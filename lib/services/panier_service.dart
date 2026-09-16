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

/// Panier en mémoire de la session de vente.
///
/// Singleton : `PanierService.instance`.
class PanierService {
  PanierService._();

  static final PanierService instance = PanierService._();

  final Map<String, LignePanier> _lignes = <String, LignePanier>{};

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

  /// Montant total du panier (CDF).
  double total() {
    double somme = 0;
    for (final LignePanier ligne in _lignes.values) {
      somme += ligne.total;
    }
    return somme;
  }

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

    _lignes[vendu.code] = LignePanier(vendu: vendu, quantite: finale);
    _notifier();
    return finale;
  }

  /// Retire une ligne du panier.
  void retirer(String cle) {
    if (_lignes.remove(cle) != null) _notifier();
  }

  /// Vide complètement le panier (vente enregistrée, annulation, déconnexion).
  void vider() {
    if (_lignes.isEmpty) return;
    _lignes.clear();
    _notifier();
  }

  void _notifier() => revision.value++;
}
