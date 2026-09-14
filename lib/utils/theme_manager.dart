import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  static const String _themeKey = 'preferredThemeMode';

  ThemeManager() {
    _loadTheme();
  }

  /// Thème actuellement utilisé
  ThemeMode get themeMode => _themeMode;

  /// Charge le thème sauvegardé
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString(_themeKey);

    if (themeString == 'light') {
      _themeMode = ThemeMode.light;
    } else if (themeString == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }

    notifyListeners();
  }

  /// 🔑 Change le thème et le sauvegarde
  /// Compatible avec `await`
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;

    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();

    final themeString = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };

    await prefs.setString(_themeKey, themeString);
    notifyListeners();
  }
}
