// lib/services/code_validation_agent_service.dart
//
// 🔐 CORRECTIF 69 — FAÇADE DART DU CODE DE VALIDATION DE L'AGENT.
//
// RPC de la migration 69 :
//   • `rpc_agent_code_demander`          → l'agent demande un code ;
//   • `rpc_agent_code_emettre`           → la Finance l'émet ;
//   • `rpc_agent_code_valider`           → l'agent le saisit ;
//   • `rpc_agent_code_revoquer`          → la Finance annule sa demande ;
//   • `rpc_agent_codes_lister`           → l'état des demandes ;
//   • `rpc_agent_dossiers_sans_code`     → ce que la Finance doit confirmer.
//
// ⚠️ DEUX PRÉCAUTIONS QUI NE SONT PAS DU ZÈVE
//
//   1. LE CODE N'EST JAMAIS ÉCRIT DANS UN JOURNAL, ni ici ni en base. Pas de
//      `debugPrint` du code émis : un journal applicatif se lit, se copie et
//      se partage. Le code ne vit que le temps de l'afficher à la Finance.
//
//   2. `emettre` NE DOIT PAS ÊTRE APPELÉ PAR L'AGENT. Le serveur refuse de
//      toute façon (FINANCE_LAPERLE ou SUPER_ADMIN seuls) ; l'écran ne doit
//      donc pas lui proposer le bouton, pas même grisé sans explication.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/code_validation_agent.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du code de validation.
class CodeAgentException implements Exception {
  const CodeAgentException(this.message, {this.type = TypeErreurCodeAgent.inconnu});

  /// Message déjà rédigé en français, affichable tel quel.
  final String message;

  final TypeErreurCodeAgent type;

  @override
  String toString() => message;
}

/// Nature de l'échec, pour que l'écran réagisse correctement.
enum TypeErreurCodeAgent {
  /// La base n'a pas encore reçu la migration 69.
  nonDeploye,

  /// Rôle insuffisant (ex. l'agent qui tenterait d'émettre).
  droits,

  /// Aucune session.
  session,

  /// Le code saisi est refusé : faux, expiré, déjà utilisé, ou jamais émis.
  /// C'est le cas le plus fréquent — l'écran doit le dire précisément.
  codeRefuse,

  /// La demande est close (déjà utilisée, révoquée).
  close,

  introuvable,
  validation,
  reseau,
  inconnu,
}

/// Service du code de validation de l'agent.
class CodeValidationAgentService {
  CodeValidationAgentService._();

  static final CodeValidationAgentService instance =
      CodeValidationAgentService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  /// L'agent demande un code pour un compte.
  ///
  /// Idempotent côté serveur : si une demande est déjà ouverte, elle est
  /// RETOURNÉE au lieu d'en créer une seconde (`dejaOuverte` le signale).
  Future<DemandeCodeAgent?> demander(
    String entrepriseId, {
    String? motif,
  }) {
    return _executer<DemandeCodeAgent?>(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_agent_code_demander',
          params: <String, dynamic>{
            'p_entreprise_id': entrepriseId,
            'p_motif': motif,
          },
        );
        return DemandeCodeAgent.depuisJson(reponse);
      },
      'la demande de code',
    );
  }

  /// La Finance (ou le Super Admin) émet un code à 6 chiffres.
  ///
  /// ⚠️ Ne JAMAIS journaliser le résultat : il contient le code. On l'affiche,
  /// la Finance le transmet à l'agent, et il n'est conservé nulle part côté
  /// application.
  Future<EmissionCodeAgent?> emettre(String demandeId) {
    return _executer<EmissionCodeAgent?>(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_agent_code_emettre',
          params: <String, dynamic>{'p_demande_id': demandeId},
        );
        return EmissionCodeAgent.depuisJson(reponse);
      },
      'l\'émission du code',
    );
  }

  /// L'agent saisit le code que la Finance lui a communiqué.
  ///
  /// Le serveur distingue code faux, expiré, déjà utilisé et jamais émis : le
  /// message renvoyé est donc directement exploitable.
  Future<void> valider(String demandeId, String code) {
    return _executer<void>(
      () async {
        await _client.rpc(
          'rpc_agent_code_valider',
          params: <String, dynamic>{
            'p_demande_id': demandeId,
            'p_code': code.trim(),
          },
        );
      },
      'la saisie du code',
    );
  }

  /// La Finance revoque une demande (elle ne sera plus utilisable).
  Future<void> revoquer(String demandeId, {String? motif}) {
    return _executer<void>(
      () async {
        await _client.rpc(
          'rpc_agent_code_revoquer',
          params: <String, dynamic>{
            'p_demande_id': demandeId,
            'p_motif': motif,
          },
        );
      },
      'la révocation de la demande',
    );
  }

  // ---------------------------------------------------------------------------
  // LECTURES
  // ---------------------------------------------------------------------------

  /// État des demandes de code.
  ///
  /// Le champ `code` revient **vide** pour l'agent : le serveur ne le transmet
  /// qu'à la Finance et au Super Admin. L'écran doit donc utiliser
  /// `codeDisponible` avant d'afficher quoi que ce soit.
  Future<List<CodeValidationAgent>> lister({
    String? entrepriseId,
    int limite = 100,
  }) {
    return _executer<List<CodeValidationAgent>>(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_agent_codes_lister',
          params: <String, dynamic>{
            'p_entreprise_id': entrepriseId,
            'p_limite': limite,
          },
        );
        final Map<String, dynamic>? map = parseMap(reponse);
        return CodeValidationAgent.listeDepuisJson(map?['codes']);
      },
      'le chargement des codes',
    );
  }

  /// Les dossiers vérifiés SANS code valide : ce que la Finance doit confirmer.
  Future<DossiersSansCode> dossiersSansCode({int limite = 100}) {
    return _executer<DossiersSansCode>(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_agent_dossiers_sans_code',
          params: <String, dynamic>{'p_limite': limite},
        );
        return DossiersSansCode.depuisJson(reponse);
      },
      'le chargement des dossiers à confirmer',
    );
  }

  // ---------------------------------------------------------------------------
  // ERREURS
  // ---------------------------------------------------------------------------

  /// Extrait le message utile d'une erreur serveur au format `CODE|texte fr`.
  ///
  /// ⚠️ `CODE_REFUSE|Code refuse (CODE_INCORRECT). Vérifiez les 6 chiffres…` :
  /// c'est le cas le plus fréquent, et le serveur y a déjà mis la raison ET la
  /// marche à suivre. On ne reformule donc rien.
  static String messageErreur(String brut, {required String repli}) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return repli;
    return texte.substring(separateur + 1).trim();
  }

  static TypeErreurCodeAgent typeDepuisMessage(String? brut) {
    final String code = (brut ?? '').toUpperCase();

    if (code.contains('PGRST202') || code.contains('NON_DEPLOYE')) {
      return TypeErreurCodeAgent.nonDeploye;
    }
    if (code.contains('SESSION_ABSENTE')) return TypeErreurCodeAgent.session;
    if (code.contains('DROIT_REFUSE')) return TypeErreurCodeAgent.droits;
    if (code.contains('CODE_REFUSE')) return TypeErreurCodeAgent.codeRefuse;
    if (code.contains('CODE_DEJA_UTILISE') ||
        code.contains('DEMANDE_REVOQUEE') ||
        code.contains('DEMANDE_CLOSE')) {
      return TypeErreurCodeAgent.close;
    }
    if (code.contains('DEMANDE_INTROUVABLE')) {
      return TypeErreurCodeAgent.introuvable;
    }
    if (code.contains('CODE_REQUIS') ||
        code.contains('PARAMETRES_INVALIDES') ||
        code.contains('ENTREPRISE_INTROUVABLE')) {
      return TypeErreurCodeAgent.validation;
    }
    return TypeErreurCodeAgent.inconnu;
  }

  Future<T> _executer<T>(
    Future<T> Function() action,
    String libelle,
  ) async {
    try {
      return await action();
    } on CodeAgentException {
      rethrow;
    } catch (e) {
      final String brut = e is PostgrestException ? e.message : e.toString();
      //  ⚠️ On journalise l'erreur, JAMAIS une valeur de code : `brut` ne
      //  contient pas de code (le serveur ne le met pas dans ses messages).
      debugPrint('CodeValidationAgentService ($libelle) : $e');
      throw CodeAgentException(
        messageErreur(brut, repli: 'Action impossible : $libelle.'),
        type: typeDepuisMessage(brut),
      );
    }
  }
}
