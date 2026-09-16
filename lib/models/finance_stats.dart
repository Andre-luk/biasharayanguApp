// lib/models/finance_stats.dart
//
// MODULE 10 — FINANCE DE L'ENTREPRISE : statistiques pures.
//
// Ces objets sont construits depuis les réponses jsonb des RPC
// `rpc_finance_tableau_bord` et `rpc_finance_rapport`. Aucun accès réseau :
// le parsing est tolérant (un nombre PostgreSQL peut arriver en `int` comme
// en `double`, cf. `utils/json_parsing.dart`).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Statistiques financières d'une période (jour, semaine, mois…).
class StatsPeriode {
  const StatsPeriode({
    this.debut,
    this.fin,
    this.chiffreAffaires = 0,
    this.coutMarchandises = 0,
    this.margeBrute = 0,
    this.depenses = 0,
    this.beneficeNet = 0,
    this.nbVentes = 0,
    this.nbDepenses = 0,
  });

  final DateTime? debut;
  final DateTime? fin;

  /// Total des ventes de la période (ventes à crédit comprises).
  final double chiffreAffaires;

  /// Coût d'achat des marchandises vendues (`produits.prix_achat`).
  final double coutMarchandises;

  /// `chiffreAffaires − coutMarchandises`.
  final double margeBrute;

  /// Dépenses de la période.
  final double depenses;

  /// `margeBrute − depenses`.
  final double beneficeNet;

  final int nbVentes;
  final int nbDepenses;

  /// Taux de marge en pourcentage — `0` si le chiffre d'affaires est nul.
  double get tauxMarge =>
      chiffreAffaires <= 0 ? 0 : (margeBrute / chiffreAffaires) * 100;

  /// Période vide (utilisée en attendant la réponse du serveur).
  static const StatsPeriode vide = StatsPeriode();

  factory StatsPeriode.depuisRpc(Map<String, dynamic> map) {
    return StatsPeriode(
      debut: parseDateTimeOrNull(map['debut']),
      fin: parseDateTimeOrNull(map['fin']),
      chiffreAffaires: parseDouble(map['chiffre_affaires']),
      coutMarchandises: parseDouble(map['cout_marchandises']),
      margeBrute: parseDouble(map['marge_brute']),
      depenses: parseDouble(map['depenses']),
      beneficeNet: parseDouble(map['benefice_net']),
      nbVentes: parseInt(map['nb_ventes']),
      nbDepenses: parseInt(map['nb_depenses']),
    );
  }
}

/// Un point d'une série quotidienne (graphiques 7 / 30 jours).
class PointSerieFinance {
  const PointSerieFinance({
    required this.jour,
    this.chiffreAffaires = 0,
    this.coutMarchandises = 0,
    this.depenses = 0,
    this.beneficeNet = 0,
    this.nbVentes = 0,
  });

  final DateTime? jour;
  final double chiffreAffaires;
  final double coutMarchandises;
  final double depenses;
  final double beneficeNet;
  final int nbVentes;

  factory PointSerieFinance.depuisRpc(Map<String, dynamic> map) {
    return PointSerieFinance(
      jour: parseDateTimeOrNull(map['jour']),
      chiffreAffaires: parseDouble(map['chiffre_affaires']),
      coutMarchandises: parseDouble(map['cout_marchandises']),
      depenses: parseDouble(map['depenses']),
      beneficeNet: parseDouble(map['benefice_net']),
      nbVentes: parseInt(map['nb_ventes']),
    );
  }

  /// Convertit la liste jsonb des séries en liste d'objets.
  static List<PointSerieFinance> listeDepuisRpc(dynamic data) => parseMapList(data)
      .map(PointSerieFinance.depuisRpc)
      .toList(growable: false);
}

/// Un article du « top 5 » des 30 derniers jours.
class ArticleTopFinance {
  const ArticleTopFinance({
    required this.produitId,
    required this.nom,
    required this.quantite,
    required this.ca,
    required this.marge,
  });

  final int produitId;
  final String nom;
  final double quantite;
  final double ca;
  final double marge;

  factory ArticleTopFinance.depuisRpc(Map<String, dynamic> map) {
    return ArticleTopFinance(
      produitId: parseInt(map['produit_id']),
      nom: parseString(map['nom'], fallback: 'Article'),
      quantite: parseDouble(map['quantite']),
      ca: parseDouble(map['ca']),
      marge: parseDouble(map['marge']),
    );
  }
}

/// Tableau de bord complet renvoyé par `rpc_finance_tableau_bord`.
class TableauBordFinance {
  const TableauBordFinance({
    this.reference,
    this.jour = StatsPeriode.vide,
    this.semaine = StatsPeriode.vide,
    this.mois = StatsPeriode.vide,
    this.series7 = const <PointSerieFinance>[],
    this.series30 = const <PointSerieFinance>[],
    this.topArticles = const <ArticleTopFinance>[],
  });

  final DateTime? reference;
  final StatsPeriode jour;
  final StatsPeriode semaine;
  final StatsPeriode mois;
  final List<PointSerieFinance> series7;
  final List<PointSerieFinance> series30;
  final List<ArticleTopFinance> topArticles;

  factory TableauBordFinance.depuisRpc(Map<String, dynamic> map) {
    return TableauBordFinance(
      reference: parseDateTimeOrNull(map['ref']),
      jour: StatsPeriode.depuisRpc(parseMap(map['jour']) ?? <String, dynamic>{}),
      semaine:
          StatsPeriode.depuisRpc(parseMap(map['semaine']) ?? <String, dynamic>{}),
      mois: StatsPeriode.depuisRpc(parseMap(map['mois']) ?? <String, dynamic>{}),
      series7: PointSerieFinance.listeDepuisRpc(map['series_7']),
      series30: PointSerieFinance.listeDepuisRpc(map['series_30']),
      topArticles: parseMapList(map['top_articles'])
          .map(ArticleTopFinance.depuisRpc)
          .toList(growable: false),
    );
  }
}
