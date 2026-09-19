// lib/services/salle_fete_service.dart
//
// 🎉 MODULE 16 (phase C4) — SALLE DES FÊTES : SALLES & ÉVÉNEMENTS.
//
//   • `public.salles` / `public.evenements` / `public.lignes_evenement`
//     — lecture (RLS boutique) ;
//   • `rpc_salle_enregistrer`          — créer / modifier une salle ;
//   • `rpc_evenement_enregistrer`      — créer / modifier un événement
//     (chevauchement refusé, avance encaissée à la création) ;
//   • `rpc_evenement_ligne_ajouter`    — prestation (traiteur, déco…) ;
//   • `rpc_evenement_ligne_supprimer`  — retirer une prestation ;
//   • `rpc_evenement_statut`           — confirmer / en cours / terminer /
//     annuler ;
//   • `rpc_evenement_encaisser`        — avance, acompte ou solde ;
//   • `rpc_salle_fetes_tableau_bord`   — calendrier & encaissements.
//
// Toutes les méthodes publiques lèvent [SalleFeteServiceException] : les
// écrans n'ont jamais à manipuler une `PostgrestException`.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/evenement.dart';
import 'package:biashara_yangu/models/salle.dart';
import 'package:biashara_yangu/models/salle_fete_tableau_bord.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart' show reponseRpcEnMap;
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/hotel_service.dart' show ClientHotelOption;
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature d'une erreur de la salle des fêtes (pour adapter l'interface).
enum TypeErreurSalleFete { droits, validation, reseau, inconnu }

/// Erreur métier du module salle des fêtes (message déjà en français).
class SalleFeteServiceException implements Exception {
  const SalleFeteServiceException(
    this.message, {
    this.type = TypeErreurSalleFete.inconnu,
  });

  final String message;
  final TypeErreurSalleFete type;

  @override
  String toString() => message;
}

/// Accès Supabase au module salle des fêtes — singleton.
class SalleFeteService {
  SalleFeteService._();

  static final SalleFeteService instance = SalleFeteService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Modes de paiement acceptés pour les encaissements (M8).
  static const Map<String, String> modesPaiement = VenteService.modesPaiement;

  static String libelleMode(String code) => modesPaiement[code] ?? code;

  // ---------------------------------------------------------------------------
  // SESSION
  // ---------------------------------------------------------------------------

  Future<String> _requireProprietaire() async {
    final String? proprietaire =
        await ArticleService.instance.proprietaireCourant();
    if (proprietaire == null || proprietaire.isEmpty) {
      throw const SalleFeteServiceException(
        'Session introuvable : connectez-vous puis réessayez.',
        type: TypeErreurSalleFete.droits,
      );
    }
    return proprietaire;
  }

  // ---------------------------------------------------------------------------
  // SALLES
  // ---------------------------------------------------------------------------

  /// Liste les salles de la boutique, triées par nom.
  Future<List<Salle>> listerSalles({bool inclureInactives = false}) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      PostgrestFilterBuilder<PostgrestList> query =
          _client.from('salles').select('*').eq('owner_id', owner);
      if (!inclureInactives) {
        query = query.eq('actif', true);
      }
      data = await query.order('nom', ascending: true);
    } on PostgrestException catch (e) {
      debugPrint(
          'SalleFeteService (salles) PostgrestException: ${e.code} ${e.message}');
      throw SalleFeteServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('SalleFeteService (salles): $e\n$st');
      throw const SalleFeteServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurSalleFete.reseau,
      );
    }

    return parseMapList(data).map(Salle.fromMap).toList(growable: false);
  }

  /// Crée ([id] nul) ou modifie une salle.
  Future<Salle> enregistrerSalle({
    String? id,
    required String nom,
    int capacite = 50,
    double prixJour = 0,
    String? description,
    String? equipements,
    bool actif = true,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_salle_enregistrer',
      params: <String, dynamic>{
        'p_id': id,
        'p_nom': nom,
        'p_capacite': capacite,
        'p_prix_jour': prixJour,
        'p_description': description,
        'p_equipements': equipements,
        'p_actif': actif,
      },
      actionLibelle: "l'enregistrement de la salle",
    );

    final Map<String, dynamic>? salle = parseMap(map?['salle']);
    if (salle == null) {
      throw const SalleFeteServiceException(
        "Réponse inattendue du serveur : la salle n'est pas confirmée.",
      );
    }
    return Salle.fromMap(salle);
  }

  /// Supprime une salle (refusé si des événements la référencent :
  /// la désactiver à la place).
  Future<void> supprimerSalle(String id) async {
    await _requireProprietaire();
    try {
      await _client.from('salles').delete().eq('id', id);
    } on PostgrestException catch (e) {
      debugPrint(
          'SalleFeteService (suppression salle) PostgrestException: ${e.code} ${e.message}');
      if (e.code == '23503') {
        throw const SalleFeteServiceException(
          'Des événements existent pour cette salle : désactivez-la au lieu de la supprimer.',
          type: TypeErreurSalleFete.validation,
        );
      }
      throw SalleFeteServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('SalleFeteService (suppression salle): $e\n$st');
      throw const SalleFeteServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurSalleFete.reseau,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // ÉVÉNEMENTS
  // ---------------------------------------------------------------------------

  /// Liste les événements de la boutique.
  ///
  /// [depuis] / [jusquA] filtrent la période (date de DÉBUT de l'événement) ;
  /// [statuts] filtre les statuts (vide = tous).
  Future<List<Evenement>> listerEvenements({
    DateTime? depuis,
    DateTime? jusquA,
    Set<StatutEvenement> statuts = const <StatutEvenement>{},
    int limit = 300,
  }) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      PostgrestFilterBuilder<PostgrestList> query = _client
          .from('evenements')
          .select('*, salles(nom), lignes_evenement(id, libelle, quantite, '
              'prix_unitaire, total)')
          .eq('owner_id', owner);

      if (depuis != null) {
        query = query.gte('date_debut', _dateSeule(depuis));
      }
      if (jusquA != null) {
        query = query.lte('date_debut', _dateSeule(jusquA));
      }
      if (statuts.isNotEmpty) {
        query = query.inFilter(
          'statut',
          statuts.map((StatutEvenement s) => s.code).toList(growable: false),
        );
      }

      data = await query
          .order('date_debut', ascending: false)
          .limit(limit);
    } on PostgrestException catch (e) {
      debugPrint(
          'SalleFeteService (evenements) PostgrestException: ${e.code} ${e.message}');
      throw SalleFeteServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('SalleFeteService (evenements): $e\n$st');
      throw const SalleFeteServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurSalleFete.reseau,
      );
    }

    return parseMapList(data).map(Evenement.fromMap).toList(growable: false);
  }

  /// Recharge UN événement avec sa salle et ses prestations.
  Future<Evenement?> chargerEvenement(String id) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      data = await _client
          .from('evenements')
          .select('*, salles(nom), lignes_evenement(id, libelle, quantite, '
              'prix_unitaire, total)')
          .eq('owner_id', owner)
          .eq('id', id)
          .limit(1);
    } on PostgrestException catch (e) {
      debugPrint(
          'SalleFeteService (chargerEvenement) PostgrestException: ${e.code} ${e.message}');
      throw SalleFeteServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('SalleFeteService (chargerEvenement): $e\n$st');
      throw const SalleFeteServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurSalleFete.reseau,
      );
    }

    final List<Map<String, dynamic>> lignes = parseMapList(data);
    if (lignes.isEmpty) return null;
    return Evenement.fromMap(lignes.first);
  }

  /// Filtre une liste déjà chargée par titre, client, salle ou numéro —
  /// PUR (testable sans réseau).
  static List<Evenement> filtrer(
    List<Evenement> evenements,
    String recherche,
  ) {
    final String terme = recherche.trim().toLowerCase();
    if (terme.isEmpty) return evenements;
    return evenements
        .where((Evenement e) =>
            e.titre.toLowerCase().contains(terme) ||
            e.clientNom.toLowerCase().contains(terme) ||
            e.salleNom.toLowerCase().contains(terme) ||
            (e.numero ?? '').toLowerCase().contains(terme))
        .toList(growable: false);
  }

  /// Crée ([id] nul) ou modifie un événement. Passe par la RPC serveur qui
  /// vérifie la disponibilité de la salle et les droits.
  Future<Evenement> enregistrerEvenement({
    String? id,
    required String salleId,
    required String titre,
    String typeEvenement = '',
    int? clientId,
    required String clientNom,
    String? telephone,
    required DateTime dateDebut,
    DateTime? dateFin,
    String? heureDebut,
    String? heureFin,
    int nbInvites = 0,
    double? prixJour,
    double avance = 0,
    String? note,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_evenement_enregistrer',
      params: <String, dynamic>{
        'p_id': id,
        'p_salle_id': salleId,
        'p_titre': titre,
        'p_type_evenement': typeEvenement,
        'p_client_id': clientId,
        'p_client_nom': clientNom,
        'p_telephone': telephone,
        'p_date_debut': _dateSeule(dateDebut),
        'p_date_fin': _dateSeule(dateFin ?? dateDebut),
        'p_heure_debut': heureDebut,
        'p_heure_fin': heureFin,
        'p_nb_invites': nbInvites,
        'p_prix_jour': prixJour,
        'p_avance': avance,
        'p_note': note,
      },
      actionLibelle: "l'enregistrement de l'événement",
    );

    return _evenementReponse(map, "l'enregistrement de l'événement");
  }

  /// Ajoute une prestation (traiteur, décoration…) — s'ajoute au total.
  Future<Evenement> ajouterPrestation({
    required String evenementId,
    required String libelle,
    double quantite = 1,
    double prixUnitaire = 0,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_evenement_ligne_ajouter',
      params: <String, dynamic>{
        'p_evenement_id': evenementId,
        'p_libelle': libelle,
        'p_quantite': quantite,
        'p_prix_unitaire': prixUnitaire,
      },
      actionLibelle: "l'ajout de la prestation",
    );
    return _evenementReponse(map, "l'ajout de la prestation");
  }

  /// Retire une prestation.
  Future<Evenement> supprimerPrestation(String ligneId) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_evenement_ligne_supprimer',
      params: <String, dynamic>{'p_ligne_id': ligneId},
      actionLibelle: 'la suppression de la prestation',
    );
    return _evenementReponse(map, 'la suppression de la prestation');
  }

  /// Fait avancer l'événement (confirmer / en cours / terminer / annuler).
  Future<Evenement> changerStatut(
    String id,
    StatutEvenement statut, {
    String? motif,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_evenement_statut',
      params: <String, dynamic>{
        'p_id': id,
        'p_statut': statut.code,
        'p_motif': motif,
      },
      actionLibelle: "le changement d'étape de l'événement",
    );
    return _evenementReponse(map, "le changement d'étape de l'événement");
  }

  /// Encaisse une avance, un acompte ou le solde.
  Future<Evenement> encaisser({
    required String id,
    required double montant,
    String modePaiement = 'especes',
    String? note,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_evenement_encaisser',
      params: <String, dynamic>{
        'p_id': id,
        'p_montant': montant,
        'p_mode': modePaiement,
        'p_note': note,
      },
      actionLibelle: "l'encaissement de l'événement",
    );
    return _evenementReponse(map, "l'encaissement de l'événement");
  }

  // ---------------------------------------------------------------------------
  // TABLEAU DE BORD & CLIENTS
  // ---------------------------------------------------------------------------

  /// Calendrier & encaissements (salles, événements, soldes, prochains).
  Future<TableauBordSalleFete> tableauBord() async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_salle_fetes_tableau_bord',
      params: const <String, dynamic>{},
      actionLibelle: 'le tableau de bord des événements',
    );
    return TableauBordSalleFete.fromMap(map ?? <String, dynamic>{});
  }

  /// Clients de la boutique (formulaire d'événement), triés par nom.
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
          'SalleFeteService (clients) PostgrestException: ${e.code} ${e.message}');
      throw SalleFeteServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('SalleFeteService (clients): $e\n$st');
      throw const SalleFeteServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurSalleFete.reseau,
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

  static TypeErreurSalleFete typeDepuisMessage(String brut) {
    final String code = brut.trim().split('|').first.trim().toUpperCase();
    switch (code) {
      case 'SESSION_ABSENTE':
      case 'DROIT_REFUSE':
      case 'ACCES_REFUSE':
      case 'HORS_BOUTIQUE':
      case 'HORS_ENTREPRISE':
        return TypeErreurSalleFete.droits;
      case 'NOM_OBLIGATOIRE':
      case 'NOM_INVALIDE':
      case 'NOM_EXISTE':
      case 'CAPACITE_INVALIDE':
      case 'CAPACITE_DEPASSEE':
      case 'PRIX_INVALIDE':
      case 'SALLE_INTROUVABLE':
      case 'SALLE_INACTIVE':
      case 'SALLE_OCCUPEE':
      case 'SALLE_OBLIGATOIRE':
      case 'TITRE_OBLIGATOIRE':
      case 'TITRE_INVALIDE':
      case 'DATES_OBLIGATOIRES':
      case 'DATES_INVALIDES':
      case 'INVITES_INVALIDE':
      case 'CLIENT_OBLIGATOIRE':
      case 'CLIENT_INTROUVABLE':
      case 'AVANCE_INVALIDE':
      case 'AVANCE_EXCESSIVE':
      case 'MONTANT_INVALIDE':
      case 'MONTANT_EXCEDENT':
      case 'PAIEMENTS_SUPERIEURS':
      case 'LIBELLE_OBLIGATOIRE':
      case 'LIBELLE_INVALIDE':
      case 'QUANTITE_INVALIDE':
      case 'STATUT_INVALIDE':
      case 'EVENEMENT_INTROUVABLE':
      case 'LIGNE_INTROUVABLE':
        return TypeErreurSalleFete.validation;
      default:
        return TypeErreurSalleFete.inconnu;
    }
  }

  static Evenement _evenementReponse(
    Map<String, dynamic>? map,
    String actionLibelle,
  ) {
    final Map<String, dynamic>? evenement = parseMap(map?['evenement']);
    if (evenement == null) {
      throw SalleFeteServiceException(
        "Réponse inattendue du serveur : $actionLibelle n'est pas confirmée.",
      );
    }
    // La réponse RPC ne contient pas la jointure de la salle : on garde le
    // nom fourni par les écrans via leur état local si besoin.
    return Evenement.fromMap(evenement);
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
          'SalleFeteService ($actionLibelle) PostgrestException: ${e.code} ${e.message}');
      throw SalleFeteServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('SalleFeteService ($actionLibelle): $e\n$st');
      throw const SalleFeteServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurSalleFete.reseau,
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
