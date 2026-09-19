// lib/models/hotel_tableau_bord.dart
//
// 🧩 MODULE 16 (phase C2) — HÔTEL : TABLEAU DE BORD DE LA RÉCEPTION.
//
// Réponse de `rpc_hotel_tableau_bord()` : occupation des chambres, nombre
// de séjours actifs, et listes des arrivées / départs attendus du jour.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Un séjour affiché sur le tableau de bord de la réception.
class SejourJour {
  const SejourJour({
    required this.id,
    required this.chambre,
    required this.client,
    required this.dateArrivee,
    required this.dateDepart,
    this.nbPersonnes = 1,
    this.montantTotal = 0,
    this.montantPaye = 0,
    this.solde = 0,
    this.retard = false,
  });

  final String id;
  final String chambre;
  final String client;

  /// Dates déjà formatées « JJ/MM/AAAA » par le serveur.
  final String dateArrivee;
  final String dateDepart;

  final int nbPersonnes;
  final double montantTotal;
  final double montantPaye;
  final double solde;

  /// La date prévue est dépassée (retard côté réception).
  final bool retard;

  factory SejourJour.fromMap(Map<String, dynamic> map) {
    return SejourJour(
      id: parseString(map['id']),
      chambre: parseString(map['chambre']),
      client: parseString(map['client'], fallback: 'Client'),
      dateArrivee: parseString(map['date_arrivee']),
      dateDepart: parseString(map['date_depart']),
      nbPersonnes: parseInt(map['nb_personnes'], fallback: 1),
      montantTotal: parseDouble(map['montant_total']),
      montantPaye: parseDouble(map['montant_paye']),
      solde: parseDouble(map['solde']),
      retard: map['retard'] == true,
    );
  }
}

/// Occupation de l'hôtel + mouvements du jour.
class TableauBordHotel {
  const TableauBordHotel({
    this.total = 0,
    this.libres = 0,
    this.reservees = 0,
    this.occupees = 0,
    this.aNettoyer = 0,
    this.occupation = 0,
    this.reservationsActives = 0,
    this.arriveesCount = 0,
    this.departsCount = 0,
    this.arrivees = const <SejourJour>[],
    this.departs = const <SejourJour>[],
  });

  final int total;
  final int libres;
  final int reservees;
  final int occupees;
  final int aNettoyer;

  /// Taux d'occupation en % (0–100).
  final double occupation;

  final int reservationsActives;
  final int arriveesCount;
  final int departsCount;

  final List<SejourJour> arrivees;
  final List<SejourJour> departs;

  factory TableauBordHotel.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic>? chambres = parseMap(map['chambres']);
    return TableauBordHotel(
      total: parseInt(chambres?['total']),
      libres: parseInt(chambres?['libres']),
      reservees: parseInt(chambres?['reservees']),
      occupees: parseInt(chambres?['occupees']),
      aNettoyer: parseInt(chambres?['a_nettoyer']),
      occupation: parseDouble(map['occupation']),
      reservationsActives: parseInt(map['reservations_actives']),
      arriveesCount: parseInt(map['arrivees_count']),
      departsCount: parseInt(map['departs_count']),
      arrivees: _liste(map['arrivees']),
      departs: _liste(map['departs']),
    );
  }

  static List<SejourJour> _liste(dynamic valeur) {
    if (valeur is! List) return const <SejourJour>[];
    return valeur
        .whereType<Map>()
        .map((Map element) =>
            SejourJour.fromMap(Map<String, dynamic>.from(element)))
        .toList(growable: false);
  }
}
