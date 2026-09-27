// lib/models/accueil_public.dart
//
// 🛒 MODULE 19 — DTO DE LA PAGE PUBLIQUE « BIASHARA ».
//
// Regroupe ce qu'une seule requête serveur ramène pour construire la page
// d'accueil publique et la fiche produit publique : c'est volontairement
// limité à quelques dizaines d'objets (jamais tout le catalogue).

import 'package:biashara_yangu/models/boutique_publique.dart';
import 'package:biashara_yangu/models/produit_public.dart';
import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Une catégorie populaire du catalogue public.
class CategoriePublique {
  const CategoriePublique({
    required this.categorie,
    this.libelle,
    this.nbProduits = 0,
  });

  final String categorie;
  final String? libelle;
  final int nbProduits;

  /// Libellé à afficher (« boissons » → « Boissons »).
  String get libelleAffiche {
    final String base = (libelle != null && libelle!.trim().isNotEmpty)
        ? libelle!.trim()
        : categorie.trim();
    if (base.isEmpty) return base;
    return base[0].toUpperCase() + base.substring(1);
  }

  factory CategoriePublique.fromMap(Map<String, dynamic> map) {
    return CategoriePublique(
      categorie: parseString(map['categorie']),
      libelle: parseStringOrNull(map['libelle']),
      nbProduits: parseInt(map['nb_produits']),
    );
  }
}

/// Données de la page d'accueil publique (une seule requête).
class AccueilPublic {
  const AccueilPublic({
    this.categories = const <CategoriePublique>[],
    this.produits = const <ProduitPublic>[],
    this.boutiques = const <ResumeBoutique>[],
    this.publicites = const <PubliciteBiashara>[],
  });

  final List<CategoriePublique> categories;
  final List<ProduitPublic> produits;
  final List<ResumeBoutique> boutiques;
  final List<PubliciteBiashara> publicites;

  bool get vide =>
      produits.isEmpty && boutiques.isEmpty && categories.isEmpty;

  factory AccueilPublic.fromMap(Map<String, dynamic> map) {
    return AccueilPublic(
      categories: map['categories'] is List
          ? (map['categories'] as List)
              .whereType<Map>()
              .map((Map e) =>
                  CategoriePublique.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <CategoriePublique>[],
      produits: map['produits'] is List
          ? (map['produits'] as List)
              .whereType<Map>()
              .map((Map e) => _produitPublic(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <ProduitPublic>[],
      boutiques: map['boutiques'] is List
          ? (map['boutiques'] as List)
              .whereType<Map>()
              .map((Map e) => ResumeBoutique.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <ResumeBoutique>[],
      publicites: map['publicites'] is List
          ? (map['publicites'] as List)
              .whereType<Map>()
              .map((Map e) =>
                  PubliciteBiashara.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <PubliciteBiashara>[],
    );
  }

  /// L'accueil renvoie les produits « à plat » (sans bloc boutique) : on
  /// reconstruit un résumé de boutique minimal pour que la carte produit reste
  /// identique aux résultats de recherche.
  static ProduitPublic _produitPublic(Map<String, dynamic> map) {
    return ProduitPublic.fromMap(<String, dynamic>{
      'publication_id': map['publication_id'],
      'produit_id': map['produit_id'],
      'nom': map['nom'],
      'photo': map['photo'],
      'prix': map['prix'],
      'unite': map['unite'],
      'disponible': map['disponible'],
      'distance_km': map['distance_km'],
      'boutique': <String, dynamic>{
        'espace_id': '',
        'nom': map['boutique_nom'],
        'slug': map['boutique_slug'],
        'quartier': map['quartier'],
        'ville': map['ville'],
      },
    });
  }
}

/// Fiche produit publique complète : le produit, SA boutique, les AUTRES
/// boutiques qui proposent un produit correspondant (comparaison des prix) et
/// les emplacements publicitaires.
class FicheProduitPublic {
  const FicheProduitPublic({
    required this.produit,
    required this.boutique,
    this.autresBoutiques = const <ProduitPublic>[],
    this.publicites = const <PubliciteBiashara>[],
  });

  final ProduitPublic produit;
  final ResumeBoutique boutique;

  /// Offres comparables (même produit chez d'autres boutiques).
  final List<ProduitPublic> autresBoutiques;

  final List<PubliciteBiashara> publicites;

  /// Offres triées par prix croissant, la boutique affichée en premier.
  List<ProduitPublic> get comparaisonTriees {
    final List<ProduitPublic> toutes = <ProduitPublic>[produit, ...autresBoutiques]
      ..sort((ProduitPublic a, ProduitPublic b) => a.prix.compareTo(b.prix));
    return toutes;
  }

  /// Prix le plus bas disponible pour ce produit.
  double get prixMin => comparaisonTriees
      .map((ProduitPublic p) => p.prix)
      .reduce((double a, double b) => a < b ? a : b);

  /// Prix le plus élevé.
  double get prixMax => comparaisonTriees
      .map((ProduitPublic p) => p.prix)
      .reduce((double a, double b) => a > b ? a : b);

  /// Nombre de boutiques qui proposent ce produit.
  int get nbBoutiques => comparaisonTriees.length;

  factory FicheProduitPublic.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic> brutProduit =
        parseMap(map['produit']) ?? <String, dynamic>{};
    final Map<String, dynamic> brutBoutique =
        parseMap(map['boutique']) ?? <String, dynamic>{};

    return FicheProduitPublic(
      produit: ProduitPublic.fromMap(<String, dynamic>{
        ...brutProduit,
        'boutique': brutBoutique,
      }),
      boutique: ResumeBoutique.fromMap(brutBoutique),
      autresBoutiques: map['autres_boutiques'] is List
          ? (map['autres_boutiques'] as List)
              .whereType<Map>()
              .map((Map e) => ProduitPublic.fromMap(_autreOffre(Map<String, dynamic>.from(e))))
              .toList(growable: false)
          : const <ProduitPublic>[],
      publicites: map['publicites'] is List
          ? (map['publicites'] as List)
              .whereType<Map>()
              .map((Map e) =>
                  PubliciteBiashara.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <PubliciteBiashara>[],
    );
  }

  /// Les « autres boutiques » arrivent à plat : on reconstruit la boutique.
  static Map<String, dynamic> _autreOffre(Map<String, dynamic> map) {
    return <String, dynamic>{
      ...map,
      'boutique': <String, dynamic>{
        'espace_id': map['espace_id'],
        'nom': map['boutique_nom'],
        'slug': map['boutique_slug'],
        'quartier': map['quartier'],
        'ville': map['ville'],
        'telephone': map['telephone'],
        'whatsapp': map['whatsapp'],
        'latitude': map['latitude'],
        'longitude': map['longitude'],
      },
    };
  }
}
