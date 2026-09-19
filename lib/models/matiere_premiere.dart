// lib/models/matiere_premiere.dart
//
// 🥖 MODULE 16 (phase C5) — BOULANGERIE : MATIÈRE PREMIÈRE.
//
// Farine, levure, sucre… suivies en stock avec un seuil d'alerte et un
// prix unitaire (dernier prix payé — base du coût de revient).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Une matière première — table `public.matieres_premieres`.
class MatierePremiere {
  const MatierePremiere({
    required this.id,
    required this.nom,
    this.unite = 'kg',
    this.stock = 0,
    this.seuilAlerte = 0,
    this.prixUnitaire = 0,
    this.actif = true,
  });

  final String id;
  final String nom;

  /// Unité de mesure : kg, g, l, pièce…
  final String unite;

  final double stock;
  final double seuilAlerte;

  /// Dernier prix payé par unité.
  final double prixUnitaire;

  final bool actif;

  /// Le stock est au niveau (ou sous) le seuil d'alerte.
  bool get enAlerte => stock <= seuilAlerte;

  /// Désignation courte (« Farine T55 (kg) »).
  String get designation => '$nom ($unite)';

  factory MatierePremiere.fromMap(Map<String, dynamic> map) {
    return MatierePremiere(
      id: parseString(map['id']),
      nom: parseString(map['nom'], fallback: 'Matière'),
      unite: parseString(map['unite'], fallback: 'kg'),
      stock: parseDouble(map['stock']),
      seuilAlerte: parseDouble(map['seuil_alerte']),
      prixUnitaire: parseDouble(map['prix_unitaire']),
      actif: map['actif'] == null ? true : map['actif'] == true,
    );
  }
}
