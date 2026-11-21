// lib/services/date_locale_service.dart
//
// 📅 CORRECTIF 179 — LA DATE VIENT DU SERVEUR, PAS DU TÉLÉPHONE.
//
// Pourquoi ce service existe :
//   Les périodes des rapports (« aujourd'hui », « cette semaine », « ce
//   mois ») étaient calculées avec `DateTime.now()` de l'appareil. Un
//   téléphone mal réglé (ou simplement dans un autre fuseau) demandait donc
//   une AUTRE période au serveur — et le patron voyait des chiffres différents
//   du tableau de bord alors que rien n'avait changé en boutique.
//
//   `public.jour_local()` renvoie la date du jour à Lubumbashi, calculée par
//   la base. Toutes les périodes de l'application s'y réfèrent : deux
//   téléphones différents affichent désormais exactement les mêmes chiffres.
//
// Le résultat est mémorisé pour la session (un seul appel réseau), avec un
// repli sur l'horloge de l'appareil si le serveur ne répond pas.

import 'package:flutter/foundation.dart';

import 'package:biashara_yangu/services/supabase_service.dart';

class DateLocaleService {
  DateLocaleService._();

  static final DateLocaleService instance = DateLocaleService._();

  DateTime? _cache;

  /// Dernière date connue du serveur (ou date de l'appareil si inconnue).
  DateTime get dernierConnu => _cache ?? _jour(DateTime.now());

  /// Nom du jour (0 = lundi) de la date de référence.
  ///
  /// Utile pour calculer « début de semaine » sans dépendre de l'heure du
  /// téléphone.
  DateTime get aujourdhui => dernierConnu;

  /// Charge (une seule fois) la date du jour côté serveur.
  ///
  /// [forcer] refait l'appel — utilisé au passage de minuit ou à la
  /// reconnexion.
  Future<DateTime> charger({bool forcer = false}) async {
    if (_cache != null && !forcer) return _cache!;

    try {
      final dynamic reponse =
          await SupabaseService.instance.client.rpc('jour_local');
      final String texte = reponse?.toString().trim() ?? '';
      if (texte.isNotEmpty) {
        final DateTime? jour = DateTime.tryParse(texte);
        if (jour != null) {
          _cache = _jour(jour);
        }
      }
    } catch (e) {
      // Base pas encore mise à jour (fonction absente) ou réseau coupé :
      // on garde l'horloge de l'appareil, sans jamais bloquer l'écran.
      debugPrint('DateLocaleService.charger (ignoré) : $e');
    }

    return dernierConnu;
  }

  /// Oublie la date mémorisée (déconnexion, changement de jour).
  void reinitialiser() => _cache = null;

  /// Mémorise une date déjà reçue d'une autre réponse serveur (par exemple
  /// `jour` du tableau de bord) : évite un appel réseau supplémentaire.
  void memoriser(DateTime jour) => _cache = _jour(jour);

  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);
}
