// lib/models/stock_article.dart
//
// MODULE 9 — CALCULS DE STOCK (conversions multi-unités).
//
// Formule du cahier des charges :
//
//   stock_total_base = stock_base + Σ(stock_conditionnements × unités_base)
//
// Dans la base, le stock d'un article vit ENTIÈREMENT dans
// `produits.quantite` (unités de base) : les conditionnements ne portent
// qu'un FACTEUR DE CONVERSION (`quantite_unites_base`). Ce fichier fournit
// donc :
//
//   • la conversion saisie → unités de base (entrée de stock en fardes,
//     cartons…) et l'inverse (prix par unité de base) ;
//   • la DÉCOMPOSITION du stock en exemplaires de conditionnement
//     (« 1 020 bouteilles = 85 fardes ») ;
//   • les comptages d'alertes et le tri par urgence du tableau de bord.
//
// Le code est PUR (aucun import Flutter) : toutes ces règles sont testables
// sans réseau.

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/statut_stock.dart';

/// Décomposition du stock d'un article en exemplaires d'un conditionnement.
///
/// Exemple : 1 004 bouteilles avec une « Farde de 12 » → 83 fardes
/// complètes et 8 bouteilles restantes.
class DecompositionStock {
  const DecompositionStock({
    required this.conditionnement,
    required this.exemplaires,
    required this.reste,
  });

  /// Conditionnement utilisé comme unité de regroupement.
  final Conditionnement conditionnement;

  /// Nombre d'exemplaires ENTIERS contenus dans le stock.
  final int exemplaires;

  /// Unités de base non regroupées (reste de la division).
  final double reste;

  /// Quantité d'unités de base représentée par les exemplaires complets
  /// (ex. 85 fardes × 12 = 1 020 bouteilles).
  double get quantiteRegroupee =>
      exemplaires * conditionnement.quantiteUnitesBase;

  /// `true` si le stock tombe exactement sur des exemplaires entiers.
  bool get estExact => reste <= StatutStock.tolerance;
}

/// Boîte à outils des calculs de stock (fonctions pures).
class StockCalculs {
  StockCalculs._();

  // ---------------------------------------------------------------------------
  // CONVERSIONS MULTI-UNITÉS
  // ---------------------------------------------------------------------------

  /// Convertit une quantité saisie dans une unité (base ou conditionnement)
  /// en UNITÉS DE BASE.
  ///
  /// - saisie en unité de base : [quantiteUnitesBase] = 1 ;
  /// - saisie en « farde de 12 » : [quantiteUnitesBase] = 12
  ///   → `10 fardes × 12 = 120 bouteilles`.
  static double versUnitesBase({
    required double quantiteSaisie,
    required double quantiteUnitesBase,
  }) {
    if (quantiteUnitesBase <= 0) return quantiteSaisie;
    return quantiteSaisie * quantiteUnitesBase;
  }

  /// Convertit un prix exprimé « par unité saisie » en prix par UNITÉ DE BASE
  /// (colonne `prix_achat_unitaire` : 1 200 CDF la farde de 12 → 100 CDF la
  /// bouteille).
  static double prixParUniteBase({
    required double prixSaisi,
    required double quantiteUnitesBase,
  }) {
    if (quantiteUnitesBase <= 1) return prixSaisi;
    return prixSaisi / quantiteUnitesBase;
  }

  // ---------------------------------------------------------------------------
  // DÉCOMPOSITION EN CONDITIONNEMENTS
  // ---------------------------------------------------------------------------

  /// Décompose [quantite] (unités de base) selon [conditionnement].
  static DecompositionStock decomposer({
    required double quantite,
    required Conditionnement conditionnement,
  }) {
    final int exemplaires = conditionnement.exemplairesContenusDans(quantite);
    final double reste = quantite - exemplaires * conditionnement.quantiteUnitesBase;
    return DecompositionStock(
      conditionnement: conditionnement,
      exemplaires: exemplaires,
      reste: reste <= StatutStock.tolerance ? 0 : reste,
    );
  }

  /// Décompositions de l'article, une par conditionnement connu.
  static List<DecompositionStock> decompositions(Article article) {
    return article.conditionnements
        .map((Conditionnement c) =>
            decomposer(quantite: article.quantite, conditionnement: c))
        .toList(growable: false);
  }

  /// Décomposition « principale » affichée dans la liste : premier
  /// conditionnement du catalogue, ou `null` si l'article n'en a aucun.
  static DecompositionStock? decompositionPrincipale(Article article) {
    if (article.conditionnements.isEmpty) return null;
    return decomposer(
      quantite: article.quantite,
      conditionnement: article.conditionnements.first,
    );
  }

  // ---------------------------------------------------------------------------
  // TABLEAU DE BORD / ALERTES
  // ---------------------------------------------------------------------------

  /// Statut d'alerte d'un article.
  static StatutStock statut(Article article) => StatutStock.depuisStock(
        quantite: article.quantite,
        seuilAlerte: article.seuilAlerte,
      );

  /// Nombre d'articles dans un statut donné.
  static int compter(List<Article> articles, StatutStock statut) =>
      articles.where((Article a) => StockCalculs.statut(a) == statut).length;

  /// Articles en alerte (faibles ou en rupture), du plus urgent au moins.
  static List<Article> enAlerte(List<Article> articles) {
    final List<Article> alertes =
        articles.where((Article a) => StockCalculs.statut(a).estAlerte).toList();
    return trierParUrgence(alertes);
  }

  /// Tri « tableau de bord » : rupture d'abord, puis faible, puis OK ;
  /// à statut égal, ordre alphabétique.
  static List<Article> trierParUrgence(List<Article> articles) {
    final List<Article> copie = List<Article>.of(articles);
    copie.sort((Article a, Article b) {
      final int parStatut =
          StockCalculs.statut(a).priorite.compareTo(StockCalculs.statut(b).priorite);
      if (parStatut != 0) return parStatut;
      return a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
    });
    return copie;
  }

  /// Valeur du stock au prix d'achat (unités de base × prix d'achat).
  static double valeurAchat(List<Article> articles) {
    double total = 0;
    for (final Article article in articles) {
      total += article.quantite * article.prixAchat;
    }
    return total;
  }
}
