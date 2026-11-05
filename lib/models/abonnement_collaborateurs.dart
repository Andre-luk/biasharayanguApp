// lib/models/abonnement_collaborateurs.dart
//
// MODULE 26 — L'ABONNEMENT VU PAR LE PROPRIÉTAIRE.
//
// Le prix suit l'équipe : abonnement de base + (collaborateurs ACTIFS × prix
// unitaire). Le calcul est fait par le serveur (`abonnement_detail_
// collaborateurs`) ; ce modèle le met en forme et fournit une version locale
// de la même règle, utile quand le détail n'est pas encore arrivé.
//
// Règles rappelées ici (elles sont appliquées en base) :
//   • le propriétaire n'est JAMAIS compté ;
//   • un collaborateur désactivé n'est plus facturé ;
//   • un compte à plusieurs rôles ne compte qu'une fois ;
//   • deux entreprises comptent séparément.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Détail de facturation d'un abonnement (base + collaborateurs).
class AbonnementCollaborateurs {
  const AbonnementCollaborateurs({
    required this.base,
    required this.nbCollaborateurs,
    required this.prixUnitaire,
    required this.supplement,
    required this.totalProchainCycle,
    this.supplementCycleEnCours = 0,
    this.dejaPaye = 0,
    this.soldeRestant = 0,
    this.prorata = false,
    this.devise = 'CDF',
    this.echeance,
  });

  /// Abonnement de base (installation ou mensuel, hors équipe).
  final double base;

  /// Nombre de collaborateurs actifs FACTURÉS.
  final int nbCollaborateurs;

  /// Prix d'un collaborateur pour une période (2 500 FC par défaut).
  final double prixUnitaire;

  /// `nbCollaborateurs × prixUnitaire`.
  final double supplement;

  /// Ce que coûtera le prochain cycle.
  final double totalProchainCycle;

  /// Supplément déjà inclus dans le cycle en cours.
  final double supplementCycleEnCours;

  final double dejaPaye;
  final double soldeRestant;
  final bool prorata;
  final String devise;
  final DateTime? echeance;

  /// Calcul PUR de la règle (sans réseau) — sert aux tests et à l'aperçu.
  static double calculerSupplement({
    required int nbCollaborateurs,
    required double prixUnitaire,
  }) {
    if (nbCollaborateurs <= 0 || prixUnitaire <= 0) return 0;
    return _arrondi(nbCollaborateurs * prixUnitaire);
  }

  /// Total du cycle : base + supplément.
  static double calculerTotal({
    required double base,
    required int nbCollaborateurs,
    required double prixUnitaire,
  }) {
    if (base <= 0) return 0;
    return _arrondi(
      base + calculerSupplement(
        nbCollaborateurs: nbCollaborateurs,
        prixUnitaire: prixUnitaire,
      ),
    );
  }

  static double _arrondi(double valeur) => (valeur * 100).roundToDouble() / 100;

  /// Construit depuis la réponse de `abonnement_detail_collaborateurs`.
  factory AbonnementCollaborateurs.fromMap(Map<String, dynamic> map) {
    final double base = parseDouble(map['base']);
    final int nb = parseInt(map['nb_collaborateurs']);
    final double unite = parseDouble(map['prix_unitaire']);

    // On préfère TOUJOURS le chiffre du serveur ; le calcul local n'est qu'un
    // repli si l'un des champs manque.
    final double supplement = map.containsKey('supplement')
        ? parseDouble(map['supplement'])
        : calculerSupplement(nbCollaborateurs: nb, prixUnitaire: unite);
    final double total = map.containsKey('total_prochain_cycle')
        ? parseDouble(map['total_prochain_cycle'])
        : calculerTotal(base: base, nbCollaborateurs: nb, prixUnitaire: unite);

    return AbonnementCollaborateurs(
      base: base,
      nbCollaborateurs: nb,
      prixUnitaire: unite,
      supplement: supplement,
      totalProchainCycle: total,
      supplementCycleEnCours: parseDouble(map['supplement_cycle_en_cours']),
      dejaPaye: parseDouble(map['deja_paye']),
      soldeRestant: parseDouble(map['solde_restant']),
      prorata: parseBool(map['prorata']),
      devise: parseString(map['devise'], fallback: 'CDF'),
      echeance: parseDateTimeOrNull(map['echeance']),
    );
  }
}
