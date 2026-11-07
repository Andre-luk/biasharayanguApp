// lib/services/panier_service.dart
//
// MODULE 7 — LE PANIER PARTAGÉ DE LA BOUTIQUE.
//
// Un seul panier pour toute la session de vente : l'écran de caisse
// (`NewSalePage`) et le scanner vendeur y ajoutent leurs lignes. Une vente
// encaissée vide le panier.
//
// Chaque ligne est identifiée par le code scanné (`PROD:…` / `COND:…`) :
//   • scanner deux fois le même code cumule les quantités ;
//   • une farde et une bouteille du même article restent deux lignes
//     distinctes (prix et unités différents).
//
// [revision] est notifiée à chaque modification : les écrans s'y abonnent
// pour se rafraîchir (badge, total…).
//
// 📌 Les quantités sont PLAFONNÉES au stock disponible lu lors du scan :
// le vendeur ne peut jamais mettre au panier plus qu'il n'y a en rayon.

import 'package:flutter/foundation.dart';

import 'package:biashara_yangu/models/article_scanne.dart';
import 'package:biashara_yangu/models/ligne_panier.dart';
import 'package:biashara_yangu/models/parametres_vente.dart';

/// Panier en mémoire de la session de vente.
///
/// Singleton : `PanierService.instance`.
class PanierService {
  PanierService._();

  static final PanierService instance = PanierService._();

  final Map<String, LignePanier> _lignes = <String, LignePanier>{};

  // ---------------------------------------------------------------- MODULE 25
  // Flexibilité commerciale : réduction globale et cadeaux. Ces valeurs
  // appartiennent à la vente EN COURS et disparaissent dès que le panier est
  // vidé (vente confirmée, annulation, déconnexion).
  double _remiseValeur = 0;
  TypeReduction _remiseType = TypeReduction.montant;
  final Map<String, CadeauPanier> _cadeaux = <String, CadeauPanier>{};

  /// Notifiée à chaque modification du panier (ajout, retrait, vidage).
  ///
  /// La valeur elle-même n'est qu'un compteur de version ; seul son
  /// changement importe.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  // ---------------------------------------------------------------------------
  // LECTURE
  // ---------------------------------------------------------------------------

  /// Lignes du panier, dans l'ordre d'ajout.
  List<LignePanier> get lignes =>
      List<LignePanier>.unmodifiable(_lignes.values);

  /// Aucune ligne au panier.
  bool get estVide => _lignes.isEmpty;

  /// Nombre de lignes (pour les badges « 3 articles »).
  int get nombreLignes => _lignes.length;

  /// Somme des quantités de toutes les lignes (unités vendues mélangées).
  double get quantiteTotale {
    double somme = 0;
    for (final LignePanier ligne in _lignes.values) {
      somme += ligne.quantite;
    }
    return somme;
  }

  /// Montant total du panier (CDF), avant réduction globale et hors cadeaux.
  ///
  /// C'est le total APRÈS négociations de lignes : ce que le serveur appellera
  /// `total_initial` avant application de la réduction du panier.
  double total() {
    double somme = 0;
    for (final LignePanier ligne in _lignes.values) {
      somme += ligne.total;
    }
    return ReglesVenteFlexible.arrondi(somme);
  }

  /// Total au PRIX CATALOGUE (référence de la négociation).
  double totalCatalogue() {
    double somme = 0;
    for (final LignePanier ligne in _lignes.values) {
      somme += ligne.totalCatalogue;
    }
    return ReglesVenteFlexible.arrondi(somme);
  }

  /// Montant accordé par négociation sur l'ensemble des lignes.
  double montantNegociation() {
    double somme = 0;
    for (final LignePanier ligne in _lignes.values) {
      somme += ligne.remiseNegociation;
    }
    return ReglesVenteFlexible.arrondi(somme);
  }

  /// Nombre de lignes négociées.
  int get nombreLignesNegociees =>
      _lignes.values.where((LignePanier l) => l.estNegociee).length;

  /// Réduction globale telle que saisie (montant ou pourcentage).
  double get remiseValeur => _remiseValeur;

  TypeReduction get remiseType => _remiseType;

  /// Réduction globale RÉELLEMENT déduite du total.
  double montantRemise() => ReglesVenteFlexible.remiseEnMontant(
        base: total(),
        valeur: _remiseValeur,
        type: _remiseType,
      );

  /// Ce que le client paie réellement.
  double totalAPayer() => ReglesVenteFlexible.arrondi(
        (total() - montantRemise()).clamp(0, double.infinity),
      );

  // ------------------------------------------------------------------ CADEAUX

  /// Produits offerts, dans l'ordre d'ajout.
  List<CadeauPanier> get cadeaux =>
      List<CadeauPanier>.unmodifiable(_cadeaux.values);

  /// Nombre total d'unités offertes.
  double get quantiteCadeaux {
    double somme = 0;
    for (final CadeauPanier cadeau in _cadeaux.values) {
      somme += cadeau.quantite;
    }
    return somme;
  }

  /// Valeur des cadeaux au prix du catalogue.
  double valeurCadeaux() {
    double somme = 0;
    for (final CadeauPanier cadeau in _cadeaux.values) {
      somme += cadeau.valeur;
    }
    return ReglesVenteFlexible.arrondi(somme);
  }

  CadeauPanier? cadeau(String cle) => _cadeaux[cle];

  /// Nombre d'articles du panier — somme des quantités (arrondie).
  ///
  /// Les unités peuvent être hétérogènes (fardes, bouteilles, kg) : cet
  /// indicateur sert de repère visuel, pas de calcul de facturation.
  int nombreArticles() => quantiteTotale.round();

  /// Quantité d'une ligne, par clé (`PROD:123`, `COND:uuid`).
  double quantiteDe(String cle) => _lignes[cle]?.quantite ?? 0;

  /// Quantité déjà au panier pour l'objet scanné.
  double quantiteDeArticle(ArticleScanne vendu) => quantiteDe(vendu.code);

  /// Quantité au panier pour l'UNITÉ DE BASE d'un article (écran de caisse).
  double quantiteProduit(int produitId) => quantiteDe('PROD:$produitId');

  /// 🧾 MODULE 27 — TOUTES LES LIGNES D'UN ARTICLE, FORMATS COMPRIS.
  ///
  /// ⚠️ `quantiteProduit()` ne compte QUE la ligne « à l'unité » (`PROD:…`).
  /// Or une farde est rangée sous `COND:…` : l'écran de caisse croyait donc
  /// que rien n'était au panier après l'ajout d'un emballage, et le bouton
  /// « + » créait une seconde ligne à l'unité au lieu d'augmenter la farde.
  /// Cette méthode rassemble toutes les lignes d'un même article.
  List<LignePanier> lignesProduit(int produitId) {
    return _lignes.values
        .where((LignePanier ligne) => ligne.produitId == produitId)
        .toList(growable: false);
  }

  /// Unités de BASE d'un article déjà au panier, tous formats confondus
  /// (2 fardes de 12 + 3 bouteilles = 27 bouteilles).
  double unitesBaseProduit(int produitId) {
    double somme = 0;
    for (final LignePanier ligne in lignesProduit(produitId)) {
      somme += ligne.unitesBase;
    }
    return somme;
  }

  /// Ligne correspondant à une clé, ou `null`.
  LignePanier? ligne(String cle) => _lignes[cle];

  // ---------------------------------------------------------------------------
  // ÉCRITURE
  // ---------------------------------------------------------------------------

  /// Ajoute une ligne complète (API Module 8). Les quantités du même
  /// article/conditionnement se cumulent, plafonnées au stock. Renvoie la
  /// quantité finale enregistrée.
  double ajouter(LignePanier ligne) {
    if (ligne.quantite <= 0) return quantiteDe(ligne.cle);
    final double souhaitee = quantiteDe(ligne.cle) + ligne.quantite;
    return definirQuantite(ligne.vendu, souhaitee);
  }

  /// Ajoute [quantite] unités vendues d'un article scanné (scanner/caisse).
  double ajouterArticle(ArticleScanne vendu, {double quantite = 1}) {
    if (quantite <= 0) return quantiteDe(vendu.code);
    final double souhaitee = quantiteDe(vendu.code) + quantite;
    return definirQuantite(vendu, souhaitee);
  }

  /// Modifie la quantité d'une ligne identifiée par son [itemId].
  ///
  /// Une quantité nulle ou négative supprime la ligne. La valeur est
  /// plafonnée au stock disponible ; renvoie la quantité réellement
  /// enregistrée (0 si la ligne a été retirée).
  double modifierQuantite(String itemId, double nouvelleQuantite) {
    final LignePanier? ligne = _lignes[itemId];
    if (ligne == null) return 0;
    return definirQuantite(ligne.vendu, nouvelleQuantite);
  }

  /// Supprime une ligne du panier (API Module 8 — équivalent de [retirer]).
  void supprimer(String itemId) => retirer(itemId);

  /// Fixe la quantité d'une ligne (0 ou moins : la retire), plafonnée au
  /// stock disponible. Renvoie la quantité réellement enregistrée.
  double definirQuantite(ArticleScanne vendu, double quantite) {
    if (quantite <= 0) {
      retirer(vendu.code);
      return 0;
    }

    final double maximum = vendu.quantiteMaxVendable;
    final double finale =
        maximum > 0 && quantite > maximum ? maximum : quantite;
    if (finale <= 0) {
      retirer(vendu.code);
      return 0;
    }

    // 🛒 MODULE 25 — un changement de quantité ne doit JAMAIS effacer le prix
    // négocié : on reprend la ligne existante avant de la remplacer.
    final LignePanier? existante = _lignes[vendu.code];
    _lignes[vendu.code] = LignePanier(
      vendu: vendu,
      quantite: finale,
      prixNegocie: existante?.prixNegocie,
    );
    _notifier();
    return finale;
  }

  // ---------------------------------------------------------------------------
  // MODULE 25 — NÉGOCIATION, RÉDUCTION, CADEAUX
  // ---------------------------------------------------------------------------

  /// Applique un prix unitaire négocié à une ligne.
  ///
  /// `null` (ou un prix égal au catalogue) rétablit le prix normal.
  /// Renvoie le prix réellement appliqué, catalogue compris.
  double definirPrixNegocie(String cle, double? prix) {
    final LignePanier? ligne = _lignes[cle];
    if (ligne == null) return 0;

    if (prix == null || (prix - ligne.prixUnitaire).abs() <= 0.005) {
      ligne.prixNegocie = null;
    } else if (prix > 0 && prix <= ligne.prixUnitaire) {
      ligne.prixNegocie = ReglesVenteFlexible.arrondi(prix);
    } else {
      // Prix invalide : on ne touche à rien.
      return ligne.prixUnitaireEffectif;
    }
    _notifier();
    return ligne.prixUnitaireEffectif;
  }

  /// Fixe la réduction globale du panier.
  void definirRemise(double valeur, {TypeReduction type = TypeReduction.montant}) {
    _remiseValeur = valeur <= 0 ? 0 : valeur;
    _remiseType = type;
    _notifier();
  }

  /// Supprime la réduction globale.
  void effacerRemise() {
    if (_remiseValeur == 0) return;
    _remiseValeur = 0;
    _remiseType = TypeReduction.montant;
    _notifier();
  }

  /// Ajoute (ou cumule) un produit offert.
  void ajouterCadeau(CadeauPanier cadeau) {
    if (cadeau.quantite <= 0) return;
    final CadeauPanier? existant = _cadeaux[cadeau.cle];
    if (existant == null) {
      _cadeaux[cadeau.cle] = cadeau;
    } else {
      _cadeaux[cadeau.cle] = CadeauPanier(
        produitId: existant.produitId,
        nom: existant.nom,
        prixCatalogue: existant.prixCatalogue,
        quantite: existant.quantite + cadeau.quantite,
        quantiteBase: existant.quantiteBase + cadeau.quantiteBase,
        conditionnementId: existant.conditionnementId,
        unite: existant.unite,
        stockDisponible: existant.stockDisponible,
      );
    }
    _notifier();
  }

  /// Retire un cadeau du panier.
  void retirerCadeau(String cle) {
    if (_cadeaux.remove(cle) != null) _notifier();
  }

  void effacerCadeaux() {
    if (_cadeaux.isEmpty) return;
    _cadeaux.clear();
    _notifier();
  }

  /// Retire une ligne du panier.
  void retirer(String cle) {
    if (_lignes.remove(cle) != null) _notifier();
  }

  /// Vide complètement le panier (vente enregistrée, annulation, déconnexion).
  void vider() {
    if (_lignes.isEmpty && _cadeaux.isEmpty && _remiseValeur == 0) return;
    _lignes.clear();
    _cadeaux.clear();
    _remiseValeur = 0;
    _remiseType = TypeReduction.montant;
    _notifier();
  }

  void _notifier() => revision.value++;
}
