// lib/services/note_credit_service.dart
//
// 🧾 MODULE 32 — AVOIRS (notes de crédit).
//
// Aucun montant n'est calculé ici : `note_credit_creer` vérifie le plafond
// (on ne peut pas rendre plus que ce qui a été encaissé), numérote l'avoir et
// l'écrit dans le journal d'audit. Le téléphone ne fait que transmettre.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/note_credit.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier d'un avoir (message déjà en français).
class NoteCreditException implements Exception {
  const NoteCreditException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Accès aux avoirs. Singleton : `NoteCreditService.instance`.
class NoteCreditService {
  NoteCreditService._();

  static final NoteCreditService instance = NoteCreditService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Émet un avoir. Le serveur refuse tout montant supérieur à la vente.
  Future<NoteCredit> creer({
    required double montant,
    TypeAvoir type = TypeAvoir.avoir,
    String? motif,
    String? venteId,
    String? factureNumero,
    String? clientId,
    String? clientNom,
    String? clientTelephone,
    String? modeRemboursement,
  }) async {
    if (montant <= 0) {
      throw const NoteCreditException(
        'Indiquez un montant supérieur à zéro.',
      );
    }

    try {
      final dynamic reponse = await _client.rpc(
        'note_credit_creer',
        params: <String, dynamic>{
          'p_montant': montant,
          'p_motif': motif,
          'p_type': type.code,
          'p_vente_id': venteId,
          'p_facture_numero': factureNumero,
          'p_client_id': clientId,
          'p_client_nom': clientNom,
          'p_client_tel': clientTelephone,
          'p_mode': modeRemboursement,
        },
      );

      final Map<String, dynamic>? map = parseMap(reponse);
      if (map == null) {
        throw const NoteCreditException('L\'avoir n\'a pas pu être enregistré.');
      }
      return NoteCredit.fromMap(map);
    } on PostgrestException catch (e) {
      throw NoteCreditException(_message(e.message));
    } catch (e) {
      if (e is NoteCreditException) rethrow;
      debugPrint('NoteCreditService.creer : $e');
      throw const NoteCreditException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
      );
    }
  }

  /// Avoirs de la boutique (les plus récents d'abord).
  Future<List<NoteCredit>> lister({
    DateTime? debut,
    DateTime? fin,
    String? recherche,
    int limite = 100,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'note_credit_lister',
        params: <String, dynamic>{
          'p_debut': _date(debut),
          'p_fin': _date(fin),
          'p_recherche': recherche,
          'p_limite': limite,
        },
      );
      return parseMapList(reponse)
          .map(NoteCredit.fromMap)
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw NoteCreditException(_message(e.message));
    } catch (e) {
      debugPrint('NoteCreditService.lister : $e');
      throw const NoteCreditException(
        'Impossible de charger les avoirs : vérifiez votre réseau.',
      );
    }
  }

  /// Annule un avoir (il n'est jamais supprimé).
  Future<void> annuler(String id, {String? motif}) async {
    if (id.trim().isEmpty) {
      throw const NoteCreditException('Avoir inconnu.');
    }
    try {
      await _client.rpc(
        'note_credit_annuler',
        params: <String, dynamic>{'p_id': id, 'p_motif': motif},
      );
    } on PostgrestException catch (e) {
      throw NoteCreditException(_message(e.message));
    } catch (e) {
      debugPrint('NoteCreditService.annuler : $e');
      throw const NoteCreditException(
        'Impossible d\'annuler cet avoir : vérifiez votre réseau.',
      );
    }
  }

  /// 🧾 MODULE 34 — REMET EN STOCK la marchandise rendue.
  ///
  /// [lignes] = `[{'produit_id': 12, 'quantite': 3, 'prix_achat': 800}]`
  /// — la quantité est en UNITÉS DE BASE, le prix d'achat est FACULTATIF.
  Future<void> retourStock(
    String noteId,
    List<Map<String, dynamic>> lignes,
  ) async {
    if (noteId.trim().isEmpty) {
      throw const NoteCreditException('Avoir inconnu.');
    }
    if (lignes.isEmpty) {
      throw const NoteCreditException(
        'Indiquez au moins un article à remettre en stock.',
      );
    }
    try {
      await _client.rpc(
        'avoir_retour_stock',
        params: <String, dynamic>{
          'p_note_id': noteId,
          'p_lignes': lignes,
        },
      );
    } on PostgrestException catch (e) {
      throw NoteCreditException(_message(e.message));
    } catch (e) {
      debugPrint('NoteCreditService.retourStock : $e');
      throw const NoteCreditException(
        'Impossible de remettre en stock : vérifiez votre réseau.',
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
