// lib/services/dette_service.dart
//
// MODULE 10 — DETTES CLIENTS : lecture, création, règlements, relances.
//
//   • `rpc_dettes_liste`    — dettes + restant dû + ancienneté + résumé ;
//   • `rpc_dette_creer`     — nouvelle dette (droit `caisse/creer`) ;
//   • `rpc_dette_paiement`  — règlement partiel ou soldant (le trigger serveur
//                             recalcule `montant_paye` et le statut) ;
//   • `rpc_dette_relancer`  — message pré-rédigé + trace dans journal_audit.
//
// La liste des clients vient directement de `public.clients` (RLS : chacun
// les siens), pour alimenter le formulaire de création.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/dette_client.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart' show reponseRpcEnMap;
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature d'une erreur de dette (pour adapter l'interface).
enum TypeErreurDette { droits, validation, reseau, inconnu }

/// Erreur métier des dettes clients (message déjà en français).
class DetteServiceException implements Exception {
  const DetteServiceException(
    this.message, {
    this.type = TypeErreurDette.inconnu,
  });

  final String message;
  final TypeErreurDette type;

  @override
  String toString() => message;
}

/// Dettes clients et relances — singleton `DetteService.instance`.
class DetteService {
  DetteService._();

  static final DetteService instance = DetteService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Modes de paiement acceptés pour un règlement (mêmes codes que le M8).
  static const Map<String, String> modesPaiement = VenteService.modesPaiement;

  static String libelleMode(String code) => modesPaiement[code] ?? code;

  /// Canaux de relance acceptés par le serveur.
  static const Map<String, String> canauxRelance = <String, String>{
    'whatsapp': 'WhatsApp',
    'sms': 'SMS',
    'appel': 'Appel téléphonique',
  };

  // ---------------------------------------------------------------------------
  // CALCULS PURS (testables sans réseau)
  // ---------------------------------------------------------------------------

  /// Normalise un numéro de téléphone pour les liens `wa.me` / `tel:` :
  /// ne garde que les chiffres ; un numéro local commençant par `0` devient
  /// un numéro RDC international (`0X…` → `243X…`).
  static String numeroInternational(String telephone) {
    final String chiffres = telephone.replaceAll(RegExp(r'[^0-9]'), '');
    if (chiffres.isEmpty) return '';
    if (chiffres.startsWith('00')) return chiffres.substring(2);
    if (chiffres.startsWith('0')) return '243${chiffres.substring(1)}';
    return chiffres;
  }

  /// Lien WhatsApp « wa.me » prêt à ouvrir pour [message].
  static Uri lienWhatsApp(String telephone, String message) {
    final String numero = numeroInternational(telephone);
    return Uri.parse(
      'https://wa.me/$numero?text=${Uri.encodeComponent(message)}',
    );
  }

  /// Lien SMS pré-rempli (Android) — repli « sms: » simple sinon.
  static Uri lienSms(String telephone, String message) {
    final String numero = numeroInternational(telephone);
    final Uri base = Uri(scheme: 'sms', path: numero);
    return base.replace(queryParameters: <String, String>{'body': message});
  }

  /// Lien d'appel téléphonique.
  static Uri lienAppel(String telephone) {
    return Uri(scheme: 'tel', path: numeroInternational(telephone));
  }

  // ---------------------------------------------------------------------------
  // LECTURE
  // ---------------------------------------------------------------------------

  /// Liste les dettes (filtres : statut `non_paye` / `partiel` / `paye`,
  /// recherche sur le nom ou le téléphone du client).
  Future<ResultatListeDettes> listerDettes({
    String? statut,
    String? recherche,
    int limit = 200,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_dettes_liste',
      params: <String, dynamic>{
        if (statut != null && statut.trim().isNotEmpty) 'p_statut': statut.trim(),
        if (recherche != null && recherche.trim().isNotEmpty)
          'p_recherche': recherche.trim(),
        'p_limit': limit,
      },
      actionLibelle: 'la lecture des dettes',
    );

    return ResultatListeDettes.depuisRpc(map ?? <String, dynamic>{});
  }

  /// Clients de la boutique (formulaire « Nouvelle dette »), triés par nom.
  Future<List<ClientDetteOption>> listerClients({
    String? recherche,
    int limit = 500,
  }) async {
    dynamic data;
    try {
      PostgrestFilterBuilder<PostgrestList> query = _client
          .from('clients')
          .select('id, nom, telephone');

      final String terme = (recherche ?? '').trim();
      if (terme.isNotEmpty) {
        query = query.ilike('nom', '%$terme%');
      }

      data = await query.order('nom', ascending: true).limit(limit);
    } on PostgrestException catch (e) {
      debugPrint('DetteService (clients) PostgrestException: ${e.code} ${e.message}');
      throw DetteServiceException(
        messageErreur(e.message),
        type: _typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('DetteService (clients): $e\n$st');
      throw const DetteServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurDette.reseau,
      );
    }

    return parseMapList(data)
        .map(ClientDetteOption.depuisRpc)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // ÉCRITURES
  // ---------------------------------------------------------------------------

  /// Crée une dette pour un client (montant total > 0).
  Future<DetteClient> creerDette({
    required int clientId,
    required double montantTotal,
    String? venteUuid,
    DateTime? dateEcheance,
  }) async {
    if (montantTotal <= 0) {
      throw const DetteServiceException(
        'Le montant de la dette doit être supérieur à zéro.',
        type: TypeErreurDette.validation,
      );
    }

    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_dette_creer',
      params: <String, dynamic>{
        'p_client_id': clientId,
        'p_montant_total': montantTotal,
        if (venteUuid != null && venteUuid.trim().isNotEmpty)
          'p_vente_uuid': venteUuid.trim(),
        if (dateEcheance != null) 'p_date_echeance': _dateSeule(dateEcheance),
      },
      actionLibelle: 'la création de la dette',
    );

    if (map == null) {
      throw const DetteServiceException(
        "Réponse inattendue du serveur : la dette n'est pas confirmée.",
      );
    }

    final double montant = parseDouble(map['montant_total']);
    final double paye = parseDouble(map['montant_paye']);
    return DetteClient(
      id: parseInt(map['dette_id']),
      clientId: parseInt(map['client_id']),
      client: parseString(map['client'], fallback: 'Client'),
      montantTotal: montant,
      montantPaye: paye,
      restant: montant - paye,
      statut: StatutDette.depuisCode(parseStringOrNull(map['statut'])),
      dateCreation: parseDateTimeOrNull(map['date_creation']),
      dateEcheance: parseDateTimeOrNull(map['date_echeance']),
    );
  }

  /// Enregistre un règlement (partiel ou soldant) d'une dette.
  ///
  /// Le serveur refuse les montants supérieurs au restant dû
  /// (`MONTANT_EXCESSIF`) ; le trigger met ensuite à jour le statut.
  Future<ResultatPaiementDette> enregistrerPaiement({
    required int detteId,
    required double montant,
    String modePaiement = 'especes',
    DateTime? datePaiement,
  }) async {
    if (montant <= 0) {
      throw const DetteServiceException(
        'Le montant du règlement doit être supérieur à zéro.',
        type: TypeErreurDette.validation,
      );
    }

    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_dette_paiement',
      params: <String, dynamic>{
        'p_dette_id': detteId,
        'p_montant': montant,
        'p_mode_paiement': modePaiement,
        if (datePaiement != null)
          'p_date_paiement': datePaiement.toUtc().toIso8601String(),
      },
      actionLibelle: "l'enregistrement du règlement",
    );

    if (map == null) {
      throw const DetteServiceException(
        "Réponse inattendue du serveur : le règlement n'est pas confirmé.",
      );
    }
    return ResultatPaiementDette.depuisRpc(map);
  }

  /// Prépare une relance client (message rédigé par le serveur) et la trace
  /// dans `journal_audit` (`RELANCE_DETTE`).
  Future<RelanceDette> relancer({
    required int detteId,
    String canal = 'whatsapp',
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_dette_relancer',
      params: <String, dynamic>{
        'p_dette_id': detteId,
        'p_canal': canal,
      },
      actionLibelle: 'la relance du client',
    );

    if (map == null) {
      throw const DetteServiceException(
        "Réponse inattendue du serveur : la relance n'est pas confirmée.",
      );
    }
    return RelanceDette.depuisRpc(map);
  }

  // ---------------------------------------------------------------------------
  // OUTILS PARTAGÉS
  // ---------------------------------------------------------------------------

  /// Extrait le message utilisateur d'une erreur du serveur.
  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  static TypeErreurDette _typeDepuisMessage(String brut) {
    final String code = brut.trim().split('|').first.trim().toUpperCase();
    switch (code) {
      case 'SESSION_ABSENTE':
      case 'ACCES_REFUSE':
      case 'DROIT_REFUSE':
      case 'HORS_ENTREPRISE':
        return TypeErreurDette.droits;
      case 'CLIENT_INTROUVABLE':
      case 'DETTE_INTROUVABLE':
      case 'MONTANT_INVALIDE':
      case 'MONTANT_EXCESSIF':
      case 'MODE_INVALIDE':
      case 'STATUT_INVALIDE':
      case 'DEJA_SOLDEE':
      case 'SANS_TELEPHONE':
      case 'CANAL_INVALIDE':
        return TypeErreurDette.validation;
      default:
        return TypeErreurDette.inconnu;
    }
  }

  /// Appelle une RPC du module et renvoie sa réponse en `Map` (ou `null`).
  Future<Map<String, dynamic>?> _appelerRpc(
    String fonction, {
    required Map<String, dynamic> params,
    required String actionLibelle,
  }) async {
    dynamic reponse;
    try {
      reponse = await _client.rpc(fonction, params: params);
    } on PostgrestException catch (e) {
      debugPrint(
          'DetteService ($actionLibelle) PostgrestException: ${e.code} ${e.message}');
      throw DetteServiceException(
        messageErreur(e.message),
        type: _typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('DetteService ($actionLibelle): $e\n$st');
      throw const DetteServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurDette.reseau,
      );
    }

    return reponseRpcEnMap(reponse);
  }

  /// `AAAA-MM-JJ` (colonne `date` : pas d'heure, pas de fuseau).
  static String _dateSeule(DateTime date) {
    final String mois = date.month.toString().padLeft(2, '0');
    final String jour = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mois-$jour';
  }
}
