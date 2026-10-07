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
//
//    Codes : 200 succès · 400 requête invalide · 401 jeton absent/incorrect ·
//            403 action refusée · 404 route inconnue · 502 erreur base · 503 non configuré.
//    Forme : { ok:true, ... } ou { erreur, message }.
//
//  DÉPLOIEMENT (résumé)
//  --------------------
//    1. Supabase Dashboard → Edge Functions → « admin-agents » → Éditer → coller
//       ce fichier → Deploy (ou `supabase functions deploy admin-agents`).
//    2. Edge Functions → Secrets → ajouter `BG_ADMIN_TOKEN` = une chaîne
//       aléatoire longue (≥ 32 caractères). La communiquer à Biashara Group.
//    3. SQL requis AVANT : 20260916000051_api_biashara_group_agents.sql
//       (crée les RPC `rpc_bg_*` réservées au service_role).
//    4. « Verify JWT » peut rester ACTIVÉ : cette fonction n'utilise pas le JWT
//       utilisateur, mais le jeton de service. Si votre passerelle l'exige,
//       envoyez aussi l'en-tête `Authorization: Bearer <anon>`.
// ============================================================================

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const BG_ADMIN_TOKEN = Deno.env.get('BG_ADMIN_TOKEN') ?? '';

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
