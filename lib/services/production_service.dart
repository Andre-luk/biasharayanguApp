// lib/services/production_service.dart
//
// 🥖 MODULE 16 (phase C5) — BOULANGERIE : MATIÈRES & PRODUCTIONS.
//
//   • `public.matieres_premieres` / `public.productions` /
//     `public.consommations_production` — lecture (RLS boutique) ;
//   • `rpc_matiere_enregistrer`    — créer / modifier une matière ;
//   • `rpc_matiere_approvisionner` — entrée de stock (prix unitaire) ;
//   • `rpc_matiere_ajuster`        — inventaire simple (stock constaté) ;
//   • `rpc_production_creer`       — ouvrir une production (produit fini) ;
//   • `rpc_production_consommer`   — matière utilisée (déduite du stock) ;
//   • `rpc_production_consommation_supprimer` — retirer une matière ;
//   • `rpc_production_terminer`    — clôture : le produit fini entre en
//     stock (ajustement officiel) et le coût de revient est calculé ;
//   • `rpc_production_annuler`     — matières rendues au stock ;
//   • `rpc_production_tableau_bord` — dashboard du jour.
//
// Toutes les méthodes publiques lèvent [ProductionServiceException] : les
// écrans n'ont jamais à manipuler une `PostgrestException`.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/matiere_premiere.dart';
import 'package:biashara_yangu/models/production.dart';
import 'package:biashara_yangu/models/production_tableau_bord.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart' show reponseRpcEnMap;
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature d'une erreur de production (pour adapter l'interface).
enum TypeErreurProduction { droits, validation, reseau, inconnu }

/// Erreur métier du module production (message déjà en français).
class ProductionServiceException implements Exception {
  const ProductionServiceException(
    this.message, {
    this.type = TypeErreurProduction.inconnu,
  });

  final String message;
  final TypeErreurProduction type;

  @override
  String toString() => message;
}

/// Produit fini proposé dans le formulaire de production.
class ProduitFiniOption {
  const ProduitFiniOption({required this.id, required this.nom});

  final int id;
  final String nom;

  factory ProduitFiniOption.depuisRpc(Map<String, dynamic> map) {
    return ProduitFiniOption(
      id: parseInt(map['id']),
      nom: parseString(map['nom'], fallback: 'Article'),
    );
  }
}

/// Accès Supabase au module production — singleton.
class ProductionService {
  ProductionService._();

  static final ProductionService instance = ProductionService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // SESSION
  // ---------------------------------------------------------------------------

  Future<String> _requireProprietaire() async {
    final String? proprietaire =
        await ArticleService.instance.proprietaireCourant();
    if (proprietaire == null || proprietaire.isEmpty) {
      throw const ProductionServiceException(
        'Session introuvable : connectez-vous puis réessayez.',
        type: TypeErreurProduction.droits,
      );
    }
    return proprietaire;
  }

  // ---------------------------------------------------------------------------
  // MATIÈRES PREMIÈRES
  // ---------------------------------------------------------------------------

  /// Liste les matières premières de la boutique, triées par nom.
  Future<List<MatierePremiere>> listerMatieres(
      {bool inclureInactives = false}) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      PostgrestFilterBuilder<PostgrestList> query =
          _client.from('matieres_premieres').select('*').eq('owner_id', owner);
      if (!inclureInactives) {
        query = query.eq('actif', true);
      }
      data = await query.order('nom', ascending: true);
    } on PostgrestException catch (e) {
      debugPrint(
          'ProductionService (matieres) PostgrestException: ${e.code} ${e.message}');
      throw ProductionServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('ProductionService (matieres): $e\n$st');
      throw const ProductionServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurProduction.reseau,
      );
    }

    return parseMapList(data)
        .map(MatierePremiere.fromMap)
        .toList(growable: false);
  }

  /// Crée ([id] nul) ou modifie une matière première.
  Future<MatierePremiere> enregistrerMatiere({
    String? id,
    required String nom,
    String unite = 'kg',
    double seuilAlerte = 0,
    double prixUnitaire = 0,
    bool actif = true,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_matiere_enregistrer',
      params: <String, dynamic>{
        'p_id': id,
        'p_nom': nom,
        'p_unite': unite,
        'p_seuil_alerte': seuilAlerte,
        'p_prix_unitaire': prixUnitaire,
        'p_actif': actif,
      },
      actionLibelle: "l'enregistrement de la matière première",
    );
    return _matiereReponse(map, "l'enregistrement de la matière première");
  }

  /// Entrée de stock d'une matière (achat) — met à jour le prix si fourni.
  Future<MatierePremiere> approvisionnerMatiere({
    required String id,
    required double quantite,
    double? prixUnitaire,
    String? note,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_matiere_approvisionner',
      params: <String, dynamic>{
        'p_id': id,
        'p_quantite': quantite,
        'p_prix_unitaire': prixUnitaire,
        'p_note': note,
      },
      actionLibelle: "l'approvisionnement de la matière première",
    );
    return _matiereReponse(map, "l'approvisionnement de la matière première");
  }

  /// Ajuste le stock au niveau constaté (inventaire simple, motif obligatoire).
  Future<MatierePremiere> ajusterMatiere({
    required String id,
    required double stockReel,
    required String raison,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_matiere_ajuster',
      params: <String, dynamic>{
        'p_id': id,
        'p_stock_reel': stockReel,
        'p_raison': raison,
      },
      actionLibelle: "l'ajustement de la matière première",
    );
    return _matiereReponse(map, "l'ajustement de la matière première");
  }

  /// Supprime une matière (refusé si des productions l'ont consommée :
  /// la désactiver à la place).
  Future<void> supprimerMatiere(String id) async {
    await _requireProprietaire();
    try {
      await _client.from('matieres_premieres').delete().eq('id', id);
    } on PostgrestException catch (e) {
      debugPrint(
          'ProductionService (suppression matiere) PostgrestException: ${e.code} ${e.message}');
      if (e.code == '23503') {
        throw const ProductionServiceException(
          'Des productions ont consommé cette matière : désactivez-la au lieu '
          'de la supprimer.',
          type: TypeErreurProduction.validation,
        );
      }
      throw ProductionServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('ProductionService (suppression matiere): $e\n$st');
      throw const ProductionServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurProduction.reseau,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // PRODUCTIONS
  // ---------------------------------------------------------------------------

  /// Liste les productions de la boutique (jointure produit + matières).
  Future<List<Production>> listerProductions({
    Set<StatutProduction> statuts = const <StatutProduction>{},
    int limit = 300,
  }) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      PostgrestFilterBuilder<PostgrestList> query = _client
          .from('productions')
          .select('*, produits(nom), consommations_production('
              'id, matiere_id, quantite, cout_unitaire, total, '
              'matieres_premieres(nom, unite))')
          .eq('owner_id', owner);

      if (statuts.isNotEmpty) {
        query = query.inFilter(
          'statut',
          statuts.map((StatutProduction s) => s.code).toList(growable: false),
        );
      }

      data = await query.order('created_at', ascending: false).limit(limit);
    } on PostgrestException catch (e) {
      debugPrint(
          'ProductionService (productions) PostgrestException: ${e.code} ${e.message}');
      throw ProductionServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('ProductionService (productions): $e\n$st');
      throw const ProductionServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurProduction.reseau,
      );
    }

    return parseMapList(data).map(Production.fromMap).toList(growable: false);
  }

  /// Recharge UNE production avec son produit et ses matières.
  Future<Production?> chargerProduction(String id) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      data = await _client
          .from('productions')
          .select('*, produits(nom), consommations_production('
              'id, matiere_id, quantite, cout_unitaire, total, '
              'matieres_premieres(nom, unite))')
          .eq('owner_id', owner)
          .eq('id', id)
          .limit(1);
    } on PostgrestException catch (e) {
      debugPrint(
          'ProductionService (chargerProduction) PostgrestException: ${e.code} ${e.message}');
      throw ProductionServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('ProductionService (chargerProduction): $e\n$st');
      throw const ProductionServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurProduction.reseau,
      );
    }

    final List<Map<String, dynamic>> lignes = parseMapList(data);
    if (lignes.isEmpty) return null;
    return Production.fromMap(lignes.first);
  }

  /// Ouvre une production (produit fini + quantité prévue).
  Future<Production> creerProduction({
    required int produitId,
    required double quantitePrevue,
    String? note,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_production_creer',
      params: <String, dynamic>{
        'p_produit_id': produitId,
        'p_quantite_prevue': quantitePrevue,
        'p_note': note,
      },
      actionLibelle: 'la création de la production',
    );
    return _productionReponse(map, 'la création de la production');
  }

  /// Ajoute une matière consommée (déduite du stock immédiatement).
  Future<Production> consommer({
    required String productionId,
    required String matiereId,
    required double quantite,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_production_consommer',
      params: <String, dynamic>{
        'p_production_id': productionId,
        'p_matiere_id': matiereId,
        'p_quantite': quantite,
      },
      actionLibelle: "l'ajout de la matière",
    );
    return _productionReponse(map, "l'ajout de la matière");
  }

  /// Retire une matière consommée (rendue au stock).
  Future<Production> supprimerConsommation(String ligneId) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_production_consommation_supprimer',
      params: <String, dynamic>{'p_ligne_id': ligneId},
      actionLibelle: 'le retrait de la matière',
    );
    return _productionReponse(map, 'le retrait de la matière');
  }

  /// Clôture : le produit fini entre en stock, coût de revient calculé.
  Future<Production> terminer({
    required String id,
    required double quantiteReelle,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_production_terminer',
      params: <String, dynamic>{
        'p_id': id,
        'p_quantite_reelle': quantiteReelle,
      },
      actionLibelle: 'la clôture de la production',
    );
    return _productionReponse(map, 'la clôture de la production');
  }

  /// Annule une production en cours (matières rendues au stock).
  Future<Production> annuler(String id, {String? motif}) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_production_annuler',
      params: <String, dynamic>{
        'p_id': id,
        'p_motif': motif,
      },
      actionLibelle: "l'annulation de la production",
    );
    return _productionReponse(map, "l'annulation de la production");
  }

  // ---------------------------------------------------------------------------
  // TABLEAU DE BORD & PRODUITS
  // ---------------------------------------------------------------------------

  /// Dashboard de l'atelier (alertes matières, productions du jour).
  Future<TableauBordProduction> tableauBord() async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_production_tableau_bord',
      params: const <String, dynamic>{},
      actionLibelle: "le tableau de bord de l'atelier",
    );
    return TableauBordProduction.fromMap(map ?? <String, dynamic>{});
  }

  /// Produits du catalogue (choix du produit fini), triés par nom.
  Future<List<ProduitFiniOption>> listerProduits({int limit = 500}) async {
    final String owner = await _requireProprietaire();

    dynamic data;
    try {
      data = await _client
          .from('produits')
          .select('id, nom')
          .eq('owner_id', owner)
          .order('nom', ascending: true)
          .limit(limit);
    } on PostgrestException catch (e) {
      debugPrint(
          'ProductionService (produits) PostgrestException: ${e.code} ${e.message}');
      throw ProductionServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('ProductionService (produits): $e\n$st');
      throw const ProductionServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurProduction.reseau,
      );
    }

    return parseMapList(data)
        .map(ProduitFiniOption.depuisRpc)
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

  static TypeErreurProduction typeDepuisMessage(String brut) {
    final String code = brut.trim().split('|').first.trim().toUpperCase();
    switch (code) {
      case 'SESSION_ABSENTE':
      case 'DROIT_REFUSE':
      case 'ACCES_REFUSE':
      case 'HORS_BOUTIQUE':
      case 'HORS_ENTREPRISE':
        return TypeErreurProduction.droits;
      case 'NOM_OBLIGATOIRE':
      case 'NOM_INVALIDE':
      case 'NOM_EXISTE':
      case 'SEUIL_INVALIDE':
      case 'PRIX_INVALIDE':
      case 'QUANTITE_INVALIDE':
      case 'RAISON_OBLIGATOIRE':
      case 'AUCUN_ECART':
      case 'MATIERE_INTROUVABLE':
      case 'STOCK_MATIERE_INSUFFISANT':
      case 'PRODUIT_OBLIGATOIRE':
      case 'PRODUIT_INTROUVABLE':
      case 'PRODUCTION_INTROUVABLE':
      case 'STATUT_INVALIDE':
      case 'LIGNE_INTROUVABLE':
        return TypeErreurProduction.validation;
      default:
        return TypeErreurProduction.inconnu;
    }
  }

  static MatierePremiere _matiereReponse(
    Map<String, dynamic>? map,
    String actionLibelle,
  ) {
    final Map<String, dynamic>? matiere = parseMap(map?['matiere']);
    if (matiere == null) {
      throw ProductionServiceException(
        "Réponse inattendue du serveur : $actionLibelle n'est pas confirmée.",
      );
    }
    return MatierePremiere.fromMap(matiere);
  }

  static Production _productionReponse(
    Map<String, dynamic>? map,
    String actionLibelle,
  ) {
    final Map<String, dynamic>? production = parseMap(map?['production']);
    if (production == null) {
      throw ProductionServiceException(
        "Réponse inattendue du serveur : $actionLibelle n'est pas confirmée.",
      );
    }
    return Production.fromMap(production);
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
          'ProductionService ($actionLibelle) PostgrestException: ${e.code} ${e.message}');
      throw ProductionServiceException(
        messageErreur(e.message),
        type: typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('ProductionService ($actionLibelle): $e\n$st');
      throw const ProductionServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurProduction.reseau,
      );
    }

    return reponseRpcEnMap(reponse);
  }
}
