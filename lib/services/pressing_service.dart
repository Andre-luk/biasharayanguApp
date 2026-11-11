// lib/services/pressing_service.dart
//
// 🧺 MODULE 35 — PRESSING & BLANCHISSERIE : ACCÈS AU MÉTIER.
//
// ⚠️ RÈGLE DE CE SERVICE : il ne calcule AUCUN montant, ne décide AUCUN
//    statut, ne numérote AUCUNE commande. Le serveur fait tout cela dans une
//    transaction (numérotation atomique, prix figés, refus de double remise,
//    politique de solde). Le téléphone transmet et affiche.
//
// Les erreurs du serveur arrivent sous la forme `CODE|texte français` : on
// n'affiche que le texte, jamais le code technique.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/pressing.dart';
import 'package:biashara_yangu/models/pressing_caisse.dart';
import 'package:biashara_yangu/models/pressing_equipe.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier d'une opération de pressing (message déjà en français).
class PressingException implements Exception {
  const PressingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Accès au module Pressing. Singleton : `PressingService.instance`.
class PressingService {
  PressingService._();

  static final PressingService instance = PressingService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // RÉGLAGES
  // ---------------------------------------------------------------------------

  Future<PressingConfig> config() async {
    try {
      final dynamic r = await _client.rpc('pressing_config_lire');
      final Map<String, dynamic>? map = parseMap(r);
      if (map == null) return PressingConfig.defaut;
      return PressingConfig.fromMap(map);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.config : $e');
      throw const PressingException(
        'Impossible de lire les réglages du pressing : vérifiez le réseau.',
      );
    }
  }

  Future<PressingConfig> enregistrerConfig(PressingConfig config) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_config_enregistrer',
        params: <String, dynamic>{'p_champs': config.toRpc()},
      );
      final Map<String, dynamic>? map = parseMap(r);
      return map == null ? config : PressingConfig.fromMap(map);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.enregistrerConfig : $e');
      throw const PressingException(
        'Impossible d\'enregistrer les réglages : vérifiez le réseau.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // CATALOGUE (types de vêtements, prestations, tarifs)
  // ---------------------------------------------------------------------------

  Future<PressingCatalogue> catalogue() async {
    try {
      final dynamic r = await _client.rpc('pressing_catalogue_lister');
      final Map<String, dynamic>? map = parseMap(r);
      if (map == null) return const PressingCatalogue();
      return PressingCatalogue.fromMap(map);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.catalogue : $e');
      throw const PressingException(
        'Impossible de charger le catalogue du pressing.',
      );
    }
  }

  /// Crée les types de vêtements et prestations de départ **sans aucun prix**
  /// (le propriétaire fixe ses tarifs lui-même).
  Future<PressingCatalogue> amorcerCatalogue() async {
    try {
      final dynamic r = await _client.rpc('pressing_amorcer_catalogue');
      final Map<String, dynamic>? map = parseMap(r);
      if (map == null) return const PressingCatalogue();
      return PressingCatalogue.fromMap(map);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.amorcerCatalogue : $e');
      throw const PressingException(
        'Impossible de préparer le catalogue : vérifiez le réseau.',
      );
    }
  }

  Future<String> categorieEnregistrer({
    String? id,
    required String nom,
    int ordre = 100,
    bool actif = true,
  }) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_categorie_enregistrer',
        params: <String, dynamic>{
          'p_id': id,
          'p_nom': nom,
          'p_ordre': ordre,
          'p_actif': actif,
        },
      );
      return parseString((parseMap(r) ?? <String, dynamic>{})['id']);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.categorieEnregistrer : $e');
      throw const PressingException(
        'Impossible d\'enregistrer ce type de vêtement.',
      );
    }
  }

  Future<String> prestationEnregistrer({
    String? id,
    required String nom,
    String? description,
    int dureeHeures = 24,
    int delaiJours = 3,
    double supplementUrgence = 0,
    bool actif = true,
  }) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_prestation_enregistrer',
        params: <String, dynamic>{
          'p_id': id,
          'p_nom': nom,
          'p_description': description,
          'p_duree_heures': dureeHeures,
          'p_delai_jours': delaiJours,
          'p_supplement_urgence': supplementUrgence,
          'p_actif': actif,
        },
      );
      return parseString((parseMap(r) ?? <String, dynamic>{})['id']);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.prestationEnregistrer : $e');
      throw const PressingException(
        'Impossible d\'enregistrer cette prestation.',
      );
    }
  }

  Future<void> tarifDefinir({
    required String prestationId,
    String? categorieId,
    required double prix,
  }) async {
    try {
      await _client.rpc(
        'pressing_tarif_definir',
        params: <String, dynamic>{
          'p_prestation_id': prestationId,
          'p_categorie_id': categorieId,
          'p_prix': prix,
        },
      );
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.tarifDefinir : $e');
      throw const PressingException('Impossible d\'enregistrer ce tarif.');
    }
  }

  Future<void> tarifSupprimer(String tarifId) async {
    try {
      await _client.rpc(
        'pressing_tarif_supprimer',
        params: <String, dynamic>{'p_tarif_id': tarifId},
      );
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.tarifSupprimer : $e');
      throw const PressingException('Impossible de désactiver ce tarif.');
    }
  }

  // ---------------------------------------------------------------------------
  // ÉTAPES DE TRAITEMENT
  // ---------------------------------------------------------------------------

  Future<List<PressingEtape>> etapes() async {
    try {
      final dynamic r = await _client.rpc('pressing_etapes_lister');
      return parseMapList(r).map(PressingEtape.fromMap).toList(growable: false);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.etapes : $e');
      throw const PressingException(
        'Impossible de charger les étapes de traitement.',
      );
    }
  }

  Future<List<PressingEtape>> amorcerEtapes() async {
    try {
      final dynamic r = await _client.rpc('pressing_amorcer_etapes');
      return parseMapList(r).map(PressingEtape.fromMap).toList(growable: false);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.amorcerEtapes : $e');
      throw const PressingException(
        'Impossible de préparer les étapes de traitement.',
      );
    }
  }

  Future<String> etapeEnregistrer({
    String? id,
    required String code,
    required String libelle,
    int ordre = 100,
    bool finale = false,
    bool actif = true,
  }) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_etape_enregistrer',
        params: <String, dynamic>{
          'p_id': id,
          'p_code': code,
          'p_libelle': libelle,
          'p_ordre': ordre,
          'p_finale': finale,
          'p_actif': actif,
        },
      );
      return parseString((parseMap(r) ?? <String, dynamic>{})['id']);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.etapeEnregistrer : $e');
      throw const PressingException('Impossible d\'enregistrer cette étape.');
    }
  }

  // ---------------------------------------------------------------------------
  // CLIENTS
  // ---------------------------------------------------------------------------

  Future<List<PressingClient>> clients({
    String? recherche,
    int limite = 100,
  }) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_clients_lister',
        params: <String, dynamic>{
          'p_recherche': (recherche ?? '').trim().isEmpty ? null : recherche,
          'p_limite': limite,
        },
      );
      return parseMapList(r)
          .map(PressingClient.fromMap)
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.clients : $e');
      throw const PressingException(
        'Impossible de charger les clients du pressing.',
      );
    }
  }

  /// Renvoie l'identifiant du client. Le serveur réutilise la fiche existante
  /// si le téléphone est déjà connu (pas de doublon).
  Future<String> clientEnregistrer({
    String? id,
    required String nom,
    String? telephone,
    String? adresse,
    String? email,
    String? notes,
  }) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_client_enregistrer',
        params: <String, dynamic>{
          'p_id': id,
          'p_nom': nom,
          'p_telephone': telephone,
          'p_adresse': adresse,
          'p_email': email,
          'p_notes': notes,
        },
      );
      return parseString((parseMap(r) ?? <String, dynamic>{})['id']);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.clientEnregistrer : $e');
      throw const PressingException(
        'Impossible d\'enregistrer ce client : vérifiez le réseau.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // DÉPÔTS ET COMMANDES
  // ---------------------------------------------------------------------------

  /// Enregistre un dépôt complet et renvoie le dossier créé (numéro, QR,
  /// lignes, totaux). `referenceLocale` rend l'opération idempotente en
  /// mode hors ligne : rejouer le même dépôt ne crée pas de doublon.
  Future<PressingCommande> depot({
    required List<LigneDepot> lignes,
    String? clientId,
    DateTime? datePrevue,
    double remise = 0,
    double supplement = 0,
    bool urgence = false,
    String? observations,
    double? paiementMontant,
    String? paiementMode,
    String? paiementReference,
    String? referenceLocale,
  }) async {
    if (lignes.isEmpty) {
      throw const PressingException('Ajoutez au moins un vêtement au dépôt.');
    }

    final Map<String, dynamic>? paiement =
        (paiementMontant != null && paiementMontant > 0)
            ? <String, dynamic>{
                'montant': paiementMontant,
                'mode': (paiementMode ?? 'especes'),
                if ((paiementReference ?? '').trim().isNotEmpty)
                  'reference': paiementReference!.trim(),
              }
            : null;

    try {
      final dynamic r = await _client.rpc(
        'pressing_depot_creer',
        params: <String, dynamic>{
          'p_client_id': clientId,
          'p_lignes': lignes.map((LigneDepot l) => l.toJson()).toList(),
          'p_date_prevue': datePrevue?.toIso8601String(),
          'p_remise': remise,
          'p_supplement': supplement,
          'p_urgence': urgence,
          'p_observations': observations,
          'p_paiement': paiement,
          'p_reference_locale': referenceLocale,
        },
      );
      final Map<String, dynamic>? map = parseMap(r);
      if (map == null) {
        throw const PressingException(
          'Le dépôt a été enregistré mais la réponse est illisible.',
        );
      }
      return PressingCommande.fromMap(map);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      if (e is PressingException) rethrow;
      debugPrint('PressingService.depot : $e');
      throw const PressingException(
        'Impossible d\'enregistrer le dépôt : vérifiez le réseau.',
      );
    }
  }

  Future<List<PressingCommandeResume>> commandes({
    String? statut,
    String? recherche,
    DateTime? debut,
    DateTime? fin,
    int limite = 100,
  }) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_commandes_lister',
        params: <String, dynamic>{
          'p_statut': statut,
          'p_recherche': (recherche ?? '').trim().isEmpty ? null : recherche,
          'p_debut': _date(debut),
          'p_fin': _date(fin),
          'p_limite': limite,
        },
      );
      return parseMapList(r)
          .map(PressingCommandeResume.fromMap)
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.commandes : $e');
      throw const PressingException(
        'Impossible de charger les commandes du pressing.',
      );
    }
  }

  Future<PressingCommande> commande(String id) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_commande_fiche',
        params: <String, dynamic>{'p_commande_id': id},
      );
      final Map<String, dynamic>? map = parseMap(r);
      if (map == null) {
        throw const PressingException('Commande introuvable.');
      }
      return PressingCommande.fromMap(map);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      if (e is PressingException) rethrow;
      debugPrint('PressingService.commande : $e');
      throw const PressingException(
        'Impossible de charger cette commande : vérifiez le réseau.',
      );
    }
  }

  /// Retrouve une commande à partir du contenu d'un QR code scanné.
  /// Le serveur vérifie que la commande appartient bien à CE pressing.
  Future<PressingCommande> commandeParQr(String token) async {
    if (token.trim().isEmpty) {
      throw const PressingException('Code illisible.');
    }
    try {
      final dynamic r = await _client.rpc(
        'pressing_commande_par_qr',
        params: <String, dynamic>{'p_token': token.trim()},
      );
      final Map<String, dynamic>? map = parseMap(r);
      if (map == null) {
        throw const PressingException(
          'Ce code ne correspond à aucune commande de ce pressing.',
        );
      }
      return PressingCommande.fromMap(map);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      if (e is PressingException) rethrow;
      debugPrint('PressingService.commandeParQr : $e');
      throw const PressingException(
        'Impossible de vérifier ce code : vérifiez le réseau.',
      );
    }
  }

  /// Fait passer un vêtement à une étape du pipeline.
  Future<void> avancerLigne(
    String ligneId,
    String etapeCode, {
    String? note,
  }) async {
    try {
      await _client.rpc(
        'pressing_ligne_avancer',
        params: <String, dynamic>{
          'p_ligne_id': ligneId,
          'p_etape': etapeCode,
          'p_note': note,
          'p_agent_id': null,
        },
      );
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.avancerLigne : $e');
      throw const PressingException(
        'Impossible de mettre à jour le traitement : vérifiez le réseau.',
      );
    }
  }

  /// Applique la même étape à plusieurs vêtements (traitement par lot).
  Future<void> avancerLot(
    List<String> ligneIds,
    String etapeCode, {
    String? note,
  }) async {
    if (ligneIds.isEmpty) {
      throw const PressingException('Sélectionnez au moins un vêtement.');
    }
    try {
      await _client.rpc(
        'pressing_lignes_avancer_lot',
        params: <String, dynamic>{
          'p_ligne_ids': ligneIds,
          'p_etape': etapeCode,
          'p_note': note,
        },
      );
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.avancerLot : $e');
      throw const PressingException(
        'Impossible de mettre à jour ces vêtements : vérifiez le réseau.',
      );
    }
  }

  /// 🧺 La FILE DE TRAVAIL de l'atelier : chaque vêtement non remis, avec son
  /// dossier, son étape et son agent. `etape` filtre sur une étape précise.
  Future<List<PressingLigneAtelier>> atelier({
    String? etape,
    bool miennes = false,
    int limite = 500,
  }) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_atelier_lister',
        params: <String, dynamic>{
          'p_etape': (etape ?? '').trim().isEmpty ? null : etape,
          'p_miennes': miennes,
          'p_limite': limite,
        },
      );
      return parseMapList(r)
          .map(PressingLigneAtelier.fromMap)
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.atelier : $e');
      throw const PressingException(
        'Impossible de charger la file de l\'atelier : vérifiez le réseau.',
      );
    }
  }

  /// Contrôle qualité : `ok = true` ⇒ prêt ; sinon ⇒ à retraiter.
  Future<void> controleQualite(
    String ligneId,
    bool ok, {
    String? note,
  }) async {
    try {
      await _client.rpc(
        'pressing_controle_qualite',
        params: <String, dynamic>{
          'p_ligne_id': ligneId,
          'p_ok': ok,
          'p_note': note,
        },
      );
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.controleQualite : $e');
      throw const PressingException(
        'Impossible d\'enregistrer le contrôle qualité.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // ARGENT
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> paiementAjouter({
    required String commandeId,
    required double montant,
    String mode = 'especes',
    String? reference,
  }) async {
    if (montant <= 0) {
      throw const PressingException('Indiquez un montant supérieur à zéro.');
    }
    try {
      final dynamic r = await _client.rpc(
        'pressing_paiement_ajouter',
        params: <String, dynamic>{
          'p_commande_id': commandeId,
          'p_montant': montant,
          'p_mode': mode,
          'p_reference': reference,
        },
      );
      return parseMap(r) ?? <String, dynamic>{};
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.paiementAjouter : $e');
      throw const PressingException(
        'Impossible d\'enregistrer ce paiement : vérifiez le réseau.',
      );
    }
  }

  /// Annule un encaissement (jamais de suppression) — réservé au propriétaire.
  Future<void> paiementAnnuler(String paiementId, String motif) async {
    if (motif.trim().isEmpty) {
      throw const PressingException('Indiquez le motif de l\'annulation.');
    }
    try {
      await _client.rpc(
        'pressing_paiement_annuler',
        params: <String, dynamic>{
          'p_paiement_id': paiementId,
          'p_motif': motif.trim(),
        },
      );
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.paiementAnnuler : $e');
      throw const PressingException(
        'Impossible d\'annuler ce paiement : vérifiez le réseau.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // REMISE DES VÊTEMENTS
  // ---------------------------------------------------------------------------

  /// Remet au client les vêtements sélectionnés (partiel ou total).
  /// Le serveur refuse tout vêtement non prêt ou déjà remis.
  Future<PressingCommande> retrait({
    required String commandeId,
    required List<String> ligneIds,
    double? montantEncaisse,
    String? mode,
    String? reference,
    String? observations,
    String? signataire,
  }) async {
    if (ligneIds.isEmpty) {
      throw const PressingException('Sélectionnez au moins un vêtement.');
    }

    final Map<String, dynamic>? paiement =
        (montantEncaisse != null && montantEncaisse > 0)
            ? <String, dynamic>{
                'montant': montantEncaisse,
                'mode': (mode ?? 'especes'),
                if ((reference ?? '').trim().isNotEmpty)
                  'reference': reference!.trim(),
              }
            : null;

    try {
      final dynamic r = await _client.rpc(
        'pressing_retrait_enregistrer',
        params: <String, dynamic>{
          'p_commande_id': commandeId,
          'p_ligne_ids': ligneIds,
          'p_paiement': paiement,
          'p_observations': observations,
          'p_signataire': signataire,
        },
      );
      final Map<String, dynamic>? map = parseMap(r);
      if (map == null) {
        throw const PressingException(
          'La remise a été enregistrée mais la réponse est illisible.',
        );
      }
      return PressingCommande.fromMap(map);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      if (e is PressingException) rethrow;
      debugPrint('PressingService.retrait : $e');
      throw const PressingException(
        'Impossible d\'enregistrer la remise : vérifiez le réseau.',
      );
    }
  }

  Future<List<PressingRetrait>> retraits(String commandeId) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_retraits_lister',
        params: <String, dynamic>{'p_commande_id': commandeId},
      );
      return parseMapList(r)
          .map(PressingRetrait.fromMap)
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.retraits : $e');
      throw const PressingException(
        'Impossible de charger l\'historique des remises.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // PILOTAGE
  // ---------------------------------------------------------------------------

  Future<PressingTableauBord> tableauBord({DateTime? debut, DateTime? fin}) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_tableau_bord',
        params: <String, dynamic>{
          'p_debut': _date(debut),
          'p_fin': _date(fin),
        },
      );
      final Map<String, dynamic>? map = parseMap(r);
      if (map == null) return const PressingTableauBord();
      return PressingTableauBord.fromMap(map);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.tableauBord : $e');
      throw const PressingException(
        'Impossible de charger le tableau de bord du pressing.',
      );
    }
  }

  Future<List<PressingCommandeResume>> enRetard({
    int jours = 0,
    int limite = 100,
  }) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_commandes_en_retard',
        params: <String, dynamic>{'p_jours': jours, 'p_limite': limite},
      );
      return parseMapList(r)
          .map(PressingCommandeResume.fromMap)
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.enRetard : $e');
      throw const PressingException(
        'Impossible de charger les commandes en retard.',
      );
    }
  }

  Future<void> annulerCommande(String commandeId, String motif) async {
    if (motif.trim().isEmpty) {
      throw const PressingException('Indiquez le motif de l\'annulation.');
    }
    try {
      await _client.rpc(
        'pressing_commande_annuler',
        params: <String, dynamic>{
          'p_commande_id': commandeId,
          'p_motif': motif.trim(),
        },
      );
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.annulerCommande : $e');
      throw const PressingException(
        'Impossible d\'annuler cette commande : vérifiez le réseau.',
      );
    }
  }

  /// Réédite le QR code (perte ou compromission) ; l'ancien devient inutile.
  Future<String> regenererQr(String commandeId) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_qr_regenerer',
        params: <String, dynamic>{'p_commande_id': commandeId},
      );
      return parseString((parseMap(r) ?? <String, dynamic>{})['qr_token']);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.regenererQr : $e');
      throw const PressingException(
        'Impossible de rééditer le QR code : vérifiez le réseau.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // ÉQUIPE (métiers du pressing)
  // ---------------------------------------------------------------------------

  /// La caisse d'une journée (encaissements par mode, annulations, activité).
  Future<CaisseJourPressing> caisseJour({DateTime? date}) async {
    try {
      final dynamic r = await _client.rpc(
        'pressing_caisse_jour',
        params: <String, dynamic>{'p_date': _date(date ?? DateTime.now())},
      );
      final Map<String, dynamic>? map = parseMap(r);
      if (map == null) return const CaisseJourPressing();
      return CaisseJourPressing.fromRpc(map);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.caisseJour : $e');
      throw const PressingException(
        'Impossible de charger la caisse du pressing.',
      );
    }
  }

  /// Métier du compte connecté dans son pressing.
  ///
  /// `null` = patron (ou compte sans métier) : tous les droits du pressing.
  /// Sert uniquement à ADAPTER l'interface ; le serveur revérifie tout.
  Future<RolePressing?> rolePressing() async {
    try {
      final dynamic r = await _client.rpc('pressing_role');
      final String? code = r is String
          ? r
          : parseStringOrNull((parseMap(r) ?? <String, dynamic>{})['role']);
      return RolePressing.depuisCode(code);
    } catch (e) {
      debugPrint('PressingService.rolePressing : $e');
      // En cas d'échec on n'enferme personne : les pages gardent leurs droits.
      return null;
    }
  }

  /// L'équipe du pressing + le métier du compte connecté.
  Future<EquipePressing> equipe() async {
    try {
      final dynamic r = await _client.rpc('press_collaborateurs_lister');
      final Map<String, dynamic>? map = parseMap(r);
      if (map == null) return const EquipePressing();
      return EquipePressing.fromRpc(map);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.equipe : $e');
      throw const PressingException(
        'Impossible de charger l\'équipe du pressing.',
      );
    }
  }

  /// Crée le compte d'un collaborateur (le serveur crée le vrai compte Auth).
  Future<String> creerCollaborateur({
    required String nom,
    String prenom = '',
    required String email,
    String telephone = '',
    required String motDePasse,
    required RolePressing role,
  }) async {
    try {
      final dynamic r = await _client.rpc(
        'press_collaborateur_creer',
        params: <String, dynamic>{
          'p_nom': nom,
          'p_prenom': prenom,
          'p_email': email,
          'p_telephone': telephone,
          'p_mot_de_passe': motDePasse,
          'p_role': role.code,
        },
      );
      return parseString((parseMap(r) ?? <String, dynamic>{})['id']);
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.creerCollaborateur : $e');
      throw const PressingException(
        'Impossible de créer ce collaborateur : vérifiez le réseau.',
      );
    }
  }

  /// Change le métier, l'état (actif/inactif) ou le mot de passe.
  Future<void> majCollaborateur({
    required String id,
    required String nom,
    String prenom = '',
    String telephone = '',
    required RolePressing role,
    bool actif = true,
    String? motDePasse,
  }) async {
    try {
      await _client.rpc(
        'press_collaborateur_maj',
        params: <String, dynamic>{
          'p_id': id,
          'p_nom': nom,
          'p_prenom': prenom,
          'p_telephone': telephone,
          'p_role': role.code,
          'p_actif': actif,
          'p_mot_de_passe':
              (motDePasse ?? '').trim().isEmpty ? null : motDePasse!.trim(),
        },
      );
    } on PostgrestException catch (e) {
      throw PressingException(_message(e.message));
    } catch (e) {
      debugPrint('PressingService.majCollaborateur : $e');
      throw const PressingException(
        'Impossible d\'enregistrer ce collaborateur.',
      );
    }
  }

  // ---------------------------------------------------------------------------

  String? _date(DateTime? valeur) {
    if (valeur == null) return null;
    final String mois = valeur.month.toString().padLeft(2, '0');
    final String jour = valeur.day.toString().padLeft(2, '0');
    return '${valeur.year}-$mois-$jour';
  }

  String _message(String brut) {
    final int barre = brut.indexOf('|');
    if (barre == -1) return brut;
    final String texte = brut.substring(barre + 1).trim();
    return texte.isEmpty ? brut : texte;
  }
}
