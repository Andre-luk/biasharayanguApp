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
  LignePanier({
    required this.vendu,
    this.quantite = 1,
    this.prixNegocie,
    this.estCadeau = false,
  });

  /// Article (et conditionnement éventuel) vendu.
  final ArticleScanne vendu;

  /// Quantité commandée, exprimée en unités vendues.
  double quantite;

  /// 🛒 MODULE 25 — prix unitaire NÉGOCIÉ accepté par le vendeur.
  ///
  /// `null` = la ligne est vendue au prix du catalogue. Le prix catalogue de
  /// l'article (`vendu.prixUnitaire`) n'est jamais modifié : ce champ ne décrit
  /// que CETTE vente.
  double? prixNegocie;

  /// 🎁 Cadeau commercial : la ligne sort du stock mais n'est pas facturée.
  final bool estCadeau;

  /// Identifiant de la ligne : code du QR scanné (`PROD:…` / `COND:…`).
  String get cle => vendu.code;

  /// Identifiant stable de la ligne (clé du panier) — API du Module 8.
  String get itemId => cle;

  /// Identifiant de l'article en base.
  int get produitId => vendu.produitId;

  /// 🔴 CORRECTIF 78 — identifiant de l'article dans la copie LOCALE (SQLite).
  ///
  /// `produitId` est le numéro de la base (celui que le serveur comprend) ;
  /// le stock du téléphone et la vente hors ligne, eux, se repèrent avec le
  /// numéro local. `null` pour une ligne scannée : on la retrouve alors par
  /// `supabase_id`.
  int? get produitIdLocal => vendu.produitIdLocal;

  /// Conditionnement vendu, ou `null` pour l'unité de base.
  String? get conditionnementId => vendu.conditionnement?.id;

  /// Nom de l'article.
  String get nom => vendu.nom;

  /// Prix d'une unité vendue (relu dans la base au moment du scan).
  ///
  /// 💵 MODULE 29 — TOUJOURS dans la devise de l'ENTREPRISE : un article
  /// prixé en dollars est converti au taux du jour. Les totaux du panier,
  /// de la facture et de la caisse restent ainsi dans une seule monnaie.
  double get prixUnitaire => vendu.prixUnitaireEntreprise;

  /// Prix dans la devise de l'ARTICLE (affichage seulement).
  double get prixUnitaireDevise => vendu.prixUnitaire;

  /// Devise du prix de l'article (`null` = celle de l'entreprise).
  String? get devise => vendu.devise;

  /// Prix unitaire RÉELLEMENT appliqué (négocié s'il existe).
  double get prixUnitaireEffectif => estCadeau ? 0 : (prixNegocie ?? prixUnitaire);

  /// Prix unitaire au catalogue (référence de la négociation).
  double get prixUnitaireCatalogue => prixUnitaire;

  /// Y a-t-il eu un accord de prix sur cette ligne ?
  bool get estNegociee =>
      !estCadeau &&
      prixNegocie != null &&
      (prixNegocie! - prixUnitaire).abs() > 0.005;

  /// Montant accordé au client sur cette ligne (catalogue − négocié).
  double get remiseNegociation =>
      estNegociee ? (prixUnitaire - prixNegocie!) * quantite : 0;

  /// Total de la ligne AVANT négociation (prix catalogue).
  double get totalCatalogue => prixUnitaire * quantite;

  /// Total de la ligne : `quantité × prix appliqué` (0 pour un cadeau).
  double get total => prixUnitaireEffectif * quantite;

  /// Sous-total de la ligne (alias métier de [total]).
  double get sousTotal => total;

  /// Unités de base consommées dans le stock (12 par farde de 12…).
  double get unitesBase => vendu.unitesBasePour(quantite);

  /// Libellé affiché dans le panier et sur la facture.
  String get libelle => vendu.libelleComplet;

  @override
  String toString() => '$libelle × $quantite = $total';
}
