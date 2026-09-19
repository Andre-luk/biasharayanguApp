// lib/models/table_salle.dart
//
// 🍽️ MODULE 16 (phase C3) — RESTAURANT : TABLE DE SALLE.
//
// Une table vit au rythme des commandes : libre → occupee (commande
// ouverte) → libre (commande encaissée ou annulée) ; « reservee » reste
// possible pour anticiper un client.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Statut d'une table (table `public.tables_salle`).
enum TableStatut {
  libre('libre', 'Libre'),
  occupee('occupee', 'Occupée'),
  reservee('reservee', 'Réservée');

  const TableStatut(this.code, this.libelle);

  final String code;
  final String libelle;

  static TableStatut fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final TableStatut statut in values) {
      if (statut.code == normalise) return statut;
    }
    return TableStatut.libre;
  }
}

/// Une table de salle — table `public.tables_salle`.
class TableSalle {
  const TableSalle({
    required this.id,
    required this.numero,
    this.zone = '',
    this.places = 2,
    this.statut = TableStatut.libre,
    this.actif = true,
    this.ownerId,
  });

  final String id;
  final String numero;

  /// Zone libre : « Salle », « Terrasse », « Étage »…
  final String zone;

  final int places;
  final TableStatut statut;
  final bool actif;
  final String? ownerId;

  /// Désignation affichée (« Table 5 — Terrasse »).
  String get designation =>
      zone.isEmpty ? 'Table $numero' : 'Table $numero — $zone';

  /// `true` si la table peut accueillir une nouvelle commande.
  bool get disponible => actif && statut != TableStatut.occupee;

  factory TableSalle.fromMap(Map<String, dynamic> map) {
    return TableSalle(
      id: parseString(map['id']),
      numero: parseString(map['numero']),
      zone: parseString(map['zone']),
      places: parseInt(map['places'], fallback: 2),
      statut: TableStatut.fromCode(parseStringOrNull(map['statut'])),
      actif: map['actif'] is bool ? map['actif'] as bool : true,
      ownerId: parseStringOrNull(map['owner_id']),
    );
  }

  TableSalle copyWith({
    String? id,
    String? numero,
    String? zone,
    int? places,
    TableStatut? statut,
    bool? actif,
    String? ownerId,
  }) {
    return TableSalle(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      zone: zone ?? this.zone,
      places: places ?? this.places,
      statut: statut ?? this.statut,
      actif: actif ?? this.actif,
      ownerId: ownerId ?? this.ownerId,
    );
  }
}
