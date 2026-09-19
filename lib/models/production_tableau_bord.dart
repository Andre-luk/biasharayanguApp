// lib/models/production_tableau_bord.dart
//
// 🥖 MODULE 16 (phase C5) — BOULANGERIE : TABLEAU DE BORD DE L'ATELIER.
//
// Réponse de `rpc_production_tableau_bord()` : alertes matières,
// productions du jour (quantité, pertes, coût) et dernières productions.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Une production récente affichée sur le tableau de bord.
class ProductionResume {
  const ProductionResume({
    required this.id,
    required this.produit,
    this.numero,
    this.statut = 'en_cours',
    this.quantitePrevue = 0,
    this.quantiteReelle = 0,
    this.pertes = 0,
    this.coutMatieres = 0,
    this.coutUnitaire = 0,
    this.date = '',
  });

  final String id;
  final String? numero;
  final String produit;
  final String statut;
  final double quantitePrevue;
  final double quantiteReelle;
  final double pertes;
  final double coutMatieres;
  final double coutUnitaire;

  /// Date déjà formatée « JJ/MM/AAAA HH:MM » par le serveur.
  final String date;

  factory ProductionResume.fromMap(Map<String, dynamic> map) {
    return ProductionResume(
      id: parseString(map['id']),
      numero: parseStringOrNull(map['numero']),
      produit: parseString(map['produit'], fallback: 'Production'),
      statut: parseString(map['statut'], fallback: 'en_cours'),
      quantitePrevue: parseDouble(map['quantite_prevue']),
      quantiteReelle: parseDouble(map['quantite_reelle']),
      pertes: parseDouble(map['pertes']),
      coutMatieres: parseDouble(map['cout_matieres']),
      coutUnitaire: parseDouble(map['cout_unitaire']),
      date: parseString(map['date']),
    );
  }
}

/// Dashboard de l'atelier (jour).
class TableauBordProduction {
  const TableauBordProduction({
    this.matieres = 0,
    this.matieresAlerte = 0,
    this.productionsJour = 0,
    this.quantiteJour = 0,
    this.pertesJour = 0,
    this.coutJour = 0,
    this.dernieres = const <ProductionResume>[],
  });

  /// Matières premières actives.
  final int matieres;

  /// Matières au niveau (ou sous) le seuil d'alerte.
  final int matieresAlerte;

  /// Productions terminées aujourd'hui.
  final int productionsJour;

  /// Quantité totale produite aujourd'hui.
  final double quantiteJour;

  /// Pertes cumulées du jour (positives uniquement).
  final double pertesJour;

  /// Coût matières du jour.
  final double coutJour;

  final List<ProductionResume> dernieres;

  factory TableauBordProduction.fromMap(Map<String, dynamic> map) {
    return TableauBordProduction(
      matieres: parseInt(map['matieres']),
      matieresAlerte: parseInt(map['matieres_alerte']),
      productionsJour: parseInt(map['productions_jour']),
      quantiteJour: parseDouble(map['quantite_jour']),
      pertesJour: parseDouble(map['pertes_jour']),
      coutJour: parseDouble(map['cout_jour']),
      dernieres: _liste(map['dernieres']),
    );
  }

  static List<ProductionResume> _liste(dynamic valeur) {
    if (valeur is! List) return const <ProductionResume>[];
    return valeur
        .whereType<Map>()
        .map((Map element) =>
            ProductionResume.fromMap(Map<String, dynamic>.from(element)))
        .toList(growable: false);
  }
}
