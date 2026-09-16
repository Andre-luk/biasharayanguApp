// lib/models/inventaire_ligne.dart
//
// MODULE 9 — LIGNES DE L'INVENTAIRE QUOTIDIEN.
//
// L'écran de clôture saisit, pour chaque article compté :
//   • la quantité THÉORIQUE (stock serveur au moment du chargement) ;
//   • la quantité PHYSIQUE comptée dans la boutique.
//
// L'écart (physique − théorique) est calculé côté application pour le retour
// visuel immédiat, puis RECALCULÉ ET FIGÉ par le serveur
// (`rpc_inventaire_cloturer`) qui enregistre `inventaires_quotidiens` et
// corrige le stock par des ajustements tracés.
//
// Ce fichier est PUR (aucun import Flutter) : les résumés d'écarts sont
// testables sans réseau.

import 'package:biashara_yangu/models/statut_stock.dart';

/// Une ligne de comptage d'inventaire (mutable : le magasinier saisit).
class LigneInventaire {
  LigneInventaire({
    required this.produitId,
    required this.nom,
    required this.unite,
    required this.quantiteTheorique,
    this.quantitePhysique,
  });

  final int produitId;
  final String nom;
  final String unite;
  final double quantiteTheorique;

  /// Quantité comptée ; `null` tant que l'article n'a pas été compté.
  double? quantitePhysique;

  /// `true` si une quantité physique a été saisie.
  bool get compte => quantitePhysique != null;

  /// Écart (physique − théorique), ou `null` si l'article n'est pas compté.
  double? get ecart =>
      quantitePhysique == null ? null : quantitePhysique! - quantiteTheorique;

  /// `true` si l'article est compté et que l'écart est nul.
  bool get estConforme {
    final double? valeur = ecart;
    return valeur != null && valeur.abs() <= StatutStock.tolerance;
  }

  /// `true` si l'article est compté et présente un écart.
  bool get estEnEcart {
    final double? valeur = ecart;
    return valeur != null && valeur.abs() > StatutStock.tolerance;
  }

  /// Corps envoyé à `rpc_inventaire_cloturer`.
  ///
  /// Une ligne non comptée ne doit jamais être envoyée : les quantités
  /// vides restent `null` côté application et sont ignorées.
  Map<String, dynamic> versJson() => <String, dynamic>{
        'produit_id': produitId,
        'quantite_physique': quantitePhysique,
      };
}

/// Synthèse des comptages d'un inventaire (avant envoi au serveur).
class ResumeInventaire {
  const ResumeInventaire({
    required this.nbComptes,
    required this.nbEcarts,
    required this.ecartNet,
    required this.ecartAbsolu,
  });

  /// Nombre d'articles comptés.
  final int nbComptes;

  /// Nombre d'articles présentant un écart.
  final int nbEcarts;

  /// Somme signée des écarts (positif = excédent global).
  final double ecartNet;

  /// Somme des valeurs absolues des écarts (ampleur des corrections).
  final double ecartAbsolu;

  static const ResumeInventaire vide = ResumeInventaire(
    nbComptes: 0,
    nbEcarts: 0,
    ecartNet: 0,
    ecartAbsolu: 0,
  );

  bool get aDesEcarts => nbEcarts > 0;

  /// Calcule la synthèse des lignes COMPTÉES uniquement.
  factory ResumeInventaire.depuisLignes(Iterable<LigneInventaire> lignes) {
    int nbComptes = 0;
    int nbEcarts = 0;
    double ecartNet = 0;
    double ecartAbsolu = 0;

    for (final LigneInventaire ligne in lignes) {
      final double? ecart = ligne.ecart;
      if (ecart == null) continue;
      nbComptes += 1;
      if (ecart.abs() > StatutStock.tolerance) {
        nbEcarts += 1;
        ecartNet += ecart;
        ecartAbsolu += ecart.abs();
      }
    }

    return ResumeInventaire(
      nbComptes: nbComptes,
      nbEcarts: nbEcarts,
      ecartNet: ecartNet,
      ecartAbsolu: ecartAbsolu,
    );
  }
}
