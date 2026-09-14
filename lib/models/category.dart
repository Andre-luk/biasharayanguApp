// lib/models/category.dart

class Category {
  final int? id;
  final String nom;

  Category({this.id, required this.nom});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nom': nom,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      nom: map['nom'] as String,
    );
  }
}