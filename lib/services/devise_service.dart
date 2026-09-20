// lib/services/devise_service.dart
//
// 🪙 MODULE 18 — DEVISE DE TRAVAIL & TAUX DE CONVERSION (facade Dart).
//
// Facade des RPC SQL (migration 39) :
//   • `rpc_devise_etat()`                 → devise + taux effectif + devises ;
//   • `rpc_devise_configurer()`           → choix du PROPRIÉTAIRE (CDF/USD) ;
//   • `rpc_devise_plateforme_definir()`   → taux par défaut (Super Admin).
//
// EFFET GLOBAL : dès que l'état est chargé, la devise est appliquée à
// [FormatMonetaire] — donc à TOUS les `formatMontant()` de l'application
// (prix des articles, ventes, dépenses, caisse, rapports, reçus, dettes…).
//
// Fail-open : tant que rien n'est chargé (hors ligne, migration absente),
// l'application reste en CDF / « FC » — comportement historique.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/devise.dart';
import 'package:biashara_yangu/services/espace_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du module « Devises ».
class DeviseServiceException implements Exception {
  const DeviseServiceException(this.message, {this.code});

  /// Message rédigé en français, affichable tel quel à l'utilisateur.
  final String message;
  final String? code;

  @override
  String toString() => message;
}

class DeviseService {
  DeviseService._();

  static final DeviseService instance = DeviseService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Configuration courante. `null` tant que rien n'est chargé.
  final ValueNotifier<EtatDevise?> etat = ValueNotifier<EtatDevise?>(null);

  bool _surveillanceActive = false;
  String? _dernierEspaceId;

  // ---------------------------------------------------------------------------
  // ACCESSEURS
  // ---------------------------------------------------------------------------

  /// Configuration (valeurs par défaut CDF tant que rien n'est chargé).
  EtatDevise get configuration => etat.value ?? const EtatDevise();

  /// Devise active de l'entreprise.
  Devise get devise => configuration.devise;

  /// Code (`CDF`, `USD`).
  String get code => devise.code;

  /// Symbole affiché (`FC`, `$`).
  String get symbole => devise.symbole;

  /// Taux effectif « 1 USD = X CDF ».
  double get taux => configuration.tauxUsdCdf;

  /// L'état serveur a-t-il été chargé ?
  bool get charge => etat.value != null;

  /// L'utilisateur peut-il changer la devise de l'entreprise ?
  bool get peutModifier => configuration.peutModifier;

  // ---------------------------------------------------------------------------
  // FORMATAGE & CONVERSIONS
  // ---------------------------------------------------------------------------

  /// Montant formaté dans la devise active (« 15 000 FC », « 12,50 $ »).
  String formater(double? montant) {
    if (montant == null) return '—';
    return formatMontant(montant);
  }

  /// Équivalent de [montant] (dans la devise active) exprimé dans l'autre
  /// devise : « ≈ 7,14 $ » pour 20 000 FC. Chaîne vide si le taux est absent.
  String equivalent(double? montant, {Devise? depuis}) {
    if (montant == null || montant == 0) return '';
    final Devise source = depuis ?? devise;
    final Devise cible =
        source == Devise.cdf ? Devise.usd : Devise.cdf;
    final double valeur = configuration.convertir(
      montant,
      deviseSource: source,
      deviseCible: cible,
    );
    return '≈ ${formatMontant(valeur, devise: cible.symbole)}';
  }

  /// Convertit un montant exprimé dans la devise de l'entreprise vers une
  /// autre devise (ex. montants de la plateforme libellés en CDF).
  double convertir(double montant, {required Devise vers, Devise? depuis}) {
    return configuration.convertir(
      montant,
      deviseSource: depuis ?? devise,
      deviseCible: vers,
    );
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  /// Charge la configuration de la devise de l'entreprise active.
  Future<EtatDevise> charger() {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc('rpc_devise_etat');

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const DeviseServiceException(
            'Le serveur a renvoyé une réponse inattendue pour votre devise.',
          );
        }

        return _appliquer(EtatDevise.fromMap(map));
      },
      'le chargement de votre devise',
      'Impossible de charger votre devise. Vérifiez votre connexion internet.',
    );
  }

  /// Variante silencieuse (démarrage, connexion, bascule d'entreprise).
  Future<void> chargerSilencieux() async {
    try {
      await charger();
    } catch (e) {
      debugPrint('DeviseService.chargerSilencieux (ignoré) : $e');
    }
  }

  /// Enregistre la devise (et éventuellement le taux) de l'entreprise.
  ///
  /// [taux] : `null` = ne change pas le taux ; `0` = revenir au taux de la
  /// plateforme ; `> 0` = taux propre à l'entreprise.
  ///
  /// ⚠️ Les montants déjà enregistrés ne sont PAS convertis : seule l'unité
  /// d'affichage change (l'écran prévient l'utilisateur).
  Future<EtatDevise> configurer({
    required Devise devise,
    double? taux,
    String? entrepriseId,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_devise_configurer',
          params: <String, dynamic>{
            'p_devise': devise.code,
            'p_taux': taux,
            'p_entreprise_id': entrepriseId,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const DeviseServiceException(
            'Le serveur a renvoyé une réponse inattendue.',
          );
        }

        return _appliquer(EtatDevise.fromMap(map));
      },
      'l\'enregistrement de votre devise',
      'Impossible d\'enregistrer votre devise. Vérifiez votre connexion '
          'internet puis réessayez.',
    );
  }

  /// Taux de change par défaut de la plateforme (SUPER_ADMIN).
  Future<EtatDevise> definirTauxPlateforme({
    required double taux,
    Devise? deviseDefaut,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_devise_plateforme_definir',
          params: <String, dynamic>{
            'p_taux': taux,
            'p_devise_defaut': deviseDefaut?.code,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const DeviseServiceException(
            'Le serveur a renvoyé une réponse inattendue.',
          );
        }

        return _appliquer(EtatDevise.fromMap(map));
      },
      'le réglage du taux de la plateforme',
      'Impossible d\'enregistrer le taux de la plateforme. Vérifiez votre '
          'connexion internet puis réessayez.',
    );
  }

  // ---------------------------------------------------------------------------
  // SURVEILLANCE DE L'ESPACE ACTIF (module 15)
  // ---------------------------------------------------------------------------

  /// Branche l'écoute de [EspaceService] : chaque bascule d'entreprise
  /// recharge la devise (elle appartient à l'entreprise). Idempotent.
  void demarrerSurveillance() {
    if (_surveillanceActive) return;
    _surveillanceActive = true;
    EspaceService.instance.etat.addListener(_reagirChangementEspace);
  }

  void _reagirChangementEspace() {
    final String? id = EspaceService.instance.actif?.id;

    if (id == null) {
      if (_dernierEspaceId != null) reinitialiser();
      return;
    }

    if (id == _dernierEspaceId) return;
    _dernierEspaceId = id;
    unawaited(chargerSilencieux());
  }

  /// Vide le cache (déconnexion) et revient à la devise par défaut (CDF).
  void reinitialiser() {
    _dernierEspaceId = null;
    etat.value = null;
    FormatMonetaire.reinitialiser();
  }

  // ---------------------------------------------------------------------------
  // OUTILS INTERNES
  // ---------------------------------------------------------------------------

  /// Applique la devise à l'affichage global AVANT de notifier les écrans.
  ///
  /// ⚠️ Les rôles de la PLATEFORME (admin, gestionnaire, finance) manipulent
  /// des montants de plateforme (abonnements, grilles tarifaires) libellés en
  /// CDF : la devise d'une entreprise cliente ne leur est pas appliquée.
  EtatDevise _appliquer(EtatDevise configuration) {
    final bool plateforme =
        PermissionService.instance.roleCourant.estPlateforme;
    final Devise affichee = plateforme ? Devise.cdf : configuration.devise;

    FormatMonetaire.definir(
      code: affichee.code,
      symbole: affichee.symbole,
    );
    etat.value = configuration;
    return configuration;
  }

  /// Extrait le message utilisateur d'une erreur serveur préfixée
  /// (`CODE|message`), comme les autres services du projet.
  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  Future<T> _executer<T>(
    Future<T> Function() action,
    String libelle,
    String messageEchec,
  ) async {
    try {
      return await action();
    } on DeviseServiceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('DeviseService ($libelle) : ${e.message}');

      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const DeviseServiceException(
          "Le module des devises n'est pas installé sur la base. "
          'Exécutez le script '
          'supabase/migrations/20260916000039_module18_devises.sql '
          'puis réessayez.',
          code: 'NON_DEPLOYE',
        );
      }

      throw DeviseServiceException(
        messageErreur(e.message),
        code: e.message.split('|').first.trim().toUpperCase(),
      );
    } catch (e, st) {
      debugPrint('DeviseService ($libelle) : $e\n$st');
      throw DeviseServiceException(messageEchec);
    }
  }
}
