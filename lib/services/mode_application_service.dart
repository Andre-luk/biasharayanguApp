// lib/services/mode_application_service.dart
//
// ⚡ MODULE 23 — MODE SIMPLE / MODE COMPLET.
//
// Deux façons d'utiliser Biashara Yangu, choisies par le commerçant :
//
//   • MODE COMPLET (défaut) : catalogue détaillé, stock, finance, rapports…
//   • MODE RAPIDE : nom + prix → on vend. Les écrans avancés sont masqués
//     (jamais bloqués : les permissions restent seules décisionnaires).
//
// Le choix est mémorisé SUR L'APPAREIL (SharedPreferences) : un téléphone de
// vente peut rester en mode rapide tandis que celui du patron reste complet.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mode d'affichage de l'application.
enum ModeApplication {
  complet('complet', 'Mode complet'),
  rapide('rapide', 'Mode rapide');

  const ModeApplication(this.code, this.libelle);

  final String code;
  final String libelle;

  static ModeApplication fromCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    return valeur == 'rapide' ? ModeApplication.rapide : ModeApplication.complet;
  }
}

/// Mémorise et diffuse le mode choisi.
class ModeApplicationService {
  ModeApplicationService._();

  static final ModeApplicationService instance = ModeApplicationService._();

  static const String clePreference = 'mode_application';

  /// Mode courant. Les écrans s'y abonnent pour se reconstruire.
  final ValueNotifier<ModeApplication> mode =
      ValueNotifier<ModeApplication>(ModeApplication.complet);

  bool _charge = false;
  bool get charge => _charge;

  bool get rapide => mode.value == ModeApplication.rapide;

  /// Lit le mode enregistré (best-effort : une erreur laisse le mode complet).
  Future<void> charger() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      mode.value = ModeApplication.fromCode(prefs.getString(clePreference));
    } catch (e) {
      debugPrint('ModeApplicationService.charger : $e');
      mode.value = ModeApplication.complet;
    } finally {
      _charge = true;
    }
  }

  /// Enregistre le mode choisi.
  Future<void> definir(ModeApplication nouveau) async {
    mode.value = nouveau;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(clePreference, nouveau.code);
    } catch (e) {
      debugPrint('ModeApplicationService.definir : $e');
    }
  }

  Future<void> basculer() => definir(
        rapide ? ModeApplication.complet : ModeApplication.rapide,
      );
}
