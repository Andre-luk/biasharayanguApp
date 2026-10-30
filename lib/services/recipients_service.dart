// lib/services/recipients_service.dart
//
// REFONTE ABONNEMENTS & DISTRIBUTION — RÉCIPIENTS, ÉCHANGES ET BONUS.
//
// Facade des RPC de la migration 0084 :
//   • `rpc_recipients_types_lister` / `rpc_recipient_type_enregistrer`
//   • `rpc_vente_recipient`        → mouvement(s) de récipient selon le mode
//   • `rpc_recipient_perte`        → casse / perte constatée
//   • `rpc_recipients_solde_client`→ ce que le client détient encore
//   • `rpc_recipients_tableau_bord`→ vue d'ensemble
//   • `rpc_regles_bonus_lister` / `rpc_bonus_regle_enregistrer`
//   • `rpc_bonus_appliquer`        → bonus dus pour une quantité achetée
//
// ⚠️ Ces RPC N'ENREGISTRENT AUCUNE VENTE : elles tracent les récipients et
// les bonus. L'encaissement reste celui de la caisse / des tournées, ce qui
// évite tout double comptage du chiffre d'affaires.

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/recipients.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier lisible (message déjà rédigé en français).
class RecipientsException implements Exception {
  const RecipientsException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class RecipientsService {
  RecipientsService._();

  static final RecipientsService instance = RecipientsService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Transforme « CODE|message » en message français.
  String _lisible(Object erreur) {
    final String brut = erreur.toString();
    final int i = brut.indexOf('|');
    final String texte = i >= 0 ? brut.substring(i + 1).trim() : brut;
    return texte
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^PostgrestException\(.*?message:\s*'), '')
        .trim();
  }

  // ---------------------------------------------------------------------------
  // TYPES DE RÉCIPIENTS
  // ---------------------------------------------------------------------------

  Future<List<TypeRecipient>> types() async {
    try {
      final dynamic reponse = await _client
          .rpc('rpc_recipients_types_lister')
          .timeout(const Duration(seconds: 15));
      return parseMapList(reponse)
          .map(TypeRecipient.fromMap)
          .toList(growable: false);
    } catch (e) {
      throw RecipientsException(_lisible(e));
    }
  }

  Future<String> enregistrerType({
    String? id,
    required String libelle,
    double? contenanceLitres,
    double prixConsigne = 0,
    bool actif = true,
    int ordre = 50,
  }) async {
    try {
      final dynamic reponse = await _client
          .rpc('rpc_recipient_type_enregistrer', params: <String, dynamic>{
        'p_id': id,
        'p_libelle': libelle,
        'p_contenance': contenanceLitres,
        'p_prix_consigne': prixConsigne,
        'p_actif': actif,
        'p_ordre': ordre,
      }).timeout(const Duration(seconds: 15));
      return (reponse ?? '').toString();
    } catch (e) {
      throw RecipientsException(_lisible(e));
    }
  }

  // ---------------------------------------------------------------------------
  // VENTE AVEC RÉCIPIENT (les trois cas)
  // ---------------------------------------------------------------------------

  /// Enregistre les mouvements de récipients et renvoie les montants à
  /// encaisser. **Ne crée pas la vente** (voir l'entête du fichier).
  Future<MontantsVenteRecipient> enregistrerVente({
    required ModeVenteRecipient mode,
    required double prixEau,
    double prixRecipient = 0,
    int quantite = 1,
    String? typeId,
    String? clientId,
    String? clientNom,
    String? tourneeId,
  }) async {
    try {
      final dynamic reponse = await _client
          .rpc('rpc_vente_recipient', params: <String, dynamic>{
        'p_mode': mode.code,
        'p_quantite': quantite,
        'p_type_id': typeId,
        'p_client_id': clientId,
        'p_client_nom': clientNom,
        'p_tournee_id': tourneeId,
        'p_prix_eau': prixEau,
        'p_prix_recipient': prixRecipient,
      }).timeout(const Duration(seconds: 20));

      final Map<String, dynamic>? m = parseMap(reponse);
      if (m == null) {
        throw const RecipientsException('Réponse du serveur illisible.');
      }
      return MontantsVenteRecipient(
        mode: ModeVenteRecipient.depuis(m['mode']?.toString()),
        quantite: parseInt(m['quantite'], fallback: quantite),
        montantEau: parseDouble(m['montant_eau']),
        montantRecipient: parseDouble(m['montant_recipient']),
      );
    } catch (e) {
      if (e is RecipientsException) rethrow;
      throw RecipientsException(_lisible(e));
    }
  }

  /// Déclare une casse ou une perte (sortie définitive).
  Future<String> enregistrerPerte({
    required String typeId,
    int quantite = 1,
    bool casse = false,
    String? clientId,
    String? note,
  }) async {
    try {
      final dynamic reponse = await _client
          .rpc('rpc_recipient_perte', params: <String, dynamic>{
        'p_type_id': typeId,
        'p_quantite': quantite,
        'p_sens': casse ? 'casse' : 'perdu',
        'p_client_id': clientId,
        'p_note': note,
      }).timeout(const Duration(seconds: 15));
      return (reponse ?? '').toString();
    } catch (e) {
      throw RecipientsException(_lisible(e));
    }
  }

  // ---------------------------------------------------------------------------
  // CE QUE DÉTIENNENT LES CLIENTS
  // ---------------------------------------------------------------------------

  Future<SoldeRecipients> soldeClient(String clientId) async {
    try {
      final dynamic reponse = await _client
          .rpc('rpc_recipients_solde_client', params: <String, dynamic>{
        'p_client_id': clientId,
      }).timeout(const Duration(seconds: 15));
      return SoldeRecipients.fromMap(parseMap(reponse));
    } catch (e) {
      throw RecipientsException(_lisible(e));
    }
  }

  Future<TableauBordRecipients> tableauBord() async {
    try {
      final dynamic reponse = await _client
          .rpc('rpc_recipients_tableau_bord')
          .timeout(const Duration(seconds: 15));
      return TableauBordRecipients.fromMap(parseMap(reponse));
    } catch (e) {
      throw RecipientsException(_lisible(e));
    }
  }

  // ---------------------------------------------------------------------------
  // BONUS
  // ---------------------------------------------------------------------------

  Future<List<RegleBonus>> regles() async {
    try {
      final dynamic reponse = await _client
          .rpc('rpc_regles_bonus_lister')
          .timeout(const Duration(seconds: 15));
      return parseMapList(reponse).map(RegleBonus.fromMap).toList(growable: false);
    } catch (e) {
      throw RecipientsException(_lisible(e));
    }
  }

  Future<String> enregistrerRegle({
    String? id,
    required String libelle,
    String? produitId,
    String typeDeclencheur = 'farde',
    int quantiteDeclencheur = 5,
    String typeOffert = 'farde',
    int quantiteOfferte = 1,
    bool actif = true,
  }) async {
    try {
      final dynamic reponse = await _client
          .rpc('rpc_bonus_regle_enregistrer', params: <String, dynamic>{
        'p_id': id,
        'p_libelle': libelle,
        'p_produit_id': produitId,
        'p_type_declencheur': typeDeclencheur,
        'p_quantite_declencheur': quantiteDeclencheur,
        'p_type_offert': typeOffert,
        'p_quantite_offerte': quantiteOfferte,
        'p_actif': actif,
      }).timeout(const Duration(seconds: 15));
      return (reponse ?? '').toString();
    } catch (e) {
      throw RecipientsException(_lisible(e));
    }
  }

  /// Applique les règles actives et renvoie la quantité offerte.
  /// Idempotent côté serveur (client + règle + tournée).
  Future<int> appliquerBonus({
    required String produitId,
    required int quantiteAchetee,
    String? clientId,
    String? clientNom,
    String? tourneeId,
  }) async {
    try {
      final dynamic reponse = await _client
          .rpc('rpc_bonus_appliquer', params: <String, dynamic>{
        'p_produit_id': produitId,
        'p_quantite_achetee': quantiteAchetee,
        'p_client_id': clientId,
        'p_client_nom': clientNom,
        'p_tournee_id': tourneeId,
      }).timeout(const Duration(seconds: 20));
      final Map<String, dynamic>? m = parseMap(reponse);
      return parseInt(m?['quantite_offerte']);
    } catch (e) {
      throw RecipientsException(_lisible(e));
    }
  }
}
