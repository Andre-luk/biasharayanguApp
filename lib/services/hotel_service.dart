// lib/services/hotel_service.dart
//
// 🧩 MODULE 16 (phase C2) — HÔTEL : CHAMBRES, RÉSERVATIONS, RÉCEPTION.
//
//   • `public.chambres` / `public.reservations` — lecture (RLS boutique) ;
//   • `rpc_chambre_enregistrer`      — créer / modifier une chambre ;
//   • `rpc_chambre_statut`           — ménage, remise en service… ;
//   • `rpc_reservation_creer`        — nouvelle réservation (avance) ;
//   • `rpc_reservation_checkin`      — arrivée du client (chambre occupée) ;
//   • `rpc_reservation_checkout`     — départ (encaissement du solde) ;
//   • `rpc_reservation_encaisser`    — avance ou acompte supplémentaire ;
//   • `rpc_reservation_annuler`      — annulation motivée ;
//   • `rpc_hotel_tableau_bord`       — occupation + arrivées/départs du jour.
//
// Toutes les méthodes publiques lèvent [HotelServiceException] : les écrans
// n'ont jamais à manipuler une `PostgrestException`.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/chambre.dart';
import 'package:biashara_yangu/models/hotel_tableau_bord.dart';
import 'package:biashara_yangu/models/reservation.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart' show reponseRpcEnMap;
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature d'une erreur d'hôtel (pour adapter l'interface).
enum TypeErreurHotel { droits, validation, reseau, inconnu }

/// Erreur métier du module hôtel (message déjà en français).
class HotelServiceException implements Exception {
  const HotelServiceException(
    this.message, {
    this.type = TypeErreurHotel.inconnu,
  });

  final String message;
  final TypeErreurHotel type;

  @override
  String toString() => message;
}

/// Client proposé dans le formulaire de réservation.
class ClientHotelOption {
  const ClientHotelOption({
    required this.id,
    required this.nom,
    this.telephone,
  });

  final int id;
  final String nom;
  final String? telephone;

  factory ClientHotelOption.depuisRpc(Map<String, dynamic> map) {
    return ClientHotelOption(
      id: parseInt(map['id']),
      nom: parseString(map['nom'], fallback: 'Client'),
      telephone: parseStringOrNull(map['telephone']),
    );
  }
}

/// Accès Supabase au module hôtel — singleton `HotelService.instance`.
class HotelService {
  HotelService._();

  static final HotelService instance = HotelService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Modes de paiement acceptés pour les encaissements de séjour (M8).
  static const Map<String, String> modesPaiement = VenteService.modesPaiement;

  static String libelleMode(String code) => modesPaiement[code] ?? code;

  // ---------------------------------------------------------------------------
  // SESSION
  // ---------------------------------------------------------------------------

  /// Patron de la boutique connectée (identique aux articles : collaborateur
  /// → son patron ; hors ligne → repli local).
  Future<String> _requireProprietaire() async {
    final String? proprietaire =
        await ArticleService.instance.proprietaireCourant();
    if (proprietaire == null || proprietaire.isEmpty) {
      throw const HotelServiceException(
        'Session introuvable : connectez-vous puis réessayez.',
        type: TypeErreurHotel.droits,
      );
    }
    return proprietaire;
  }

  // ---------------------------------------------------------------------------
  // CHAMBRES
  // ---------------------------------------------------------------------------

  /// Liste les chambres de la boutique, triées par numéro.
  Future<List<Chambre>> listerChambres({bool inclureInactives = false}) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      PostgrestFilterBuilder<PostgrestList> query =
          _client.from('chambres').select('*').eq('owner_id', owner);
      if (!inclureInactives) {
        query = query.eq('actif', true);
      }
      data = await query.order('numero', ascending: true);
    } on PostgrestException catch (e) {
      debugPrint(
          'HotelService (chambres) PostgrestException: ${e.code} ${e.message}');
      throw HotelServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('HotelService (chambres): $e\n$st');
      throw const HotelServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurHotel.reseau,
      );
    }

    return parseMapList(data)
        .map(Chambre.fromMap)
        .toList(growable: false);
  }

  /// Crée ([id] nul) ou modifie une chambre. Passe par la RPC serveur qui
  /// vérifie les droits (`chambres/creer` ou `chambres/modifier`).
  Future<Chambre> enregistrerChambre({
    String? id,
    required String numero,
    String typeChambre = '',
    int capacite = 1,
    double prixNuit = 0,
    String? equipements,
    bool actif = true,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_chambre_enregistrer',
      params: <String, dynamic>{
        'p_id': id,
        'p_numero': numero,
        'p_type_chambre': typeChambre,
        'p_capacite': capacite,
        'p_prix_nuit': prixNuit,
        'p_equipements': equipements,
        'p_actif': actif,
      },
      actionLibelle: "l'enregistrement de la chambre",
    );

    final Map<String, dynamic>? chambre = parseMap(map?['chambre']);
    if (chambre == null) {
      throw const HotelServiceException(
        "Réponse inattendue du serveur : la chambre n'est pas confirmée.",
      );
    }
    return Chambre.fromMap(chambre);
  }

  /// Change le statut d'une chambre (ménage, remise en service…).
  Future<Chambre> changerStatutChambre(String id, ChambreStatut statut) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_chambre_statut',
      params: <String, dynamic>{
        'p_id': id,
        'p_statut': statut.code,
      },
      actionLibelle: 'le changement de statut de la chambre',
    );

    final Map<String, dynamic>? chambre = parseMap(map?['chambre']);
    if (chambre == null) {
      throw const HotelServiceException(
        'Réponse inattendue du serveur : le statut n\'est pas confirmé.',
      );
    }
    return Chambre.fromMap(chambre);
  }

  /// Supprime une chambre (refusé si des réservations la référencent :
  /// la désactiver à la place).
  Future<void> supprimerChambre(String id) async {
    await _requireProprietaire();
    try {
      await _client.from('chambres').delete().eq('id', id);
    } on PostgrestException catch (e) {
      debugPrint(
          'HotelService (suppression chambre) PostgrestException: ${e.code} ${e.message}');
      if (e.code == '23503') {
        throw const HotelServiceException(
          'Des réservations existent pour cette chambre : désactivez-la '
          'plutôt que de la supprimer.',
          type: TypeErreurHotel.validation,
        );
      }
      if (e.code == '42501') {
        throw const HotelServiceException(
          'Votre rôle ne permet pas de supprimer une chambre.',
          type: TypeErreurHotel.droits,
        );
      }
      throw HotelServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('HotelService (suppression chambre): $e\n$st');
      throw const HotelServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurHotel.reseau,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // RÉSERVATIONS
  // ---------------------------------------------------------------------------

  /// Liste les séjours de la boutique, les plus récents d'abord.
  Future<List<Reservation>> listerReservations({
    StatutReservation? statut,
    int limit = 300,
  }) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      PostgrestFilterBuilder<PostgrestList> query = _client
          .from('reservations')
          .select('*, chambres(numero, type_chambre), clients(nom, telephone)')
          .eq('owner_id', owner);
      if (statut != null) {
        query = query.eq('statut', statut.code);
      }
      data = await query.order('date_arrivee', ascending: false).limit(limit);
    } on PostgrestException catch (e) {
      debugPrint(
          'HotelService (réservations) PostgrestException: ${e.code} ${e.message}');
      throw HotelServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('HotelService (réservations): $e\n$st');
      throw const HotelServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurHotel.reseau,
      );
    }

    return parseMapList(data)
        .map(Reservation.fromMap)
        .toList(growable: false);
  }

  /// Crée une réservation (avance facultative).
  Future<Reservation> creerReservation({
    required String chambreId,
    required DateTime dateArrivee,
    required DateTime dateDepart,
    int nbPersonnes = 1,
    int? clientId,
    String? clientNom,
    double? prixNuit,
    double avance = 0,
    String? note,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_reservation_creer',
      params: <String, dynamic>{
        'p_chambre_id': chambreId,
        'p_date_arrivee': _dateSeule(dateArrivee),
        'p_date_depart': _dateSeule(dateDepart),
        'p_nb_personnes': nbPersonnes,
        'p_client_id': clientId,
        'p_client_nom': clientNom,
        'p_prix_nuit': prixNuit,
        'p_avance': avance,
        'p_note': note,
      },
      actionLibelle: 'la création de la réservation',
    );

    return _reservationReponse(map, 'la création de la réservation');
  }

  /// Enregistre l'arrivée du client (check-in).
  Future<Reservation> checkin(String id) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_reservation_checkin',
      params: <String, dynamic>{'p_id': id},
      actionLibelle: "l'enregistrement de l'arrivée",
    );
    return _reservationReponse(map, "l'enregistrement de l'arrivée");
  }

  /// Enregistre le départ (check-out) et encaisse le solde réglé.
  Future<Reservation> checkout(
    String id, {
    double? montantPaye,
    String modePaiement = 'especes',
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_reservation_checkout',
      params: <String, dynamic>{
        'p_id': id,
        'p_montant_paye': montantPaye,
        'p_mode_paiement': modePaiement,
      },
      actionLibelle: "l'enregistrement du départ",
    );
    return _reservationReponse(map, "l'enregistrement du départ");
  }

  /// Encaisse une avance ou un acompte sur un séjour.
  Future<Reservation> encaisser(
    String id,
    double montant, {
    String modePaiement = 'especes',
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_reservation_encaisser',
      params: <String, dynamic>{
        'p_id': id,
        'p_montant': montant,
        'p_mode': modePaiement,
      },
      actionLibelle: "l'encaissement du séjour",
    );
    return _reservationReponse(map, "l'encaissement du séjour");
  }

  /// Annule une réservation en attente (motif facultatif).
  Future<Reservation> annuler(String id, {String? motif}) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_reservation_annuler',
      params: <String, dynamic>{
        'p_id': id,
        'p_motif': motif,
      },
      actionLibelle: "l'annulation de la réservation",
    );
    return _reservationReponse(map, "l'annulation de la réservation");
  }

  // ---------------------------------------------------------------------------
  // TABLEAU DE BORD & CLIENTS
  // ---------------------------------------------------------------------------

  /// Occupation + arrivées/départs attendus du jour.
  Future<TableauBordHotel> tableauBord() async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_hotel_tableau_bord',
      params: const <String, dynamic>{},
      actionLibelle: "le tableau de bord de l'hôtel",
    );
    return TableauBordHotel.fromMap(map ?? <String, dynamic>{});
  }

  /// Clients de la boutique (formulaire de réservation), triés par nom.
  Future<List<ClientHotelOption>> listerClients({int limit = 500}) async {
    dynamic data;
    try {
      data = await _client
          .from('clients')
          .select('id, nom, telephone')
          .order('nom', ascending: true)
          .limit(limit);
    } on PostgrestException catch (e) {
      debugPrint(
          'HotelService (clients) PostgrestException: ${e.code} ${e.message}');
      throw HotelServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('HotelService (clients): $e\n$st');
      throw const HotelServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurHotel.reseau,
      );
    }

    return parseMapList(data)
        .map(ClientHotelOption.depuisRpc)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // OUTILS PARTAGÉS
  // ---------------------------------------------------------------------------

  /// Extrait le message utilisateur d'une erreur du serveur (« CODE|texte »).
  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  static TypeErreurHotel typeDepuisMessage(String brut) {
    final String code = brut.trim().split('|').first.trim().toUpperCase();
    switch (code) {
      case 'SESSION_ABSENTE':
      case 'DROIT_REFUSE':
      case 'ACCES_REFUSE':
      case 'HORS_BOUTIQUE':
      case 'HORS_ENTREPRISE':
        return TypeErreurHotel.droits;
      case 'NUMERO_OBLIGATOIRE':
      case 'NUMERO_INVALIDE':
      case 'NUMERO_EXISTE':
      case 'CAPACITE_INVALIDE':
      case 'CAPACITE_DEPASSEE':
      case 'PRIX_INVALIDE':
      case 'CHAMBRE_INTROUVABLE':
      case 'CHAMBRE_INACTIVE':
      case 'CHAMBRE_OCCUPEE':
      case 'DATES_OBLIGATOIRES':
      case 'DATES_INVALIDES':
      case 'ARRIVEE_PASSEE':
      case 'PERSONNES_INVALIDE':
      case 'CLIENT_INTROUVABLE':
      case 'CLIENT_OBLIGATOIRE':
      case 'AVANCE_INVALIDE':
      case 'AVANCE_EXCESSIVE':
      case 'MONTANT_INVALIDE':
      case 'MONTANT_EXCEDENT':
      case 'STATUT_INVALIDE':
      case 'TROP_TOT':
      case 'RESERVATION_INTROUVABLE':
      case 'SEJOUR_EN_COURS':
      case 'AUCUNE_RESERVATION':
        return TypeErreurHotel.validation;
      default:
        return TypeErreurHotel.inconnu;
    }
  }

  static Reservation _reservationReponse(
    Map<String, dynamic>? map,
    String actionLibelle,
  ) {
    final Map<String, dynamic>? reservation = parseMap(map?['reservation']);
    if (reservation == null) {
      throw HotelServiceException(
        "Réponse inattendue du serveur : $actionLibelle n'est pas confirmée.",
      );
    }
    return Reservation.fromMap(reservation);
  }

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
          'HotelService ($actionLibelle) PostgrestException: ${e.code} ${e.message}');
      throw HotelServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('HotelService ($actionLibelle): $e\n$st');
      throw const HotelServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurHotel.reseau,
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
