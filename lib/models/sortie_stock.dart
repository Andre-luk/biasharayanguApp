// lib/models/sortie_stock.dart
//
// 📦 MODULE 9 — LES SORTIES DE STOCK SPÉCIALES.
//
// Une VENTE n'est pas la seule façon dont un article quitte le stock :
//   • le propriétaire consomme son propre article ;
//   • un article est offert (« goffre ») ;
//   • une bouteille est cassée, un produit est périmé, un article est perdu ;
//   • une marchandise retourne au fournisseur ;
//   • un article sert d'ingrédient à une fabrication interne.
//
// Dans TOUS ces cas le stock doit diminuer et AUCUN argent ne doit entrer en
// caisse. C'est exactement ce que ce modèle décrit.
//
// ⚠️ La sortie n'est jamais un texte libre : le motif est un CODE stable
//    (`consommation_proprietaire`, `offert`, `perte`…). Les rapports et les
//    totaux ne dépendent donc pas de l'orthographe de celui qui saisit.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Motif d'une sortie de stock non commerciale.
///
/// L'ordre de déclaration est celui proposé à l'utilisateur : d'abord les cas
/// du quotidien (consommation, offert), puis les accidents (perte, casse,
/// péremption), puis les cas comptables (retour fournisseur, usage interne).
enum MotifSortieStock {
  consommationProprietaire(
    'consommation_proprietaire',
    'Consommation du propriétaire',
    "Le patron (ou sa famille) consomme l'article de sa propre boutique.",
    Icons.person_outline,
  ),
  offert(
    'offert',
    'Offert / échantillon (goffre)',
    'Article donné gratuitement à un client, à un prospect ou en promotion.',
    Icons.redeem_outlined,
  ),
  perte(
    'perte',
    'Perte ou vol',
    "L'article a disparu : vol, erreur de livraison, disparition constatée.",
    Icons.search_off_rounded,
  ),
  casse(
    'casse',
    'Casse',
    'Article cassé, renversé ou rendu inutilisable.',
    Icons.broken_image_outlined,
  ),
  peremption(
    'peremption',
    'Périmé',
    'Produit arrivé à expiration, retiré de la vente.',
    Icons.event_busy_outlined,
  ),
  retourFournisseur(
    'retour_fournisseur',
    'Retour au fournisseur',
    'Marchandise renvoyée au fournisseur (défaut, invendu, échange).',
    Icons.local_shipping_outlined,
  ),
  usageInterne(
    'usage_interne',
    'Usage interne / fabrication',
    'Article consommé pour fabriquer un autre produit ou pour le service.',
    Icons.settings_outlined,
  ),
  autre(
    'autre',
    'Autre motif',
    'Tout autre cas : précisez dans la note.',
    Icons.more_horiz_rounded,
  );

  const MotifSortieStock(this.code, this.libelle, this.explication, this.icone);

  /// Code envoyé au serveur (jamais traduit).
  final String code;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// Explication d'une ligne, affichée sous le choix du motif.
  final String explication;

  final IconData icone;

  /// Vrai pour les motifs qui correspondent à une PERTE de valeur.
  bool get estUnePerte =>
      this == MotifSortieStock.perte ||
      this == MotifSortieStock.casse ||
      this == MotifSortieStock.peremption;

  /// Libellé d'un code tel qu'il vient du serveur.
  static String libelleDe(String? code) {
    final String propre = (code ?? '').trim();
    for (final MotifSortieStock motif in MotifSortieStock.values) {
      if (motif.code == propre) return motif.libelle;
    }
    return propre.isEmpty ? 'Motif inconnu' : propre;
  }

  /// Icône d'un code tel qu'il vient du serveur.
  static IconData iconeDe(String? code) {
    final String propre = (code ?? '').trim();
    for (final MotifSortieStock motif in MotifSortieStock.values) {
      if (motif.code == propre) return motif.icone;
    }
    return Icons.more_horiz_rounded;
  }

  /// Retrouve le motif correspondant à un code (ou `autre`).
  static MotifSortieStock depuisCode(String? code) {
    final String propre = (code ?? '').trim();
    for (final MotifSortieStock motif in MotifSortieStock.values) {
      if (motif.code == propre) return motif;
    }
    return MotifSortieStock.autre;
  }
}

/// Une sortie de stock enregistrée (une ligne de l'historique / du rapport).
class SortieStock {
  const SortieStock({
    required this.id,
    required this.produitId,
    required this.produit,
    required this.unite,
    required this.quantite,
    required this.motif,
    required this.valeurUnitaire,
    required this.valeurTotale,
    this.note,
    this.date,
  });

  final int id;
  final int produitId;
  final String produit;
  final String unite;
  final double quantite;

  /// Code du motif (`consommation_proprietaire`, `offert`…).
  final String motif;

  final String? note;
  final double valeurUnitaire;
  final double valeurTotale;
  final DateTime? date;

  String get libelleMotif => MotifSortieStock.libelleDe(motif);

  IconData get iconeMotif => MotifSortieStock.iconeDe(motif);

  factory SortieStock.fromMap(Map<String, dynamic> map) {
    return SortieStock(
      id: parseInt(map['id'] ?? map['sortie_id']),
      produitId: parseInt(map['produit_id']),
      produit: parseString(map['produit'], fallback: 'Article'),
      unite: parseString(map['unite'], fallback: 'unité'),
      quantite: parseDouble(map['quantite']),
      motif: parseString(map['motif'], fallback: 'autre'),
      note: parseStringOrNull(map['note']),
      valeurUnitaire: parseDouble(map['valeur_unitaire']),
      valeurTotale: parseDouble(map['valeur_totale']),
      date: parseDateTimeOrNull(map['date']),
    );
  }
}

/// Total d'un motif (nombre de sorties + valeur).
class TotalMotifSortie {
  const TotalMotifSortie({
    required this.code,
    required this.nb,
    required this.valeur,
  });

  /// Code du motif (`consommation_proprietaire`, `offert`…).
  final String code;

  final int nb;
  final double valeur;

  String get libelle => MotifSortieStock.libelleDe(code);

  IconData get icone => MotifSortieStock.iconeDe(code);
}

/// Résultat d'une enquête sur les sorties d'une période.
class ResumeSortiesStock {
  const ResumeSortiesStock({
    required this.lignes,
    required this.nb,
    required this.valeur,
    required this.parMotif,
    this.debut,
    this.fin,
  });

  final List<SortieStock> lignes;
  final int nb;
  final double valeur;

  /// Détail par CODE de motif.
  final Map<String, TotalMotifSortie> parMotif;

  final DateTime? debut;
  final DateTime? fin;

  bool get estVide => lignes.isEmpty;

  /// Les motifs réellement présents, du plus coûteux au moins coûteux.
  List<MapEntry<String, TotalMotifSortie>> get motifsTries {
    final List<MapEntry<String, TotalMotifSortie>> entrees =
        parMotif.entries.toList();
    entrees.sort((MapEntry<String, TotalMotifSortie> a,
            MapEntry<String, TotalMotifSortie> b) =>
        b.value.valeur.compareTo(a.value.valeur));
    return entrees;
  }

  factory ResumeSortiesStock.fromRpc(Map<String, dynamic> map) {
    final List<SortieStock> lignes = parseMapList(map['lignes'])
        .map(SortieStock.fromMap)
        .toList(growable: false);

    final Map<String, dynamic> totaux =
        parseMap(map['totaux']) ?? const <String, dynamic>{};
    final Map<String, TotalMotifSortie> parMotif =
        <String, TotalMotifSortie>{};
    final Map<String, dynamic> motifs =
        parseMap(totaux['par_motif']) ?? const <String, dynamic>{};
    motifs.forEach((String code, dynamic valeur) {
      final Map<String, dynamic> details =
          parseMap(valeur) ?? const <String, dynamic>{};
      parMotif[code] = TotalMotifSortie(
        code: code,
        nb: parseInt(details['nb']),
        valeur: parseDouble(details['valeur']),
      );
    });

    return ResumeSortiesStock(
      lignes: lignes,
      nb: parseInt(totaux['nb'], fallback: lignes.length),
      valeur: parseDouble(totaux['valeur']),
      parMotif: parMotif,
      debut: parseDateTimeOrNull(map['debut']),
      fin: parseDateTimeOrNull(map['fin']),
    );
  }
}

/// Récapitulatif renvoyé juste après l'enregistrement d'une sortie.
class ResultatSortieStock {
  const ResultatSortieStock({
    required this.id,
    required this.produitId,
    required this.nom,
    required this.unite,
    required this.quantite,
    required this.motif,
    required this.valeurUnitaire,
    required this.valeurTotale,
    required this.stockAvant,
    required this.stockApres,
    this.note,
    this.date,
  });

  final int id;
  final int produitId;
  final String nom;
  final String unite;
  final double quantite;
  final String motif;
  final String? note;
  final double valeurUnitaire;
  final double valeurTotale;
  final double stockAvant;
  final double stockApres;
  final DateTime? date;

  factory ResultatSortieStock.fromRpc(Map<String, dynamic> map) {
    return ResultatSortieStock(
      id: parseInt(map['sortie_id'] ?? map['id']),
      produitId: parseInt(map['produit_id']),
      nom: parseString(map['nom']),
      unite: parseString(map['unite'], fallback: 'unité'),
      quantite: parseDouble(map['quantite']),
      motif: parseString(map['motif'], fallback: 'autre'),
      note: parseStringOrNull(map['note']),
      valeurUnitaire: parseDouble(map['valeur_unitaire']),
      valeurTotale: parseDouble(map['valeur_totale']),
      stockAvant: parseDouble(map['stock_avant']),
      stockApres: parseDouble(map['stock_apres']),
      date: parseDateTimeOrNull(map['date']),
    );
  }
}
