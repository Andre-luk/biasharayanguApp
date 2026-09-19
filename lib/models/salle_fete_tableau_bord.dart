// lib/models/salle_fete_tableau_bord.dart
//
// 🎉 MODULE 16 (phase C4) — SALLE DES FÊTES : TABLEAU DE BORD.
//
// Réponse de `rpc_salle_fetes_tableau_bord()` : nombre de salles,
// événements du jour et à venir, encaissé / solde, et les 5 prochains
// événements du calendrier.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Un événement du calendrier affiché sur le tableau de bord.
class EvenementProchain {
  const EvenementProchain({
    required this.id,
    required this.titre,
    required this.salle,
    required this.client,
    this.numero,
    this.dateDebut = '',
    this.dateFin = '',
    this.statut = 'reserve',
    this.montantTotal = 0,
    this.solde = 0,
  });

  final String id;
  final String? numero;
  final String titre;
  final String salle;
  final String client;

  /// Dates déjà formatées « JJ/MM/AAAA » par le serveur.
  final String dateDebut;
  final String dateFin;

  final String statut;
  final double montantTotal;
  final double solde;

  factory EvenementProchain.fromMap(Map<String, dynamic> map) {
    return EvenementProchain(
      id: parseString(map['id']),
      numero: parseStringOrNull(map['numero']),
      titre: parseString(map['titre'], fallback: 'Événement'),
      salle: parseString(map['salle'], fallback: 'Salle'),
      client: parseString(map['client'], fallback: 'Client'),
      dateDebut: parseString(map['date_debut']),
      dateFin: parseString(map['date_fin']),
      statut: parseString(map['statut'], fallback: 'reserve'),
      montantTotal: parseDouble(map['montant_total']),
      solde: parseDouble(map['solde']),
    );
  }
}

/// Calendrier & encaissements de la salle des fêtes.
class TableauBordSalleFete {
  const TableauBordSalleFete({
    this.sallesTotal = 0,
    this.sallesActives = 0,
    this.evenementsEnCours = 0,
    this.evenementsAVenir = 0,
    this.encaisse = 0,
    this.solde = 0,
    this.prochains = const <EvenementProchain>[],
  });

  final int sallesTotal;
  final int sallesActives;

  /// Événements dont la période couvre aujourd'hui (statut actif).
  final int evenementsEnCours;

  /// Événements dont la date de début est future.
  final int evenementsAVenir;

  /// Total encaissé sur les événements non annulés.
  final double encaisse;

  /// Solde restant à encaisser sur les événements non annulés.
  final double solde;

  final List<EvenementProchain> prochains;

  factory TableauBordSalleFete.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic>? salles = parseMap(map['salles']);
    return TableauBordSalleFete(
      sallesTotal: parseInt(salles?['total']),
      sallesActives: parseInt(salles?['actives']),
      evenementsEnCours: parseInt(map['evenements_en_cours']),
      evenementsAVenir: parseInt(map['evenements_a_venir']),
      encaisse: parseDouble(map['encaisse']),
      solde: parseDouble(map['solde']),
      prochains: _liste(map['prochains']),
    );
  }

  static List<EvenementProchain> _liste(dynamic valeur) {
    if (valeur is! List) return const <EvenementProchain>[];
    return valeur
        .whereType<Map>()
        .map((Map element) =>
            EvenementProchain.fromMap(Map<String, dynamic>.from(element)))
        .toList(growable: false);
  }
}
