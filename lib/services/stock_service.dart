// lib/services/stock_service.dart
//
// MODULE 9 — GESTION DU STOCK (conversions multi-unités).
//
// Toutes les ÉCRITURES passent par les transactions serveur de la migration
// `20260916000010_module9_stock.sql` :
//
//   • `rpc_stock_definir_seuil`   — seuil d'alerte d'un article ;
//   • `rpc_stock_approvisionner`  — ENTRÉE (approvisionnement fournisseur) ;
//   • `rpc_stock_ajuster`         — AJUSTEMENT (raison obligatoire) ;
//   • `rpc_inventaire_cloturer`   — CLÔTURE quotidienne (comptages + écarts).
//
// Rappels de conception :
//   • le STOCK vit dans `produits.quantite` (unités de base) ; les
//     conditionnements ne sont que des facteurs de conversion — c'est
//     l'application qui convertit AVANT l'appel (10 fardes de 12 → 120) ;
//   • les triggers serveur appliquent les mouvements (vérifié par sonde) :
//     les RPC n'écrivent JAMAIS `produits.quantite` directement ;
//   • chaque opération est journalisée dans `journal_audit` côté serveur.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/inventaire_ligne.dart';
import 'package:biashara_yangu/models/mouvement_article.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart' show reponseRpcEnMap;
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature d'une erreur de stock (pour adapter l'interface).
enum TypeErreurStock { droits, validation, reseau, inconnu }

/// Erreur métier du module Stock (message déjà rédigé en français).
class StockServiceException implements Exception {
  const StockServiceException(
    this.message, {
    this.type = TypeErreurStock.inconnu,
  });

  final String message;
  final TypeErreurStock type;

  @override
  String toString() => message;
}

/// Récapitulatif d'une entrée de stock (`rpc_stock_approvisionner`).
class ResultatApprovisionnement {
  const ResultatApprovisionnement({
    required this.produitId,
    required this.nom,
    required this.quantiteAjoutee,
    required this.prixAchatUnitaire,
    required this.stockAvant,
    required this.stockApres,
    this.fournisseur,
    this.date,
  });

  final int produitId;
  final String nom;
  final double quantiteAjoutee;
  final double prixAchatUnitaire;
  final double stockAvant;
  final double stockApres;
  final String? fournisseur;
  final DateTime? date;

  factory ResultatApprovisionnement.depuisRpc(Map<String, dynamic> map) {
    return ResultatApprovisionnement(
      produitId: parseInt(map['produit_id']),
      nom: parseString(map['nom']),
      quantiteAjoutee: parseDouble(map['quantite_ajoutee']),
      prixAchatUnitaire: parseDouble(map['prix_achat_unitaire']),
      stockAvant: parseDouble(map['stock_avant']),
      stockApres: parseDouble(map['stock_apres']),
      fournisseur: parseStringOrNull(map['fournisseur']),
      date: parseDateTimeOrNull(map['date']),
    );
  }
}

/// Récapitulatif d'un ajustement (`rpc_stock_ajuster`).
class ResultatAjustement {
  const ResultatAjustement({
    required this.produitId,
    required this.nom,
    required this.delta,
    required this.raison,
    required this.stockAvant,
    required this.stockApres,
  });

  final int produitId;
  final String nom;
  final double delta;
  final String raison;
  final double stockAvant;
  final double stockApres;

  factory ResultatAjustement.depuisRpc(Map<String, dynamic> map) {
    return ResultatAjustement(
      produitId: parseInt(map['produit_id']),
      nom: parseString(map['nom']),
      delta: parseDouble(map['delta']),
      raison: parseString(map['raison']),
      stockAvant: parseDouble(map['stock_avant']),
      stockApres: parseDouble(map['stock_apres']),
    );
  }
}

/// Une ligne du récapitulatif de clôture d'inventaire.
class LigneResultatInventaire {
  const LigneResultatInventaire({
    required this.produitId,
    required this.nom,
    required this.unite,
    required this.theorique,
    required this.physique,
    required this.ecart,
    required this.ajuste,
  });

  final int produitId;
  final String nom;
  final String unite;
  final double theorique;
  final double physique;
  final double ecart;

  /// `true` si l'écart a été corrigé par un ajustement.
  final bool ajuste;

  factory LigneResultatInventaire.depuisRpc(Map<String, dynamic> map) {
    return LigneResultatInventaire(
      produitId: parseInt(map['produit_id']),
      nom: parseString(map['nom']),
      unite: parseString(map['unite']),
      theorique: parseDouble(map['theorique']),
      physique: parseDouble(map['physique']),
      ecart: parseDouble(map['ecart']),
      ajuste: map['ajuste'] == true,
    );
  }
}

/// Récapitulatif d'une clôture d'inventaire (`rpc_inventaire_cloturer`).
class ResultatInventaire {
  const ResultatInventaire({
    required this.dateCloture,
    required this.nbLignes,
    required this.nbEcarts,
    required this.ecartNet,
    required this.ajustementsCrees,
    required this.lignes,
  });

  final DateTime? dateCloture;
  final int nbLignes;
  final int nbEcarts;
  final double ecartNet;
  final bool ajustementsCrees;
  final List<LigneResultatInventaire> lignes;

  factory ResultatInventaire.depuisRpc(Map<String, dynamic> map) {
    return ResultatInventaire(
      dateCloture: parseDateTimeOrNull(map['date_cloture']),
      nbLignes: parseInt(map['nb_lignes']),
      nbEcarts: parseInt(map['nb_ecarts']),
      ecartNet: parseDouble(map['ecart_net']),
      ajustementsCrees: map['ajustements_crees'] == true,
      lignes: parseMapList(map['lignes'])
          .map(LigneResultatInventaire.depuisRpc)
          .toList(growable: false),
    );
  }
}

/// Accès au stock d'une boutique : lecture (catalogue) et écritures (RPC).
///
/// Singleton : `StockService.instance`.
class StockService {
  StockService._();

  static final StockService instance = StockService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // LECTURE
  // ---------------------------------------------------------------------------

  /// Tous les articles de la boutique AVEC leurs conditionnements et leur
  /// seuil d'alerte — c'est la matière première des écrans Stock.
  Future<List<Article>> getStock() => ArticleService.instance.getArticles();

  /// Un article (stock + conditionnements + seuil), ou `null` s'il a été
  /// supprimé.
  Future<Article?> getArticle(int id) => ArticleService.instance.getArticleById(id);

  /// Historique des mouvements d'un article (approvisionnements, ajustements,
  /// ventes), du plus récent au plus ancien.
  Future<List<MouvementArticle>> getMouvements(int produitId) =>
      ArticleService.instance.getMouvements(produitId);

  /// S'abonne aux changements du catalogue (le stock change à chaque
  /// mouvement : le trigger met à jour `produits.quantite`).
  ///
  /// L'appelant DOIT libérer le canal avec [arreterEcoute].
  RealtimeChannel ecouterChangements(void Function() onChange) =>
      ArticleService.instance.ecouterChangements(onChange);

  Future<void> arreterEcoute(RealtimeChannel canal) =>
      ArticleService.instance.arreterEcoute(canal);

  // ---------------------------------------------------------------------------
  // SEUIL D'ALERTE
  // ---------------------------------------------------------------------------

  /// Modifie le seuil d'alerte d'un article (exigence Module 9).
  Future<void> definirSeuil({
    required int produitId,
    required double seuil,
  }) async {
    if (seuil < 0) {
      throw const StockServiceException(
        "Le seuil d'alerte doit être un nombre positif ou nul.",
        type: TypeErreurStock.validation,
      );
    }

    await _appelerRpc(
      'rpc_stock_definir_seuil',
      params: <String, dynamic>{
        'p_produit_id': produitId,
        'p_seuil': seuil,
      },
      actionLibelle: "l'enregistrement du seuil d'alerte",
    );
  }

  // ---------------------------------------------------------------------------
  // ENTRÉE DE STOCK (APPROVISIONNEMENT)
  // ---------------------------------------------------------------------------

  /// Enregistre une ENTRÉE de stock, [quantiteUnitesBase] étant déjà convertie
  /// en unités de base (10 fardes de 12 → 120).
  ///
  /// Le serveur vérifie le droit `stock/creer`, l'appartenance de l'article et
  /// les valeurs, insère le mouvement (le trigger serveur ajoute le stock) et
  /// journalise l'opération.
  Future<ResultatApprovisionnement> approvisionner({
    required int produitId,
    required double quantiteUnitesBase,
    required double prixAchatUnitaire,
    String? fournisseur,
    DateTime? dateApprovisionnement,
  }) async {
    if (quantiteUnitesBase <= 0) {
      throw const StockServiceException(
        'La quantité ajoutée doit être supérieure à zéro.',
        type: TypeErreurStock.validation,
      );
    }
    if (prixAchatUnitaire < 0) {
      throw const StockServiceException(
        "Le prix d'achat ne peut pas être négatif.",
        type: TypeErreurStock.validation,
      );
    }

    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_stock_approvisionner',
      params: <String, dynamic>{
        'p_produit_id': produitId,
        'p_quantite': quantiteUnitesBase,
        'p_prix_achat_unitaire': prixAchatUnitaire,
        'p_fournisseur': _texteOuNull(fournisseur),
        'p_date_approvisionnement':
            dateApprovisionnement?.toUtc().toIso8601String(),
      },
      actionLibelle: "l'enregistrement de l'entrée de stock",
    );

    if (map == null) {
      throw const StockServiceException(
        "Réponse inattendue du serveur : l'entrée de stock n'est pas confirmée.",
      );
    }
    return ResultatApprovisionnement.depuisRpc(map);
  }

  // ---------------------------------------------------------------------------
  // AJUSTEMENT (INVENTAIRE)
  // ---------------------------------------------------------------------------

  /// Corrige le stock d'un article vers [quantitePhysique] comptée, avec une
  /// [raison] OBLIGATOIRE (3 caractères minimum).
  ///
  /// Le serveur calcule l'écart « physique − théorique », l'insère dans
  /// `public.ajustements` (mouvement tracé ; le trigger applique le delta) et
  /// journalise l'opération. Un écart nul est refusé (`AUCUN_ECART`).
  Future<ResultatAjustement> ajuster({
    required int produitId,
    required double quantitePhysique,
    required String raison,
  }) async {
    final String motif = raison.trim();
    if (motif.length < 3) {
      throw const StockServiceException(
        "Indiquez la raison de l'ajustement (3 caractères minimum).",
        type: TypeErreurStock.validation,
      );
    }
    if (quantitePhysique < 0) {
      throw const StockServiceException(
        'La quantité physique doit être un nombre positif ou nul.',
        type: TypeErreurStock.validation,
      );
    }

    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_stock_ajuster',
      params: <String, dynamic>{
        'p_produit_id': produitId,
        'p_quantite_physique': quantitePhysique,
        'p_raison': motif,
      },
      actionLibelle: "l'enregistrement de l'ajustement",
    );

    if (map == null) {
      throw const StockServiceException(
        "Réponse inattendue du serveur : l'ajustement n'est pas confirmé.",
      );
    }
    return ResultatAjustement.depuisRpc(map);
  }

  // ---------------------------------------------------------------------------
  // CLÔTURE DE L'INVENTAIRE QUOTIDIEN
  // ---------------------------------------------------------------------------

  /// Clôture l'inventaire quotidien : les lignes [lignes] comptées sont
  /// envoyées au serveur qui enregistre les comptages dans
  /// `inventaires_quotidiens` et, si [ajuster] est vrai, corrige les écarts
  /// par des ajustements tracés « Inventaire quotidien du JJ/MM/AAAA ».
  ///
  /// Les lignes NON comptées (`quantitePhysique == null`) sont ignorées.
  Future<ResultatInventaire> cloturerInventaire({
    required List<LigneInventaire> lignes,
    DateTime? dateCloture,
    bool ajuster = true,
  }) async {
    final List<Map<String, dynamic>> comptees = lignes
        .where((LigneInventaire ligne) => ligne.compte)
        .map((LigneInventaire ligne) => ligne.versJson())
        .toList(growable: false);

    if (comptees.isEmpty) {
      throw const StockServiceException(
        'Aucun article compté : saisissez au moins une quantité physique.',
        type: TypeErreurStock.validation,
      );
    }

    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_inventaire_cloturer',
      params: <String, dynamic>{
        'p_lignes': comptees,
        'p_date_cloture': _dateSeule(dateCloture ?? DateTime.now()),
        'p_ajuster': ajuster,
      },
      actionLibelle: "la clôture de l'inventaire",
    );

    if (map == null) {
      throw const StockServiceException(
        "Réponse inattendue du serveur : la clôture de l'inventaire n'est pas confirmée.",
      );
    }
    return ResultatInventaire.depuisRpc(map);
  }

  // ---------------------------------------------------------------------------
  // OUTILS PARTAGÉS
  // ---------------------------------------------------------------------------

  /// Extrait le message utilisateur d'une erreur du serveur.
  ///
  /// Les fonctions SQL préfixent leurs messages d'un code
  /// (`RAISON_OBLIGATOIRE|…`) : l'application n'affiche que la partie
  /// française.
  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  static TypeErreurStock _typeDepuisMessage(String brut) {
    final String code = brut.trim().split('|').first.trim().toUpperCase();
    switch (code) {
      case 'SESSION_ABSENTE':
      case 'DROIT_REFUSE':
      case 'HORS_BOUTIQUE':
        return TypeErreurStock.droits;
      case 'SEUIL_INVALIDE':
      case 'QUANTITE_INVALIDE':
      case 'PRIX_INVALIDE':
      case 'RAISON_OBLIGATOIRE':
      case 'AUCUN_ECART':
      case 'LIGNE_INVALIDE':
      case 'PRODUIT_INTROUVABLE':
        return TypeErreurStock.validation;
      default:
        return TypeErreurStock.inconnu;
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
      debugPrint('StockService ($actionLibelle) PostgrestException: ${e.code} ${e.message}');
      throw StockServiceException(
        messageErreur(e.message),
        type: _typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('StockService ($actionLibelle): $e\n$st');
      throw const StockServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurStock.reseau,
      );
    }

    return reponseRpcEnMap(reponse);
  }

  String? _texteOuNull(String? valeur) {
    final String texte = (valeur ?? '').trim();
    return texte.isEmpty ? null : texte;
  }

  /// `AAAA-MM-JJ` (colonne `date` : pas d'heure, pas de fuseau).
  static String _dateSeule(DateTime date) {
    final String mois = date.month.toString().padLeft(2, '0');
    final String jour = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mois-$jour';
  }
}
