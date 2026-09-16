// lib/models/depense_finance.dart
//
// MODULE 10 — DÉPENSES (sorties de caisse).
//
// Les dépenses vivent dans `public.depenses` (colonnes legacy + `categorie`
// ajoutée par la migration du Module 10). La lecture passe par
// `rpc_depenses_liste`, l'écriture par `rpc_depense_creer` / `_supprimer`.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Une dépense de l'entreprise.
class DepenseFinance {
  const DepenseFinance({
    required this.id,
    required this.motif,
    required this.montant,
    this.categorie = 'autre',
    this.date,
  });

  final int id;
  final String motif;
  final double montant;
  final String categorie;
  final DateTime? date;

  factory DepenseFinance.depuisRpc(Map<String, dynamic> map) {
    return DepenseFinance(
      id: parseInt(map['depense_id']),
      motif: parseString(map['motif'], fallback: 'Dépense'),
      montant: parseDouble(map['montant']),
      categorie: parseString(map['categorie'], fallback: 'autre'),
      date: parseDateTimeOrNull(map['date']),
    );
  }
}

/// Totaux d'une liste de dépenses.
class ResumeDepenses {
  const ResumeDepenses({this.nb = 0, this.total = 0});

  final int nb;
  final double total;

  /// Dépense moyenne de la sélection — `0` si aucune ligne.
  double get moyenne => nb <= 0 ? 0 : total / nb;

  factory ResumeDepenses.depuisRpc(Map<String, dynamic> map) {
    return ResumeDepenses(
      nb: parseInt(map['nb']),
      total: parseDouble(map['total']),
    );
  }
}

/// Résultat de `rpc_depenses_liste` (lignes + totaux + catégories connues).
class ResultatListeDepenses {
  const ResultatListeDepenses({
    this.debut,
    this.fin,
    this.categorie,
    this.lignes = const <DepenseFinance>[],
    this.totaux = const ResumeDepenses(),
    this.categories = const <String>[],
  });

  final DateTime? debut;
  final DateTime? fin;
  final String? categorie;
  final List<DepenseFinance> lignes;
  final ResumeDepenses totaux;

  /// Toutes les catégories déjà utilisées par la boutique (filtre).
  final List<String> categories;

  factory ResultatListeDepenses.depuisRpc(Map<String, dynamic> map) {
    final List<String> categories = <String>[];
    for (final dynamic valeur in (map['categories'] as List<dynamic>? ??
        const <dynamic>[])) {
      final String texte = valeur?.toString().trim() ?? '';
      if (texte.isNotEmpty) categories.add(texte);
    }

    return ResultatListeDepenses(
      debut: parseDateTimeOrNull(map['debut']),
      fin: parseDateTimeOrNull(map['fin']),
      categorie: parseStringOrNull(map['categorie']),
      lignes: parseMapList(map['lignes'])
          .map(DepenseFinance.depuisRpc)
          .toList(growable: false),
      totaux:
          ResumeDepenses.depuisRpc(parseMap(map['totaux']) ?? <String, dynamic>{}),
      categories: categories,
    );
  }
}
