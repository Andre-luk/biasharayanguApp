// lib/models/salle.dart
//
// 🎉 MODULE 16 (phase C4) — SALLE DES FÊTES : SALLE.
//
// Une salle accueille des événements (mariages, anniversaires, réunions…).
// Elle n'a pas de « statut » figé : son occupation se déduit du calendrier
// des événements actifs. Le prix par jour sert de tarif proposé (il peut
// être négocié événement par événement).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Une salle de fête — table `public.salles`.
class Salle {
  const Salle({
    required this.id,
    required this.nom,
    this.capacite = 50,
    this.prixJour = 0,
    this.description,
    this.equipements,
    this.actif = true,
    this.ownerId,
  });

  final String id;

  /// Nom affiché (« Salle principale », « Terrasse »…). Unique par boutique.
  final String nom;

  /// Capacité maximale (personnes).
  final int capacite;

  /// Prix par jour (unité monétaire de l'application).
  final double prixJour;

  /// Description libre.
  final String? description;

  /// Équipements / notes (sono, climatisation, parking…).
  final String? equipements;

  /// Une salle inactive reste dans l'historique mais ne se réserve plus.
  final bool actif;

  final String? ownerId;

  /// Désignation courte (« Salle principale · 200 pers. »).
  String get designation => '$nom · $capacite pers.';

  factory Salle.fromMap(Map<String, dynamic> map) {
    return Salle(
      id: parseString(map['id']),
      nom: parseString(map['nom'], fallback: 'Salle'),
      capacite: parseInt(map['capacite'], fallback: 50),
      prixJour: parseDouble(map['prix_jour']),
      description: parseStringOrNull(map['description']),
      equipements: parseStringOrNull(map['equipements']),
      actif: map['actif'] == null ? true : map['actif'] == true,
      ownerId: parseStringOrNull(map['owner_id']),
    );
  }
}
