// lib/models/devise.dart
//
// 🪙 MODULE 18 — DEVISES DE TRAVAIL & TAUX DE CONVERSION.
//
// Chaque entreprise travaille dans SA devise (CDF ou USD) : tous ses montants
// (prix d'achat / de vente, ventes, dépenses, caisse, rapports, paiements,
// abonnements) sont exprimés et affichés dans cette devise.
//
// Le taux de conversion « 1 USD = X CDF » permet d'afficher les équivalences :
//   • taux de la PLATEFORME (réglage Super Admin) ;
//   • taux propre à l'ENTREPRISE (optionnel, prioritaire).
//
// API SQL : `supabase/migrations/20260916000039_module18_devises.sql`.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Devise de travail (mêmes codes que `entreprises.devise`).
enum Devise {
  cdf('CDF', 'Franc congolais', 'CDF'),
  usd('USD', 'Dollar américain', r'$');

  const Devise(this.code, this.libelle, this.symbole);

  /// Code stocké en base (`CDF`, `USD`).
  final String code;

  /// Libellé lisible (« Franc congolais »).
  final String libelle;

  /// Unité d'affichage (`CDF`, `$`) — miroir de `devise_symbole()` (SQL).
  final String symbole;

  bool get estCdf => this == Devise.cdf;
  bool get estUsd => this == Devise.usd;

  /// Convertit un code SQL en devise (repli : [Devise.cdf]).
  static Devise fromCode(String? code) {
    final String normalise = (code ?? '').trim().toUpperCase();
    for (final Devise devise in values) {
      if (devise.code == normalise) return devise;
    }
    return Devise.cdf;
  }
}

/// Taux de change par défaut si la base n'a jamais été réglée.
const double tauxUsdCdfParDefaut = 2800;

/// État complet renvoyé par `rpc_devise_etat()`.
class EtatDevise {
  const EtatDevise({
    this.devise = Devise.cdf,
    this.tauxUsdCdf = tauxUsdCdfParDefaut,
    this.tauxEntreprise,
    this.tauxPlateforme = tauxUsdCdfParDefaut,
    this.devisePlateforme = Devise.cdf,
    this.entrepriseId,
    this.peutModifier = false,
    this.devises = const <Devise>[Devise.cdf, Devise.usd],
  });

  /// Devise de travail de l'entreprise active.
  final Devise devise;

  /// Taux effectif : `1 USD = tauxUsdCdf CDF`.
  final double tauxUsdCdf;

  /// Taux imposé par l'entreprise (`null` = taux de la plateforme).
  final double? tauxEntreprise;

  /// Taux par défaut de la plateforme.
  final double tauxPlateforme;

  /// Devise proposée par défaut aux nouvelles entreprises.
  final Devise devisePlateforme;

  final String? entrepriseId;

  /// L'utilisateur connecté peut-il modifier la configuration ?
  final bool peutModifier;

  /// Devises proposées (CDF, USD…).
  final List<Devise> devises;

  /// Le taux vient-il de l'entreprise (et non de la plateforme) ?
  bool get tauxPropreEntreprise => tauxEntreprise != null && tauxEntreprise! > 0;

  /// Convertit [montant] depuis [deviseSource] vers [deviseCible].
  ///
  /// Exemples (taux 2 800) : 28 000 FC → 10 $ ; 10 $ → 28 000 FC.
  double convertir(
    double montant, {
    required Devise deviseSource,
    required Devise deviseCible,
  }) {
    if (deviseSource == deviseCible) return montant;
    final double taux = tauxUsdCdf > 0 ? tauxUsdCdf : tauxUsdCdfParDefaut;

    if (deviseSource == Devise.cdf && deviseCible == Devise.usd) {
      return montant / taux;
    }
    return montant * taux; // USD → CDF
  }

  /// Équivalent de [montant] (exprimé dans [deviseSource]) dans l'autre devise.
  double equivalent(double montant, {Devise? deviseSource}) {
    final Devise source = deviseSource ?? devise;
    final Devise cible = source == Devise.cdf ? Devise.usd : Devise.cdf;
    return convertir(montant, deviseSource: source, deviseCible: cible);
  }

  /// Devise opposée (pour l'affichage des équivalences).
  Devise get deviseOpposee => devise == Devise.cdf ? Devise.usd : Devise.cdf;

  EtatDevise copyWith({
    Devise? devise,
    double? tauxUsdCdf,
    double? tauxEntreprise,
    bool? peutModifier,
  }) {
    return EtatDevise(
      devise: devise ?? this.devise,
      tauxUsdCdf: tauxUsdCdf ?? this.tauxUsdCdf,
      tauxEntreprise: tauxEntreprise ?? this.tauxEntreprise,
      tauxPlateforme: tauxPlateforme,
      devisePlateforme: devisePlateforme,
      entrepriseId: entrepriseId,
      peutModifier: peutModifier ?? this.peutModifier,
      devises: devises,
    );
  }

  /// Analyse la réponse de `rpc_devise_etat()`.
  factory EtatDevise.fromMap(Map<String, dynamic> map) {
    final List<Devise> proposees = parseMapList(map['devises'])
        .map((Map<String, dynamic> element) =>
            Devise.fromCode(parseStringOrNull(element['code'])))
        .toList(growable: false);

    return EtatDevise(
      devise: Devise.fromCode(parseStringOrNull(map['devise'])),
      tauxUsdCdf: parseDoubleOrNull(map['taux_usd_cdf']) ??
          tauxUsdCdfParDefaut,
      tauxEntreprise: parseDoubleOrNull(map['taux_entreprise']),
      tauxPlateforme: parseDoubleOrNull(map['taux_plateforme']) ??
          tauxUsdCdfParDefaut,
      devisePlateforme:
          Devise.fromCode(parseStringOrNull(map['devise_plateforme'])),
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      peutModifier: map['peut_modifier'] == true,
      devises: proposees.isEmpty
          ? const <Devise>[Devise.cdf, Devise.usd]
          : proposees,
    );
  }
}
