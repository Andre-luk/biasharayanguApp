// lib/widgets/icones_pages.dart
//
// MODULE 4 — Icônes des pages de permission.
//
// Le modèle `PageAccess` est volontairement sans dépendance Flutter (il est
// testable sans binding) : la correspondance vers les icônes vit donc ici, dans
// la couche des widgets, et sert à construire les menus dynamiques.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/permission.dart';

/// Icône associée à une page. Jamais nulle : une page sans icône dédiée
/// reçoit [Icons.widgets_outlined].
IconData iconePourPage(PageAccess page) {
  switch (page) {
    case PageAccess.dashboard:
      return Icons.dashboard_customize_outlined;
    case PageAccess.entreprises:
      return Icons.business_rounded;
    case PageAccess.utilisateurs:
      return Icons.people_alt_rounded;
    case PageAccess.villes:
      return Icons.location_city_rounded;
    case PageAccess.activites:
      return Icons.category_rounded;
    case PageAccess.groupesTarifaires:
      return Icons.workspace_premium_rounded;
    case PageAccess.abonnements:
      return Icons.card_membership_rounded;
    // 🧾 MODULE 14 — écrans du workflow d'activation.
    case PageAccess.verificationComptes:
      return Icons.fact_check_rounded;
    case PageAccess.activationsFinance:
      return Icons.rocket_launch_rounded;
    case PageAccess.paiements:
      return Icons.payments_rounded;
    case PageAccess.finance:
      return Icons.account_balance_rounded;
    case PageAccess.audit:
      return Icons.history_edu_rounded;
    case PageAccess.securite:
      return Icons.security_rounded;
    case PageAccess.assistantIa:
      return Icons.smart_toy_rounded;
    case PageAccess.notifications:
      return Icons.notifications_active_rounded;
    case PageAccess.assistance:
      return Icons.support_agent_rounded;
    case PageAccess.parametres:
      return Icons.settings_applications_rounded;
    case PageAccess.ventes:
      return Icons.receipt_long_rounded;
    case PageAccess.caisse:
      return Icons.point_of_sale_rounded;
    case PageAccess.scanner:
      return Icons.qr_code_scanner_rounded;
    case PageAccess.panier:
      return Icons.shopping_cart_rounded;
    case PageAccess.articles:
      return Icons.inventory_2_rounded;
    case PageAccess.stock:
      return Icons.warehouse_rounded;
    case PageAccess.clients:
      return Icons.groups_rounded;
    case PageAccess.fournisseurs:
      return Icons.local_shipping_rounded;
    case PageAccess.depenses:
      return Icons.money_off_csred_rounded;
    case PageAccess.collaborateurs:
      return Icons.badge_rounded;
    case PageAccess.qrCodes:
      return Icons.qr_code_rounded;
    case PageAccess.rapports:
      return Icons.bar_chart_rounded;
    // 🏨 MODULE 16 C2 — hôtel.
    case PageAccess.chambres:
      return Icons.king_bed_rounded;
    case PageAccess.reservations:
      return Icons.event_available_rounded;
    case PageAccess.reception:
      return Icons.room_service_rounded;
    // 🍽️ MODULE 16 C3 — restaurant.
    case PageAccess.tables:
      return Icons.table_restaurant_rounded;
    case PageAccess.commandes:
      return Icons.restaurant_menu_rounded;
    case PageAccess.cuisine:
      return Icons.soup_kitchen_rounded;
    // 🎉 MODULE 16 C4 — salle des fêtes.
    case PageAccess.salles:
      return Icons.meeting_room_rounded;
    case PageAccess.evenements:
      return Icons.celebration_rounded;
    // 🥖 MODULE 16 C5 — boulangerie.
    case PageAccess.production:
      return Icons.bakery_dining_rounded;
  }
}

/// Libellé court de l'espace d'une page (« Plateforme », « Entreprise »,
/// « Les deux »), utilisé dans l'écran des permissions.
String libelleEspace(PageAccess page) {
  final bool plateforme = page.dansEspace(EspaceApplication.plateforme);
  final bool entreprise = page.dansEspace(EspaceApplication.entreprise);

  if (plateforme && entreprise) return 'Les deux';
  if (plateforme) return 'Plateforme';
  return 'Entreprise';
}
