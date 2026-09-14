// lib/utils/language_manager.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gestionnaire de la langue de l'application
class LanguageManager extends ChangeNotifier {
  Locale? _appLocale;
  static const String _localeKey = 'app_locale';

  LanguageManager() {
    _loadLocale();
  }

  Locale get appLocale => _appLocale ?? const Locale('fr', '');

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString(_localeKey);
    if (languageCode != null) {
      _appLocale = Locale(languageCode);
    } else {
      _appLocale = const Locale('fr', '');
    }
    notifyListeners();
  }

  /// Change la langue de l'application
  Future<void> changeLanguage(Locale newLocale) async {
    if (newLocale.languageCode == _appLocale?.languageCode) return;

    _appLocale = newLocale;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, newLocale.languageCode);

    // Notifie les widgets écoutant ce manager
    notifyListeners();
  }
}
