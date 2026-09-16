// lib/models/paiement_laperle.dart
//
// MODULE 3 — Paiement enregistré par le moteur d'abonnement.
// Table `public.paiements_abonnements_laperle`.
//
// Cette table est DÉDIÉE au moteur d'abonnement (Module 3) : elle est
// volontairement séparée de `public.paiements_abonnement` (historique du
// Module 1). Chaque encaissement conserve son type (avance / solde /
// renouvellement), le mode de paiement, une note libre, et l'état des
// montants APRÈS l'opération.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Type d'un paiement d'abonnement.
///
/// ⚠️ [code] est la valeur stockée dans `paiements_abonnements_laperle`.
enum TypePaiement {
  avance('AVANCE', 'Avance'),
  solde('SOLDE', 'Solde'),
  renouvellement('RENOUVELLEMENT', 'Renouvellement');

  const TypePaiement(this.code, this.libelle);

  /// Valeur enregistrée en base.
  final String code;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// Convertit un code SQL en type applicatif, ou `null` si inconnu.
  static TypePaiement? fromCode(String? code) {
    if (code == null) return null;

    for (final TypePaiement type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

/// Modes de paiement proposés dans le formulaire.
///
/// La colonne est un texte libre côté base : cette liste couvre les cas
/// courants, le champ restant modifiable si un autre mode est nécessaire.
const List<String> modesPaiementDisponibles = <String>[
  'Espèces',
  'Mobile Money',
  'Virement bancaire',
  'Carte bancaire',
  'Autre',
];

/// Encaissement enregistré par le moteur d'abonnement.
class PaiementLaperle {
  final String id;
  final String? entrepriseId;
  final double montant;
  final TypePaiement? typePaiement;
  final String? modePaiement;
  final String? note;

  /// Cumul payé et solde APRÈS l'opération (historique exact même si
  /// l'entreprise évolue ensuite).
  final double? totalApres;
  final double? soldeApres;

  /// Nombre de jours ajoutés à `date_expiration` (0 si aucun).
  final int prolongationJours;

  final String? enregistrePar;
  final DateTime? createdAt;

  /// Nom de l'auteur, alimenté par une jointure locale : ne correspond à
  /// aucune colonne de la table.
  final String? enregistreParNom;

  const PaiementLaperle({
    required this.id,
    this.entrepriseId,
    this.montant = 0,
    this.typePaiement,
    this.modePaiement,
    this.note,
    this.totalApres,
    this.soldeApres,
    this.prolongationJours = 0,
    this.enregistrePar,
    this.createdAt,
    this.enregistreParNom,
  });

  factory PaiementLaperle.fromMap(Map<String, dynamic> map) {
    return PaiementLaperle(
      id: parseString(map['id']),
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      montant: parseDouble(map['montant']),
      typePaiement:
          TypePaiement.fromCode(parseStringOrNull(map['type_paiement'])),
      modePaiement: parseStringOrNull(map['mode_paiement']),
      note: parseStringOrNull(map['note']),
      totalApres: parseDoubleOrNull(map['total_apres']),
      soldeApres: parseDoubleOrNull(map['solde_apres']),
      prolongationJours: parseInt(map['prolongation_jours']),
      enregistrePar: parseStringOrNull(map['enregistre_par']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }

  /// Colonnes de `public.paiements_abonnements_laperle` uniquement.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entreprise_id': entrepriseId,
      'montant': montant,
      'type_paiement': typePaiement?.code,
      'mode_paiement': modePaiement,
      'note': note,
      'total_apres': totalApres,
      'solde_apres': soldeApres,
      'prolongation_jours': prolongationJours,
      'enregistre_par': enregistrePar,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// Vrai si cet encaissement a repoussé la date d'expiration.
  bool get aProlonge => prolongationJours > 0;

  PaiementLaperle copyWith({
    String? id,
    String? entrepriseId,
    double? montant,
    TypePaiement? typePaiement,
    String? modePaiement,
    String? note,
    double? totalApres,
    double? soldeApres,
    int? prolongationJours,
    String? enregistrePar,
    DateTime? createdAt,
    String? enregistreParNom,
  }) {
    return PaiementLaperle(
      id: id ?? this.id,
      entrepriseId: entrepriseId ?? this.entrepriseId,
      montant: montant ?? this.montant,
      typePaiement: typePaiement ?? this.typePaiement,
      modePaiement: modePaiement ?? this.modePaiement,
      note: note ?? this.note,
      totalApres: totalApres ?? this.totalApres,
      soldeApres: soldeApres ?? this.soldeApres,
      prolongationJours: prolongationJours ?? this.prolongationJours,
      enregistrePar: enregistrePar ?? this.enregistrePar,
      createdAt: createdAt ?? this.createdAt,
      enregistreParNom: enregistreParNom ?? this.enregistreParNom,
    );
  }
}
