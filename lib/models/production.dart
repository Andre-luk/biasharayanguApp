// lib/models/production.dart
//
// 🥖 MODULE 16 (phase C5) — BOULANGERIE : PRODUCTION & MATIÈRES CONSOMMÉES.
//
// Cycle : en_cours (on saisit les matières) → terminee (le produit fini
// entre en stock, coût de revient calculé) ; ou annulee (matières rendues).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Statut d'une production (table `public.productions`).
enum StatutProduction {
  enCours('en_cours', 'En cours'),
  terminee('terminee', 'Terminée'),
  annulee('annulee', 'Annulée');

  const StatutProduction(this.code, this.libelle);

  final String code;
  final String libelle;

  /// La production est ouverte (matières modifiables).
  bool get estEnCours => this == StatutProduction.enCours;

  /// La production est close.
  bool get estClose => this != StatutProduction.enCours;

  static StatutProduction fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final StatutProduction statut in values) {
      if (statut.code == normalise) return statut;
    }
    return StatutProduction.enCours;
  }
}

/// Une matière consommée — table `public.consommations_production`.
class ConsommationProduction {
  const ConsommationProduction({
    required this.id,
    required this.matiereId,
    required this.libelle,
    this.unite = '',
    this.quantite = 0,
    this.coutUnitaire = 0,
    this.total = 0,
  });

  final String id;
  final String matiereId;

  /// Nom de la matière (jointure) — « Farine T55 ».
  final String libelle;

  /// Unité (jointure) — kg, l…
  final String unite;

  final double quantite;

  /// Prix unitaire FIGÉ au moment de la consommation.
  final double coutUnitaire;

  final double total;

  factory ConsommationProduction.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic>? matiere =
        parseMap(map['matieres_premieres']) ?? parseMap(map['matiere']);
    return ConsommationProduction(
      id: parseString(map['id']),
      matiereId: parseString(map['matiere_id']),
      libelle: matiere == null
          ? parseString(map['libelle'], fallback: 'Matière')
          : parseString(matiere['nom'], fallback: 'Matière'),
      unite:
          matiere == null ? '' : parseString(matiere['unite']),
      quantite: parseDouble(map['quantite']),
      coutUnitaire: parseDouble(map['cout_unitaire']),
      total: parseDouble(map['total']),
    );
  }
}

/// Une production — table `public.productions`.
class Production {
  const Production({
    required this.id,
    required this.produitId,
    this.produitNom = '',
    this.numero,
    this.quantitePrevue = 0,
    this.quantiteReelle = 0,
    this.pertes = 0,
    this.coutMatieres = 0,
    this.coutUnitaire = 0,
    this.statut = StatutProduction.enCours,
    this.note,
    this.motifAnnulation,
    this.termineeLe,
    this.createdAt,
    this.consommations = const <ConsommationProduction>[],
  });

  final String id;
  final int produitId;

  /// Nom du produit fini (rempli par la jointure de lecture).
  final String produitNom;

  /// Numéro journalier « PROD-AAAAMMJJ-0001 ».
  final String? numero;

  final double quantitePrevue;
  final double quantiteReelle;

  /// Quantité prévue − quantité réelle (négatif = surplus).
  final double pertes;

  /// Coût total des matières consommées.
  final double coutMatieres;

  /// Coût de revient unitaire (matières ÷ quantité réelle).
  final double coutUnitaire;

  final StatutProduction statut;
  final String? note;
  final String? motifAnnulation;
  final DateTime? termineeLe;
  final DateTime? createdAt;

  /// Matières consommées (remplies par la lecture avec jointure).
  final List<ConsommationProduction> consommations;

  /// Pertes positives uniquement (affichage).
  double get pertesAffichees => pertes > 0 ? pertes : 0;

  /// Surplus éventuel (produit plus que prévu).
  double get surplus => pertes < 0 ? -pertes : 0;

  factory Production.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic>? produit = parseMap(map['produits']);
    return Production(
      id: parseString(map['id']),
      produitId: parseInt(map['produit_id']),
      produitNom: produit == null
          ? parseString(map['produit_nom'])
          : parseString(produit['nom']),
      numero: parseStringOrNull(map['numero']),
      quantitePrevue: parseDouble(map['quantite_prevue']),
      quantiteReelle: parseDouble(map['quantite_reelle']),
      pertes: parseDouble(map['pertes']),
      coutMatieres: parseDouble(map['cout_matieres']),
      coutUnitaire: parseDouble(map['cout_unitaire']),
      statut: StatutProduction.fromCode(parseString(map['statut'])),
      note: parseStringOrNull(map['note']),
      motifAnnulation: parseStringOrNull(map['motif_annulation']),
      termineeLe: parseDateTimeOrNull(map['terminee_le']),
      createdAt: parseDateTimeOrNull(map['created_at']),
      consommations: _consommations(map['consommations_production']),
    );
  }

  Production copyWith({
    StatutProduction? statut,
    double? quantiteReelle,
    double? pertes,
    double? coutMatieres,
    double? coutUnitaire,
  }) {
    return Production(
      id: id,
      produitId: produitId,
      produitNom: produitNom,
      numero: numero,
      quantitePrevue: quantitePrevue,
      quantiteReelle: quantiteReelle ?? this.quantiteReelle,
      pertes: pertes ?? this.pertes,
      coutMatieres: coutMatieres ?? this.coutMatieres,
      coutUnitaire: coutUnitaire ?? this.coutUnitaire,
      statut: statut ?? this.statut,
      note: note,
      motifAnnulation: motifAnnulation,
      termineeLe: termineeLe,
      createdAt: createdAt,
      consommations: consommations,
    );
  }

  static List<ConsommationProduction> _consommations(dynamic valeur) {
    if (valeur is! List) return const <ConsommationProduction>[];
    return valeur
        .whereType<Map>()
        .map((Map element) =>
            ConsommationProduction.fromMap(Map<String, dynamic>.from(element)))
        .toList(growable: false);
  }

  /// Nombre affiché « 12,5 kg » (sans zéros inutiles).
  static String nombre(double valeur) {
    if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
    return valeur
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
