// lib/models/activite.dart
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Référentiel des activités commerciales — table `public.activites`.
///
/// Chaque activité est rattachée à un ou plusieurs groupes tarifaires
/// (voir [GroupeTarifaire]).
class Activite {
  final String id;
  final String nom;
  final String? description;
  final DateTime? createdAt;

  const Activite({
    required this.id,
    required this.nom,
    this.description,
    this.createdAt,
  });

  factory Activite.fromMap(Map<String, dynamic> map) {
    return Activite(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      description: parseStringOrNull(map['description']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nom': nom,
      'description': description,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Activite copyWith({
    String? id,
    String? nom,
    String? description,
    DateTime? createdAt,
  }) {
    return Activite(
      id: id ?? this.id,
      nom: nom ?? this.nom,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
