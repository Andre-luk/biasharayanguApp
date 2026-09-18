// lib/utils/accessibilite_manager.dart
//
// ♿ ACCESSIBILITÉ — taille du texte de l'application.
//
// L'échelle choisie dans « Paramètres → Accessibilité » est persistée et
// appliquée à TOUTE l'application (MaterialApp.builder dans `main.dart`).
// Valeurs proposées : 90 % · 100 % · 115 % · 130 % (confort de lecture).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gère l'échelle de texte choisie par l'utilisateur.
class AccessibiliteManager extends ChangeNotifier {
  static const String _cleStockage = 'accessibilite_echelle_texte';

  /// Échelles proposées dans l'écran Accessibilité.
  static const List<double> echelles = <double>[0.9, 1.0, 1.15, 1.3];

  double _echelle = 1.0;

  /// Échelle courante (1.0 = taille normale).
  double get echelle => _echelle;

  AccessibiliteManager() {
    _charger();
  }

  Future<void> _charger() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final double? valeur = prefs.getDouble(_cleStockage);
      if (valeur != null && valeur >= 0.8 && valeur <= 1.5) {
        _echelle = valeur;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AccessibiliteManager : lecture ignorée ($e)');
    }
  }

  /// Applique et sauvegarde une nouvelle échelle (bornée 80 % – 150 %).
  Future<void> setEchelle(double valeur) async {
    final double bornee = valeur.clamp(0.8, 1.5);
    if (bornee == _echelle) return;

    _echelle = bornee;
    notifyListeners();

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_cleStockage, bornee);
    } catch (e) {
      debugPrint('AccessibiliteManager : sauvegarde ignorée ($e)');
    }
  }
}
