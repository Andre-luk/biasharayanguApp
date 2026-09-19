// lib/models/statut_expiration.dart
//
// 🧩 MODULE 16 (phase C1) — PHARMACIE : STATUT D'EXPIRATION D'UN ARTICLE.
//
// Objet de valeur PUR (aucun accès réseau) : il classe un article selon sa
// date de péremption — expiré / expire bientôt (≤ 30 jours par défaut) /
// valide — et fournit le tri par urgence utilisé par l'écran « Expirations ».

import 'package:biashara_yangu/models/article.dart';

/// Statut d'expiration d'un article (par ordre d'urgence).
enum StatutExpiration {
  expire('expire', 'Expiré'),
  proche('proche', 'Expire bientôt'),
  valide('valide', 'Valide');

  const StatutExpiration(this.code, this.libelle);

  /// Code stocké/affiché (« expire », « proche », « valide »).
  final String code;

  /// Libellé français affiché à l'utilisateur.
  final String libelle;

  /// L'article demande une action (expiré ou bientôt périmé) ?
  bool get estUrgent => this != StatutExpiration.valide;

  /// Statut d'une date d'expiration — `null` si l'article n'a pas de date.
  ///
  /// [joursProches] : seuil « expire bientôt » (30 jours par défaut).
  /// [reference] : jour de référence (aujourd'hui par défaut — injecté en
  /// test).
  static StatutExpiration? depuis(
    DateTime? dateExpiration, {
    DateTime? reference,
    int joursProches = 30,
  }) {
    if (dateExpiration == null) return null;

    final DateTime expiration = _jour(dateExpiration);
    final DateTime ref = _jour(reference ?? DateTime.now());

    if (expiration.isBefore(ref)) return StatutExpiration.expire;
    if (expiration.difference(ref).inDays <= joursProches) {
      return StatutExpiration.proche;
    }
    return StatutExpiration.valide;
  }

  /// Jours restants avant l'expiration (négatif si déjà expiré) —
  /// `null` si l'article n'a pas de date.
  static int? joursRestants(DateTime? dateExpiration, {DateTime? reference}) {
    if (dateExpiration == null) return null;

    final DateTime expiration = _jour(dateExpiration);
    final DateTime ref = _jour(reference ?? DateTime.now());
    return expiration.difference(ref).inDays;
  }

  /// Libellé lisible des jours restants : « Expiré depuis 3 j », « Aujourd'hui »,
  /// « Dans 12 j »…
  static String libelleJours(int? jours) {
    if (jours == null) return '—';
    if (jours < 0) {
      final int retard = -jours;
      return 'Expiré depuis $retard j';
    }
    if (jours == 0) return "Expire aujourd'hui";
    if (jours == 1) return 'Expire demain';
    return 'Dans $jours j';
  }

  /// Articles triés par urgence d'expiration (expirés d'abord puis les plus
  /// proches). Les articles sans date sont placés en fin, par nom.
  static List<Article> trierParUrgence(
    List<Article> articles, {
    DateTime? reference,
    int joursProches = 30,
  }) {
    final List<Article> tries = List<Article>.of(articles);
    tries.sort((Article a, Article b) {
      final StatutExpiration? sa = depuis(a.dateExpiration,
          reference: reference, joursProches: joursProches);
      final StatutExpiration? sb = depuis(b.dateExpiration,
          reference: reference, joursProches: joursProches);

      // Sans date : en dernier.
      if (sa == null && sb == null) return a.nom.compareTo(b.nom);
      if (sa == null) return 1;
      if (sb == null) return -1;

      // Date la plus urgente d'abord (expirés puis proches puis valides).
      final int cmp = a.dateExpiration!.compareTo(b.dateExpiration!);
      if (cmp != 0) return cmp;
      return a.nom.compareTo(b.nom);
    });
    return tries;
  }

  /// Normalise une date en « jour » (minuit) — évite les écarts d'heures.
  static DateTime _jour(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
