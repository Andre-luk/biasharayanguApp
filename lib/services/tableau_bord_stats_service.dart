// lib/services/tableau_bord_stats_service.dart
//
// 📊 MODULE 23 — STATISTIQUES D'ACCUEIL LUES SUR LE SERVEUR.
//
// Problème corrigé : l'accueil lisait la copie SQLite du téléphone. Une vente
// faite sur un autre appareil, ou un article ajouté depuis le web, n'y
// apparaissait qu'après une synchronisation — d'où l'impression que
// « l'application ment ».
//
// Ce service interroge `rpc_accueil_stats()` : les chiffres sont calculés sur
// les VRAIES lignes de la base, pour toute l'entreprise (patron et
// collaborateurs voient donc exactement la même chose).

import 'package:flutter/foundation.dart';

import 'package:biashara_yangu/services/cache_lecture.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Chiffres du tableau de bord.
class StatsAccueil {
  const StatsAccueil({
    this.produits = 0,
    this.stockAlertes = 0,
    this.ventesJour = 0,
    this.ventesTotal = 0,
    this.caJour = 0,
    this.caTotal = 0,
  });

  final int produits;
  final int stockAlertes;
  final int ventesJour;

  /// Nombre TOTAL de ventes de la boutique (même source que [caTotal]).
  final int ventesTotal;
  final double caJour;
  final double caTotal;

  factory StatsAccueil.depuisJson(Map<String, dynamic> json) {
    return StatsAccueil(
      produits: parseInt(json['produits']),
      stockAlertes: parseInt(json['stock_alertes']),
      ventesJour: parseInt(json['ventes_jour']),
      ventesTotal: parseInt(json['ventes_total']),
      caJour: parseDouble(json['ca_jour']),
      caTotal: parseDouble(json['ca_total']),
    );
  }
}

/// Accès à `rpc_accueil_stats`.
class TableauBordStatsService {
  TableauBordStatsService._();

  static final TableauBordStatsService instance = TableauBordStatsService._();

  /// 🧹 JETTE LA RÉPONSE MISE EN CACHE.
  ///
  /// ⚠️ Défaut réel corrigé ici : l'accueil lit `rpc_accueil_stats` **via le
  /// cache de lecture** (validité 10 minutes). Après une vente, l'écran
  /// pouvait donc réafficher pendant dix minutes des chiffres d'AVANT la
  /// vente — « la facture est donnée mais le tableau de bord ne bouge pas ».
  /// Toute écriture qui change les totaux doit donc invalider cette clé.
  Future<void> invalider() async {
    try {
      await CacheLecture.instance
          .oublier(CacheLecture.cleRpc('rpc_accueil_stats'));
    } catch (e) {
      debugPrint('TableauBordStatsService.invalider (ignoré) : $e');
    }
  }

  /// `null` si le serveur ne répond pas (l'appelant garde alors ses chiffres
  /// locaux — jamais un écran vide).
  Future<StatsAccueil?> charger() async {
    try {
      // 🔌 HORS LIGNE : la dernière réponse connue est affichée si le
      // serveur ne répond pas (jamais un écran vide).
      final dynamic reponse = await CacheLecture.instance.rpc('rpc_accueil_stats');
      final Map<String, dynamic>? json = parseMap(reponse);
      if (json == null || json['ok'] != true) return null;
      return StatsAccueil.depuisJson(json);
    } catch (e) {
      debugPrint('TableauBordStatsService.charger (ignoré) : $e');
      return null;
    }
  }
}
