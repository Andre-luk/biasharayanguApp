// lib/services/securite_service.dart
//
// MODULE 12 — SÉCURITÉ CÔTÉ APPLICATION (MIDDLEWARE GLOBAL).
//
//  1. `verifierActionSensible(nature)` — miroir client de la garde serveur
//     `public.verifier_action_sensible(text)` :
//        • contrôle LOCAL d'abord (rapide, sans réseau — même règle que la
//          connexion : abonnement échu = lecture seule, suspendu = bloqué) ;
//        • revérification SERVEUR ensuite (la décision finale lui appartient,
//          y compris si un statut a changé depuis l'ouverture de l'écran).
//     Toute écriture sensible de l'application doit passer par ici : ventes,
//     stock, dépenses, dettes, imports, achats de quotas de l'agent IA…
//
//  2. Écran « Sécurité » (personnel plateforme) :
//        • `derniereConnexions()` → dernières connexions + compteurs 24 h ;
//        • `alertes()`            → tentatives échouées répétées, IP suspectes ;
//        • `resetPermissions()`   → réinitialise les surcharges (Super Admin).
//
// ⚠️ Toujours du bon côté du principe « ne jamais faire confiance au client » :
// ce service AMÉLIORE l'expérience (message clair, blocage anticipé) mais
// chaque RPC/trigger revérifie les droits et l'abonnement côté serveur.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/audit.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/audit_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';

/// Nature d'une erreur de sécurité.
enum TypeErreurSecurite { abonnement, droits, reseau, inconnu }

/// Erreur de sécurité (message déjà rédigé en français).
class SecuriteException implements Exception {
  const SecuriteException(
    this.message, {
    this.code = '',
    this.type = TypeErreurSecurite.inconnu,
  });

  final String message;

  /// Code serveur (`ABONNEMENT_BLOQUE`, `ABONNEMENT_EXPIRE`, `ACCES_REFUSE`…).
  final String code;

  final TypeErreurSecurite type;

  @override
  String toString() => message;
}

/// Garde d'abonnement + écran Sécurité. Singleton : `SecuriteService.instance`.
class SecuriteService {
  SecuriteService._();

  static final SecuriteService instance = SecuriteService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // 1. GARDE DES ACTIONS SENSIBLES
  // ---------------------------------------------------------------------------

  /// Vérifie qu'une action sensible peut être réalisée MAINTENANT.
  ///
  /// Lève [SecuriteException] si l'abonnement de la boutique est suspendu ou
  /// échu. Ne renvoie rien quand l'action est autorisée.
  ///
  /// [nature] est un libellé court inséré dans le message (« vente »,
  /// « modification de prix », « import des articles »…).
  Future<void> verifierActionSensible(String nature) async {
    // 1) Contrôle local immédiat (état connu de la session).
    if (AbonnementService.instance.lectureSeule) {
      throw SecuriteException(
        'Abonnement échu (lecture seule) : impossible de réaliser '
        '« $nature ». Renouvelez l\'abonnement pour continuer.',
        code: 'ABONNEMENT_EXPIRE',
        type: TypeErreurSecurite.abonnement,
      );
    }

    // 2) Contrôle serveur — la décision finale revient à la base.
    try {
      await _client.rpc(
        'verifier_action_sensible',
        params: <String, dynamic>{'p_nature': nature},
      );
    } on PostgrestException catch (e) {
      final String code = e.message.split('|').first.trim().toUpperCase();
      if (code == 'ABONNEMENT_BLOQUE' || code == 'ABONNEMENT_EXPIRE') {
        throw SecuriteException(
          AuditService.messageErreur(e.message),
          code: code,
          type: TypeErreurSecurite.abonnement,
        );
      }
      if (code == 'ACCES_REFUSE' || code == 'DROIT_REFUSE') {
        throw SecuriteException(
          AuditService.messageErreur(e.message),
          code: code,
          type: TypeErreurSecurite.droits,
        );
      }
      // Fonction absente (déploiement intermédiaire) ou autre incident :
      // on n'invente pas un blocage — le serveur revérifiera de toute façon.
      debugPrint('SecuriteService.verifierActionSensible ($code) ignoré : ${e.message}');
    } catch (e) {
      debugPrint('SecuriteService.verifierActionSensible ignoré (réseau) : $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 2. ÉCRAN SÉCURITÉ (PERSONNEL PLATEFORME)
  // ---------------------------------------------------------------------------

  /// Dernières connexions / déconnexions / échecs + compteurs (24 h / 7 j).
  Future<ResultatConnexions> derniereConnexions({int limit = 50}) async {
    final dynamic reponse = await _executer(
      () => _client.rpc(
        'rpc_securite_connexions',
        params: <String, dynamic>{'p_limit': limit},
      ),
      actionLibelle: 'le chargement des connexions',
    );

    return ResultatConnexions.depuisRpc(reponse);
  }

  /// Alertes calculées : tentatives échouées par email, IPs suspectes.
  Future<ResultatAlertes> alertes() async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_securite_alertes'),
      actionLibelle: 'le chargement des alertes',
    );

    return ResultatAlertes.depuisRpc(reponse);
  }

  /// Réinitialise les permissions personnalisées d'un rôle (ou de TOUS les
  /// rôles si [roleCode] est `null`). Réservé au Super Admin côté serveur.
  ///
  /// Recharge ensuite les surcharges pour que l'application reflète l'état.
  Future<Map<String, dynamic>> resetPermissions({String? roleCode}) async {
    final dynamic reponse = await _executer(
      () => _client.rpc(
        'rpc_securite_reset_permissions',
        params: <String, dynamic>{
          if (roleCode != null && roleCode.isNotEmpty) 'p_role': roleCode,
        },
      ),
      actionLibelle: 'la réinitialisation des permissions',
    );

    await PermissionService.instance.rechargerSurcharges();

    final Map<String, dynamic>? map = reponse is Map
        ? Map<String, dynamic>.from(reponse)
        : null;
    return map ?? <String, dynamic>{'reinitialise': true};
  }

  // ---------------------------------------------------------------------------
  // 3. INTERNES
  // ---------------------------------------------------------------------------

  Future<T> _executer<T>(
    Future<T> Function() action, {
    required String actionLibelle,
  }) async {
    try {
      return await action();
    } on SecuriteException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('SecuriteService ($actionLibelle) : ${e.message}');
      throw SecuriteException(
        AuditService.messageErreur(e.message),
        code: e.message.split('|').first.trim().toUpperCase(),
        type: TypeErreurSecurite.droits,
      );
    } catch (e) {
      debugPrint('SecuriteService ($actionLibelle) : $e');
      throw const SecuriteException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurSecurite.reseau,
      );
    }
  }
}
