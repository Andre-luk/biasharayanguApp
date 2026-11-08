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
import 'package:biashara_yangu/utils/devise_produit.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Article (et éventuel conditionnement) identifié par un scan.
class ArticleScanne {
  const ArticleScanne({
    required this.article,
    this.conditionnement,
    this.idServeurEnAttente = false,
    this.produitIdLocal,
    this.poidsImpose,
  });

  /// Article de base, relu dans `public.produits`.
  final Article article;

  /// Conditionnement scanné, ou `null` quand l'unité de base est vendue.
  final Conditionnement? conditionnement;

  /// `true` quand la ligne vient d'un article local **pas encore envoyé** au
  /// serveur (correctif 77) : sa vente doit attendre la synchronisation.
  final bool idServeurEnAttente;

  /// 🔴 CORRECTIF 78 — LE NUMÉRO LOCAL, INDISPENSABLE AU STOCK DU TÉLÉPHONE.
  ///
  /// `article.id` est le numéro de la BASE (celui que le serveur comprend).
  /// La copie locale SQLite a le sien, différent : c'est lui qu'il faut pour
  /// décrémenter le stock du téléphone et enregistrer une vente hors ligne.
  ///
  /// Les deux doivent donc voyager ensemble : sans [produitIdLocal],
  /// l'enregistrement local répond « Produit ID 503 introuvable ».
  final int? produitIdLocal;

  /// ⚖️ MODULE 23 — POIDS LU SUR L'ÉTIQUETTE DE LA BALANCE (`BAL:id:grammes`).
  ///
  /// `null` = pas de pesée dans le code : le vendeur saisit le poids.
  final double? poidsImpose;

  /// Copie avec un poids imposé par l'étiquette de la balance.
  ArticleScanne avecPoids(double poids) {
    return ArticleScanne(
      article: article,
      conditionnement: conditionnement,
      idServeurEnAttente: idServeurEnAttente,
      produitIdLocal: produitIdLocal,
      poidsImpose: poids,
    );
  }

  /// Construit l'article scanné depuis la copie locale (SQLite) d'un produit.
  ///
  /// Utilisé par l'écran de vente classique, qui travaille avec [Produit].
  ///
  /// 🔴 CORRECTIF 77 — C'EST ICI QUE SE JOUAIT LA PANNE.
  ///
  /// On prenait `produit.id` — l'identifiant **LOCAL** de SQLite — pour
  /// l'identifiant serveur. Le panier envoyait donc « 83 » à
  /// `rpc_vente_valider`, qui répondait « Article n° 83 introuvable : il a
  /// peut-être été supprimé. » alors que l'article existait bel et bien (sous
  /// son vrai numéro, par exemple 503).
  ///
  /// C'est pourquoi la vente fonctionnait au SCANNER (le scan relit l'article
  /// dans la base, donc avec le bon numéro) et échouait depuis la LISTE de la
  /// caisse.
  ///
  /// Désormais on envoie [Produit.idServeur]. Si l'article n'a pas encore été
  /// envoyé au serveur, [idServeurEnAttente] vaut `true` : la caisse prévient
  /// au lieu de laisser le serveur refuser.
  factory ArticleScanne.depuisProduit(
    Produit produit, {
    Conditionnement? conditionnement,
  }) {
    final int? idServeur = produit.idServeur;
    return ArticleScanne(
      article: Article(
        id: idServeur ?? produit.id ?? 0,
        nom: produit.nom,
        categorie: produit.categorie,
        prixAchat: produit.prixAchat,
        prixVente: produit.prixVente,
        quantite: produit.quantite,
        uniteMesure: produit.uniteMesure,
        photo: produit.photo,
        ownerId: produit.ownerId,
        // 💵 MODULE 29 — la devise suit l'article jusqu'au panier.
        devise: produit.devise,
      ),
      conditionnement: conditionnement,
      idServeurEnAttente: idServeur == null,
      produitIdLocal: produit.id,
    );
  }

  /// Identifiant de l'article en base.
  int get produitId => article.id;

  /// Nom de l'article.
  String get nom => article.nom;

  /// Code QR correspondant : `PROD:<id>` ou `COND:<qr_code_id>`.
  ///
  /// 🧾 MODULE 27 — Si un conditionnement n'a pas encore de `qr_code_id`
  /// (emballage créé hors ligne), on retombe sur son IDENTIFIANT. Sans cela
  /// tous ces emballages partageaient la clé `COND:` et se remplaçaient les
  /// uns les autres dans le panier : le produit ajouté « ne s'affichait pas ».
  String get code {
    if (conditionnement == null) return 'PROD:${article.id}';
    final String qr = conditionnement!.qrCodeId.trim();
    return 'COND:${qr.isNotEmpty ? qr : conditionnement!.id}';
  }

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
  ///
  /// 💵 MODULE 29 — ce prix est exprimé dans la devise de l'ARTICLE
  /// (`article.devise`), celle que le commerçant a saisie.
  double get prixUnitaire => conditionnement?.prixVente ?? article.prixVente;

  /// 💵 MODULE 29 — le même prix, converti dans la devise de l'ENTREPRISE.
  ///
  /// C'est cette valeur qui alimente le panier, la facture et la caisse : on
  /// n'additionne jamais deux devises. Le taux est celui du jour.
  double get prixUnitaireEntreprise =>
      versDeviseEntreprise(prixUnitaire, article.devise);

  /// Devise du prix de cet article (`null` = celle de l'entreprise).
  String? get devise => article.devise;

  /// Le prix est-il dans une autre devise que celle de l'entreprise ?
  bool get deviseDifferenteDeEntreprise =>
      deviseDifferente(article.devise);

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

  /// 🥩 MODULE 16 C6 (boucherie) — l'objet vendu se pèse-t-il ?
  ///
  /// Vrai seulement pour l'unité de base marquée « vendable au poids »
  /// (un conditionnement reste vendu à la pièce).
  bool get vendableAuPoids =>
      conditionnement == null && article.vendableAuPoids;

  /// Pas des boutons + / − de la quantité : 0,5 kg pour un article pesé,
  /// 1 sinon.
  double get pasQuantite => vendableAuPoids ? 0.5 : 1;

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
