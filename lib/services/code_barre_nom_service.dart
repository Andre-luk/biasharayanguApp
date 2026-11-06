// lib/services/code_barre_nom_service.dart
//
// 🏷️ « JE SCANNE LE CODE-BARRES, LE NOM S'ÉCRIT. »
//
// Deux sources, dans cet ordre :
//
//   1. LE CATALOGUE DE LA BOUTIQUE — géré par l'appelant via
//      `ArticleService.trouverParCodeBarre` : un produit déjà enregistré est
//      reconnu instantanément, même sans réseau (cache local).
//
//   2. UNE BASE PUBLIQUE (OpenFoodFacts) — utilisée UNIQUEMENT quand le code
//      est inconnu de la boutique, pour PROPOSER un nom. La proposition n'est
//      jamais écrite d'office : le commerçant l'accepte d'un geste.
//
// ⚠️ RÈGLES
//    • aucune clé d'API, aucun compte : appel public anonyme ;
//    • délai court (6 s) et échec SILENCIEUX : sans réseau, on rend `null` et
//      le commerçant saisit le nom comme avant ;
//    • on ne transmet AUCUNE donnée de la boutique (seul le code-barres).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Suggestion de nom à partir d'un code-barres inconnu.
class CodeBarreNomService {
  CodeBarreNomService._();

  static final CodeBarreNomService instance = CodeBarreNomService._();

  static const Duration _delai = Duration(seconds: 6);

  final Map<String, String?> _cache = <String, String?>{};

  /// Nom probable d'un produit, ou `null` si aucune source ne le connaît.
  ///
  /// Le résultat est mis en cache (y compris l'absence de résultat) : un même
  /// code n'est jamais interrogé deux fois dans la même session.
  Future<String?> nomProbable(String code) async {
    final String recherche = code.trim();
    if (recherche.length < 6) return null;
    if (_cache.containsKey(recherche)) return _cache[recherche];

    String? nom;
    try {
      nom = await _openFoodFacts(recherche);
    } catch (e) {
      debugPrint('CodeBarreNomService (ignoré) : $e');
      nom = null;
    }

    _cache[recherche] = nom;
    return nom;
  }

  /// Interrogation de la base publique OpenFoodFacts (Codes-barres EAN/UPC).
  Future<String?> _openFoodFacts(String code) async {
    final Uri uri = Uri.parse(
      'https://world.openfoodfacts.org/api/v2/product/$code.json'
      '?fields=product_name,product_name_fr,generic_name,generic_name_fr,'
      'brands,quantity',
    );

    final http.Response reponse = await http.get(
      uri,
      headers: <String, String>{
        'User-Agent': 'BiasharaYangu/3.6.1 (application de gestion)',
        'Accept': 'application/json',
      },
    ).timeout(_delai);

    if (reponse.statusCode != 200) return null;

    final dynamic decode = jsonDecode(reponse.body);
    if (decode is! Map) return null;
    if (decode['status'] != 1) return null;

    final Map<String, dynamic> produit = Map<String, dynamic>.from(
      decode['product'] is Map ? decode['product'] as Map : <String, dynamic>{},
    );

    String texte(dynamic valeur) =>
        valeur == null ? '' : valeur.toString().trim();

    final String base = texte(produit['product_name_fr']).isNotEmpty
        ? texte(produit['product_name_fr'])
        : (texte(produit['product_name']).isNotEmpty
            ? texte(produit['product_name'])
            : (texte(produit['generic_name_fr']).isNotEmpty
                ? texte(produit['generic_name_fr'])
                : texte(produit['generic_name'])));

    if (base.isEmpty) return null;

    final String marque = texte(produit['brands']).split(',').first.trim();
    final String quantite = texte(produit['quantity']);

    final StringBuffer nom = StringBuffer();
    if (marque.isNotEmpty && !base.toLowerCase().contains(marque.toLowerCase())) {
      nom.write('$marque ');
    }
    nom.write(base);
    if (quantite.isNotEmpty) nom.write(' $quantite');

    return nom.toString().trim();
  }
}
