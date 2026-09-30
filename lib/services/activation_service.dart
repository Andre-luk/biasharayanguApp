// lib/services/activation_service.dart
//
// MODULE 14 — WORKFLOW D'ACTIVATION À DOUBLE VALIDATION (côté application).
//
// Séparation stricte des responsabilités (le serveur revérifie chaque rôle
// à chaque appel — ce service n'est qu'une façade) :
//
//   1. Soumission          → `rpc_entreprise_creer` (à la création du compte) :
//                            le dossier passe EN ATTENTE DE VÉRIFICATION.
//   2. GESTIONNAIRE DES COMPTES → [verifier] : vérifie le dossier et le
//                            transmet à la finance (ou rejette avec motif).
//   3. FINANCE             → [validerFinance] : valide le paiement réellement
//                            reçu puis l'activation est AUTOMATIQUE :
//                              • paiement total   → 30 jours immédiats ;
//                              • paiement partiel → 7 jours d'essai + solde.
//   4. Suivi automatique   → [synchroniser] (au démarrage) : restriction
//                            quand le solde est impayé à l'échéance,
//                            réactivation après régularisation.
//
// Les données ne sont JAMAIS supprimées : un compte restreint reste
// consultable (lecture seule, Module 3).
//
// API SQL : `supabase/migrations/20260916000018_module14_activation.sql`.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/activation.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du workflow d'activation.
///
/// [message] est toujours rédigé en français et peut être affiché tel quel.
class ActivationServiceException implements Exception {
  const ActivationServiceException(this.message, {this.code});

  final String message;

  /// Code serveur (`DROIT_REFUSE`, `ETAPE_INVALIDE`…) quand disponible.
  final String? code;

  @override
  String toString() => message;
}

class ActivationService {
  ActivationService._();

  static final ActivationService instance = ActivationService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // LECTURE
  // ---------------------------------------------------------------------------

  /// Tableau de bord du dossier d'activation.
  ///
  /// Sans [entrepriseId] : dossier de l'utilisateur connecté (son
  /// entreprise). Avec [entrepriseId] : dossier d'une entreprise précise
  /// (réservé au personnel plateforme ou aux membres de l'entreprise).
  Future<EtatActivation> chargerEtat({String? entrepriseId}) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_activation_etat',
          params: <String, dynamic>{'p_entreprise_id': entrepriseId},
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const ActivationServiceException(
            "Le serveur a renvoyé une réponse inattendue pour votre dossier.",
          );
        }

        return EtatActivation.fromMap(map);
      },
      "le chargement de votre dossier d'activation",
      "Impossible de charger votre dossier d'activation. "
          'Vérifiez votre connexion internet.',
    );
  }

  /// Liste des dossiers d'activation (écrans GESTIONNAIRE / FINANCE).
  ///
  /// [etape] filtre sur une étape précise (`en_attente_verification`,
  /// `verifie`, `actif`, `restreint`, `rejete`). `null` = tous les dossiers.
  Future<List<DossierActivation>> lister({String? etape}) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_activation_lister',
          params: <String, dynamic>{'p_etape': etape},
        );

        if (reponse is! List) return const <DossierActivation>[];

        return reponse
            .whereType<Map>()
            .map((Map element) =>
                DossierActivation.fromMap(Map<String, dynamic>.from(element)))
            .toList(growable: false);
      },
      "le chargement des dossiers d'activation",
      'Impossible de charger les dossiers d\'activation. '
          'Vérifiez votre connexion internet.',
    );
  }

  // ---------------------------------------------------------------------------
  // ÉCRITURE — GESTIONNAIRE DES COMPTES
  // ---------------------------------------------------------------------------

  /// Première validation (GESTIONNAIRE DES COMPTES / SUPER_ADMIN).
  ///
  /// - [approuver] `true`  → le dossier passe « vérifié » et attend la
  ///   finance ;
  /// - [approuver] `false` → rejet : [note] (motif) est obligatoire.
  ///
  /// ⚠️ Le gestionnaire n'active jamais un compte : seule la finance
  /// valide l'activation finale (vérifié par le serveur).
  Future<EtapeActivation> verifier({
    required String entrepriseId,
    required bool approuver,
    String? note,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_activation_verifier',
          params: <String, dynamic>{
            'p_entreprise_id': entrepriseId,
            'p_approuver': approuver,
            'p_note': note,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        return EtapeActivation.fromCode(
            parseStringOrNull(map?['etape']));
      },
      'la vérification du dossier',
      'Impossible de vérifier ce dossier. Vérifiez votre connexion internet.',
    );
  }

  // ---------------------------------------------------------------------------
  // ÉCRITURE — FINANCE (VALIDATION FINALE + ACTIVATION AUTOMATIQUE)
  // ---------------------------------------------------------------------------

  /// Validation finale (FINANCE_LAPERLE / SUPER_ADMIN).
  ///
  /// Enregistre le paiement réellement reçu ([montant], [modePaiement],
  /// [referenceTransaction]) puis la base applique automatiquement :
  ///   - paiement total   → activation immédiate, 30 jours ;
  ///   - paiement partiel → 7 jours d'essai + solde à régler.
  ///
  /// [approuver] `false` enregistre un rejet (le paiement n'est pas
  /// confirmé) : [note] (motif) est alors obligatoire.
  ///
  /// Renvoie la réponse brute de la base (étape, statut, dates, montants).
  Future<Map<String, dynamic>> validerFinance({
    required String entrepriseId,
    required bool approuver,
    double? montant,
    String? modePaiement,
    String? referenceTransaction,
    String? note,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_activation_valider_finance',
          params: <String, dynamic>{
            'p_entreprise_id': entrepriseId,
            'p_approuver': approuver,
            'p_montant': montant,
            'p_mode_paiement': modePaiement,
            'p_reference_transaction': referenceTransaction,
            'p_note': note,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const ActivationServiceException(
            'Le serveur a renvoyé une réponse inattendue.',
          );
        }
        return map;
      },
      'la validation du paiement et l\'activation du compte',
      'Impossible de valider ce paiement. Vérifiez votre connexion '
          'internet puis réessayez.',
    );
  }

  // ---------------------------------------------------------------------------
  // ÉCRITURE — MONTANT TOTAL DÛ (MODULE 21)
  // ---------------------------------------------------------------------------

  /// Fixe le montant total dû de l'abonnement d'une entreprise.
  ///
  /// C'est le champ qui manquait à la fenêtre « Valider le paiement » : sans
  /// lui, une entreprise sans grille tarifaire ne pouvait pas être activée
  /// (`MONTANT_TOTAL_INCONNU`), et un montant négocié était ignoré au profit
  /// du prix générique du pack. `solde_restant` étant calculé par la base
  /// (total − payé), le solde se met à jour automatiquement.
  ///
  /// Renvoie le nouveau solde restant, tel que calculé par le serveur.
  Future<double> definirMontantTotal({
    required String entrepriseId,
    required double montant,
    String? note,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_activation_definir_montant_total',
          params: <String, dynamic>{
            'p_entreprise_id': entrepriseId,
            'p_montant': montant,
            'p_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const ActivationServiceException(
            'Le serveur a renvoyé une réponse inattendue.',
          );
        }
        return parseDouble(map['solde_restant']);
      },
      'l\'enregistrement du montant total dû',
      'Impossible d\'enregistrer le montant total dû. Vérifiez votre '
          'connexion internet puis réessayez.',
    );
  }

  // ---------------------------------------------------------------------------
  // AUTOMATISATION (démarrage de l'application)
  // ---------------------------------------------------------------------------

  /// Restriction automatique (solde impayé à l'échéance) et réactivation
  /// (après régularisation). Best-effort : appelée au démarrage, un échec
  /// ne doit jamais bloquer l'application.
  Future<void> synchroniserSilencieux() async {
    try {
      await _client.rpc('rpc_activation_synchroniser');
    } catch (e) {
      debugPrint('ActivationService.synchroniser (ignoré): $e');
    }
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
    } on ActivationServiceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('ActivationService ($libelle) : ${e.message}');

      // Fonction absente : la migration du Module 14 n'est pas installée.
      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const ActivationServiceException(
          "Le workflow d'activation n'est pas installé sur la base. "
          'Exécutez le script '
          'supabase/migrations/20260916000018_module14_activation.sql '
          'puis réessayez.',
          code: 'NON_DEPLOYE',
        );
      }

      throw ActivationServiceException(
        messageErreur(e.message),
        code: e.message.split('|').first.trim().toUpperCase(),
      );
    } catch (e, st) {
      debugPrint('ActivationService ($libelle) : $e\n$st');
      throw ActivationServiceException(messageEchec);
    }
  }
}
