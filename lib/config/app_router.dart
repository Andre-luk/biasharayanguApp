import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ================== MODÈLES ==================
import 'package:biashara_yangu/models/activite.dart';
import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/etiquette_qr.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
// 🧩 MODULE 16 — profils de modules des types d'activités.
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
// 🛒 MODULE 19 — campagne publicitaire passée en `extra` pour l'édition.
import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart';

// ================== SERVICES ==================
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';

// ================== PAGES ==================
import 'package:biashara_yangu/pages/login_page.dart';
import 'package:biashara_yangu/pages/setup_page.dart';
import 'package:biashara_yangu/pages/home_page.dart';
// 🧾 MODULE 17 — page « compte verrouillé » (activation en attente, échu…).
import 'package:biashara_yangu/pages/compte_verrouille_page.dart';
// 🪙 MODULE 18 — devises de travail et taux de conversion.
import 'package:biashara_yangu/pages/devise_page.dart';
// 📊 MODULE 11 — RAPPORTS & EXPORTS. L'ancien écran `reports_page.dart`
// (SQLite) est débranché ; le fichier est conservé comme pour les Modules 9/10.
import 'package:biashara_yangu/pages/rapports_page.dart';
import 'package:biashara_yangu/pages/settings_page.dart'; // Contient SettingsPage et AboutPage
import 'package:biashara_yangu/pages/new_sale_page.dart';
import 'package:biashara_yangu/pages/admin_home_page.dart';
import 'package:biashara_yangu/pages/scaffold_with_nav_bar.dart';
import 'package:biashara_yangu/pages/profile_edit_page.dart';
import 'package:biashara_yangu/pages/change_password_page.dart';
import 'package:biashara_yangu/pages/manage_categories_page.dart';
import 'package:biashara_yangu/pages/subscription_expired_page.dart';

// 👇 NOUVELLES PAGES DE SUIVI
import 'package:biashara_yangu/pages/inventaires_page.dart';
import 'package:biashara_yangu/pages/commercial_hub_page.dart';
import 'package:biashara_yangu/pages/clients_page.dart';

// 💰 MODULE 10 — FINANCE DE L'ENTREPRISE (caisse, dépenses, dettes, rapports)
//
// Les anciens écrans SQLite `DepensesPage` / `DettesPage` sont débranchés
// (fichiers conservés, comme le stock du Module 9) : ces écrans écrivent
// désormais dans Supabase via les RPC du Module 10.
import 'package:biashara_yangu/pages/caisse_page.dart';
import 'package:biashara_yangu/pages/cloture_caisse_page.dart';
import 'package:biashara_yangu/pages/finance_dashboard_page.dart';
import 'package:biashara_yangu/pages/rapports_finance_page.dart';
import 'package:biashara_yangu/pages/depenses_finance_page.dart';
import 'package:biashara_yangu/pages/depense_finance_form_page.dart';
import 'package:biashara_yangu/pages/dettes_clients_page.dart';
import 'package:biashara_yangu/pages/dette_form_page.dart';

// ================== UTILISATEURS ==================
import 'package:biashara_yangu/pages/manage_users_page.dart';
import 'package:biashara_yangu/pages/add_user_page.dart';
import 'package:biashara_yangu/pages/collaborateurs_stats_page.dart';

// ================== MODULE 1 : ENTREPRISES ==================
import 'package:biashara_yangu/pages/entreprise_creation_page.dart';
import 'package:biashara_yangu/pages/entreprise_detail_page.dart';
import 'package:biashara_yangu/pages/entreprise_fiche_page.dart';
import 'package:biashara_yangu/pages/entreprise_form_page.dart';

// ============ MODULE 2 : ACTIVITÉS & GROUPES TARIFAIRES ============
import 'package:biashara_yangu/pages/activite_form_page.dart';
import 'package:biashara_yangu/pages/activites_page.dart';
import 'package:biashara_yangu/pages/groupe_tarifaire_form_page.dart';
import 'package:biashara_yangu/pages/groupes_tarifaires_page.dart';

// ===== MODULE 16 : TYPES D'ACTIVITÉS & MODULES (multi-activités) =====
import 'package:biashara_yangu/pages/type_activite_form_page.dart';
import 'package:biashara_yangu/pages/types_activites_page.dart';

// ================== MODULE 3 : MOTEUR D'ABONNEMENT ==================
import 'package:biashara_yangu/pages/abonnement_detail_page.dart';
import 'package:biashara_yangu/pages/niveau_abonnement_form_page.dart';
import 'package:biashara_yangu/pages/niveau_entreprise_page.dart';
import 'package:biashara_yangu/pages/niveaux_abonnement_page.dart';
import 'package:biashara_yangu/pages/paiement_abonnement_page.dart';

// ============= MODULE 4 : PERMISSIONS (RÔLES & ACCÈS) =============
import 'package:biashara_yangu/pages/permissions_role_page.dart';

// ========== MODULE 5 : ARTICLES & CATALOGUE (CONDITIONNEMENTS) ==========
import 'package:biashara_yangu/pages/article_detail_page.dart';
import 'package:biashara_yangu/pages/article_form_page.dart';
import 'package:biashara_yangu/pages/articles_page.dart';
import 'package:biashara_yangu/pages/categories_page.dart';
import 'package:biashara_yangu/pages/conditionnement_form_page.dart';
// 🧩 MODULE 16 C1 — écran « Expirations » (pharmacie : lots & péremption).
import 'package:biashara_yangu/pages/expirations_page.dart';
// ⚖️ Conditions d'utilisation (droit congolais — Lubumbashi, RDC).
import 'package:biashara_yangu/pages/conditions_utilisation_page.dart';
// 🏨 MODULE 16 C2 — hôtel : chambres, réservations, réception & facture.
import 'package:biashara_yangu/models/chambre.dart';
import 'package:biashara_yangu/models/reservation.dart';
import 'package:biashara_yangu/pages/chambre_form_page.dart';
import 'package:biashara_yangu/pages/chambres_page.dart';
import 'package:biashara_yangu/pages/facture_sejour_page.dart';
import 'package:biashara_yangu/pages/reception_page.dart';
import 'package:biashara_yangu/pages/reservation_form_page.dart';
import 'package:biashara_yangu/pages/reservations_page.dart';
// 🍽️ MODULE 16 C3 — restaurant : plan de salle, commandes & cuisine.
import 'package:biashara_yangu/models/commande.dart';
import 'package:biashara_yangu/models/table_salle.dart';
import 'package:biashara_yangu/pages/commande_detail_page.dart';
import 'package:biashara_yangu/pages/commandes_page.dart';
import 'package:biashara_yangu/pages/cuisine_page.dart';
import 'package:biashara_yangu/pages/table_salle_form_page.dart';
import 'package:biashara_yangu/pages/tables_salle_page.dart';
// 🎉 MODULE 16 C4 — salle des fêtes : salles, événements & dossier.
import 'package:biashara_yangu/models/evenement.dart';
import 'package:biashara_yangu/models/salle.dart';
import 'package:biashara_yangu/pages/evenement_detail_page.dart';
import 'package:biashara_yangu/pages/evenement_form_page.dart';
import 'package:biashara_yangu/pages/evenements_page.dart';
import 'package:biashara_yangu/pages/salle_form_page.dart';
import 'package:biashara_yangu/pages/salles_page.dart';
// 🥖 MODULE 16 C5 — boulangerie : matières premières & productions.
import 'package:biashara_yangu/models/matiere_premiere.dart';
import 'package:biashara_yangu/models/production.dart';
import 'package:biashara_yangu/pages/matiere_form_page.dart';
import 'package:biashara_yangu/pages/matieres_premieres_page.dart';
import 'package:biashara_yangu/pages/production_detail_page.dart';
import 'package:biashara_yangu/pages/production_form_page.dart';
import 'package:biashara_yangu/pages/productions_page.dart';

// ============== MODULE 6 : GÉNÉRATION DES QR CODES ==============
import 'package:biashara_yangu/pages/qr_apercu_page.dart';
import 'package:biashara_yangu/pages/qr_codes_page.dart';

// ============== MODULE 7 : INTERFACE VENDEUR (SCANNER) ==============
import 'package:biashara_yangu/pages/scanner_page.dart';

// ========== MODULE 12 : AUDIT, SÉCURITÉ & IMPORT DE PRODUITS ==========
import 'package:biashara_yangu/pages/factures_abonnement_page.dart';
import 'package:biashara_yangu/pages/import_produits_page.dart';
import 'package:biashara_yangu/pages/journal_audit_page.dart';
import 'package:biashara_yangu/pages/securite_page.dart';

// ========== MODULE 13 : ASSISTANT IA (DEEPSEEK) ==========
import 'package:biashara_yangu/pages/achat_quotas_page.dart';
import 'package:biashara_yangu/pages/agent_abonnements_page.dart';
import 'package:biashara_yangu/pages/agent_ia_config_page.dart';
import 'package:biashara_yangu/pages/tokens_ia_page.dart';
import 'package:biashara_yangu/pages/assistant_ia_page.dart';

// ========== AIDE, ACCESSIBILITÉ & INFORMATIONS LÉGALES ==========
import 'package:biashara_yangu/pages/accessibilite_page.dart';
import 'package:biashara_yangu/pages/guide_utilisation_page.dart';
import 'package:biashara_yangu/pages/politique_confidentialite_page.dart';

// ========== MODULE 14 : ACTIVATION À DOUBLE VALIDATION ==========
import 'package:biashara_yangu/pages/activations_finance_page.dart';
// 🛡️ MODULE 20 — administration plateforme (audit final) : parc des boutiques
// et modération du catalogue public.
import 'package:biashara_yangu/pages/admin_boutiques_page.dart';
import 'package:biashara_yangu/pages/admin_moderation_page.dart';
import 'package:biashara_yangu/pages/comptes_verification_page.dart';
import 'package:biashara_yangu/pages/mon_activation_page.dart';
// ========== MODULE 15 : PACK MULTI-ENTREPRISES ==========
import 'package:biashara_yangu/pages/mes_entreprises_page.dart';

// ===== MODULE 19 : MARKETPLACE LOCAL GÉOLOCALISÉ (« BIASHARA ») =====
//
//  • Pages PUBLIQUES (aucune règle de permission : accessibles sans compte) :
//    page d'accueil publique, recherche, fiche boutique partageable, fiche
//    produit avec comparaison des prix, carte interactive.
//  • Pages COMMERÇANT (permissions `publications`, `visibilite`, `publicites`) :
//    vitrine/localisation, publications, tableau de bord de visibilité et
//    campagnes publicitaires.
import 'package:biashara_yangu/pages/ma_vitrine_page.dart';
import 'package:biashara_yangu/pages/marketplace_boutique_page.dart';
import 'package:biashara_yangu/pages/marketplace_carte_page.dart';
import 'package:biashara_yangu/pages/marketplace_produit_page.dart';
import 'package:biashara_yangu/pages/marketplace_recherche_page.dart';
import 'package:biashara_yangu/pages/marketplace_welcome_page.dart';
import 'package:biashara_yangu/pages/mes_publications_page.dart';
import 'package:biashara_yangu/pages/publicite_biashara_form_page.dart';
import 'package:biashara_yangu/pages/publicites_biashara_page.dart';
import 'package:biashara_yangu/pages/visibilite_biashara_page.dart';

// ========== MODULE 8 : PANIER & VALIDATION DE VENTE ==========
import 'package:biashara_yangu/pages/panier_page.dart';
import 'package:biashara_yangu/pages/encaissement_page.dart';
import 'package:biashara_yangu/pages/vente_confirmation_page.dart';
import 'package:biashara_yangu/pages/mes_ventes_page.dart';

// ========== MODULE 9 : GESTION DU STOCK (CONVERSIONS MULTI-UNITÉS) ==========
//
// L'écran « Stock » remplace les anciens écrans locaux (SQLite) : le module 9
// lit/écrit Supabase (le stock est mis à jour par les triggers serveur des
// mouvements : ventes, approvisionnements, ajustements).
import 'package:biashara_yangu/pages/stock_gestion_page.dart';
import 'package:biashara_yangu/pages/stock_detail_page.dart';
import 'package:biashara_yangu/pages/approvisionnement_form_page.dart';
import 'package:biashara_yangu/pages/ajustement_form_page.dart';
import 'package:biashara_yangu/pages/inventaire_cloture_page.dart';

// ================== NAV KEYS ==================
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> shellNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> settingsBranchKey = GlobalKey<NavigatorState>();

// ================== ROUTER ==================
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/login',

  // ==========================================================================
  //  🔐 MODULE 4 — MIDDLEWARE DE PERMISSIONS
  // ==========================================================================
  //  Vérifie les droits AVANT chaque navigation.
  //
  //  Ordre des contrôles (imposé par le cahier des charges) :
  //    1. l'abonnement (Module 3) — un abonnement suspendu bloque l'accès,
  //       un abonnement échu met l'application en lecture seule. Ce contrôle
  //       a lieu à la connexion, avant que cette fonction ne s'exécute ;
  //    2. les permissions du rôle — ce redirect.
  //
  //  Comportement :
  //    • tant que les permissions ne sont pas chargées (`pret == false`) ou
  //      que le rôle est inconnu (écran de connexion, session restaurée en
  //      cours d'initialisation), on ne bloque RIEN : il vaut mieux laisser
  //      passer que verrouiller l'application sur un état transitoire ;
  //    • 🔒 MODULE 17 — un compte NON OPÉRATIONNEL (activation en attente de
  //      la finance, abonnement échu, compte restreint ou suspendu) ne peut
  //      pas ouvrir les ÉCRANS COMMERCIAUX, même par lien direct : il est
  //      renvoyé vers `/main/compte-verrouille` qui explique la situation.
  //      La consultation (accueil, rapports, stock, caisse, finance…) reste
  //      toujours accessible ;
  //    • une URL sans règle (connexion, inscription, pages libres) est
  //      toujours autorisée ;
  //    • en cas de refus, l'utilisateur est ramené sur la première page de
  //      son rôle, jamais sur une page interdite.
  redirect: (BuildContext context, GoRouterState state) {
    final PermissionService permissions = PermissionService.instance;
    final RoleUtilisateur role = permissions.roleCourant;

    if (!permissions.pret || role == RoleUtilisateur.inconnu) return null;

    final String location = state.uri.path;

    // 🔒 MODULE 17 — verrou commercial : même par lien direct, un compte non
    // opérationnel n'accède pas aux écrans d'opération.
    if (location != '/main/compte-verrouille' &&
        AbonnementService.instance.operationsVerrouillees &&
        AbonnementService.cheminVerrouille(location)) {
      return '/main/compte-verrouille';
    }

    // La page de verrou est purement informative : accessible à TOUS les
    // rôles de l'entreprise (sinon les rôles sans tableau de bord
    // rebondiraient en boucle entre leur accueil verrouillé et cette page).
    if (location == '/main/compte-verrouille') return null;

    if (permissions.routeAutorisee(location)) return null;

    final String? accueil = permissions.accueilPour(role);
    if (accueil == null) return '/login';
    if (accueil == location) return null;

    return accueil;
  },

  routes: [
    // ================== AUTHENTIFICATION ==================
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/setup',
      name: 'setup',
      builder: (context, state) => const SetupPage(),
    ),

    GoRoute(
      path: '/subscription-expired',
      name: 'subscription-expired',
      builder: (context, state) => const SubscriptionExpiredPage(),
    ),

    // ================== MODULE 7 : SCANNER VENDEUR ==================
    // Écran plein écran (caméra) : volontairement placé HORS de la coquille
    // de navigation pour que la barre d'onglets ne recouvre pas la caméra.
    // Le contrôle du rôle et de l'abonnement est fait par la page elle-même,
    // en plus du middleware de permissions (`/scanner` → page `scanner`).
    GoRoute(
      path: '/scanner',
      name: 'scanner',
      builder: (context, state) => const ScannerPage(),
    ),

    // ========== MODULE 12 : AUDIT, SÉCURITÉ & IMPORT DE PRODUITS ==========
    //
    // Routes plein écran de premier niveau (comme `/scanner`) : l'accès est
    // contrôlé par le middleware de permissions (`/audit` → page `audit`,
    // `/securite` → page `securite`, `/import-produits` → `articles/créer`)
    // ET revérifié côté serveur par les RPC du module.
    GoRoute(
      path: '/audit',
      name: 'journal-audit',
      builder: (context, state) => const JournalAuditPage(),
    ),
    GoRoute(
      path: '/securite',
      name: 'securite',
      builder: (context, state) => const SecuritePage(),
    ),
    GoRoute(
      path: '/import-produits',
      name: 'import-produits',
      builder: (context, state) => const ImportProduitsPage(),
    ),

    // 🧾 CORRECTIF 67 — FACTURES D'ABONNEMENT. Route de premier niveau : elle
    // sert dans les deux espaces (la plateforme gère toutes les factures, le
    // client consulte les siennes).
    //   • plateforme → choix de la boutique, puis ses factures ;
    //   • entreprise → directement les siennes (le serveur filtre de toute
    //     façon : même si l'URL était forcée, la RPC ne renverrait que ce que
    //     l'appelant a le droit de voir).
    GoRoute(
      path: '/factures-abonnement',
      name: 'factures-abonnement',
      builder: (context, state) {
        final bool plateforme = PermissionService.instance.roleCourant
            .estPlateforme;

        return plateforme
            ? const FacturesAbonnementBoutiquePage()
            : const FacturesAbonnementPage();
      },
    ),

    // 🏢 MODE PLATEFORME — production des étiquettes QR des boutiques
    // (service de l'administration : le patron n'a plus cet écran).
    GoRoute(
      path: '/admin/qr-codes',
      name: 'admin-qr-codes',
      builder: (context, state) => const QrCodesPage(modePlateforme: true),
    ),

    // 🪙 MODULE 18 — devises : taux de change par défaut de la plateforme et
    // configuration ponctuelle d'une entreprise (Super Admin).
    GoRoute(
      path: '/admin/devises',
      name: 'admin-devises',
      builder: (context, state) => const DevisePage(modePlateforme: true),
    ),

    // 🛒 MODULE 19 — modération des campagnes publicitaires (plateforme) :
    // seules les campagnes ACTIVÉES ici sont diffusées dans le catalogue.
    GoRoute(
      path: '/admin/publicites',
      name: 'admin-publicites',
      builder: (context, state) =>
          const PublicitesBiasharaPage(modePlateforme: true),
    ),

    // 🧾 MODULE 14 — workflow d'activation à double validation.
    //  • « Comptes à vérifier » (GESTIONNAIRE DES COMPTES) : première
    //    validation, transmission à la finance ou rejet motivé ;
    //  • « Activations & paiements » (FINANCE) : validation du paiement et
    //    activation automatique du compte.
    // Le middleware exige `verification_comptes/voir` (resp.
    // `activations_finance/voir`) et les RPC revérifient le rôle serveur.
    GoRoute(
      path: '/admin/verification-comptes',
      name: 'admin-verification-comptes',
      builder: (context, state) => const ComptesVerificationPage(),
    ),
    GoRoute(
      path: '/admin/activations-finance',
      name: 'admin-activations-finance',
      builder: (context, state) => const ActivationsFinancePage(),
    ),

    // 🛡️ MODULE 20 — ADMINISTRATION PLATEFORME (audit final) : parc des
    // boutiques de toutes les entreprises et modération du catalogue public.
    // Le middleware exige `boutiques/voir` (resp. `moderation/voir`) et
    // chaque RPC revérifie `est_plateforme()` côté serveur.
    GoRoute(
      path: '/admin/boutiques',
      name: 'admin-boutiques',
      builder: (context, state) => const AdminBoutiquesPage(),
    ),
    GoRoute(
      path: '/admin/moderation',
      name: 'admin-moderation',
      builder: (context, state) => const AdminModerationPage(),
    ),

    // ========== MODULE 13 : ASSISTANT IA (DEEPSEEK) ==========
    //
    // Le chat (et la gestion des quotas) passe par l'Edge Function « agent-ia »
    // — jamais directement à DeepSeek. La configuration IA est réservée au
    // Super Admin (règle `parametres/modifier` + revérification serveur).
    GoRoute(
      path: '/assistant-ia',
      name: 'assistant-ia',
      builder: (context, state) => const AssistantIaPage(),
    ),
    GoRoute(
      path: '/achat-quotas',
      name: 'achat-quotas',
      builder: (context, state) => const AchatQuotasPage(),
    ),
    GoRoute(
      path: '/agent-ia-config',
      name: 'agent-ia-config',
      builder: (context, state) => const AgentIaConfigPage(),
    ),

    // 🧩 CORRECTIF 76 — LES ABONNEMENTS DES BOUTIQUES DE L'AGENT TERRAIN :
    // il suit les comptes qu'il a créés ou pris en charge (étape d'activation,
    // échéance, jours restants, encaissé, solde). Lecture seule : la Finance
    // reste seule à encaisser et à activer.
    GoRoute(
      path: '/agent/abonnements',
      name: 'agent-abonnements',
      builder: (context, state) => const AgentAbonnementsPage(),
    ),
    GoRoute(
      path: '/tokens-ia',
      name: 'tokens-ia',
      builder: (context, state) => const TokensIaPage(),
    ),

    // 🧩 CORRECTIF 65 — niveau d'abonnement d'UNE entreprise : niveau choisi,
    // fonctionnalités négociées, et ce qui est réellement appliqué.
    GoRoute(
      path: '/entreprise/:id/niveau',
      name: 'entreprise-niveau',
      builder: (context, state) => NiveauEntreprisePage(
        entrepriseId: state.pathParameters['id'] ?? '',
      ),
    ),

    // 🧩 CORRECTIF 65 — catalogue des NIVEAUX D'ABONNEMENT (Super Admin) :
    // ce que chaque niveau ouvre comme fonctionnalités.
    GoRoute(
      path: '/niveaux-abonnement',
      name: 'niveaux-abonnement',
      builder: (context, state) => const NiveauxAbonnementPage(),
      routes: <RouteBase>[
        GoRoute(
          path: 'nouveau',
          name: 'niveau-abonnement-nouveau',
          builder: (context, state) => const NiveauAbonnementFormPage(),
        ),
        GoRoute(
          path: ':code',
          name: 'niveau-abonnement-fiche',
          builder: (context, state) => NiveauAbonnementFormPage(
            code: state.pathParameters['code'],
          ),
        ),
      ],
    ),

    // ========== AIDE, ACCESSIBILITÉ & INFORMATIONS LÉGALES ==========
    GoRoute(
      path: '/accessibilite',
      name: 'accessibilite',
      builder: (context, state) => const AccessibilitePage(),
    ),
    GoRoute(
      path: '/guide-utilisation',
      name: 'guide-utilisation',
      builder: (context, state) => const GuideUtilisationPage(),
    ),
    GoRoute(
      path: '/politique-confidentialite',
      name: 'politique-confidentialite',
      builder: (context, state) => const PolitiqueConfidentialitePage(),
    ),
    // ⚖️ Conditions d'utilisation (droit congolais — Lubumbashi, RDC).
    GoRoute(
      path: '/conditions-utilisation',
      name: 'conditions-utilisation',
      builder: (context, state) => const ConditionsUtilisationPage(),
    ),

    // ==========================================================================
    //  🛒 MODULE 19 — MARKETPLACE PUBLIC « BIASHARA » (SANS COMPTE)
    // ==========================================================================
    //  Ces routes n'ont AUCUNE règle dans le middleware de permissions : un
    //  visiteur qui n'a jamais créé de compte doit pouvoir chercher un produit
    //  et découvrir les boutiques autour de lui. C'est une exigence explicite
    //  du module : la visibilité des petites boutiques passe par l'ouverture.
    GoRoute(
      path: '/biashara',
      name: 'biashara',
      builder: (context, state) => const MarketplaceWelcomePage(),
    ),
    GoRoute(
      path: '/biashara/recherche',
      name: 'biashara-recherche',
      builder: (context, state) => MarketplaceRecherchePage(
        requeteInitiale: state.uri.queryParameters['q'],
        categorieInitiale: state.uri.queryParameters['categorie'],
        triInitial: state.uri.queryParameters['tri'],
      ),
    ),
    GoRoute(
      path: '/biashara/carte',
      name: 'biashara-carte',
      builder: (context, state) => MarketplaceCartePage(
        requete: state.uri.queryParameters['q'],
      ),
    ),
    GoRoute(
      path: '/biashara/boutique/:slug',
      name: 'biashara-boutique',
      builder: (context, state) => MarketplaceBoutiquePage(
        slugOuId: state.pathParameters['slug'] ?? '',
      ),
    ),
    GoRoute(
      path: '/biashara/produit/:id',
      name: 'biashara-produit',
      builder: (context, state) => MarketplaceProduitPage(
        publicationId: state.pathParameters['id'] ?? '',
      ),
    ),

    // ============== MODULE 8 : CONFIRMATION DE VENTE ==============
    // Reçu affiché après l'encaissement (le panier est déjà vidé). Hors
    // coquille : l'écran occupe toute la place.
    GoRoute(
      path: '/confirmation-vente',
      name: 'vente-confirmation',
      builder: (context, state) {
        final Object? extra = state.extra;
        if (extra is VenteEnregistree) {
          return VenteConfirmationPage(vente: extra);
        }
        return const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aucune vente à afficher.\n'
                'Encaissez d\'abord un panier.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    ),

    // ================== ADMINISTRATION ==================
    GoRoute(
      path: '/admin',
      name: 'admin',
      builder: (context, state) => const AdminHomePage(),
      routes: [
        // 🏢 MODULE 1 — GESTION DES ENTREPRISES
        //
        // La liste est affichée dans un onglet de `AdminHomePage` (pas besoin
        // de route) ; seules les sous-pages en ont une : elles s'empilent
        // au-dessus de l'espace admin et bénéficient du retour natif.
        GoRoute(
          path: 'entreprises/new',
          name: 'entreprise-new',
          builder: (context, state) => const EntrepriseFormPage(),
        ),
        // 🆕 CORRECTIF 73 — création COMPLÈTE : l'entreprise ET le compte de
        // son propriétaire en une seule fois. Déclarée AVANT `:id`, sinon
        // « new-complet » serait pris pour un identifiant.
        GoRoute(
          path: 'entreprises/new-complet',
          name: 'entreprise-creation-complete',
          builder: (context, state) => const EntrepriseCreationPage(),
        ),
        GoRoute(
          path: 'entreprises/:id',
          name: 'entreprise-detail',
          builder: (context, state) => EntrepriseDetailPage(
            entreprise:
                state.extra is Entreprise ? state.extra as Entreprise : null,
            entrepriseId: state.pathParameters['id'],
          ),
          routes: [
            GoRoute(
              path: 'edit',
              name: 'entreprise-edit',
              builder: (context, state) => EntrepriseFormPage(
                entreprise: state.extra is Entreprise
                    ? state.extra as Entreprise
                    : null,
                entrepriseId: state.pathParameters['id'],
              ),
            ),
            // 🆕 CORRECTIF 73 — LA FICHE UNIQUE : abonnement, installation,
            // suivi et avance sur un seul écran.
            GoRoute(
              path: 'fiche',
              name: 'entreprise-fiche',
              builder: (context, state) => EntrepriseFichePage(
                entrepriseId: state.pathParameters['id']!,
                nom: state.extra is Entreprise
                    ? (state.extra as Entreprise).nom
                    : null,
              ),
            ),
          ],
        ),

        // 📚 MODULE 2 — ACTIVITÉS & GROUPES TARIFAIRES
        //
        // Le hub (onglet « Référentiels » de AdminHomePage) ouvre ces listes ;
        // les formulaires s'empilent au-dessus de l'espace admin et
        // bénéficient du retour natif.
        GoRoute(
          path: 'activites',
          name: 'activites',
          builder: (context, state) => const ActivitesPage(),
          routes: [
            GoRoute(
              path: 'new',
              name: 'activite-new',
              builder: (context, state) => const ActiviteFormPage(),
            ),
            GoRoute(
              path: ':id',
              name: 'activite-edit',
              builder: (context, state) => ActiviteFormPage(
                activite:
                    state.extra is Activite ? state.extra as Activite : null,
                activiteId: state.pathParameters['id'],
              ),
            ),
          ],
        ),
        GoRoute(
          path: 'groupes-tarifaires',
          name: 'groupes-tarifaires',
          builder: (context, state) => GroupesTarifairesPage(
            activiteIdInitial:
                state.extra is String ? state.extra as String : null,
          ),
          routes: [
            GoRoute(
              path: 'new',
              name: 'groupe-tarifaire-new',
              builder: (context, state) => GroupeTarifaireFormPage(
                activiteIdInitial:
                    state.extra is String ? state.extra as String : null,
              ),
            ),
            GoRoute(
              path: ':id',
              name: 'groupe-tarifaire-edit',
              builder: (context, state) => GroupeTarifaireFormPage(
                groupe: state.extra is GroupeTarifaire
                    ? state.extra as GroupeTarifaire
                    : null,
                groupeId: state.pathParameters['id'],
              ),
            ),
          ],
        ),

        // 🧩 MODULE 16 — TYPES D'ACTIVITÉS & MODULES (multi-activités).
        //
        // Le type de chaque entreprise (module 15) détermine ses modules ;
        // l'« Expert Administrateur » crée ici de nouveaux types (ex :
        // « Salon de coiffure ») et coche leurs modules — aucune mise à jour
        // de l'application n'est nécessaire.
        GoRoute(
          path: 'types-activites',
          name: 'types-activites',
          builder: (context, state) => const TypesActivitesPage(),
          routes: [
            GoRoute(
              path: 'new',
              name: 'type-activite-new',
              builder: (context, state) => const TypeActiviteFormPage(),
            ),
            GoRoute(
              path: ':type',
              name: 'type-activite-edit',
              builder: (context, state) => TypeActiviteFormPage(
                profil: state.extra is ProfilModules
                    ? state.extra as ProfilModules
                    : null,
                typeCode: state.pathParameters['type'],
              ),
            ),
          ],
        ),

        // 💳 MODULE 3 — MOTEUR D'ABONNEMENT
        //
        // Accessible depuis la fiche entreprise (action de la barre de titre).
        // `:id` est l'identifiant de l'entreprise.
        GoRoute(
          path: 'abonnements/:id',
          name: 'abonnement-detail',
          builder: (context, state) => AbonnementDetailPage(
            entreprise:
                state.extra is Entreprise ? state.extra as Entreprise : null,
            entrepriseId: state.pathParameters['id'],
          ),
          routes: [
            GoRoute(
              path: 'paiement',
              name: 'abonnement-paiement',
              builder: (context, state) => PaiementAbonnementPage(
                entreprise: state.extra is Entreprise
                    ? state.extra as Entreprise
                    : null,
                entrepriseId: state.pathParameters['id'],
              ),
            ),
          ],
        ),

        // 🔐 MODULE 4 — PERMISSIONS DES RÔLES (Super Admin uniquement)
        //
        // Également accessible depuis l'onglet « Système ». La permission
        // exigée est `parametres` + `modifier` ; l'écran vérifie en plus que
        // le rôle est SUPER_ADMIN, et la RPC `rpc_permissions_set` le vérifie
        // une troisième fois côté serveur.
        GoRoute(
          path: 'permissions',
          name: 'permissions-roles',
          builder: (context, state) => PermissionsRolePage(
            roleInitial: state.extra is RoleUtilisateur
                ? state.extra as RoleUtilisateur
                : null,
          ),
        ),
      ],
    ),

    // ================== APPLICATION PRINCIPALE ==================
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          ScaffoldWithNavBar(navigationShell: navigationShell),
      branches: [
        // 🏠 BRANCHE 1 : ACCUEIL, VENTES & SUIVI COMMERCIAL
        StatefulShellBranch(
          navigatorKey: shellNavigatorKey,
          routes: [
            GoRoute(
              path: '/main',
              name: 'home',
              builder: (context, state) => const HomePage(),
              routes: [
                // 🧾 MODULE 17 — page « compte verrouillé » (activation en
                // attente, abonnement échu…). Toujours accessible.
                GoRoute(
                  path: 'compte-verrouille',
                  name: 'compte-verrouille',
                  builder: (context, state) => const CompteVerrouillePage(),
                ),

                GoRoute(
                  path: 'new-sale',
                  name: 'new-sale',
                  builder: (context, state) => const NewSalePage(),
                ),

                // 🏬 MODULE 9 — GESTION DU STOCK (conversions multi-unités)
                //
                // `/main/stock` = écran principal (liste, alertes, filtres) ;
                // sous-routes : clôture d'inventaire, entrée de stock,
                // ajustement (raison obligatoire) et fiche stock d'un article.
                // Les routes statiques sont déclarées AVANT `:id` pour être
                // résolues en priorité.
                GoRoute(
                  path: 'stock',
                  name: 'stock',
                  builder: (context, state) => const StockGestionPage(),
                  routes: [
                    GoRoute(
                      path: 'inventaire',
                      name: 'stock-inventaire',
                      builder: (context, state) =>
                          const InventaireCloturePage(),
                    ),
                    GoRoute(
                      path: 'approvisionnement',
                      name: 'stock-approvisionnement',
                      builder: (context, state) => ApprovisionnementFormPage(
                        article: state.extra is Article
                            ? state.extra as Article
                            : null,
                      ),
                    ),
                    GoRoute(
                      path: 'ajustement',
                      name: 'stock-ajustement',
                      builder: (context, state) => AjustementFormPage(
                        article: state.extra is Article
                            ? state.extra as Article
                            : null,
                      ),
                    ),
                    GoRoute(
                      path: ':id',
                      name: 'stock-article',
                      builder: (context, state) => StockDetailPage(
                        articleId:
                            int.tryParse(state.pathParameters['id'] ?? '') ??
                                -1,
                        article: state.extra is Article
                            ? state.extra as Article
                            : null,
                      ),
                    ),
                  ],
                ),
                // 🧩 CORRECTIF 76 — UN SEUL formulaire de création.
                //
                // « Ajouter un produit » (ancien écran SQLite, hors ligne) et
                // « Nouvel article » étaient DEUX écrans différents pour la
                // même chose : deux jeux de champs, deux comportements (pas de
                // lot, pas de péremption, pas de variantes d'un côté). Le
                // patron ne pouvait pas savoir lequel ouvrait quoi.
                //
                // Désormais l'ancienne adresse REDIRIGE vers le formulaire
                // d'article : tous les boutons qui pointaient ici (« Stock »,
                // « Gestion du stock », raccourcis) ouvrent exactement le même
                // formulaire, avec les mêmes champs.
                GoRoute(
                  path: 'add-product',
                  name: 'add-product',
                  redirect: (context, state) => '/main/articles/new',
                ),
                GoRoute(
                  path: 'edit-product',
                  name: 'edit-product',
                  redirect: (context, state) => '/main/articles',
                ),

                // ⭐ ROUTES COMMERCIALES
                GoRoute(
                  path: 'commercial',
                  name: 'commercial',
                  builder: (context, state) => const CommercialHubPage(),
                ),

                // 💰 MODULE 10 — FINANCE DE L'ENTREPRISE
                //
                // Caisse (solde calculé + historique + clôture), tableau de
                // bord et rapports. Les écritures passent par les RPC du
                // Module 10 : la finance reste STRICTEMENT dans l'entreprise
                // (la plateforme n'y a aucun accès).
                GoRoute(
                  path: 'caisse',
                  name: 'caisse',
                  builder: (context, state) => const CaissePage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'cloture',
                      name: 'caisse-cloture',
                      builder: (context, state) => const ClotureCaissePage(),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'finance',
                  name: 'finance',
                  builder: (context, state) => const FinanceDashboardPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'rapports',
                      name: 'finance-rapports',
                      builder: (context, state) => const RapportsFinancePage(),
                    ),
                  ],
                ),
                // MODULE 10 — l'écran Dépenses (Supabase) remplace l'écran
                // SQLite ; même chemin et même nom de route qu'avant.
                GoRoute(
                  path: 'depenses',
                  name: 'depenses',
                  builder: (context, state) => const DepensesFinancePage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'new',
                      name: 'depense-new',
                      builder: (context, state) =>
                          const DepenseFinanceFormPage(),
                    ),
                  ],
                ),
                // MODULE 10 — dettes clients (Supabase), mêmes chemin/nom.
                GoRoute(
                  path: 'dettes',
                  name: 'dettes',
                  builder: (context, state) => const DettesClientsPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'new',
                      name: 'dette-new',
                      builder: (context, state) => const DetteFormPage(),
                    ),
                  ],
                ),
                // 📊 MODULE 11 — RAPPORTS & EXPORTS (boutique) : aperçu de
                // tous les rapports + exports PDF/Excel signés et tracés.
                GoRoute(
                  path: 'rapports',
                  name: 'rapports',
                  builder: (context, state) => const RapportsPage(),
                ),
                GoRoute(
                  path: 'clients',
                  name: 'clients',
                  builder: (context, state) => const ClientsPage(),
                ),
                GoRoute(
                  path: 'inventaires',
                  name: 'inventaires',
                  builder: (context, state) => const InventairesPage(),
                ),

                // 🧾 MODULE 14 — tableau de bord du dossier d'activation :
                // étape en cours, montants, dates, jours restants et
                // historique complet des décisions (transparence client).
                GoRoute(
                  path: 'mon-activation',
                  name: 'mon-activation',
                  builder: (context, state) => const MonActivationPage(),
                ),

                // 🏢 MODULE 15 — mes entreprises (pack multi-entreprises) :
                // liste, création et bascule d'entreprise active.
                GoRoute(
                  path: 'mes-entreprises',
                  name: 'mes-entreprises',
                  builder: (context, state) => const MesEntreprisesPage(),
                ),

                // 🏨 MODULE 16 C2 — HÔTEL : chambres & occupation, planning
                // des réservations (check-in / check-out), réception du jour
                // et facture de séjour.
                GoRoute(
                  path: 'hotel/chambres',
                  name: 'hotel-chambres',
                  builder: (context, state) => const ChambresPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'new',
                      name: 'hotel-chambre-new',
                      builder: (context, state) => const ChambreFormPage(),
                    ),
                    GoRoute(
                      path: ':id/edit',
                      name: 'hotel-chambre-edit',
                      builder: (context, state) => ChambreFormPage(
                        chambre: state.extra is Chambre
                            ? state.extra as Chambre
                            : null,
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'hotel/reservations',
                  name: 'hotel-reservations',
                  builder: (context, state) => const ReservationsPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'new',
                      name: 'hotel-reservation-new',
                      builder: (context, state) =>
                          const ReservationFormPage(),
                    ),
                    GoRoute(
                      path: ':id/facture',
                      name: 'hotel-facture',
                      builder: (context, state) => FactureSejourPage(
                        reservation: state.extra is Reservation
                            ? state.extra as Reservation
                            : null,
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'hotel/reception',
                  name: 'hotel-reception',
                  builder: (context, state) => const ReceptionPage(),
                ),

                // 🍽️ MODULE 16 C3 — RESTAURANT : plan de salle, commandes
                // (envoi cuisine, service, encaissement) et écran cuisine.
                GoRoute(
                  path: 'restaurant/tables',
                  name: 'restaurant-tables',
                  builder: (context, state) => const TablesSallePage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'new',
                      name: 'restaurant-table-new',
                      builder: (context, state) => const TableSalleFormPage(),
                    ),
                    GoRoute(
                      path: ':id/edit',
                      name: 'restaurant-table-edit',
                      builder: (context, state) => TableSalleFormPage(
                        table: state.extra is TableSalle
                            ? state.extra as TableSalle
                            : null,
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'restaurant/commandes',
                  name: 'restaurant-commandes',
                  builder: (context, state) => const CommandesPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: ':id',
                      name: 'restaurant-commande-detail',
                      builder: (context, state) => CommandeDetailPage(
                        commandeId: state.pathParameters['id'] ?? '',
                        commande: state.extra is Commande
                            ? state.extra as Commande
                            : null,
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'restaurant/cuisine',
                  name: 'restaurant-cuisine',
                  builder: (context, state) => const CuisinePage(),
                ),

                // 🎉 MODULE 16 C4 — SALLE DES FÊTES : salles (nom,
                // capacité, prix/jour), calendrier des événements, dossier
                // complet (prestations, cycle de vie, encaissements).
                GoRoute(
                  path: 'evenements',
                  name: 'evenements',
                  builder: (context, state) => const EvenementsPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'new',
                      name: 'evenements-new',
                      builder: (context, state) => const EvenementFormPage(),
                    ),
                    GoRoute(
                      path: 'salles',
                      name: 'evenements-salles',
                      builder: (context, state) => const SallesPage(),
                      routes: <RouteBase>[
                        GoRoute(
                          path: 'new',
                          name: 'evenements-salle-new',
                          builder: (context, state) => const SalleFormPage(),
                        ),
                        GoRoute(
                          path: ':id/edit',
                          name: 'evenements-salle-edit',
                          builder: (context, state) => SalleFormPage(
                            salle: state.extra is Salle
                                ? state.extra as Salle
                                : null,
                          ),
                        ),
                      ],
                    ),
                    GoRoute(
                      path: ':id',
                      name: 'evenements-detail',
                      builder: (context, state) => EvenementDetailPage(
                        evenementId: state.pathParameters['id'] ?? '',
                        evenement: state.extra is Evenement
                            ? state.extra as Evenement
                            : null,
                      ),
                    ),
                    GoRoute(
                      path: ':id/edit',
                      name: 'evenements-edit',
                      builder: (context, state) => EvenementFormPage(
                        evenement: state.extra is Evenement
                            ? state.extra as Evenement
                            : null,
                      ),
                    ),
                  ],
                ),

                // 🥖 MODULE 16 C5 — BOULANGERIE : matières premières
                // (farine, levure…), productions (quantités, pertes,
                // coût de revient) et entrée en stock du produit fini.
                GoRoute(
                  path: 'production',
                  name: 'production',
                  builder: (context, state) => const ProductionsPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'new',
                      name: 'production-new',
                      builder: (context, state) => const ProductionFormPage(),
                    ),
                    GoRoute(
                      path: 'matieres',
                      name: 'production-matieres',
                      builder: (context, state) =>
                          const MatieresPremieresPage(),
                      routes: <RouteBase>[
                        GoRoute(
                          path: 'new',
                          name: 'production-matiere-new',
                          builder: (context, state) => const MatiereFormPage(),
                        ),
                        GoRoute(
                          path: ':id/edit',
                          name: 'production-matiere-edit',
                          builder: (context, state) => MatiereFormPage(
                            matiere: state.extra is MatierePremiere
                                ? state.extra as MatierePremiere
                                : null,
                          ),
                        ),
                      ],
                    ),
                    GoRoute(
                      path: ':id',
                      name: 'production-detail',
                      builder: (context, state) => ProductionDetailPage(
                        productionId: state.pathParameters['id'] ?? '',
                        production: state.extra is Production
                            ? state.extra as Production
                            : null,
                      ),
                    ),
                  ],
                ),

                // � MODULE 19 — MARKETPLACE : la vitrine publique de la
                // boutique (position guidée, adresse lisible par un visiteur
                // étranger, horaires, contacts publics, aperçu avant
                // publication), les articles publiés, le tableau de bord
                // « Ma visibilité Biashara » et les campagnes publicitaires.
                GoRoute(
                  path: 'vitrine',
                  name: 'ma-vitrine',
                  builder: (context, state) => const MaVitrinePage(),
                ),
                GoRoute(
                  path: 'publications',
                  name: 'mes-publications',
                  builder: (context, state) => const MesPublicationsPage(),
                ),
                GoRoute(
                  path: 'visibilite',
                  name: 'ma-visibilite',
                  builder: (context, state) => const VisibiliteBiasharaPage(),
                ),
                GoRoute(
                  path: 'publicites',
                  name: 'publicites',
                  builder: (context, state) => const PublicitesBiasharaPage(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'new',
                      name: 'publicite-new',
                      builder: (context, state) =>
                          const PubliciteBiasharaFormPage(),
                    ),
                    GoRoute(
                      path: ':id',
                      name: 'publicite-edit',
                      builder: (context, state) => PubliciteBiasharaFormPage(
                        publicite: state.extra is PubliciteBiashara
                            ? state.extra as PubliciteBiashara
                            : null,
                      ),
                    ),
                  ],
                ),

                // �🗂️ MODULE 5 — ARTICLES & CATALOGUE (multi-conditionnements)
                //
                // Liste, création / modification, détail (QR codes +
                // historique des mouvements) et gestion des catégories.
                // Les emballages vendables (farde, carton…) vivent dans des
                // sous-routes du détail : ils ont besoin d'un article existant.
                GoRoute(
                  path: 'articles',
                  name: 'articles',
                  builder: (context, state) => const ArticlesPage(),
                  routes: [
                    GoRoute(
                      path: 'categories',
                      name: 'article-categories',
                      builder: (context, state) => const CategoriesPage(),
                    ),
                    GoRoute(
                      path: 'new',
                      name: 'article-new',
                      builder: (context, state) => const ArticleFormPage(),
                    ),
                    // 🧩 MODULE 16 C1 — pharmacie : produits expirés ou
                    // proches de la péremption (module lots_expiration).
                    GoRoute(
                      path: 'expirations',
                      name: 'articles-expirations',
                      builder: (context, state) => const ExpirationsPage(),
                    ),
                    GoRoute(
                      path: ':id',
                      name: 'article-detail',
                      builder: (context, state) => ArticleDetailPage(
                        articleId:
                            int.tryParse(state.pathParameters['id'] ?? '') ??
                                -1,
                        article: state.extra is Article
                            ? state.extra as Article
                            : null,
                      ),
                      routes: [
                        GoRoute(
                          path: 'edit',
                          name: 'article-edit',
                          builder: (context, state) => ArticleFormPage(
                            article: state.extra is Article
                                ? state.extra as Article
                                : null,
                            articleId: state.pathParameters['id'],
                          ),
                        ),
                        GoRoute(
                          path: 'conditionnements/new',
                          name: 'conditionnement-new',
                          builder: (context, state) => ConditionnementFormPage(
                            articleId: int.tryParse(
                                    state.pathParameters['id'] ?? '') ??
                                -1,
                          ),
                        ),
                        GoRoute(
                          path: 'conditionnements/:conditionnementId/edit',
                          name: 'conditionnement-edit',
                          builder: (context, state) => ConditionnementFormPage(
                            articleId: int.tryParse(
                                    state.pathParameters['id'] ?? '') ??
                                -1,
                            conditionnement: state.extra is Conditionnement
                                ? state.extra as Conditionnement
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // 🔳 MODULE 6 — GESTION & IMPRESSION DES QR CODES
                //
                // Liste de sélection (articles + conditionnements), génération
                // en masse, téléchargement PNG/SVG et planche d'étiquettes PDF.
                GoRoute(
                  path: 'qr-codes',
                  name: 'qr-codes',
                  builder: (context, state) => const QrCodesPage(),
                  routes: [
                    GoRoute(
                      path: 'apercu',
                      name: 'qr-apercu',
                      builder: (context, state) {
                        final Object? extra = state.extra;
                        if (extra is EtiquetteQr) {
                          return QrApercuPage(etiquette: extra);
                        }
                        return const Scaffold(
                          body: Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Aucune étiquette sélectionnée.\n'
                                'Ouvrez cet aperçu depuis la gestion des QR codes.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                // ========== MODULE 8 — PANIER & VALIDATION DE VENTE ==========
                //
                // `/main/panier` liste les lignes du panier partagé (rempli par
                // le scanner du Module 7) et mène à `/main/panier/encaissement`
                // (transaction serveur `rpc_vente_valider`). `/main/ventes` est
                // l'historique du vendeur (filtres jour / mode de paiement).
                GoRoute(
                  path: 'panier',
                  name: 'panier',
                  builder: (context, state) => const PanierPage(),
                  routes: [
                    GoRoute(
                      path: 'encaissement',
                      name: 'panier-encaissement',
                      builder: (context, state) => const EncaissementPage(),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'ventes',
                  name: 'mes-ventes',
                  builder: (context, state) => const MesVentesPage(),
                ),
              ],
            ),
          ],
        ),

        // 📊 BRANCHE 2 : RAPPORTS
        //
        // 📊 MODULE 11 — l'onglet « Rapports » ouvre le nouvel écran
        // (données Supabase + exports PDF/Excel). Le chemin `/reports` est
        // conservé : toutes les navigations existantes continuent d'aboutir.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/reports',
              name: 'reports',
              builder: (context, state) => const RapportsPage(),
            ),
          ],
        ),

        // 📦 BRANCHE 3 : GESTION DE STOCK
        //
        // 🏬 MODULE 9 — l'onglet ouvre le nouvel écran de gestion du stock
        // (Supabase) : le même écran que `/main/stock`.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/stock-management',
              name: 'stock-management',
              builder: (context, state) => const StockGestionPage(),
            ),
          ],
        ),

        // ⚙️ BRANCHE 4 : PARAMÈTRES & UTILISATEURS
        StatefulShellBranch(
          navigatorKey: settingsBranchKey,
          routes: [
            GoRoute(
              path: '/settings',
              name: 'settings',
              builder: (context, state) => const SettingsPage(),
              routes: [
                GoRoute(
                  path: 'profile-edit',
                  name: 'profile-edit',
                  builder: (context, state) => const ProfileEditPage(),
                ),
                GoRoute(
                  path: 'password-change',
                  name: 'password-change',
                  builder: (context, state) => const ChangePasswordPage(),
                ),
                GoRoute(
                  path: 'manage-categories',
                  name: 'manage-categories',
                  builder: (context, state) => const ManageCategoriesPage(),
                ),
                GoRoute(
                  path: 'about',
                  name: 'about',
                  builder: (context, state) => const AboutPage(),
                ),

                // 🪙 MODULE 18 — devise de travail de l'entreprise (CDF/USD)
                // et taux de conversion.
                GoRoute(
                  path: 'devise',
                  name: 'devise',
                  builder: (context, state) => const DevisePage(),
                ),

                // 👥 GESTION DES VENDEURS
                GoRoute(
                  path: 'manage-users',
                  name: 'manage-users',
                  builder: (context, state) => const ManageUsersPage(),
                  routes: [
                    GoRoute(
                      path: 'add-user',
                      name: 'add-user',
                      builder: (context, state) => const AddUserPage(),
                    ),
                  ],
                ),

                // 📊 STATS COLLABORATEURS
                GoRoute(
                  path: 'collaborateurs-stats',
                  name: 'collaborateurs-stats',
                  builder: (context, state) {
                    final ownerId = state.extra as String?;
                    if (ownerId == null) {
                      return const Scaffold(
                        body: Center(child: Text("Owner ID manquant")),
                      );
                    }
                    return CollaborateursStatsPage(ownerId: ownerId);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
