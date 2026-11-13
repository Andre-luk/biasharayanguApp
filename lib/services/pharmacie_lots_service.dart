// lib/services/pharmacie_lots_service.dart
//
// MODULE 36 — LOTS DE MÉDICAMENTS (facade Dart).
//
// Ce service ne calcule RIEN : il transmet, et il explique.
//   • la réception augmente le stock PAR LE LOT (trigger serveur) ;
//   • la vente consomme les lots en FEFO (trigger serveur) ;
//   • un retrait de lot sort le stock par un ajustement tracé (RPC) ;
//   • les statuts (valide / proche / périmé / retiré) sont décidés par le
//     serveur, qui connaît la date du jour et le délai d'alerte de la
//     boutique.
//
// Toute erreur est une [PharmacieLotsException] au message français déjà
// rédigé : les écrans n'ont pas à traduire des codes PostgreSQL.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/lot_medicament.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature de l'échec, pour adapter l'affichage.
enum TypeErreurLots {
  nonDeploye,
  droits,
  session,
  validation,
  stock,
  reseau,
  inconnu,
}

class PharmacieLotsException implements Exception {
  const PharmacieLotsException(
    this.message, {
    this.code,
    this.type = TypeErreurLots.inconnu,
  });

  final String message;
  final String? code;
  final TypeErreurLots type;

  @override
  String toString() => message;
}

class PharmacieLotsService {
  PharmacieLotsService._();

  static final PharmacieLotsService instance = PharmacieLotsService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // LECTURE
  // ---------------------------------------------------------------------------

  /// Lots d'un article, triés FEFO, avec les totaux de stock.
  Future<DossierLots> lister(int produitId, {int joursAlarme = 30}) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_lots_lister',
          params: <String, dynamic>{
            'p_produit_id': produitId,
            'p_jours_alarme': joursAlarme,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const PharmacieLotsException(
            'Le serveur a renvoyé une réponse inattendue.',
          );
        }

        final DossierLots dossier = DossierLots.fromRpc(map);
        return DossierLots(
          produitId: dossier.produitId,
          produit: dossier.produit,
          stock: dossier.stock,
          stockLots: dossier.stockLots,
          stockVendable: dossier.stockVendable,
          dateExpiration: dossier.dateExpiration,
          joursAlarme: joursAlarme,
          lots: dossier.lots,
        );
      },
      actionLibelle: 'le chargement des lots',
      messageEchec:
          'Impossible de charger les lots. Vérifiez votre connexion internet.',
    );
  }

  // ---------------------------------------------------------------------------
  // ÉCRITURE
  // ---------------------------------------------------------------------------

  /// Enregistre une RÉCEPTION (nouveau lot). Le stock de l'article augmente
  /// de [quantite] — jamais deux fois : c'est le trigger du lot qui l'ajoute.
  Future<ResultatReceptionLot> recevoir({
    required int produitId,
    required String numeroLot,
    required DateTime datePeremption,
    required double quantite,
    double? prixAchatUnitaire,
    String? fournisseur,
    DateTime? dateFabrication,
    String? observations,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_lot_recevoir',
          params: <String, dynamic>{
            'p_produit_id': produitId,
            'p_numero_lot': numeroLot.trim(),
            'p_date_peremption': _dateSeule(datePeremption),
            'p_quantite': quantite,
            'p_prix_achat_unitaire': prixAchatUnitaire,
            'p_fournisseur': _texteOuNull(fournisseur),
            'p_date_fabrication':
                dateFabrication == null ? null : _dateSeule(dateFabrication),
            'p_observations': _texteOuNull(observations),
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const PharmacieLotsException(
            'Le lot a peut-être été enregistré : rechargez la fiche avant de réessayer.',
            type: TypeErreurLots.inconnu,
          );
        }

        return ResultatReceptionLot.depuisRpc(map);
      },
      actionLibelle: 'l\'enregistrement du lot',
      messageEchec:
          "Impossible d'enregistrer ce lot. Vérifiez votre connexion internet.",
    );
  }

  /// Retire un lot du stock (casse, rappel, péremption).
  ///
  /// Le motif est OBLIGATOIRE : un retrait sans raison est un stock qui
  /// disparaît sans explication.
  Future<ResultatRetraitLot> retirer({
    required String lotId,
    required String motif,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_lot_retirer',
          params: <String, dynamic>{
            'p_lot_id': lotId,
            'p_motif': motif.trim(),
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const PharmacieLotsException(
            'Le retrait a peut-être été enregistré : rechargez la fiche avant de réessayer.',
          );
        }

        return ResultatRetraitLot.depuisRpc(map);
      },
      actionLibelle: 'le retrait du lot',
      messageEchec:
          'Impossible de retirer ce lot. Vérifiez votre connexion internet.',
    );
  }

  // ---------------------------------------------------------------------------
  // OUTILS
  // ---------------------------------------------------------------------------

  static String _dateSeule(DateTime date) {
    final String mois = date.month.toString().padLeft(2, '0');
    final String jour = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mois-$jour';
  }

  static String? _texteOuNull(String? valeur) {
    final String texte = (valeur ?? '').trim();
    return texte.isEmpty ? null : texte;
  }

  /// Message utilisateur d'une erreur préfixée `CODE|texte`.
  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  /// Type d'erreur déduit du code serveur.
  static TypeErreurLots typeDepuisMessage(String message) {
    final String code = message.split('|').first.trim().toUpperCase();
    switch (code) {
      case 'DROIT_REFUSE':
      case 'HORS_BOUTIQUE':
        return TypeErreurLots.droits;
      case 'SESSION_ABSENTE':
        return TypeErreurLots.session;
      case 'QUANTITE_INVALIDE':
      case 'LOT_OBLIGATOIRE':
      case 'LOT_DOUBLON':
      case 'PEREMPTION_OBLIGATOIRE':
      case 'PEREMPTION_PASSEE':
      case 'DATES_INCOHERENTES':
      case 'QUANTITE_INCOHERENTE':
      case 'MOTIF_OBLIGATOIRE':
      case 'LOT_DATE_IMMUABLE':
      case 'LOT_QUANTITE_IMMUABLE':
        return TypeErreurLots.validation;
      case 'LOT_INTROUVABLE':
      case 'LOT_DEJA_RETIRE':
      case 'ARTICLE_INTROUVABLE':
        return TypeErreurLots.stock;
      default:
        return TypeErreurLots.inconnu;
    }
  }

  Future<T> _executer<T>(
    Future<T> Function() action, {
    required String actionLibelle,
    required String messageEchec,
  }) async {
    try {
      return await action();
    } on PharmacieLotsException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('PharmacieLotsService ($actionLibelle) : ${e.code} ${e.message}');

      // Fonction absente : la migration 0163 n'est pas exécutée.
      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const PharmacieLotsException(
          'La gestion des lots n\'est pas encore installée sur la base. '
          'Exécutez la migration '
          'supabase/migrations/20260916000163_module36_lots_pharmacie.sql '
          'puis réessayez.',
          code: 'NON_DEPLOYE',
          type: TypeErreurLots.nonDeploye,
        );
      }

      final String message = messageErreur(e.message);
      throw PharmacieLotsException(
        message,
        code: e.message.split('|').first.trim().toUpperCase(),
        type: typeDepuisMessage(message),
      );
    } catch (e, st) {
      debugPrint('PharmacieLotsService ($actionLibelle) : $e\n$st');
      throw PharmacieLotsException(messageEchec);
    }
  }
}
