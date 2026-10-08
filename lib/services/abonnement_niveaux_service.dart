// lib/services/abonnement_niveaux_service.dart
//
// 🧩 CORRECTIF 65 — CATALOGUE DES NIVEAUX D'ABONNEMENT (CRUD).
//
// Facade Dart des RPC livrées par la migration 65 :
//   • `niveaux_abonnement`              → lecture (RLS : lecture seule) ;
//   • `rpc_abonnement_niveau_enregistrer` → créer / modifier (Super Admin) ;
//   • `rpc_abonnement_niveau_supprimer`   → supprimer (Super Admin) ;
//   • `rpc_abonnement_definir_niveau_entreprise` → niveau NÉGOCIÉ d'une
//     entreprise (Finance, gestionnaire des comptes ou Super Admin).
//
// ⚠️ Les écritures passent OBLIGATOIREMENT par les RPC : la table n'accepte
// aucune écriture directe (correctif 66). Un commerçant ne peut donc pas
// s'octroyer un niveau supérieur.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/niveau_abonnement.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du catalogue des niveaux.
class NiveauxAbonnementException implements Exception {
  const NiveauxAbonnementException(this.message);

  /// Message déjà rédigé en français, affichable tel quel.
  final String message;

  @override
  String toString() => message;
}

/// Le niveau NÉGOCIÉ d'une entreprise (colonnes du correctif 65).
class NiveauEntreprise {
  const NiveauEntreprise({
    this.niveau,
    this.fonctionnalites = const <String>{},
    this.modulesEffectifs,
  });

  /// Niveau explicitement affecté (`null` = celui du pack tarifaire).
  final String? niveau;

  /// Fonctionnalités négociées (`null` en base = suivre le niveau).
  final Set<String> fonctionnalites;

  /// Fonctionnalités réellement appliquées (résolues côté serveur).
  /// `null` = AUCUNE restriction (règle fail-open).
  final Set<String>? modulesEffectifs;

  /// Y a-t-il une négociation particulière (hors niveau) ?
  bool get negocie => fonctionnalites.isNotEmpty;

  /// Aucune restriction appliquée ?
  bool get sansRestriction =>
      modulesEffectifs == null || modulesEffectifs!.isEmpty;
}

class NiveauxAbonnementService {
  NiveauxAbonnementService._();

  static final NiveauxAbonnementService instance = NiveauxAbonnementService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // LECTURE
  // ---------------------------------------------------------------------------

  /// Tous les niveaux du catalogue, dans l'ordre d'affichage.
  Future<List<NiveauAbonnement>> lister() {
    return _executer(
      () async {
        final dynamic reponse = await _client
            .from('niveaux_abonnement')
            .select()
            .order('ordre')
            .order('code');

        return parseMapList(reponse)
            .map(NiveauAbonnement.fromMap)
            .toList(growable: false);
      },
      messageEchec:
          'Impossible de charger les niveaux d\'abonnement. Vérifiez votre connexion internet.',
    );
  }

  /// Le niveau et les fonctionnalités d'une entreprise.
  Future<NiveauEntreprise> lireNiveauEntreprise(String entrepriseId) {
    return _executer(
      () async {
        final dynamic ligne = await _client
            .from('entreprises')
            .select('niveau_abonnement, modules_abonnement')
            .eq('id', entrepriseId)
            .maybeSingle();

        final Map<String, dynamic>? map = parseMap(ligne);

        Set<String>? effectifs;
        try {
          final dynamic modules = await _client.rpc(
            'abonnement_modules_entreprise',
            params: <String, dynamic>{'p_entreprise_id': entrepriseId},
          );
          effectifs = _codes(modules);
        } catch (e) {
          //  Best-effort : sans cette information on affiche simplement
          //  « aucune restriction », jamais une erreur.
          debugPrint('NiveauxAbonnementService (modules effectifs) : $e');
        }

        return NiveauEntreprise(
          niveau: parseStringOrNull(map?['niveau_abonnement']),
          fonctionnalites: _codes(map?['modules_abonnement']),
          modulesEffectifs: effectifs,
        );
      },
      messageEchec:
          'Impossible de lire le niveau de cette entreprise. Vérifiez votre connexion internet.',
    );
  }

  // ---------------------------------------------------------------------------
  // ÉCRITURE — CATALOGUE (Super Admin)
  // ---------------------------------------------------------------------------

  /// Crée ou met à jour un niveau.
  Future<NiveauAbonnement> enregistrer(NiveauAbonnement niveau) {
    return _executer(
      () async {
        if (niveau.code.trim().isEmpty) {
          throw const NiveauxAbonnementException(
            'Indiquez un code de niveau (lettres, chiffres, souligné).',
          );
        }
        if (niveau.libelle.trim().isEmpty) {
          throw const NiveauxAbonnementException(
            'Indiquez le nom affiché du niveau.',
          );
        }

        await _client.rpc(
          'rpc_abonnement_niveau_enregistrer',
          params: niveau.versRpc(),
        );

        return niveau;
      },
      messageEchec:
          'Impossible d\'enregistrer ce niveau. Vérifiez votre connexion internet.',
    );
  }

  /// Supprime un niveau. Refusé s'il est encore utilisé (le serveur le dit).
  Future<void> supprimer(String code) {
    return _executer(
      () async {
        await _client.rpc(
          'rpc_abonnement_niveau_supprimer',
          params: <String, dynamic>{'p_code': code},
        );
      },
      messageEchec:
          'Impossible de supprimer ce niveau. Vérifiez votre connexion internet.',
    );
  }

  // ---------------------------------------------------------------------------
  // ÉCRITURE — NIVEAU NÉGOCIÉ D'UNE ENTREPRISE (Finance)
  // ---------------------------------------------------------------------------

  /// Fixe le niveau et/ou les fonctionnalités NÉGOCIÉES d'une entreprise.
  ///
  /// [fonctionnalites] laissé à `null` = ne pas modifier. Une liste VIDE
  /// remet l'entreprise sur son niveau (annule la négociation).
  Future<void> affecterEntreprise({
    required String entrepriseId,
    String? niveau,
    Set<String>? fonctionnalites,
    String? note,
  }) {
    return _executer(
      () async {
        await _client.rpc(
          'rpc_abonnement_definir_niveau_entreprise',
          params: <String, dynamic>{
            'p_entreprise_id': entrepriseId,
            'p_niveau': niveau,
            'p_modules': fonctionnalites == null
                ? null
                : (fonctionnalites.toList(growable: false)..sort()),
            'p_note': note,
          },
        );
      },
      messageEchec:
          'Impossible d\'enregistrer le niveau de cette entreprise. Vérifiez votre connexion internet.',
    );
  }

  // ---------------------------------------------------------------------------
  // OUTILS
  // ---------------------------------------------------------------------------

  /// Extrait le texte utile d'un message serveur (« CODE|message »).
  ///
  /// Les RPC du projet préfixent leurs erreurs métier par un code suivi de
  /// `|` : c'est ce qui suit qui est destiné à l'utilisateur. Tout autre
  /// message (réseau, droits, contrainte technique) est remplacé par
  /// [repli], plus compréhensible.
  static String messageErreur(String brut, {required String repli}) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return repli;
    return texte.substring(separateur + 1).trim();
  }

  Future<T> _executer<T>(
    Future<T> Function() action, {
    required String messageEchec,
  }) async {
    try {
      return await action();
    } on NiveauxAbonnementException {
      rethrow;
    } catch (e) {
      final String brut = e is PostgrestException ? e.message : e.toString();
      debugPrint('NiveauxAbonnementService : $e');
      throw NiveauxAbonnementException(
        messageErreur(brut, repli: messageEchec),
      );
    }
  }

  static Set<String> _codes(dynamic valeur) {
    if (valeur is! List) return const <String>{};

    return valeur
        .map((dynamic element) => element.toString().trim())
        .where((String code) => code.isNotEmpty)
        .toSet();
  }
}
