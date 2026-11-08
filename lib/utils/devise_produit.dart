// lib/utils/devise_produit.dart
//
// 💵 MODULE 29 — LA DEVISE DE CHAQUE ARTICLE.
//
// Dans une même boutique, un article peut être prixé en **francs congolais**
// et un autre en **dollars**. Le commerçant saisit le prix dans la devise du
// produit ; l'application ne le convertit JAMAIS à l'enregistrement.
//
// La conversion n'a lieu qu'à deux moments, toujours avec le taux du jour
// (`DeviseService`, Module 18) :
//   • à la VENTE : le panier et la facture sont tenus dans la devise de
//     l'entreprise (une seule monnaie pour additionner, encaisser et
//     comptabiliser) ;
//   • à l'AFFICHAGE : on montre le prix d'origine et son équivalent.
//
// ⚠️ Règle d'or : additionner deux devises n'a aucun sens. Tous les TOTAUX
//    (panier, facture, caisse, rapports) restent dans la devise de
//    l'entreprise. Seuls les PRIX D'ARTICLE portent une devise.

import 'package:biashara_yangu/models/devise.dart';
import 'package:biashara_yangu/services/devise_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Devise d'un article, avec repli sur celle de l'entreprise.
///
/// Un article sans devise (`null`, chaîne vide) suit la devise de la boutique :
/// c'est le cas de tous les articles créés avant le Module 29.
Devise deviseArticle(String? code) {
  final String propre = (code ?? '').trim();
  if (propre.isEmpty) return DeviseService.instance.configuration.devise;
  return Devise.fromCode(propre);
}

/// Le prix de l'article est-il exprimé dans une AUTRE devise que celle de
/// l'entreprise ? (sert à décider si l'on affiche un équivalent)
bool deviseDifferente(String? code) =>
    deviseArticle(code) != DeviseService.instance.configuration.devise;

/// Convertit un prix d'article vers la devise de l'entreprise.
///
/// Le taux utilisé est celui du jour (taux de l'entreprise s'il existe, sinon
/// celui de la plateforme). Le prix enregistré n'est jamais modifié.
double versDeviseEntreprise(double montant, String? deviseProduit) {
  final Devise source = deviseArticle(deviseProduit);
  final Devise cible = DeviseService.instance.configuration.devise;
  if (source == cible) return montant;

  final double converti = DeviseService.instance.convertir(
    montant,
    depuis: source,
    vers: cible,
  );
  // Les francs n'ont pas de centimes : on arrondit à l'unité, sinon une
  // facture afficherait « 27 999,99 CDF ».
  return cible == Devise.cdf ? converti.roundToDouble() : _arrondi2(converti);
}

/// Prix affichable d'un article : « 10 $ » ou « 28 000 CDF ».
///
/// [avecEquivalence] ajoute la conversion entre parenthèses quand la devise de
/// l'article diffère de celle de l'entreprise.
String prixArticle(
  double montant,
  String? deviseProduit, {
  bool avecEquivalence = true,
}) {
  final Devise devise = deviseArticle(deviseProduit);
  final String principal = formatMontant(montant, devise: devise.symbole);

  if (!avecEquivalence || devise == DeviseService.instance.configuration.devise) {
    return principal;
  }

  final double equivalent = versDeviseEntreprise(montant, deviseProduit);
  // `formatMontant` applique les séparateurs de milliers et la devise de
  // l'entreprise : « 10,00 $ ≈ 28 000 CDF ».
  return '$principal ≈ ${formatMontant(equivalent)}';
}

/// Taux appliqué, pour l'expliquer au commerçant (« 1 $ = 2 800 CDF »).
double get tauxDuJour => DeviseService.instance.configuration.tauxUsdCdf;

/// Arrondi monétaire à 2 décimales (dollars).
double _arrondi2(double valeur) => (valeur * 100).roundToDouble() / 100;
