// lib/models/ville.dart
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Référentiel des villes — table `public.villes`.
///
/// Modèle en lecture seule dans ce module : les villes sont gérées directement
/// côté Supabase par l'administrateur système.
class Ville {
  final String id;
  final String nom;
  final String? pays;
  final DateTime? createdAt;

  const Ville({
    required this.id,
    required this.nom,
    this.pays,
    this.createdAt,
  });

  factory Ville.fromMap(Map<String, dynamic> map) {
    return Ville(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      pays: parseStringOrNull(map['pays']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nom': nom,
      'pays': pays,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Ville copyWith({
    String? id,
    String? nom,
    String? pays,
    DateTime? createdAt,
  }) {
    return Ville(
      id: id ?? this.id,
      nom: nom ?? this.nom,
      pays: pays ?? this.pays,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
