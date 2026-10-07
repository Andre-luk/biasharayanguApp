// ============================================================================
//  biashara_yangu — MODULE 13 : EDGE FUNCTION « agent-ia » (ÉTAPE 2)
//
//  Proxy SÉCURISÉ entre l'application et l'API DeepSeek : la clé API ne
//  quitte JAMAIS le serveur (secret Supabase), l'application ne parle qu'à
//  cette fonction.
//
//  PIPELINE (les 12 étapes du cahier des charges) :
//     1. vérifie le JWT utilisateur (auth.getUser) ;
//     2. charge la configuration IA (`agent_ia_config`) ;
//     3. vérifie l'ABONNEMENT de l'entreprise (actif / lecture seule) ;
//     4. vérifie le SOLDE DE QUOTAS du demandeur (> 0) ;
//     5. applique le RATE LIMITING (30 messages/h, 5000 caractères de
//        réponse/h — décisions utilisateur) ;
//     6. relit l'historique récent (12 derniers messages) et enregistre le
//        message entrant ;
//     7. envoie le tout à DeepSeek (`deepseek-chat`, max 500 tokens) ;
//     8. exécute les tool_calls reçus côté serveur — les outils appellent les
//        RPC des modules (RLS + permissions vérifiées PAR LE SERVEUR) ;
//     9. renvoie les résultats des outils à DeepSeek pour la réponse finale ;
//    10. calcule les quotas consommés (1 quota = `caracteres_par_quota`
//        caractères de réponse utile, minimum 1) ;
//    11. débite le solde via `rpc_agent_ia_debiter` (atomique, service_role) ;
//    12. journalise TOUT (`agent_ia_conversations`, `agent_ia_actions`,
//        `journal_audit` action `AGENT_IA`) et renvoie la réponse + le solde.
//
//  ⚠️ OUTILS : le registre `OUTILS` ci-dessous est COMPLET (Étapes 5 & 8) :
//  ventes, produits & stock, finance, clients, rapports, collaborateurs,
//  abonnement, QR codes, informations — chaque outil s'exécute avec le JWT
//  de l'utilisateur (RLS + permissions serveur = autorité finale). Les
//  actions sensibles exigent `confirmation=true` (Étape 9).
//
//  DÉPLOIEMENT (résumé — détails dans docs/module13_agent_ia.md) :
//    Supabase Dashboard → Edge Functions → « agent-ia » → Éditer → coller ce
//    fichier → Deploy. Secret requis : DEEPSEEK_API_KEY (Edge Functions →
//    Secrets). Les variables SUPABASE_URL / SUPABASE_ANON_KEY /
//    SUPABASE_SERVICE_ROLE_KEY sont fournies automatiquement.
//
//  SQL REQUIS AVANT DÉPLOIEMENT :
//    20260916000014_module13_agent_ia.sql       (Étape 1 : tables)
//    20260916000015_module13_agent_ia_rpc.sql   (Étape 2 : débit atomique)
//    20260916000016_module13_achats_rpc.sql     (Étapes 6/7 : achats,
//                                                attribution, config, page)
// ============================================================================

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

// ---------------------------------------------------------------------------
// CONSTANTES MÉTIER (décisions utilisateur validées)
// ---------------------------------------------------------------------------

const DEEPSEEK_URL = 'https://api.deepseek.com/chat/completions';
const MODELE = 'deepseek-chat';

/** Longueur maximale d'une réponse (tokens) — décision utilisateur. */
const MAX_TOKENS_REPONSE = 500;

/** Nombre de messages d'historique envoyés en contexte à DeepSeek. */
const NB_MESSAGES_CONTEXTE = 12;

/** Rate limiting (par utilisateur, fenêtre glissante de 1 heure). */
const MAX_MESSAGES_PAR_HEURE = 30;
const MAX_CARACTERES_REPONSE_PAR_HEURE = 5000;

/** Longueur maximale d'un message entrant (anti-abus tokens). */
const MAX_MESSAGE_UTILISATEUR = 2000;

/** Boucles d'outils maximum par message (anti-boucle infinie). */
const MAX_TOURS_OUTILS = 4;

const CORS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// ---------------------------------------------------------------------------
// VARIABLES D'ENVIRONNEMENT
// ---------------------------------------------------------------------------
//  SUPABASE_* sont injectées automatiquement par la plateforme Edge Functions.

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const DEEPSEEK_API_KEY = Deno.env.get('DEEPSEEK_API_KEY') ?? '';

// ---------------------------------------------------------------------------
// TYPES
// ---------------------------------------------------------------------------

interface ConfigAgent {
  tarif_par_quota: number;
  caracteres_par_quota: number;
  prix_pack_10_quotas: number;
  quotas_offerts_inscription: number;
  actif: boolean;
}

interface EntrepriseInfo {
  id: string;
  nom: string;
  statut: string | null;
  date_expiration: string | null;
  montant_total_du: number | null;
  montant_deja_paye: number | null;
  solde_restant: number | null;
  activite_id: string | null;
}

interface UtilisateurContexte {
  id: string;
  nom: string;
  email: string;
  role: string;
}

interface ContexteOutil {
  /** Client portant le JWT de l'utilisateur : les outils s'exécutent avec SES droits (RLS + `peut(...)`). */
  userClient: SupabaseClient;
  admin: SupabaseClient;
  utilisateur: UtilisateurContexte;
  /** Id de l'entreprise (= propriétaire) ou du compte autonome. */
  entrepriseId: string;
  entreprise: EntrepriseInfo | null;
  activite: string | null;
  config: ConfigAgent;
  soldeQuotas: number;
}

interface OutilAgent {
  definition: {
    name: string;
    description: string;
    parameters: Record<string, unknown>;
  };
  executer: (
    args: Record<string, unknown>,
    contexte: ContexteOutil,
  ) => Promise<unknown>;
  /** Étape 9 : action sensible → confirmation explicite exigée. */
  destructif?: boolean;
}

interface MessageDeepSeek {
  role: 'system' | 'user' | 'assistant' | 'tool';
  content: string | null;
  tool_calls?: AppelOutilDeepSeek[];
  tool_call_id?: string;
}

interface AppelOutilDeepSeek {
  id: string;
  type: string;
  function: { name: string; arguments: string };
}

interface ActionExecutee {
  outil: string;
  succes: boolean;
}

// ---------------------------------------------------------------------------
// OUTILS DE L'AGENT
// ---------------------------------------------------------------------------
//  ⚠️ ÉTAPE 2 = moteur + outils pilotes. Les outils suivants (ventes, stock,
//  finance, rapports, collaborateurs, QR codes…) seront AJOUTÉS à ce tableau
//  aux étapes 5 et 8 du plan, avec le même contrat :
//    • `definition`   → schéma JSON exposé à DeepSeek ;
//    • `executer`     → exécution serveur ; pour les actions métier, appeler
//      les RPC existantes avec un client portant le JWT de l'utilisateur
//      (la RLS et les permissions `peut(...)` restent l'autorité finale).

const informationsEntreprise: OutilAgent = {
  definition: {
    name: 'informations_entreprise',
    description:
      "Informations sur l'entreprise de l'utilisateur : nom, activité, statut d'abonnement, jours restants et quotas IA restants.",
    parameters: {
      type: 'object',
      properties: {},
      additionalProperties: false,
    },
  },
  async executer(_args, ctx) {
    return {
      ok: true,
      donnees: {
        entreprise: ctx.entreprise?.nom ?? null,
        activite: ctx.activite,
        statut_abonnement: ctx.entreprise?.statut ?? null,
        expiration: ctx.entreprise?.date_expiration ?? null,
        jours_restants: joursRestants(ctx.entreprise?.date_expiration),
        quotas_ia_restants: ctx.soldeQuotas,
        role: ctx.utilisateur.role,
      },
    };
  },
};

const consulterAbonnement: OutilAgent = {
  definition: {
    name: 'consulter_abonnement',
    description:
      "Détaille l'abonnement de l'entreprise : statut, expiration, jours restants, montant dû, déjà payé et solde restant.",
    parameters: {
      type: 'object',
      properties: {},
      additionalProperties: false,
    },
  },
  async executer(_args, ctx) {
    const e = ctx.entreprise;
    return {
      ok: true,
      donnees: {
        statut: e?.statut ?? null,
        expiration: e?.date_expiration ?? null,
        jours_restants: joursRestants(e?.date_expiration),
        montant_total_du: e?.montant_total_du ?? null,
        montant_deja_paye: e?.montant_deja_paye ?? null,
        solde_restant: e?.solde_restant ?? null,
      },
    };
  },
};

// ---------------------------------------------------------------------------
// HELPERS DES OUTILS
// ---------------------------------------------------------------------------

/** Message d'erreur lisible d'une erreur PostgREST/JS (retire le code serveur). */
function messageErreur(e: unknown): string {
  const brut = e && typeof e === 'object' && 'message' in e
    ? String((e as { message: unknown }).message ?? '')
    : e instanceof Error
    ? e.message
    : String(e);
  const separateur = brut.indexOf('|');
  return separateur >= 0 ? brut.slice(separateur + 1).trim() : brut;
}

/** Lève une erreur si PostgREST a renvoyé une erreur. */
function verifier(error: unknown): void {
  if (error) throw new Error(messageErreur(error));
}

function ok(donnees: unknown): unknown {
  return { ok: true, donnees };
}

function echec(texte: string): unknown {
  return { ok: false, erreur: texte };
}

/** Schéma JSON d'un objet de paramètres d'outil. */
function obj(
  proprietes: Record<string, unknown>,
  requis: string[] = [],
): Record<string, unknown> {
  return {
    type: 'object',
    properties: proprietes,
    required: requis,
    additionalProperties: false,
  };
}

/** Fabrique un outil de l'agent. */
function outil(
  name: string,
  description: string,
  parameters: Record<string, unknown>,
  executer: OutilAgent['executer'],
  destructif = false,
): OutilAgent {
  return { definition: { name, description, parameters }, executer, destructif };
}

/** Nombre sûr depuis une valeur d'outil. */
function nb(valeur: unknown): number {
  const n = Number(valeur);
  return Number.isFinite(n) ? n : NaN;
}

/**
 * Étape 9 — garde des actions sensibles : les outils destructifs refusent de
 * s'exécuter tant que le modèle n'a pas obtenu une confirmation EXPLICITE de
 * l'utilisateur puis rappelé l'outil avec `confirmation: true`.
 */
const MSG_CONFIRMATION =
  "CONFIRMATION_REQUISE : expliquez d'abord l'action à l'utilisateur, " +
  "demandez-lui de confirmer explicitement, puis rappelez l'outil avec confirmation=true.";

/** Jour courant à Kinshasa (UTC+1, sans heure d'été) au format AAAA-MM-JJ. */
function jourKinshasa(maintenant: Date = new Date()): string {
  return maintenant.toLocaleDateString('en-CA', { timeZone: 'Africa/Kinshasa' });
}

/** Bornes ISO [début, fin) d'une journée (heure de Kinshasa). */
function bornesJour(jour: string): { debut: string; fin: string } {
  const debut = new Date(`${jour}T00:00:00+01:00`);
  return {
    debut: debut.toISOString(),
    fin: new Date(debut.getTime() + 86_400_000).toISOString(),
  };
}

/** Mot de passe temporaire lisible (12 caractères, sans ambiguïté). */
function motDePasseAleatoire(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  let sortie = '';
  for (const octet of crypto.getRandomValues(new Uint8Array(12))) {
    sortie += alphabet[octet % alphabet.length];
  }
  return sortie;
}

/** Ventes d'une période regroupées par vente (outil interne partagé). */
async function listerVentes(
  ctx: ContexteOutil,
  debutIso: string,
  finIso: string,
  periode: string,
): Promise<unknown> {
  const { data, error } = await ctx.userClient
    .from('ventes')
    .select('id, vente_uuid, numero_vente, produit_id, quantite, prix, mode_paiement, date')
    .gte('date', debutIso)
    .lt('date', finIso)
    .order('date', { ascending: false })
    .limit(300);
  verifier(error);

  const lignes = data ?? [];
  const ids = [...new Set(lignes.map((l: { produit_id: number }) => l.produit_id))]
    .filter(Boolean);
  const noms: Record<number, string> = {};
  if (ids.length > 0) {
    const { data: produits } = await ctx.userClient
      .from('produits')
      .select('id, nom')
      .in('id', ids);
    for (const p of produits ?? []) noms[p.id] = p.nom;
  }

  const parVente = new Map<string, {
    numero: string | null;
    date: string | null;
    mode: string;
    total: number;
    articles: string[];
  }>();

  for (const l of lignes) {
    const cle = l.vente_uuid ?? `ligne:${l.id}`;
    const item = parVente.get(cle) ??
      { numero: l.numero_vente, date: l.date, mode: l.mode_paiement, total: 0, articles: [] };
    item.total += Number(l.prix ?? 0);
    item.articles.push(`${noms[l.produit_id] ?? `Article #${l.produit_id}`} ×${l.quantite}`);
    parVente.set(cle, item);
  }

  const ventes = [...parVente.values()];
  return ok({
    periode,
    nb_ventes: ventes.length,
    total_cdf: ventes.reduce((somme, v) => somme + v.total, 0),
    ventes: ventes.slice(0, 20).map((v) => ({
      numero_vente: v.numero,
      date: v.date,
      mode_paiement: v.mode,
      total_cdf: v.total,
      articles: v.articles.slice(0, 5),
    })),
  });
}

// ---------------------------------------------------------------------------
// OUTILS — VENTES
// ---------------------------------------------------------------------------

const rechercherProduit = outil(
  'rechercher_produit',
  "Recherche des articles par nom (insensible à la casse). Renvoie id, nom, prix de vente, stock (unités de base) et unité.",
  obj({ query: { type: 'string', description: 'Texte recherché dans le nom' } }, ['query']),
  async (args, ctx) => {
    const q = String(args.query ?? '').trim();
    if (!q) return echec('Indiquez le nom (ou une partie du nom) de l\'article.');
    const { data, error } = await ctx.userClient
      .from('produits')
      .select('id, nom, categorie, prix_vente, quantite, unite_mesure')
      .ilike('nom', `%${q}%`)
      .order('nom')
      .limit(10);
    verifier(error);
    return ok({
      resultats: (data ?? []).map((p: Record<string, unknown>) => ({
        id: p.id,
        nom: p.nom,
        categorie: p.categorie,
        prix_vente: p.prix_vente,
        stock: p.quantite,
        unite: p.unite_mesure,
      })),
    });
  },
);

const creerVente = outil(
  'creer_vente',
  "Enregistre une vente d'un article (quantité en UNITÉS DE BASE de l'article). Le serveur relit le prix, déduit le stock, encaisse en caisse et trace la vente. Demande les droits « caisse/créer ».",
  obj({
    produit_id: { type: 'integer', description: "Identifiant de l'article (rechercher_produit d'abord)" },
    quantite: { type: 'number', description: "Quantité en unités de base (ex. 3 pour 3 fardes si l'article se vend à la farde)" },
    mode_paiement: { type: 'string', enum: ['especes', 'mobile_money', 'carte', 'virement', 'autre'], description: 'Défaut : especes' },
    client_id: { type: 'integer', description: 'Client (optionnel)' },
  }, ['produit_id', 'quantite']),
  async (args, ctx) => {
    const produitId = nb(args.produit_id);
    const quantite = nb(args.quantite);
    if (!Number.isFinite(produitId) || !Number.isFinite(quantite) || quantite <= 0) {
      return echec('Article et quantité (> 0) sont obligatoires.');
    }

    const { data: produit, error } = await ctx.userClient
      .from('produits')
      .select('id, nom, quantite, unite_mesure')
      .eq('id', produitId)
      .maybeSingle();
    verifier(error);
    if (!produit) return echec('Article introuvable.');

    const modes = ['especes', 'mobile_money', 'carte', 'virement', 'autre'];
    const mode = modes.includes(String(args.mode_paiement))
      ? String(args.mode_paiement)
      : 'especes';

    const { data, error: erreurRpc } = await ctx.userClient.rpc('rpc_vente_valider', {
      p_lignes: [{ produit_id: produitId, quantite, quantite_vendue: quantite }],
      p_mode_paiement: mode,
      p_montant_recu: null,
      p_numero_transaction: null,
      p_client_id: args.client_id != null ? nb(args.client_id) : null,
    });
    if (erreurRpc) return echec(messageErreur(erreurRpc));

    return ok({
      numero_vente: data?.numero_vente ?? null,
      total_cdf: data?.total ?? null,
      mode_paiement: mode,
      article: produit.nom,
      quantite,
    });
  },
);

const annulerVente = outil(
  'annuler_vente',
  "ANNULATION d'une vente (propriétaire uniquement) : stock restitué, caisse corrigée, trace CRITIQUE. ACTION SENSIBLE : confirmation obligatoire.",
  obj({
    vente_uuid: { type: 'string', description: 'UUID de la vente (lister_ventes_du_jour le donne)' },
    vente_id: { type: 'integer', description: 'OU identifiant de ligne (une seule vente historique)' },
    raison: { type: 'string', description: "Raison de l'annulation (3 caractères minimum)" },
    confirmation: { type: 'boolean', description: "À mettre à true UNIQUEMENT après accord explicite de l'utilisateur" },
  }, ['raison', 'confirmation']),
  async (args, ctx) => {
    if (args.confirmation !== true) return echec(MSG_CONFIRMATION);
    if (!args.vente_uuid && args.vente_id == null) {
      return echec('Précisez la vente (vente_uuid ou vente_id).');
    }
    const raison = String(args.raison ?? '').trim();
    if (raison.length < 3) return echec('Indiquez la raison (3 caractères minimum).');
    const { data, error } = await ctx.userClient.rpc('rpc_vente_annuler', {
      p_vente_uuid: args.vente_uuid ?? null,
      p_vente_id: args.vente_id != null ? nb(args.vente_id) : null,
      p_raison: raison,
    });
    if (error) return echec(messageErreur(error));
    return ok(data);
  },
  true,
);

const listerVentesDuJour = outil(
  'lister_ventes_du_jour',
  "Ventes d'aujourd'hui (heure de Kinshasa) : nombre, total et dernières ventes.",
  obj({}),
  async (_args, ctx) => {
    const jour = jourKinshasa();
    const bornes = bornesJour(jour);
    return listerVentes(ctx, bornes.debut, bornes.fin, `aujourd'hui (${jour})`);
  },
);

const listerVentesPeriode = outil(
  'lister_ventes_periode',
  'Ventes entre deux dates (AAAA-MM-JJ, bornes incluses).',
  obj({
    date_debut: { type: 'string', description: 'AAAA-MM-JJ' },
    date_fin: { type: 'string', description: 'AAAA-MM-JJ' },
  }, ['date_debut', 'date_fin']),
  async (args, ctx) => {
    const debut = String(args.date_debut ?? '');
    const fin = String(args.date_fin ?? '');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(debut) || !/^\d{4}-\d{2}-\d{2}$/.test(fin)) {
      return echec('Dates attendues au format AAAA-MM-JJ.');
    }
    const { fin: finExclusive } = bornesJour(fin);
    return listerVentes(ctx, bornesJour(debut).debut, finExclusive, `du ${debut} au ${fin}`);
  },
);

// ---------------------------------------------------------------------------
// OUTILS — PRODUITS & STOCK
// ---------------------------------------------------------------------------

const ajouterProduit = outil(
  'ajouter_produit',
  'Crée un article dans le catalogue. Prix de vente obligatoire ; prix d\'achat et stock initial optionnels.',
  obj({
    nom: { type: 'string' },
    categorie: { type: 'string' },
    prix_achat: { type: 'number', description: 'Défaut 0' },
    prix_vente: { type: 'number', description: 'Obligatoire (> 0 conseillé)' },
    quantite: { type: 'number', description: 'Stock initial en unités de base (défaut 0)' },
    unite_mesure: { type: 'string', description: 'Défaut « unité » (ex. pièce, kg, farde)' },
  }, ['nom', 'prix_vente']),
  async (args, ctx) => {
    const nom = String(args.nom ?? '').trim();
    const prixVente = nb(args.prix_vente);
    if (!nom) return echec("Le nom de l'article est obligatoire.");
    if (!Number.isFinite(prixVente) || prixVente < 0) return echec('Prix de vente invalide.');
    const prixAchat = Number.isFinite(nb(args.prix_achat)) ? nb(args.prix_achat) : 0;
    const quantite = Number.isFinite(nb(args.quantite)) ? nb(args.quantite) : 0;
    if (prixAchat < 0 || quantite < 0) return echec('Prix et stock doivent être positifs.');

    const { data, error } = await ctx.userClient
      .from('produits')
      .insert({
        nom,
        categorie: String(args.categorie ?? '').trim(),
        prix_achat: prixAchat,
        prix_vente: prixVente,
        quantite,
        unite_mesure: String(args.unite_mesure ?? 'unité').trim() || 'unité',
        owner_id: ctx.entrepriseId,
      })
      .select('id, nom, prix_vente, quantite')
      .maybeSingle();
    if (error) return echec(messageErreur(error));
    return ok({ article: data });
  },
);

const modifierProduit = outil(
  'modifier_produit',
  "Modifie la fiche d'un article. Le PRIX ne peut être changé que par le propriétaire (verrou serveur) et exige une confirmation.",
  obj({
    produit_id: { type: 'integer' },
    nom: { type: 'string' },
    categorie: { type: 'string' },
    prix_achat: { type: 'number' },
    prix_vente: { type: 'number' },
    unite_mesure: { type: 'string' },
    description: { type: 'string' },
    confirmation: { type: 'boolean', description: 'Obligatoire pour un CHANGEMENT DE PRIX' },
  }, ['produit_id']),
  async (args, ctx) => {
    const maj: Record<string, unknown> = {};
    if (args.nom !== undefined) maj.nom = String(args.nom).trim();
    if (args.categorie !== undefined) maj.categorie = String(args.categorie).trim();
    if (args.unite_mesure !== undefined) maj.unite_mesure = String(args.unite_mesure).trim();
    if (args.description !== undefined) maj.description = String(args.description).trim();
    if (args.prix_achat !== undefined) maj.prix_achat = nb(args.prix_achat);
    if (args.prix_vente !== undefined) maj.prix_vente = nb(args.prix_vente);
    if (Object.keys(maj).length === 0) return echec('Aucun champ à modifier.');

    const touchePrix = maj.prix_achat !== undefined || maj.prix_vente !== undefined;
    if (touchePrix && args.confirmation !== true) {
      return echec(`${MSG_CONFIRMATION} (modification de PRIX = action sensible)`);
    }

    const { data, error } = await ctx.userClient
      .from('produits')
      .update(maj)
      .eq('id', nb(args.produit_id))
      .select('id, nom, prix_achat, prix_vente')
      .maybeSingle();
    if (error) return echec(messageErreur(error));
    return ok({ article: data });
  },
  true,
);

const supprimerProduit = outil(
  'supprimer_produit',
  "SUPPRESSION d'un article du catalogue. ACTION SENSIBLE : confirmation obligatoire. Historique conservé par le journal d'audit.",
  obj({
    produit_id: { type: 'integer' },
    confirmation: { type: 'boolean' },
  }, ['produit_id', 'confirmation']),
  async (args, ctx) => {
    if (args.confirmation !== true) return echec(MSG_CONFIRMATION);

    const { data: produit } = await ctx.userClient
      .from('produits')
      .select('id, nom, quantite')
      .eq('id', nb(args.produit_id))
      .maybeSingle();
    if (!produit) return echec('Article introuvable.');

    const { error } = await ctx.userClient
      .from('produits')
      .delete()
      .eq('id', nb(args.produit_id));
    if (error) return echec(messageErreur(error));
    return ok({ supprime: true, article: produit.nom, stock_restant: produit.quantite });
  },
  true,
);

const consulterStock = outil(
  'consulter_stock',
  "Stock d'un article précis (avec produit_id) ou résumé global : nombre d'articles, alertes, valeur d'achat.",
  obj({ produit_id: { type: 'integer', description: 'Optionnel' } }),
  async (args, ctx) => {
    if (args.produit_id != null) {
      const { data, error } = await ctx.userClient
        .from('produits')
        .select('id, nom, quantite, unite_mesure, seuil_alerte, prix_achat, prix_vente')
        .eq('id', nb(args.produit_id))
        .maybeSingle();
      verifier(error);
      if (!data) return echec('Article introuvable.');
      return ok({ article: data });
    }

    const { data, error } = await ctx.userClient
      .from('produits')
      .select('id, nom, quantite, unite_mesure, seuil_alerte, prix_achat')
      .order('nom')
      .limit(1000);
    verifier(error);

    const articles = data ?? [];
    const alertes = articles.filter(
      (a: Record<string, unknown>) => Number(a.quantite ?? 0) <= Number(a.seuil_alerte ?? 0),
    );
    const valeur = articles.reduce(
      (somme: number, a: Record<string, unknown>) =>
        somme + Number(a.quantite ?? 0) * Number(a.prix_achat ?? 0),
      0,
    );

    return ok({
      nb_articles: articles.length,
      nb_alertes: alertes.length,
      valeur_achat_cdf: Math.round(valeur),
      exemples_alertes: alertes.slice(0, 10).map((a: Record<string, unknown>) => ({
        id: a.id,
        nom: a.nom,
        stock: a.quantite,
        seuil: a.seuil_alerte,
      })),
    });
  },
);

const listerStockFaible = outil(
  'lister_stock_faible',
  "Articles en alerte : stock (unités de base) inférieur ou égal au seuil (seuil personnalisé optionnel, sinon seuil_alerte de chaque article).",
  obj({ seuil: { type: 'number', description: 'Seuil global optionnel' } }),
  async (args, ctx) => {
    const { data, error } = await ctx.userClient
      .from('produits')
      .select('id, nom, quantite, unite_mesure, seuil_alerte')
      .order('quantite')
      .limit(1000);
    verifier(error);

    const seuilGlobal = Number.isFinite(nb(args.seuil)) ? nb(args.seuil) : null;
    const faibles = (data ?? []).filter((a: Record<string, unknown>) => {
      const seuil = seuilGlobal ?? Number(a.seuil_alerte ?? 0);
      return Number(a.quantite ?? 0) <= seuil;
    });

    return ok({
      nb_alertes: faibles.length,
      articles: faibles.slice(0, 30).map((a: Record<string, unknown>) => ({
        id: a.id,
        nom: a.nom,
        stock: a.quantite,
        unite: a.unite_mesure,
        seuil: seuilGlobal ?? a.seuil_alerte,
      })),
    });
  },
);

const ajouterStock = outil(
  'ajouter_stock',
  "Entrée de stock (approvisionnement) : ajoute la quantité au stock de l'article et trace le mouvement.",
  obj({
    produit_id: { type: 'integer' },
    quantite: { type: 'number', description: 'Quantité ajoutée (unités de base), > 0' },
    prix_achat_unitaire: { type: 'number', description: 'Prix d\'achat par unité de base (optionnel)' },
    fournisseur: { type: 'string' },
  }, ['produit_id', 'quantite']),
  async (args, ctx) => {
    const quantite = nb(args.quantite);
    if (!Number.isFinite(quantite) || quantite <= 0) return echec('Quantité invalide.');
    const { data, error } = await ctx.userClient.rpc('rpc_stock_approvisionner', {
      p_produit_id: nb(args.produit_id),
      p_quantite: quantite,
      p_prix_achat_unitaire: Number.isFinite(nb(args.prix_achat_unitaire))
        ? nb(args.prix_achat_unitaire)
        : 0,
      p_fournisseur: args.fournisseur != null ? String(args.fournisseur) : null,
      p_date_approvisionnement: null,
    });
    if (error) return echec(messageErreur(error));
    return ok(data);
  },
);

const ajusterStock = outil(
  'ajuster_stock',
  "AJUSTEMENT d'inventaire : corrige le stock d'un article à une quantité physique constatée (raison obligatoire). ACTION SENSIBLE : confirmation obligatoire.",
  obj({
    produit_id: { type: 'integer' },
    nouvelle_quantite: { type: 'number', description: 'Stock physique constaté (unités de base)' },
    raison: { type: 'string', description: 'Motif (3 caractères minimum)' },
    confirmation: { type: 'boolean' },
  }, ['produit_id', 'nouvelle_quantite', 'raison', 'confirmation']),
  async (args, ctx) => {
    if (args.confirmation !== true) return echec(MSG_CONFIRMATION);
    const raison = String(args.raison ?? '').trim();
    if (raison.length < 3) return echec('Indiquez la raison (3 caractères minimum).');
    const { data, error } = await ctx.userClient.rpc('rpc_stock_ajuster', {
      p_produit_id: nb(args.produit_id),
      p_quantite_physique: nb(args.nouvelle_quantite),
      p_raison: raison,
    });
    if (error) return echec(messageErreur(error));
    return ok(data);
  },
  true,
);

const rechercherProduitParQr = outil(
  'rechercher_produit_par_qr',
  "Retrouve un article à partir d'un code QR scanné (« PROD:123 » ou « COND:<uuid> »).",
  obj({ code_qr: { type: 'string' } }, ['code_qr']),
  async (args, ctx) => {
    const code = String(args.code_qr ?? '').trim();

    let produitId: number | null = null;
    let conditionnement: Record<string, unknown> | null = null;

    if (code.startsWith('PROD:')) {
      produitId = parseInt(code.slice(5), 10);
    } else if (code.startsWith('COND:')) {
      const uuid = code.slice(5);
      const { data, error } = await ctx.userClient
        .from('conditionnements')
        .select('id, produit_id, libelle, quantite_unites_base, prix_vente, qr_code_id')
        .or(`qr_code_id.eq.${uuid},id.eq.${uuid}`)
        .limit(1)
        .maybeSingle();
      verifier(error);
      if (!data) return echec('Conditionnement introuvable pour ce code QR.');
      conditionnement = data;
      produitId = Number(data.produit_id);
    } else {
      produitId = parseInt(code, 10);
    }

    if (!produitId || Number.isNaN(produitId)) return echec('Code QR illisible.');

    const { data: produit, error } = await ctx.userClient
      .from('produits')
      .select('id, nom, categorie, quantite, unite_mesure, prix_vente, seuil_alerte')
      .eq('id', produitId)
      .maybeSingle();
    verifier(error);
    if (!produit) return echec('Article introuvable.');

    return ok({ article: produit, conditionnement });
  },
);

// ---------------------------------------------------------------------------
// OUTILS — FINANCE
// ---------------------------------------------------------------------------

const consulterCaisse = outil(
  'consulter_caisse',
  "Résumé de caisse d'un jour (défaut : aujourd'hui, heure de Kinshasa) : solde, entrées, sorties, opérations.",
  obj({ date: { type: 'string', description: 'AAAA-MM-JJ (optionnel)' } }),
  async (args, ctx) => {
    const date = args.date != null ? String(args.date) : jourKinshasa();
    const { data, error } = await ctx.userClient.rpc('rpc_caisse_resume', { p_date: date });
    if (error) return echec(messageErreur(error));
    return ok(data);
  },
);

const ajouterDepense = outil(
  'ajouter_depense',
  'Enregistre une dépense (sortie de caisse). Demande les droits « depenses/créer ».',
  obj({
    motif: { type: 'string' },
    montant: { type: 'number', description: 'Montant en CDF, > 0' },
    categorie: { type: 'string', description: 'Ex. transport, loyer, ia… (optionnel)' },
  }, ['motif', 'montant']),
  async (args, ctx) => {
    const motif = String(args.motif ?? '').trim();
    const montant = nb(args.montant);
    if (!motif) return echec('Le motif est obligatoire.');
    if (!Number.isFinite(montant) || montant <= 0) return echec('Montant invalide.');
    const { data, error } = await ctx.userClient.rpc('rpc_depense_creer', {
      p_motif: motif,
      p_montant: montant,
      p_categorie: args.categorie != null ? String(args.categorie) : null,
    });
    if (error) return echec(messageErreur(error));
    return ok(data);
  },
);

const listerDepensesPeriode = outil(
  'lister_depenses_periode',
  'Dépenses entre deux dates (AAAA-MM-JJ) : liste et total.',
  obj({
    date_debut: { type: 'string' },
    date_fin: { type: 'string' },
  }, ['date_debut', 'date_fin']),
  async (args, ctx) => {
    const { data, error } = await ctx.userClient.rpc('rpc_depenses_liste', {
      p_debut: String(args.date_debut ?? ''),
      p_fin: String(args.date_fin ?? ''),
      p_limit: 100,
    });
    if (error) return echec(messageErreur(error));
    return ok(data);
  },
);

const consulterDettesClient = outil(
  'consulter_dettes_client',
  'Dettes d\'un client : montants, déjà payé, restant dû et statut de chaque dette.',
  obj({ client_id: { type: 'integer' } }, ['client_id']),
  async (args, ctx) => {
    const clientId = nb(args.client_id);
    const { data: client, error: errClient } = await ctx.userClient
      .from('clients')
      .select('id, nom, telephone')
      .eq('id', clientId)
      .maybeSingle();
    verifier(errClient);
    if (!client) return echec('Client introuvable.');

    const { data, error } = await ctx.userClient
      .from('dettes')
      .select('id, montant_total, montant_paye, statut, date_creation, date_echeance')
      .eq('client_id', clientId)
      .order('date_creation', { ascending: false })
      .limit(50);
    verifier(error);

    return ok({
      client,
      dettes: (data ?? []).map((d: Record<string, unknown>) => ({
        id: d.id,
        montant_total: d.montant_total,
        montant_paye: d.montant_paye,
        restant_du: Math.max(
          Number(d.montant_total ?? 0) - Number(d.montant_paye ?? 0),
          0,
        ),
        statut: d.statut,
        date_echeance: d.date_echeance,
      })),
    });
  },
);

const enregistrerPaiementDette = outil(
  'enregistrer_paiement_dette',
  'Enregistre un paiement sur une dette client (recalcul automatique du solde et du statut).',
  obj({
    dette_id: { type: 'integer' },
    montant: { type: 'number', description: 'Montant payé en CDF, > 0' },
    mode_paiement: { type: 'string', enum: ['especes', 'mobile_money', 'carte', 'virement', 'autre'] },
  }, ['dette_id', 'montant']),
  async (args, ctx) => {
    const montant = nb(args.montant);
    if (!Number.isFinite(montant) || montant <= 0) return echec('Montant invalide.');
    const { data, error } = await ctx.userClient.rpc('rpc_dette_paiement', {
      p_dette_id: nb(args.dette_id),
      p_montant: montant,
      p_mode_paiement: args.mode_paiement != null ? String(args.mode_paiement) : 'especes',
    });
    if (error) return echec(messageErreur(error));
    return ok(data);
  },
);

// ---------------------------------------------------------------------------
// OUTILS — CLIENTS
// ---------------------------------------------------------------------------

const ajouterClient = outil(
  'ajouter_client',
  'Crée un client de la boutique.',
  obj({
    nom: { type: 'string' },
    telephone: { type: 'string' },
    email: { type: 'string' },
  }, ['nom']),
  async (args, ctx) => {
    const nom = String(args.nom ?? '').trim();
    if (!nom) return echec('Le nom du client est obligatoire.');
    const { data, error } = await ctx.userClient
      .from('clients')
      .insert({
        nom,
        telephone: String(args.telephone ?? '').trim(),
        email: String(args.email ?? '').trim(),
        owner_id: ctx.entrepriseId,
      })
      .select('id, nom, telephone')
      .maybeSingle();
    if (error) return echec(messageErreur(error));
    return ok({ client: data });
  },
);

const rechercherClient = outil(
  'rechercher_client',
  'Recherche un client par nom ou téléphone.',
  obj({ query: { type: 'string' } }, ['query']),
  async (args, ctx) => {
    const q = String(args.query ?? '').replace(/[,%]/g, ' ').trim();
    if (!q) return echec('Indiquez le nom ou le téléphone.');
    const { data, error } = await ctx.userClient
      .from('clients')
      .select('id, nom, telephone, email')
      .or(`nom.ilike.%${q}%,telephone.ilike.%${q}%`)
      .order('nom')
      .limit(10);
    verifier(error);
    return ok({ resultats: data ?? [] });
  },
);

const listerClients = outil(
  'lister_clients',
  'Liste les clients de la boutique (50 premiers, par nom).',
  obj({}),
  async (_args, ctx) => {
    const { data, error } = await ctx.userClient
      .from('clients')
      .select('id, nom, telephone')
      .order('nom')
      .limit(50);
    verifier(error);
    return ok({ clients: data ?? [] });
  },
);

// ---------------------------------------------------------------------------
// OUTILS — RAPPORTS
// ---------------------------------------------------------------------------

/** Résume une enveloppe de rapport (totaux + indicateurs, sans le détail). */
function resumeRapport(data: Record<string, unknown> | null): unknown {
  if (!data) return echec('Rapport vide.');
  return ok({
    titre: data.titre,
    debut: data.debut,
    fin: data.fin,
    totaux: data.totaux,
    resume: data.resume,
  });
}

const genererRapportVentes = outil(
  'generer_rapport_ventes',
  "Rapport des ventes par jour, semaine ou mois (défaut : 30 derniers jours).",
  obj({
    date_debut: { type: 'string', description: 'AAAA-MM-JJ (optionnel)' },
    date_fin: { type: 'string', description: 'AAAA-MM-JJ (optionnel)' },
    groupe: { type: 'string', enum: ['jour', 'semaine', 'mois'] },
  }),
  async (args, ctx) => {
    const { data, error } = await ctx.userClient.rpc('rpc_rapport_entreprise', {
      p_type: 'ventes',
      p_debut: args.date_debut != null ? String(args.date_debut) : null,
      p_fin: args.date_fin != null ? String(args.date_fin) : null,
      p_filtres: { groupe: args.groupe != null ? String(args.groupe) : 'jour' },
    });
    if (error) return echec(messageErreur(error));
    return resumeRapport(data);
  },
);

const rapportTopProduits = outil(
  'rapport_top_produits',
  'Articles les plus vendus (par quantité) sur une période.',
  obj({
    date_debut: { type: 'string' },
    date_fin: { type: 'string' },
    limite: { type: 'integer', description: 'Défaut 10 (max 50)' },
  }),
  async (args, ctx) => {
    const limite = Number.isFinite(nb(args.limite))
      ? Math.min(Math.max(nb(args.limite), 1), 50)
      : 10;
    const { data, error } = await ctx.userClient.rpc('rpc_rapport_entreprise', {
      p_type: 'top_produits',
      p_debut: args.date_debut != null ? String(args.date_debut) : null,
      p_fin: args.date_fin != null ? String(args.date_fin) : null,
      p_filtres: { limite },
    });
    if (error) return echec(messageErreur(error));
    if (!data) return echec('Rapport vide.');
    return ok({
      titre: data.titre,
      debut: data.debut,
      fin: data.fin,
      lignes: (data.lignes ?? []).slice(0, 20),
      resume: data.resume,
    });
  },
);

const rapportChiffreAffaires = outil(
  'rapport_chiffre_affaires',
  "Chiffre d'affaires, coût marchandises, dépenses et bénéfice net sur une période (demande « finance/voir »).",
  obj({
    date_debut: { type: 'string' },
    date_fin: { type: 'string' },
  }, ['date_debut', 'date_fin']),
  async (args, ctx) => {
    const { data, error } = await ctx.userClient.rpc('rpc_rapport_entreprise', {
      p_type: 'finance',
      p_debut: String(args.date_debut ?? ''),
      p_fin: String(args.date_fin ?? ''),
      p_filtres: {},
    });
    if (error) return echec(messageErreur(error));
    return resumeRapport(data);
  },
);

const rapportStock = outil(
  'rapport_stock',
  "État du stock : articles, alertes, ruptures et valeur (filtre alerte_seulement possible).",
  obj({
    categorie: { type: 'string' },
    alerte_seulement: { type: 'boolean' },
  }),
  async (args, ctx) => {
    const { data, error } = await ctx.userClient.rpc('rpc_rapport_entreprise', {
      p_type: 'stock',
      p_debut: null,
      p_fin: null,
      p_filtres: {
        categorie: args.categorie != null ? String(args.categorie) : '',
        alerte_seulement: args.alerte_seulement === true,
      },
    });
    if (error) return echec(messageErreur(error));
    return resumeRapport(data);
  },
);

// ---------------------------------------------------------------------------
// OUTILS — COLLABORATEURS
// ---------------------------------------------------------------------------

const listerCollaborateurs = outil(
  'lister_collaborateurs',
  'Liste les membres de l\'entreprise (nom, email, rôle).',
  obj({}),
  async (_args, ctx) => {
    const { data, error } = await ctx.userClient
      .from('utilisateurs')
      .select('id, nom, email, new_role, role, parent_id, entreprise_id')
      .or(
        `id.eq.${ctx.entrepriseId},parent_id.eq.${ctx.entrepriseId},entreprise_id.eq.${ctx.entrepriseId}`,
      )
      .order('nom')
      .limit(50);
    verifier(error);
    return ok({
      collaborateurs: (data ?? []).map((u: Record<string, unknown>) => ({
        id: u.id,
        nom: u.nom,
        email: u.email,
        role: u.new_role ?? u.role ?? '',
      })),
    });
  },
);

const ajouterCollaborateur = outil(
  'ajouter_collaborateur',
  "Crée un COMPTE pour un membre de l'équipe (propriétaire uniquement). Un mot de passe temporaire est généré : l'utilisateur devra le changer. Rôles : vendeur, magasinier, comptable.",
  obj({
    nom: { type: 'string' },
    email: { type: 'string' },
    role: { type: 'string', enum: ['vendeur', 'magasinier', 'comptable'] },
    mot_de_passe: { type: 'string', description: 'Optionnel : mot de passe temporaire à imposer' },
  }, ['nom', 'email', 'role']),
  async (args, ctx) => {
    if (ctx.utilisateur.role !== 'PROPRIETAIRE') {
      return echec('Seul le propriétaire peut créer des comptes collaborateurs.');
    }

    const nom = String(args.nom ?? '').trim();
    const email = String(args.email ?? '').trim().toLowerCase();
    const roleCode = ({
      vendeur: 'VENDEUR',
      magasinier: 'MAGASINIER',
      comptable: 'COMPTABLE_ENTREPRISE',
    } as Record<string, string>)[String(args.role ?? '')];

    if (!nom || !email.includes('@')) return echec('Nom et email valides obligatoires.');
    if (!roleCode) return echec('Rôle inconnu : vendeur, magasinier ou comptable.');

    const motDePasse = String(args.mot_de_passe ?? '').trim() || motDePasseAleatoire();

    const { data: cree, error } = await ctx.admin.auth.admin.createUser({
      email,
      password: motDePasse,
      email_confirm: true,
      user_metadata: {
        nom,
        role: 'collaborator',
        parent_id: ctx.entrepriseId,
      },
    });
    if (error) return echec(messageErreur(error));

    const id = cree?.user?.id as string | undefined;
    if (id) {
      // Profil (le trigger peut l'avoir déjà créé : upsert).
      const { error: errProfil } = await ctx.admin
        .from('utilisateurs')
        .upsert({
          id,
          nom,
          email,
          role: 'collaborator',
          new_role: roleCode,
          valide: 1,
          parent_id: ctx.entrepriseId,
          entreprise_id: ctx.entrepriseId,
        }, { onConflict: 'id' });
      if (errProfil) {
        console.error('agent-ia : profil collaborateur', errProfil.message);
      }
    }

    return ok({
      id,
      nom,
      email,
      role: roleCode,
      mot_de_passe_temporaire: motDePasse,
      message:
        "Compte créé. Transmettez l'email et le mot de passe temporaire au collaborateur (il pourra le changer dans Paramètres).",
    });
  },
);

const modifierRoleCollaborateur = outil(
  'modifier_role_collaborateur',
  "Change le rôle d'un membre de l'équipe (propriétaire uniquement). Rôles : vendeur, magasinier, comptable.",
  obj({
    utilisateur_id: { type: 'string', description: 'UUID du membre (lister_collaborateurs)' },
    nouveau_role: { type: 'string', enum: ['vendeur', 'magasinier', 'comptable'] },
  }, ['utilisateur_id', 'nouveau_role']),
  async (args, ctx) => {
    if (ctx.utilisateur.role !== 'PROPRIETAIRE') {
      return echec('Seul le propriétaire peut changer les rôles.');
    }
    const roleCode = ({
      vendeur: 'VENDEUR',
      magasinier: 'MAGASINIER',
      comptable: 'COMPTABLE_ENTREPRISE',
    } as Record<string, string>)[String(args.nouveau_role ?? '')];
    if (!roleCode) return echec('Rôle inconnu : vendeur, magasinier ou comptable.');

    const utilisateurId = String(args.utilisateur_id ?? '').trim();
    const { data: membre } = await ctx.admin
      .from('utilisateurs')
      .select('id, parent_id, entreprise_id')
      .eq('id', utilisateurId)
      .maybeSingle();
    if (
      !membre ||
      (membre.parent_id !== ctx.entrepriseId && membre.entreprise_id !== ctx.entrepriseId)
    ) {
      return echec('Ce collaborateur n\'appartient pas à votre entreprise.');
    }

    const { error } = await ctx.admin
      .from('utilisateurs')
      .update({ new_role: roleCode })
      .eq('id', utilisateurId);
    if (error) return echec(messageErreur(error));
    return ok({ utilisateur_id: utilisateurId, nouveau_role: roleCode });
  },
);

// ---------------------------------------------------------------------------
// OUTILS — ABONNEMENT
// ---------------------------------------------------------------------------

const voirJoursRestants = outil(
  'voir_jours_restants',
  "Jours restants avant l'expiration de l'abonnement de l'entreprise.",
  obj({}),
  async (_args, ctx) =>
    ok({
      expiration: ctx.entreprise?.date_expiration ?? null,
      jours_restants: joursRestants(ctx.entreprise?.date_expiration),
      statut: ctx.entreprise?.statut ?? null,
    }),
);

const enregistrerPaiementAbonnement = outil(
  'enregistrer_paiement_abonnement',
  "Enregistre un paiement d'abonnement La Perle (personnel plateforme : finance/paiements). Types : AVANCE, SOLDE, RENOUVELLEMENT.",
  obj({
    montant: { type: 'number', description: 'Montant en CDF, > 0' },
    type_paiement: { type: 'string', enum: ['AVANCE', 'SOLDE', 'RENOUVELLEMENT'] },
    entreprise_id: { type: 'string', description: "UUID de l'entreprise (obligatoire pour le personnel plateforme)" },
    mode_paiement: { type: 'string' },
    note: { type: 'string' },
  }, ['montant']),
  async (args, ctx) => {
    const montant = nb(args.montant);
    if (!Number.isFinite(montant) || montant <= 0) return echec('Montant invalide.');
    const entrepriseId = args.entreprise_id != null
      ? String(args.entreprise_id)
      : ctx.entrepriseId;
    const { data, error } = await ctx.userClient.rpc(
      'rpc_abonnement_enregistrer_paiement',
      {
        p_entreprise_id: entrepriseId,
        p_montant: montant,
        p_type_paiement: args.type_paiement != null
          ? String(args.type_paiement).toUpperCase()
          : 'AVANCE',
        p_mode_paiement: args.mode_paiement != null ? String(args.mode_paiement) : null,
        p_note: args.note != null ? String(args.note) : null,
      },
    );
    if (error) return echec(messageErreur(error));
    return ok(data);
  },
);

// ---------------------------------------------------------------------------
// OUTILS — QR CODES
// ---------------------------------------------------------------------------

/** ÉTIQUETTES (codes) d'une liste d'articles — outil interne partagé. */
async function etiquettesArticles(
  ctx: ContexteOutil,
  produitIds: number[],
): Promise<unknown> {
  if (produitIds.length === 0) return echec('Aucun article indiqué.');
  if (produitIds.length > 20) return echec('20 articles maximum par demande.');

  const { data: produits, error } = await ctx.userClient
    .from('produits')
    .select('id, nom')
    .in('id', produitIds);
  verifier(error);

  const { data: conditionnements } = await ctx.userClient
    .from('conditionnements')
    .select('id, produit_id, libelle, qr_code_id')
    .in('produit_id', produitIds);

  const parProduit = new Map<number, string[]>();
  for (const c of conditionnements ?? []) {
    const liste = parProduit.get(c.produit_id) ?? [];
    liste.push(`COND:${c.qr_code_id} (${c.libelle})`);
    parProduit.set(c.produit_id, liste);
  }

  return ok({
    etiquettes: (produits ?? []).map((p: Record<string, unknown>) => ({
      produit: p.nom,
      codes: [`PROD:${p.id}`, ...(parProduit.get(p.id as number) ?? [])],
    })),
    note:
      "L'impression se fait depuis l'écran « QR codes » de l'application (PNG, SVG ou planche PDF).",
  });
}

const genererQrProduit = outil(
  'generer_qr_produit',
  "Prépare les codes QR d'un article (article + conditionnements) pour impression.",
  obj({ produit_id: { type: 'integer' } }, ['produit_id']),
  async (args, ctx) => etiquettesArticles(ctx, [nb(args.produit_id)]),
);

const imprimerEtiquettes = outil(
  'imprimer_etiquettes',
  "Prépare les étiquettes de plusieurs articles (max 20) — l'impression s'ouvre dans l'écran QR codes.",
  obj({
    produit_ids: { type: 'array', items: { type: 'integer' }, description: 'Identifiants des articles' },
  }, ['produit_ids']),
  async (args, ctx) => {
    const ids = Array.isArray(args.produit_ids)
      ? (args.produit_ids as unknown[]).map((v) => nb(v)).filter(Number.isFinite)
      : [];
    return etiquettesArticles(ctx, ids);
  },
);

// ---------------------------------------------------------------------------
// OUTILS — INFORMATIONS
// ---------------------------------------------------------------------------

const statistiquesGlobales = outil(
  'statistiques_globales',
  "Statistiques de la plateforme (personnel La Perle uniquement) : entreprises, utilisateurs, ventes du jour.",
  obj({}),
  async (_args, ctx) => {
    const rolesPlateforme = [
      'SUPER_ADMIN',
      'GESTIONNAIRE_COMPTES',
      'FINANCE_LAPERLE',
      'SUPPORT',
    ];
    if (!rolesPlateforme.includes(ctx.utilisateur.role)) {
      return echec('Réservé au personnel de la plateforme.');
    }

    const [entreprises, utilisateurs] = await Promise.all([
      ctx.userClient.from('entreprises').select('id', { count: 'exact', head: true }),
      ctx.userClient.from('utilisateurs').select('id', { count: 'exact', head: true }),
    ]);

    const bornes = bornesJour(jourKinshasa());
    const { data: ventesJour } = await ctx.userClient
      .from('ventes')
      .select('prix')
      .gte('date', bornes.debut)
      .lt('date', bornes.fin)
      .limit(2000);

    return ok({
      entreprises: entreprises.count ?? null,
      utilisateurs: utilisateurs.count ?? null,
      ventes_du_jour_cdf: (ventesJour ?? []).reduce(
        (somme: number, v: { prix: unknown }) => somme + Number(v.prix ?? 0),
        0,
      ),
    });
  },
);

// ---------------------------------------------------------------------------
// REGISTRE FINAL DES OUTILS
// ---------------------------------------------------------------------------
//  ⚠️ Toute modification du registre doit être répercutée dans le prompt
//  système (liste des capacités) — et re-déployée sur Supabase (Éditeur).

const OUTILS: OutilAgent[] = [
  // Ventes
  rechercherProduit,
  creerVente,
  annulerVente,
  listerVentesDuJour,
  listerVentesPeriode,
  // Produits & stock
  ajouterProduit,
  modifierProduit,
  supprimerProduit,
  consulterStock,
  listerStockFaible,
  ajouterStock,
  ajusterStock,
  rechercherProduitParQr,
  // Finance
  consulterCaisse,
  ajouterDepense,
  listerDepensesPeriode,
  consulterDettesClient,
  enregistrerPaiementDette,
  // Clients
  ajouterClient,
  rechercherClient,
  listerClients,
  // Rapports
  genererRapportVentes,
  rapportTopProduits,
  rapportChiffreAffaires,
  rapportStock,
  // Collaborateurs
  listerCollaborateurs,
  ajouterCollaborateur,
  modifierRoleCollaborateur,
  // Abonnement
  consulterAbonnement,
  voirJoursRestants,
  enregistrerPaiementAbonnement,
  // QR codes
  genererQrProduit,
  imprimerEtiquettes,
  // Informations
  informationsEntreprise,
  statistiquesGlobales,
];

// ---------------------------------------------------------------------------
// HELPERS
// ---------------------------------------------------------------------------

/** Réponse JSON homogène (avec CORS). */
function json(donnees: unknown, status = 200): Response {
  return new Response(JSON.stringify(donnees), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}

/** Réponse d'erreur normalisée, consommable telle quelle par l'application. */
function erreur(
  code: string,
  message: string,
  status: number,
  extra: Record<string, unknown> = {},
): Response {
  return json({ erreur: code, message, ...extra }, status);
}

/** Nombre de caractères « utiles » (points de code Unicode, pas octets). */
function nombreCaracteres(texte: string): number {
  return Array.from(texte).length;
}

/** Jours restants avant une date d'expiration (`null` si non renseignée). */
function joursRestants(dateExpiration: string | null | undefined): number | null {
  if (!dateExpiration) return null;
  const fin = new Date(dateExpiration).getTime();
  if (Number.isNaN(fin)) return null;
  return Math.max(Math.ceil((fin - Date.now()) / 86_400_000), 0);
}

/**
 * État d'abonnement — MÊME logique que `public.abonnement_etat()` (Module 12)
 * mais recalculée ici car la fonction SQL n'est pas exécutable par les
 * clients (droits volontairement réservés). FAIL-OPEN : entreprise inconnue
 * → 'OK' (on ne bloque jamais l'activité sur un incident de lecture).
 */
function etatAbonnement(entreprise: EntrepriseInfo | null): 'OK' | 'LECTURE_SEULE' | 'BLOQUE' {
  if (!entreprise) return 'OK';

  const statut = (entreprise.statut ?? '').toString().toUpperCase();
  if (statut === 'SUSPENDU') return 'BLOQUE';
  if (statut === 'EXPIRE' || statut === 'EN_ATTENTE_COMPLEMENT') {
    return 'LECTURE_SEULE';
  }
  if (entreprise.date_expiration) {
    const fin = new Date(entreprise.date_expiration).getTime();
    if (!Number.isNaN(fin) && fin < Date.now()) return 'LECTURE_SEULE';
  }
  return 'OK';
}

/** Prompt système de l'assistant (Partie 9 du cahier des charges). */
function promptSysteme(ctx: {
  nom: string;
  role: string;
  entreprise: string;
  activite: string;
  quotas: number;
}): string {
  const jour = new Date().toISOString().slice(0, 10);
  return [
    "Tu es l'assistant IA officiel de BiasharaYangu, une plateforme de gestion",
    'commerciale multisecteur (pharmacies, boutiques, restaurants, hôtels, etc.).',
    '',
    'CONTEXTE UTILISATEUR :',
    `- Nom : ${ctx.nom}`,
    `- Rôle : ${ctx.role}`,
    `- Entreprise : ${ctx.entreprise}`,
    `- Activité : ${ctx.activite}`,
    `- Solde quotas : ${ctx.quotas}`,
    `- Date du jour : ${jour}`,
    '',
    'RÈGLES :',
    '- Réponds toujours en français, de manière concise et professionnelle.',
    "- Utilise les outils à ta disposition pour exécuter des actions ; ne JAMAIS",
    '  inventer de données : utilise les outils.',
    '- Si une action échoue, explique pourquoi clairement et propose une',
    '  alternative si possible.',
    '- AVANT toute action destructive (supprimer un article, annuler une vente,',
    "  modifier un prix, ajuster un stock), tu DOIS : (1) expliquer ce que tu vas",
    '  faire, (2) demander une confirmation écrite à l\'utilisateur, (3) APRÈS',
    "  son accord, rappeler l'outil avec confirmation=true. Sans cet accord,",
    '  les outils destructifs refusent de s\'exécuter (les outils sensibles',
    '  exigeront une confirmation).',
    '- Pour les prix, rappelle que seul le propriétaire peut les modifier.',
    "- Si l'utilisateur demande de nouveaux quotas : explique qu'il peut demander",
    '  un pack (écran « Acheter des quotas ») que le Super Admin valide.',
    "- Sois BREF : chaque caractère de ta réponse est facturé à l'utilisateur",
    '  (1 quota ≈ 20 caractères). Va droit au but, sans remplissage.',
    "- Adapte ton langage au rôle : un caissier (VENDEUR) ou un magasinier reçoit",
    '  des réponses simples ; un comptable, des réponses plus précises.',
    '- Si un outil refuse à cause des permissions de l\'utilisateur, dis-le',
    "  simplement et propose l'écran adapté.",
    '',
    'CAPACITÉS (selon les droits du rôle) : ventes (vendre, annuler,',
    'consulter), produits & stock (ajouter, modifier, approvisionner, ajuster),',
    'finance (caisse, dépenses, dettes), clients, rapports (ventes, top',
    'produits, chiffre d\'affaires, stock), collaborateurs (le propriétaire),',
    'abonnement (personnel plateforme), QR codes, informations entreprise.',
  ].join('\n');
}

/**
 * Consommation RÉELLE renvoyée par DeepSeek pour un appel.
 *
 * `entreeCache` est un SOUS-ENSEMBLE de `entree` : ce sont les tokens servis
 * depuis le cache DeepSeek, facturés environ 50 fois moins cher. Pour la
 * comptabilité on isole donc `entreeNonCachee = entree - entreeCache`.
 */
interface UsageDeepSeek {
  entree: number;
  entreeCache: number;
  sortie: number;
  total: number;
}

const USAGE_VIDE: UsageDeepSeek = { entree: 0, entreeCache: 0, sortie: 0, total: 0 };

function cumulerUsage(a: UsageDeepSeek, b: UsageDeepSeek): UsageDeepSeek {
  return {
    entree: a.entree + b.entree,
    entreeCache: a.entreeCache + b.entreeCache,
    sortie: a.sortie + b.sortie,
    total: a.total + b.total,
  };
}

/** Appel HTTP à l'API DeepSeek (OpenAI-compatible). */
async function appelerDeepSeek(messages: MessageDeepSeek[]): Promise<{
  message: MessageDeepSeek;
  usage: UsageDeepSeek;
}> {
  const corps: Record<string, unknown> = {
    model: MODELE,
    messages,
    max_tokens: MAX_TOKENS_REPONSE,
    temperature: 0.3,
    stream: false,
  };

  if (OUTILS.length > 0) {
    corps.tools = OUTILS.map((o) => ({
      type: 'function',
      function: o.definition,
    }));
    corps.tool_choice = 'auto';
  }

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
  const message: MessageDeepSeek | undefined = donnees?.choices?.[0]?.message;
  if (!message) {
    throw new Error('DeepSeek : réponse sans message.');
  }

  // Consommation réelle : DeepSeek détaille entrée / cache / sortie.
  const u = donnees?.usage ?? {};
  const entree = Number(u.prompt_tokens ?? 0);
  const entreeCache = Number(
    u.prompt_cache_hit_tokens ?? u.prompt_tokens_details?.cached_tokens ?? 0,
  );
  const sortie = Number(u.completion_tokens ?? 0);

  return {
    message,
    usage: {
      entree,
      entreeCache: Math.min(Math.max(entreeCache, 0), entree),
      sortie,
      total: Number(u.total_tokens ?? entree + sortie),
    },
  };
}

// ---------------------------------------------------------------------------
// TRAITEMENT PRINCIPAL
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  // — CORS préalable (appels web) et méthode —
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS });
  }
  if (req.method !== 'POST') {
    return erreur('METHODE_INVALIDE', 'Utilisez POST.', 405);
  }

  try {
    // =======================================================================
    // 0. CONFIGURATION SERVEUR
    // =======================================================================
    if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SERVICE_ROLE_KEY) {
      return erreur(
        'CONFIG_MANQUANTE',
        'La fonction n\'est pas correctement configurée (variables Supabase).',
        500,
      );
    }
    if (!DEEPSEEK_API_KEY) {
      return erreur(
        'SECRET_MANQUANT',
        'Le secret DEEPSEEK_API_KEY n\'est pas configuré (Supabase → Edge Functions → Secrets).',
        503,
      );
    }

    // =======================================================================
    // 1. JWT UTILISATEUR
    // =======================================================================
    const enteteAuth = req.headers.get('Authorization') ?? '';
    if (!enteteAuth.startsWith('Bearer ')) {
      return erreur(
        'SESSION_ABSENTE',
        'Connectez-vous pour utiliser l\'assistant.',
        401,
      );
    }

    // Deux clients :
    //   • `userClient` porte le JWT de l'utilisateur → les outils s'exécutent
    //     avec SES droits (RLS + `peut(...)` côté RPC : jamais de passe-droit) ;
    //   • `admin` (service_role) → réservé aux compteurs, quotas, journal.
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: enteteAuth } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: donneesAuth, error: erreurAuth } = await userClient.auth.getUser();
    const utilisateur = donneesAuth?.user;
    if (erreurAuth || !utilisateur) {
      return erreur(
        'SESSION_ABSENTE',
        'Session invalide ou expirée : reconnectez-vous.',
        401,
      );
    }

    // =======================================================================
    // MESSAGE ENTRANT
    // =======================================================================
    const corps = await req.json().catch(() => null) as
      | { message?: unknown }
      | null;
    const message = (corps?.message ?? '').toString().trim();

    if (!message) {
      return erreur('MESSAGE_VIDE', 'Écrivez votre demande.', 400);
    }
    if (nombreCaracteres(message) > MAX_MESSAGE_UTILISATEUR) {
      return erreur(
        'MESSAGE_TROP_LONG',
        `Message trop long (${MAX_MESSAGE_UTILISATEUR} caractères maximum).`,
        400,
      );
    }

    // =======================================================================
    // 2. CONFIGURATION IA
    // =======================================================================
    const { data: configBrute } = await admin
      .from('agent_ia_config')
      .select(
        'tarif_par_quota, caracteres_par_quota, prix_pack_10_quotas, quotas_offerts_inscription, actif',
      )
      .limit(1)
      .maybeSingle();

    if (!configBrute) {
      return erreur(
        'ASSISTANT_INDISPONIBLE',
        'La configuration de l\'assistant est absente (migration Module 13 non exécutée ?).',
        503,
      );
    }
    if (configBrute.actif !== true) {
      return erreur(
        'ASSISTANT_DESACTIVE',
        'L\'assistant IA est temporairement désactivé par l\'administrateur.',
        403,
      );
    }

    const config: ConfigAgent = {
      tarif_par_quota: Number(configBrute.tarif_par_quota ?? 150),
      caracteres_par_quota: Math.max(
        1,
        Number(configBrute.caracteres_par_quota ?? 20),
      ),
      prix_pack_10_quotas: Number(configBrute.prix_pack_10_quotas ?? 1000),
      quotas_offerts_inscription: Number(
        configBrute.quotas_offerts_inscription ?? 0,
      ),
      actif: true,
    };

    // — Profil + entreprise (le patron = propriétaire pour les collaborateurs) —
    const { data: profil } = await admin
      .from('utilisateurs')
      .select('id, nom, email, new_role, role, parent_id, entreprise_id')
      .eq('id', utilisateur.id)
      .maybeSingle();

    const entrepriseId = (profil?.entreprise_id ??
      profil?.parent_id ??
      utilisateur.id) as string;

    const { data: entrepriseBrute } = await admin
      .from('entreprises')
      .select(
        'id, nom, statut, date_expiration, montant_total_du, montant_deja_paye, solde_restant, activite_id',
      )
      .eq('id', entrepriseId)
      .maybeSingle();

    const entreprise: EntrepriseInfo | null = entrepriseBrute
      ? {
        id: entrepriseBrute.id,
        nom: entrepriseBrute.nom ?? '',
        statut: entrepriseBrute.statut ?? null,
        date_expiration: entrepriseBrute.date_expiration ?? null,
        montant_total_du: entrepriseBrute.montant_total_du ?? null,
        montant_deja_paye: entrepriseBrute.montant_deja_paye ?? null,
        solde_restant: entrepriseBrute.solde_restant ?? null,
        activite_id: entrepriseBrute.activite_id ?? null,
      }
      : null;

    let activite: string | null = null;
    if (entreprise?.activite_id) {
      const { data: activiteBrute } = await admin
        .from('activites')
        .select('nom')
        .eq('id', entreprise.activite_id)
        .maybeSingle();
      activite = activiteBrute?.nom ?? null;
    }

    const utilisateurContexte: UtilisateurContexte = {
      id: utilisateur.id,
      nom: (profil?.nom ?? utilisateur.email ?? '').toString(),
      email: (profil?.email ?? utilisateur.email ?? '').toString(),
      role: (
        profil?.new_role ??
        profil?.role ??
        'INCONNU'
      ).toString().toUpperCase(),
    };

    // =======================================================================
    // 3. ABONNEMENT — vérification À CHAQUE message (middleware global)
    // =======================================================================
    const etat = etatAbonnement(entreprise);
    if (etat === 'BLOQUE') {
      return erreur(
        'ABONNEMENT_BLOQUE',
        'Votre abonnement est suspendu. Régularisez votre situation pour ' +
          'utiliser l\'assistant.',
        403,
      );
    }
    if (etat === 'LECTURE_SEULE') {
      return erreur(
        'ABONNEMENT_EXPIRE',
        'Votre abonnement est expiré (lecture seule). Renouvelez pour ' +
          'utiliser l\'assistant.',
        403,
      );
    }

    // =======================================================================
    // 4. SOLDE DE QUOTAS (> 0) — AVANT tout appel DeepSeek
    // =======================================================================
    const { data: ligneQuotas } = await admin
      .from('agent_ia_quotas')
      .select('quotas_disponibles, quotas_utilises_total')
      .eq('utilisateur_id', utilisateur.id)
      .maybeSingle();

    const soldeDisponible = Number(ligneQuotas?.quotas_disponibles ?? 0);
    if (!ligneQuotas || soldeDisponible <= 0) {
      return erreur(
        'QUOTAS_EPUISES',
        'Votre solde de quotas est épuisé. Demandez un pack de quotas à ' +
          'votre responsable, ou achetez-en depuis l\'écran « Acheter des quotas ».',
        402,
        {
          solde: soldeDisponible,
          tarif_par_quota: config.tarif_par_quota,
          prix_pack_10_quotas: config.prix_pack_10_quotas,
        },
      );
    }

    // =======================================================================
    // 5. RATE LIMITING — 30 messages/h et 5000 caractères de réponse/h
    // =======================================================================
    const ilYAUneHeure = new Date(Date.now() - 3_600_000).toISOString();

    const { count: nbMessagesHeure } = await admin
      .from('agent_ia_conversations')
      .select('id', { count: 'exact', head: true })
      .eq('utilisateur_id', utilisateur.id)
      .eq('role', 'user')
      .gte('created_at', ilYAUneHeure);

    if ((nbMessagesHeure ?? 0) >= MAX_MESSAGES_PAR_HEURE) {
      return erreur(
        'LIMITE_MESSAGES',
        `Limite atteinte : ${MAX_MESSAGES_PAR_HEURE} messages par heure. ` +
          'Réessayez dans quelques minutes.',
        429,
      );
    }

    const { data: reponsesHeure } = await admin
      .from('agent_ia_conversations')
      .select('contenu')
      .eq('utilisateur_id', utilisateur.id)
      .eq('role', 'assistant')
      .gte('created_at', ilYAUneHeure);

    const caracteresHeure = (reponsesHeure ?? []).reduce(
      (total: number, ligne: { contenu: string | null }) =>
        total + nombreCaracteres(ligne.contenu ?? ''),
      0,
    );

    if (caracteresHeure >= MAX_CARACTERES_REPONSE_PAR_HEURE) {
      return erreur(
        'LIMITE_CARACTERES',
        `Limite atteinte : ${MAX_CARACTERES_REPONSE_PAR_HEURE} caractères de ` +
          'réponse par heure. Réessayez dans quelques minutes.',
        429,
      );
    }

    // =======================================================================
    // 6. HISTORIQUE RÉCENT + ENREGISTREMENT DU MESSAGE ENTRANT
    // =======================================================================
    const { data: historiqueBrut } = await admin
      .from('agent_ia_conversations')
      .select('role, contenu, created_at')
      .eq('utilisateur_id', utilisateur.id)
      .in('role', ['user', 'assistant'])
      .order('created_at', { ascending: false })
      .limit(NB_MESSAGES_CONTEXTE);

    const historique: MessageDeepSeek[] = (historiqueBrut ?? [])
      .slice()
      .reverse()
      .filter((ligne: { contenu: string | null }) =>
        (ligne.contenu ?? '').toString().trim().length > 0
      )
      .map((ligne: { role: string; contenu: string | null }) => ({
        role: ligne.role === 'assistant' ? 'assistant' : 'user',
        content: (ligne.contenu ?? '').toString(),
      }));

    await admin.from('agent_ia_conversations').insert({
      utilisateur_id: utilisateur.id,
      entreprise_id: entrepriseId,
      role: 'user',
      contenu: message,
    });

    // =======================================================================
    // 7-9. DEEPSEEK + BOUCLE D'OUTILS
    // =======================================================================
    const contexteOutil: ContexteOutil = {
      userClient,
      admin,
      utilisateur: utilisateurContexte,
      entrepriseId,
      entreprise,
      activite,
      config,
      soldeQuotas: soldeDisponible,
    };

    const messages: MessageDeepSeek[] = [
      {
        role: 'system',
        content: promptSysteme({
          nom: utilisateurContexte.nom || utilisateurContexte.email,
          role: utilisateurContexte.role,
          entreprise: entreprise?.nom ?? '—',
          activite: activite ?? '—',
          quotas: soldeDisponible,
        }),
      },
      ...historique,
      { role: 'user', content: message },
    ];

    const actionsExecutees: ActionExecutee[] = [];
    let reponseTexte = '';
    let tokensTotal = 0;
    let usageCumule: UsageDeepSeek = USAGE_VIDE;

    for (let tour = 0; tour < MAX_TOURS_OUTILS; tour++) {
      const { message: messageAssistant, usage } = await appelerDeepSeek(
        messages,
      );
      tokensTotal += usage.total;
      usageCumule = cumulerUsage(usageCumule, usage);

      const appels = messageAssistant.tool_calls ?? [];

      // — Pas d'outil demandé : c'est la réponse finale. —
      if (appels.length === 0) {
        reponseTexte = (messageAssistant.content ?? '').toString().trim();
        break;
      }

      // — Outils demandés : on exécute côté serveur puis on re-boucle. —
      messages.push({
        role: 'assistant',
        content: messageAssistant.content ?? null,
        tool_calls: appels,
      });

      for (const appel of appels) {
        const nomOutil = appel.function?.name ?? '';
        let parametres: Record<string, unknown> = {};
        try {
          parametres = JSON.parse(appel.function?.arguments ?? '{}');
        } catch (_) {
          parametres = {};
        }

        const outil = OUTILS.find((o) => o.definition.name === nomOutil);
        let resultat: unknown;
        let succes = true;

        if (!outil) {
          succes = false;
          resultat = { ok: false, erreur: `Outil inconnu : ${nomOutil}` };
        } else {
          try {
            resultat = await outil.executer(parametres, contexteOutil);
          } catch (e) {
            succes = false;
            resultat = {
              ok: false,
              erreur: `Échec de l'outil : ${
                e instanceof Error ? e.message : String(e)
              }`,
            };
            console.error(`agent-ia : outil ${nomOutil} en échec`, e);
          }
        }

        actionsExecutees.push({ outil: nomOutil, succes });

        // 12.a — traçabilité de CHAQUE outil exécuté (best-effort).
        try {
          await admin.from('agent_ia_actions').insert({
            utilisateur_id: utilisateur.id,
            entreprise_id: entrepriseId,
            outil: nomOutil,
            parametres,
            resultat: resultat as Record<string, unknown>,
            succes,
            quotas_consommes: 0, // les quotas sont facturés sur la réponse finale
          });
        } catch (e) {
          console.error('agent-ia : journalisation agent_ia_actions', e);
        }

        messages.push({
          role: 'tool',
          tool_call_id: appel.id,
          content: JSON.stringify(resultat),
        });
      }
    }

    if (!reponseTexte) {
      reponseTexte =
        'Je n\'ai pas pu terminer la demande pour le moment. Reformulez ou réessayez.';
    }

    // =======================================================================
    // 10. FACTURATION — 1 quota = `caracteres_par_quota` caractères (min 1)
    // =======================================================================
    const nbCaracteres = nombreCaracteres(reponseTexte);
    const quotasConsommes = Math.max(
      1,
      Math.ceil(nbCaracteres / config.caracteres_par_quota),
    );
    const montantCdf = quotasConsommes * config.tarif_par_quota;

    // =======================================================================
    // 11. DÉBIT ATOMIQUE DU SOLDE (service_role)
    // =======================================================================
    let soldeRestant = Math.max(soldeDisponible - quotasConsommes, 0);
    try {
      const { data: debit, error: erreurDebit } = await admin.rpc(
        'rpc_agent_ia_debiter',
        { p_utilisateur: utilisateur.id, p_quotas: quotasConsommes },
      );
      if (erreurDebit) {
        console.error('agent-ia : débit des quotas', erreurDebit.message);
      } else if (debit && typeof debit.solde === 'number') {
        soldeRestant = Number(debit.solde);
        if (debit.ok !== true) {
          console.error('agent-ia : quota insuffisant au moment du débit', debit);
        }
      }
    } catch (e) {
      console.error('agent-ia : débit impossible', e);
    }

    // =======================================================================
    // 11.b — COMPTABILITÉ RÉELLE (tokens + coût DeepSeek + marge)
    // =======================================================================
    //  Alimente `agent_ia_usage` : c'est ce qui permet au Super Admin de
    //  vérifier la marge réellement réalisée et d'estimer les questions
    //  restantes selon le solde DeepSeek. Best-effort : une panne de
    //  comptabilité ne doit jamais empêcher la réponse à l'utilisateur.
    try {
      const { data: compta, error: erreurCompta } = await admin.rpc(
        'rpc_ia_usage_enregistrer',
        {
          p_entreprise: entrepriseId,
          p_utilisateur: utilisateur.id,
          p_source: 'agent-ia',
          p_modele: MODELE,
          p_tokens_entree: usageCumule.entree,
          p_tokens_cache: usageCumule.entreeCache,
          p_tokens_sortie: usageCumule.sortie,
          p_quotas_debites: quotasConsommes,
          p_montant_cdf: montantCdf,
        },
      );
      if (erreurCompta) {
        console.error('agent-ia : comptabilité des tokens', erreurCompta.message);
      } else if (compta && typeof compta === 'object') {
        console.log(
          `agent-ia : comptabilité — coût ${(compta as Record<string, unknown>).cout_cdf} CDF, ` +
            `facturé ${(compta as Record<string, unknown>).montant_cdf} CDF`,
        );
      }
    } catch (e) {
      console.error('agent-ia : comptabilité impossible', e);
    }

    // =======================================================================
    // 12. TRAÇABILITÉ COMPLÈTE + RÉPONSE
    // =======================================================================

    // 12.b — la réponse assistant (avec ses quotas).
    try {
      await admin.from('agent_ia_conversations').insert({
        utilisateur_id: utilisateur.id,
        entreprise_id: entrepriseId,
        role: 'assistant',
        contenu: reponseTexte,
        quotas_consommes: quotasConsommes,
        action_executee: actionsExecutees.length > 0
          ? actionsExecutees.map((a) => a.outil).join(', ')
          : null,
      });
    } catch (e) {
      console.error('agent-ia : journalisation conversation', e);
    }

    // 12.c — trace dans le journal d'audit global (niveau MOYEN).
    try {
      await admin.from('journal_audit').insert({
        entreprise_id: null,
        action: 'AGENT_IA',
        niveau: 'MOYEN',
        utilisateur_id: utilisateur.id,
        details: {
          outils: actionsExecutees.map((a) => a.outil),
          quotas_consommes: quotasConsommes,
          montant_cdf: montantCdf,
          caracteres_reponse: nbCaracteres,
          tokens: tokensTotal,
          tokens_entree: usageCumule.entree,
          tokens_entree_cache: usageCumule.entreeCache,
          tokens_sortie: usageCumule.sortie,
          boutique: entrepriseId,
          portee: 'entreprise',
        },
      });
    } catch (e) {
      console.error('agent-ia : trace journal_audit', e);
    }

    // 12.d — réponse à l'application (forme stable pour le service Flutter).
    return json({
      reponse: reponseTexte,
      quotas_consommes: quotasConsommes,
      montant_cdf: montantCdf,
      solde_restant: soldeRestant,
      caracteres_reponse: nbCaracteres,
      actions: actionsExecutees,
    });
  } catch (e) {
    console.error('agent-ia : erreur interne', e);
    return erreur(
      'ERREUR_INTERNE',
      'Une erreur interne est survenue. Réessayez dans un instant.',
      500,
    );
  }
});
