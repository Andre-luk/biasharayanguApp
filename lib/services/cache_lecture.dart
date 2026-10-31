// lib/services/cache_lecture.dart
//
// 🔌 100 % HORS LIGNE — LA DERNIÈRE RÉPONSE CONNUE RESTE À L'ÉCRAN.
//
// Le problème réel, entendu sur le terrain : « l'application doit fonctionner
// et rapidement ». Une boutique coupée du réseau voyait des écrans vides
// (rapports, abonnement, tableau de bord) alors que l'appareil possédait déjà
// toutes les données des jours précédents.
//
// Principe — volontairement simple :
//
//   1. on interroge le serveur (avec un délai court) ;
//   2. succès      → on ENREGISTRE la réponse et on la renvoie ;
//   3. échec/timeout → on RELIT la dernière réponse connue et on la renvoie ;
//   4. rien en cache → on laisse remonter l'erreur (jamais de fausse donnée).
//
// Règles de sécurité :
//   • Aucune ÉCRITURE n'est mise en cache (paiement, vente, validation) :
//     seules les lectures passent ici.
//   • Une valeur périmée est servie **seulement** quand le réseau échoue ;
//     jamais à la place d'une réponse fraîche.
//   • Le cache est isolé par utilisateur et par entreprise : [cleRpc] inclut
//     l'identifiant du compte, sinon deux boutiques sur le même téléphone
//     verraient les chiffres de l'autre.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/services/supabase_service.dart';

/// Origine d'une valeur lue : fraîche du serveur, ou reprise du cache local.
enum SourceLecture { serveur, cache }

/// Résultat d'une lecture avec son origine et sa date.
class LectureCachee {
  const LectureCachee({
    required this.valeur,
    required this.source,
    this.majLe,
  });

  final dynamic valeur;
  final SourceLecture source;

  /// Date d'enregistrement du cache (utile pour prévenir l'utilisateur).
  final DateTime? majLe;

  bool get vientDuCache => source == SourceLecture.cache;
}

/// Où l'on garde les valeurs. Abstract pour pouvoir tester la logique de
/// repli sans base de données.
abstract class StockageCache {
  Future<String?> lire(String cle);
  Future<void> ecrire(String cle, String valeur);
  Future<DateTime?> majLe(String cle);
  Future<void> purger(String cle);
  Future<void> vider();
}

/// Stockage réel : la table SQLite `cache_lecture` (db_helper v13).
class StockageCacheSqlite implements StockageCache {
  const StockageCacheSqlite();

  DBHelper get _db => DBHelper.instance;

  @override
  Future<String?> lire(String cle) => _db.cacheLire(cle);

  @override
  Future<void> ecrire(String cle, String valeur) => _db.cacheEcrire(cle, valeur);

  @override
  Future<DateTime?> majLe(String cle) => _db.cacheMiseAJour(cle);

  @override
  Future<void> purger(String cle) => _db.cachePurger(cle);

  @override
  Future<void> vider() => _db.cacheVider();
}

class CacheLecture {
  CacheLecture({StockageCache? stockage})
      : _stockage = stockage ?? const StockageCacheSqlite();

  static final CacheLecture instance = CacheLecture();

  final StockageCache _stockage;

  /// Au-delà de ce délai, on préfère le cache à une attente interminable.
  static const Duration delaiReseau = Duration(seconds: 8);

  /// Durée pendant laquelle une valeur est considérée comme « fraîche ».
  static const Duration validite = Duration(minutes: 10);

  /// Dernière lecture servie depuis le cache (bandeau / diagnostic).
  final ValueNotifier<bool> dernierResultatLocal = ValueNotifier<bool>(false);

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Clé stable et cloisonnée : utilisateur + entreprise + fonction + arguments.
  ///
  /// Les paramètres sont triés par nom pour que `{a,b}` et `{b,a}` tombent sur
  /// la même entrée.
  static String cleRpc(String fonction, {Map<String, dynamic>? params}) {
    String utilisateur = 'anonyme';
    try {
      utilisateur =
          SupabaseService.instance.auth.currentUser?.id ?? 'anonyme';
    } catch (_) {
      // Supabase non initialisé (tests, tout premier lancement) : la clé
      // reste utilisable, elle n'est simplement pas cloisonnée.
    }
    final Map<String, dynamic>? propres = params == null
        ? null
        : <String, dynamic>{
            for (final MapEntry<String, dynamic> e in params.entries)
              if (e.value != null) e.key: e.value,
          };

    if (propres == null || propres.isEmpty) return '$fonction|$utilisateur';

    final List<String> cles = propres.keys.toList()..sort();
    final String args =
        cles.map((String k) => '$k=${propres[k]}').join('&');
    return '$fonction|$utilisateur|$args';
  }

  /// Lit une RPC avec reprise sur cache.
  ///
  /// [validite] ne sert qu'à prévenir l'utilisateur quand la donnée est
  /// ancienne ; on ne refuse jamais une valeur en cache parce qu'elle est
  /// vieille — hors ligne, une donnée d'hier reste infiniment plus utile
  /// qu'un écran vide.
  Future<dynamic> rpc(
    String fonction, {
    Map<String, dynamic>? params,
    Duration? delai,
  }) {
    return avecRepli(
      cleRpc(fonction, params: params),
      () => _client.rpc(fonction, params: params),
      delai: delai,
    );
  }

  /// Cœur du mécanisme, indépendant de Supabase (donc testable).
  ///
  /// [distant] est la lecture réseau ; [cle] identifie la valeur en cache.
  Future<dynamic> avecRepli(
    String cle,
    Future<dynamic> Function() distant, {
    Duration? delai,
  }) async {
    try {
      final dynamic reponse = await distant().timeout(delai ?? delaiReseau);
      await _memoriser(cle, reponse);
      _notifier(false);
      return reponse;
    } on PostgrestException {
      // ⚠️ Le serveur a RÉPONDU (droit refusé, donnée absente…) : sa réponse
      // fait foi. On ne sert jamais un cache contre un refus du serveur.
      _notifier(false);
      rethrow;
    } catch (e) {
      final dynamic cache = await _relire(cle);
      if (cache != null) {
        debugPrint('CacheLecture: $cle servi depuis le cache ($e)');
        _notifier(true);
        return cache;
      }
      _notifier(false);
      rethrow;
    }
  }

  /// Comme [rpc], mais renvoie aussi l'origine et la date de la donnée.
  /// Utile pour afficher « données du 30/10 » sur un rapport.
  Future<LectureCachee?> rpcDetaille(
    String fonction, {
    Map<String, dynamic>? params,
    Duration? delai,
  }) async {
    final String cle = cleRpc(fonction, params: params);

    try {
      final dynamic reponse = await _client
          .rpc(fonction, params: params)
          .timeout(delai ?? delaiReseau);
      await _memoriser(cle, reponse);
      return LectureCachee(valeur: reponse, source: SourceLecture.serveur);
    } on PostgrestException {
      rethrow;
    } catch (e) {
      final dynamic cache = await _relire(cle);
      if (cache == null) return null;
      debugPrint('CacheLecture: $fonction (détaillé) depuis le cache ($e)');
      return LectureCachee(
        valeur: cache,
        source: SourceLecture.cache,
        majLe: await _stockage.majLe(cle),
      );
    }
  }

  /// Enregistre directement une valeur (utile pour amorcer un écran).
  Future<void> memoriser(String cle, dynamic valeur) => _memoriser(cle, valeur);

  /// Relit une valeur sans appeler le serveur.
  Future<dynamic> relire(String cle) => _relire(cle);

  Future<void> oublier(String cle) => _stockage.purger(cle);

  /// Vide tout le cache local (déconnexion).
  Future<void> vider() async {
    await _stockage.vider();
    _notifier(false);
  }

  // -------------------------------------------------------------------------
  // INTERNE
  // -------------------------------------------------------------------------

  Future<void> _memoriser(String cle, dynamic valeur) async {
    if (valeur == null) return;
    try {
      await _stockage.ecrire(cle, jsonEncode(valeur));
    } catch (e) {
      // Une valeur non sérialisable n'est simplement pas mise en cache.
      debugPrint('CacheLecture.memoriser($cle) ignoré : $e');
    }
  }

  Future<dynamic> _relire(String cle) async {
    final String? brut = await _stockage.lire(cle);
    if (brut == null || brut.isEmpty) return null;
    try {
      return jsonDecode(brut);
    } catch (e) {
      debugPrint('CacheLecture.relire($cle) illisible : $e');
      return null;
    }
  }

  void _notifier(bool depuisCache) {
    try {
      dernierResultatLocal.value = depuisCache;
    } catch (_) {}
  }
}
