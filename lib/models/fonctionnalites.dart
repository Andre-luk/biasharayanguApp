// lib/models/fonctionnalites.dart
//
// 🧩 CORRECTIF 65 — CATALOGUE DES FONCTIONNALITÉS, AVEC LEURS LIBELLÉS.
//
// `ModuleCode` (module_activite.dart) ne contient que les CODES, miroir de
// `public.modules_catalogue()` (SQL). Ici, chaque code est accompagné de son
// NOM AFFICHÉ et de sa famille, pour les écrans qui font **cocher** des
// fonctionnalités — aujourd'hui les niveaux d'abonnement.
//
// ⚠️ RÈGLE DU PROJET : toute nouvelle fonctionnalité doit être déclarée dans
// `ModuleCode`, dans `public.modules_catalogue()` **et** ici. Les trois vont
// ensemble. Un code présent en base mais absent d'ici n'est jamais perdu : il
// est simplement affiché brut (voir [libelleDe]).

import 'package:biashara_yangu/models/module_activite.dart';

/// Une fonctionnalité affichable : un code, un nom, une famille.
class Fonctionnalite {
  const Fonctionnalite(this.code, this.libelle, this.famille);

  /// Code stocké en base (`ventes`, `assistant_ia`…).
  final String code;

  /// Nom affiché au commerçant.
  final String libelle;

  /// Regroupement dans les écrans de sélection.
  final String famille;
}

abstract final class Fonctionnalites {
  /// Le joker : « toutes les fonctionnalités de l'activité ».
  ///
  /// Miroir de `ReglesAbonnement.joker`. C'est le niveau le plus élevé : il
  /// reste correct même quand de nouvelles fonctionnalités sont ajoutées.
  static const String joker = '*';

  // Familles d'affichage.
  static const String familleCommerce = 'Commerce';
  static const String familleGestion = 'Gestion';
  static const String familleMetiers = 'Métiers';

  /// Toutes les fonctionnalités connues, dans l'ordre d'affichage.
  static const List<Fonctionnalite> toutes = <Fonctionnalite>[
    // ── Commerce : le socle du comptoir ──────────────────────────────────
    Fonctionnalite(ModuleCode.ventes, 'Ventes', familleCommerce),
    Fonctionnalite(ModuleCode.produits, 'Produits', familleCommerce),
    Fonctionnalite(ModuleCode.stock, 'Stock', familleCommerce),
    Fonctionnalite(ModuleCode.caisse, 'Caisse', familleCommerce),
    Fonctionnalite(ModuleCode.clients, 'Clients', familleCommerce),
    Fonctionnalite(ModuleCode.qr, 'Étiquettes QR', familleCommerce),
    Fonctionnalite(ModuleCode.pesee, 'Vente au poids', familleCommerce),
    Fonctionnalite(
        ModuleCode.variantes, 'Variantes (taille, couleur)', familleCommerce),

    // ── Gestion : le pilotage ────────────────────────────────────────────
    Fonctionnalite(ModuleCode.finance, 'Finance', familleGestion),
    Fonctionnalite(ModuleCode.employes, 'Employés', familleGestion),
    Fonctionnalite(ModuleCode.rapports, 'Rapports', familleGestion),
    Fonctionnalite(
        ModuleCode.assistantIa, 'Assistant IA', familleGestion),
    Fonctionnalite(
        ModuleCode.lotsExpiration, 'Lots & péremption', familleGestion),
    Fonctionnalite(ModuleCode.production, 'Production', familleGestion),

    // ── Métiers : activités spécialisées ─────────────────────────────────
    Fonctionnalite(ModuleCode.chambres, 'Chambres', familleMetiers),
    Fonctionnalite(ModuleCode.reservations, 'Réservations', familleMetiers),
    Fonctionnalite(ModuleCode.checkin, 'Check-in', familleMetiers),
    Fonctionnalite(ModuleCode.tables, 'Tables', familleMetiers),
    Fonctionnalite(ModuleCode.commandes, 'Commandes', familleMetiers),
    Fonctionnalite(ModuleCode.cuisine, 'Cuisine', familleMetiers),
    Fonctionnalite(ModuleCode.salles, 'Salles', familleMetiers),
    Fonctionnalite(ModuleCode.evenements, 'Événements', familleMetiers),
  ];

  /// Les familles, dans l'ordre d'affichage.
  static const List<String> familles = <String>[
    familleCommerce,
    familleGestion,
    familleMetiers,
  ];

  /// Les fonctionnalités d'une famille.
  static List<Fonctionnalite> deLaFamille(String famille) =>
      toutes.where((Fonctionnalite f) => f.famille == famille).toList();

  /// Tous les codes, dans l'ordre d'affichage.
  static List<String> get codes =>
      toutes.map((Fonctionnalite f) => f.code).toList();

  /// Le code est-il connu de l'application ?
  static bool codeConnu(String code) =>
      code == joker || toutes.any((Fonctionnalite f) => f.code == code);

  /// Nom affiché d'un code.
  ///
  /// Un code inconnu (fonctionnalité ajoutée côté base et pas encore ici)
  /// n'est jamais perdu : il est affiché tel quel, entre guillemets, pour
  /// qu'on comprenne qu'il vient de plus loin que l'application.
  static String libelleDe(String code) {
    if (code == joker) return 'Toutes les fonctionnalités';
    for (final Fonctionnalite f in toutes) {
      if (f.code == code) return f.libelle;
    }
    return code;
  }

  /// Nombre de fonctionnalités d'un ensemble de codes (le joker compte pour
  /// tout le catalogue).
  static int compte(Set<String> codes) =>
      codes.contains(joker) ? toutes.length : codes.length;
}
