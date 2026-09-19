// lib/models/reservation.dart
//
// 🧩 MODULE 16 (phase C2) — HÔTEL : RÉSERVATION / SÉJOUR.
//
// Un séjour suit le cycle : reservee (réservation prise) → en_cours
// (check-in enregistré) → terminee (check-out) ; ou annulee tant que le
// client n'est pas arrivé.
//
// Les montants sont des SNAPSHOTS : `prix_nuit` est figé au moment de la
// réservation, modifier le prix de la chambre plus tard ne change pas un
// séjour existant.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Statut d'une réservation / séjour.
enum StatutReservation {
  reservee('reservee', 'En attente'),
  enCours('en_cours', 'En cours'),
  terminee('terminee', 'Terminée'),
  annulee('annulee', 'Annulée');

  const StatutReservation(this.code, this.libelle);

  final String code;
  final String libelle;

  /// Le séjour occupe (ou va occuper) une chambre.
  bool get estActive =>
      this == StatutReservation.reservee || this == StatutReservation.enCours;

  static StatutReservation fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final StatutReservation statut in values) {
      if (statut.code == normalise) return statut;
    }
    return StatutReservation.reservee;
  }
}

/// Un séjour d'hôtel — table `public.reservations`.
class Reservation {
  const Reservation({
    required this.id,
    required this.chambreId,
    this.chambreNumero = '',
    this.clientId,
    required this.clientNom,
    this.clientTelephone,
    required this.dateArrivee,
    required this.dateDepart,
    this.nbPersonnes = 1,
    this.prixNuit = 0,
    this.montantTotal = 0,
    this.montantPaye = 0,
    this.statut = StatutReservation.reservee,
    this.note,
    this.motifAnnulation,
  });

  final String id;
  final String chambreId;

  /// Numéro de la chambre (rempli par la jointure de lecture).
  final String chambreNumero;

  final int? clientId;
  final String clientNom;
  final String? clientTelephone;

  final DateTime dateArrivee;
  final DateTime dateDepart;

  final int nbPersonnes;

  /// Prix par nuit FIGÉ à la réservation.
  final double prixNuit;

  final double montantTotal;

  /// Total encaissé (avances + soldes), toujours ≤ [montantTotal].
  final double montantPaye;

  final StatutReservation statut;

  final String? note;
  final String? motifAnnulation;

  /// Nombre de nuits (différence de dates, départ exclu).
  int get nuits => dateDepart.difference(dateArrivee).inDays;

  /// Reste à payer (jamais négatif).
  double get solde {
    final double reste = montantTotal - montantPaye;
    return reste < 0 ? 0 : reste;
  }

  /// `true` si le séjour compte encore (en attente ou en cours).
  bool get estActive => statut.estActive;

  /// Le client est arrivé en retard, en attente de check-in.
  bool get enRetard {
    final DateTime aujourdHui = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    return statut == StatutReservation.reservee &&
        dateArrivee.isBefore(aujourdHui);
  }

  factory Reservation.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic>? chambre = parseMap(map['chambres']);
    final Map<String, dynamic>? client = parseMap(map['clients']);

    return Reservation(
      id: parseString(map['id']),
      chambreId: parseString(map['chambre_id']),
      chambreNumero: parseString(chambre?['numero']),
      clientId: map['client_id'] == null ? null : parseInt(map['client_id']),
      clientNom: parseString(map['client_nom'], fallback: 'Client'),
      clientTelephone: parseStringOrNull(client?['telephone']),
      dateArrivee: parseDateTimeOrNull(map['date_arrivee']) ?? DateTime.now(),
      dateDepart:
          parseDateTimeOrNull(map['date_depart']) ?? DateTime.now(),
      nbPersonnes: parseInt(map['nb_personnes'], fallback: 1),
      prixNuit: parseDouble(map['prix_nuit']),
      montantTotal: parseDouble(map['montant_total']),
      montantPaye: parseDouble(map['montant_paye']),
      statut: StatutReservation.fromCode(parseStringOrNull(map['statut'])),
      note: parseStringOrNull(map['note']),
      motifAnnulation: parseStringOrNull(map['motif_annulation']),
    );
  }

  Reservation copyWith({
    String? id,
    String? chambreId,
    String? chambreNumero,
    int? clientId,
    String? clientNom,
    String? clientTelephone,
    DateTime? dateArrivee,
    DateTime? dateDepart,
    int? nbPersonnes,
    double? prixNuit,
    double? montantTotal,
    double? montantPaye,
    StatutReservation? statut,
    String? note,
    String? motifAnnulation,
  }) {
    return Reservation(
      id: id ?? this.id,
      chambreId: chambreId ?? this.chambreId,
      chambreNumero: chambreNumero ?? this.chambreNumero,
      clientId: clientId ?? this.clientId,
      clientNom: clientNom ?? this.clientNom,
      clientTelephone: clientTelephone ?? this.clientTelephone,
      dateArrivee: dateArrivee ?? this.dateArrivee,
      dateDepart: dateDepart ?? this.dateDepart,
      nbPersonnes: nbPersonnes ?? this.nbPersonnes,
      prixNuit: prixNuit ?? this.prixNuit,
      montantTotal: montantTotal ?? this.montantTotal,
      montantPaye: montantPaye ?? this.montantPaye,
      statut: statut ?? this.statut,
      note: note ?? this.note,
      motifAnnulation: motifAnnulation ?? this.motifAnnulation,
    );
  }
}

/// Une ligne de la facture de séjour (libellé + montant).
class LigneFactureSejour {
  const LigneFactureSejour(this.libelle, this.montant);

  final String libelle;
  final double montant;
}

/// Facture de séjour — document construit localement depuis [Reservation].
///
/// C'est un simple regroupement de lignes : nuits × prix, avance, reste.
class FactureSejour {
  const FactureSejour({
    required this.reference,
    required this.reservation,
    required this.lignes,
  });

  /// Référence imprimée « SÉJ-XXXXXXXX » (8 premiers caractères de l'id).
  final String reference;

  final Reservation reservation;
  final List<LigneFactureSejour> lignes;

  double get total => reservation.montantTotal;
  double get paye => reservation.montantPaye;
  double get solde => reservation.solde;

  factory FactureSejour.depuisReservation(Reservation reservation) {
    final String court = reservation.id.length >= 8
        ? reservation.id.substring(0, 8).toUpperCase()
        : reservation.id.toUpperCase();

    return FactureSejour(
      reference: 'SÉJ-$court',
      reservation: reservation,
      lignes: <LigneFactureSejour>[
        LigneFactureSejour(
          '${reservation.nuits} nuit${reservation.nuits > 1 ? 's' : ''} '
          '× ${reservation.prixNuit.toStringAsFixed(0)}',
          reservation.montantTotal,
        ),
      ],
    );
  }
}
