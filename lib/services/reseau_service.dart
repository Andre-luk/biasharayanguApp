// lib/services/reseau_service.dart
//
// 📡 ÉTAT DU RÉSEAU — et reprise automatique.
//
// Le socle hors ligne existe déjà : les ventes, produits, clients, dépenses…
// sont écrits d'abord sur l'appareil (SQLite), puis poussés vers le serveur
// par `SyncService`. Ce service ajoute la pièce manquante : savoir QUAND la
// connexion revient, pour vider la file TOUT SEUL — sans que le commerçant
// ait à appuyer sur un bouton qu'il ne connaît pas.
//
// ⚠️ Aucun service tiers : une requête minuscule suffit à distinguer
//    « pas de réseau » de « serveur qui répond ».

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/sync_service.dart';

class ReseauService {
  ReseauService._();

  static final ReseauService instance = ReseauService._();

  /// `true` tant que le serveur répond. On démarre optimiste : mieux vaut
  /// tenter une opération que bloquer l'écran sur un faux négatif.
  final ValueNotifier<bool> enLigne = ValueNotifier<bool>(true);

  /// Dernière transition hors-ligne → en-ligne (pour l'affichage).
  final ValueNotifier<DateTime?> revenuLe = ValueNotifier<DateTime?>(null);

  Timer? _minuteur;
  bool _verificationEnCours = false;

  /// Intervalle entre deux sondes. Court quand on est hors ligne (pour
  /// reprendre vite), plus long quand tout va bien (pour ne rien consommer).
  static const Duration intervalleHorsLigne = Duration(seconds: 8);
  static const Duration intervalleEnLigne = Duration(seconds: 25);
  static const Duration delaiSonde = Duration(seconds: 6);

  /// Démarre la surveillance (idempotent). À appeler après la connexion.
  void demarrerSurveillance() {
    _minuteur ??= Timer.periodic(intervalleEnLigne, (_) => _sonder());
    unawaited(_sonder());
  }

  void arreterSurveillance() {
    _minuteur?.cancel();
    _minuteur = null;
  }

  /// Force une vérification immédiate (bouton « Réessayer »).
  Future<bool> verifierMaintenant() => _sonder();

  /// Une opération réseau a échoué : on le note tout de suite, sans attendre
  /// la prochaine sonde.
  void signalerEchec() => _basculer(false);

  /// Une opération réseau a réussi : le réseau est là.
  void signalerSucces() => _basculer(true);

  Future<bool> _sonder() async {
    if (_verificationEnCours) return enLigne.value;
    _verificationEnCours = true;

    try {
      // Requête volontairement minuscule : une seule ligne, trois colonnes.
      await SupabaseService.instance.client
          .from('app_settings')
          .select('key')
          .limit(1)
          .timeout(delaiSonde);

      _basculer(true);
    } catch (e) {
      if (kDebugMode) debugPrint('ReseauService : hors ligne ($e)');
      _basculer(false);
    } finally {
      _verificationEnCours = false;

      // Rythme adaptatif : on insiste quand la connexion manque.
      if (_minuteur != null) {
        final Duration voulu =
            enLigne.value ? intervalleEnLigne : intervalleHorsLigne;
        if (_minuteur!.tick == 0 || _minuteur!.isActive) {
          _minuteur?.cancel();
          _minuteur = Timer.periodic(voulu, (_) => _sonder());
        }
      }
    }

    return enLigne.value;
  }

  void _basculer(bool connecte) {
    final bool etait = enLigne.value;
    if (etait == connecte) return;

    enLigne.value = connecte;

    if (connecte && !etait) {
      revenuLe.value = DateTime.now();
      // 🔁 LA CONNEXION REVIENT : on vide la file d'attente locale.
      // Best-effort : un échec laissera simplement les lignes en attente.
      SyncService.instance
          .syncAll()
          .catchError((Object e) => debugPrint('Reprise sync ignorée : $e'));
    }
  }
}
