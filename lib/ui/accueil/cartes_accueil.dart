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
    this.page,
    this.action = ActionAccess.voir,
    this.priorite = 50,
    this.alerte,
  });

  /// Identifiant stable (tests + clés de widgets).
  final String id;

  /// Module requis (Module 16). `null` = carte de base (toujours éligible).
  final String? module;

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
    // 🗂️ MODULE 5 — produits (catalogue + conditionnements).
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
    // 💰 MODULE 10 — caisse (encaissements + clôtures).
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
  static List<CarteAccueil> visibles({
    required Set<String> modules,
    required bool profilCharge,
    required bool Function(PageAccess page, ActionAccess action) autorise,
  }) {
    final List<CarteAccueil> selection = registre.where((CarteAccueil carte) {
      // 1. Module de l'activité (fail-open si profil non chargé/vide).
      final String? module = carte.module;
      if (module != null &&
          !ModulesService.estActif(modules, profilCharge, module)) {
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
}
