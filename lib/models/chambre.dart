// lib/models/chambre.dart
//
// 🧩 MODULE 16 (phase C2) — HÔTEL : CHAMBRE.
//
// Cycle de vie du statut :
//   libre → reservee (une réservation existe) → occupee (check-in) →
//   a_nettoyer (check-out) → libre (remise en service).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Statut d'une chambre (table `public.chambres`).
enum ChambreStatut {
  libre('libre', 'Libre'),
  reservee('reservee', 'Réservée'),
  occupee('occupee', 'Occupée'),
  aNettoyer('a_nettoyer', 'À nettoyer');

  const ChambreStatut(this.code, this.libelle);

  /// Code stocké côté serveur.
  final String code;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// Convertit un code serveur en statut (repli : [libre]).
  static ChambreStatut fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final ChambreStatut statut in values) {
      if (statut.code == normalise) return statut;
    }
    return ChambreStatut.libre;
  }
}

/// Une chambre d'hôtel — table `public.chambres`.
class Chambre {
  const Chambre({
    required this.id,
    required this.numero,
    this.typeChambre = '',
    this.capacite = 1,
    this.prixNuit = 0,
    this.statut = ChambreStatut.libre,
    this.equipements,
    this.actif = true,
    this.ownerId,
  });

  final String id;

  /// Numéro affiché (« 101 », « Suite A »…). Unique par boutique.
  final String numero;

  /// Type libre : Simple, Double, Suite…
  final String typeChambre;

  /// Capacité maximale (personnes).
  final int capacite;

  /// Prix par nuit (unité monétaire de l'application).
  final double prixNuit;

  final ChambreStatut statut;

  /// Équipements / notes (climatisation, douche, balcon…).
  final String? equipements;

  /// Une chambre inactive reste dans l'historique mais n'est plus louée.
  final bool actif;

  final String? ownerId;

  /// `true` si la chambre peut immédiatement accueillir une nouvelle
  /// réservation.
  bool get disponible => actif && statut == ChambreStatut.libre;

  /// Désignation complète (« Chambre 101 — Double »).
  String get designation =>
      typeChambre.isEmpty ? 'Chambre $numero' : 'Chambre $numero — $typeChambre';

  factory Chambre.fromMap(Map<String, dynamic> map) {
    return Chambre(
      id: parseString(map['id']),
      numero: parseString(map['numero']),
      typeChambre: parseString(map['type_chambre']),
      capacite: parseInt(map['capacite'], fallback: 1),
      prixNuit: parseDouble(map['prix_nuit']),
      statut: ChambreStatut.fromCode(parseStringOrNull(map['statut'])),
      equipements: parseStringOrNull(map['equipements']),
      actif: map['actif'] is bool ? map['actif'] as bool : true,
      ownerId: parseStringOrNull(map['owner_id']),
    );
  }

  Chambre copyWith({
    String? id,
    String? numero,
    String? typeChambre,
    int? capacite,
    double? prixNuit,
    ChambreStatut? statut,
    String? equipements,
    bool? actif,
    String? ownerId,
  }) {
    return Chambre(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      typeChambre: typeChambre ?? this.typeChambre,
      capacite: capacite ?? this.capacite,
      prixNuit: prixNuit ?? this.prixNuit,
      statut: statut ?? this.statut,
      equipements: equipements ?? this.equipements,
      actif: actif ?? this.actif,
      ownerId: ownerId ?? this.ownerId,
    );
  }
}
