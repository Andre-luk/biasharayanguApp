// lib/services/restaurant_service.dart
//
// 🍽️ MODULE 16 (phase C3) — RESTAURANT : TABLES, COMMANDES, CUISINE.
//
//   • `public.tables_salle` — lecture (RLS boutique) ;
//   • `public.commandes` / `public.lignes_commande` — lecture avec jointures
//     (`tables_salle(numero)`, `lignes_commande(*)`) ;
//   • RPC : table (enregistrer / statut), commande (créer, lignes, envoyer,
//     avancer, annuler) et ENCAISSEMENT via la caisse existante
//     (`rpc_commande_encaisser` rejoue la vente réelle du Module 8 :
//     stock, reçu, journal).
//
// Toutes les méthodes publiques lèvent [RestaurantServiceException].

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/commande.dart';
import 'package:biashara_yangu/models/restaurant_tableau_bord.dart';
import 'package:biashara_yangu/models/table_salle.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart' show reponseRpcEnMap;
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature d'une erreur de restaurant (pour adapter l'interface).
enum TypeErreurRestaurant { droits, validation, reseau, inconnu }

/// Erreur métier du module restaurant (message déjà en français).
class RestaurantServiceException implements Exception {
  const RestaurantServiceException(
    this.message, {
    this.type = TypeErreurRestaurant.inconnu,
  });

  final String message;
  final TypeErreurRestaurant type;

  @override
  String toString() => message;
}

/// Article proposé à la commande (catalogue).
class ProduitRestaurantOption {
  const ProduitRestaurantOption({
    required this.id,
    required this.nom,
    this.prixVente = 0,
    this.quantite = 0,
    this.uniteMesure = 'unité',
  });

  final int id;
  final String nom;
  final double prixVente;
  final double quantite;
  final String uniteMesure;

  factory ProduitRestaurantOption.depuisRpc(Map<String, dynamic> map) {
    return ProduitRestaurantOption(
      id: parseInt(map['id']),
      nom: parseString(map['nom'], fallback: 'Article'),
      prixVente: parseDouble(map['prix_vente']),
      quantite: parseDouble(map['quantite']),
      uniteMesure: parseString(map['unite_mesure'], fallback: 'unité'),
    );
  }
}

/// Accès Supabase au module restaurant — singleton `RestaurantService.instance`.
class RestaurantService {
  RestaurantService._();

  static final RestaurantService instance = RestaurantService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Modes de paiement acceptés (même liste que la caisse).
  static const Map<String, String> modesPaiement = VenteService.modesPaiement;

  static String libelleMode(String code) => modesPaiement[code] ?? code;

  // ---------------------------------------------------------------------------
  // SESSION
  // ---------------------------------------------------------------------------

  Future<String> _requireProprietaire() async {
    final String? proprietaire =
        await ArticleService.instance.proprietaireCourant();
    if (proprietaire == null || proprietaire.isEmpty) {
      throw const RestaurantServiceException(
        'Session introuvable : connectez-vous puis réessayez.',
        type: TypeErreurRestaurant.droits,
      );
    }
    return proprietaire;
  }

  // ---------------------------------------------------------------------------
  // TABLES
  // ---------------------------------------------------------------------------

  /// Liste les tables de la salle, triées par numéro.
  Future<List<TableSalle>> listerTables({bool inclureInactives = false}) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      PostgrestFilterBuilder<PostgrestList> query =
          _client.from('tables_salle').select('*').eq('owner_id', owner);
      if (!inclureInactives) {
        query = query.eq('actif', true);
      }
      data = await query.order('numero', ascending: true);
    } on PostgrestException catch (e) {
      debugPrint(
          'RestaurantService (tables) PostgrestException: ${e.code} ${e.message}');
      throw RestaurantServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('RestaurantService (tables): $e\n$st');
      throw const RestaurantServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurRestaurant.reseau,
      );
    }

    return parseMapList(data).map(TableSalle.fromMap).toList(growable: false);
  }

  /// Crée ([id] nul) ou modifie une table.
  Future<TableSalle> enregistrerTable({
    String? id,
    required String numero,
    String zone = '',
    int places = 2,
    bool actif = true,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_table_enregistrer',
      params: <String, dynamic>{
        'p_id': id,
        'p_numero': numero,
        'p_zone': zone,
        'p_places': places,
        'p_actif': actif,
      },
      actionLibelle: "l'enregistrement de la table",
    );

    final Map<String, dynamic>? table = parseMap(map?['table']);
    if (table == null) {
      throw const RestaurantServiceException(
        "Réponse inattendue du serveur : la table n'est pas confirmée.",
      );
    }
    return TableSalle.fromMap(table);
  }

  /// Change le statut d'une table (réservation, libération).
  Future<TableSalle> changerStatutTable(String id, TableStatut statut) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_table_statut',
      params: <String, dynamic>{
        'p_id': id,
        'p_statut': statut.code,
      },
      actionLibelle: 'le changement de statut de la table',
    );

    final Map<String, dynamic>? table = parseMap(map?['table']);
    if (table == null) {
      throw const RestaurantServiceException(
        'Réponse inattendue du serveur : le statut n\'est pas confirmé.',
      );
    }
    return TableSalle.fromMap(table);
  }

  /// Supprime une table (refusé si des commandes la référencent).
  Future<void> supprimerTable(String id) async {
    await _requireProprietaire();
    try {
      await _client.from('tables_salle').delete().eq('id', id);
    } on PostgrestException catch (e) {
      debugPrint(
          'RestaurantService (suppression table) PostgrestException: ${e.code} ${e.message}');
      if (e.code == '23503') {
        throw const RestaurantServiceException(
          'Des commandes existent pour cette table : désactivez-la plutôt '
          'que de la supprimer.',
          type: TypeErreurRestaurant.validation,
        );
      }
      if (e.code == '42501') {
        throw const RestaurantServiceException(
          'Votre rôle ne permet pas de supprimer une table.',
          type: TypeErreurRestaurant.droits,
        );
      }
      throw RestaurantServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('RestaurantService (suppression table): $e\n$st');
      throw const RestaurantServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurRestaurant.reseau,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // COMMANDES
  // ---------------------------------------------------------------------------

  /// Liste les commandes (avec table et lignes), les plus récentes d'abord.
  Future<List<Commande>> listerCommandes({
    StatutCommande? statut,
    bool activesSeulement = false,
    int limit = 300,
  }) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      PostgrestFilterBuilder<PostgrestList> query = _client
          .from('commandes')
          .select('*, tables_salle(numero, zone), lignes_commande(*)')
          .eq('owner_id', owner);
      if (statut != null) {
        query = query.eq('statut', statut.code);
      }
      data = await query.order('created_at', ascending: false).limit(limit);
    } on PostgrestException catch (e) {
      debugPrint(
          'RestaurantService (commandes) PostgrestException: ${e.code} ${e.message}');
      throw RestaurantServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('RestaurantService (commandes): $e\n$st');
      throw const RestaurantServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurRestaurant.reseau,
      );
    }

    List<Commande> commandes =
        parseMapList(data).map(Commande.fromMap).toList(growable: false);
    if (activesSeulement) {
      commandes = commandes
          .where((Commande c) => c.statut.estActive)
          .toList(growable: false);
    }
    return commandes;
  }

  /// Recharge une commande complète (table + lignes).
  Future<Commande> chargerCommande(String id) async {
    dynamic data;
    try {
      data = await _client
          .from('commandes')
          .select('*, tables_salle(numero, zone), lignes_commande(*)')
          .eq('id', id)
          .maybeSingle();
    } on PostgrestException catch (e) {
      debugPrint(
          'RestaurantService (charger commande) PostgrestException: ${e.code} ${e.message}');
      throw RestaurantServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('RestaurantService (charger commande): $e\n$st');
      throw const RestaurantServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurRestaurant.reseau,
      );
    }

    final Map<String, dynamic>? map = parseMap(data);
    if (map == null) {
      throw const RestaurantServiceException(
        'Commande introuvable : elle a peut-être été supprimée.',
        type: TypeErreurRestaurant.validation,
      );
    }
    return Commande.fromMap(map);
  }

  /// Ouvre une commande sur une table.
  Future<Commande> creerCommande({
    required String tableId,
    String? clientNom,
    int nbPersonnes = 1,
    String? note,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_commande_creer',
      params: <String, dynamic>{
        'p_table_id': tableId,
        'p_client_nom': clientNom,
        'p_nb_personnes': nbPersonnes,
        'p_note': note,
      },
      actionLibelle: "l'ouverture de la commande",
    );
    return _commandeReponse(map, "l'ouverture de la commande");
  }

  /// Ajoute un article (du catalogue) à une commande.
  Future<Commande> ajouterLigne({
    required String commandeId,
    required int produitId,
    double quantite = 1,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_commande_ligne_ajouter',
      params: <String, dynamic>{
        'p_commande_id': commandeId,
        'p_produit_id': produitId,
        'p_quantite': quantite,
      },
      actionLibelle: "l'ajout de l'article",
    );

    final Map<String, dynamic>? commande = parseMap(map?['commande']);
    if (commande == null) {
      throw const RestaurantServiceException(
        "Réponse inattendue du serveur : l'article n'est pas confirmé.",
      );
    }
    return Commande.fromMap(commande);
  }

  /// Retire un article d'une commande en saisie.
  Future<Commande> supprimerLigne(String ligneId) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_commande_ligne_supprimer',
      params: <String, dynamic>{'p_ligne_id': ligneId},
      actionLibelle: "le retrait de l'article",
    );

    final Map<String, dynamic>? commande = parseMap(map?['commande']);
    if (commande == null) {
      throw const RestaurantServiceException(
        'Réponse inattendue du serveur : le retrait n\'est pas confirmé.',
      );
    }
    return Commande.fromMap(commande);
  }

  /// Envoie la commande en cuisine.
  Future<Commande> envoyer(String id) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_commande_envoyer',
      params: <String, dynamic>{'p_id': id},
      actionLibelle: "l'envoi en cuisine",
    );
    return _commandeReponse(map, "l'envoi en cuisine");
  }

  /// Fait avancer la commande (« en_preparation », « prete » ou « servie »).
  Future<Commande> avancer(String id, StatutCommande etape) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_commande_avancer',
      params: <String, dynamic>{
        'p_id': id,
        'p_statut': etape.code,
      },
      actionLibelle: 'la mise à jour de la commande',
    );
    return _commandeReponse(map, 'la mise à jour de la commande');
  }

  /// Annule une commande (motif facultatif).
  Future<Commande> annuler(String id, {String? motif}) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_commande_annuler',
      params: <String, dynamic>{
        'p_id': id,
        'p_motif': motif,
      },
      actionLibelle: "l'annulation de la commande",
    );
    return _commandeReponse(map, "l'annulation de la commande");
  }

  /// Encaisse la commande via la caisse existante (vente réelle, stock,
  /// reçu, journal). Renvoie la commande mise à jour.
  Future<Commande> encaisser(
    String id, {
    String modePaiement = 'especes',
    double? montantRecu,
    String? numeroTransaction,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_commande_encaisser',
      params: <String, dynamic>{
        'p_id': id,
        'p_mode_paiement': modePaiement,
        'p_montant_recu': montantRecu,
        'p_numero_transaction': numeroTransaction,
      },
      actionLibelle: "l'encaissement de la commande",
    );
    return _commandeReponse(map, "l'encaissement de la commande");
  }

  // ---------------------------------------------------------------------------
  // TABLEAU DE BORD & CATALOGUE
  // ---------------------------------------------------------------------------

  /// Occupation des tables + état des commandes.
  Future<RestaurantTableauBord> tableauBord() async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_restaurant_tableau_bord',
      params: const <String, dynamic>{},
      actionLibelle: 'le tableau de bord du restaurant',
    );
    return RestaurantTableauBord.fromMap(map ?? <String, dynamic>{});
  }

  /// Catalogue (articles) proposé à la commande.
  Future<List<ProduitRestaurantOption>> listerProduits({
    String? recherche,
    int limit = 500,
  }) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      PostgrestFilterBuilder<PostgrestList> query = _client
          .from('produits')
          .select('id, nom, prix_vente, quantite, unite_mesure')
          .eq('owner_id', owner);
      final String terme = (recherche ?? '').trim();
      if (terme.isNotEmpty) {
        query = query.ilike('nom', '%$terme%');
      }
      data = await query.order('nom', ascending: true).limit(limit);
    } on PostgrestException catch (e) {
      debugPrint(
          'RestaurantService (produits) PostgrestException: ${e.code} ${e.message}');
      throw RestaurantServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('RestaurantService (produits): $e\n$st');
      throw const RestaurantServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurRestaurant.reseau,
      );
    }

    return parseMapList(data)
        .map(ProduitRestaurantOption.depuisRpc)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // OUTILS PARTAGÉS
  // ---------------------------------------------------------------------------

  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  static TypeErreurRestaurant typeDepuisMessage(String brut) {
    final String code = brut.trim().split('|').first.trim().toUpperCase();
    switch (code) {
      case 'SESSION_ABSENTE':
      case 'DROIT_REFUSE':
      case 'ACCES_REFUSE':
      case 'HORS_BOUTIQUE':
      case 'HORS_ENTREPRISE':
        return TypeErreurRestaurant.droits;
      case 'NUMERO_OBLIGATOIRE':
      case 'NUMERO_INVALIDE':
      case 'NUMERO_EXISTE':
      case 'PLACES_INVALIDES':
      case 'TABLE_INTROUVABLE':
      case 'TABLE_INACTIVE':
      case 'TABLE_OCCUPEE':
      case 'TABLE_OBLIGATOIRE':
      case 'COMMANDE_EN_COURS':
      case 'COMMANDE_INTROUVABLE':
      case 'COMMANDE_VIDE':
      case 'STATUT_INVALIDE':
      case 'LIGNE_INTROUVABLE':
      case 'QUANTITE_INVALIDE':
      case 'PRODUIT_OBLIGATOIRE':
      case 'PRODUIT_INTROUVABLE':
      case 'MONTANT_INVALIDE':
      case 'MONTANT_INSUFFISANT':
      case 'STOCK_INSUFFISANT':
      case 'PRODUIT_EXPIRE':
      case 'PANIER_VIDE':
        return TypeErreurRestaurant.validation;
      default:
        return TypeErreurRestaurant.inconnu;
    }
  }

  static Commande _commandeReponse(
    Map<String, dynamic>? map,
    String actionLibelle,
  ) {
    final Map<String, dynamic>? commande = parseMap(map?['commande']);
    if (commande == null) {
      throw RestaurantServiceException(
        "Réponse inattendue du serveur : $actionLibelle n'est pas confirmée.",
      );
    }
    return Commande.fromMap(commande);
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
          'RestaurantService ($actionLibelle) PostgrestException: ${e.code} ${e.message}');
      throw RestaurantServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('RestaurantService ($actionLibelle): $e\n$st');
      throw const RestaurantServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurRestaurant.reseau,
      );
    }

    return reponseRpcEnMap(reponse);
  }
}
