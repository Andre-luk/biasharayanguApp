// lib/services/donnees_service.dart
//
// 🔔 CORRECTIF 78 — « LES CHIFFRES ONT CHANGÉ ».
//
// Problème constaté : après avoir ajouté un article ou encaissé une vente, le
// tableau de bord continuait d'afficher les anciens totaux. Il fallait quitter
// l'application ou tirer l'écran vers le bas pour voir la mise à jour.
//
// La cause : l'accueil lit la copie LOCALE des données et ne relit rien quand
// on revient d'un autre écran (`initState` n'est appelé qu'une fois). Le
// temps réel du serveur ne suffit pas non plus : il se déclenche à l'envoi,
// pas à l'écriture locale.
//
// Ce service est le carillon commun : CHAQUE écriture qui change les chiffres
// affichés (vente enregistrée, vente encaissée, article créé/modifié/supprimé,
// stock ajusté) prévient ici, et les écrans qui affichent des totaux
// s'abonnent. Un seul point d'écoute, aucune dépendance croisée entre pages.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:biashara_yangu/services/tableau_bord_stats_service.dart';

/// Canal d'annonce des écritures de données.
///
/// [revision] s'incrémente à chaque annonce ; les écrans s'y abonnent et
/// relisent leurs données. Un `ValueNotifier<int>` plutôt qu'un `Stream` :
/// pas d'abonnement à oublier, pas de diffusion manquée, et un état lisible
/// (le nombre d'annonces depuis le démarrage).
class DonneesService {
  DonneesService._();

  static final DonneesService instance = DonneesService._();

  /// Incrémenté après chaque écriture. Écouter pour se rafraîchir.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Dernier motif annoncé (diagnostic : « vente », « article »…).
  String dernierMotif = '';

  /// Annonce une écriture. Best-effort : ne lève jamais, ne bloque jamais.
  ///
  /// [motif] sert uniquement aux journaux de mise au point — il n'est jamais
  /// affiché au commerçant.
  void signale([String motif = '']) {
    dernierMotif = motif;
    revision.value = revision.value + 1;

    // 🧹 Une écriture qui change les totaux rend PÉRIMÉE la réponse
    // d'accueil gardée en cache : on la jette pour que le prochain
    // affichage interroge réellement le serveur (sinon l'écran peut rester
    // dix minutes sur les chiffres d'avant la vente). Best-effort : cette
    // invalidation ne bloque jamais l'appelant.
    unawaited(TableauBordStatsService.instance.invalider());

    if (kDebugMode) {
      debugPrint('DonneesService : rafraichissement ($motif)');
    }
  }
}
