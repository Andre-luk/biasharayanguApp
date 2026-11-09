// lib/ui/accueil/cartes_accueil.dart
//
// 🧩 MODULE 16 (phase B) — GRILLE D'ACCUEIL PILOTÉE PAR LES MODULES.
//
// Chaque MODULE de l'activité (Module 16, phase A) apporte SA carte
// d'accueil. La grille est construite à l'exécution :
//
//   cartes visibles = REGISTRE ∩ modules actifs du profil ∩ permissions
//
// Règles :
//   • Fail-open : profil non chargé ou vide → toutes les cartes compatibles
//     avec le rôle (comportement historique — zéro régression) ;
//   • Une carte SANS module (ex. « Mon abonnement ») est toujours éligible ;
//   • Pour ajouter la carte d'un module métier (phases C : chambres,
//     commandes…) : ajouter UNE entrée au registre ci-dessous — elle
//     n'apparaîtra que quand le module sera actif dans le profil.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/type_activite.dart';
import 'package:biashara_yangu/services/modules_service.dart';

/// Valeurs dynamiques affichées par les cartes (calculées par l'accueil).
class DonneesAccueil {
  const DonneesAccueil({
    this.produitsCount = 0,
    this.stockAlertes = 0,
    this.ventesJour = 0,
    this.expirationsCount = 0,
    this.chambresTotal = 0,
    this.chambresOccupees = 0,
    this.reservationsActives = 0,
    this.arriveesJour = 0,
    this.departsJour = 0,
    this.tablesTotal = 0,
    this.tablesOccupees = 0,
    this.commandesActives = 0,
    this.cuisineEnAttente = 0,
    this.sallesTotal = 0,
    this.sallesActives = 0,
    this.evenementsAVenir = 0,
    this.soldeEvenements = 0,
    this.matieresTotal = 0,
    this.matieresAlerte = 0,
    this.productionsJour = 0,
    this.tourneesActives = 0,
    this.consignesOuvertes = 0,
  });

  /// Nombre d'articles au catalogue.
  final int produitsCount;

  /// Nombre d'articles sous le seuil d'alerte.
  final int stockAlertes;

  /// Nombre de ventes du jour.
  final int ventesJour;

  /// 🧩 MODULE 16 C1 — produits expirés ou expirant sous 30 jours.
  final int expirationsCount;

  /// 🏨 MODULE 16 C2 — chambres actives de l'hôtel.
  final int chambresTotal;

  /// 🏨 chambres actuellement occupées.
  final int chambresOccupees;

  /// 🏨 séjours en attente ou en cours.
  final int reservationsActives;

  /// 🏨 arrivées attendues aujourd'hui (ou en retard).
  final int arriveesJour;

  /// 🏨 départs à enregistrer aujourd'hui.
  final int departsJour;

  /// 🍽️ MODULE 16 C3 — tables de salle actives.
  final int tablesTotal;

  /// 🍽️ tables actuellement occupées.
  final int tablesOccupees;

  /// 🍽️ commandes ni encaissées ni annulées.
  final int commandesActives;

  /// 🍽️ charge de la cuisine (en préparation + prêtes).
  final int cuisineEnAttente;

  /// 🎉 MODULE 16 C4 — salles de fête actives.
  final int sallesTotal;

  /// 🎉 salles actuellement répertoriées comme actives (miroir de
  /// [sallesTotal] hors salles désactivées).
  final int sallesActives;

  /// 🎉 événements réservés ou confirmés dont la date est à venir.
  final int evenementsAVenir;

  /// 🎉 solde à encaisser sur les événements non annulés.
  final double soldeEvenements;

  /// 🥖 MODULE 16 C5 — matières premières suivies (boulangerie).
  final int matieresTotal;

  /// 🥖 matières premières au niveau (ou sous) leur seuil d'alerte.
  final int matieresAlerte;

  /// 🥖 productions terminées aujourd'hui.
  final int productionsJour;

  /// 🚚 MODULE 23 — tournées préparées ou en cours.
  final int tourneesActives;

  /// 🚚 récipients de l'entreprise encore chez des clients.
  final int consignesOuvertes;
}

/// Une carte du tableau de bord d'accueil.
class CarteAccueil {
  const CarteAccueil({
    required this.id,
    required this.titre,
    required this.valeur,
    required this.icone,
    required this.couleur,
    required this.route,
    this.module,
    this.typeRequis,
    this.page,
    this.action = ActionAccess.voir,
    this.priorite = 50,
    this.alerte,
  });

  /// Identifiant stable (tests + clés de widgets).
  final String id;

  /// Module requis (Module 16). `null` = carte de base (toujours éligible).
  final String? module;

  /// ⚙️ REFONTE ABONNEMENTS & DISTRIBUTION — type d'activité requis.
  /// `null` = carte commune aux boutiques ET aux distributions.
  /// Renseigné = la carte n'apparaît que pour ce type d'entreprise ;
  /// si le type n'est pas renseigné en base, la carte reste visible
  /// (fail-open, aucune régression).
  final TypeActivite? typeRequis;

  /// Permission requise sur [page] / [action] (`null` = aucune).
  final PageAccess? page;
  final ActionAccess action;

  /// Ordre d'affichage (croissant).
  final int priorite;

  final String Function(AppLocalizations T) titre;
  final String Function(DonneesAccueil d, AppLocalizations T) valeur;
  final IconData icone;
  final Color couleur;

  /// Route ouverte au toucher.
  final String route;

  /// Mise en évidence conditionnelle (ex. alertes de stock).
  final bool Function(DonneesAccueil d)? alerte;

  // ---------------------------------------------------------------------------
  // LE REGISTRE — ajouter une carte d'accueil = ajouter une entrée ici.
  // ---------------------------------------------------------------------------

  static final List<CarteAccueil> registre = <CarteAccueil>[
    // 🚚 MODULE 24 — tableau de bord Distribution complet (production,
    // intrants, produits finis, commerciaux, caisse). Distinct de « Tournées ».
    CarteAccueil(
      id: 'distribution-pro',
      module: ModuleCode.distribution,
      typeRequis: TypeActivite.distribution,
      page: PageAccess.distribution,
      priorite: 21,
      titre: (AppLocalizations T) => 'Production & distribution',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Ouvrir',
      icone: Icons.factory_rounded,
      couleur: const Color(0xFF1D4ED8),
      route: '/main/distribution',
    ),
    // � MODULE 23 — distribution terrain (cartes transverses, sans module :
    // elles restent utiles à toute activité qui livre).
    CarteAccueil(
      id: 'tournees',
      module: ModuleCode.ventes,
      typeRequis: TypeActivite.distribution,
      page: PageAccess.distribution,
      priorite: 22,
      titre: (AppLocalizations T) => 'Tournées',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          '${d.tourneesActives}',
      icone: Icons.local_shipping_rounded,
      couleur: const Color(0xFF0F766E),
      route: '/main/tournees',
    ),
    CarteAccueil(
      id: 'consignes',
      module: ModuleCode.ventes,
      typeRequis: TypeActivite.distribution,
      page: PageAccess.distribution,
      priorite: 24,
      titre: (AppLocalizations T) => 'Consignes clients',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          d.consignesOuvertes == 0 ? 'À jour' : '${d.consignesOuvertes}',
      icone: Icons.inventory_2_rounded,
      couleur: const Color(0xFFB45309),
      route: '/main/tournees',
      alerte: (DonneesAccueil d) => d.consignesOuvertes > 0,
    ),
    CarteAccueil(
      id: 'ma-tournee',
      module: ModuleCode.ventes,
      typeRequis: TypeActivite.distribution,
      page: PageAccess.maTournee,
      priorite: 23,
      titre: (AppLocalizations T) => 'Ma tournée',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Ouvrir',
      icone: Icons.delivery_dining_rounded,
      couleur: const Color(0xFF9333EA),
      route: '/main/ma-tournee',
    ),
    // 🫙 REFONTE DISTRIBUTION — récipients, échanges et règles de bonus.
    CarteAccueil(
      id: 'recipients',
      module: ModuleCode.ventes,
      typeRequis: TypeActivite.distribution,
      page: PageAccess.distribution,
      priorite: 26,
      titre: (AppLocalizations T) => 'Récipients & bonus',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Ouvrir',
      icone: Icons.water_drop_rounded,
      couleur: const Color(0xFF0891B2),
      route: '/main/recipients',
    ),
    // �🗂️ MODULE 5 — produits (catalogue + conditionnements).
    CarteAccueil(
      id: 'produits',
      module: ModuleCode.produits,
      page: PageAccess.articles,
      priorite: 10,
      titre: (AppLocalizations T) => T.statProductsCount,
      valeur: (DonneesAccueil d, AppLocalizations T) => '${d.produitsCount}',
      icone: Icons.inventory_2_rounded,
      couleur: const Color(0xFF2563EB),
      route: '/main/articles',
    ),
    // 🏬 MODULE 9 — stock & alertes.
    CarteAccueil(
      id: 'stock',
      module: ModuleCode.stock,
      page: PageAccess.stock,
      priorite: 20,
      titre: (AppLocalizations T) => T.statStockStatus,
      valeur: (DonneesAccueil d, AppLocalizations T) => '${d.stockAlertes}',
      icone: Icons.warning_amber_rounded,
      couleur: const Color(0xFFF59E0B),
      route: '/main/stock',
      alerte: (DonneesAccueil d) => d.stockAlertes > 0,
    ),
    // 💊 MODULE 16 C1 — pharmacie : produits expirés / bientôt périmés.
    CarteAccueil(
      id: 'expirations',
      module: ModuleCode.lotsExpiration,
      page: PageAccess.articles,
      priorite: 25,
      titre: (AppLocalizations T) => 'Expirations',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          d.expirationsCount == 0 ? 'À jour' : '${d.expirationsCount}',
      icone: Icons.medication_rounded,
      couleur: const Color(0xFFDC2626),
      route: '/main/articles/expirations',
      alerte: (DonneesAccueil d) => d.expirationsCount > 0,
    ),
    // 🏨 MODULE 16 C2 — hôtel : occupation des chambres.
    CarteAccueil(
      id: 'chambres',
      module: ModuleCode.chambres,
      page: PageAccess.chambres,
      priorite: 12,
      titre: (AppLocalizations T) => 'Chambres',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          '${d.chambresOccupees}/${d.chambresTotal}',
      icone: Icons.king_bed_rounded,
      couleur: const Color(0xFF0369A1),
      route: '/main/hotel/chambres',
    ),
    // 🏨 MODULE 16 C2 — hôtel : planning des réservations.
    CarteAccueil(
      id: 'reservations',
      module: ModuleCode.reservations,
      page: PageAccess.reservations,
      priorite: 14,
      titre: (AppLocalizations T) => 'Réservations',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          d.reservationsActives == 0 ? 'À jour' : '${d.reservationsActives}',
      icone: Icons.event_available_rounded,
      couleur: const Color(0xFF0F766E),
      route: '/main/hotel/reservations',
    ),
    // 🏨 MODULE 16 C2 — hôtel : réception (arrivées / départs du jour).
    CarteAccueil(
      id: 'checkin',
      module: ModuleCode.checkin,
      page: PageAccess.reception,
      priorite: 16,
      titre: (AppLocalizations T) => 'Réception',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          '${d.arriveesJour}/${d.departsJour}',
      icone: Icons.room_service_rounded,
      couleur: const Color(0xFF9333EA),
      route: '/main/hotel/reception',
      alerte: (DonneesAccueil d) =>
          d.arriveesJour > 0 || d.departsJour > 0,
    ),
    // 🧺 MODULE 35 — pressing : dépôts, vêtements confiés et retraits.
    //    (Le détail chiffré vit dans l'écran du module : pas de compteur
    //     inventé sur l'accueil.)
    CarteAccueil(
      id: 'pressing',
      module: ModuleCode.pressDepots,
      page: PageAccess.pressingDepots,
      priorite: 13,
      titre: (AppLocalizations T) => 'Pressing',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Dépôts & retraits',
      icone: Icons.local_laundry_service_rounded,
      couleur: const Color(0xFF2563EB),
      route: '/main/pressing/depots',
    ),
    // 🍽️ MODULE 16 C3 — restaurant : occupation des tables.
    CarteAccueil(
      id: 'tables',
      module: ModuleCode.tables,
      page: PageAccess.tables,
      priorite: 13,
      titre: (AppLocalizations T) => 'Tables',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          '${d.tablesOccupees}/${d.tablesTotal}',
      icone: Icons.table_restaurant_rounded,
      couleur: const Color(0xFFEA580C),
      route: '/main/restaurant/tables',
    ),
    // 🍽️ MODULE 16 C3 — restaurant : commandes actives.
    CarteAccueil(
      id: 'commandes',
      module: ModuleCode.commandes,
      page: PageAccess.commandes,
      priorite: 15,
      titre: (AppLocalizations T) => 'Commandes',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          d.commandesActives == 0 ? 'À jour' : '${d.commandesActives}',
      icone: Icons.restaurant_menu_rounded,
      couleur: const Color(0xFFB45309),
      route: '/main/restaurant/commandes',
    ),
    // 🍽️ MODULE 16 C3 — restaurant : cuisine (en préparation + prêtes).
    CarteAccueil(
      id: 'cuisine',
      module: ModuleCode.cuisine,
      page: PageAccess.cuisine,
      priorite: 17,
      titre: (AppLocalizations T) => 'Cuisine',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          '${d.cuisineEnAttente}',
      icone: Icons.soup_kitchen_rounded,
      couleur: const Color(0xFFB91C1C),
      route: '/main/restaurant/cuisine',
      alerte: (DonneesAccueil d) => d.cuisineEnAttente > 0,
    ),
    // 🎉 MODULE 16 C4 — salle des fêtes : calendrier des événements.
    CarteAccueil(
      id: 'evenements',
      module: ModuleCode.evenements,
      page: PageAccess.evenements,
      priorite: 18,
      titre: (AppLocalizations T) => 'Événements',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          '${d.evenementsAVenir}',
      icone: Icons.celebration_rounded,
      couleur: const Color(0xFF7C3AED),
      route: '/main/evenements',
      alerte: (DonneesAccueil d) => d.evenementsAVenir > 0,
    ),
    // 🎉 MODULE 16 C4 — salle des fêtes : salles disponibles.
    CarteAccueil(
      id: 'salles',
      module: ModuleCode.salles,
      page: PageAccess.salles,
      priorite: 19,
      titre: (AppLocalizations T) => 'Salles',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          d.sallesTotal == 0 ? 'À créer' : '${d.sallesActives}/${d.sallesTotal}',
      icone: Icons.meeting_room_rounded,
      couleur: const Color(0xFF9333EA),
      route: '/main/evenements/salles',
    ),
    // 🥖 MODULE 16 C5 — boulangerie : productions du jour (+ alertes matières).
    CarteAccueil(
      id: 'production',
      module: ModuleCode.production,
      page: PageAccess.production,
      priorite: 21,
      titre: (AppLocalizations T) => 'Production',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          '${d.productionsJour}',
      icone: Icons.bakery_dining_rounded,
      couleur: const Color(0xFFB45309),
      route: '/main/production',
      alerte: (DonneesAccueil d) => d.matieresAlerte > 0,
    ),
    // 🧾 MODULE 8 — historique des ventes.
    CarteAccueil(
      id: 'ventes',
      module: ModuleCode.ventes,
      page: PageAccess.ventes,
      priorite: 30,
      titre: (AppLocalizations T) => 'Mes ventes',
      valeur: (DonneesAccueil d, AppLocalizations T) => '${d.ventesJour}',
      icone: Icons.receipt_long_rounded,
      couleur: const Color(0xFF16A34A),
      route: '/main/ventes',
    ),
    // 👥 MODULE 10 — clients, crédits et remboursements.
    CarteAccueil(
      id: 'clients',
      module: ModuleCode.clients,
      page: PageAccess.clients,
      priorite: 40,
      titre: (AppLocalizations T) => 'Clients & dettes',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Clients',
      icone: Icons.people_alt_rounded,
      couleur: const Color(0xFF0EA5E9),
      route: '/main/clients',
    ),
    // � MODULE 19 — la vitrine publique de la boutique (position, horaires,
    // contacts, articles à publier). Volontairement SANS module d'activité :
    // le marketplace est transverse — une boutique, un hôtel, une pharmacie ou
    // un salon peuvent y figurer.
    CarteAccueil(
      id: 'publications',
      page: PageAccess.publications,
      priorite: 45,
      titre: (AppLocalizations T) => 'Ma vitrine Biashara',
      valeur: (DonneesAccueil d, AppLocalizations T) =>
          d.produitsCount == 0 ? 'À préparer' : 'Publier',
      icone: Icons.storefront_rounded,
      couleur: const Color(0xFF0EA5E9),
      route: '/main/vitrine',
    ),
    // 🛒 MODULE 19 — tableau de bord « Ma visibilité Biashara » : ce que
    // Biashara apporte réellement (affichages, intérêt, intentions, ventes
    // attribuées).
    CarteAccueil(
      id: 'visibilite',
      page: PageAccess.visibilite,
      priorite: 46,
      titre: (AppLocalizations T) => 'Ma visibilité',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Voir',
      icone: Icons.insights_rounded,
      couleur: const Color(0xFF16A34A),
      route: '/main/visibilite',
    ),
    // 🛒 MODULE 19 — campagnes publicitaires (toujours marquées « PUBLICITÉ »
    // et jamais mélangées aux résultats organiques).
    CarteAccueil(
      id: 'publicites',
      page: PageAccess.publicites,
      priorite: 47,
      titre: (AppLocalizations T) => 'Publicités',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Gérer',
      icone: Icons.campaign_rounded,
      couleur: const Color(0xFFF08A4B),
      route: '/main/publicites',
    ),
    // �💰 MODULE 10 — caisse (encaissements + clôtures).
    CarteAccueil(
      id: 'caisse',
      module: ModuleCode.caisse,
      page: PageAccess.caisse,
      priorite: 50,
      titre: (AppLocalizations T) => 'Solde & clôture',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Caisse',
      icone: Icons.account_balance_wallet_rounded,
      couleur: const Color(0xFF0D9488),
      route: '/main/caisse',
    ),
    // 💰 MODULE 10 — tableau de bord financier.
    CarteAccueil(
      id: 'finance',
      module: ModuleCode.finance,
      page: PageAccess.finance,
      priorite: 60,
      titre: (AppLocalizations T) => 'CA & bénéfice',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Finance',
      icone: Icons.insights_rounded,
      couleur: const Color(0xFF7C3AED),
      route: '/main/finance',
    ),
    // 📊 MODULE 11 — rapports & exports (PDF / Excel signés).
    CarteAccueil(
      id: 'rapports',
      module: ModuleCode.rapports,
      page: PageAccess.rapports,
      priorite: 70,
      titre: (AppLocalizations T) => 'Rapports & exports',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Rapports',
      icone: Icons.bar_chart_rounded,
      couleur: const Color(0xFF8B5E34),
      route: '/main/rapports',
    ),
    // 🤖 MODULE 13 — assistant IA.
    CarteAccueil(
      id: 'assistant_ia',
      module: ModuleCode.assistantIa,
      page: PageAccess.assistantIa,
      priorite: 80,
      titre: (AppLocalizations T) => 'Assistant IA',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Conseils',
      icone: Icons.smart_toy_rounded,
      couleur: const Color(0xFFDB2777),
      route: '/assistant-ia',
    ),
    // 🧾 MODULE 14 — suivi du dossier d'activation (carte de base, sans module).
    CarteAccueil(
      id: 'abonnement',
      page: PageAccess.dashboard,
      priorite: 90,
      titre: (AppLocalizations T) => 'Mon abonnement',
      valeur: (DonneesAccueil d, AppLocalizations T) => 'Suivi',
      icone: Icons.verified_user_rounded,
      couleur: const Color(0xFFB45309),
      route: '/main/mon-activation',
    ),
  ];

  /// Cartes visibles pour un état donné — PUR (testable sans réseau).
  ///
  /// [modules] : modules du profil actif ; [profilCharge] : un profil serveur
  /// a-t-il été reçu ? (sinon fail-open) ; [autorise] : matrice de permissions
  /// du rôle courant.
  ///
  /// 🚚 MODULE 24 — [universDistribution] et [masquerTournees] séparent les
  /// deux univers :
  ///   • [universDistribution] : un compte de distribution ne voit PLUS les
  ///     cartes de la boutique (Stock, Ventes, Caisse, Rapports…). Il travaille
  ///     dans SES écrans (`dist_*`), qui ont leur propre stock et leur propre
  ///     caisse ;
  ///   • [masquerTournees] : le module 24 complet remplace les cartes
  ///     « Tournées », « Ma tournée », « Consignes clients » et « Récipients &
  ///     bonus » du module 23.
  /// Valeurs par défaut `false` : aucune régression pour les boutiques.
  static List<CarteAccueil> visibles({
    required Set<String> modules,
    required bool profilCharge,
    required bool Function(PageAccess page, ActionAccess action) autorise,
    TypeActivite? typeActivite,
    bool universDistribution = false,
    bool masquerTournees = false,
  }) {
    final List<CarteAccueil> selection = registre.where((CarteAccueil carte) {
      // 0. Séparation des univers (module 24).
      if (masquerTournees && _idsTournees.contains(carte.id)) return false;
      if (universDistribution && _idsBoutique.contains(carte.id)) return false;

      // 1. Module de l'activité (fail-open si profil non chargé/vide).
      final String? module = carte.module;
      if (module != null &&
          !ModulesService.estActif(modules, profilCharge, module)) {
        return false;
      }

      // 1 bis. Type d'activité (boutique / distribution). Fail-open : un type
      // non renseigné ne masque rien.
      if (ReglesTypeActivite.masque(typeActivite, carte.typeRequis)) {
        return false;
      }

      // 2. Permissions du rôle.
      final PageAccess? page = carte.page;
      if (page != null && !autorise(page, carte.action)) return false;

      return true;
    }).toList(growable: false);

    final List<CarteAccueil> triees = selection.toList()
      ..sort(
          (CarteAccueil a, CarteAccueil b) => a.priorite.compareTo(b.priorite));
    return triees;
  }

  /// Cartes propres à la BOUTIQUE : masquées dès que le compte travaille dans
  /// une distribution (module 24), car le module a son propre stock, ses
  /// ventes, sa caisse et son tableau de bord.
  static const Set<String> _idsBoutique = <String>{
    'produits',
    'stock',
    'expirations',
    'chambres',
    'reservations',
    'checkin',
    'tables',
    'commandes',
    'cuisine',
    'evenements',
    'salles',
    'production',
    'ventes',
    'clients',
    'publications',
    'visibilite',
    'publicites',
    'caisse',
    'finance',
    'rapports',
  };

  /// Cartes du module 23 (tournées) : un module 24 complet les remplace.
  static const Set<String> _idsTournees = <String>{
    'tournees',
    'consignes',
    'ma-tournee',
    'recipients',
  };
}
