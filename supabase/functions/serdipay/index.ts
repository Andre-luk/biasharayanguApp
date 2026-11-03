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
//        SERDIPAY_EMAIL           e-mail du compte app.serdipay.com  (OBLIGATOIRE)
//        SERDIPAY_PASSWORD        mot de passe de ce compte          (OBLIGATOIRE)
//        SERDIPAY_WEBHOOK_SECRET  secret partagé de signature       (OBLIGATOIRE)
//      Optionnels : SERDIPAY_BASE_URL, SERDIPAY_PATH_TOKEN,
//      SERDIPAY_PATH_INITIER, SERDIPAY_PATH_STATUT, SERDIPAY_AUTH_CORPS,
//      SERDIPAY_CORPS_INITIER, SERDIPAY_TOKEN_URL, SERDIPAY_RETURN_URL,
//      SERDIPAY_DEVISE.
//
//  🧪 DIAGNOSTIC (protégé par l’en-tête `x-relais-token`)
//        POST /diag-token     → essaie plusieurs corps pour obtenir un jeton
//        POST /diag-paiement  → appelle payment-merchant avec {} pour faire
//                               lister par SerdiPay les champs obligatoires
//
//  🔌 ROUTES RÉELLES DE SERDIPAY (communiquées le 30/10/2026)
//  ------------------------------------------------------------
//    PRODUCTION  https://public-apis.services.serdipay.com
//      POST /api/public-api/v1/merchant/get-token
//      POST /api/public-api/v1/merchant/payment-merchant     (C2B, encaissement)
//      POST /api/public-api/v1/merchant/payment-client       (B2C, décaissement)
//    MISE EN SCÈNE  https://apis.serdipay.cloud  (mêmes chemins)
//  ⚠️ SerdiPay n'accepte que des IP déclarées : nos appels passent donc par le
//     relais à IP fixe (213.130.145.53) — voir tools/relais_serdipay.
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

// Adresse de l'API SerdiPay. Par défaut : notre relais à IP fixe
// (213.130.145.53), indispensable car SerdiPay n'accepte que des IP déclarées.
// Le secret SERDIPAY_BASE_URL permet de revenir à un appel direct si besoin.
const SERDIPAY_BASE_URL = (Deno.env.get('SERDIPAY_BASE_URL') ??
  'https://serdipay.biasharagroup.com/api')
  .trim()
  .replace(/\/+$/, '');
// Identifiant de compte API remis par SerdiPay (ce n'est PAS un secret, il est
// lisible dans leur courriel : « ID API: APIWY4G2W9 »).
const SERDIPAY_API_ID = (Deno.env.get('SERDIPAY_API_ID') ?? 'APIWY4G2W9')
  .trim();
const SERDIPAY_API_KEY = (Deno.env.get('SERDIPAY_API_KEY') ?? '').trim();
const SERDIPAY_CLIENT_ID = (Deno.env.get('SERDIPAY_CLIENT_ID') ?? '').trim();
const SERDIPAY_CLIENT_SECRET = (Deno.env.get('SERDIPAY_CLIENT_SECRET') ?? '')
  .trim();
const SERDIPAY_WEBHOOK_SECRET = (Deno.env.get('SERDIPAY_WEBHOOK_SECRET') ?? '')
  .trim();

// Identifiants du compte MARCHAND remis le 30/10/2026 (espace
// https://app.serdipay.com). Le code marchand n'est pas secret ; l'identifiant,
// le mot de passe et le PIN le sont → ils ne vivent que dans les secrets
// Supabase, jamais dans le code.
const SERDIPAY_MERCHANT_CODE = (Deno.env.get('SERDIPAY_MERCHANT_CODE') ??
  '066036').trim();
const SERDIPAY_USERNAME = (Deno.env.get('SERDIPAY_USERNAME') ?? '').trim();
const SERDIPAY_PASSWORD = (Deno.env.get('SERDIPAY_PASSWORD') ?? '').trim();
// ✅ FORMAT CONFIRMÉ LE 30/10/2026 (test réel via le relais) :
//   POST /api/public-api/v1/merchant/get-token  { email, password }
//   - corps vide      → 400 « Validation Error » { email, password requis }
//   - identifiants faux → 401 « Invalid Credentials »
// L'identifiant du back-office est donc un ADRESSE E-MAIL. Le secret
// SERDIPAY_EMAIL (ou à défaut SERDIPAY_USERNAME) porte cette adresse.
const SERDIPAY_EMAIL = (Deno.env.get('SERDIPAY_EMAIL') ??
  Deno.env.get('SERDIPAY_USERNAME') ?? '').trim();
// Mot de passe d'API exigé par `/merchant/payment-merchant` (champ
// `api_password`, longueur minimale imposée par SerdiPay). À défaut du secret
// dédié, on réutilise le mot de passe du compte.
const SERDIPAY_API_PASSWORD = (Deno.env.get('SERDIPAY_API_PASSWORD') ??
  Deno.env.get('SERDIPAY_PASSWORD') ?? '').trim();
// ✅ Le PIN est OBLIGATOIRE pour payer : `merchant_pin` figure parmi les champs
// requis de `/merchant/payment-merchant` (validation.min.numeric).
const SERDIPAY_PIN = (Deno.env.get('SERDIPAY_PIN') ?? '').trim();

/**
 * Remplace les jetons `{…}` d'un modèle JSON par les valeurs connues.
 * Jetons disponibles : {apiId} {apiKey} {merchantCode} {username} {password}
 * {pin}.
 */
function remplirModele(modele: string): string {
  const valeurs: Record<string, string> = {
    apiId: SERDIPAY_API_ID,
    apiKey: SERDIPAY_API_KEY,
    apiPassword: SERDIPAY_API_PASSWORD,
    merchantCode: SERDIPAY_MERCHANT_CODE,
    email: SERDIPAY_EMAIL,
    username: SERDIPAY_USERNAME || SERDIPAY_EMAIL,
    password: SERDIPAY_PASSWORD,
    pin: SERDIPAY_PIN,
  };
  let sortie = modele;
  for (const [cle, valeur] of Object.entries(valeurs)) {
    sortie = sortie.replaceAll(`{${cle}}`, valeur.replaceAll('"', '\\"'));
  }
  return sortie;
}

// Corps envoyé à `/merchant/get-token` — format VÉRIFIÉ chez SerdiPay.
// Modèle surchargeable par le secret SERDIPAY_AUTH_CORPS au cas où.
const SERDIPAY_AUTH_CORPS = Deno.env.get('SERDIPAY_AUTH_CORPS') ??
  '{"email":"{email}","password":"{password}"}';

/** Y a-t-il de quoi demander un jeton ? */
function identifiantsFournisseur(): boolean {
  return (SERDIPAY_EMAIL.length > 0 && SERDIPAY_PASSWORD.length > 0) ||
    SERDIPAY_API_KEY.length > 0 ||
    (SERDIPAY_CLIENT_ID.length > 0 && SERDIPAY_CLIENT_SECRET.length > 0);
}
// 🔒 RELAIS À IP FIXE (tools/relais_serdipay).
// Si SERDIPAY_BASE_URL pointe vers notre relais (ex. https://serdipay.domaine.cd/api),
// ce jeton prouve au relais que l'appel vient bien de NOUS : sans lui, le
// relais refuserait de transmettre et ne pourrait pas servir de proxy ouvert
// vers l'API SerdiPay. Vide = aucun en-tête envoyé (appel direct à SerdiPay).
// Valeur par défaut = celle inscrite dans relais.php (JETON_RELAIS). Elle est
// surchargeable par le secret SERDIPAY_RELAIS_TOKEN, mais ce repli évite d'avoir
// à saisir un secret supplémentaire dans le tableau de bord Supabase.
const SERDIPAY_RELAIS_TOKEN = (Deno.env.get('SERDIPAY_RELAIS_TOKEN') ??
  '7ab3fb3dc4781754e5ec8a49a92de09dab1bd9d275ec5f9feb0f7483829cf57e')
  .trim();

// Routes annoncées par SerdiPay (préfixe `/api` du relais en moins).
const SERDIPAY_PATH_TOKEN = Deno.env.get('SERDIPAY_PATH_TOKEN') ??
  '/public-api/v1/merchant/get-token';
const SERDIPAY_PATH_INITIER = Deno.env.get('SERDIPAY_PATH_INITIER') ??
  '/public-api/v1/merchant/payment-merchant';
// SerdiPay n'a communiqué AUCUNE route d'interrogation d'un paiement : tant
// que ce chemin est vide, l'app se contente du webhook (aucun appel inutile).
// Le jour où la route est fournie : secret SERDIPAY_PATH_STATUT
// (ex. /public-api/v1/merchant/payment-merchant/{reference}).
const SERDIPAY_PATH_STATUT = Deno.env.get('SERDIPAY_PATH_STATUT') ?? '';
const SERDIPAY_TOKEN_URL = Deno.env.get('SERDIPAY_TOKEN_URL') ?? '';
// Page de retour après paiement : la version web publique (surchargée par le
// secret SERDIPAY_RETURN_URL si besoin).
const SERDIPAY_RETURN_URL = Deno.env.get('SERDIPAY_RETURN_URL') ??
  'https://biashara-yangu-app.netlify.app/';
const SERDIPAY_DEVISE = Deno.env.get('SERDIPAY_DEVISE') ?? 'CDF';

// 💰 BARÈME SERDIPAY (réponse réelle de leur API le 03/11/2026) :
//   « The amount is not within allowed range! min: 2300 - max : 5750000 CDF »
// En dessous/en dessus, la transaction est refusée (HTTP 402) avec un message
// technique. On l'intercepte pour expliquer clairement au commerçant.
const SERDIPAY_MONTANT_MIN = Number(
  Deno.env.get('SERDIPAY_MONTANT_MIN') ?? 2300,
);
const SERDIPAY_MONTANT_MAX = Number(
  Deno.env.get('SERDIPAY_MONTANT_MAX') ?? 5_750_000,
);

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
      "Rien à payer pour le moment : votre abonnement est déjà réglé. " +
      'Si votre abonnement est échu, ouvrez « Mon abonnement » puis ' +
      '« Renouveler maintenant » pour obtenir le montant du mois.',
    PREMIER_CYCLE:
      "Ce compte n'a pas encore été activé : le prix d'installation est dû. " +
      'Le montant apparaît dans « Mon abonnement ».',
    PRIX_ABSENT:
      "Aucun prix n'est défini pour ce compte : contactez la plateforme.",
    CONFIRMATION_REQUISE: 'Confirmation manquante.',
    MONTANT_SUPERIEUR:
      'Le montant dépasse ce que vous devez : corrigez la somme.',
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
  return SERDIPAY_BASE_URL.length > 0 &&
    SERDIPAY_API_ID.length > 0 &&
    identifiantsFournisseur();
}

/** « This domain or IP (…) is not whitelisted » → message actionnable. */
function estIpNonAutorisee(texte: string): boolean {
  return /not\s*whitelist/i.test(texte) || /non\s*autoris/i.test(texte);
}

/**
 * Jeton d'accès SerdiPay (`POST /merchant/get-token`).
 *  - par défaut : corps JSON `{ email, password }` (format VÉRIFIÉ) ;
 *  - si seuls CLIENT_ID / CLIENT_SECRET sont fournis : OAuth
 *    « client_credentials » en formulaire ;
 *  - si SerdiPay répond que la route n'existe pas, on retombe sur l'usage de la
 *    clé d'API directement en Bearer (ancien mode).
 * Le jeton est gardé en mémoire de l'instance (durée annoncée, 1 h par défaut).
 */
async function jetonSerdipay(): Promise<Jeton> {
  // ⚠️ Le jeton SerdiPay semble à USAGE UNIQUE (ou très court) : un 401
  // « Unauthenticated. » apparaît si on le réutilise. On ne le garde donc que
  // quelques secondes, et `appelFournisseur` en redemande un sur 401.
  if (jetonEnCache && jetonEnCache.expireLe > Date.now() + 2_000) {
    return jetonEnCache;
  }

  const url = SERDIPAY_TOKEN_URL ||
    `${SERDIPAY_BASE_URL}${SERDIPAY_PATH_TOKEN}`;

  let corps: string;
  let typeContenu: string;

  if (SERDIPAY_API_KEY.length === 0 && SERDIPAY_CLIENT_ID.length > 0) {
    typeContenu = 'application/x-www-form-urlencoded';
    corps = new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: SERDIPAY_CLIENT_ID,
      client_secret: SERDIPAY_CLIENT_SECRET,
    }).toString();
  } else {
    typeContenu = 'application/json';
    corps = remplirModele(SERDIPAY_AUTH_CORPS);
  }

  const reponse = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': typeContenu,
      Accept: 'application/json',
      ...(SERDIPAY_RELAIS_TOKEN
        ? { 'x-relais-token': SERDIPAY_RELAIS_TOKEN }
        : {}),
    },
    body: corps,
    signal: AbortSignal.timeout(DELAI_FOURNISSEUR_MS),
  });

  const texte = await reponse.text();

  if (!reponse.ok) {
    if (estIpNonAutorisee(texte)) {
      throw new Error(
        'SERDIPAY_IP_NON_AUTORISEE : ' + texte.slice(0, 200),
      );
    }
    // Route de jeton absente : on tente la clé d'API en Bearer direct.
    if (
      (reponse.status === 404 || reponse.status === 405) &&
      SERDIPAY_API_KEY.length > 0
    ) {
      jetonEnCache = {
        valeur: SERDIPAY_API_KEY,
        expireLe: Date.now() + 30 * 60_000,
      };
      return jetonEnCache;
    }
    throw new Error(
      `SERDIPAY_AUTH_${reponse.status} : ${texte.slice(0, 300)}`,
    );
  }

  let data: Record<string, unknown> = {};
  try {
    data = JSON.parse(texte) as Record<string, unknown>;
    if (data && typeof data === 'object' && data.data &&
      typeof data.data === 'object') {
      data = {
        ...(data.data as Record<string, unknown>),
        ...data,
      };
    }
  } catch {
    // Certaines API renvoient le jeton en texte brut.
    const brut = texte.trim().replace(/^["']|["']$/g, '');
    if (brut.length >= 16 && !brut.includes(' ')) {
      jetonEnCache = {
        valeur: brut,
        expireLe: Date.now() + 30 * 60_000,
      };
      return jetonEnCache;
    }
    throw new Error('SERDIPAY_AUTH_REPONSE_INVALIDE');
  }

  const jeton = String(
    data.token ?? data.access_token ?? data.accessToken ?? data.jwt ?? '',
  ).trim();
  if (!jeton) throw new Error('SERDIPAY_AUTH_SANS_JETON');

  const duree = Number(data.expires_in ?? data.expiresIn ?? data.expiration ??
    3600);
  jetonEnCache = {
    valeur: jeton,
    expireLe: Date.now() + (Number.isFinite(duree) && duree > 60
      ? duree
      : 3600) * 1000,
  };

  return jetonEnCache;
}

/**
 * Appel authentifié à l'API SerdiPay, avec UNE reprise automatique :
 * si l'API répond 401 (« Unauthenticated. »), on jette le jeton en cache,
 * on en demande un neuf et on rejoue la requête une seule fois.
 */
async function appelFournisseur(
  chemin: string,
  methode: 'GET' | 'POST',
  corps?: unknown,
): Promise<{ ok: boolean; statutHttp: number; texte: string; data: unknown }> {
  let derniere: {
    ok: boolean;
    statutHttp: number;
    texte: string;
    data: unknown;
  } = { ok: false, statutHttp: 0, texte: '', data: null };

  for (let essai = 0; essai < 2; essai++) {
    const { valeur: jeton } = await jetonSerdipay();

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

    derniere = {
      ok: reponse.ok,
      statutHttp: reponse.status,
      texte,
      data,
    };

    if (reponse.status === 401 && essai === 0) {
      jetonEnCache = null; // jeton périmé ou déjà consommé
      continue;
    }
    break;
  }

  return derniere;
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

/**
 * Normalise un numéro Mobile Money au format international sans « + ».
 * Ex. « 0970000000 » → « 243970000000 », « 970000000 » → « 243970000000 ».
 */
function numeroInternational(brut: string): string {
  let d = (brut ?? '').replace(/[^0-9]/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.startsWith('243')) return d;
  if (d.startsWith('0')) return '243' + d.slice(1);
  if (d.length === 9) return '243' + d;
  return d;
}

/**
 * Code opérateur attendu par SerdiPay (`telecom`).
 * ⚠️ SerdiPay n'a pas communiqué les valeurs admises (l'API répond
 * « Unhandled match case 'orange' »). Le secret `SERDIPAY_TELECOM_MAP`
 * (JSON, ex. `{"orange":"OrangeMoney"}`) permet de les corriger SANS
 * redéployer la fonction.
 */
function codeTelecom(operateur: string | null): string {
  const o = (operateur ?? '').trim().toLowerCase().replace(/[\s-]/g, '');
  let surcharges: Record<string, string> = {};
  try {
    const brut = Deno.env.get('SERDIPAY_TELECOM_MAP');
    if (brut && brut.trim().length > 0) {
      surcharges = JSON.parse(brut) as Record<string, string>;
    }
  } catch {
    console.error('[serdipay] SERDIPAY_TELECOM_MAP n’est pas un JSON valide');
  }
  // ✅ VALEURS CONFIRMÉES / DÉDUITES le 30/10/2026 : SerdiPay attend des
  // ABRÉVIATIONS MAJUSCULES, pas le nom de l'opérateur.
  //   `OM` → accepté (Orange Money) — les autres suivent la même logique.
  const table: Record<string, string> = {
    orange: 'OM',
    orangemoney: 'OM',
    airtel: 'AM',
    airtelmoney: 'AM',
    mpesa: 'VM',
    vodacom: 'VM',
    afrimoney: 'AF',
    africell: 'AF',
    ...surcharges,
  };
  return table[o] ?? o;
}

/** Message lisible renvoyé par SerdiPay (champ `error`, `message` ou `errors`). */
function resumeErreurFournisseur(data: unknown, texte: string): string {
  const d = (data ?? {}) as Record<string, unknown>;
  const err = d.error ?? d.errors ?? d.message;
  if (typeof err === 'string' && err.trim().length > 0) {
    return err.trim().slice(0, 200);
  }
  if (err && typeof err === 'object') {
    const paires = Object.entries(err as Record<string, unknown>);
    if (paires.length > 0) {
      return paires
        .slice(0, 3)
        .map(([champ, valeur]) => `${champ}: ${String(valeur).slice(0, 120)}`)
        .join(' · ');
    }
  }
  return texte.slice(0, 200);
}

function construireCorpsInitier(
  p: PaiementOuvert,
  nomClient: string,
  repli?: { telephone?: string | null; operateur?: string | null },
): Record<string, unknown> {
  const callback = `${SUPABASE_URL}/functions/v1/${FONCTION}/webhook`;
  const description = `Abonnement Biashara Yangu - ${p.reference}`;

  // 🔎 Le téléphone/opérateur viennent normalement de la ligne ouverte en
  // base. S'ils y sont vides (ligne ancienne, RPC d'une version antérieure),
  // on reprend ceux de la REQUÊTE : sans eux SerdiPay répond
  // « clientPhone: validation.required · telecom: validation.required ».
  const telBrut = (p.telephone ?? '').trim().length >= 9
    ? p.telephone
    : (repli?.telephone ?? p.telephone);
  const opBrut = (p.operateur ?? '').trim().length > 0
    ? p.operateur
    : (repli?.operateur ?? p.operateur);

  const clientPhone = numeroInternational(telBrut ?? '');
  const telecom = codeTelecom(opBrut ?? null);

  // Modèle surchargeable sans redéploiement : secret SERDIPAY_CORPS_INITIER.
  const modele = Deno.env.get('SERDIPAY_CORPS_INITIER');

  // 🔐 Champs EXIGÉS par SerdiPay (l'API répond
  // « clientPhone: validation.required · telecom: validation.required »
  // dès que l'un d'eux est vide). Ils sont réinjectés après application du
  // modèle : un secret incomplet ne peut plus casser un paiement.
  const obligatoires: Record<string, unknown> = {
    merchantCode: SERDIPAY_MERCHANT_CODE,
    api_id: SERDIPAY_API_ID,
    api_password: SERDIPAY_API_PASSWORD,
    merchant_pin: SERDIPAY_PIN,
    clientPhone,
    telecom,
    amount: Number(p.montant),
    currency: p.devise || SERDIPAY_DEVISE,
  };

  const injecterObligatoires = (
    corps: Record<string, unknown>,
    origine: string,
  ): Record<string, unknown> => {
    const manquants: string[] = [];
    for (const [cle, valeur] of Object.entries(obligatoires)) {
      const actuel = corps[cle];
      if (actuel === undefined || actuel === null || actuel === '') {
        corps[cle] = valeur;
        manquants.push(cle);
      }
    }
    if (manquants.length > 0) {
      console.warn(
        `[serdipay] champs obligatoires réinjectés (${origine}) : ` +
          manquants.join(', '),
      );
    }
    return corps;
  };

  if (modele && modele.trim().length > 0) {
    const rempli = modele
      .replaceAll('{apiId}', SERDIPAY_API_ID)
      .replaceAll('{apiPassword}', SERDIPAY_API_PASSWORD)
      .replaceAll('{pin}', SERDIPAY_PIN)
      .replaceAll('{merchantCode}', SERDIPAY_MERCHANT_CODE)
      .replaceAll('{reference}', p.reference)
      .replaceAll('{montant}', String(Number(p.montant)))
      .replaceAll('{devise}', p.devise || SERDIPAY_DEVISE)
      .replaceAll('{telephone}', clientPhone)
      .replaceAll('{operateur}', telecom)
      .replaceAll('{callback}', callback)
      .replaceAll('{retour}', SERDIPAY_RETURN_URL)
      .replaceAll('{description}', description)
      .replaceAll('{nomClient}', nomClient || 'Client Biashara Yangu');
    try {
      const lu = JSON.parse(rempli) as Record<string, unknown>;
      lu.merchantCode ??= SERDIPAY_MERCHANT_CODE;
      return injecterObligatoires(lu, 'modèle SERDIPAY_CORPS_INITIER');
    } catch {
      // Modèle invalide : on utilise le corps par défaut ci-dessous.
      console.error('[serdipay] SERDIPAY_CORPS_INITIER n’est pas un JSON valide');
    }
  }

  // ✅ Corps EXACT exigé par `POST /merchant/payment-merchant`.
  // Champs obligatoires découverts le 30/10/2026 en interrogeant l'API :
  //   merchantCode, api_id, api_password, merchant_pin, clientPhone,
  //   telecom, amount, currency
  return injecterObligatoires(
    {
      merchantCode: SERDIPAY_MERCHANT_CODE,
      api_id: SERDIPAY_API_ID,
      api_password: SERDIPAY_API_PASSWORD,
      merchant_pin: SERDIPAY_PIN,
      clientPhone,
      telecom,
      amount: Number(p.montant),
      currency: p.devise || SERDIPAY_DEVISE,
      // Facultatifs, utiles au reçu et au rapprochement :
      reference: p.reference,
      description,
      callbackUrl: callback,
      returnUrl: SERDIPAY_RETURN_URL,
    },
    'corps par défaut',
  );
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
    sous.transactionId,
    sous.provider_reference,
    sous.reference,
    // SerdiPay renvoie `transactionId` (ex. « SD261030ZQ3UJ ») et un `token`
    // de session à l'intérieur de l'objet `payment`.
    sous.token,
    sous.sessionId,
    d.token,
    d.sessionId,
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

/**
 * Retrouve la référence interne d'un paiement.
 *  - si la notification la contient, on la prend ;
 *  - sinon on la déduit de la référence fournisseur (`transactionId` SerdiPay,
 *    ex. « SD261030ZQ3UJ ») enregistrée lors de l'initialisation.
 */
async function referenceDepuisFournisseur(
  referenceDirecte: string | null,
  providerReference: string | null,
): Promise<string | null> {
  if (referenceDirecte) return referenceDirecte;
  if (!providerReference) return null;
  try {
    const { data } = await clientService()
      .from('paiements_serdipay')
      .select('reference')
      .eq('provider_reference', providerReference)
      .maybeSingle();
    const ref = (data as Record<string, unknown> | null)?.reference;
    return ref ? String(ref) : null;
  } catch {
    return null;
  }
}

/**
 * SerdiPay ajoute des FRAIS OPÉRATEUR au montant demandé (ex. 2 300 CDF
 * demandés → 2 366 CDF débités au client). On ne transforme donc jamais un
 * paiement réussi en échec quand le montant reçu est SUPÉRIEUR : on transmet le
 * montant attendu (le contrôle de la base reste actif pour les montants
 * INFÉRIEURS, qui sont bien des anomalies).
 */
async function montantARecorder(
  reference: string,
  montantRecu: number | null,
): Promise<number | null> {
  if (montantRecu === null) return null;
  try {
    const { data } = await clientService()
      .from('paiements_serdipay')
      .select('montant')
      .eq('reference', reference)
      .maybeSingle();
    const attendu = Number((data as Record<string, unknown> | null)?.montant);
    if (Number.isFinite(attendu) && montantRecu >= attendu) return attendu;
  } catch {
    // best-effort : on transmet le montant brut
  }
  return montantRecu;
}

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
 * SerdiPay indique que la clé de signature est soit `api_password`, soit un
 * « Webhook Secret » généré dans le back-office : on essaie donc LES DEUX.
 * Accepte, dans cet ordre :
 *   1. un HMAC-SHA256 du corps (hex ou base64) dans l'en-tête de signature ;
 *   2. un simple jeton partagé dans un EN-TÊTE (`x-serdipay-token` /
 *      `x-webhook-token`, ou l'en-tête `Authorization`) ;
 *   3. le même HMAC calculé en hexadécimal MAJUSCULE ou avec le corps compacté.
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
    'x-serdipay-webhook-signature',
  ];

  // Secrets candidats : le secret dédié, puis le mot de passe d'API.
  const secrets = [SERDIPAY_WEBHOOK_SECRET, SERDIPAY_API_PASSWORD]
    .map((s) => (s ?? '').trim())
    .filter((s, i, t) => s.length > 0 && t.indexOf(s) === i);

  for (const secret of secrets) {
    const { hex, base64 } = await hmac(secret, corps);

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
  }

  // Jeton partagé envoyé tel quel dans un en-tête.
  const jetons = [
    req.headers.get('x-serdipay-token'),
    req.headers.get('x-webhook-token'),
    jetonPorteur(req),
  ];

  for (const jeton of jetons) {
    if (!jeton) continue;
    for (const secret of secrets) {
      if (egalConstant(jeton.trim(), secret)) return true;
    }
  }

  // Journalisation : indispensable pour aligner l'algorithme de SerdiPay.
  try {
    const entetesRecus: Record<string, string> = {};
    req.headers.forEach((v, k) => {
      if (/authorization|token|signature|secret|key/i.test(k)) {
        entetesRecus[k] = v.slice(0, 120);
      }
    });
    console.error('[serdipay][webhook refuse]', JSON.stringify({
      entetes: entetesRecus,
      corps: corps.slice(0, 600),
    }));
  } catch {
    // ignore
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
    apiIdDefinie: SERDIPAY_API_ID.length > 0,
    merchantCode: SERDIPAY_MERCHANT_CODE,
    emailDefini: SERDIPAY_EMAIL.length > 0,
    motDePasseDefini: SERDIPAY_PASSWORD.length > 0,
    motDePasseApiDefini: SERDIPAY_API_PASSWORD.length > 0,
    pinDefini: SERDIPAY_PIN.length > 0,
    cleApiDefinie: SERDIPAY_API_KEY.length > 0,
    routes: {
      base: SERDIPAY_BASE_URL,
      jeton: SERDIPAY_PATH_TOKEN,
      paiement: SERDIPAY_PATH_INITIER,
      statut: SERDIPAY_PATH_STATUT || '(non fournie par SerdiPay)',
    },
    devise: SERDIPAY_DEVISE,
    webhook: `${SUPABASE_URL}/functions/v1/${FONCTION}/webhook`,
  });
}

/**
 * POST /diag-token — essai à blanc de l'obtention du jeton.
 * Protégé par l'en-tête `x-relais-token` (secret partagé avec le relais).
 * Essaie plusieurs formes de corps, s'arrête au premier succès et renvoie la
 * réponse BRUTE de SerdiPay (aucun secret n'apparaît dans la réponse).
 */
async function routeDiagToken(req: Request): Promise<Response> {
  const jeton = req.headers.get('x-relais-token') ?? '';
  if (SERDIPAY_RELAIS_TOKEN.length === 0 || jeton !== SERDIPAY_RELAIS_TOKEN) {
    return erreur('ACCES_REFUSE', 'En-tête x-relais-token attendu.', 403);
  }
  if (!identifiantsFournisseur()) {
    return erreur(
      'SERDIPAY_NON_CONFIGURE',
      'Aucun identifiant : renseignez SERDIPAY_EMAIL + SERDIPAY_PASSWORD ' +
        'dans les secrets Supabase.',
      503,
    );
  }

  const url = SERDIPAY_TOKEN_URL ||
    `${SERDIPAY_BASE_URL}${SERDIPAY_PATH_TOKEN}`;

  const essais: { nom: string; type: string; corps: string }[] = [
    {
      nom: 'email+password (JSON) — format confirmé',
      type: 'application/json',
      corps: JSON.stringify({
        email: SERDIPAY_EMAIL,
        password: SERDIPAY_PASSWORD,
      }),
    },
    {
      nom: 'email+password+merchantCode (JSON)',
      type: 'application/json',
      corps: JSON.stringify({
        email: SERDIPAY_EMAIL,
        password: SERDIPAY_PASSWORD,
        merchantCode: SERDIPAY_MERCHANT_CODE,
      }),
    },
    {
      nom: 'apiId+apiKey(=mot de passe) (JSON)',
      type: 'application/json',
      corps: JSON.stringify({
        apiId: SERDIPAY_API_ID,
        apiKey: SERDIPAY_PASSWORD,
      }),
    },
    {
      nom: 'form-urlencoded email/password',
      type: 'application/x-www-form-urlencoded',
      corps: new URLSearchParams({
        email: SERDIPAY_EMAIL,
        password: SERDIPAY_PASSWORD,
      }).toString(),
    },
  ];

  const resultats: Record<string, unknown>[] = [];
  for (const essai of essais) {
    let statutHttp = 0;
    let texte = '';
    let ok = false;
    try {
      const reponse = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': essai.type,
          Accept: 'application/json',
          ...(SERDIPAY_RELAIS_TOKEN
            ? { 'x-relais-token': SERDIPAY_RELAIS_TOKEN }
            : {}),
        },
        body: essai.corps,
        signal: AbortSignal.timeout(15_000),
      });
      statutHttp = reponse.status;
      ok = reponse.ok;
      texte = (await reponse.text()).slice(0, 300);
    } catch (e) {
      texte = 'ERREUR_RESEAU : ' + String(e).slice(0, 180);
    }
    resultats.push({
      essai: essai.nom,
      statutHttp,
      ok,
      reponse: texte,
    });
    if (ok) break;
  }

  return json({
    url,
    merchantCode: SERDIPAY_MERCHANT_CODE,
    apiId: SERDIPAY_API_ID,
    emailDefini: SERDIPAY_EMAIL.length > 0,
    motDePasseDefini: SERDIPAY_PASSWORD.length > 0,
    essais: resultats,
  });
}

/**
 * POST /diag-paiement — vérifie le jeton PUIS interroge
 * `/merchant/payment-merchant` avec un corps VIDE : SerdiPay répond alors la
 * liste des champs obligatoires, sans créer de transaction.
 * Protégé par `x-relais-token`.
 */
async function routeDiagPaiement(req: Request): Promise<Response> {
  const jeton = req.headers.get('x-relais-token') ?? '';
  if (SERDIPAY_RELAIS_TOKEN.length === 0 || jeton !== SERDIPAY_RELAIS_TOKEN) {
    return erreur('ACCES_REFUSE', 'En-tête x-relais-token attendu.', 403);
  }
  if (!serdipayConfigure()) {
    return erreur(
      'SERDIPAY_NON_CONFIGURE',
      'Aucun identifiant : renseignez SERDIPAY_EMAIL + SERDIPAY_PASSWORD ' +
        'dans les secrets Supabase.',
      503,
    );
  }

  // Corps transmis tel quel s'il est fourni (permet d'explorer l'API sans
  // redéployer), sinon un corps vide pour faire lister les champs requis.
  let corpsEnvoye = '{}';
  try {
    const brut = (await req.text()).trim();
    if (brut.length > 0) {
      corpsEnvoye = remplirModele(brut);
    }
  } catch {
    // corps illisible : on garde '{}'
  }

  const url = `${SERDIPAY_BASE_URL}${SERDIPAY_PATH_INITIER}`;
  let statutHttp = 0;
  let texte = '';

  // Deux tentatives : le jeton SerdiPay peut être refusé (401) s'il a déjà
  // servi ; on en redemande un neuf avant de rejouer.
  for (let essai = 0; essai < 2; essai++) {
    let valeurJeton = '';
    try {
      valeurJeton = (await jetonSerdipay()).valeur;
    } catch (e) {
      return json({
        etape: 'jeton',
        ok: false,
        erreur: String(e).slice(0, 400),
      });
    }

    try {
      const reponse = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${valeurJeton}`,
          'Content-Type': 'application/json',
          Accept: 'application/json',
          ...(SERDIPAY_RELAIS_TOKEN
            ? { 'x-relais-token': SERDIPAY_RELAIS_TOKEN }
            : {}),
        },
        body: corpsEnvoye,
        signal: AbortSignal.timeout(20_000),
      });
      statutHttp = reponse.status;
      texte = (await reponse.text()).slice(0, 800);
    } catch (e) {
      texte = 'ERREUR_RESEAU : ' + String(e).slice(0, 200);
    }

    if (statutHttp === 401 && essai === 0) {
      jetonEnCache = null;
      continue;
    }
    break;
  }

  return json({
    etape: 'paiement',
    jetonObtenu: true,
    url,
    corpsEnvoye: corpsEnvoye.replace(
      /"(api_password|merchant_pin)":"[^"]*"/g,
      '"$1":"***"',
    ),
    statutHttp,
    reponse: texte,
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
        'renseignez SERDIPAY_EMAIL et SERDIPAY_PASSWORD dans les secrets ' +
        'Supabase, puis redéployez la fonction « serdipay ».',
      503,
    );
  }

  // SerdiPay exige `api_password` ET `merchant_pin` dans le corps du paiement.
  if (SERDIPAY_API_PASSWORD.length === 0 || SERDIPAY_PIN.length === 0) {
    return erreur(
      'SERDIPAY_PIN_MANQUANT',
      'Il manque le mot de passe API ou le PIN SerdiPay : renseignez ' +
        'SERDIPAY_API_PASSWORD et SERDIPAY_PIN dans les secrets Supabase.',
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

  // AVANCE : le client peut payer une PARTIE de ce qu'il doit. Le montant
  // reste vérifié en base (jamais supérieur au solde) : l'application ne
  // peut donc pas « négocier » un prix par ce champ.
  const montantBrut = corps.montant ?? corps.p_montant ?? null;
  const montantDemande =
    montantBrut === null || montantBrut === undefined || montantBrut === ''
      ? null
      : Number(montantBrut);
  if (
    montantDemande !== null &&
    (!Number.isFinite(montantDemande) || montantDemande <= 0)
  ) {
    return erreur(
      'MONTANT_INCORRECT',
      'Le montant saisi est invalide.',
      400,
    );
  }

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
      p_montant: montantDemande,
    },
  );

  if (erreurOuverture) {
    const t = traduireErreurBase(erreurOuverture.message ?? '');
    const statutHttp = t.code === 'SESSION_ABSENTE' ? 401 : 400;
    return erreur(t.code, t.message, statutHttp);
  }

  const paiement = ouvert as PaiementOuvert;

  // 💰 Barème SerdiPay : hors bornes, leur API répond 402 avec un message
  // technique. On explique AVANT de créer la transaction.
  const devise = (paiement.devise || SERDIPAY_DEVISE).toUpperCase();
  if (devise === 'CDF') {
    const montant = Number(paiement.montant);
    if (
      Number.isFinite(montant) &&
      (montant < SERDIPAY_MONTANT_MIN || montant > SERDIPAY_MONTANT_MAX)
    ) {
      await clientService().rpc('rpc_serdipay_echec', {
        p_reference: paiement.reference,
        p_motif:
          `MONTANT_HORS_BAREME : ${montant} CDF (autorisé ` +
          `${SERDIPAY_MONTANT_MIN} - ${SERDIPAY_MONTANT_MAX})`,
      });
      return erreur(
        'MONTANT_HORS_BAREME',
        'Montant hors du barème Mobile Money : SerdiPay accepte de ' +
          `${SERDIPAY_MONTANT_MIN} à ${SERDIPAY_MONTANT_MAX} CDF. ` +
          `Votre paiement de ${montant} CDF est refusé.`,
        400,
      );
    }
  }

  let nom = '';
  try {
    const id = await identiteClient(ctx.client, ctx.userId);
    nom = id.nom;
  } catch {
    // best-effort
  }

  // 2) Créer la transaction chez SerdiPay.
  let reponse: Awaited<ReturnType<typeof appelFournisseur>>;
  try {
    reponse = await appelFournisseur(
      SERDIPAY_PATH_INITIER,
      'POST',
      construireCorpsInitier(paiement, nom, {
        // Repli : les valeurs réellement demandées par l'utilisateur.
        telephone,
        operateur,
      }),
    );
  } catch (e) {
    const motif = String(e);
    await clientService().rpc('rpc_serdipay_echec', {
      p_reference: paiement.reference,
      p_motif: `FOURNISSEUR : ${motif.slice(0, 300)}`,
    });

    if (motif.includes('SERDIPAY_IP_NON_AUTORISEE')) {
      return erreur(
        'SERDIPAY_IP_NON_AUTORISEE',
        "SerdiPay refuse l'appel : l'adresse IP du relais " +
          '(213.130.145.53) n’est pas encore déclarée chez eux. ' +
          'Demandez à SerdiPay de la mettre en liste blanche.',
        503,
      );
    }

    if (motif.includes('SERDIPAY_AUTH_')) {
      return erreur(
        'SERDIPAY_AUTH',
        'SerdiPay a refusé nos identifiants : vérifiez les secrets ' +
          'SERDIPAY_API_ID et SERDIPAY_API_KEY, puis réessayez.',
        502,
      );
    }

    return erreur(
      'FOURNISSEUR_INJOIGNABLE',
      "Impossible de joindre SerdiPay pour le moment. Réessayez dans " +
        'quelques instants.',
      502,
    );
  }

  if (!reponse.ok) {
    const detail = resumeErreurFournisseur(reponse.data, reponse.texte);

    await clientService().rpc('rpc_serdipay_echec', {
      p_reference: paiement.reference,
      p_motif: `HTTP_${reponse.statutHttp} : ${reponse.texte.slice(0, 400)}`,
    });

    return erreur(
      'PAIEMENT_REFUSE_FOURNISSEUR',
      `SerdiPay a refusé la demande : ${detail}`,
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
  // Ignoré tant que SerdiPay n'a pas communiqué de route d'interrogation.
  if (
    paiement.statut === 'en_attente' && serdipayConfigure() &&
    SERDIPAY_PATH_STATUT.trim().length > 0
  ) {
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
          const montantRecu = await montantARecorder(reference, infos.montant);
          const { data: confirme } = await clientService().rpc(
            'rpc_serdipay_confirmer',
            {
              p_reference: reference,
              p_statut: infos.statut,
              p_provider_reference: infos.providerReference,
              p_montant_recu: montantRecu,
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
  if (!SERDIPAY_WEBHOOK_SECRET && !SERDIPAY_API_PASSWORD) {
    return erreur(
      'WEBHOOK_NON_CONFIGURE',
      'Secret de signature absent : définissez SERDIPAY_WEBHOOK_SECRET ' +
        '(ou SERDIPAY_API_PASSWORD, utilisé par SerdiPay).',
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

  // La notification ne contient pas forcément notre référence : on la retrouve
  // grâce au `transactionId` renvoyé à l'initialisation.
  const reference = await referenceDepuisFournisseur(
    infos.reference,
    infos.providerReference,
  );

  if (!reference) {
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

  const montantRecu = await montantARecorder(reference, infos.montant);

  const { data, error } = await clientService().rpc('rpc_serdipay_confirmer', {
    p_reference: reference,
    p_statut: infos.statut,
    p_provider_reference: infos.providerReference,
    p_montant_recu: montantRecu,
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

    if (chemin === '/diag-token') {
      if (req.method !== 'POST') {
        return erreur('METHODE_REFUSEE', 'Utilisez POST.', 405);
      }
      return await routeDiagToken(req);
    }

    if (chemin === '/diag-paiement') {
      if (req.method !== 'POST') {
        return erreur('METHODE_REFUSEE', 'Utilisez POST.', 405);
      }
      return await routeDiagPaiement(req);
    }

    if (chemin === '/statut') {
      if (req.method !== 'POST') {
        return erreur('METHODE_REFUSEE', 'Utilisez POST.', 405);
      }
      return await routeStatut(req);
    }

    return erreur(
      'ROUTE_INCONNUE',
      `Route inconnue « ${chemin} ». Attendu : /ping, /initier, /statut, ` +
        '/webhook, /diag-token, /diag-paiement.',
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
