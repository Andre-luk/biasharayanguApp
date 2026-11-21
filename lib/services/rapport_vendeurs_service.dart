// lib/services/rapport_vendeurs_service.dart
//
// 🧑‍🤝‍🧑 CORRECTIF 179 — ACCÈS AU RAPPORT PAR COLLABORATEUR.
//
// Un seul point d'entrée : `RapportVendeursService.instance.charger(...)`.
// Le calcul (et surtout la reconstitution du stock à l'instant de chaque
// vente) est fait par `rpc_rapport_vendeurs` : l'application ne devine rien.
//
// ⚠️ Aucune écriture : ce service ne lit que le rapport.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/rapport_vendeurs.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur lisible (jamais un message technique brut à l'écran).
class RapportVendeursException implements Exception {
  const RapportVendeursException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RapportVendeursService {
  RapportVendeursService._();

  static final RapportVendeursService instance = RapportVendeursService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Charge le rapport des vendeurs d'une entreprise sur une période.
  ///
  /// [debut] et [fin] sont INCLUSES (le serveur ajoute un jour à `fin`).
  /// En cas d'échec (RPC absente, réseau, droits), lève une
  /// [RapportVendeursException] avec un message utilisable tel quel.
  Future<RapportVendeurs> charger({
    required String entrepriseId,
    DateTime? debut,
    DateTime? fin,
  }) async {
    if (entrepriseId.trim().isEmpty) {
      throw const RapportVendeursException('Entreprise inconnue.');
    }

    try {
      final dynamic reponse = await _client.rpc(
        'rpc_rapport_vendeurs',
        params: <String, dynamic>{
          'p_entreprise_id': entrepriseId,
          'p_debut': _date(debut),
          'p_fin': _date(fin),
        },
      );

      final Map<String, dynamic>? map = parseMap(reponse);
      if (map == null) return RapportVendeurs.vide;
      return RapportVendeurs.fromMap(map);
    } on PostgrestException catch (e) {
      debugPrint('RapportVendeursService.charger : ${e.code} ${e.message}');
      throw RapportVendeursException(_message(e.message));
    } catch (e) {
      debugPrint('RapportVendeursService.charger : $e');
      throw const RapportVendeursException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
      );
    }
  }

  /// `AAAA-MM-JJ` (le serveur attend une `date`, pas un timestamp).
  String? _date(DateTime? d) {
    if (d == null) return null;
    final String mois = d.month.toString().padLeft(2, '0');
    final String jour = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mois-$jour';
  }

  /// Traduit les messages serveur `CODE|texte` en une phrase affichable.
  String _message(String brut) {
    final String texte = brut.trim();
    final int barre = texte.indexOf('|');
    if (barre > 0) {
      final String code = texte.substring(0, barre).trim().toUpperCase();
      final String suite = texte.substring(barre + 1).trim();
      switch (code) {
        case 'SESSION_ABSENTE':
          return 'Votre session a expiré : reconnectez-vous.';
        case 'DROIT_REFUSE':
          return suite.isEmpty
              ? "Votre rôle ne permet pas de consulter ce rapport."
              : suite;
        case 'ENTREPRISE_INCONNUE':
        case 'ENTREPRISE_INTROUVABLE':
          return "Cette entreprise n'existe pas ou plus.";
        case 'PERIODE_INVALIDE':
          return 'La date de fin précède la date de début.';
        case 'MODULE_ABSENT':
          return suite.isEmpty
              ? 'Une mise à jour de la base est nécessaire.'
              : suite;
        default:
          return suite.isEmpty ? texte : suite;
      }
    }
    return texte.isEmpty
        ? 'Impossible de charger le rapport des vendeurs.'
        : texte;
  }
}
