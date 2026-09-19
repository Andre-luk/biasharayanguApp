// lib/models/evenement.dart
//
// 🎉 MODULE 16 (phase C4) — SALLE DES FÊTES : ÉVÉNEMENT & PRESTATIONS.
//
// Cycle : reserve → confirme → en_cours → termine ; ou annule.
// `montant_total` = prix de la salle (prix/jour × jours, figé à la
// création) + prestations (traiteur, décoration…) ; `montant_paye` suit
// les avances et les soldes encaissés.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Statut d'un événement (table `public.evenements`).
enum StatutEvenement {
  reserve('reserve', 'Réservé'),
  confirme('confirme', 'Confirmé'),
  enCours('en_cours', 'En cours'),
  termine('termine', 'Terminé'),
  annule('annule', 'Annulé');

  const StatutEvenement(this.code, this.libelle);

  final String code;
  final String libelle;

  /// L'événement occupe encore la salle (réservation vivante).
  bool get occupeLaSalle =>
      this == StatutEvenement.reserve ||
      this == StatutEvenement.confirme ||
      this == StatutEvenement.enCours;

  /// L'événement est clos (plus de modification possible).
  bool get estClos =>
      this == StatutEvenement.termine || this == StatutEvenement.annule;

  static StatutEvenement fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final StatutEvenement statut in values) {
      if (statut.code == normalise) return statut;
    }
    return StatutEvenement.reserve;
  }
}

/// Une prestation d'événement — table `public.lignes_evenement`.
class LigneEvenement {
  const LigneEvenement({
    required this.id,
    required this.libelle,
    this.quantite = 1,
    this.prixUnitaire = 0,
    this.total = 0,
  });

  final String id;

  /// Prestation saisie librement (« Traiteur », « Décoration »…).
  final String libelle;

  final double quantite;
  final double prixUnitaire;
  final double total;

  factory LigneEvenement.fromMap(Map<String, dynamic> map) {
    return LigneEvenement(
      id: parseString(map['id']),
      libelle: parseString(map['libelle'], fallback: 'Prestation'),
      quantite: parseDouble(map['quantite'], fallback: 1),
      prixUnitaire: parseDouble(map['prix_unitaire']),
      total: parseDouble(map['total']),
    );
  }
}

/// Un événement — table `public.evenements`.
class Evenement {
  const Evenement({
    required this.id,
    required this.salleId,
    required this.titre,
    required this.clientNom,
    required this.dateDebut,
    required this.dateFin,
    this.salleNom = '',
    this.numero,
    this.typeEvenement,
    this.clientId,
    this.telephone,
    this.heureDebut,
    this.heureFin,
    this.nbInvites = 0,
    this.prixJour = 0,
    this.montantSalle = 0,
    this.montantTotal = 0,
    this.montantPaye = 0,
    this.statut = StatutEvenement.reserve,
    this.note,
    this.motifAnnulation,
    this.createdAt,
    this.lignes = const <LigneEvenement>[],
  });

  final String id;
  final String salleId;

  /// Nom de la salle (rempli par la jointure de lecture).
  final String salleNom;

  /// Numéro journalier « EVT-AAAAMMJJ-0001 ».
  final String? numero;

  final String titre;

  /// Type libre : mariage, anniversaire, réunion…
  final String? typeEvenement;

  final int? clientId;
  final String clientNom;
  final String? telephone;

  /// Dates `date` (sans heure), formatées côté serveur ou parsées localement.
  final DateTime? dateDebut;
  final DateTime? dateFin;

  /// Heures libres (« 14:00 »).
  final String? heureDebut;
  final String? heureFin;

  final int nbInvites;

  /// Prix par jour NÉGOCIÉ (figé sur l'événement).
  final double prixJour;

  /// Part « salle » (prix/jour × jours).
  final double montantSalle;

  /// Salle + prestations.
  final double montantTotal;

  /// Total encaissé (avances + soldes).
  final double montantPaye;

  final StatutEvenement statut;
  final String? note;
  final String? motifAnnulation;
  final DateTime? createdAt;

  /// Prestations (remplies par la lecture avec jointure).
  final List<LigneEvenement> lignes;

  /// Nombre de jours (bornes incluses).
  int get nbJours {
    final DateTime? debut = dateDebut;
    final DateTime? fin = dateFin;
    if (debut == null || fin == null) return 1;
    return fin.difference(debut).inDays + 1;
  }

  /// Solde restant à encaisser.
  double get solde => (montantTotal - montantPaye).clamp(0, double.infinity);

  /// L'événement est-il soldé ?
  bool get estSolde => solde <= 0.005;

  /// L'événement se déroule-t-il aujourd'hui ?
  bool enCoursAujourdhui(DateTime jour) {
    final DateTime? debut = dateDebut;
    final DateTime? fin = dateFin;
    if (debut == null || fin == null) return false;
    final DateTime d = DateTime(jour.year, jour.month, jour.day);
    final DateTime d0 = DateTime(debut.year, debut.month, debut.day);
    final DateTime d1 = DateTime(fin.year, fin.month, fin.day);
    return !d.isBefore(d0) && !d.isAfter(d1);
  }

  /// Résumé court des prestations (« Traiteur, Décoration »).
  String get resumePrestations {
    if (lignes.isEmpty) return 'Aucune prestation';
    return lignes.map((LigneEvenement l) => l.libelle).join(', ');
  }

  factory Evenement.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic>? salle = parseMap(map['salles']);
    return Evenement(
      id: parseString(map['id']),
      salleId: parseString(map['salle_id']),
      salleNom: salle == null
          ? parseString(map['salle_nom'])
          : parseString(salle['nom']),
      numero: parseStringOrNull(map['numero']),
      titre: parseString(map['titre'], fallback: 'Événement'),
      typeEvenement: parseStringOrNull(map['type_evenement']),
      clientId: map['client_id'] == null ? null : parseInt(map['client_id']),
      clientNom: parseString(map['client_nom'], fallback: 'Client'),
      telephone: parseStringOrNull(map['telephone']),
      dateDebut: _date(map['date_debut']),
      dateFin: _date(map['date_fin']),
      heureDebut: parseStringOrNull(map['heure_debut']),
      heureFin: parseStringOrNull(map['heure_fin']),
      nbInvites: parseInt(map['nb_invites']),
      prixJour: parseDouble(map['prix_jour']),
      montantSalle: parseDouble(map['montant_salle']),
      montantTotal: parseDouble(map['montant_total']),
      montantPaye: parseDouble(map['montant_paye']),
      statut: StatutEvenement.fromCode(parseString(map['statut'])),
      note: parseStringOrNull(map['note']),
      motifAnnulation: parseStringOrNull(map['motif_annulation']),
      createdAt: parseDateTimeOrNull(map['created_at']),
      lignes: _lignes(map['lignes_evenement']),
    );
  }

  Evenement copyWith({
    StatutEvenement? statut,
    double? montantTotal,
    double? montantPaye,
    List<LigneEvenement>? lignes,
  }) {
    return Evenement(
      id: id,
      salleId: salleId,
      salleNom: salleNom,
      numero: numero,
      titre: titre,
      typeEvenement: typeEvenement,
      clientId: clientId,
      clientNom: clientNom,
      telephone: telephone,
      dateDebut: dateDebut,
      dateFin: dateFin,
      heureDebut: heureDebut,
      heureFin: heureFin,
      nbInvites: nbInvites,
      prixJour: prixJour,
      montantSalle: montantSalle,
      montantTotal: montantTotal ?? this.montantTotal,
      montantPaye: montantPaye ?? this.montantPaye,
      statut: statut ?? this.statut,
      note: note,
      motifAnnulation: motifAnnulation,
      createdAt: createdAt,
      lignes: lignes ?? this.lignes,
    );
  }

  static DateTime? _date(dynamic valeur) {
    final String brut = parseString(valeur);
    if (brut.isEmpty) return null;
    return DateTime.tryParse(brut);
  }

  static List<LigneEvenement> _lignes(dynamic valeur) {
    if (valeur is! List) return const <LigneEvenement>[];
    return valeur
        .whereType<Map>()
        .map((Map element) =>
            LigneEvenement.fromMap(Map<String, dynamic>.from(element)))
        .toList(growable: false);
  }

  /// Date affichée « JJ/MM/AAAA » (ou « — »).
  static String dateCourte(DateTime? date) {
    if (date == null) return '—';
    final String jour = date.day.toString().padLeft(2, '0');
    final String mois = date.month.toString().padLeft(2, '0');
    return '$jour/$mois/${date.year}';
  }

  /// Période affichée (« 12/10/2026 » ou « 12/10/2026 → 13/10/2026 »).
  String get periode {
    final String debut = dateCourte(dateDebut);
    final String fin = dateCourte(dateFin);
    return debut == fin ? debut : '$debut → $fin';
  }
}
