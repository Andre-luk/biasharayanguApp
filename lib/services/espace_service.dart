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
        etat.value = resultat;
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

  // ---------------------------------------------------------------------------
  // ÉCRITURE
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
        if (actuel != null) {
          etat.value = actuel.avecActif(espaceId);
        } else {
          await charger();
        }
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

  /// Vide le cache (déconnexion, changement de compte).
  void reinitialiser() {
    etat.value = null;
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
