// lib/models/analyse_entreprise.dart
//
// 📊 MIGRATION 175 — RAPPORT D'ANALYSE D'UNE ENTREPRISE.
//
// Modèle du JSON renvoyé par `rpc_rapport_entreprise_analyse(entreprise,
// debut, fin)` : totaux, meilleur produit, meilleur jour, meilleur moment,
// conseils de croissance et simulation « si ce produit progresse de 10 % ».
//
// Toutes les conversions passent par les helpers tolérants de
// `utils/json_parsing.dart` : une colonne `numeric` peut arriver en `int`
// comme en `String` selon PostgREST.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Totaux de la période analysée.
class AnalyseTotaux {
  const AnalyseTotaux({
    this.ca = 0,
    this.ventes = 0,
    this.articles = 0,
    this.panierMoyen = 0,
    this.marge = 0,
  });

  final double ca;
  final int ventes;
  final double articles;
  final double panierMoyen;
  final double marge;

  bool get estVide => ventes == 0;

  factory AnalyseTotaux.depuisJson(dynamic json) {
    final Map<String, dynamic> map = parseMap(json) ?? <String, dynamic>{};
    return AnalyseTotaux(
      ca: parseDouble(map['ca']),
      ventes: parseInt(map['ventes']),
      articles: parseDouble(map['articles']),
      panierMoyen: parseDouble(map['panier_moyen']),
      marge: parseDouble(map['marge']),
    );
  }
}

/// Ligne du classement des produits.
class AnalyseProduit {
  const AnalyseProduit({
    this.rang = 0,
    this.nom = '',
    this.quantite = 0,
    this.ca = 0,
    this.part = 0,
  });

  final int rang;
  final String nom;
  final double quantite;
  final double ca;
  final double part;

  factory AnalyseProduit.depuisJson(dynamic json) {
    final Map<String, dynamic> map = parseMap(json) ?? <String, dynamic>{};
    return AnalyseProduit(
      rang: parseInt(map['rang']),
      nom: parseString(map['nom'], fallback: 'Article'),
      quantite: parseDouble(map['quantite']),
      ca: parseDouble(map['ca']),
      part: parseDouble(map['part']),
    );
  }
}

/// Chiffre d'affaires par jour de la semaine.
class AnalyseJour {
  const AnalyseJour({
    this.dow = 0,
    this.jour = '',
    this.ca = 0,
    this.ventes = 0,
  });

  /// 0 = dimanche … 6 = samedi (convention PostgreSQL).
  final int dow;
  final String jour;
  final double ca;
  final int ventes;

  factory AnalyseJour.depuisJson(dynamic json) {
    final Map<String, dynamic> map = parseMap(json) ?? <String, dynamic>{};
    return AnalyseJour(
      dow: parseInt(map['dow']),
      jour: parseString(map['jour']),
      ca: parseDouble(map['ca']),
      ventes: parseInt(map['ventes']),
    );
  }
}

/// Chiffre d'affaires par moment de la journée.
class AnalyseMoment {
  const AnalyseMoment({this.moment = '', this.ca = 0, this.ventes = 0});

  final String moment;
  final double ca;
  final int ventes;

  factory AnalyseMoment.depuisJson(dynamic json) {
    final Map<String, dynamic> map = parseMap(json) ?? <String, dynamic>{};
    return AnalyseMoment(
      moment: parseString(map['moment']),
      ca: parseDouble(map['ca']),
      ventes: parseInt(map['ventes']),
    );
  }
}

/// Conseil de croissance calculé sur les données réelles.
class AnalyseConseil {
  const AnalyseConseil({this.titre = '', this.detail = ''});

  final String titre;
  final String detail;

  factory AnalyseConseil.depuisJson(dynamic json) {
    final Map<String, dynamic> map = parseMap(json) ?? <String, dynamic>{};
    return AnalyseConseil(
      titre: parseString(map['titre']),
      detail: parseString(map['detail']),
    );
  }
}

/// Simulation : « si le produit n°1 progresse de X %, la boutique gagne Y ».
class AnalyseSimulation {
  const AnalyseSimulation({
    this.produit = '',
    this.caActuel = 0,
    this.objectifPct = 10,
    this.caSupplementaire = 0,
    this.caProjete = 0,
    this.message = '',
  });

  final String produit;
  final double caActuel;
  final double objectifPct;
  final double caSupplementaire;
  final double caProjete;
  final String message;

  bool get estVide => produit.trim().isEmpty;

  factory AnalyseSimulation.depuisJson(dynamic json) {
    final Map<String, dynamic> map = parseMap(json) ?? <String, dynamic>{};
    return AnalyseSimulation(
      produit: parseString(map['produit']),
      caActuel: parseDouble(map['ca_actuel']),
      objectifPct: parseDouble(map['objectif_pct'], fallback: 10),
      caSupplementaire: parseDouble(map['ca_supplementaire']),
      caProjete: parseDouble(map['ca_projete']),
      message: parseString(map['message']),
    );
  }
}

/// Rapport d'analyse complet d'une entreprise sur une période.
class AnalyseEntreprise {
  const AnalyseEntreprise({
    required this.entrepriseId,
    this.entrepriseNom = '',
    this.debut,
    this.fin,
    this.devise = 'CDF',
    this.totaux = const AnalyseTotaux(),
    this.topProduits = const <AnalyseProduit>[],
    this.jours = const <AnalyseJour>[],
    this.moments = const <AnalyseMoment>[],
    this.meilleurProduit,
    this.meilleurJour,
    this.meilleurMoment,
    this.conseils = const <AnalyseConseil>[],
    this.simulation,
    this.nbProduits = 0,
    this.sources = const <String, int>{},
  });
  final String entrepriseId;
  final String entrepriseNom;
  final DateTime? debut;
  final DateTime? fin;
  final String devise;
  final AnalyseTotaux totaux;
  final List<AnalyseProduit> topProduits;
  final List<AnalyseJour> jours;
  final List<AnalyseMoment> moments;
  final AnalyseProduit? meilleurProduit;
  final AnalyseJour? meilleurJour;
  final AnalyseMoment? meilleurMoment;
  final List<AnalyseConseil> conseils;
  final AnalyseSimulation? simulation;

  /// Nombre de produits (ou prestations) DIFFÉRENTS vendus sur la période.
  ///
  /// Le serveur renvoie TOUS les produits classés par meilleure vente ; ce
  /// compteur évite de parcourir la liste pour l'afficher en tête de rapport.
  final int nbProduits;

  /// Origine des lignes analysées : `boutique` (ventes d'articles) et
  /// `pressing` (prestations de dépôts). Un pressing ne vend pas d'articles :
  /// sans cette source, son rapport serait toujours vide.
  final Map<String, int> sources;

  /// Libellé lisible de l'origine (« Ventes boutique », « Pressing »…).
  String get libelleOrigines {
    final List<String> parts = <String>[];
    if ((sources['boutique'] ?? 0) > 0) {
      parts.add('${sources['boutique']} ligne(s) boutique');
    }
    if ((sources['pressing'] ?? 0) > 0) {
      parts.add('${sources['pressing']} ligne(s) pressing');
    }
    return parts.isEmpty ? 'aucune vente enregistrée' : parts.join(' · ');
  }

  bool get estVide => totaux.estVide;

  /// Durée en jours (bornes incluses) — 7 pour une semaine, ~30 pour un mois.
  int get nombreDeJours {
    if (debut == null || fin == null) return 0;
    return fin!.difference(debut!).inDays + 1;
  }

  factory AnalyseEntreprise.depuisJson(
    dynamic json, {
    String? entrepriseId,
  }) {
    final Map<String, dynamic> map = parseMap(json) ?? <String, dynamic>{};

    AnalyseProduit? produit(dynamic valeur) {
      final Map<String, dynamic>? sous = parseMap(valeur);
      return sous == null ? null : AnalyseProduit.depuisJson(sous);
    }

    AnalyseJour? jour(dynamic valeur) {
      final Map<String, dynamic>? sous = parseMap(valeur);
      return sous == null ? null : AnalyseJour.depuisJson(sous);
    }

    AnalyseMoment? moment(dynamic valeur) {
      final Map<String, dynamic>? sous = parseMap(valeur);
      return sous == null ? null : AnalyseMoment.depuisJson(sous);
    }

    return AnalyseEntreprise(
      entrepriseId:
          parseString(map['entreprise_id'], fallback: entrepriseId ?? ''),
      entrepriseNom: parseString(map['entreprise_nom']),
      debut: parseDateTimeOrNull(map['debut']),
      fin: parseDateTimeOrNull(map['fin']),
      devise: parseString(map['devise'], fallback: 'CDF'),
      totaux: AnalyseTotaux.depuisJson(map['totaux']),
      topProduits: parseMapList(map['top_produits'])
          .map(AnalyseProduit.depuisJson)
          .toList(),
      jours:
          parseMapList(map['jours']).map(AnalyseJour.depuisJson).toList(),
      moments:
          parseMapList(map['moments']).map(AnalyseMoment.depuisJson).toList(),
      meilleurProduit: produit(map['meilleur_produit']),
      meilleurJour: jour(map['meilleur_jour']),
      meilleurMoment: moment(map['meilleur_moment']),
      conseils: parseMapList(map['conseils'])
          .map(AnalyseConseil.depuisJson)
          .toList(),
      simulation: parseMap(map['simulation']) == null
          ? null
          : AnalyseSimulation.depuisJson(map['simulation']),
      nbProduits: parseInt(map['nb_produits']).clamp(
        0,
        1 << 30,
      ),
      sources: <String, int>{
        for (final MapEntry<String, dynamic> e
            in (parseMap(map['sources']) ?? const <String, dynamic>{}).entries)
          e.key: parseInt(e.value),
      },
    );
  }
}
