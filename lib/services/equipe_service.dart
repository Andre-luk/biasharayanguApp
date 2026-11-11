// lib/services/equipe_service.dart
//
//  MON ÉQUIPE — création des comptes collaborateurs SANS code d'invitation.
//
//  Le propriétaire saisit lui-même le nom, l'e-mail, le mot de passe et le
//  rôle : le serveur crée le compte Auth (mot de passe haché) et le rattache à
//  SON entreprise. La session du propriétaire n'est jamais remplacée.
//
//  S'appuie sur la migration 0140 (`rpc_collaborateur_creer`,
//  `rpc_collaborateurs_lister`, `rpc_collaborateur_maj`).
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/collaborateur_entreprise.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

class EquipeException implements Exception {
  final String message;
  final String? code;

  const EquipeException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Rôles qu'un propriétaire peut donner (aucun rôle de plateforme).
const List<({String code, String libelle})> kRolesCollaborateur = [
  (code: 'VENDEUR', libelle: 'Vendeur / caissier'),
  (code: 'MAGASINIER', libelle: 'Magasinier / stock'),
  (code: 'COMPTABLE_ENTREPRISE', libelle: 'Comptable'),
  (code: 'PROPRIETAIRE', libelle: 'Responsable (tous les droits)'),
];

class EquipeService {
  EquipeService._();
  static final EquipeService instance = EquipeService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Traduit un message serveur « CODE|texte » en message lisible.
  static String messageErreur(String? brut) {
    final String texte = (brut ?? '').trim();
    if (texte.isEmpty) {
      return 'Opération impossible : réessayez dans quelques instants.';
    }

    final int separateur = texte.indexOf('|');
    final String message =
        separateur >= 0 ? texte.substring(separateur + 1).trim() : texte;

    const Map<String, String> complements = <String, String>{
      'SESSION_ABSENTE': 'Session expirée : reconnectez-vous.',
      'DROIT_REFUSE':
          'Seul le propriétaire peut créer ou modifier un collaborateur.',
      'NOM_REQUIS': 'Indiquez le nom du collaborateur.',
      'EMAIL_INVALIDE':
          'Adresse e-mail invalide : elle sert d\'identifiant de connexion.',
      'MOT_DE_PASSE_TROP_COURT':
          'Le mot de passe doit comporter au moins 8 caractères.',
      'ROLE_INVALIDE': 'Choisissez un rôle valide pour ce collaborateur.',
      'COMPTE_EXISTANT':
          'Cette adresse e-mail est déjà utilisée. Choisissez-en une autre.',
      'COLLABORATEUR_INTROUVABLE':
          'Ce collaborateur n\'appartient pas à votre entreprise.',
      'ACTION_INTERDITE':
          'Vous ne pouvez pas modifier votre propre compte ici.',
    };

    for (final MapEntry<String, String> e in complements.entries) {
      if (texte.contains(e.key)) return e.value;
    }

    final bool nonDeploye = texte.contains('PGRST202') ||
        texte.contains('Could not find the function');
    if (nonDeploye) {
      return 'Le module Équipe n\'est pas encore installé sur le serveur. '
          'Exécutez la migration 20260916000140_collaborateurs_sans_code.sql.';
    }

    return message.isEmpty ? 'Opération impossible.' : message;
  }

  Future<dynamic> _appel(String nom, [Map<String, dynamic>? params]) async {
    try {
      return await _client.rpc(nom, params: params);
    } on PostgrestException catch (e) {
      final String codeBrut = (e.message.split('|').first).trim().toUpperCase();
      throw EquipeException(messageErreur(e.message), code: codeBrut);
    } catch (e) {
      debugPrint('EquipeService.$nom : $e');
      throw const EquipeException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        code: 'RESEAU',
      );
    }
  }

  /// L'équipe de l'entreprise du propriétaire connecté.
  Future<List<CollaborateurEntreprise>> collaborateurs() async {
    final dynamic reponse = await _appel('rpc_collaborateurs_lister');
    final Map<String, dynamic> racine =
        parseMap(reponse) ?? const <String, dynamic>{};
    return parseMapList(racine['lignes'])
        .map(CollaborateurEntreprise.depuisJson)
        .toList(growable: false);
  }

  /// Crée le compte d'un collaborateur rattaché à l'entreprise.
  ///
  /// [espaceId] = boutique où il travaillera (`null` = boutique par défaut).
  Future<CollaborateurEntreprise> creer({
    required String nom,
    String prenom = '',
    required String email,
    String telephone = '',
    required String motDePasse,
    required String role,
    String? espaceId,
  }) async {
    final dynamic reponse = await _appel('rpc_collaborateur_creer', {
      'p_nom': nom,
      'p_prenom': prenom,
      'p_email': email,
      'p_telephone': telephone,
      'p_mot_de_passe': motDePasse,
      'p_role': role,
      'p_espace_id': espaceId,
    });

    final Map<String, dynamic> res =
        parseMap(reponse) ?? const <String, dynamic>{};
    return CollaborateurEntreprise(
      id: parseString(res['id']),
      nom: nom,
      prenom: prenom,
      email: parseString(res['email']).isEmpty
          ? email.trim().toLowerCase()
          : parseString(res['email']),
      telephone: telephone,
      role: parseString(res['role']).isEmpty
          ? role.toUpperCase()
          : parseString(res['role']),
      actif: true,
      espaceId: parseStringOrNull(res['espace_id']) ?? espaceId,
    );
  }

  /// Change le rôle, l'état (actif) ou le mot de passe d'un collaborateur.
  ///
  /// [espaceId] non nul = déplace le collaborateur vers cette boutique.
  Future<void> maj({
    required String id,
    required String nom,
    String prenom = '',
    String telephone = '',
    required String role,
    bool actif = true,
    String? motDePasse,
    String? espaceId,
  }) async {
    await _appel('rpc_collaborateur_maj', {
      'p_id': id,
      'p_nom': nom,
      'p_prenom': prenom,
      'p_telephone': telephone,
      'p_role': role,
      'p_actif': actif,
      'p_mot_de_passe': (motDePasse == null || motDePasse.trim().length < 8)
          ? null
          : motDePasse.trim(),
      'p_espace_id': espaceId,
    });
  }
}
