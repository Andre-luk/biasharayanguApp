// lib/services/espace_service.dart
//
// MODULE 15 — SÉLECTEUR D'ENTREPRISE (pack avancé multi-entreprises).
//
// Facade Dart des RPC SQL (migration 19) :
//   • `rpc_espaces_lister`  → entreprises du compte + entreprise active ;
//   • `rpc_espace_basculer` → change l'entreprise active (toutes les données
//     suivent : c'est `mon_proprietaire()` qui bascule côté serveur) ;
//   • `rpc_espace_creer`    → nouvelle entreprise (propriétaire + pack).
//
// L'état est exposé via [etat] (ValueNotifier) : les écrans s'y abonnent
// pour rafraîchir leurs données quand l'entreprise active change.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/espace.dart';
import 'package:biashara_yangu/services/donnees_service.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/scanner_service.dart';
import 'package:biashara_yangu/services/scope_donnees.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du module multi-entreprises.
class EspaceServiceException implements Exception {
  const EspaceServiceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class EspaceService {
  EspaceService._();

  static final EspaceService instance = EspaceService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// État courant (entreprises + active). `null` tant que rien n'est chargé.
  final ValueNotifier<EtatEspaces?> etat = ValueNotifier<EtatEspaces?>(null);

  /// 🔄 Nombre de changements d'entreprise depuis le démarrage.
  ///
  /// Les écrans qui ne peuvent pas s'abonner à [etat] (widgets reconstruits
  /// avec une clé, diagnostics, tests) peuvent utiliser cette valeur comme
  /// identité du contexte : elle ne change QUE sur une bascule réelle.
  final ValueNotifier<int> generation = ValueNotifier<int>(0);

  /// Entreprise active (raccourci).
  Espace? get actif => etat.value?.actif;

  /// Nombre d'entreprises du compte (0 si non chargé).
  int get nombre => etat.value?.espaces.length ?? 0;

  /// Le sélecteur est-il utile (plus d'une entreprise) ?
  bool get multiEntreprises => etat.value?.multiEntreprises ?? false;

  // ---------------------------------------------------------------------------
  // LECTURE
  // ---------------------------------------------------------------------------

  /// Charge (ou recharge) la liste des entreprises du compte.
  Future<EtatEspaces> charger() {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc('rpc_espaces_lister');

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const EspaceServiceException(
            'Le serveur a renvoyé une réponse inattendue.',
          );
        }

        final EtatEspaces resultat = EtatEspaces.fromMap(map);

        // 🧩 L'entreprise active a-t-elle CHANGÉ ? (rechargement de la liste
        //    après création, correction de type, retour au premier plan…)
        final String? precedente = ScopeDonnees.espaceActif;
        final String? nouvelle = resultat.actifId;

        // ⚠️ ORDRE IMPORTANT : la portée de travail est publiée AVANT la
        // notification de `etat`. Les écrans qui écoutent le changement
        // lisent `ScopeDonnees` dans leur rechargement : si l'ordre était
        // inversé, ils reliraient l'ANCIENNE entreprise.
        ScopeDonnees.definirEspaceActif(nouvelle);
        await _lireProprietaireEffectif();

        etat.value = resultat;

        if (precedente != null &&
            nouvelle != null &&
            precedente != nouvelle) {
          _reinitialiserSessionMetier();
        }

        return resultat;
      },
      'le chargement de vos entreprises',
      'Impossible de charger vos entreprises. Vérifiez votre connexion internet.',
    );
  }

  /// Variante silencieuse (démarrage / connexion) : un échec ne doit jamais
  /// bloquer l'application.
  Future<void> chargerSilencieux() async {
    try {
      await charger();
    } catch (e) {
      debugPrint('EspaceService.chargerSilencieux (ignoré): $e');
    }
  }

  /// Chargement en cours (déduplication : plusieurs écrans peuvent le
  /// demander en même temps au démarrage).
  Future<void>? _chargementEnCours;

  /// Charge la liste **seulement si elle n'est pas déjà connue**.
  ///
  /// Utilisé par les écrans (mixin `EcouteContexteEntreprise`) : quand la
  /// session est restaurée sans passer par l'écran de connexion — rechargement
  /// de la page web, retour d'arrière-plan, redémarrage — rien n'avait chargé
  /// les entreprises. Les écrans interrogeaient alors la base avec la portée
  /// de secours et affichaient **les données d'une autre entreprise**.
  /// Ne lève jamais, ne relance pas un chargement déjà en cours.
  Future<void> assurerChargement() {
    if (etat.value != null) return Future<void>.value();
    return _chargementEnCours ??= chargerSilencieux().whenComplete(() {
      _chargementEnCours = null;
    });
  }

  // ---------------------------------------------------------------------------  // PROPRIÉTAIRE EFFECTIF (source de vérité = le SERVEUR)
  // -----------------------------------------------------------------------

  /// Lit `mon_proprietaire()` : c'est EXACTEMENT la valeur que les policies
  /// RLS comparent à `owner_id`.
  ///
  /// Pourquoi ne pas garder seulement l'espace choisi ? Parce que le serveur
  /// n'honore `espace_actif_id` que s'il appartient à l'entreprise courante
  /// du compte. Quand les deux divergent, écrire avec l'espace choisi créait
  /// des lignes INVISIBLES (« ça s'enregistre mais aucun article ne s'affiche »).
  ///
  /// Best-effort : hors ligne, l'ancienne valeur (espace choisi) est gardée.
  Future<void> _lireProprietaireEffectif() async {
    try {
      final dynamic reponse = await _client.rpc('mon_proprietaire');
      final String? valeur = parseStringOrNull(reponse);
      ScopeDonnees.definirProprietaireEffectif(valeur);
      if (valeur != null && valeur != ScopeDonnees.espaceActif) {
        debugPrint(
          'EspaceService : espace ${ScopeDonnees.espaceActif} ≠ '
          'propriétaire effectif $valeur — les données suivent le serveur.',
        );
      }
    } catch (e) {
      debugPrint('EspaceService.propriétaire effectif (ignoré) : $e');
    }
  }

  // -----------------------------------------------------------------------  // ÉCRITURE
  // ---------------------------------------------------------------------------

  /// Bascule vers une autre entreprise du compte.
  ///
  /// Après succès, [etat] est mis à jour localement : les écrans abonnés
  /// rechargent leurs données sur le nouvel espace.
  Future<void> basculer(String espaceId) {
    return _executer(
      () async {
        await _client.rpc(
          'rpc_espace_basculer',
          params: <String, dynamic>{'p_espace_id': espaceId},
        );

        final EtatEspaces? actuel = etat.value;

        // ⚠️ La portée est publiée AVANT la notification (même raison que
        // dans `charger`) : les écrans doivent relire la NOUVELLE entreprise.
        ScopeDonnees.definirEspaceActif(espaceId);
        await _lireProprietaireEffectif();

        if (actuel != null) {
          etat.value = actuel.avecActif(espaceId);
        } else {
          await charger();
        }

        // 🧹 Une bascule est un changement de CONTEXTE, pas un simple
        //    changement de menu : tout ce qui appartenait à la vente en
        //    cours (panier, historique de scans) est abandonné, sinon un
        //    article de la pharmacie partirait dans une vente de la boutique.
        _reinitialiserSessionMetier();
      },
      'le changement d\'entreprise',
      'Impossible de changer d\'entreprise. Vérifiez votre connexion internet.',
    );
  }

  /// Crée une entreprise supplémentaire (propriétaire + pack multi).
  ///
  /// Renvoie le nouvel [Espace] et rafraîchit [etat].
  Future<Espace> creer({
    required String nom,
    TypeEspace type = TypeEspace.boutique,
    String? villeId,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_espace_creer',
          params: <String, dynamic>{
            'p_nom': nom.trim(),
            'p_type': type.code,
            'p_ville_id': villeId,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const EspaceServiceException(
            'Le serveur a renvoyé une réponse inattendue.',
          );
        }

        // Recharge la liste complète (quota, nouvelle active éventuelle).
        await charger();

        return Espace(
          id: parseString(map['espace_id']),
          nom: parseString(map['nom']),
          type: TypeEspace.fromCode(parseStringOrNull(map['type'])),
          actif: true,
        );
      },
      'la création de votre entreprise',
      'Impossible de créer cette entreprise. Vérifiez votre connexion internet.',
    );
  }

  /// 🧩 MODULE 17 — change la CATÉGORIE D'ACTIVITÉ d'une entreprise
  /// (Hôtel, Restaurant, Pharmacie…).
  ///
  /// Réservé au PROPRIÉTAIRE (vérifié côté serveur). L'environnement suit
  /// immédiatement : si l'entreprise modifiée est l'espace actif, le profil
  /// de modules est rechargé (`rpc_mes_modules` lit `espaces.type`).
  Future<void> definirType({
    required String espaceId,
    required String type,
  }) {
    return _executer(
      () async {
        await _client.rpc(
          'rpc_espace_type_definir',
          params: <String, dynamic>{
            'p_espace_id': espaceId,
            'p_type': type,
          },
        );

        // Recharge la liste (le type affiché change) puis, si c'est l'espace
        // actif, les modules de l'activité.
        await charger();

        final Espace? actif = etat.value?.actif;
        if (actif != null && actif.id == espaceId) {
          await ModulesService.instance.chargerSilencieux();
        }
      },
      'le changement de catégorie',
      'Impossible de changer la catégorie de cette entreprise. '
          'Vérifiez votre connexion internet.',
    );
  }

  /// 🧩 MODULE 17 — catégories d'activité proposées par la plateforme
  /// (`rpc_types_espaces_publics`) : code + libellé, y compris les types
  /// créés par l'Expert (ex. « Salon de coiffure »).
  ///
  /// Repli hors ligne : les types standards du module 15. Ne lève jamais.
  Future<List<({String code, String libelle})>> listerCategories() async {
    final Set<String> vus = <String>{};
    final List<({String code, String libelle})> liste =
        <({String code, String libelle})>[];

    try {
      final dynamic reponse = await _client.rpc('rpc_types_espaces_publics');

      if (reponse is List) {
        for (final dynamic element in reponse) {
          if (element is! Map) continue;
          final String code = (element['type'] ?? '').toString().trim();
          final String libelle = (element['libelle'] ?? '').toString().trim();
          if (code.isEmpty || libelle.isEmpty || !vus.add(code)) continue;
          liste.add((code: code, libelle: libelle));
        }
      }
    } catch (e) {
      debugPrint('EspaceService.listerCategories (repli local) : $e');
    }

    if (liste.isEmpty) {
      for (final TypeEspace type in TypeEspace.values) {
        liste.add((code: type.code, libelle: type.libelle));
      }
    }

    return liste;
  }

  /// 🧹 Remise à zéro de l'état de SESSION métier après une bascule.
  ///
  /// Ce qui NE doit PAS survivre à un changement d'entreprise :
  ///   • le panier (lignes, remises, cadeaux) — sinon une vente de la
  ///     pharmacie serait encaissée sur la boutique ;
  ///   • l'historique des scans (mêmes raisons) ;
  ///   • les totaux mis en cache (l'accueil et les listes sont prévenus).
  ///
  /// Ce qui survit légitimement : la session, les préférences d'affichage et
  /// le catalogue public.
  void _reinitialiserSessionMetier() {
    PanierService.instance.vider();
    ScannerService.instance.viderHistorique();
    generation.value = generation.value + 1;

    // Carillon commun : accueil, ventes, tableaux de bord et caches de
    // lecture se rafraîchissent sur le NOUVEAU contexte.
    DonneesService.instance.signale('entreprise');
  }

  /// Vide le cache (déconnexion, changement de compte).
  void reinitialiser() {
    etat.value = null;
    // Déconnexion : plus aucune boutique active (le compte suivant ne doit
    // jamais hériter de l'espace de données du précédent).
    ScopeDonnees.reinitialiser();
    _reinitialiserSessionMetier();
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
    } on EspaceServiceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('EspaceService ($libelle) : ${e.message}');

      // Fonction absente : la migration du Module 15 n'est pas installée.
      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const EspaceServiceException(
          "Le module multi-entreprises n'est pas installé sur la base. "
          'Exécutez le script '
          'supabase/migrations/20260916000019_module15_multi_entreprises.sql '
          'puis réessayez.',
          code: 'NON_DEPLOYE',
        );
      }

      throw EspaceServiceException(
        messageErreur(e.message),
        code: e.message.split('|').first.trim().toUpperCase(),
      );
    } catch (e, st) {
      debugPrint('EspaceService ($libelle) : $e\n$st');
      throw EspaceServiceException(messageEchec);
    }
  }
}
