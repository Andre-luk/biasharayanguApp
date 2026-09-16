// lib/models/categorie.dart
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Catégorie d'articles — table `public.categories`.
///
/// Le référentiel est GLOBAL (partagé par toutes les boutiques) : chaque nom
/// est unique, insensible à la casse et aux espaces (index
/// `idx_categories_nom_unique`).
///
/// Un article référence sa catégorie par son NOM (`produits.categorie`),
/// stocké tel quel — renommer une catégorie est donc propagé par le service
/// aux articles de la boutique.
///
/// ⚠️ À ne pas confondre avec `models/category.dart` (`Category`) : ancien
/// modèle de la base locale SQLite, conservé pour les écrans historiques.
class Categorie {
  final int id;
  final String nom;

  const Categorie({required this.id, required this.nom});

  factory Categorie.fromMap(Map<String, dynamic> map) {
    return Categorie(
      id: parseInt(map['id']),
      nom: parseString(map['nom']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nom': nom,
    };
  }

  Categorie copyWith({int? id, String? nom}) {
    return Categorie(
      id: id ?? this.id,
      nom: nom ?? this.nom,
    );
  }

  /// Normalisation utilisée pour comparer deux noms de catégorie
  /// (« Boissons » = «  boissons »).
  static String normaliser(String nom) => nom.trim().toLowerCase();
}
