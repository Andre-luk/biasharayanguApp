// lib/models/paiement_abonnement.dart
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Encaissement d'un abonnement — table `public.paiements_abonnement`.
///
/// Chaque encaissement est historisé : on sait qui a encaissé quel montant,
/// quand, et quelle prolongation en a découlé.
///
/// `totalApres` et `soldeApres` sont enregistrés au moment de l'opération :
/// l'historique reste exact même si l'entreprise est modifiée plus tard.
class PaiementAbonnement {
  final String id;
  final String? entrepriseId;
  final double montant;
  final double? totalApres;
  final double? soldeApres;
  final int prolongationJours;
  final String? enregistrePar;
  final DateTime? createdAt;

  /// Nom de l'auteur, alimenté par une jointure locale : ne correspond à
  /// aucune colonne de `public.paiements_abonnement`.
  final String? enregistreParNom;

  const PaiementAbonnement({
    required this.id,
    this.entrepriseId,
    this.montant = 0,
    this.totalApres,
    this.soldeApres,
    this.prolongationJours = 0,
    this.enregistrePar,
    this.createdAt,
    this.enregistreParNom,
  });

  factory PaiementAbonnement.fromMap(Map<String, dynamic> map) {
    return PaiementAbonnement(
      id: parseString(map['id']),
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      montant: parseDouble(map['montant']),
      totalApres: parseDoubleOrNull(map['total_apres']),
      soldeApres: parseDoubleOrNull(map['solde_apres']),
      prolongationJours: parseInt(map['prolongation_jours']),
      enregistrePar: parseStringOrNull(map['enregistre_par']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }

  /// Colonnes de `public.paiements_abonnement` uniquement.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entreprise_id': entrepriseId,
      'montant': montant,
      'total_apres': totalApres,
      'solde_apres': soldeApres,
      'prolongation_jours': prolongationJours,
      'enregistre_par': enregistrePar,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// Vrai si cet encaissement a repoussé la date d'expiration.
  bool get aProlonge => prolongationJours > 0;

  PaiementAbonnement copyWith({
    String? id,
    String? entrepriseId,
    double? montant,
    double? totalApres,
    double? soldeApres,
    int? prolongationJours,
    String? enregistrePar,
    DateTime? createdAt,
    String? enregistreParNom,
  }) {
    return PaiementAbonnement(
      id: id ?? this.id,
      entrepriseId: entrepriseId ?? this.entrepriseId,
      montant: montant ?? this.montant,
      totalApres: totalApres ?? this.totalApres,
      soldeApres: soldeApres ?? this.soldeApres,
      prolongationJours: prolongationJours ?? this.prolongationJours,
      enregistrePar: enregistrePar ?? this.enregistrePar,
      createdAt: createdAt ?? this.createdAt,
      enregistreParNom: enregistreParNom ?? this.enregistreParNom,
    );
  }
}
