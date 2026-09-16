// lib/models/ligne_panier.dart
//
// MODULE 7 — SCANNER VENDEUR : une ligne du panier.
//
// Le panier est tenu par `PanierService` ; chaque ligne associe :
//   • l'article scanné ([ArticleScanne]) — avec son éventuel conditionnement ;
//   • la quantité choisie (en unités vendues : bouteilles, fardes, kg…).
//
// Une ligne est identifiée par le CODE de l'objet vendu :
//   • « PROD:123 »  → l'unité de base de l'article 123 ;
//   • « COND:uuid » → le conditionnement correspondant.
// Scanner deux fois le même code cumule donc les quantités sur la même ligne,
// tandis qu'une farde et une bouteille du même article restent distinctes.

import 'package:biashara_yangu/models/article_scanne.dart';

/// Ligne du panier (article ou conditionnement + quantité).
class LignePanier {
  LignePanier({required this.vendu, this.quantite = 1});

  /// Article (et conditionnement éventuel) vendu.
  final ArticleScanne vendu;

  /// Quantité commandée, exprimée en unités vendues.
  double quantite;

  /// Identifiant de la ligne : code du QR scanné (`PROD:…` / `COND:…`).
  String get cle => vendu.code;

  /// Identifiant stable de la ligne (clé du panier) — API du Module 8.
  String get itemId => cle;

  /// Identifiant de l'article en base.
  int get produitId => vendu.produitId;

  /// Conditionnement vendu, ou `null` pour l'unité de base.
  String? get conditionnementId => vendu.conditionnement?.id;

  /// Nom de l'article.
  String get nom => vendu.nom;

  /// Prix d'une unité vendue (relu dans la base au moment du scan).
  double get prixUnitaire => vendu.prixUnitaire;

  /// Total de la ligne : `quantité × prix unitaire`.
  double get total => prixUnitaire * quantite;

  /// Sous-total de la ligne (alias métier de [total]).
  double get sousTotal => total;

  /// Unités de base consommées dans le stock (12 par farde de 12…).
  double get unitesBase => vendu.unitesBasePour(quantite);

  /// Libellé affiché dans le panier et sur la facture.
  String get libelle => vendu.libelleComplet;

  @override
  String toString() => '$libelle × $quantite = $total';
}
