// lib/services/agent_terrain_service.dart
//
// 🧑‍🌾 MODULE 21 ter — PILOTAGE DE L'AGENT TERRAIN.
//
// Regroupe les RPC cloisonnées du terrain :
//   • `rpc_agent_fiche`               → sa fiche (compteurs, revenus, journal) ;
//   • `rpc_agent_utilisateurs_lister` → ses utilisateurs/clients ;
//   • `rpc_agent_abonnements_lister`  → ses abonnements et ce qu'ils génèrent ;
//   • `rpc_agent_rattacher_entreprise`→ prendre en charge un dossier libre.
//
// ⚠️ Le CLOISONNEMENT est fait par le SERVEUR (filtre `agent_id` + RLS). Ce
// service n'est qu'un appelant : une interface masquée ne protège rien.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/agent_terrain.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature de l'échec, pour choisir le bon message.
enum TypeErreurAgentTerrain { accesRefuse, nonDeploye, validation, reseau, inconnu }

class AgentTerrainException implements Exception {
  const AgentTerrainException(this.message, {this.type = TypeErreurAgentTerrain.inconnu});

  final String message;
  final TypeErreurAgentTerrain type;

  @override
  String toString() => message;
}

class AgentTerrainService {
  AgentTerrainService._();

  static final AgentTerrainService instance = AgentTerrainService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Sa fiche (ou celle d'un agent donné, pour le personnel plateforme).
  Future<FicheAgentTerrain> fiche({String? agentId}) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_agent_fiche', params: <String, dynamic>{
        'p_agent_id': agentId,
      }),
      'le chargement de la fiche agent',
    );

    final Map<String, dynamic>? map = parseMap(reponse);
    if (map == null) {
      throw const AgentTerrainException('Réponse inattendue du serveur.');
    }
    return FicheAgentTerrain.fromMap(map);
  }

  /// Ses utilisateurs (clients/patrons onboardés).
  Future<List<UtilisateurAgentTerrain>> utilisateurs({
    String? agentId,
    String? recherche,
    int limite = 200,
    int decalage = 0,
  }) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_agent_utilisateurs_lister', params: <String, dynamic>{
        'p_agent_id': agentId,
        'p_recherche': (recherche ?? '').trim().isEmpty ? null : recherche,
        'p_limite': limite,
        'p_decalage': decalage,
      }),
      'le chargement des utilisateurs de l\'agent',
    );

    final Map<String, dynamic>? map = parseMap(reponse);
    final List<dynamic> liste =
        (map?['utilisateurs'] as List?) ?? const <dynamic>[];
    return liste
        .whereType<Map>()
        .map((Map e) => UtilisateurAgentTerrain.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Ses abonnements + ce qu'ils ont généré.
  Future<(List<EntrepriseAgentTerrain>, num encaisse, num solde)> abonnements({
    String? agentId,
    String filtre = 'tous',
    int limite = 200,
    int decalage = 0,
  }) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_agent_abonnements_lister', params: <String, dynamic>{
        'p_agent_id': agentId,
        'p_filtre': filtre,
        'p_limite': limite,
        'p_decalage': decalage,
      }),
      'le chargement des abonnements de l\'agent',
    );

    final Map<String, dynamic>? map = parseMap(reponse);
    final List<dynamic> liste =
        (map?['abonnements'] as List?) ?? const <dynamic>[];

    final List<EntrepriseAgentTerrain> abonnements = liste
        .whereType<Map>()
        .map((Map e) =>
            EntrepriseAgentTerrain.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);

    num n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
    return (abonnements, n(map?['montant_encaisse']), n(map?['solde_du']));
  }

  /// Prend en charge une entreprise libre (dossier non attribué).
  Future<bool> rattacher(String entrepriseId) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_agent_rattacher_entreprise',
          params: <String, dynamic>{'p_entreprise_id': entrepriseId}),
      'la prise en charge du dossier',
    );
    return parseMap(reponse)?['ok'] == true;
  }

  /// Texte lisible d'un message serveur préfixé « CODE|texte fr ».
  static String messageErreur(String brut) {
    final int separateur = brut.indexOf('|');
    if (separateur < 0 || separateur == brut.length - 1) return brut;
    return brut.substring(separateur + 1).trim();
  }

  Future<T> _executer<T>(Future<T> Function() action, String libelle) async {
    try {
      return await action();
    } on AgentTerrainException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('AgentTerrainService ($libelle) : ${e.message}');
      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const AgentTerrainException(
          'Le module agent terrain n\'est pas installé sur la base : '
          'exécutez la migration 20260916000047_agent_terrain_cloisonnement.sql.',
          type: TypeErreurAgentTerrain.nonDeploye,
        );
      }
      final String message = messageErreur(e.message);
      if (message.contains('DROIT_REFUSE') || message.contains('ACCES_REFUSE')) {
        throw AgentTerrainException(message,
            type: TypeErreurAgentTerrain.accesRefuse);
      }
      throw AgentTerrainException(message,
          type: TypeErreurAgentTerrain.validation);
    } catch (e) {
      debugPrint('AgentTerrainService ($libelle) : $e');
      throw const AgentTerrainException(
        'Serveur injoignable. Vérifiez votre connexion.',
        type: TypeErreurAgentTerrain.reseau,
      );
    }
  }
}
