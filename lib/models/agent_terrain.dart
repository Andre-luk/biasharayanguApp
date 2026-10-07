// lib/models/agent_terrain.dart
//
// 🧑‍🌾 MODULE 21 ter — FICHE D'ACTIVITÉ DE L'AGENT TERRAIN.
//
// Objets de valeur purs (aucun import Flutter, aucun accès réseau) : la fiche
// alimente l'écran « Ma fiche terrain » et se teste sans binding.
//
// Le serveur (`rpc_agent_fiche`) reste l'autorité : il ne renvoie QUE le
// périmètre de l'agent demandé (ses utilisateurs, ses entreprises).

/// Entreprise suivie par un agent (ligne de suivi d'abonnement).
class EntrepriseAgentTerrain {
  const EntrepriseAgentTerrain({
    required this.id,
    required this.nom,
    required this.statut,
    required this.etape,
    required this.soldeRestant,
    this.montantTotalDu,
    this.montantDejaPaye,
    this.dateExpiration,
    this.createdAt,
    this.responsable,
    this.contact,
    this.telephone,
    this.nbPublies = 0,
  });

  final String id;
  final String nom;
  final String statut;

  /// `en_attente_verification`, `verifie`, `actif`, `restreint`, `rejete`.
  final String etape;

  final num soldeRestant;
  final num? montantTotalDu;
  final num? montantDejaPaye;
  final DateTime? dateExpiration;
  final DateTime? createdAt;

  /// Nom du patron (jointure serveur), si disponible.
  final String? responsable;
  final String? contact;
  final String? telephone;

  /// Nombre d'articles publiés sur sa vitrine.
  final int nbPublies;

  bool get enAttente =>
      etape == 'en_attente_verification' || etape == 'verifie';

  bool get actif => etape == 'actif';

  bool get impaye => soldeRestant > 0;

  /// Libellé lisible de l'étape.
  String get libelleEtape {
    switch (etape) {
      case 'en_attente_verification':
        return 'À vérifier';
      case 'verifie':
        return 'Vérifié — à activer';
      case 'actif':
        return 'Actif';
      case 'restreint':
        return 'Restreint (impayé)';
      case 'rejete':
        return 'Rejeté';
      default:
        return etape.isEmpty ? '—' : etape;
    }
  }

  factory EntrepriseAgentTerrain.fromMap(Map<String, dynamic> map) {
    num? n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');
    DateTime? d(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

    return EntrepriseAgentTerrain(
      id: '${map['entreprise_id'] ?? map['id'] ?? ''}',
      nom: '${map['nom'] ?? ''}',
      statut: '${map['statut'] ?? ''}',
      etape: '${map['activation_etape'] ?? map['etape'] ?? 'actif'}',
      soldeRestant: n(map['solde_restant']) ?? 0,
      montantTotalDu: n(map['montant_total_du']),
      montantDejaPaye: n(map['montant_deja_paye']),
      dateExpiration: d(map['date_expiration']),
      createdAt: d(map['created_at']),
      responsable: map['responsable']?.toString(),
      contact: map['contact']?.toString(),
      telephone: map['telephone']?.toString(),
      nbPublies: (n(map['nb_publies']) ?? 0).toInt(),
    );
  }
}

/// Utilisateur (client / patron) rattaché à un agent.
class UtilisateurAgentTerrain {
  const UtilisateurAgentTerrain({
    required this.id,
    required this.nom,
    required this.email,
    this.telephone,
    this.role = '',
    this.entrepriseId,
    this.entreprise,
    this.etape = '',
    this.createdAt,
  });

  final String id;
  final String nom;
  final String email;
  final String? telephone;
  final String role;
  final String? entrepriseId;
  final String? entreprise;
  final String etape;
  final DateTime? createdAt;

  factory UtilisateurAgentTerrain.fromMap(Map<String, dynamic> map) {
    DateTime? d(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    return UtilisateurAgentTerrain(
      id: '${map['id'] ?? ''}',
      nom: '${map['nom'] ?? ''}',
      email: '${map['email'] ?? ''}',
      telephone: map['telephone']?.toString(),
      role: '${map['role'] ?? ''}',
      entrepriseId: map['entreprise_id']?.toString(),
      entreprise: map['entreprise']?.toString(),
      etape: '${map['activation_etape'] ?? ''}',
      createdAt: d(map['created_at']),
    );
  }
}

/// Ligne du journal d'audit de l'agent (traçabilité).
class ActionAgentTerrain {
  const ActionAgentTerrain({
    required this.action,
    this.niveau,
    this.createdAt,
    this.details,
  });

  final String action;
  final String? niveau;
  final DateTime? createdAt;
  final Map<String, dynamic>? details;

  factory ActionAgentTerrain.fromMap(Map<String, dynamic> map) {
    DateTime? d(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    final Object? det = map['details'];
    return ActionAgentTerrain(
      action: '${map['action'] ?? ''}',
      niveau: map['niveau']?.toString(),
      createdAt: d(map['created_at']),
      details: det is Map ? Map<String, dynamic>.from(det) : null,
    );
  }
}

/// Fiche complète d'un agent terrain.
class FicheAgentTerrain {
  const FicheAgentTerrain({
    required this.agentId,
    required this.nom,
    required this.email,
    this.role = '',
    this.nbUtilisateurs = 0,
    this.nbEntreprises = 0,
    this.nbBoutiques = 0,
    this.nbAbonnementsActifs = 0,
    this.nbEnAttente = 0,
    this.nbProduits = 0,
    this.nbConditionnements = 0,
    this.nbQrCodes = 0,
    this.nbProduitsPublies = 0,
    this.montantEncaisse = 0,
    this.soldeDu = 0,
    this.entreprises = const <EntrepriseAgentTerrain>[],
    this.utilisateurs = const <UtilisateurAgentTerrain>[],
    this.journal = const <ActionAgentTerrain>[],
  });

  final String agentId;
  final String nom;
  final String email;
  final String role;

  final int nbUtilisateurs;
  final int nbEntreprises;
  final int nbBoutiques;
  final int nbAbonnementsActifs;
  final int nbEnAttente;
  final int nbProduits;
  final int nbConditionnements;
  final int nbQrCodes;
  final int nbProduitsPublies;

  /// Ce que ses abonnements ont encaissé (paiements validés en finance).
  final num montantEncaisse;

  /// Total restant dû sur ses entreprises.
  final num soldeDu;

  final List<EntrepriseAgentTerrain> entreprises;
  final List<UtilisateurAgentTerrain> utilisateurs;
  final List<ActionAgentTerrain> journal;

  factory FicheAgentTerrain.fromMap(Map<String, dynamic> map) {
    int i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    num n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

    List<T> liste<T>(dynamic brut, T Function(Map<String, dynamic>) f) {
      if (brut is! List) return <T>[];
      return brut
          .whereType<Map>()
          .map((Map e) => f(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }

    return FicheAgentTerrain(
      agentId: '${map['agent_id'] ?? ''}',
      nom: '${map['nom'] ?? ''}',
      email: '${map['email'] ?? ''}',
      role: '${map['role'] ?? ''}',
      nbUtilisateurs: i(map['nb_utilisateurs']),
      nbEntreprises: i(map['nb_entreprises']),
      nbBoutiques: i(map['nb_boutiques']),
      nbAbonnementsActifs: i(map['nb_abonnements_actifs']),
      nbEnAttente: i(map['nb_en_attente']),
      nbProduits: i(map['nb_produits']),
      nbConditionnements: i(map['nb_conditionnements']),
      nbQrCodes: i(map['nb_qr_codes']),
      nbProduitsPublies: i(map['nb_produits_publies']),
      montantEncaisse: n(map['montant_encaisse']),
      soldeDu: n(map['solde_du']),
      entreprises: liste<EntrepriseAgentTerrain>(
          map['entreprises'], EntrepriseAgentTerrain.fromMap),
      utilisateurs: liste<UtilisateurAgentTerrain>(
          map['utilisateurs'], UtilisateurAgentTerrain.fromMap),
      journal: liste<ActionAgentTerrain>(map['journal'], ActionAgentTerrain.fromMap),
    );
  }
}
