// lib/ui/mise_en_page_adaptative.dart
//
// 🖥️ MISE EN PAGE ADAPTATIVE — l'interface est dessinée pour un TÉLÉPHONE.
//
// Sur un ordinateur (fenêtre 1 200 × 800), les mêmes marges et la même grille
// de 2 colonnes donnaient des cartes et des boutons énormes, étirés sur toute
// la largeur. Deux réglages suffisent à retrouver des proportions de bureau :
//
//   • le contenu est CENTRÉ et sa largeur est bornée ([largeurContenuMax]) :
//     plus d'éléments étirés d'un bord à l'autre ;
//   • la grille de l'accueil ajoute des colonnes quand la place le permet
//     ([colonnesGrille]) au lieu de gonfler les cartes.
//
// Helpers PURS (aucune dépendance aux données) : testables directement et
// réutilisables par n'importe quel écran.

import 'package:flutter/widgets.dart';

/// Règles de largeur de l'application (miroir des valeurs de l'accueil).
abstract final class MiseEnPageAdaptative {
  /// Largeur maximale du contenu sur grand écran (au-delà, on centre).
  static const double largeurContenuMax = 980;

  /// Marge latérale minimale (identique aux marges « téléphone »).
  static const double margeLateraleMin = 20;

  /// Largeur minimale confortable d'une carte de statistique.
  static const double largeurCarteMin = 280;

  /// Marge latérale à appliquer pour centrer le contenu.
  ///
  /// • fenêtre étroite (téléphone) → [margeLateraleMin] ;
  /// • fenêtre large (ordinateur)  → l'espace restant est réparti des deux
  ///   côtés, le contenu reste au plus large de [largeurContenuMax].
  static double margeLaterale(double largeurEcran) {
    if (!largeurEcran.isFinite || largeurEcran <= 0) return margeLateraleMin;
    if (largeurEcran <= largeurContenuMax + 2 * margeLateraleMin) {
      return margeLateraleMin;
    }
    return (largeurEcran - largeurContenuMax) / 2;
  }

  /// Largeur réellement occupée par le contenu dans une fenêtre donnée.
  static double largeurContenu(double largeurEcran) {
    if (!largeurEcran.isFinite || largeurEcran <= 0) return 0;
    return largeurEcran - 2 * margeLaterale(largeurEcran);
  }

  /// Nombre de colonnes de la grille d'accueil.
  ///
  /// Jamais moins de 2 (grille historique) et au plus [maxColonnes]. Une
  /// activité sans carte ne dépend pas de cette valeur.
  static int colonnesGrille(
    double largeurEcran, {
    int maxColonnes = 3,
    double largeurCarte = largeurCarteMin,
  }) {
    final double contenu = largeurContenu(largeurEcran);
    int colonnes = (contenu / largeurCarte).floor();
    if (colonnes < 2) colonnes = 2;
    if (colonnes > maxColonnes) colonnes = maxColonnes;
    return colonnes;
  }

  /// Proportion (largeur / hauteur) d'une carte de grille CORRIGÉE de
  /// l'échelle de texte choisie par l'utilisateur (♿ Réglages → jusqu'à 1,3).
  ///
  /// Une proportion figée tronquait les libellés dès que le texte était
  /// agrandi (bandes de débordement jaunes/noires). Plus le texte est grand,
  /// plus la carte doit être HAUTE : la proportion diminue donc, sans jamais
  /// descendre sous [minimum] pour ne pas obtenir des cartes interminables.
  ///
  /// Version PURE (testable sans widget) : le facteur est fourni.
  static double proportionCartePour(
    double base,
    double facteurTexte, {
    double minimum = 0.45,
  }) {
    if (!base.isFinite || base <= 0) return base;
    if (!facteurTexte.isFinite || facteurTexte <= 1) return base;
    final double ajustee = base / facteurTexte;
    return ajustee < minimum ? minimum : ajustee;
  }

  /// Même règle, en lisant directement l'échelle de texte de l'application.
  /// À utiliser dans les `GridView` pour éviter toute proportion figée.
  static double proportionCarte(
    BuildContext context,
    double base, {
    double minimum = 0.45,
  }) {
    final double facteur = MediaQuery.textScalerOf(context).scale(1);
    return proportionCartePour(base, facteur, minimum: minimum);
  }
}
