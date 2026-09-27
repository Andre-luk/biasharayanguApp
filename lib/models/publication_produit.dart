// lib/models/publication_produit.dart
//
// 🛒 MODULE 19 — ÉTAT DE PUBLICATION D'UN ARTICLE DANS LE CATALOGUE PUBLIC.
//
// Le commerçant ne « duplique » pas ses articles : il choisit ceux qu'il rend
// visibles dans Biashara, avec un éventuel prix public et un texte d'accroche.
// La table `produits` n'est jamais modifiée par ce module.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Article du catalogue interne, vu depuis l'écran « Mes publications ».
class PublicationProduit {
  const PublicationProduit({
    required this.produitId,
    required this.nom,
    this.publicationId,
    this.categorie,
    this.photo,
    this.prixVente = 0,
    this.prixPublic,
    this.unite = 'unité',
    this.descriptionCourte,
    this.motsCles,
    this.publie = false,
    this.disponible = false,
    this.stock = 0,
    this.misAJourLe,
  });

  /// Identifiant de la publication (`null` = jamais publié).
  final String? publicationId;

  /// Identifiant de l'article dans `produits` (bigint).
  final int produitId;

  final String nom;
  final String? categorie;
  final String? photo;

  /// Prix de vente interne (unités de base).
  final double prixVente;

  /// Prix affiché publiquement. `null` = le prix de vente est utilisé.
  final double? prixPublic;

  final String unite;
  final String? descriptionCourte;
  final String? motsCles;

  final bool publie;

  /// Disponibilité DÉCLARÉE par le commerçant (le stock exact n'est jamais
  /// publié).
  final bool disponible;

  /// Stock interne — reste affiché uniquement dans l'application du commerçant.
  final double stock;

  final DateTime? misAJourLe;

  /// Prix réellement affiché dans le catalogue public.
  double get prixAffiche => prixPublic ?? prixVente;

  /// Le prix public a-t-il été personnalisé ?
  bool get prixPersonnalise =>
      prixPublic != null && (prixPublic! - prixVente).abs() > 0.004;

  /// Nombre d'informations manquantes qui pénalisent la visibilité.
  ///
  /// Ce contrôle est TRANSPARENT : il explique au commerçant, avec des mots
  /// simples, pourquoi sa fiche peut être classée après une autre.
  List<String> get informationsManquantes {
    final List<String> manquantes = <String>[];
    if (photo == null || photo!.trim().isEmpty) manquantes.add('Photo');
    if (descriptionCourte == null || descriptionCourte!.trim().isEmpty) {
      manquantes.add('Courte description');
    }
    if (!publie) manquantes.add('Publication');
    if (!disponible) manquantes.add('Disponibilité');
    return manquantes;
  }

  /// Score de complétude 0 → 100 (affiché à titre indicatif).
  int get completude {
    int score = 40; // publié + disponible = base
    if (!publie) score -= 30;
    if (!disponible) score -= 10;
    if (photo != null && photo!.trim().isNotEmpty) score += 30;
    if (descriptionCourte != null && descriptionCourte!.trim().isNotEmpty) {
      score += 25;
    }
    if (motsCles != null && motsCles!.trim().isNotEmpty) score += 5;
    return score.clamp(0, 100);
  }

  factory PublicationProduit.fromMap(Map<String, dynamic> map) {
    return PublicationProduit(
      publicationId: parseStringOrNull(map['publication_id']),
      produitId: parseInt(map['produit_id']),
      nom: parseString(map['nom']),
      categorie: parseStringOrNull(map['categorie']),
      photo: parseStringOrNull(map['photo']),
      prixVente: parseDouble(map['prix_vente']),
      prixPublic: parseDoubleOrNull(map['prix_public']),
      unite: parseString(map['unite'], fallback: 'unité'),
      descriptionCourte: parseStringOrNull(map['description_courte']),
      motsCles: parseStringOrNull(map['mots_cles']),
      publie: map['publie'] == true,
      disponible: map['disponible'] == true,
      stock: parseDouble(map['stock']),
      misAJourLe: parseDateTimeOrNull(map['mis_a_jour_le']),
    );
  }

  PublicationProduit copyWith({
    bool? publie,
    bool? disponible,
    double? prixPublic,
    String? descriptionCourte,
  }) {
    return PublicationProduit(
      publicationId: publicationId,
      produitId: produitId,
      nom: nom,
      categorie: categorie,
      photo: photo,
      prixVente: prixVente,
      prixPublic: prixPublic ?? this.prixPublic,
      unite: unite,
      descriptionCourte: descriptionCourte ?? this.descriptionCourte,
      motsCles: motsCles,
      publie: publie ?? this.publie,
      disponible: disponible ?? this.disponible,
      stock: stock,
      misAJourLe: misAJourLe,
    );
  }
}

/// État complet de l'écran « Mes publications ».
class EtatPublications {
  const EtatPublications({
    this.espaceId = '',
    this.total = 0,
    this.nbPublies = 0,
    this.articles = const <PublicationProduit>[],
  });

  final String espaceId;

  /// Nombre total d'articles du catalogue interne.
  final int total;

  /// Nombre d'articles effectivement visibles dans Biashara.
  final int nbPublies;

  final List<PublicationProduit> articles;

  /// Part du catalogue publiée, en pourcentage (0 → 100).
  int get tauxPublication {
    if (total <= 0) return 0;
    return ((nbPublies / total) * 100).round().clamp(0, 100);
  }

  factory EtatPublications.fromMap(Map<String, dynamic> map) {
    return EtatPublications(
      espaceId: parseString(map['espace_id']),
      total: parseInt(map['total']),
      nbPublies: parseInt(map['nb_publies']),
      articles: map['articles'] is List
          ? (map['articles'] as List)
              .whereType<Map>()
              .map((Map e) =>
                  PublicationProduit.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <PublicationProduit>[],
    );
  }
}

/// Filtres de l'écran « Mes publications ».
enum FiltrePublications {
  tous('tous', 'Tous'),
  publies('publies', 'Publiés'),
  nonPublies('non_publies', 'Non publiés'),
  indisponibles('indisponibles', 'Indisponibles');

  const FiltrePublications(this.code, this.libelle);

  final String code;
  final String libelle;
}
