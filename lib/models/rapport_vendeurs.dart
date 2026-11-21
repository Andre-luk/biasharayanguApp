// lib/models/rapport_vendeurs.dart
//
// 🧑‍🤝‍🧑 CORRECTIF 179 — RAPPORT PAR COLLABORATEUR (VENDEUR).
//
// Besoin exprimé par l'utilisateur :
//
//   « j'ai 5 beignets ; le collaborateur A en vend 1 → il reste 4 ; le
//     collaborateur B vient et en vend 1. Le rapport de B doit montrer
//     qu'il restait 4 beignets, et que c'est A qui avait vendu. »
//
// Le calcul du stock est fait PAR LE SERVEUR (`rpc_rapport_vendeurs`) : il
// possède l'historique complet des mouvements (ventes, approvisionnements,
// ajustements, sorties). L'application ne reconstitue donc jamais un stock
// « à la main » — elle affiche ce que la base a calculé.
//
// Chaque vente porte :
//   • `stockAvant` / `stockApres`  → le stock au moment EXACT de la vente ;
//   • `venduAvantPar`              → qui a vendu l'unité précédente du même
//                                    article (chaîne de traçabilité).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Une vente du journal, avec l'état du stock à cet instant.
class JournalVenteVendeur {
  const JournalVenteVendeur({
    required this.date,
    required this.produit,
    required this.quantite,
    required this.prix,
    this.vendeur,
    this.stockAvant,
    this.stockApres,
    this.venduAvantPar,
  });

  /// Date locale de la vente (le serveur renvoie déjà l'heure de Lubumbashi).
  final DateTime? date;
  final String produit;
  final double quantite;
  final double prix;
  final String? vendeur;

  /// Stock restant AVANT la vente (`null` si l'article n'existe plus).
  final double? stockAvant;

  /// Stock restant APRÈS la vente.
  final double? stockApres;

  /// Nom du vendeur de l'unité précédente du même article.
  final String? venduAvantPar;

  /// Le stock est-il connu ? (article supprimé → inconnu)
  bool get stockConnu => stockApres != null;

  factory JournalVenteVendeur.fromMap(Map<String, dynamic> map) {
    return JournalVenteVendeur(
      date: parseDateTimeOrNull(map['date']),
      produit: parseString(map['produit'], fallback: 'Article'),
      quantite: parseDouble(map['quantite']),
      prix: parseDouble(map['prix']),
      vendeur: parseStringOrNull(map['vendeur']),
      stockAvant: parseDoubleOrNull(map['stock_avant']),
      stockApres: parseDoubleOrNull(map['stock_apres']),
      venduAvantPar: parseStringOrNull(map['vendu_avant_par']),
    );
  }
}

/// Ce qu'un vendeur a vendu d'un article.
class ProduitVendeur {
  const ProduitVendeur({
    required this.nom,
    required this.quantite,
    required this.ca,
  });

  final String nom;
  final double quantite;
  final double ca;

  factory ProduitVendeur.fromMap(Map<String, dynamic> map) {
    return ProduitVendeur(
      nom: parseString(map['nom'], fallback: 'Article'),
      quantite: parseDouble(map['quantite']),
      ca: parseDouble(map['ca']),
    );
  }
}

/// Le rapport d'UN collaborateur.
class VendeurRapport {
  const VendeurRapport({
    required this.id,
    required this.nom,
    required this.ventes,
    required this.quantite,
    required this.ca,
    required this.panierMoyen,
    this.premier,
    this.dernier,
    this.produits = const <ProduitVendeur>[],
    this.journal = const <JournalVenteVendeur>[],
  });

  /// Identifiant du compte vendeur (`proprietaire` pour le patron).
  final String id;
  final String nom;
  final int ventes;
  final double quantite;
  final double ca;
  final double panierMoyen;
  final DateTime? premier;
  final DateTime? dernier;
  final List<ProduitVendeur> produits;
  final List<JournalVenteVendeur> journal;

  /// Stock restant après la DERNIÈRE vente de ce vendeur : permet de voir
  /// d'un coup d'œil « il restait 4 » sans ouvrir le journal.
  double? get stockApresDerniereVente {
    for (int i = journal.length - 1; i >= 0; i--) {
      final double? stock = journal[i].stockApres;
      if (stock != null) return stock;
    }
    return null;
  }

  factory VendeurRapport.fromMap(Map<String, dynamic> map) {
    return VendeurRapport(
      id: parseString(map['id'], fallback: 'proprietaire'),
      nom: parseString(map['nom'], fallback: 'Vendeur'),
      ventes: parseInt(map['ventes']),
      quantite: parseDouble(map['quantite']),
      ca: parseDouble(map['ca']),
      panierMoyen: parseDouble(map['panier_moyen']),
      premier: parseDateTimeOrNull(map['premier']),
      dernier: parseDateTimeOrNull(map['dernier']),
      produits: parseMapList(map['produits'])
          .map(ProduitVendeur.fromMap)
          .toList(growable: false),
      journal: parseMapList(map['journal'])
          .map(JournalVenteVendeur.fromMap)
          .toList(growable: false),
    );
  }
}

/// L'état du stock d'un article sur la période.
class ProduitStockRapport {
  const ProduitStockRapport({
    required this.nom,
    required this.vendu,
    required this.ca,
    this.produitId,
    this.stockActuel,
    this.stockDebut,
  });

  final String nom;
  final String? produitId;

  /// Stock aujourd'hui (`null` si l'article a été supprimé).
  final double? stockActuel;

  /// Stock au premier jour de la période analysée.
  final double? stockDebut;

  /// Quantité vendue pendant la période (tous vendeurs confondus).
  final double vendu;
  final double ca;

  factory ProduitStockRapport.fromMap(Map<String, dynamic> map) {
    return ProduitStockRapport(
      nom: parseString(map['nom'], fallback: 'Article'),
      produitId: parseStringOrNull(map['produit_id']),
      stockActuel: parseDoubleOrNull(map['stock_actuel']),
      stockDebut: parseDoubleOrNull(map['stock_debut']),
      vendu: parseDouble(map['vendu']),
      ca: parseDouble(map['ca']),
    );
  }
}

/// Totaux de la période.
class TotauxVendeurs {
  const TotauxVendeurs({
    required this.ca,
    required this.ventes,
    required this.quantite,
    required this.vendeurs,
    required this.articles,
    required this.panierMoyen,
  });

  final double ca;
  final int ventes;
  final double quantite;
  final int vendeurs;
  final int articles;
  final double panierMoyen;

  static const TotauxVendeurs vide = TotauxVendeurs(
    ca: 0,
    ventes: 0,
    quantite: 0,
    vendeurs: 0,
    articles: 0,
    panierMoyen: 0,
  );

  factory TotauxVendeurs.fromMap(Map<String, dynamic> map) {
    return TotauxVendeurs(
      ca: parseDouble(map['ca']),
      ventes: parseInt(map['ventes']),
      quantite: parseDouble(map['quantite']),
      vendeurs: parseInt(map['vendeurs']),
      articles: parseInt(map['articles']),
      panierMoyen: parseDouble(map['panier_moyen']),
    );
  }
}

/// Le rapport complet d'une entreprise sur une période.
class RapportVendeurs {
  const RapportVendeurs({
    required this.entreprise,
    required this.debut,
    required this.fin,
    required this.totaux,
    this.entrepriseId,
    this.vendeurs = const <VendeurRapport>[],
    this.produits = const <ProduitStockRapport>[],
    this.journal = const <JournalVenteVendeur>[],
  });

  final String entreprise;
  final String? entrepriseId;
  final DateTime? debut;
  final DateTime? fin;
  final TotauxVendeurs totaux;
  final List<VendeurRapport> vendeurs;
  final List<ProduitStockRapport> produits;

  /// Chronologie complète (toutes personnes confondues).
  final List<JournalVenteVendeur> journal;

  static const RapportVendeurs vide = RapportVendeurs(
    entreprise: '',
    debut: null,
    fin: null,
    totaux: TotauxVendeurs.vide,
  );

  bool get estVide => vendeurs.isEmpty && journal.isEmpty;

  VendeurRapport? vendeurParId(String id) {
    for (final VendeurRapport v in vendeurs) {
      if (v.id == id) return v;
    }
    return null;
  }

  factory RapportVendeurs.fromMap(Map<String, dynamic> map) {
    return RapportVendeurs(
      entreprise: parseString(map['entreprise']),
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      debut: parseDateTimeOrNull(map['debut']),
      fin: parseDateTimeOrNull(map['fin']),
      totaux: TotauxVendeurs.fromMap(
        parseMap(map['totaux']) ?? const <String, dynamic>{},
      ),
      vendeurs: parseMapList(map['vendeurs'])
          .map(VendeurRapport.fromMap)
          .toList(growable: false),
      produits: parseMapList(map['produits'])
          .map(ProduitStockRapport.fromMap)
          .toList(growable: false),
      journal: parseMapList(map['journal'])
          .map(JournalVenteVendeur.fromMap)
          .toList(growable: false),
    );
  }
}
