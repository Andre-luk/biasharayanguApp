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
  });

  /// CDF facturés par quota consommé (100 à 150).
  final double tarifParQuota;

  /// Nombre de caractères de réponse comptant pour 1 quota (défaut 20).
  final int caracteresParQuota;

  /// Prix du pack de 10 quotas (les autres packs sont proportionnels).
  final double prixPack10Quotas;

  /// Quotas offerts une fois par entreprise (bonus de bienvenue).
  final int quotasOffertsInscription;

  /// Assistant actif ou non (réglage Super Admin).
  final bool actif;

  /// Valeurs de repli (mêmes défauts que la migration SQL).
  static const AgentIaConfig defaut = AgentIaConfig(
    tarifParQuota: 150,
    caracteresParQuota: 20,
    prixPack10Quotas: 1000,
    quotasOffertsInscription: 5,
    actif: true,
  );

  static AgentIaConfig? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;

    return AgentIaConfig(
      tarifParQuota: parseDouble(map['tarif_par_quota'], fallback: 150),
      caracteresParQuota: parseInt(map['caracteres_par_quota'], fallback: 20),
      prixPack10Quotas: parseDouble(map['prix_pack_10_quotas'], fallback: 1000),
      quotasOffertsInscription:
          parseInt(map['quotas_offerts_inscription'], fallback: 5),
      actif: map['actif'] != false,
    );
  }
}

/// Un pack de quotas proposé à l'achat.
class PackQuotas {
  const PackQuotas({required this.quotas, required this.prix});

  final int quotas;
  final double prix;

  /// Prix par quota dans ce pack (affiché pour l'économie).
  double get prixParQuota => quotas > 0 ? prix / quotas : 0;

  /// Les 4 packs officiels — prix proportionnels au prix du pack de 10.
  static List<PackQuotas> depuisConfig(AgentIaConfig config) {
    final double base = config.prixPack10Quotas;
    return <PackQuotas>[
      PackQuotas(quotas: 10, prix: base),
      PackQuotas(quotas: 20, prix: base * 2),
      PackQuotas(quotas: 50, prix: base * 5),
      PackQuotas(quotas: 100, prix: base * 10),
    ];
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
