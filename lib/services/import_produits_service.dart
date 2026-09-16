// lib/services/import_produits_service.dart
//
// MODULE 12 — IMPORT RAPIDE D'ARTICLES (SERVICE).
//
// Chaîne complète :
//   1. ANALYSE LOCALE — `analyserContenu` / `analyserOctets` lisent un
//      CSV/TSV tolérant (voir `utils/import_csv.dart`) : rien ne part au
//      serveur tant que l'utilisateur n'a pas vérifié le résultat ;
//   2. IMPORT SERVEUR — `importer(...)` appelle `rpc_produits_importer` par
//      tranches de 500 lignes (limite du serveur) et cumule les résultats ;
//   3. TRACABILITÉ — le serveur journalise UNE entrée `IMPORT_PRODUITS`
//      (niveau HAUT) avec créés / mis à jour / ignorés / erreurs.
//
// ⚠️ La quantité n'est JAMAIS modifiée pour un article existant : le stock ne
// bouge que par les mouvements tracés du Module 9. La mise à jour optionnelle
// ne touche que la fiche (catégorie, unité, description, prix).

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/import_produits.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart' show reponseRpcEnMap;
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/import_csv.dart';

/// Nature d'une erreur d'import (pour adapter l'interface).
enum TypeErreurImport { droits, validation, abonnement, reseau, inconnu }

/// Erreur métier de l'import (message déjà en français).
class ImportProduitsException implements Exception {
  const ImportProduitsException(
    this.message, {
    this.type = TypeErreurImport.inconnu,
  });

  final String message;
  final TypeErreurImport type;

  @override
  String toString() => message;
}

/// Analyse et import d'articles. Singleton : `ImportProduitsService.instance`.
class ImportProduitsService {
  ImportProduitsService._();

  static final ImportProduitsService instance = ImportProduitsService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Limite serveur : `rpc_produits_importer` refuse plus de 500 lignes.
  static const int maxParAppel = 500;

  // ---------------------------------------------------------------------------
  // 1. ANALYSE LOCALE
  // ---------------------------------------------------------------------------

  /// Analyse un contenu CSV/TSV déjà décodé.
  AnalyseImport analyserContenu(String contenu) => ImportCsv.analyser(contenu);

  /// Décode des octets (UTF-8 tolérant : BOM et caractères invalides gérés)
  /// puis analyse le contenu.
  AnalyseImport analyserOctets(Uint8List octets) {
    final String contenu = utf8.decode(octets, allowMalformed: true);
    return ImportCsv.analyser(contenu);
  }

  // ---------------------------------------------------------------------------
  // 2. IMPORT SERVEUR (TRANCHES DE 500)
  // ---------------------------------------------------------------------------

  /// Importe les lignes validées. [mettreAJour] : `true` pour mettre à jour la
  /// fiche des articles portant le même nom (`false` : ils sont ignorés).
  ///
  /// Renvoie le cumul des tranches ; les erreurs de chaque tranche sont
  /// renumérotées par rapport au fichier d'origine.
  Future<ResultatImport> importer(
    List<LigneImport> lignes, {
    bool mettreAJour = false,
  }) async {
    if (lignes.isEmpty) {
      throw const ImportProduitsException(
        'Aucune ligne valide à importer : corrigez le fichier puis relancez l\'analyse.',
        type: TypeErreurImport.validation,
      );
    }

    ResultatImport total = const ResultatImport.vide();

    for (int debut = 0; debut < lignes.length; debut += maxParAppel) {
      final List<LigneImport> tranche = lignes.sublist(
        debut,
        math.min(debut + maxParAppel, lignes.length),
      );

      final ResultatImport resultat = await _importerTranche(
        tranche,
        mettreAJour: mettreAJour,
      );

      total = total.fusionner(resultat, decalageLignes: debut);
    }

    return total;
  }

  Future<ResultatImport> _importerTranche(
    List<LigneImport> tranche, {
    required bool mettreAJour,
  }) async {
    dynamic reponse;
    try {
      reponse = await _client.rpc(
        'rpc_produits_importer',
        params: <String, dynamic>{
          'p_lignes': tranche
              .map((LigneImport ligne) => ligne.toJson())
              .toList(growable: false),
          'p_mettre_a_jour': mettreAJour,
        },
      );
    } on PostgrestException catch (e) {
      debugPrint('ImportProduitsService : ${e.message}');
      throw ImportProduitsException(
        messageErreur(e.message),
        type: _typeDepuisMessage(e.message),
      );
    } catch (e) {
      debugPrint('ImportProduitsService : $e');
      throw const ImportProduitsException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurImport.reseau,
      );
    }

    final ResultatImport? resultat = ResultatImport.depuisRpc(reponseRpcEnMap(reponse));
    if (resultat == null) {
      throw const ImportProduitsException(
        'Réponse inattendue du serveur : vérifiez la liste des articles avant '
        'de relancer un import.',
      );
    }
    return resultat;
  }

  // ---------------------------------------------------------------------------
  // 3. OUTILS
  // ---------------------------------------------------------------------------

  /// Extrait le message utilisateur d'une erreur serveur préfixée
  /// (`CODE|message`), comme les autres services du projet.
  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  static TypeErreurImport _typeDepuisMessage(String brut) {
    final String code = brut.trim().split('|').first.trim().toUpperCase();
    switch (code) {
      case 'SESSION_ABSENTE':
      case 'DROIT_REFUSE':
      case 'RESERVE_ENTREPRISE':
        return TypeErreurImport.droits;
      case 'LIGNES_VIDES':
      case 'TROP_DE_LIGNES':
        return TypeErreurImport.validation;
      case 'ABONNEMENT_BLOQUE':
      case 'ABONNEMENT_EXPIRE':
        return TypeErreurImport.abonnement;
      default:
        return TypeErreurImport.inconnu;
    }
  }
}
