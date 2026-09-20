// lib/services/agent_service.dart
//
// MODULE 13 — SERVICE DE L'ASSISTANT IA.
//
//   • `envoyerMessage`  → appelle l'EDGE FUNCTION `agent-ia` (le proxy
//     sécurisé : clé DeepSeek côté serveur, quotas, abonnement, outils,
//     journalisation). C'est LE seul chemin de l'application vers l'IA ;
//   • `chargerEtat`     → soldes (pool + mon allocation), tarifs, droits,
//     collaborateurs — via `rpc_agent_ia_etat` (crée le pool + bonus de
//     bienvenue au premier appel) ;
//   • `demanderAchat` / `validerAchat` / `marquerPaye` / `attribuer` /
//     `majConfig` → RPC du Module 13 (montants calculés CÔTÉ SERVEUR) ;
//   • `listerAchats`    → lecture RLS (soi / son entreprise / plateforme).
//
// ⚠️ Rien n'est facturé ici : la facturation (quotas = caractères utiles
// divisés par `caracteres_par_quota`, minimum 1) est faite par l'Edge
// Function, et le débit est atomique (`rpc_agent_ia_debiter`).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/agent_ia.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature d'une erreur de l'assistant (pour adapter l'interface).
enum TypeErreurAgent {
  session,
  quotas,
  abonnement,
  limite,
  assistant,
  droits,
  reseau,
  inconnu,
}

/// Erreur métier de l'assistant (message déjà en français).
class AgentServiceException implements Exception {
  const AgentServiceException(
    this.message, {
    this.code = '',
    this.type = TypeErreurAgent.inconnu,
    this.solde,
    this.tarifParQuota,
    this.prixPack10Quotas,
  });

  final String message;

  /// Code serveur (`QUOTAS_EPUISES`, `ABONNEMENT_EXPIRE`, `LIMITE_MESSAGES`…).
  final String code;

  final TypeErreurAgent type;

  /// Solde restant (renvoyé avec `QUOTAS_EPUISES`).
  final int? solde;

  /// Tarifs renvoyés avec `QUOTAS_EPUISES` (invitation à acheter un pack).
  final double? tarifParQuota;
  final double? prixPack10Quotas;

  @override
  String toString() => message;
}

/// Appels à l'assistant IA et à la gestion des quotas.
/// Singleton : `AgentService.instance`.
class AgentService {
  AgentService._();

  static final AgentService instance = AgentService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Nom de l'Edge Function (proxy sécurisé).
  static const String fonctionAgent = 'agent-ia';

  // ---------------------------------------------------------------------------
  // 1. CHAT — ENVOYER UN MESSAGE À L'ASSISTANT
  // ---------------------------------------------------------------------------

  /// Envoie [message] à l'Edge Function et renvoie la réponse complète
  /// (texte, quotas consommés, montant CDF, solde restant, actions exécutées).
  Future<ReponseAgent> envoyerMessage(String message) async {
    final String texte = message.trim();
    if (texte.isEmpty) {
      throw const AgentServiceException('Écrivez votre demande.');
    }

    dynamic donnees;
    try {
      final FunctionResponse reponse = await _client.functions.invoke(
        fonctionAgent,
        body: <String, dynamic>{'message': texte},
      );
      donnees = reponse.data;
    } on FunctionException catch (e) {
      final Map<String, dynamic>? map = mapDepuis(e.details);
      if (map != null && map['erreur'] != null) {
        throw exceptionDepuis(map);
      }
      if (e.status == 404) {
        // ⚠️ Cas VÉRIFIÉ le 20/09/2026 : la passerelle Supabase répond
        // `{"code":"NOT_FOUND","message":"Requested function was not found"}`
        // tant que la fonction n'est pas PUBLIÉE. Une fonction visible dans le
        // Dashboard mais jamais déployée donne exactement ce 404.
        throw const AgentServiceException(
          "L'assistant n'est pas encore publié sur le serveur : "
          'l\'administrateur doit déployer la fonction « agent-ia » '
          '(Supabase → Edge Functions → agent-ia → Deploy, ou '
          'tools/deploy_agent_ia.sh) et définir le secret DEEPSEEK_API_KEY. '
          'Le reste de l\'application fonctionne normalement.',
          code: 'NON_DEPLOYE',
          type: TypeErreurAgent.assistant,
        );
      }
      if (e.status == 503 || e.status == 500) {
        // La fonction existe mais son serveur refuse : le secret manque le
        // plus souvent (clé IA absente ou invalide).
        throw const AgentServiceException(
          "L'assistant est publié mais son serveur a refusé la demande : "
          'vérifiez la clé IA (secret DEEPSEEK_API_KEY) dans Supabase → '
          'Project Settings → Edge Functions → Secrets.',
          code: 'SECRET_MANQUANT',
          type: TypeErreurAgent.assistant,
        );
      }
      if (e.status == 401) {
        throw const AgentServiceException(
          'Session expirée : reconnectez-vous pour utiliser l\'assistant.',
          code: 'SESSION_ABSENTE',
          type: TypeErreurAgent.session,
        );
      }
      debugPrint('AgentService.envoyerMessage (${e.status}) : ${e.details}');
      throw AgentServiceException(
        'L\'assistant a rencontré une erreur (${e.status}). Réessayez dans un instant.',
        type: TypeErreurAgent.reseau,
      );
    } catch (e) {
      if (e is AgentServiceException) rethrow;
      debugPrint('AgentService.envoyerMessage : $e');
      throw const AgentServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurAgent.reseau,
      );
    }

    final Map<String, dynamic>? map = mapDepuis(donnees);
    if (map == null) {
      throw const AgentServiceException(
        'Réponse inattendue de l\'assistant. Réessayez.',
        type: TypeErreurAgent.inconnu,
      );
    }
    if (map['erreur'] != null) throw exceptionDepuis(map);

    final ReponseAgent? reponse = ReponseAgent.depuisJson(map);
    if (reponse == null) {
      throw const AgentServiceException(
        'Réponse illisible de l\'assistant. Réessayez.',
        type: TypeErreurAgent.inconnu,
      );
    }
    return reponse;
  }

  // ---------------------------------------------------------------------------
  // 2. ÉTAT & QUOTAS
  // ---------------------------------------------------------------------------

  /// État complet : tarifs, pool de l'entreprise (+ bonus de bienvenue crédité
  /// une seule fois), mon allocation, droits et collaborateurs.
  Future<EtatAgentIa> chargerEtat() {
    return _executer<EtatAgentIa>(
      () async {
        final dynamic reponse = await _client.rpc('rpc_agent_ia_etat');
        final EtatAgentIa? etat = EtatAgentIa.depuisRpc(reponse);
        if (etat == null) {
          throw const AgentServiceException(
            'État des quotas illisible. Réessayez.',
          );
        }
        return etat;
      },
      'le chargement des quotas',
    );
  }

  /// Réglages de l'assistant (lecture seule — les tarifs sont publics).
  Future<AgentIaConfig> chargerConfig() {
    return _executer<AgentIaConfig>(
      () async {
        final dynamic ligne = await _client
            .from('agent_ia_config')
            .select(
              'tarif_par_quota, caracteres_par_quota, prix_pack_10_quotas, '
              'quotas_offerts_inscription, actif',
            )
            .limit(1)
            .maybeSingle();
        return AgentIaConfig.depuisJson(ligne) ?? AgentIaConfig.defaut;
      },
      'le chargement de la configuration',
    );
  }

  /// Demande un pack de quotas (montant calculé par le SERVEUR).
  Future<Map<String, dynamic>> demanderAchat({
    required int nombreQuotas,
    String modePaiement = 'especes',
    String? note,
  }) {
    return _executer<Map<String, dynamic>>(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_agent_ia_demander_achat',
          params: <String, dynamic>{
            'p_nombre_quotas': nombreQuotas,
            'p_mode_paiement': modePaiement,
            if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
          },
        );
        return parseMap(reponse) ?? <String, dynamic>{};
      },
      'l\'envoi de la demande',
    );
  }

  /// Super Admin : approuve (crédite le pool) ou refuse une demande.
  Future<Map<String, dynamic>> validerAchat({
    required String achatId,
    required bool approuver,
    String? note,
  }) {
    return _executer<Map<String, dynamic>>(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_agent_ia_valider_achat',
          params: <String, dynamic>{
            'p_achat_id': achatId,
            'p_approuver': approuver,
            if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
          },
        );
        return parseMap(reponse) ?? <String, dynamic>{};
      },
      'la validation de la demande',
    );
  }

  /// Marque un achat PAYÉ : le propriétaire règle depuis sa caisse (une
  /// dépense est écrite), le Super Admin confirme l'encaissement.
  Future<Map<String, dynamic>> marquerPaye({
    required String achatId,
    String? note,
  }) {
    return _executer<Map<String, dynamic>>(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_agent_ia_marquer_paye',
          params: <String, dynamic>{
            'p_achat_id': achatId,
            if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
          },
        );
        return parseMap(reponse) ?? <String, dynamic>{};
      },
      'le marquage du paiement',
    );
  }

  /// Propriétaire : attribue [quotas] du pool à un membre de l'équipe.
  Future<Map<String, dynamic>> attribuer({
    required String utilisateurId,
    required int quotas,
  }) {
    return _executer<Map<String, dynamic>>(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_agent_ia_attribuer',
          params: <String, dynamic>{
            'p_utilisateur': utilisateurId,
            'p_quotas': quotas,
          },
        );
        return parseMap(reponse) ?? <String, dynamic>{};
      },
      'l\'attribution des quotas',
    );
  }

  /// Super Admin : met à jour les tarifs/réglages.
  Future<Map<String, dynamic>> majConfig(AgentIaConfig config) {
    return _executer<Map<String, dynamic>>(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_agent_ia_config_maj',
          params: <String, dynamic>{
            'p_tarif_par_quota': config.tarifParQuota,
            'p_caracteres_par_quota': config.caracteresParQuota,
            'p_prix_pack_10_quotas': config.prixPack10Quotas,
            'p_quotas_offerts_inscription': config.quotasOffertsInscription,
            'p_actif': config.actif,
          },
        );
        return parseMap(reponse) ?? <String, dynamic>{};
      },
      'l\'enregistrement de la configuration',
    );
  }

  // ---------------------------------------------------------------------------
  // 3. HISTORIQUE DES ACHATS (RLS : soi / entreprise / plateforme)
  // ---------------------------------------------------------------------------

  /// Derniers achats/demandes visibles pour la session, noms des demandeurs
  /// renseignés (jointure best-effort).
  Future<List<AchatQuotas>> listerAchats({int limit = 60}) {
    return _executer<List<AchatQuotas>>(
      () async {
        final dynamic donnees = await _client
            .from('agent_ia_achats')
            .select('*')
            .order('created_at', ascending: false)
            .limit(limit);
        final List<Map<String, dynamic>> bruts = parseMapList(donnees);
        if (bruts.isEmpty) return const <AchatQuotas>[];

        final Set<String> ids = bruts
            .map((Map<String, dynamic> e) => parseString(e['utilisateur_id']))
            .where((String id) => id.isNotEmpty)
            .toSet();

        final Map<String, String> noms = <String, String>{};
        if (ids.isNotEmpty) {
          try {
            final dynamic utilisateurs = await _client
                .from('utilisateurs')
                .select('id, nom, email')
                .inFilter('id', ids.toList(growable: false));
            for (final Map<String, dynamic> u in parseMapList(utilisateurs)) {
              noms[parseString(u['id'])] = parseString(
                u['nom'],
                fallback: parseString(u['email']),
              );
            }
          } catch (e) {
            debugPrint('AgentService.listerAchats (noms) : $e');
          }
        }

        return bruts
            .map((Map<String, dynamic> e) => AchatQuotas.depuisJson(
                  e,
                  utilisateurNom: noms[parseString(e['utilisateur_id'])] ?? '',
                ))
            .whereType<AchatQuotas>()
            .toList(growable: false);
      },
      'le chargement des achats',
    );
  }

  // ---------------------------------------------------------------------------
  // 4. OUTILS PURS (testables) & INTERNES
  // ---------------------------------------------------------------------------

  /// Convertit une valeur quelconque (Map ou chaîne JSON) en Map.
  static Map<String, dynamic>? mapDepuis(dynamic valeur) {
    final Map<String, dynamic>? direct = parseMap(valeur);
    if (direct != null) return direct;
    if (valeur is String && valeur.trim().isNotEmpty) {
      try {
        return parseMap(jsonDecode(valeur));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Transforme une réponse d'erreur de l'Edge Function en exception typée.
  static AgentServiceException exceptionDepuis(Map<String, dynamic> map) {
    final String code = parseString(map['erreur']).toUpperCase();
    final String message = parseString(
      map['message'],
      fallback: 'L\'assistant a refusé la demande.',
    );

    final TypeErreurAgent type;
    switch (code) {
      case 'SESSION_ABSENTE':
        type = TypeErreurAgent.session;
      case 'QUOTAS_EPUISES':
        type = TypeErreurAgent.quotas;
      case 'ABONNEMENT_EXPIRE':
      case 'ABONNEMENT_BLOQUE':
        type = TypeErreurAgent.abonnement;
      case 'LIMITE_MESSAGES':
      case 'LIMITE_CARACTERES':
        type = TypeErreurAgent.limite;
      case 'ASSISTANT_DESACTIVE':
      case 'ASSISTANT_INDISPONIBLE':
      case 'SECRET_MANQUANT':
      case 'NON_DEPLOYE':
        type = TypeErreurAgent.assistant;
      case 'DROIT_REFUSE':
      case 'ACCES_REFUSE':
        type = TypeErreurAgent.droits;
      default:
        type = TypeErreurAgent.inconnu;
    }

    return AgentServiceException(
      message,
      code: code,
      type: type,
      solde: map['solde'] == null ? null : parseInt(map['solde']),
      tarifParQuota: parseDoubleOrNull(map['tarif_par_quota']),
      prixPack10Quotas: parseDoubleOrNull(map['prix_pack_10_quotas']),
    );
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
  ) async {
    try {
      return await action();
    } on AgentServiceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('AgentService ($libelle) : ${e.message}');
      throw AgentServiceException(
        messageErreur(e.message),
        code: e.message.split('|').first.trim().toUpperCase(),
      );
    } catch (e) {
      debugPrint('AgentService ($libelle) : $e');
      throw const AgentServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurAgent.reseau,
      );
    }
  }
}
