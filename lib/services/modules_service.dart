// lib/services/modules_service.dart
//
// MODULE 16 (phase A) — MODULES DE L'ACTIVITÉ (facade Dart).
//
// Facade des RPC SQL (migration 27) :
//   • `rpc_mes_modules()`              → profil de modules de l'espace actif ;
//   • `rpc_types_espaces_lister()`     → liste admin des profils ;
//   • `rpc_type_espace_modules_maj()`  → création/modification (Expert).
//
// L'état est exposé via [modules] (ValueNotifier) : les écrans s'y abonnent
// pour filtrer leurs entrées quand l'activité ne concerne pas un module.
//
// ⚠️ RÈGLE D'OR (zéro régression) : [moduleActif] est « fail-open » — tant
// que rien n'est chargé (hors ligne, migration absente, profil vide), tout
// reste VISIBLE. Un profil ne fait que MASQUER ce qu'il ne contient pas.
//
// Le service écoute aussi [EspaceService] : changer d'entreprise change
// d'activité — les modules sont rechargés automatiquement.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/services/espace_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du module « Types d'activités ».
class ModulesServiceException implements Exception {
  const ModulesServiceException(this.message, {this.code});

  /// Message rédigé en français, affichable tel quel à l'utilisateur.
  final String message;
  final String? code;

  @override
  String toString() => message;
}

class ModulesService {
  ModulesService._();

  static final ModulesService instance = ModulesService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Modules de base = comportement actuel de l'application.
  /// Miroir de `public.modules_base()` (SQL) — toute évolution des deux côtés.
  static const Set<String> modulesBase = <String>{
    ModuleCode.ventes,
    ModuleCode.produits,
    ModuleCode.stock,
    ModuleCode.qr,
    ModuleCode.caisse,
    ModuleCode.clients,
    ModuleCode.finance,
    ModuleCode.employes,
    ModuleCode.rapports,
    ModuleCode.assistantIa,
  };

  /// Modules du profil de l'espace actif. Vide tant que rien n'est chargé
  /// (=> tout est visible, comportement historique).
  final ValueNotifier<Set<String>> modules =
      ValueNotifier<Set<String>>(const <String>{});

  /// 🧩 CORRECTIF 65 — fonctionnalités ouvertes par l'ABONNEMENT de
  /// l'entreprise. Vide tant que rien n'est chargé (=> tout est visible).
  final ValueNotifier<Set<String>> modulesAbonnement =
      ValueNotifier<Set<String>>(const <String>{});

  String? _type;
  String? _libelle;
  bool _charge = false;
  bool _chargeAbonnement = false;
  bool _surveillanceActive = false;
  String? _dernierEspaceId;

  /// Le profil a-t-il été chargé (une réponse serveur reçue) ?
  bool get charge => _charge;

  /// L'abonnement a-t-il été chargé ? `false` = aucune restriction connue
  /// (fail-open).
  bool get abonnementCharge => _chargeAbonnement;

  /// Code du type de l'espace actif (« boutique » tant que rien n'est chargé).
  String get type => _type ?? ModuleCode.profilDefaut;

  /// Nom affiché du profil (« Hôtel »…), `null` si non chargé.
  String? get libelle => _libelle;

  // ---------------------------------------------------------------------------
  // GARDE UNIVERSELLE (gating)
  // ---------------------------------------------------------------------------

  /// Le module est-il **actif** ET **ouvert par l'abonnement** ?
  ///
  /// CORRECTIF 65 — deux filtres indépendants :
  ///   • l'ACTIVITÉ dit ce qui a du SENS (une pharmacie gère des lots,
  ///     un hôtel des chambres) ;
  ///   • l'ABONNEMENT dit ce qui est PAYÉ.
  ///
  /// Les deux sont fail-open : une panne réseau, une migration non exécutée
  /// ou une liste vide laissent TOUT visible — aucune régression possible
  /// chez un commerçant dont l'abonnement est en règle.
  bool moduleActif(String code) {
    if (!estActif(modules.value, _charge, code)) return false;
    // 🛟 PACK MAL CONFIGURÉ — « un pack ne doit jamais cacher un écran ».
    // Si l'abonnement ouvre des fonctionnalités dont AUCUNE n'appartient à
    // l'activité (cas réel : le pack « Pharmacie » contenait les modules du
    // pressing), le filtre d'abonnement masquait des champs légitimes —
    // « Lot & péremption » disparaissait d'une pharmacie. On considère alors
    // le pack comme non informatif et on laisse passer.
    if (packHorsActivite(
      modulesAbonnement.value,
      modules.value,
      abonnementCharge: _chargeAbonnement,
      activiteChargee: _charge,
    )) {
      return true;
    }
    return estAutoriseParAbonnement(modulesAbonnement.value, _chargeAbonnement, code);
  }

  /// Version PURE (testable sans réseau) : le pack d'abonnement ouvre-t-il des
  /// fonctionnalités qui n'ont **aucun rapport** avec l'activité de l'espace ?
  ///
  /// `true` seulement quand les deux listes sont connues et non vides et que
  /// leur intersection est vide. C'est le signal d'une configuration
  /// incohérente (pack rattaché au mauvais type d'entreprise) : dans ce cas
  /// l'abonnement ne doit pas servir de filtre.
  static bool packHorsActivite(
    Set<String> ouverts,
    Set<String> activite, {
    required bool abonnementCharge,
    required bool activiteChargee,
  }) {
    if (!abonnementCharge || !activiteChargee) return false;
    if (ouverts.isEmpty || activite.isEmpty) return false;
    if (ouverts.contains(ReglesAbonnement.joker)) return false;
    return ouverts.intersection(activite).isEmpty;
  }

  /// Version PURE (testable sans réseau) du filtre ACTIVITÉ.
  ///
  /// Délègue à [ReglesActivite.actif] : la règle fail-open est écrite UNE
  /// seule fois (model) et partagée par toutes les entrées de l'interface.
  static bool estActif(Set<String> actifs, bool charge, String code) =>
      ReglesActivite.actif(actifs, charge, <String>{code});

  /// Version PURE (testable sans réseau) du filtre ABONNEMENT.
  static bool estAutoriseParAbonnement(
    Set<String> ouverts,
    bool charge,
    String code,
  ) =>
      ReglesAbonnement.autorise(ouverts, charge, <String>{code});

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  /// Charge le profil de modules de l'espace de travail actif.
  Future<void> charger() {
    return _executer(
      () async {
        // Pendant le chargement, on repasse en « fail-open » : si le réseau
        // échoue, l'application ne masque rien (comportement historique).
        _charge = false;

        final dynamic reponse = await _client.rpc('rpc_mes_modules');

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const ModulesServiceException(
            'Le serveur a renvoyé une réponse inattendue.',
          );
        }

        _type = parseStringOrNull(map['type']) ?? ModuleCode.profilDefaut;
        _libelle = parseStringOrNull(map['libelle']);
        modules.value = ProfilModules.modulesDepuisJson(map['modules']);
        _charge = true;

        //  CORRECTIF 65 — les fonctionnalités ouvertes par l'abonnement.
        //  Chargement BEST-EFFORT : si la RPC n'existe pas encore (migration
        //  non exécutée) ou si le réseau lâche, on reste en fail-open. Un
        //  abonnement ne doit JAMAIS faire disparaître un écran par accident.
        await _chargerAbonnement();
      },
      'le chargement des modules de votre activité',
      'Impossible de charger les modules de votre activité. '
          'Vérifiez votre connexion internet.',
    );
  }

  /// Charge les fonctionnalités ouvertes par l'abonnement (best-effort).
  ///
  /// `rpc_abonnement_modules()` renvoie soit une LISTE de codes, soit `null`
  /// — `null` signifiant « aucune restriction ». Toute erreur est avalée :
  /// c'est la contrepartie de la règle fail-open.
  Future<void> _chargerAbonnement() async {
    try {
      final dynamic reponse = await _client.rpc('rpc_abonnement_modules');

      modulesAbonnement.value = _codesDepuisJson(reponse);
      _chargeAbonnement = true;
    } catch (e) {
      debugPrint('ModulesService (abonnement, ignoré) : $e');
      modulesAbonnement.value = const <String>{};
      _chargeAbonnement = false;
    }
  }

  /// Liste de codes de fonctionnalités depuis une réponse jsonb.
  ///
  /// Toute forme inattendue (null, objet, texte) donne une liste VIDE, donc
  /// « aucune restriction » — on ne devine jamais, on n'invente jamais une
  /// fonctionnalité manquante.
  static Set<String> _codesDepuisJson(dynamic valeur) {
    if (valeur is! List) return const <String>{};

    return valeur
        .map((dynamic element) => element.toString().trim())
        .where((String code) => code.isNotEmpty)
        .toSet();
  }

  /// Variante silencieuse (démarrage / connexion / bascule d'entreprise) :
  /// un échec ne doit jamais bloquer ni déranger l'utilisateur.
  Future<void> chargerSilencieux() async {
    try {
      await charger();
    } catch (e) {
      debugPrint('ModulesService.chargerSilencieux (ignoré) : $e');
    }
  }

  /// Vide le cache (déconnexion, changement de compte, espace vide).
  void reinitialiser() {
    _type = null;
    _libelle = null;
    _charge = false;
    _chargeAbonnement = false;
    _dernierEspaceId = null;
    modules.value = const <String>{};
    modulesAbonnement.value = const <String>{};
  }

  // ---------------------------------------------------------------------------
  // SURVEILLANCE DE L'ESPACE ACTIF (module 15)
  // ---------------------------------------------------------------------------

  /// Branche l'écoute de [EspaceService] : chaque changement d'entreprise
  /// recharge le profil de modules (l'activité change avec l'espace).
  /// À appeler une seule fois au démarrage (idempotent).
  void demarrerSurveillance() {
    if (_surveillanceActive) return;
    _surveillanceActive = true;
    EspaceService.instance.etat.addListener(_reagirChangementEspace);
  }

  void _reagirChangementEspace() {
    final String? id = EspaceService.instance.actif?.id;

    // Sélecteur réinitialisé (déconnexion) : plus aucun espace actif.
    if (id == null) {
      if (_dernierEspaceId != null) reinitialiser();
      return;
    }

    if (id == _dernierEspaceId) return;
    _dernierEspaceId = id;
    unawaited(chargerSilencieux());
  }

  // ---------------------------------------------------------------------------
  // ADMINISTRATION PLATEFORME (page « Types d'activités »)
  // ---------------------------------------------------------------------------

  /// Tous les profils de modules (administrateurs plateforme).
  Future<List<ProfilModules>> listerProfils() {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc('rpc_types_espaces_lister');

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const ModulesServiceException(
            'Le serveur a renvoyé une réponse inattendue.',
          );
        }

        final List<dynamic> brutes =
            map['types'] is List ? map['types'] as List<dynamic> : <dynamic>[];

        return brutes
            .whereType<Map>()
            .map((Map brut) =>
                ProfilModules.fromMap(Map<String, dynamic>.from(brut)))
            .toList();
      },
      'le chargement des types d\'activités',
      'Impossible de charger les types d\'activités. '
          'Vérifiez votre connexion internet.',
    );
  }

  /// Crée ou modifie le profil d'un type d'activité (Expert Administrateur).
  ///
  /// [modules] est envoyé dans l'ordre du catalogue (affichage stable).
  Future<ProfilModules> enregistrerProfil({
    required String type,
    required String libelle,
    required Set<String> modules,
    bool actif = true,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_type_espace_modules_maj',
          params: <String, dynamic>{
            'p_type': type.trim().toLowerCase(),
            'p_libelle': libelle.trim(),
            'p_modules': ordonnerModules(modules),
            'p_actif': actif,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const ModulesServiceException(
            'Le serveur a renvoyé une réponse inattendue.',
          );
        }

        return ProfilModules.fromMap(map);
      },
      'l\'enregistrement du type d\'activité',
      'Impossible d\'enregistrer ce type d\'activité. '
          'Vérifiez votre connexion internet.',
    );
  }

  // ---------------------------------------------------------------------------
  // OUTILS PURS (testables sans réseau)
  // ---------------------------------------------------------------------------

  /// Modules triés dans l'ordre du catalogue (inconnus en fin, ordre stable).
  static List<String> ordonnerModules(Set<String> modules) {
    final List<String> ordonnes = <String>[];
    for (final ModuleActivite module in ModuleActivite.catalogue) {
      if (modules.contains(module.code)) ordonnes.add(module.code);
    }

    final List<String> inconnus = modules
        .where((String code) => !ModuleActivite.codeConnu(code))
        .toList()
      ..sort();
    return <String>[...ordonnes, ...inconnus];
  }

  /// Génère le code technique (« slug ») d'un type à partir de son nom :
  /// « Salon de coiffure » → `salon_de_coiffure`, accents retirés
  /// (« Dépôt » → `depot`). Miroir de la validation SQL
  /// `^[a-z][a-z0-9_]{1,40}$`.
  static String codeProfilDepuisLibelle(String libelle) {
    final StringBuffer tampon = StringBuffer();
    for (final int rune in _sansAccents(libelle.toLowerCase()).runes) {
      final String c = String.fromCharCode(rune);
      final int code = c.codeUnitAt(0);
      final bool alphanum = (code >= 97 && code <= 122) || // a-z
          (code >= 48 && code <= 57); // 0-9
      tampon.write(alphanum ? c : '_');
    }

    String slug = tampon
        .toString()
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (slug.length > 40) {
      slug = slug.substring(0, 40).replaceAll(RegExp(r'_+$'), '');
    }
    if (slug.isEmpty) return 'type';
    if (RegExp(r'^[0-9]').hasMatch(slug)) slug = 'type_$slug';
    return slug;
  }

  /// Remplace les caractères accentués les plus courants (français + voisins).
  static String _sansAccents(String texte) {
    const Map<String, String> remplacements = <String, String>{
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'å': 'a',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ñ': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'œ': 'oe',
      'æ': 'ae',
    };

    final StringBuffer tampon = StringBuffer();
    for (final int rune in texte.runes) {
      final String c = String.fromCharCode(rune);
      tampon.write(remplacements[c] ?? c);
    }
    return tampon.toString();
  }

  // ---------------------------------------------------------------------------
  // OUTILS INTERNES
  // ---------------------------------------------------------------------------

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
    } on ModulesServiceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('ModulesService ($libelle) : ${e.message}');

      // Fonction absente : la migration du module 16 n'est pas installée.
      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const ModulesServiceException(
          'Le module « Types d\'activités » n\'est pas installé sur la base. '
          'Exécutez le script '
          'supabase/migrations/20260916000027_module16_types_activites.sql '
          'puis réessayez.',
          code: 'NON_DEPLOYE',
        );
      }

      throw ModulesServiceException(
        messageErreur(e.message),
        code: e.message.split('|').first.trim().toUpperCase(),
      );
    } catch (e, st) {
      debugPrint('ModulesService ($libelle) : $e\n$st');
      throw ModulesServiceException(messageEchec);
    }
  }
}
