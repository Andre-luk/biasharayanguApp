// lib/models/restaurant_tableau_bord.dart
//
// 🍽️ MODULE 16 (phase C3) — RESTAURANT : TABLEAU DE BORD DU SERVICE.
//
// Réponse de `rpc_restaurant_tableau_bord()` : occupation des tables et
// avancement des commandes (à envoyer, en cuisine, prêtes, servies).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Occupation des tables + état des commandes du service.
class RestaurantTableauBord {
  const RestaurantTableauBord({
    this.tablesTotal = 0,
    this.tablesLibres = 0,
    this.tablesOccupees = 0,
    this.tablesReservees = 0,
    this.commandesActives = 0,
    this.aEnvoyer = 0,
    this.enCuisine = 0,
    this.pretes = 0,
    this.servies = 0,
    this.montantActif = 0,
  });

  final int tablesTotal;
  final int tablesLibres;
  final int tablesOccupees;
  final int tablesReservees;

  /// Commandes ni encaissées ni annulées.
  final int commandesActives;

  /// Commandes en saisie (non encore envoyées en cuisine).
  final int aEnvoyer;

  /// Commandes envoyées ou en préparation.
  final int enCuisine;

  /// Commandes prêtes à servir.
  final int pretes;

  /// Commandes servies, en attente d'encaissement.
  final int servies;

  /// Montant total des commandes actives (chiffre en cours).
  final double montantActif;

  /// Charge de la cuisine (en préparation + prêtes).
  int get cuisineCount => enCuisine + pretes;

  factory RestaurantTableauBord.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic>? tables = parseMap(map['tables']);
    return RestaurantTableauBord(
      tablesTotal: parseInt(tables?['total']),
      tablesLibres: parseInt(tables?['libres']),
      tablesOccupees: parseInt(tables?['occupees']),
      tablesReservees: parseInt(tables?['reservees']),
      commandesActives: parseInt(map['commandes_actives']),
      aEnvoyer: parseInt(map['a_envoyer']),
      enCuisine: parseInt(map['en_cuisine']),
      pretes: parseInt(map['pretes']),
      servies: parseInt(map['servies']),
      montantActif: parseDouble(map['montant_actif']),
    );
  }
}
