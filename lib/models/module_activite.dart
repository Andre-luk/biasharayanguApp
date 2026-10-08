// lib/models/module_activite.dart
//
// MODULE 16 (phase A) — RÉFÉRENTIEL DES MODULES & PROFILS D'ACTIVITÉ.
//
// Un « module » est une unité fonctionnelle activable selon l'activité de
// l'entreprise : ventes, stock, chambres (hôtel), commandes (restaurant)…
// Le type de l'espace de travail (module 15) référence un PROFIL DE MODULES
// côté serveur (`public.types_espaces_modules`, migration 27) ; l'application
// charge ce profil et masque les écrans qui ne concernent pas l'activité.
//
// ⚠️ Le catalogue ci-dessous est le MIROIR de `public.modules_catalogue()`
// (SQL) : toute évolution doit être faite DES DEUX CÔTÉS — même règle que la
// matrice des permissions du module 4.
//
// Règle d'or : profil inconnu, absent ou vide → comportement actuel de
// l'application (tout est visible) ; aucune régression possible.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Codes des modules (valeurs stockées côté serveur).
abstract final class ModuleCode {
  // ------------------------------------------------------------------ actuels
  static const String ventes = 'ventes';
  static const String produits = 'produits';
  static const String stock = 'stock';
  static const String qr = 'qr';
  static const String caisse = 'caisse';
  static const String clients = 'clients';
  static const String finance = 'finance';
  static const String employes = 'employes';
  static const String rapports = 'rapports';
  static const String assistantIa = 'assistant_ia';

  // -------------------------------- phases C (métier) — C1→C4 DÉJÀ LIVRÉS
  static const String chambres = 'chambres';
  static const String reservations = 'reservations';
  static const String checkin = 'checkin';
  static const String tables = 'tables';
  static const String commandes = 'commandes';
  static const String cuisine = 'cuisine';
  static const String salles = 'salles';
  static const String evenements = 'evenements';
  static const String lotsExpiration = 'lots_expiration';
  static const String production = 'production';
  static const String pesee = 'pesee';
  static const String variantes = 'variantes';

  /// Module « par défaut » de repli (profil boutique).
  static const String profilDefaut = 'boutique';
}

/// 🧩 CORRECTIF 65 — RÈGLES D'ABONNEMENT.
///
/// Deuxième filtre, indépendant de l'activité : un écran doit avoir du SENS
/// (activité) **et** être PAYÉ (niveau d'abonnement).
///
/// ⚠️ Même règle d'or que [ReglesActivite] : **fail-open**. Liste vide, non
/// chargée, ou portant le joker `*` → tout est ouvert. Un abonnement ne fait
/// que MASQUER ce qu'il n'inclut pas — il ne masque jamais tout, et une panne
/// réseau ne fait jamais disparaître les écrans d'un commerçant qui paie.
abstract final class ReglesAbonnement {
  /// Le joker : « toutes les fonctionnalités de l'activité ».
  ///
  /// C'est le niveau le plus élevé. Il restera correct même quand de
  /// nouvelles fonctionnalités seront ajoutées à l'application — contrairement
  /// à une liste énumérée qu'il faudrait penser à compléter.
  static const String joker = '*';

  /// Règle générique : au moins une des fonctionnalités demandées est-elle
  /// ouverte par l'abonnement ?
  static bool autorise(
    Set<String> ouverts,
    bool charge,
    Set<String> codes,
  ) {
    if (!charge || ouverts.isEmpty) return true; // fail-open
    if (ouverts.contains(joker)) return true; // niveau le plus haut
    for (final String code in codes) {
      if (ouverts.contains(code)) return true;
    }
    return false;
  }
}

/// 🧩 MODULE 16 — RÈGLES D'AFFICHAGE PILOTÉES PAR L'ACTIVITÉ.
///
/// Un module ne fait que **MASQUER** une entrée : il ne bloque jamais un
/// écran. Ces règles répondent à la question « cette activité utilise-t-elle
/// cet écran ? » pour les entrées qui n'ont pas de carte d'accueil : actions
/// rapides de l'accueil, boutons secondaires, onglets de la barre de
/// navigation.
///
/// ⚠️ Fail-open (règle d'or du module 16) : profil non chargé ou vide →
/// `true`. Sans cette précaution, une panne réseau ferait disparaître des
/// boutons légitimes (boutique hors ligne).
///
/// Miroir de `public.modules_base()` / des profils `public.types_espaces_modules`
/// côté serveur et de [ModulesService.moduleActif] côté client.
abstract final class ReglesActivite {
  /// Règle générique : AU MOINS UN des modules est-il actif ?
  static bool actif(
    Set<String> modules,
    bool profilCharge,
    Set<String> codes,
  ) {
    if (!profilCharge || modules.isEmpty) return true; // fail-open
    for (final String code in codes) {
      if (modules.contains(code)) return true;
    }
    return false;
  }

  /// 💰 Vente au comptoir : « Nouvelle Vente », scanner vendeur, suivi
  /// commercial, montants « ventes du jour ».
  ///
  /// Un hôtel (profil sans `ventes`) n'encaisse pas au comptoir : il utilise
  /// ses propres écrans (réservations, check-in) et sa caisse.
  static bool ventes(Set<String> modules, bool profilCharge) => actif(
        modules,
        profilCharge,
        const <String>{ModuleCode.ventes},
      );

  /// 🗂️ Catalogue d'articles : « Ajouter un produit », catégories, import,
  /// conditionnements.
  ///
  /// ⚠️ Uniquement le module `produits` : les ÉTIQUETTES QR (`qr`) ne
  /// suffisent PAS — un hôtel peut imprimer des étiquettes sans avoir de
  /// catalogue d'articles à gérer (constaté en production).
  static bool catalogue(Set<String> modules, bool profilCharge) => actif(
        modules,
        profilCharge,
        const <String>{ModuleCode.produits},
      );

  /// 🏬 Stock & inventaire (onglet « Stock », rapports de stock).
  ///
  /// ⚠️ Seul le module `stock` compte : le PROFIL est l'autorité. Une activité
  /// qui gère des articles sans gestion de stock (ex. « salon_de_coiffure »
  /// créé par l'Expert : produits, caisse, clients, rapports, employes) ne
  /// doit pas voir l'onglet — ses articles restent accessibles par l'écran
  /// Articles.
  static bool stock(Set<String> modules, bool profilCharge) => actif(
        modules,
        profilCharge,
        const <String>{ModuleCode.stock},
      );

  /// 💵 Caisse / encaissement : présent dans TOUS les profils actuels, mais
  /// une activité peut un jour se contenter de rapports.
  static bool caisse(Set<String> modules, bool profilCharge) => actif(
        modules,
        profilCharge,
        const <String>{ModuleCode.caisse},
      );

  /// 🔎 Testeur d'un module précis, à passer aux entrées qui n'ont qu'une
  /// seule dépendance (onglet « Rapports », cartes d'un menu…).
  ///
  /// ```dart
  /// _BrancheNav(index: 1, activite: ReglesActivite.module(ModuleCode.rapports))
  /// ```
  static bool Function(Set<String> modules, bool profilCharge) module(
    String code,
  ) {
    return (Set<String> modules, bool profilCharge) =>
        actif(modules, profilCharge, <String>{code});
  }
}

/// Regroupement d'affichage des modules (page admin « Types d'activités »).
enum ModuleCategorie {
  general('Général'),
  sejour('Hôtel & séjour'),
  restauration('Restauration'),
  evenementiel('Événementiel'),
  commerceSpecialise('Commerces spécialisés');

  const ModuleCategorie(this.libelle);

  final String libelle;
}

/// Un module du catalogue : code technique, libellé, icône, disponibilité.
class ModuleActivite {
  const ModuleActivite({
    required this.code,
    required this.libelle,
    required this.description,
    required this.icone,
    required this.categorie,
    this.disponible = true,
  });

  /// Code stocké côté serveur (snake_case, miroir de `modules_catalogue()`).
  final String code;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// Présentation courte (page « Types d'activités »).
  final String description;

  final IconData icone;
  final ModuleCategorie categorie;

  /// `false` = module pré-déclaré mais pas encore codé (« bientôt ») : il
  /// peut être coché dans un profil (préparation des phases C), aucun écran
  /// ne le consomme encore.
  final bool disponible;

  /// Le catalogue complet (actuels + phases C).
  static const List<ModuleActivite> catalogue = <ModuleActivite>[
    // ------------------------------------------------------------- actuels
    ModuleActivite(
      code: ModuleCode.ventes,
      libelle: 'Ventes & panier',
      description: 'Panier, encaissement, reçus et historique.',
      icone: Icons.point_of_sale_rounded,
      categorie: ModuleCategorie.general,
    ),
    ModuleActivite(
      code: ModuleCode.produits,
      libelle: 'Articles & catalogue',
      description: 'Fiches articles, catégories, conditionnements.',
      icone: Icons.inventory_2_rounded,
      categorie: ModuleCategorie.general,
    ),
    ModuleActivite(
      code: ModuleCode.stock,
      libelle: 'Stock & inventaire',
      description: 'Approvisionnements, ajustements, inventaires.',
      icone: Icons.warehouse_rounded,
      categorie: ModuleCategorie.general,
    ),
    ModuleActivite(
      code: ModuleCode.qr,
      libelle: 'QR codes & étiquettes',
      description: 'Génération et impression des étiquettes QR.',
      icone: Icons.qr_code_2_rounded,
      categorie: ModuleCategorie.general,
    ),
    ModuleActivite(
      code: ModuleCode.caisse,
      libelle: 'Caisse & encaissement',
      description: 'Mouvements de caisse et clôtures.',
      icone: Icons.payments_rounded,
      categorie: ModuleCategorie.general,
    ),
    ModuleActivite(
      code: ModuleCode.clients,
      libelle: 'Clients & dettes',
      description: 'Fiches clients, crédits et remboursements.',
      icone: Icons.people_alt_rounded,
      categorie: ModuleCategorie.general,
    ),
    ModuleActivite(
      code: ModuleCode.finance,
      libelle: 'Finance & dépenses',
      description: 'Dépenses, bénéfices, tableau de bord financier.',
      icone: Icons.account_balance_wallet_rounded,
      categorie: ModuleCategorie.general,
    ),
    ModuleActivite(
      code: ModuleCode.employes,
      libelle: 'Collaborateurs',
      description: 'Équipe, rôles et permissions.',
      icone: Icons.badge_rounded,
      categorie: ModuleCategorie.general,
    ),
    ModuleActivite(
      code: ModuleCode.rapports,
      libelle: 'Rapports & exports',
      description: 'Rapports PDF / Excel signés.',
      icone: Icons.bar_chart_rounded,
      categorie: ModuleCategorie.general,
    ),
    ModuleActivite(
      code: ModuleCode.assistantIa,
      libelle: 'Assistant IA',
      description: 'Assistant intelligent (analyses, conseils).',
      icone: Icons.smart_toy_rounded,
      categorie: ModuleCategorie.general,
    ),
    // ------------------------------------------------- hôtel (phase C2)
    ModuleActivite(
      code: ModuleCode.chambres,
      libelle: 'Chambres',
      description: 'Plan des chambres, statuts et équipements.',
      icone: Icons.hotel,
      categorie: ModuleCategorie.sejour,
    ),
    ModuleActivite(
      code: ModuleCode.reservations,
      libelle: 'Réservations',
      description: 'Réservations clients, avances et soldes.',
      icone: Icons.event_available,
      categorie: ModuleCategorie.sejour,
    ),
    ModuleActivite(
      code: ModuleCode.checkin,
      libelle: 'Check-in / Check-out',
      description: 'Arrivées, départs et facturation des séjours.',
      icone: Icons.how_to_reg,
      categorie: ModuleCategorie.sejour,
    ),
    // --------------------------------------------- restaurant (phase C3)
    ModuleActivite(
      code: ModuleCode.tables,
      libelle: 'Plan de salle',
      description: 'Tables, occupation et service.',
      icone: Icons.table_restaurant,
      categorie: ModuleCategorie.restauration,
    ),
    ModuleActivite(
      code: ModuleCode.commandes,
      libelle: 'Commandes',
      description: 'Prise de commande (table → cuisine).',
      icone: Icons.receipt_long,
      categorie: ModuleCategorie.restauration,
    ),
    ModuleActivite(
      code: ModuleCode.cuisine,
      libelle: 'Écran cuisine',
      description: 'File de préparation pour la cuisine.',
      icone: Icons.soup_kitchen,
      categorie: ModuleCategorie.restauration,
    ),
    // -------------------------------------------- salle des fêtes (C4)
    ModuleActivite(
      code: ModuleCode.salles,
      libelle: 'Salles',
      description: 'Salles, capacités et tarifs.',
      icone: Icons.meeting_room,
      categorie: ModuleCategorie.evenementiel,
    ),
    ModuleActivite(
      code: ModuleCode.evenements,
      libelle: 'Événements',
      description: 'Calendrier, contrats et avances des événements.',
      icone: Icons.celebration,
      categorie: ModuleCategorie.evenementiel,
    ),
    // ---------------------------------------- commerces spécialisés (C1/C5/C6/C8)
    ModuleActivite(
      code: ModuleCode.lotsExpiration,
      libelle: 'Lots & péremption',
      description: "Lots, dates d'expiration et alertes (pharmacie).",
      icone: Icons.science,
      categorie: ModuleCategorie.commerceSpecialise,
    ),
    ModuleActivite(
      code: ModuleCode.production,
      libelle: 'Production',
      description: 'Production, matières premières et pertes (boulangerie).',
      icone: Icons.bakery_dining,
      categorie: ModuleCategorie.commerceSpecialise,
    ),
    ModuleActivite(
      code: ModuleCode.pesee,
      libelle: 'Vente au poids',
      description: 'Vente au kg avec arrondis (boucherie).',
      icone: Icons.scale,
      categorie: ModuleCategorie.commerceSpecialise,
    ),
    ModuleActivite(
      code: ModuleCode.variantes,
      libelle: 'Variantes (taille / couleur)',
      description: 'Attributs des articles : taille, couleur, marque.',
      icone: Icons.palette,
      categorie: ModuleCategorie.commerceSpecialise,
    ),
  ];

  /// Le module du catalogue portant ce code, ou `null` si inconnu
  /// (profil plus récent que l'application : on l'affiche tel quel).
  static ModuleActivite? parCode(String code) {
    for (final ModuleActivite module in catalogue) {
      if (module.code == code) return module;
    }
    return null;
  }

  /// Le code est-il connu de cette version de l'application ?
  static bool codeConnu(String code) => parCode(code) != null;
}

/// Profil de modules d'un type d'activité (ligne de `types_espaces_modules`).
class ProfilModules {
  const ProfilModules({
    required this.type,
    required this.libelle,
    this.modules = const <String>{},
    this.actif = true,
    this.nbEspaces = 0,
    this.updatedAt,
  });

  /// Code du type (« boutique », « hotel », « salon_de_coiffure »…).
  final String type;

  /// Nom affiché (« Hôtel », « Salon de coiffure »…).
  final String libelle;

  /// Modules du profil (vide = comportement actuel : tout est visible).
  final Set<String> modules;

  final bool actif;

  /// Nombre d'entreprises (espaces) utilisant ce type.
  final int nbEspaces;

  final DateTime? updatedAt;

  /// S'agit-il du profil de repli universel ?
  bool get profilDefaut => type == ModuleCode.profilDefaut;

  /// Modules du profil plus récents que l'application (affichés bruts).
  Set<String> get modulesInconnus =>
      modules.where((String code) => !ModuleActivite.codeConnu(code)).toSet();

  factory ProfilModules.fromMap(Map<String, dynamic> map) {
    return ProfilModules(
      type: parseString(map['type']),
      libelle: parseString(map['libelle']),
      modules: modulesDepuisJson(map['modules']),
      actif: map['actif'] == null ? true : map['actif'] == true,
      nbEspaces: parseInt(map['nb_espaces']),
      updatedAt: parseDateTimeOrNull(map['updated_at']),
    );
  }

  /// Convertit un tableau JSON de codes en ensemble normalisé (minuscules,
  /// espaces retirés, doublons ignorés, valeurs non textuelles écartées).
  static Set<String> modulesDepuisJson(dynamic brut) {
    if (brut is! List) return const <String>{};

    final Set<String> resultat = <String>{};
    for (final dynamic item in brut) {
      if (item is String) {
        final String code = item.trim().toLowerCase();
        if (code.isNotEmpty) resultat.add(code);
      }
    }
    return resultat;
  }
}
