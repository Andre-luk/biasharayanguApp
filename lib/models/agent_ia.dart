// lib/models/agent_ia.dart
//
// MODULE 13 — MODÈLES DE L'ASSISTANT IA (DEEPSEEK).
//
// Objets de valeur purs (aucun import Flutter, aucun accès réseau) :
//   • [AgentIaConfig]  — réglages (tarif/quota, taille d'un quota, pack, etc.) ;
//   • [PackQuotas]     — les 4 packs officiels (10 · 20 · 50 · 100 quotas) ;
//   • [SoldeQuotas]    — une ligne de soldes (pool entreprise ou utilisateur) ;
//   • [MembreQuota]    — collaborateur auquel le patron attribue des quotas ;
//   • [EtatAgentIa]    — réponse de `rpc_agent_ia_etat` (soldes + droits) ;
//   • [AchatQuotas]    — une demande/achat de pack (montant TOUJOURS affiché,
//                        payé ou impayé — exigence métier) ;
//   • [ActionAgent] / [ReponseAgent] — réponse de l'Edge Function `agent-ia`.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Réglages de l'assistant IA (`public.agent_ia_config`).
class AgentIaConfig {
  const AgentIaConfig({
    required this.tarifParQuota,
    required this.caracteresParQuota,
    required this.prixPack10Quotas,
    required this.quotasOffertsInscription,
    required this.actif,
    this.tauxMarge = 16,
    this.tauxUsdCdf = 2800,
    this.coutCdfParMillionEntree = 840,
    this.coutCdfParMillionCache = 16.8,
    this.coutCdfParMillionSortie = 3360,
    this.soldeDeepseekUsd = 0,
    this.alerteSoldeUsd = 1,
  });

  /// CDF facturés par quota consommé (1 à 1000 depuis le module 13 bis).
  final double tarifParQuota;

  /// Nombre de caractères de réponse comptant pour 1 quota (défaut 400).
  final int caracteresParQuota;

  /// Prix du pack de 10 quotas (les autres packs sont proportionnels).
  final double prixPack10Quotas;

  /// Quotas offerts une fois par entreprise (bonus de bienvenue).
  final int quotasOffertsInscription;

  /// Assistant actif ou non (réglage Super Admin).
  final bool actif;

  /// Coefficient de marge appliqué au coût réel DeepSeek (16 par défaut).
  final double tauxMarge;

  /// Change appliqué aux conversions dollar ↔ franc congolais.
  final double tauxUsdCdf;

  /// Coût CDF d'un million de tokens d'entrée NON cachés (tarif de pointe).
  final double coutCdfParMillionEntree;

  /// Coût CDF d'un million de tokens d'entrée CACHÉS (≈ 50 fois moins cher).
  final double coutCdfParMillionCache;

  /// Coût CDF d'un million de tokens de sortie.
  final double coutCdfParMillionSortie;

  /// Crédit DeepSeek restant, en dollars (saisi par les recharges).
  final double soldeDeepseekUsd;

  /// Seuil sous lequel le tableau de bord affiche une alerte de recharge.
  final double alerteSoldeUsd;

  /// Prix d'un caractère de réponse (CDF) : tarif / taille d'un quota.
  double get prixParCaractere =>
      caracteresParQuota > 0 ? tarifParQuota / caracteresParQuota : 0;

  /// Coût réel estimé d'une question (6 CDF par défaut, mesure de référence).
  static const double coutQuestionReferenceCdf = 6;

  /// Valeurs de repli — mêmes défauts que la migration 52 (module 13 bis).
  static const AgentIaConfig defaut = AgentIaConfig(
    tarifParQuota: 96,
    caracteresParQuota: 400,
    prixPack10Quotas: 860,
    quotasOffertsInscription: 5,
    actif: true,
  );

  static AgentIaConfig? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    return AgentIaConfig(
      tarifParQuota: parseDouble(map['tarif_par_quota'], fallback: 96),
      caracteresParQuota: parseInt(map['caracteres_par_quota'], fallback: 400),
      prixPack10Quotas: parseDouble(map['prix_pack_10_quotas'], fallback: 860),
      quotasOffertsInscription:
          parseInt(map['quotas_offerts_inscription'], fallback: 5),
      actif: map['actif'] != false,
      tauxMarge: parseDouble(map['taux_marge'], fallback: 16),
      tauxUsdCdf: parseDouble(map['taux_usd_cdf'], fallback: 2800),
      coutCdfParMillionEntree:
          parseDouble(map['cout_cdf_par_million_entree'], fallback: 840),
      coutCdfParMillionCache:
          parseDouble(map['cout_cdf_par_million_cache'], fallback: 16.8),
      coutCdfParMillionSortie:
          parseDouble(map['cout_cdf_par_million_sortie'], fallback: 3360),
      soldeDeepseekUsd: parseDouble(map['solde_deepseek_usd']),
      alerteSoldeUsd: parseDouble(map['alerte_solde_usd'], fallback: 1),
    );
  }
}

/// Un pack de quotas proposé à l'achat.
class PackQuotas {
  const PackQuotas({
    required this.quotas,
    required this.prix,
    this.id,
    this.libelle,
    this.ordre = 0,
    this.actif = true,
  });

  /// Identifiant du pack EN BASE (correctif 68). `null` = pack de repli,
  /// c'est-à-dire l'ancienne grille codée en dur.
  final String? id;

  final int quotas;
  final double prix;

  /// Nom commercial (« Pack découverte », « Pack boutique »…).
  final String? libelle;

  final int ordre;
  final bool actif;

  /// Prix par quota dans ce pack (affiché pour l'économie).
  double get prixParQuota => quotas > 0 ? prix / quotas : 0;

  /// Vrai si ce pack vient du CATALOGUE en base (et non du repli local).
  bool get vientDeLaBase => id != null;

  /// Libellé affiché, jamais vide.
  String get libelleAffiche =>
      (libelle ?? '').trim().isEmpty ? '$quotas quotas' : libelle!.trim();

  // ---------------------------------------------------------------------------
  // CATALOGUE EN BASE (correctif 68)
  // ---------------------------------------------------------------------------

  static PackQuotas? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    final int quotas = parseInt(map['quotas']);
    if (quotas <= 0) return null;

    return PackQuotas(
      id: parseStringOrNull(map['id']),
      quotas: quotas,
      prix: parseDouble(map['prix']),
      libelle: parseStringOrNull(map['libelle']),
      ordre: parseInt(map['ordre']),
      //  Absent ≠ inactif : une base plus ancienne que l'application ne doit
      //  pas faire disparaître le catalogue.
      actif: map['actif'] == null || map['actif'] == true,
    );
  }

  /// Convertit une liste renvoyée par `rpc_agent_ia_packs`, triée pour
  /// l'affichage (ordre du Super Admin, puis taille).
  static List<PackQuotas> listeDepuisJson(dynamic valeur) {
    final List<PackQuotas> packs = <PackQuotas>[];

    for (final Map<String, dynamic> ligne in parseMapList(valeur)) {
      final PackQuotas? pack = depuisJson(ligne);
      if (pack != null) packs.add(pack);
    }

    packs.sort((PackQuotas a, PackQuotas b) {
      final int parOrdre = a.ordre.compareTo(b.ordre);
      return parOrdre != 0 ? parOrdre : a.quotas.compareTo(b.quotas);
    });

    return packs;
  }

  // ---------------------------------------------------------------------------
  // REPLI LOCAL
  // ---------------------------------------------------------------------------

  /// Les 4 packs d'origine — prix proportionnels au prix du pack de 10.
  ///
  /// ⚠️ Ce n'est plus qu'un REPLI, utilisé quand le catalogue en base n'est
  /// pas joignable (migration 68 pas encore exécutée, ou hors ligne). Sans
  /// lui, l'écran d'achat serait vide et personne ne pourrait commander.
  /// Règle fail-open du projet : mieux vaut une grille approchante que rien.
  static List<PackQuotas> depuisConfig(AgentIaConfig config) {
    final double base = config.prixPack10Quotas;
    return <PackQuotas>[
      PackQuotas(quotas: 10, prix: base, libelle: 'Pack découverte', ordre: 10),
      PackQuotas(quotas: 20, prix: base * 2, libelle: 'Pack standard', ordre: 20),
      PackQuotas(quotas: 50, prix: base * 5, libelle: 'Pack boutique', ordre: 30),
      PackQuotas(
          quotas: 100, prix: base * 10, libelle: 'Pack professionnel', ordre: 40),
    ];
  }
}

// -----------------------------------------------------------------------------
// CORRECTIF 68 — ATTRIBUTIONS : OÙ SONT PASSÉS LES QUOTAS ?
// -----------------------------------------------------------------------------

/// Le solde de quotas d'UN collaborateur, tel que le patron doit le voir.
///
/// `rpc_agent_ia_etat` liste les collaborateurs sans leur solde : le patron ne
/// pouvait donc pas savoir qui détenait quoi, ni décider quoi reprendre.
class AttributionQuota {
  const AttributionQuota({
    required this.utilisateurId,
    this.nom = 'Collaborateur',
    this.role = '',
    this.quotasDisponibles = 0,
    this.quotasUtilisesTotal = 0,
    this.quotasAchetesTotal = 0,
    this.attribueLe,
    this.attribueParNom,
  });

  final String utilisateurId;
  final String nom;
  final String role;

  /// Quotas encore disponibles chez ce collaborateur.
  final int quotasDisponibles;

  /// Quotas déjà consommés — JAMAIS reprenables : le service a été rendu.
  final int quotasUtilisesTotal;

  final int quotasAchetesTotal;
  final DateTime? attribueLe;
  final String? attribueParNom;

  /// Vrai s'il reste quelque chose à reprendre.
  bool get peutEtreReprise => quotasDisponibles > 0;

  static AttributionQuota? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    final String id = parseString(map['utilisateur_id']);
    if (id.isEmpty) return null;

    return AttributionQuota(
      utilisateurId: id,
      nom: parseString(map['nom'], fallback: 'Collaborateur'),
      role: parseString(map['role']),
      quotasDisponibles: parseInt(map['quotas_disponibles']),
      quotasUtilisesTotal: parseInt(map['quotas_utilises_total']),
      quotasAchetesTotal: parseInt(map['quotas_achetes_total']),
      attribueLe: parseDateTimeOrNull(map['attribue_le']),
      attribueParNom: parseStringOrNull(map['attribue_par_nom']),
    );
  }
}

/// Le tableau complet : le pool restant et ce que détient chaque membre.
class AttributionsQuotas {
  const AttributionsQuotas({
    this.entrepriseId,
    this.poolDisponible = 0,
    this.attributions = const <AttributionQuota>[],
  });

  final String? entrepriseId;

  /// Quotas encore dans le pool de l'entreprise (non distribués).
  final int poolDisponible;

  final List<AttributionQuota> attributions;

  static const AttributionsQuotas vide = AttributionsQuotas();

  /// Somme des quotas encore détenus par les membres.
  int get totalChezLesMembres => attributions.fold(
        0,
        (int total, AttributionQuota a) => total + a.quotasDisponibles,
      );

  /// Somme déjà consommée par les membres (ne reviendra jamais).
  int get totalConsomme => attributions.fold(
        0,
        (int total, AttributionQuota a) => total + a.quotasUtilisesTotal,
      );

  /// Vrai s'il y a au moins une attribution à montrer.
  bool get estVide => attributions.isEmpty;

  static AttributionsQuotas depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return vide;

    final List<AttributionQuota> liste = <AttributionQuota>[];
    for (final Map<String, dynamic> ligne in parseMapList(map['attributions'])) {
      final AttributionQuota? a = AttributionQuota.depuisJson(ligne);
      if (a != null) liste.add(a);
    }
    liste.sort((AttributionQuota a, AttributionQuota b) => a.nom.compareTo(b.nom));

    return AttributionsQuotas(
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      poolDisponible: parseInt(map['pool_disponible']),
      attributions: liste,
    );
  }
}

/// Une ligne de soldes (`agent_ia_quotas`) : pool entreprise OU utilisateur.
class SoldeQuotas {
  const SoldeQuotas({
    required this.quotasDisponibles,
    required this.quotasUtilisesTotal,
    required this.quotasAchetesTotal,
  });

  final int quotasDisponibles;
  final int quotasUtilisesTotal;
  final int quotasAchetesTotal;

  static const SoldeQuotas vide = SoldeQuotas(
    quotasDisponibles: 0,
    quotasUtilisesTotal: 0,
    quotasAchetesTotal: 0,
  );

  static SoldeQuotas? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    return SoldeQuotas(
      quotasDisponibles: parseInt(map['quotas_disponibles']),
      quotasUtilisesTotal: parseInt(map['quotas_utilises_total']),
      quotasAchetesTotal: parseInt(map['quotas_achetes_total']),
    );
  }
}

/// Collaborateur auquel le patron peut attribuer des quotas.
class MembreQuota {
  const MembreQuota({required this.id, required this.nom, required this.role});

  final String id;
  final String nom;
  final String role;

  static MembreQuota? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;
    return MembreQuota(
      id: parseString(map['id']),
      nom: parseString(map['nom'], fallback: 'Collaborateur'),
      role: parseString(map['role']),
    );
  }
}

/// Réponse de `rpc_agent_ia_etat()` : tout ce dont les écrans ont besoin.
class EtatAgentIa {
  const EtatAgentIa({
    required this.config,
    required this.pool,
    required this.moi,
    required this.role,
    required this.estProprietaire,
    required this.estPlateforme,
    required this.estSuperAdmin,
    required this.collaborateurs,
  });

  final AgentIaConfig config;

  /// Soldes du POOL de l'entreprise (`null` pour le personnel plateforme).
  final SoldeQuotas? pool;

  /// MON allocation personnelle.
  final SoldeQuotas moi;

  final String role;
  final bool estProprietaire;
  final bool estPlateforme;
  final bool estSuperAdmin;
  final List<MembreQuota> collaborateurs;

  static const EtatAgentIa defaut = EtatAgentIa(
    config: AgentIaConfig.defaut,
    pool: null,
    moi: SoldeQuotas.vide,
    role: '',
    estProprietaire: false,
    estPlateforme: false,
    estSuperAdmin: false,
    collaborateurs: <MembreQuota>[],
  );

  static EtatAgentIa? depuisRpc(dynamic reponse) {
    final Map<String, dynamic>? map = parseMap(reponse);
    if (map == null) return null;

    return EtatAgentIa(
      config: AgentIaConfig.depuisJson(map['config']) ?? AgentIaConfig.defaut,
      pool: SoldeQuotas.depuisJson(map['pool']),
      moi: SoldeQuotas.depuisJson(map['moi']) ?? SoldeQuotas.vide,
      role: parseString(map['role']),
      estProprietaire: map['est_proprietaire'] == true,
      estPlateforme: map['est_plateforme'] == true,
      estSuperAdmin: map['est_super_admin'] == true,
      collaborateurs: parseMapList(map['collaborateurs'])
          .map(MembreQuota.depuisJson)
          .whereType<MembreQuota>()
          .toList(growable: false),
    );
  }
}

/// Une demande/achat de quotas (`agent_ia_achats`).
///
/// ⚠️ Le MONTANT (`montantCdf`) est toujours affiché, y compris impayé — c'est
/// une exigence métier (suivi de l'argent dû pour l'assistant).
class AchatQuotas {
  const AchatQuotas({
    required this.id,
    required this.utilisateurId,
    required this.utilisateurNom,
    required this.nombreQuotas,
    required this.montantCdf,
    required this.modePaiement,
    required this.statut,
    required this.statutPaiement,
    required this.note,
    required this.createdAt,
    required this.valideLe,
  });

  final String id;
  final String utilisateurId;

  /// Nom du demandeur (rempli par le service après jointure).
  final String utilisateurNom;

  final int nombreQuotas;
  final double montantCdf;
  final String modePaiement;

  /// `demande`, `approuve` ou `refuse`.
  final String statut;

  /// `impaye` ou `paye`.
  final String statutPaiement;

  final String? note;
  final DateTime? createdAt;
  final DateTime? valideLe;

  bool get enAttente => statut == 'demande';
  bool get approuve => statut == 'approuve';
  bool get refuse => statut == 'refuse';
  bool get paye => statutPaiement == 'paye';
  bool get impaye => !paye;

  static AchatQuotas? depuisJson(dynamic valeur,
      {String utilisateurNom = ''}) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    return AchatQuotas(
      id: parseString(map['id']),
      utilisateurId: parseString(map['utilisateur_id']),
      utilisateurNom: utilisateurNom,
      nombreQuotas: parseInt(map['nombre_quotas']),
      montantCdf: parseDouble(map['montant_cdf']),
      modePaiement: parseString(map['mode_paiement'], fallback: 'especes'),
      statut: parseString(map['statut'], fallback: 'demande'),
      statutPaiement: parseString(map['statut_paiement'], fallback: 'impaye'),
      note: parseStringOrNull(map['note']),
      createdAt: parseDateTimeOrNull(map['created_at']),
      valideLe: parseDateTimeOrNull(map['valide_le']),
    );
  }

  /// Copie avec le nom du demandeur renseigné (jointure côté service).
  AchatQuotas avecDemandeur(String nom) => AchatQuotas(
        id: id,
        utilisateurId: utilisateurId,
        utilisateurNom: nom,
        nombreQuotas: nombreQuotas,
        montantCdf: montantCdf,
        modePaiement: modePaiement,
        statut: statut,
        statutPaiement: statutPaiement,
        note: note,
        createdAt: createdAt,
        valideLe: valideLe,
      );
}

/// Une action exécutée par l'agent (retour de l'Edge Function).
class ActionAgent {
  const ActionAgent({required this.outil, required this.succes});

  final String outil;
  final bool succes;

  String get libelle => libelleOutil(outil);

  static ActionAgent? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;
    return ActionAgent(
      outil: parseString(map['outil']),
      succes: map['succes'] != false,
    );
  }
}

/// Réponse complète de l'Edge Function `agent-ia`.
class ReponseAgent {
  const ReponseAgent({
    required this.reponse,
    required this.quotasConsommes,
    required this.montantCdf,
    required this.soldeRestant,
    required this.caracteresReponse,
    required this.actions,
  });

  final String reponse;
  final int quotasConsommes;
  final double montantCdf;
  final int soldeRestant;
  final int caracteresReponse;
  final List<ActionAgent> actions;

  static ReponseAgent? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    return ReponseAgent(
      reponse: parseString(map['reponse']),
      quotasConsommes: parseInt(map['quotas_consommes']),
      montantCdf: parseDouble(map['montant_cdf']),
      soldeRestant: parseInt(map['solde_restant']),
      caracteresReponse: parseInt(map['caracteres_reponse']),
      actions: parseMapList(map['actions'])
          .map(ActionAgent.depuisJson)
          .whereType<ActionAgent>()
          .toList(growable: false),
    );
  }
}

/// Un message affiché dans le chat (local à la session en cours).
class MessageAgent {
  const MessageAgent({
    required this.role,
    required this.contenu,
    this.actions = const <ActionAgent>[],
    this.quotasConsommes = 0,
    this.montantCdf = 0,
    this.erreur = false,
    this.codeErreur,
  });

  /// `user` ou `assistant`.
  final String role;

  final String contenu;
  final List<ActionAgent> actions;
  final int quotasConsommes;
  final double montantCdf;

  /// `true` pour une bulle d'erreur (blocage quotas, abonnement…).
  final bool erreur;

  final String? codeErreur;

  bool get deUtilisateur => role == 'user';
}

/// Libellé français d'un outil de l'agent (affiché dans le chat).
String libelleOutil(String outil) {
  return _libellesOutils[outil] ?? outil.replaceAll('_', ' ');
}

const Map<String, String> _libellesOutils = <String, String>{
  'rechercher_produit': 'Recherche d\'articles',
  'creer_vente': 'Vente enregistrée',
  'annuler_vente': 'Annulation de vente',
  'lister_ventes_du_jour': 'Ventes du jour',
  'lister_ventes_periode': 'Ventes de la période',
  'ajouter_produit': 'Article créé',
  'modifier_produit': 'Article modifié',
  'supprimer_produit': 'Article supprimé',
  'consulter_stock': 'Consultation du stock',
  'lister_stock_faible': 'Articles en alerte',
  'ajouter_stock': 'Entrée de stock',
  'ajuster_stock': 'Ajustement de stock',
  'rechercher_produit_par_qr': 'Recherche par QR',
  'consulter_caisse': 'Caisse',
  'ajouter_depense': 'Dépense enregistrée',
  'lister_depenses_periode': 'Dépenses',
  'consulter_dettes_client': 'Dettes client',
  'enregistrer_paiement_dette': 'Paiement de dette',
  'ajouter_client': 'Client créé',
  'rechercher_client': 'Recherche client',
  'lister_clients': 'Clients',
  'generer_rapport_ventes': 'Rapport des ventes',
  'rapport_top_produits': 'Top produits',
  'rapport_chiffre_affaires': 'Chiffre d\'affaires',
  'rapport_stock': 'État du stock',
  'lister_collaborateurs': 'Collaborateurs',
  'ajouter_collaborateur': 'Collaborateur créé',
  'modifier_role_collaborateur': 'Rôle modifié',
  'consulter_abonnement': 'Abonnement',
  'voir_jours_restants': 'Jours restants',
  'enregistrer_paiement_abonnement': 'Paiement d\'abonnement',
  'generer_qr_produit': 'QR code préparé',
  'imprimer_etiquettes': 'Étiquettes préparées',
  'informations_entreprise': 'Informations entreprise',
  'statistiques_globales': 'Statistiques plateforme',
};

// ============================================================================
//  MODULE 13 bis — GESTION RÉELLE DES TOKENS
// ============================================================================

/// Une ligne de la comptabilité IA (`public.agent_ia_usage`).
///
/// Représente UN appel facturé : les tokens réellement consommés chez DeepSeek,
/// le coût correspondant en CDF, et ce qui a été facturé au client.
class LigneUsageIa {
  const LigneUsageIa({
    required this.id,
    required this.createdAt,
    required this.source,
    this.modele,
    this.entrepriseId,
    this.entreprise,
    this.utilisateurId,
    this.utilisateur,
    required this.tokensEntree,
    required this.tokensCache,
    required this.tokensSortie,
    required this.tokensTotal,
    required this.coutCdf,
    required this.quotasDebites,
    required this.montantCdf,
    required this.margeCdf,
  });

  final int id;
  final DateTime? createdAt;

  /// `agent-ia` (application) ou `admin-agents` (API Biashara Group).
  final String source;

  final String? modele;
  final String? entrepriseId;
  final String? entreprise;
  final String? utilisateurId;
  final String? utilisateur;

  /// Tokens d'entrée NON cachés (facturés plein tarif).
  final int tokensEntree;

  /// Tokens d'entrée servis depuis le cache (≈ 50 fois moins chers).
  final int tokensCache;

  final int tokensSortie;
  final int tokensTotal;

  /// Coût réel payé à DeepSeek, en CDF.
  final double coutCdf;

  final int quotasDebites;

  /// Montant facturé au client, en CDF (0 pour un appel offert).
  final double montantCdf;

  /// Marge = montant facturé − coût réel (négative pour un appel offert).
  final double margeCdf;

  /// Part des tokens d'entrée servie par le cache (indicateur d'efficacité).
  double get tauxCache {
    final int total = tokensEntree + tokensCache;
    return total > 0 ? tokensCache / total : 0;
  }

  static LigneUsageIa? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    return LigneUsageIa(
      id: parseInt(map['id']),
      createdAt: parseDateTimeOrNull(map['created_at']),
      source: parseString(map['source'], fallback: 'agent-ia'),
      modele: parseStringOrNull(map['modele']),
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      entreprise: parseStringOrNull(map['entreprise']),
      utilisateurId: parseStringOrNull(map['utilisateur_id']),
      utilisateur: parseStringOrNull(map['utilisateur']),
      tokensEntree: parseInt(map['tokens_entree']),
      tokensCache: parseInt(map['tokens_entree_cache']),
      tokensSortie: parseInt(map['tokens_sortie']),
      tokensTotal: parseInt(map['tokens_total']),
      coutCdf: parseDouble(map['cout_cdf']),
      quotasDebites: parseInt(map['quotas_debites']),
      montantCdf: parseDouble(map['montant_cdf']),
      margeCdf: parseDouble(map['marge_cdf']),
    );
  }

  static List<LigneUsageIa> listeDepuisJson(dynamic valeur) {
    return parseMapList(valeur)
        .map(LigneUsageIa.depuisJson)
        .whereType<LigneUsageIa>()
        .toList(growable: false);
  }
}

/// Consommation agrégée d'une entreprise (distribution de l'usage).
class RepartitionIaEntreprise {
  const RepartitionIaEntreprise({
    this.entrepriseId,
    required this.entreprise,
    required this.appels,
    required this.tokensTotal,
    required this.coutCdf,
    required this.factureCdf,
    required this.margeCdf,
    required this.quotasDebites,
    required this.caracteres,
    this.derniereActivite,
  });

  final String? entrepriseId;
  final String entreprise;
  final int appels;
  final int tokensTotal;
  final double coutCdf;
  final double factureCdf;
  final double margeCdf;
  final int quotasDebites;

  /// Équivalent en caractères de réponse (quotas × `caracteres_par_quota`).
  final int caracteres;
  final DateTime? derniereActivite;

  static RepartitionIaEntreprise? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    return RepartitionIaEntreprise(
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      entreprise: parseString(map['entreprise'], fallback: 'Sans entreprise'),
      appels: parseInt(map['appels']),
      tokensTotal: parseInt(map['tokens_total']),
      coutCdf: parseDouble(map['cout_cdf']),
      factureCdf: parseDouble(map['facture_cdf']),
      margeCdf: parseDouble(map['marge_cdf']),
      quotasDebites: parseInt(map['quotas_debites']),
      caracteres: parseInt(map['caracteres']),
      derniereActivite: parseDateTimeOrNull(map['derniere_activite']),
    );
  }

  static List<RepartitionIaEntreprise> listeDepuisJson(dynamic valeur) {
    return parseMapList(valeur)
        .map(RepartitionIaEntreprise.depuisJson)
        .whereType<RepartitionIaEntreprise>()
        .toList(growable: false);
  }
}

/// Tableau de bord des tokens IA (`rpc_ia_tokens_tableau_bord`).
class TokensIaTableauBord {
  const TokensIaTableauBord({
    required this.jours,
    required this.config,
    required this.appels,
    required this.tokensEntree,
    required this.tokensCache,
    required this.tokensSortie,
    required this.coutCdf,
    required this.factureCdf,
    required this.margeCdf,
    required this.coefficient,
    required this.quotasDebites,
    required this.coutMoyenQuestionCdf,
    required this.periodeAppels,
    required this.periodeCoutCdf,
    required this.periodeFactureCdf,
    required this.periodeMargeCdf,
    required this.periodeQuotas,
    required this.jourCoutCdf,
    required this.jourFactureCdf,
    required this.jourMargeCdf,
    required this.jourQuotas,
    required this.soldeDeepseekUsd,
    required this.soldeCdf,
    required this.questionsRestantes,
    required this.consommationPct,
    required this.alerte,
  });

  final int jours;
  final AgentIaConfig config;

  // — Depuis toujours —
  final int appels;
  final int tokensEntree;
  final int tokensCache;
  final int tokensSortie;

  /// Coût réel cumulé payé à DeepSeek (CDF).
  final double coutCdf;

  /// Total facturé aux clients (CDF).
  final double factureCdf;

  /// Bénéfice réalisé (CDF).
  final double margeCdf;

  /// Coefficient constaté = facturé ÷ coût (l'objectif est 16).
  final double coefficient;

  final int quotasDebites;

  /// Coût moyen réellement constaté d'une question (CDF).
  final double coutMoyenQuestionCdf;

  // — Sur la période choisie —
  final int periodeAppels;
  final double periodeCoutCdf;
  final double periodeFactureCdf;
  final double periodeMargeCdf;
  final int periodeQuotas;

  // — Aujourd'hui (heure de Kinshasa) —
  final double jourCoutCdf;
  final double jourFactureCdf;
  final double jourMargeCdf;
  final int jourQuotas;

  // — Solde DeepSeek —
  final double soldeDeepseekUsd;
  final double soldeCdf;
  final int questionsRestantes;
  final double consommationPct;

  /// `true` si le solde est au niveau du seuil d'alerte.
  final bool alerte;

  int get tokensTotal => tokensEntree + tokensCache + tokensSortie;

  /// Part des tokens d'entrée servie par le cache.
  double get tauxCache {
    final int total = tokensEntree + tokensCache;
    return total > 0 ? tokensCache / total : 0;
  }

  /// Marge potentielle si tout le solde était consommé (CDF).
  double get margePotentielleCdf => soldeCdf * (config.tauxMarge - 1);

  static TokensIaTableauBord? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null || map['ok'] == false) return null;

    return TokensIaTableauBord(
      jours: parseInt(map['jours'], fallback: 30),
      config: AgentIaConfig.depuisJson(map) ?? AgentIaConfig.defaut,
      appels: parseInt(map['appels']),
      tokensEntree: parseInt(map['tokens_entree']),
      tokensCache: parseInt(map['tokens_cache']),
      tokensSortie: parseInt(map['tokens_sortie']),
      coutCdf: parseDouble(map['cout_cdf']),
      factureCdf: parseDouble(map['facture_cdf']),
      margeCdf: parseDouble(map['marge_cdf']),
      coefficient: parseDouble(map['coefficient']),
      quotasDebites: parseInt(map['quotas_debites']),
      coutMoyenQuestionCdf: parseDouble(map['cout_moyen_question_cdf']),
      periodeAppels: parseInt(map['periode_appels']),
      periodeCoutCdf: parseDouble(map['periode_cout_cdf']),
      periodeFactureCdf: parseDouble(map['periode_facture_cdf']),
      periodeMargeCdf: parseDouble(map['periode_marge_cdf']),
      periodeQuotas: parseInt(map['periode_quotas']),
      jourCoutCdf: parseDouble(map['jour_cout_cdf']),
      jourFactureCdf: parseDouble(map['jour_facture_cdf']),
      jourMargeCdf: parseDouble(map['jour_marge_cdf']),
      jourQuotas: parseInt(map['jour_quotas']),
      soldeDeepseekUsd: parseDouble(map['solde_deepseek_usd']),
      soldeCdf: parseDouble(map['solde_cdf']),
      questionsRestantes: parseInt(map['questions_restantes']),
      consommationPct: parseDouble(map['consommation_pct']),
      alerte: map['alerte'] == true,
    );
  }
}
