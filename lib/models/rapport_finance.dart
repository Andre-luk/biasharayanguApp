// lib/models/rapport_finance.dart
//
// MODULE 10 — RAPPORTS FINANCIERS.
//
// `rpc_finance_rapport` renvoie des lignes dont la forme dépend du groupe :
//
//   • article           : produit_id, nom, quantite, ca, cout, marge ;
//   • vendeur           : seller_id, nom, nb_ventes, ca ;
//   • mode              : mode, nb_ventes, ca ;
//   • categorie_depense : categorie, nb, montant ;
//   • jour              : jour, chiffre_affaires, cout_marchandises,
//                         depenses, benefice_net, nb_ventes.
//
// [LigneRapportFinance] normalise ces différences : `montant` porte le
// chiffre d'affaires (ou le montant dépensé), les autres champs sont
// optionnels.

import 'package:biashara_yangu/models/finance_stats.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Axe d'analyse d'un rapport financier.
enum GroupeRapportFinance {
  article('article', 'Articles'),
  vendeur('vendeur', 'Vendeurs'),
  mode('mode', 'Modes de paiement'),
  categorieDepense('categorie_depense', 'Catégories de dépenses'),
  jour('jour', 'Par jour');

  const GroupeRapportFinance(this.code, this.libelle);

  final String code;
  final String libelle;
}

/// Une ligne de rapport, tous groupes confondus.
class LigneRapportFinance {
  const LigneRapportFinance({
    required this.cle,
    required this.libelle,
    this.montant = 0,
    this.nb,
    this.quantite,
    this.cout,
    this.marge,
    this.depenses,
    this.beneficeNet,
  });

  /// Clé technique (id produit, id vendeur, code mode, catégorie, jour ISO).
  final String cle;
  final String libelle;

  /// Chiffre d'affaires (ou montant des dépenses pour les catégories).
  final double montant;

  /// Nombre de ventes (ou de dépenses selon le groupe).
  final int? nb;
  final double? quantite;
  final double? cout;
  final double? marge;
  final double? depenses;

  /// Renseigné pour le groupe « jour ».
  final double? beneficeNet;

  /// Part de cette ligne dans [total] (0…1), utilisée par les barres.
  double part(double total) => total <= 0 ? 0 : montant / total;

  factory LigneRapportFinance.depuisRpc(
    GroupeRapportFinance groupe,
    Map<String, dynamic> map,
  ) {
    switch (groupe) {
      case GroupeRapportFinance.article:
        return LigneRapportFinance(
          cle: parseString(map['produit_id']),
          libelle: parseString(map['nom'], fallback: 'Article'),
          montant: parseDouble(map['ca']),
          quantite: parseDouble(map['quantite']),
          cout: parseDouble(map['cout']),
          marge: parseDouble(map['marge']),
        );
      case GroupeRapportFinance.vendeur:
        final String? sellerId = parseStringOrNull(map['seller_id']);
        return LigneRapportFinance(
          cle: sellerId ?? 'non-attribue',
          libelle: parseString(map['nom'], fallback: 'Vendeur non attribué'),
          montant: parseDouble(map['ca']),
          nb: parseInt(map['nb_ventes']),
        );
      case GroupeRapportFinance.mode:
        final String mode = parseString(map['mode'], fallback: 'especes');
        return LigneRapportFinance(
          cle: mode,
          libelle: mode,
          montant: parseDouble(map['ca']),
          nb: parseInt(map['nb_ventes']),
        );
      case GroupeRapportFinance.categorieDepense:
        final String categorie =
            parseString(map['categorie'], fallback: 'autre');
        return LigneRapportFinance(
          cle: categorie,
          libelle: categorie,
          montant: parseDouble(map['montant']),
          nb: parseInt(map['nb']),
        );
      case GroupeRapportFinance.jour:
        final String jour = parseString(map['jour']);
        return LigneRapportFinance(
          cle: jour,
          libelle: jour,
          montant: parseDouble(map['chiffre_affaires']),
          nb: parseInt(map['nb_ventes']),
          cout: parseDouble(map['cout_marchandises']),
          depenses: parseDouble(map['depenses']),
          beneficeNet: parseDouble(map['benefice_net']),
        );
    }
  }
}

/// Rapport complet renvoyé par `rpc_finance_rapport`.
class RapportFinance {
  const RapportFinance({
    required this.groupe,
    this.debut,
    this.fin,
    this.lignes = const <LigneRapportFinance>[],
    this.totaux = StatsPeriode.vide,
  });

  final GroupeRapportFinance groupe;
  final DateTime? debut;
  final DateTime? fin;
  final List<LigneRapportFinance> lignes;
  final StatsPeriode totaux;

  /// Somme des montants des lignes (pour les barres de proportion).
  double get totalLignes => lignes.fold<double>(
        0,
        (double somme, LigneRapportFinance ligne) => somme + ligne.montant,
      );

  factory RapportFinance.depuisRpc(
    GroupeRapportFinance groupe,
    Map<String, dynamic> map,
  ) {
    return RapportFinance(
      groupe: groupe,
      debut: parseDateTimeOrNull(map['debut']),
      fin: parseDateTimeOrNull(map['fin']),
      lignes: parseMapList(map['lignes'])
          .map((Map<String, dynamic> ligne) =>
              LigneRapportFinance.depuisRpc(groupe, ligne))
          .toList(growable: false),
      totaux: StatsPeriode.depuisRpc(
          parseMap(map['totaux']) ?? <String, dynamic>{}),
    );
  }
}
