// lib/models/statut_stock.dart
//
// MODULE 9 — STATUT D'ALERTE D'UN ARTICLE.
//
// Le statut se déduit du stock (unités de base) et du seuil d'alerte de
// l'article (`produits.seuil_alerte`) :
//
//   • Rupture — stock = 0 (ou négatif) : alerte urgente ;
//   • Faible  — stock ≤ seuil : à réapprovisionner ;
//   • OK      — stock > seuil.
//
// Ce fichier est volontairement PUR (aucun import Flutter) : la logique
// d'alerte est testable sans réseau ni interface.

/// Statut d'alerte du stock d'un article.
enum StatutStock {
  ok('OK'),
  faible('Faible'),
  rupture('Rupture');

  const StatutStock(this.libelle);

  /// Libellé affichable en français.
  final String libelle;

  /// `true` si l'article demande une action (faible ou en rupture).
  bool get estAlerte => this != StatutStock.ok;

  /// Ordre d'affichage : les ruptures d'abord, puis les articles faibles.
  int get priorite => switch (this) {
        StatutStock.rupture => 0,
        StatutStock.faible => 1,
        StatutStock.ok => 2,
      };

  /// Statut d'un article d'après son stock et son seuil.
  ///
  /// [quantite] et [seuilAlerte] sont exprimés en UNITÉS DE BASE.
  /// Un seuil nul ou négatif désactive l'alerte « Faible » : seules les
  /// ruptures sont alors signalées.
  static StatutStock depuisStock({
    required double quantite,
    required double seuilAlerte,
  }) {
    if (quantite <= tolerance) return StatutStock.rupture;
    if (seuilAlerte > 0 && quantite <= seuilAlerte + tolerance) {
      return StatutStock.faible;
    }
    return StatutStock.ok;
  }

  /// Tolérance des comparaisons de quantités (arrondis de la base `real`).
  static const double tolerance = 0.000001;
}
