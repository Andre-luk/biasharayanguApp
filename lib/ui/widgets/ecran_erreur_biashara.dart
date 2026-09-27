// lib/ui/widgets/ecran_erreur_biashara.dart
//
// 🛡️ ÉCRAN DE REPLI GLOBAL — audit final de professionnalisation.
//
// Par défaut, Flutter remplace le widget fautif par un écran rouge
// « Unhandled Exception » (bandes jaunes/noires) illisible pour un
// utilisateur final : en production, cela donnait l'image d'une application
// cassée.
//
// Cet écran est volontairement AUTONOME :
//   • aucun Provider, aucun Service, aucun accès réseau ;
//   • aucun MediaQuery, aucune dépendance au thème de l'application.
// Il doit pouvoir s'afficher même lorsque l'arbre de widgets qui a échoué est
// corrompu, ou que les données dont il dépendent sont indisponibles.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Message de repli affiché à la place d'un widget qui a levé une exception.
///
/// Branché sur `ErrorWidget.builder` dans `main.dart`.
class EcranErreurBiashara extends StatelessWidget {
  const EcranErreurBiashara({super.key});

  @override
  Widget build(BuildContext context) {
    // `Material` est nécessaire pour que les `Text` héritent d'un style
    // valide ; rien d'autre n'est requis.
    return Material(
      color: AppCouleurs.fondClair,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  size: 44,
                  color: AppCouleurs.alerte,
                ),
                SizedBox(height: 12),
                Text(
                  'Biashara Yangu',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppCouleurs.marine,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Cet élément n\'a pas pu s\'afficher.\n'
                  'Revenez en arrière puis réessayez.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF5A6472),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
