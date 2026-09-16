// lib/models/article_scanne.dart
//
// MODULE 7 — SCANNER VENDEUR : l'article prêt à être vendu.
//
// Un QR code scanné désigne soit :
//   • un ARTICLE vendu à l'unité de base      (« PROD:123 »   → bouteille) ;
//   • un CONDITIONNEMENT vendu par emballage  (« COND:<uuid> » → farde de 12).
//
// [ArticleScanne] rassemble les deux cas et expose tout ce dont l'interface
// du vendeur a besoin : prix unitaire, unité vendue, stock disponible…
//
// ⚠️ RÈGLES ABSOLUES (cahier des charges Module 7)
//   • le prix et le stock proviennent TOUJOURS de la base de données au
//     moment du scan — jamais du QR code (une étiquette n'encode aucun prix) ;
//   • seul un PROPRIÉTAIRE ou son MAGASINIER modifie ces valeurs : l'écran du
//     vendeur ne fait que les lire.

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/produit.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Article (et éventuel conditionnement) identifié par un scan.
class ArticleScanne {
  const ArticleScanne({
    required this.article,
    this.conditionnement,
  });

  /// Article de base, relu dans `public.produits`.
  final Article article;

  /// Conditionnement scanné, ou `null` quand l'unité de base est vendue.
  final Conditionnement? conditionnement;

  /// Construit l'article scanné depuis la copie locale (SQLite) d'un produit.
  ///
  /// Utilisé par l'écran de vente classique, qui travaille avec [Produit] :
  /// les deux représentations désignent la même ligne de `public.produits`.
  factory ArticleScanne.depuisProduit(Produit produit) {
    return ArticleScanne(
      article: Article(
        id: produit.id ?? 0,
        nom: produit.nom,
        categorie: produit.categorie,
        prixAchat: produit.prixAchat,
        prixVente: produit.prixVente,
        quantite: produit.quantite,
        uniteMesure: produit.uniteMesure,
        photo: produit.photo,
        ownerId: produit.ownerId,
      ),
    );
  }

  /// Identifiant de l'article en base.
  int get produitId => article.id;

  /// Nom de l'article.
  String get nom => article.nom;

  /// Code QR correspondant : `PROD:<id>` ou `COND:<qr_code_id>`.
  String get code => conditionnement == null
      ? 'PROD:${article.id}'
      : 'COND:${conditionnement!.qrCodeId}';

  /// `true` quand c'est un emballage (farde, carton…) qui est vendu.
  bool get estConditionnement => conditionnement != null;

  /// Libellé du conditionnement (« Farde de 12 »), vide pour l'unité de base.
  String get libelleConditionnement => conditionnement?.libelle ?? '';

  /// Libellé complet : « Eau Casino — Farde de 12 ».
  String get libelleComplet {
    if (conditionnement == null) return article.nom;
    return '${article.nom} — ${conditionnement!.libelle}';
  }

  /// Prix de vente d'UNE unité vendue (unité de base ou un exemplaire
  /// d'emballage) — lu dans la base au moment du scan.
  double get prixUnitaire => conditionnement?.prixVente ?? article.prixVente;

  /// Unité vendue : le libellé du conditionnement, ou l'unité de base.
  String get uniteVente =>
      conditionnement?.libelle ?? article.uniteMesure;

  /// Unité vendue accordée à [quantite] (« 2 fardes », « 1,5 kg »).
  ///
  /// Le libellé d'un conditionnement n'est jamais pluralisé (« Farde de 12 »),
  /// seule l'unité de base l'est.
  String uniteVentePlurielle(double quantite) =>
      conditionnement?.libelle ?? pluriel(article.uniteMesure, quantite);

  /// Unités de base consommées par 1 unité vendue (12 pour « Farde de 12 »).
  double get unitesBaseParVente =>
      conditionnement?.quantiteUnitesBase ?? 1;

  /// Stock disponible, exprimé en UNITÉS DE BASE.
  double get stockUnitesBase => article.quantite;

  /// Quantité maximale vendable, exprimée en unités vendues.
  ///
  /// Pour un conditionnement, seuls des emballages COMPLETS sont vendus :
  /// 34 bouteilles et une farde de 12 → 2 fardes vendables.
  double get quantiteMaxVendable {
    if (conditionnement == null) return article.quantite;
    return conditionnement!.exemplairesContenusDans(article.quantite).toDouble();
  }

  /// `true` quand plus rien ne peut être vendu (stock nul ou emballage
  /// incomplet).
  bool get enRupture => quantiteMaxVendable <= 0;

  /// Unités de base nécessaires pour vendre [quantite] unités vendues.
  double unitesBasePour(double quantite) => quantite * unitesBaseParVente;

  /// Résume le stock affiché dans la fiche d'ajout au panier.
  ///
  /// Exemples :
  ///   • « Stock : 120 bouteilles » ;
  ///   • « Stock : 34 bouteilles — 2 × Farde de 12 ».
  String resumeStock() {
    final String unites =
        '${_quantiteTexte(stockUnitesBase)} '
        '${pluriel(article.uniteMesure, stockUnitesBase)}';

    if (conditionnement == null) return 'Stock : $unites';

    final int exemplaires = quantiteMaxVendable.truncate();
    if (exemplaires <= 0) {
      return 'Stock : $unites — aucun ${conditionnement!.libelle} complet '
          'disponible.';
    }
    return 'Stock : $unites — $exemplaires × ${conditionnement!.libelle}.';
  }

  /// Prix affiché du sous-total : `quantite × prix unitaire`.
  double sousTotal(double quantite) => prixUnitaire * quantite;

  /// Prix unitaire formaté (« 12 000 CDF »).
  String prixUnitaireTexte() => formatMontant(prixUnitaire);

  /// Sous-total formaté (« 24 000 CDF »).
  String sousTotalTexte(double quantite) => formatMontant(sousTotal(quantite));
}

/// Pluriel simple des unités (« bouteille » → « bouteilles »).
///
/// Réutilise la règle du Module 5 ([Conditionnement.pluriel]) pour que le
/// scanner et le catalogue écrivent les unités de la même façon.
String pluriel(String unite, double quantite) =>
    Conditionnement.pluriel(unite, quantite);

/// « 12 » pour une quantité entière, « 2,5 » sinon.
String _quantiteTexte(double valeur) {
  if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
  return valeur
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}
