// ============================================================================
//  biashara_yangu — EDGE FUNCTION « serdipay »
//
//  Passerelle de paiement SerdiPay (RDC) : Orange Money, Airtel Money,
//  M-Pesa, Afrimoney, carte bancaire.
//
//  RÔLES
//  -----
//    1) `POST /initier`  (JWT utilisateur)  → ouvre un paiement et renvoie
//       l'URL de paiement / le message USSD. Le MONTANT est calculé par la
//       base (`rpc_serdipay_ouvrir`) : il n'est JAMAIS fourni par l'app.
//    2) `POST /webhook`  (PUBLIC, signature HMAC) → SerdiPay notifie le
//       changement de statut. On vérifie la signature, le montant, puis on
//       crédite l'abonnement (`rpc_serdipay_confirmer`, idempotent).
//    3) `POST /statut`   (JWT utilisateur) → sondage de l'app (filet de
//       sécurité si le webhook n'arrive pas : on interroge aussi SerdiPay).
//    4) `GET  /ping`     (public) → diagnostic de configuration.
//
//  ⚠️ SÉCURITÉ — À NE PAS AFFAIBLIR
//  --------------------------------
//    • La clé `service_role` ne sort jamais d'ici.
//    • Le webhook REFUSE tout appel non signé (503 si le secret n'est pas
//      défini, 401 si la signature est absente ou fausse). Sans ce contrôle,
//      n'importe qui pourrait s'offrir un abonnement.
//    • Le montant annoncé par le fournisseur est comparé au montant attendu
//      EN BASE ; un écart > 0,01 met le paiement en `echoue`.
//    • Toute confirmation est idempotente (un webhook rejoué ne crédite pas
//      deux fois).
//
//  ⚠️ DÉPLOIEMENT
//  --------------
//   1. SQL d'abord : `supabase/migrations/20260916000079_passerelle_serdipay.sql`
//      (tables + RPC). Rien ne fonctionne sans elle.
//   2. Dashboard → Edge Functions → `serdipay` → coller ce fichier → Deploy
//      (ou `npx supabase functions deploy serdipay --project-ref <ref>`).
//   3. ⚠️ DÉSACTIVER « Verify JWT » sur cette fonction : le webhook arrive
//      SANS JWT. Les routes privées vérifient elles-mêmes le jeton.
//      (équivalent CLI : `--no-verify-jwt`)
//   4. Secrets à créer (Project Settings → Edge Functions → Secrets) :
//        SERDIPAY_BASE_URL        ex. https://api.serdipay.com   (OBLIGATOIRE)
//        SERDIPAY_API_KEY         clé d'API, OU
//        SERDIPAY_CLIENT_ID       + SERDIPAY_CLIENT_SECRET (OAuth 2.0)
//        SERDIPAY_WEBHOOK_SECRET  secret partagé de signature (OBLIGATOIRE)
//      Optionnels : SERDIPAY_PATH_INITIER, SERDIPAY_PATH_STATUT,
//      SERDIPAY_TOKEN_URL, SERDIPAY_RETURN_URL, SERDIPAY_DEVISE.
//
//  ⚠️ ADAPTATEUR — LE SEUL ENDROIT À MODIFIER quand SerdiPay vous remettra sa
//     documentation : `construireCorpsInitier`, `extraireUrlPaiement`,
//     `extraireReferenceFournisseur`, `extraireWebhook` (section 4).
// ============================================================================

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

// ---------------------------------------------------------------------------
// 1. ENVIRONNEMENT
// ---------------------------------------------------------------------------

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

const FONCTION = 'serdipay';

const SERDIPAY_BASE_URL = (Deno.env.get('SERDIPAY_BASE_URL') ?? '')
  .trim()
  .replace(/\/+$/, '');
const SERDIPAY_API_KEY = (Deno.env.get('SERDIPAY_API_KEY') ?? '').trim();
const SERDIPAY_CLIENT_ID = (Deno.env.get('SERDIPAY_CLIENT_ID') ?? '').trim();
const SERDIPAY_CLIENT_SECRET = (Deno.env.get('SERDIPAY_CLIENT_SECRET') ?? '')
  .trim();
const SERDIPAY_WEBHOOK_SECRET = (Deno.env.get('SERDIPAY_WEBHOOK_SECRET') ?? '')
  .trim();

// 🔒 RELAIS À IP FIXE (tools/relais_serdipay).
// Si SERDIPAY_BASE_URL pointe vers notre relais (ex. https://serdipay.domaine.cd/api),
// ce jeton prouve au relais que l'appel vient bien de NOUS : sans lui, le
// relais refuserait de transmettre et ne pourrait pas servir de proxy ouvert
// vers l'API SerdiPay. Vide = aucun en-tête envoyé (appel direct à SerdiPay).
const SERDIPAY_RELAIS_TOKEN = (Deno.env.get('SERDIPAY_RELAIS_TOKEN') ?? '')
  .trim();

const SERDIPAY_PATH_INITIER = Deno.env.get('SERDIPAY_PATH_INITIER') ??
  '/api/v1/payments';
const SERDIPAY_PATH_STATUT = Deno.env.get('SERDIPAY_PATH_STATUT') ??
  '/api/v1/payments/{reference}';
const SERDIPAY_TOKEN_URL = Deno.env.get('SERDIPAY_TOKEN_URL') ?? '';
const SERDIPAY_RETURN_URL = Deno.env.get('SERDIPAY_RETURN_URL') ??
  'https://andre-luk.github.io/biasharayanguApp/';
const SERDIPAY_DEVISE = Deno.env.get('SERDIPAY_DEVISE') ?? 'CDF';

const DELAI_FOURNISSEUR_MS = 20_000;

const CORS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

// ---------------------------------------------------------------------------
// 2. RÉPONSES ET OUTILS
// ---------------------------------------------------------------------------

function json(corps: unknown, statut = 200): Response {
  return new Response(JSON.stringify(corps), {
    status: statut,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function erreur(code: string, message: string, statut = 400): Response {
  return json({ erreur: code, message }, statut);
}

function clientService(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Client portant le JWT de l'appelant (RLS + auth.uid() respectés). */
function clientUtilisateur(jwt: string): SupabaseClient {
  return createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Chemin utile, sans le préfixe de la fonction. Ex. « /initier ». */
function cheminUtile(url: URL): string {
  let p = url.pathname;
  for (const m of [`/functions/v1/${FONCTION}`, `/${FONCTION}`]) {
    if (p.startsWith(m)) {
      p = p.slice(m.length);
      break;
    }
  }
  if (p === '') p = '/';
  if (p.length > 1 && p.endsWith('/')) p = p.slice(0, -1);
  return p;
}

/** Extrait le texte lisible d'un message « CODE|texte ». */
function messageLisible(brut: string): string {
  const i = brut.indexOf('|');
  return i >= 0 && i < brut.length - 1 ? brut.slice(i + 1).trim() : brut;
}

/** Convertit une erreur PostgREST/Supabase en message français. */
function traduireErreurBase(brut: string): { code: string; message: string } {
  const texte = messageLisible(brut ?? '');
  const table: Record<string, string> = {
    SESSION_ABSENTE:
      'Session expirée : reconnectez-vous pour payer.',
    ENTREPRISE_INTROUVABLE:
      "Aucune entreprise rattachée à ce compte : impossible d'ouvrir un paiement.",
    ENTREPRISE_REFUSEE:
      "Vous n'avez pas accès à cette entreprise.",
    TELEPHONE_INVALIDE:
      'Numéro de téléphone invalide : indiquez au moins 9 chiffres.',
    OBJET_REQUIS:
      'Précisez la facture à régler.',
    OBJET_INVALIDE:
      'Type de paiement non pris en charge.',
    FACTURE_INTROUVABLE:
      'Cette facture est introuvable ou ne concerne pas votre entreprise.',
    SOLDE_NUL:
      'Aucun montant à payer : votre abonnement est déjà réglé.',
    REFERENCE_INCONNUE:
      "Référence de paiement inconnue.",
    STATUT_INVALIDE:
      'Statut de paiement invalide.',
    MONTANT_INCORRECT:
      'Le montant reçu ne correspond pas au montant attendu : paiement refusé.',
    ACTEUR_FINANCE_INTROUVABLE:
      'Aucun compte Finance de la plateforme : contactez le support.',
    ACCES_REFUSE:
      "Vous n'avez pas accès à ce paiement.",
  };

  for (const [code, msg] of Object.entries(table)) {
    if (texte.includes(code)) return { code, message: msg };
  }

  return { code: 'ERREUR_BASE', message: texte || 'Erreur de base de données.' };
}

// ---------------------------------------------------------------------------
// 3. CLIENT SERDIPAY
// ---------------------------------------------------------------------------

type Jeton = { valeur: string; expireLe: number };
let jetonEnCache: Jeton | null = null;

function serdipayConfigure(): boolean {
  return (
    SERDIPAY_BASE_URL.length > 0 &&
    (SERDIPAY_API_KEY.length > 0 ||
      (SERDIPAY_CLIENT_ID.length > 0 && SERDIPAY_CLIENT_SECRET.length > 0))
  );
}

/**
 * Jeton d'accès SerdiPay.
 *  - OAuth 2.0 « client_credentials » si un client id/secret est fourni
 *    (mode annoncé par SerdiPay) ;
 *  - sinon, la clé d'API est utilisée directement en Bearer.
 */
async function jetonSerdipay(): Promise<string> {
  if (SERDIPAY_API_KEY && !SERDIPAY_CLIENT_ID) return SERDIPAY_API_KEY;

  if (jetonEnCache && jetonEnCache.expireLe > Date.now() + 30_000) {
    return jetonEnCache.valeur;
  }

  const url = SERDIPAY_TOKEN_URL ||
    `${SERDIPAY_BASE_URL}/oauth/token`;

  const reponse = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Accept: 'application/json',
      ...(SERDIPAY_RELAIS_TOKEN
        ? { 'x-relais-token': SERDIPAY_RELAIS_TOKEN }
        : {}),
    },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: SERDIPAY_CLIENT_ID,
      client_secret: SERDIPAY_CLIENT_SECRET,
    }),
    signal: AbortSignal.timeout(DELAI_FOURNISSEUR_MS),
  });

  const texte = await reponse.text();
  if (!reponse.ok) {
    throw new Error(
      `SERDIPAY_AUTH_${reponse.status} : ${texte.slice(0, 300)}`,
    );
  }

  let data: Record<string, unknown> = {};
  try {
    data = JSON.parse(texte) as Record<string, unknown>;
  } catch {
    throw new Error('SERDIPAY_AUTH_REPONSE_INVALIDE');
  }

  const jeton = String(
    data.access_token ?? data.token ?? data.accessToken ?? '',
  );
  if (!jeton) throw new Error('SERDIPAY_AUTH_SANS_JETON');

  const duree = Number(data.expires_in ?? data.expiresIn ?? 3600);
  jetonEnCache = {
    valeur: jeton,
    expireLe: Date.now() + (Number.isFinite(duree) ? duree : 3600) * 1000,
  };

  return jeton;
}

async function appelFournisseur(
  chemin: string,
  methode: 'GET' | 'POST',
  corps?: unknown,
): Promise<{ ok: boolean; statutHttp: number; texte: string; data: unknown }> {
  const jeton = await jetonSerdipay();

  const reponse = await fetch(`${SERDIPAY_BASE_URL}${chemin}`, {
    method: methode,
    headers: {
      Authorization: `Bearer ${jeton}`,
      Accept: 'application/json',
      ...(SERDIPAY_RELAIS_TOKEN
        ? { 'x-relais-token': SERDIPAY_RELAIS_TOKEN }
        : {}),
      ...(corps ? { 'Content-Type': 'application/json' } : {}),
    },
    body: corps ? JSON.stringify(corps) : undefined,
    signal: AbortSignal.timeout(DELAI_FOURNISSEUR_MS),
  });

  const texte = await reponse.text();
  let data: unknown = null;
  try {
    data = texte ? JSON.parse(texte) : null;
  } catch {
    data = null;
  }

  return { ok: reponse.ok, statutHttp: reponse.status, texte, data };
}

// ---------------------------------------------------------------------------
// 4. ADAPTATEUR SERDIPAY  ⚠️ SEULE SECTION À AJUSTER
// ---------------------------------------------------------------------------
//  La documentation publique de SerdiPay n'est pas accessible au moment de
//  l'écriture : les noms de champs ci-dessous sont donc TOLÉRANTS (plusieurs
//  variantes acceptées) et regroupés ici. Quand SerdiPay vous remettra sa
//  doc, il suffit de corriger CES QUATRE FONCTIONS — rien d'autre.
// ---------------------------------------------------------------------------

type PaiementOuvert = {
  reference: string;
  entreprise_id: string;
  montant: number;
  devise: string;
  telephone: string | null;
  operateur: string | null;
};

function construireCorpsInitier(
  p: PaiementOuvert,
  nomClient: string,
  emailClient: string,
): Record<string, unknown> {
  const callback = `${SUPABASE_URL}/functions/v1/${FONCTION}/webhook`;
  const description = `Abonnement Biashara Yangu - ${p.reference}`;

  return {
    reference: p.reference,
    amount: Number(p.montant),
    currency: p.devise || SERDIPAY_DEVISE,
    description,
    customer: {
      name: nomClient || 'Client Biashara Yangu',
      phone: p.telephone,
      email: emailClient || undefined,
    },
    // Certains agrégateurs attendent `payment_method`, d'autres `operator`.
    payment_method: p.operateur ?? undefined,
    operator: p.operateur ?? undefined,
    callback_url: callback,
    return_url: SERDIPAY_RETURN_URL,
    metadata: { reference_interne: p.reference },
  };
}

function extraireUrlPaiement(data: unknown): string | null {
  const d = (data ?? {}) as Record<string, unknown>;
  const sous = (d.data ?? d.payment ?? d.transaction ?? {}) as Record<
    string,
    unknown
  >;

  const candidats = [
    d.payment_url,
    d.paymentUrl,
    d.checkout_url,
    d.checkoutUrl,
    d.redirect_url,
    d.redirectUrl,
    d.url,
    sous.payment_url,
    sous.paymentUrl,
    sous.checkout_url,
    sous.redirect_url,
    sous.url,
  ];

  for (const c of candidats) {
    if (typeof c === 'string' && c.startsWith('http')) return c;
  }
  return null;
}

function extraireReferenceFournisseur(data: unknown): string | null {
  const d = (data ?? {}) as Record<string, unknown>;
  const sous = (d.data ?? d.payment ?? d.transaction ?? {}) as Record<
    string,
    unknown
  >;

  const candidats = [
    d.id,
    d.transaction_id,
    d.transactionId,
    d.provider_reference,
    d.providerReference,
    d.reference,
    sous.id,
    sous.transaction_id,
    sous.reference,
  ];

  for (const c of candidats) {
    if (typeof c === 'string' && c.trim().length > 0) return c.trim();
    if (typeof c === 'number') return String(c);
  }
  return null;
}

const STATUTS_PAYES = new Set([
  'success',
  'successful',
  'succeeded',
  'paid',
  'paye',
  'payé',
  'paiement_reussi',
  'completed',
  'complete',
  'approved',
  'confirmed',
  'confirme',
  'ok',
  'done',
  '1',
  'true',
]);

const STATUTS_ECHEC = new Set([
  'failed',
  'failure',
  'echec',
  'échec',
  'cancelled',
  'canceled',
  'annule',
  'annulé',
  'expired',
  'expire',
  'expiré',
  'rejected',
  'refused',
  'declined',
  'error',
  '0',
  'false',
]);

function normaliserStatut(brut: unknown): string {
  return String(brut ?? '').trim().toLowerCase();
}

/** Extrait les informations utiles d'un webhook SerdiPay. */
function extraireWebhook(payload: unknown): {
  reference: string | null;
  providerReference: string | null;
  montant: number | null;
  statut: 'paye' | 'echoue' | 'annule' | 'expire' | null;
} {
  const racine = (payload ?? {}) as Record<string, unknown>;
  const d = (racine.data ?? racine.transaction ?? racine.payment ??
    racine) as Record<string, unknown>;

  const texte = (v: unknown): string | null =>
    typeof v === 'string' && v.trim().length > 0
      ? v.trim()
      : typeof v === 'number'
      ? String(v)
      : null;

  const reference = texte(
    d.reference ?? d.external_reference ?? d.merchant_reference ??
      d.order_reference ?? racine.reference ?? d.reference_interne,
  );

  const providerReference = texte(
    d.transaction_id ?? d.transactionId ?? d.id ?? d.txid ??
      d.provider_reference ?? racine.transaction_id,
  );

  const montantBrut = d.amount ?? d.montant ?? d.montant_recu ??
    d.paid_amount ?? d.total ?? racine.amount;
  const montant = montantBrut === undefined || montantBrut === null
    ? null
    : Number(montantBrut);

  const statutBrut = normaliserStatut(
    d.status ?? d.statut ?? d.state ?? racine.status ?? racine.statut ??
      racine.event ?? racine.event_type ?? racine.type,
  );

  let statut: 'paye' | 'echoue' | 'annule' | 'expire' | null = null;

  if (STATUTS_PAYES.has(statutBrut) || statutBrut.includes('success') ||
    statutBrut.includes('paid')) {
    statut = 'paye';
  } else if (statutBrut.includes('cancel') || statutBrut.includes('annul')) {
    statut = 'annule';
  } else if (statutBrut.includes('expir')) {
    statut = 'expire';
  } else if (
    STATUTS_ECHEC.has(statutBrut) || statutBrut.includes('fail') ||
    statutBrut.includes('echec') || statutBrut.includes('échec') ||
    statutBrut.includes('reject') || statutBrut.includes('refus')
  ) {
    statut = 'echoue';
  }

  return {
    reference,
    providerReference,
    montant: Number.isFinite(montant as number) ? montant : null,
    statut,
  };
}

// ---------------------------------------------------------------------------
// 5. SIGNATURE DU WEBHOOK
// ---------------------------------------------------------------------------

/** HMAC-SHA256 du corps BRUT (jamais du JSON re-sérialisé). */
async function hmac(secret: string, corps: string): Promise<{
  hex: string;
  base64: string;
}> {
  const cle = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'HMAC',
    cle,
    new TextEncoder().encode(corps),
  );

  const octets = new Uint8Array(signature);

  const hex = Array.from(octets)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  const base64 = btoa(String.fromCharCode(...octets));

  return { hex, base64 };
}

function egalConstant(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function nettoyerSignature(brut: string): string {
  return brut
    .trim()
    .replace(/^["']|["']$/g, '')
    .replace(/^sha256=/i, '')
    .replace(/\s+/g, '')
    .toLowerCase();
}

/**
 * Vérifie la signature.
 * Accepte, dans cet ordre :
 *   1. un HMAC-SHA256 du corps (hex ou base64) dans l'en-tête de signature ;
 *   2. un simple jeton partagé dans un EN-TÊTE (`x-serdipay-token` /
 *      `x-webhook-token`) — certains agrégateurs n'implémentent que ça.
 *
 * ⚠️ PAS de secret en paramètre d'URL (`?token=…`) : les URL finissent dans
 *    les journaux des proxys, des CDN et des navigateurs. Un secret dans une
 *    query string est un secret divulgué. Volontairement NON supporté.
 */
async function signatureValide(
  req: Request,
  corps: string,
): Promise<boolean> {
  const enTetes = [
    Deno.env.get('SERDIPAY_SIGNATURE_HEADER') ?? 'x-serdipay-signature',
    'x-serdipay-signature',
    'x-signature',
    'x-webhook-signature',
  ];

  const { hex, base64 } = await hmac(SERDIPAY_WEBHOOK_SECRET, corps);

  for (const nom of enTetes) {
    const valeur = req.headers.get(nom);
    if (!valeur) continue;

    const propre = nettoyerSignature(valeur);
    if (
      egalConstant(propre, hex) || egalConstant(propre, base64.toLowerCase())
    ) {
      return true;
    }
  }

  const jetons = [
    req.headers.get('x-serdipay-token'),
    req.headers.get('x-webhook-token'),
  ];

  for (const jeton of jetons) {
    if (jeton && egalConstant(jeton.trim(), SERDIPAY_WEBHOOK_SECRET)) {
      return true;
    }
  }

  return false;
}

// ---------------------------------------------------------------------------
// 6. AUTHENTIFICATION DES ROUTES PRIVÉES
// ---------------------------------------------------------------------------

type Contexte = { client: SupabaseClient; userId: string; jwt: string };

function jetonPorteur(req: Request): string | null {
  const brut = req.headers.get('Authorization') ?? req.headers.get('authorization');
  if (!brut) return null;
  const m = brut.match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : null;
}

async function exigerUtilisateur(req: Request): Promise<Contexte | Response> {
  const jwt = jetonPorteur(req);
  if (!jwt) {
    return erreur(
      'SESSION_ABSENTE',
      'Connectez-vous pour effectuer un paiement.',
      401,
    );
  }

  const client = clientUtilisateur(jwt);

  try {
    const { data, error } = await client.auth.getUser();
    if (error || !data.user) {
      return erreur('SESSION_ABSENTE', 'Session expirée : reconnectez-vous.', 401);
    }
    return { client, userId: data.user.id, jwt };
  } catch {
    return erreur('SESSION_ABSENTE', 'Session expirée : reconnectez-vous.', 401);
  }
}

/** Nom + téléphone du client (best-effort, pour le reçu SerdiPay). */
async function identiteClient(
  client: SupabaseClient,
  userId: string,
): Promise<{ nom: string; email: string }> {
  let nom = '';
  let email = '';

  try {
    const { data } = await client
      .from('utilisateurs')
      .select('nom, telephone')
      .eq('id', userId)
      .maybeSingle();

    nom = String((data as Record<string, unknown> | null)?.nom ?? '');
  } catch {
    // best-effort
  }

  try {
    const { data } = await client.auth.getUser();
    email = data.user?.email ?? '';
    if (!nom) {
      nom = String(
        (data.user?.user_metadata as Record<string, unknown> | undefined)?.nom ??
          '',
      );
    }
  } catch {
    // best-effort
  }

  return { nom, email };
}

// ---------------------------------------------------------------------------
// 7. ROUTES
// ---------------------------------------------------------------------------

function routePing(): Response {
  return json({
    ok: true,
    service: FONCTION,
    fournisseurConfigure: serdipayConfigure(),
    signatureConfiguree: SERDIPAY_WEBHOOK_SECRET.length > 0,
    baseUrlDefinie: SERDIPAY_BASE_URL.length > 0,
    devise: SERDIPAY_DEVISE,
    webhook: `${SUPABASE_URL}/functions/v1/${FONCTION}/webhook`,
  });
}

/** POST /initier — ouvre un paiement et renvoie le lien / l'instruction USSD. */
async function routeInitier(req: Request): Promise<Response> {
  const ctx = await exigerUtilisateur(req);
  if (ctx instanceof Response) return ctx;

  if (!serdipayConfigure()) {
    return erreur(
      'SERDIPAY_NON_CONFIGURE',
      "Le paiement en ligne n'est pas encore configuré : " +
        'renseignez SERDIPAY_BASE_URL et SERDIPAY_API_KEY (ou ' +
        'SERDIPAY_CLIENT_ID / SERDIPAY_CLIENT_SECRET) dans les secrets ' +
        'Supabase, puis redéployez la fonction « serdipay ».',
      503,
    );
  }

  let corps: Record<string, unknown>;
  try {
    corps = (await req.json()) as Record<string, unknown>;
  } catch {
    return erreur('CORPS_INVALIDE', 'Corps JSON attendu.', 400);
  }

  const objet = String(corps.objet ?? 'abonnement').trim().toLowerCase();
  if (!['abonnement', 'facture'].includes(objet)) {
    return erreur('OBJET_INVALIDE', 'Type de paiement non pris en charge.', 400);
  }

  const objetId = corps.objetId ?? corps.objet_id ?? null;
  const telephone = String(corps.telephone ?? '').trim();
  const operateur = String(corps.operateur ?? '').trim().toLowerCase();
  const entrepriseId = corps.entrepriseId ?? corps.entreprise_id ?? null;

  if (telephone.length < 9) {
    return erreur(
      'TELEPHONE_INVALIDE',
      'Indiquez le numéro Mobile Money (au moins 9 chiffres).',
      400,
    );
  }

  // 1) Ouvrir le paiement EN BASE (le montant est calculé là-bas).
  const { data: ouvert, error: erreurOuverture } = await ctx.client.rpc(
    'rpc_serdipay_ouvrir',
    {
      p_objet: objet,
      p_objet_id: objetId,
      p_telephone: telephone,
      p_operateur: operateur || null,
      p_entreprise_id: entrepriseId,
    },
  );

  if (erreurOuverture) {
    const t = traduireErreurBase(erreurOuverture.message ?? '');
    const statutHttp = t.code === 'SESSION_ABSENTE' ? 401 : 400;
    return erreur(t.code, t.message, statutHttp);
  }

  const paiement = ouvert as PaiementOuvert;

  let nom = '';
  let email = '';
  try {
    const id = await identiteClient(ctx.client, ctx.userId);
    nom = id.nom;
    email = id.email;
  } catch {
    // best-effort
  }

  // 2) Créer la transaction chez SerdiPay.
  let reponse: Awaited<ReturnType<typeof appelFournisseur>>;
  try {
    reponse = await appelFournisseur(
      SERDIPAY_PATH_INITIER,
      'POST',
      construireCorpsInitier(paiement, nom, email),
    );
  } catch (e) {
    await clientService().rpc('rpc_serdipay_echec', {
      p_reference: paiement.reference,
      p_motif: `RESEAU_FOURNISSEUR : ${String(e).slice(0, 300)}`,
    });

    return erreur(
      'FOURNISSEUR_INJOIGNABLE',
      "Impossible de joindre SerdiPay pour le moment. Réessayez dans " +
        'quelques instants.',
      502,
    );
  }

  if (!reponse.ok) {
    await clientService().rpc('rpc_serdipay_echec', {
      p_reference: paiement.reference,
      p_motif: `HTTP_${reponse.statutHttp} : ${reponse.texte.slice(0, 400)}`,
    });

    return erreur(
      'PAIEMENT_REFUSE_FOURNISSEUR',
      `SerdiPay a refusé la demande (HTTP ${reponse.statutHttp}). ` +
        'Vérifiez le numéro et le moyen de paiement, puis réessayez.',
      502,
    );
  }

  const urlPaiement = extraireUrlPaiement(reponse.data);
  const referenceFournisseur = extraireReferenceFournisseur(reponse.data);

  // 3) Mémoriser le lien (le fournisseur peut répondre sans URL : USSD).
  const { data: lien } = await clientService().rpc('rpc_serdipay_definir_lien', {
    p_reference: paiement.reference,
    p_url_paiement: urlPaiement,
    p_provider_reference: referenceFournisseur,
    p_payload: reponse.data,
  });

  return json({
    ok: true,
    paiement: {
      reference: paiement.reference,
      montant: paiement.montant,
      devise: paiement.devise,
      statut: 'en_attente',
      url_paiement: urlPaiement ?? (lien as Record<string, unknown>)?.url_paiement ?? null,
      provider_reference: referenceFournisseur,
      message: urlPaiement
        ? 'Ouvrez la page de paiement SerdiPay pour valider la transaction.'
        : 'Validez la demande reçue sur votre téléphone (USSD / notification ' +
          'Mobile Money).',
    },
  });
}

/** POST /statut — sondage ; interroge SerdiPay en secours si webhook absent. */
async function routeStatut(req: Request): Promise<Response> {
  const ctx = await exigerUtilisateur(req);
  if (ctx instanceof Response) return ctx;

  let corps: Record<string, unknown>;
  try {
    corps = (await req.json()) as Record<string, unknown>;
  } catch {
    return erreur('CORPS_INVALIDE', 'Corps JSON attendu.', 400);
  }

  const reference = String(corps.reference ?? '').trim();
  if (!reference) {
    return erreur('REFERENCE_REQUISE', 'Référence de paiement manquante.', 400);
  }

  const { data, error } = await ctx.client.rpc('rpc_serdipay_statut', {
    p_reference: reference,
  });

  if (error) {
    const t = traduireErreurBase(error.message ?? '');
    return erreur(t.code, t.message, t.code === 'ACCES_REFUSE' ? 403 : 400);
  }

  let paiement = data as Record<string, unknown>;

  // Filet de sécurité : si toujours en attente et fournisseur configuré,
  // on demande directement l'état à SerdiPay (webhook perdu, réseau…).
  if (paiement.statut === 'en_attente' && serdipayConfigure()) {
    try {
      const chemin = SERDIPAY_PATH_STATUT.replace(
        '{reference}',
        encodeURIComponent(reference),
      );
      const reponse = await appelFournisseur(chemin, 'GET');

      if (reponse.ok) {
        const infos = extraireWebhook(reponse.data);
        if (infos.statut && infos.reference === null) {
          // Le fournisseur ne renvoie pas notre référence : on la force.
          infos.reference = reference;
        }

        if (infos.statut) {
          const { data: confirme } = await clientService().rpc(
            'rpc_serdipay_confirmer',
            {
              p_reference: reference,
              p_statut: infos.statut,
              p_provider_reference: infos.providerReference,
              p_montant_recu: infos.montant,
              p_payload: reponse.data,
            },
          );

          if (confirme) {
            const { data: relu } = await ctx.client.rpc('rpc_serdipay_statut', {
              p_reference: reference,
            });
            if (relu) paiement = relu as Record<string, unknown>;
          }
        }
      }
    } catch {
      // Silencieux : le webhook reste la source de vérité.
    }
  }

  return json({ ok: true, paiement });
}

/** POST /webhook — notification SerdiPay (PUBLIC, signé). */
async function routeWebhook(req: Request): Promise<Response> {
  if (!SERDIPAY_WEBHOOK_SECRET) {
    return erreur(
      'WEBHOOK_NON_CONFIGURE',
      'Secret de signature absent : définissez SERDIPAY_WEBHOOK_SECRET.',
      503,
    );
  }

  // Corps BRUT obligatoire pour le HMAC.
  const brut = await req.text();

  if (!(await signatureValide(req, brut))) {
    return erreur(
      'SIGNATURE_INVALIDE',
      "Signature du webhook absente ou incorrecte : appel refusé.",
      401,
    );
  }

  let payload: unknown;
  try {
    payload = JSON.parse(brut);
  } catch {
    return erreur('CORPS_INVALIDE', 'Corps JSON invalide.', 400);
  }

  const infos = extraireWebhook(payload);

  if (!infos.reference) {
    // On répond 200 pour ne pas déclencher de tempête de réessais.
    return json({
      ok: true,
      ignore: true,
      motif: 'Référence interne absente du webhook.',
    });
  }

  if (!infos.statut) {
    return json({
      ok: true,
      ignore: true,
      motif: 'Statut non reconnu : aucun crédit effectué.',
    });
  }

  const { data, error } = await clientService().rpc('rpc_serdipay_confirmer', {
    p_reference: infos.reference,
    p_statut: infos.statut,
    p_provider_reference: infos.providerReference,
    p_montant_recu: infos.montant,
    p_payload: payload,
  });

  if (error) {
    const t = traduireErreurBase(error.message ?? '');

    // Référence inconnue : on acquitte (ce n'est pas notre trafic).
    if (t.code === 'REFERENCE_INCONNUE') {
      return json({ ok: true, ignore: true, motif: 'Référence inconnue.' });
    }

    // MONTANT_INCORRECT : le paiement est déjà passé en `echoue` en base.
    if (t.code === 'MONTANT_INCORRECT') {
      return erreur(t.code, t.message, 422);
    }

    // Toute autre erreur : 500 pour que le fournisseur REJOUE.
    return erreur(t.code, t.message, 500);
  }

  return json({ ok: true, resultat: data });
}

// ---------------------------------------------------------------------------
// 8. POINT D'ENTRÉE
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS });
  }

  const url = new URL(req.url);
  const chemin = cheminUtile(url);

  try {
    if (chemin === '/' || chemin === '/ping') {
      return routePing();
    }

    if (chemin === '/webhook') {
      // GET = vérification d'URL par le fournisseur (certains le font).
      if (req.method === 'GET') {
        return json({ ok: true, service: FONCTION, webhook: 'actif' });
      }
      if (req.method === 'POST') return await routeWebhook(req);
      return erreur('METHODE_REFUSEE', 'Utilisez POST.', 405);
    }

    if (chemin === '/initier') {
      if (req.method !== 'POST') {
        return erreur('METHODE_REFUSEE', 'Utilisez POST.', 405);
      }
      return await routeInitier(req);
    }

    if (chemin === '/statut') {
      if (req.method !== 'POST') {
        return erreur('METHODE_REFUSEE', 'Utilisez POST.', 405);
      }
      return await routeStatut(req);
    }

    return erreur(
      'ROUTE_INCONNUE',
      `Route inconnue « ${chemin} ». Attendu : /ping, /initier, /statut, /webhook.`,
      404,
    );
  } catch (e) {
    console.error('[serdipay] erreur non gérée :', e);
    return erreur(
      'ERREUR_INTERNE',
      'Erreur interne de la passerelle de paiement.',
      500,
    );
  }
});
