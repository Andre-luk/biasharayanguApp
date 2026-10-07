// ============================================================================
//  biashara_yangu — MODULE 21 quinquies : EDGE FUNCTION « admin-agents »
//
//  API de service qui permet à la plateforme d'administration de BIASHARA
//  GROUP (biasharagroup.com/admin) de suivre ses agents terrain :
//  recrutement, activité, dossiers, boutiques, QR codes, encaissements,
//  journal complet, désactivation.
//
//  ⚠️ SÉCURITÉ
//  -----------
//    • La clé `service_role` NE SORT JAMAIS d'ici : Biashara Group n'appelle
//      cette fonction qu'avec un JETON DE SERVICE dédié (secret
//      `BG_ADMIN_TOKEN`), transmis dans l'en-tête `x-bg-token`.
//    • Aucune session utilisateur n'est requise (le service_role n'en a pas).
//    • Les RPC `rpc_bg_*` appelées ici sont `execute` UNIQUEMENT pour
//      `service_role` : elles sont inaccessibles depuis l'application Flutter.
//    • Les données exposées se limitent à l'ACTIVITÉ DE L'AGENT : jamais les
//      ventes, le stock, les dépenses ou les clients des commerçants.
//    • L'assistant IA (route /ia) raisonne UNIQUEMENT sur ces mêmes données :
//      la clé `DEEPSEEK_API_KEY` ne sort pas non plus de la fonction.
//
//  CONTRAT (préfixe : /admin-agents)
//  ---------------------------------
//    GET    /admin-agents/ping                          → {ok:true, service:'admin-agents'}
//    GET    /admin-agents/agents                        → liste des agents + compteurs
//    GET    /admin-agents/agents/{agentId}              → fiche complète d'un agent
//    GET    /admin-agents/agents/{agentId}/journal      → journal unifié
//           ?limite=100&decalage=0
//    POST   /admin-agents/agents                        → créer un agent
//           { email, password, nom, prenom, note }
//    POST   /admin-agents/agents/{agentId}/desactiver   → désactiver (valide = 0)
//           { motif }
//    GET    /admin-agents/ia                            → état de l'assistant IA
//    POST   /admin-agents/ia                            → analyser via DeepSeek
//           { question, agentId? }
//
//    Codes : 200 succès · 400 requête invalide · 401 jeton absent/incorrect ·
//            403 action refusée · 404 route inconnue · 502 erreur base · 503 non configuré.
//    Forme : { ok:true, ... } ou { erreur, message }.
//
//  DÉPLOIEMENT (résumé)
//  --------------------
//    1. Supabase Dashboard → Edge Functions → « admin-agents » → Éditer → coller
//       ce fichier → Deploy (ou `supabase functions deploy admin-agents`).
//    2. Edge Functions → Secrets → ajouter :
//         • `BG_ADMIN_TOKEN`   = chaîne aléatoire longue (≥ 32 caractères),
//           à communiquer à Biashara Group (en-tête `x-bg-token`) ;
//         • `DEEPSEEK_API_KEY` = déjà défini si l'assistant `agent-ia`
//           fonctionne (les secrets Supabase sont au niveau du PROJET).
//    3. SQL requis AVANT : 20260916000051_api_biashara_group_agents.sql
//       (crée les RPC `rpc_bg_*` réservées au service_role).
//    4. ⚠️ DÉSACTIVER « Verify JWT » (« Enforce JWT verification ») sur cette
//       fonction : elle ne s'authentifie PAS par JWT mais par `x-bg-token`.
//       Sinon la passerelle répond AVANT le code :
//         401 {"code":"UNAUTHORIZED_NO_AUTH_HEADER","message":"Missing authorization header"}
//       Sinon, il faut ajouter l'en-tête `Authorization: Bearer <anon>` à
//       chaque appel (mais `apikey:` seul NE SUFFIT PAS).
// ============================================================================

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const BG_ADMIN_TOKEN = Deno.env.get('BG_ADMIN_TOKEN') ?? '';
const DEEPSEEK_API_KEY = Deno.env.get('DEEPSEEK_API_KEY') ?? '';

// ---- Assistant IA (DeepSeek) ----------------------------------------------
const DEEPSEEK_URL = 'https://api.deepseek.com/chat/completions';
const DEEPSEEK_MODEL = 'deepseek-chat';
const IA_MAX_TOKENS = 900;
const IA_TEMPERATURE = 0.2;
const IA_QUESTION_MAX = 1000;
const IA_JOURNAL_MAX = 40;

const CORS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-bg-token',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

// ---------------------------------------------------------------------------
// RÉPONSES
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

/** Extrait le texte lisible d'un message serveur préfixé « CODE|texte ». */
function messageLisible(brut: string): string {
  const i = brut.indexOf('|');
  return i >= 0 && i < brut.length - 1 ? brut.slice(i + 1).trim() : brut;
}

// ---------------------------------------------------------------------------
// OUTILS
// ---------------------------------------------------------------------------

function clientService(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Chemin utile, sans le préfixe de la fonction. Ex. « /agents/abc/journal ». */
function cheminUtile(url: URL): string {
  let p = url.pathname;
  // Retire « /admin-agents » (ou le slug réel de la fonction) s'il est présent.
  const marqueurs = ['/admin-agents', '/functions/v1/admin-agents'];
  for (const m of marqueurs) {
    if (p.startsWith(m)) {
      p = p.slice(m.length);
      break;
    }
  }
  if (!p.startsWith('/')) p = '/' + p;
  return p.replace(/\/+$/, '') || '/';
}

function estUuid(v: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
}

// ---------------------------------------------------------------------------
// ASSISTANT IA (DeepSeek) — analyse de l'activité des agents terrain
// ---------------------------------------------------------------------------

const IA_SYSTEME = `Tu es l'assistant analytique de l'espace d'administration de BIASHARA GROUP
(biasharagroup.com/admin), la societe editrice de l'application « Biashara Yangu ».

TON ROLE : aider les administrateurs et responsables a suivre leurs AGENTS TERRAIN.

DONNEES MISES A TA DISPOSITION (transmises en JSON avec la question) :
  - le PORTEFEUILLE des agents (compteurs par agent) ; ou
  - la FICHE d'un agent precis : entreprises raccordees, boutiques, QR codes,
    abonnements actifs, produits, encaissements, solde du ; et
  - son JOURNAL d'activite unifie (connexions, verifications de comptes,
    montants definis, vitrines, publications, rapports, paiements encaisses).

REGLES STRICTES :
  1. Ne reponds QUE d'apres les donnees fournies. Si une information manque,
     dis-le explicitement (« je ne vois pas cette information dans les donnees »).
     N'invente JAMAIS un chiffre, un nom ou une date.
  2. Tu n'as acces NI aux ventes, NI au stock, NI aux depenses, NI aux clients des
     commercants : ce n'est pas ton perimetre. Refuse poliment ces demandes et
     rappelle que seules les ACTIVITES DE L'AGENT sont suivies.
  3. Reponds en FRANCAIS, de facon breve et concrete : 5 phrases maximum, ou une
     courte liste a puces. Aucun preambule, aucune conclusion creuse.
  4. Les montants sont en francs congolais (CDF) : ecris-les avec une espace comme
     separateur de milliers (exemple : 12 500 CDF).
  5. Termine, quand c'est utile, par 1 ou 2 recommandations actionnables.`;

interface ReponseIa {
  reponse: string;
  usage: {
    entree: number;
    entreeCache: number;
    sortie: number;
    total: number;
  };
}

/** RPC service_role qui renvoie les DONNEES (et non une Response HTTP). */
async function rpcDonnees(
  client: SupabaseClient,
  nom: string,
  params: Record<string, unknown>,
): Promise<unknown> {
  const { data, error } = await client.rpc(nom, params);
  if (error) throw new Error(error.message ?? 'Erreur inconnue');
  return data;
}

/** Rassemble le contexte JSON : portefeuille, ou fiche + journal d'un agent. */
async function construireContexte(
  client: SupabaseClient,
  agentId: string | null,
): Promise<Record<string, unknown>> {
  if (!agentId) {
    return { portefeuille: await rpcDonnees(client, 'rpc_bg_agents_lister', {}) };
  }

  const fiche = await rpcDonnees(client, 'rpc_bg_agent_fiche', { p_agent_id: agentId });

  let journal: unknown = null;
  try {
    journal = await rpcDonnees(client, 'rpc_bg_agent_journal_lister', {
      p_agent_id: agentId,
      p_limite: IA_JOURNAL_MAX,
      p_decalage: 0,
    });
  } catch (e) {
    console.error(`admin-agents : journal indisponible pour ${agentId} → ${e}`);
  }

  return { fiche, journal };
}

/** Appel HTTP à l'API DeepSeek (compatible OpenAI). */
async function interrogerIa(
  question: string,
  contexte: Record<string, unknown>,
): Promise<ReponseIa> {
  const corps = {
    model: DEEPSEEK_MODEL,
    messages: [
      { role: 'system', content: IA_SYSTEME },
      {
        role: 'user',
        content: 'DONNEES (JSON) :\n' + JSON.stringify(contexte) +
          '\n\nQUESTION DE L\'ADMINISTRATEUR :\n' + question,
      },
    ],
    max_tokens: IA_MAX_TOKENS,
    temperature: IA_TEMPERATURE,
    stream: false,
  };

  const reponse = await fetch(DEEPSEEK_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${DEEPSEEK_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(corps),
    signal: AbortSignal.timeout(60_000),
  });

  if (!reponse.ok) {
    const texte = await reponse.text().catch(() => '');
    throw new Error(`DeepSeek ${reponse.status} : ${texte.slice(0, 300)}`);
  }

  const donnees = await reponse.json();
  const contenu = donnees?.choices?.[0]?.message?.content;
  if (!contenu) throw new Error('DeepSeek : reponse sans contenu.');

  const u = donnees?.usage ?? {};
  const entree = Number(u.prompt_tokens ?? 0);
  const entreeCache = Number(
    u.prompt_cache_hit_tokens ?? u.prompt_tokens_details?.cached_tokens ?? 0,
  );
  const sortie = Number(u.completion_tokens ?? 0);

  return {
    reponse: String(contenu).trim(),
    usage: {
      entree,
      entreeCache: Math.min(Math.max(entreeCache, 0), entree),
      sortie,
      total: Number(u.total_tokens ?? entree + sortie),
    },
  };
}

// ---------------------------------------------------------------------------
// APPEL RPC (service_role) AVEC NORMALISATION DES ERREURS
// ---------------------------------------------------------------------------

async function rpc(
  client: SupabaseClient,
  nom: string,
  params: Record<string, unknown>,
): Promise<Response> {
  const { data, error } = await client.rpc(nom, params);

  if (error) {
    const brut = error.message ?? 'Erreur inconnue';
    const lisible = messageLisible(brut);
    const code = brut.split('|')[0]?.trim() ?? 'ERREUR_BASE';

    if (code === 'PGRST202' || error.code === 'PGRST202' || error.code === '42883') {
      return erreur(
        'NON_DEPLOYE',
        "L'API agents n'est pas installée sur la base : exécutez la migration 20260916000051_api_biashara_group_agents.sql.",
        503,
      );
    }
    if (code === 'DROIT_REFUSE' || code === 'ACCES_REFUSE') {
      return erreur(code, lisible, 403);
    }
    if (
      code === 'UTILISATEUR_INCONNU' ||
      code === 'ROLE_INVALIDE' ||
      code === 'MOTIF_REQUIS' ||
      code === 'EMAIL_INVALIDE' ||
      code === 'MOT_DE_PASSE_TROP_COURT'
    ) {
      return erreur(code, lisible, 400);
    }
    console.error(`admin-agents : ${nom} → ${brut}`);
    return erreur(code, lisible, 502);
  }

  return json(data);
}

// ---------------------------------------------------------------------------
// SERVEUR
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS });
  }

  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return erreur('SERVICE_INDISPONIBLE', 'Configuration serveur incomplète.', 503);
  }
  if (!BG_ADMIN_TOKEN) {
    return erreur(
      'SECRET_MANQUANT',
      "Le secret BG_ADMIN_TOKEN n'est pas défini sur la fonction : ajoutez-le dans Edge Functions → Secrets.",
      503,
    );
  }

  // Authentification par jeton de service (comparaison à durée constante).
  const fourni = req.headers.get('x-bg-token') ?? '';
  if (fourni.length !== BG_ADMIN_TOKEN.length) {
    return erreur('JETON_INVALIDE', 'Jeton de service absent ou incorrect.', 401);
  }
  let diff = 0;
  for (let i = 0; i < fourni.length; i++) {
    diff |= fourni.charCodeAt(i) ^ BG_ADMIN_TOKEN.charCodeAt(i);
  }
  if (diff !== 0) {
    return erreur('JETON_INVALIDE', 'Jeton de service absent ou incorrect.', 401);
  }

  const url = new URL(req.url);
  const chemin = cheminUtile(url);
  const client = clientService();

  try {
    // ---------------------------------------------------------------- ping
    if (chemin === '/ping' || chemin === '/') {
      return json({ ok: true, service: 'admin-agents' });
    }

    // ------------------------------------------------------ assistant IA
    // GET  /ia → état de l'assistant (secret présent ou non).
    // POST /ia → { question, agentId? } → analyse DeepSeek.
    if (chemin === '/ia' || chemin === '/ia/etat') {
      if (req.method === 'GET') {
        return json({
          ok: true,
          assistant: 'deepseek',
          modele: DEEPSEEK_MODEL,
          disponible: DEEPSEEK_API_KEY.length > 0,
          usage: 'POST /admin-agents/ia { "question": "...", "agentId": "<uuid>|null" }',
        });
      }
      if (req.method !== 'POST') {
        return erreur('METHODE_INVALIDE', 'Utilisez GET ou POST sur /ia.', 405);
      }
      if (!DEEPSEEK_API_KEY) {
        return erreur(
          'IA_INDISPONIBLE',
          "Le secret DEEPSEEK_API_KEY n'est pas défini sur le projet : ajoutez-le dans Edge Functions → Secrets.",
          503,
        );
      }

      const corps = await req.json().catch(() => null) as Record<string, unknown> | null;
      const question = String(corps?.question ?? '').trim();
      if (question.length < 3) {
        return erreur('QUESTION_REQUISE', 'Posez une question (3 caractères minimum).');
      }
      if (question.length > IA_QUESTION_MAX) {
        return erreur(
          'QUESTION_TROP_LONGUE',
          `La question est limitée à ${IA_QUESTION_MAX} caractères.`,
        );
      }

      const brutAgent = corps?.agentId == null ? '' : String(corps.agentId).trim();
      if (brutAgent && !estUuid(brutAgent)) {
        return erreur('AGENT_ID_INVALIDE', 'Identifiant d\'agent invalide.', 400);
      }
      const agentId = brutAgent || null;

      try {
        const contexte = await construireContexte(client, agentId);
        const { reponse: texte, usage } = await interrogerIa(question, contexte);

        // Comptabilité réelle (best-effort) : cet appel est offert à Biashara
        // Group, donc 0 quota et 0 CDF facturés — seul le COÛT est enregistré,
        // ce qui rend la charge visible dans le tableau de bord des tokens.
        try {
          await client.rpc('rpc_ia_usage_enregistrer', {
            p_entreprise: null,
            p_utilisateur: null,
            p_source: 'admin-agents',
            p_modele: DEEPSEEK_MODEL,
            p_tokens_entree: usage.entree,
            p_tokens_cache: usage.entreeCache,
            p_tokens_sortie: usage.sortie,
            p_quotas_debites: 0,
            p_montant_cdf: 0,
          });
        } catch (e) {
          console.error(`admin-agents : comptabilite /ia → ${e}`);
        }

        return json({
          ok: true,
          agent_id: agentId,
          reponse: texte,
          jetons: usage.total,
        });
      } catch (e) {
        const brut = e instanceof Error ? e.message : String(e);
        console.error(`admin-agents : /ia → ${brut}`);
        if (brut.startsWith('DeepSeek')) {
          return erreur('IA_ERREUR', `Assistant IA en échec : ${messageLisible(brut)}`, 502);
        }
        return erreur(
          'IA_CONTEXTE_ERREUR',
          `Lecture des données impossible : ${messageLisible(brut)}`,
          502,
        );
      }
    }

    // ------------------------------------------------- liste des agents
    if (chemin === '/agents' && req.method === 'GET') {
      return await rpc(client, 'rpc_bg_agents_lister', {});
    }

    // ------------------------------------------------- créer un agent
    if (chemin === '/agents' && req.method === 'POST') {
      const corps = await req.json().catch(() => null) as Record<string, unknown> | null;
      if (!corps) return erreur('CORPS_INVALIDE', 'Corps JSON attendu.');

      const email = String(corps.email ?? '').trim();
      const password = String(corps.password ?? '');
      if (!email) return erreur('EMAIL_INVALIDE', 'L\'adresse e-mail est obligatoire.');

      return await rpc(client, 'rpc_bg_agent_creer', {
        p_email: email,
        p_password: password,
        p_nom: String(corps.nom ?? '').trim(),
        p_prenom: String(corps.prenom ?? '').trim(),
        p_note: corps.note ? String(corps.note).trim() : null,
      });
    }

    // ------------------------------------------------- routes /agents/:id
    const mAgents = /^\/agents\/([^/]+)(\/journal|\/desactiver)?$/.exec(chemin);
    if (mAgents) {
      const agentId = mAgents[1];
      const sous = mAgents[2] ?? '';

      if (!estUuid(agentId)) {
        return erreur('AGENT_ID_INVALIDE', 'Identifiant d\'agent invalide.', 400);
      }

      // Fiche complète
      if (sous === '' && req.method === 'GET') {
        return await rpc(client, 'rpc_bg_agent_fiche', { p_agent_id: agentId });
      }

      // Journal unifié
      if (sous === '/journal' && req.method === 'GET') {
        const limite = Number.parseInt(url.searchParams.get('limite') ?? '100', 10);
        const decalage = Number.parseInt(url.searchParams.get('decalage') ?? '0', 10);
        return await rpc(client, 'rpc_bg_agent_journal_lister', {
          p_agent_id: agentId,
          p_limite: Number.isFinite(limite) ? limite : 100,
          p_decalage: Number.isFinite(decalage) ? decalage : 0,
        });
      }

      // Désactivation
      if (sous === '/desactiver' && req.method === 'POST') {
        const corps = await req.json().catch(() => null) as Record<string, unknown> | null;
        const motif = String(corps?.motif ?? '').trim();
        if (motif.length < 3) {
          return erreur('MOTIF_REQUIS', 'Indiquez le motif (3 caractères minimum).');
        }
        return await rpc(client, 'rpc_bg_agent_desactiver', {
          p_agent_id: agentId,
          p_motif: motif,
        });
      }
    }

    return erreur('ROUTE_INCONNUE', `Route inconnue : ${req.method} ${chemin}`, 404);
  } catch (e) {
    console.error('admin-agents : exception', e);
    return erreur('ERREUR_SERVEUR', `Erreur inattendue : ${e}`, 500);
  }
});
