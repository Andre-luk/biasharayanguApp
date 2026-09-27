// lib/services/admin_plateforme_service.dart
//
// 🛡️ MODULE 20 — ADMINISTRATION PLATEFORME (audit final).
//
// Regroupe les six appels RPC réservés au personnel plateforme :
//   • parc des boutiques (espaces) : consultation et activation ;
//   • modération du catalogue public : retrait / republication motivés ;
//   • utilisateurs : diagnostic des dépendances puis retrait sûr.
//
// Aucune requête directe sur une table : le serveur revérifie le rôle
// (`est_plateforme()`) DANS chaque fonction. Une interface masquée ne suffit
// jamais — c'est l'architecture retenue par tout le projet.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/admin_plateforme.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature de l'échec, pour que l'écran choisisse le bon message.
enum TypeErreurAdmin {
  /// Les fonctions SQL du module 20 ne sont pas encore installées.
  nonDeploye,

  /// Le compte connecté n'appartient pas à l'équipe plateforme.
  accesRefuse,

  /// Règle métier refusée (motif manquant, propriété à transférer…).
  validation,

  /// Réseau indisponible.
  reseau,

  inconnu,
}

/// Erreur métier de l'administration plateforme.
class AdminPlateformeException implements Exception {
  const AdminPlateformeException(
    this.message, {
    this.type = TypeErreurAdmin.inconnu,
  });

  final String message;
  final TypeErreurAdmin type;

  @override
  String toString() => message;
}

class AdminPlateformeService {
  AdminPlateformeService._();

  static final AdminPlateformeService instance = AdminPlateformeService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // 1. PARC DES BOUTIQUES
  // ---------------------------------------------------------------------------

  /// Liste les boutiques de toutes les entreprises.
  ///
  /// [filtre] : `tous` | `actifs` | `inactifs` | `visibles` | `non_visibles`.
  Future<(List<EspaceAdmin>, ResumeParcEspaces)> listerEspaces({
    String? recherche,
    String filtre = 'tous',
    int limite = 100,
    int decalage = 0,
  }) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_admin_espaces_lister', params: <String, dynamic>{
        'p_recherche': (recherche ?? '').trim().isEmpty ? null : recherche,
        'p_filtre': filtre,
        'p_limite': limite,
        'p_decalage': decalage,
      }),
      'le chargement du parc des boutiques',
    );

    final Map<String, dynamic>? map = parseMap(reponse);
    final List<dynamic> liste =
        (map?['espaces'] as List?) ?? const <dynamic>[];

    final List<EspaceAdmin> espaces = liste
        .whereType<Map>()
        .map((Map e) => EspaceAdmin.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);

    return (espaces, ResumeParcEspaces.fromMap(parseMap(map?['total'])));
  }

  /// Active/désactive une boutique et/ou sa visibilité publique.
  ///
  /// ⚠️ Désactiver une boutique la RETIRE du catalogue public : les deux
  /// notions sont liées côté serveur, on ne peut pas créer d'état incohérent.
  Future<bool> changerStatutEspace({
    required String espaceId,
    bool? actif,
    bool? visible,
    String? motif,
  }) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_admin_espace_statut', params: <String, dynamic>{
        'p_espace_id': espaceId,
        'p_actif': actif,
        'p_visible': visible,
        'p_motif': (motif ?? '').trim().isEmpty ? null : motif,
      }),
      'la mise à jour de la boutique',
    );

    return parseMap(reponse)?['ok'] == true;
  }

  // ---------------------------------------------------------------------------
  // 2. MODÉRATION DU CATALOGUE PUBLIC
  // ---------------------------------------------------------------------------

  /// Inventaire du catalogue public, toutes boutiques confondues.
  ///
  /// [filtre] : `toutes` | `publiees` | `retirees` | `indisponibles`.
  Future<(List<PublicationAdmin>, ResumePublications)> listerPublications({
    String? recherche,
    String filtre = 'toutes',
    String? espaceId,
    int limite = 100,
    int decalage = 0,
  }) async {
    final dynamic reponse = await _executer(
      () =>
          _client.rpc('rpc_admin_publications_lister', params: <String, dynamic>{
        'p_recherche': (recherche ?? '').trim().isEmpty ? null : recherche,
        'p_filtre': filtre,
        'p_espace_id': espaceId,
        'p_limite': limite,
        'p_decalage': decalage,
      }),
      'le chargement du catalogue public',
    );

    final Map<String, dynamic>? map = parseMap(reponse);
    final List<dynamic> liste =
        (map?['publications'] as List?) ?? const <dynamic>[];

    final List<PublicationAdmin> publications = liste
        .whereType<Map>()
        .map((Map e) => PublicationAdmin.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);

    return (publications, ResumePublications.fromMap(parseMap(map?['total'])));
  }

  /// Retire un article du catalogue public, ou le republie.
  ///
  /// Le motif est OBLIGATOIRE en cas de retrait : le commerçant doit
  /// comprendre la décision, c'est une exigence de transparence du module.
  Future<bool> modererPublication({
    required String publicationId,
    required bool publie,
    String? motif,
  }) async {
    final dynamic reponse = await _executer(
      () =>
          _client.rpc('rpc_admin_publication_statut', params: <String, dynamic>{
        'p_publication_id': publicationId,
        'p_publie': publie,
        'p_motif': (motif ?? '').trim().isEmpty ? null : motif,
      }),
      'la modération de l\'article',
    );

    return parseMap(reponse)?['ok'] == true;
  }

  // ---------------------------------------------------------------------------
  // 3. UTILISATEURS — DIAGNOSTIC PUIS RETRAIT SÛR
  // ---------------------------------------------------------------------------

  /// Analyse ce qui dépend d'un utilisateur avant toute décision.
  Future<DependancesUtilisateur> dependancesUtilisateur(
      String utilisateurId) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_admin_utilisateur_dependances',
          params: <String, dynamic>{'p_utilisateur_id': utilisateurId}),
      'l\'analyse des dépendances du compte',
    );

    final Map<String, dynamic>? map = parseMap(reponse);
    if (map == null) {
      throw const AdminPlateformeException(
        'Analyse impossible : réponse inattendue du serveur.',
        type: TypeErreurAdmin.inconnu,
      );
    }
    return DependancesUtilisateur.fromMap(map);
  }

  /// Retire un compte selon la stratégie choisie.
  ///
  /// Le serveur RECALCULE les dépendances : envoyer une décision calculée
  /// côté application ne permet jamais de contourner une contrainte.
  Future<bool> retirerUtilisateur({
    required String utilisateurId,
    required StrategieSuppression strategie,
    String? motif,
  }) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_admin_utilisateur_supprimer',
          params: <String, dynamic>{
            'p_utilisateur_id': utilisateurId,
            'p_mode': strategie.code,
            'p_motif': (motif ?? '').trim().isEmpty ? null : motif,
          }),
      'le retrait du compte',
    );

    return parseMap(reponse)?['ok'] == true;
  }

  // ---------------------------------------------------------------------------
  // OUTILS
  // ---------------------------------------------------------------------------

  /// Extrait le texte lisible d'un message serveur préfixé « CODE|texte fr ».
  static String messageErreur(String brut) {
    final int separateur = brut.indexOf('|');
    if (separateur < 0 || separateur == brut.length - 1) return brut;
    return brut.substring(separateur + 1).trim();
  }

  Future<T> _executer<T>(Future<T> Function() action, String libelle) async {
    try {
      return await action();
    } on AdminPlateformeException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('AdminPlateformeService ($libelle) : ${e.message}');

      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const AdminPlateformeException(
          'L\'administration plateforme n\'est pas installée sur la base. '
          'Exécutez supabase/migrations/20260916000041_admin_plateforme.sql.',
          type: TypeErreurAdmin.nonDeploye,
        );
      }

      final String code = e.message.split('|').first.trim().toUpperCase();
      throw AdminPlateformeException(
        messageErreur(e.message),
        type: switch (code) {
          'ACCES_REFUSE' => TypeErreurAdmin.accesRefuse,
          'ESPACE_INCONNU' ||
          'PRODUIT_INCONNU' ||
          'UTILISATEUR_INCONNU' ||
          'MOTIF_MANQUANT' ||
          'MODE_INCONNU' ||
          'DONNEES_INVALIDES' ||
          'SUPPRESSION_IMPOSSIBLE' ||
          'PROPRIETE_A_TRANSFERER' =>
            TypeErreurAdmin.validation,
          _ => TypeErreurAdmin.inconnu,
        },
      );
    } catch (e, st) {
      debugPrint('AdminPlateformeService ($libelle) : $e\n$st');
      throw const AdminPlateformeException(
        'Impossible de contacter Biashara. Vérifiez votre connexion internet.',
        type: TypeErreurAdmin.reseau,
      );
    }
  }
}
