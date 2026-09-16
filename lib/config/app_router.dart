import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ================== MODÈLES ==================
import 'package:biashara_yangu/models/activite.dart';
import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/models/produit.dart';

// ================== PAGES ==================
import 'package:biashara_yangu/pages/login_page.dart';
import 'package:biashara_yangu/pages/setup_page.dart';
import 'package:biashara_yangu/pages/home_page.dart';
import 'package:biashara_yangu/pages/reports_page.dart';
import 'package:biashara_yangu/pages/stock_management_page.dart';
import 'package:biashara_yangu/pages/settings_page.dart'; // Contient SettingsPage et AboutPage
import 'package:biashara_yangu/pages/add_product_page.dart';
import 'package:biashara_yangu/pages/stock_page.dart';
import 'package:biashara_yangu/pages/new_sale_page.dart';
import 'package:biashara_yangu/pages/admin_home_page.dart';
import 'package:biashara_yangu/pages/scaffold_with_nav_bar.dart';
import 'package:biashara_yangu/pages/profile_edit_page.dart';
import 'package:biashara_yangu/pages/change_password_page.dart';
import 'package:biashara_yangu/pages/manage_categories_page.dart';
import 'package:biashara_yangu/pages/subscription_expired_page.dart';

// 👇 NOUVELLES PAGES DE SUIVI
import 'package:biashara_yangu/pages/depenses_page.dart';
import 'package:biashara_yangu/pages/dettes_page.dart';
import 'package:biashara_yangu/pages/inventaires_page.dart';
import 'package:biashara_yangu/pages/commercial_hub_page.dart';
import 'package:biashara_yangu/pages/clients_page.dart';

// ================== UTILISATEURS ==================
import 'package:biashara_yangu/pages/manage_users_page.dart';
import 'package:biashara_yangu/pages/add_user_page.dart';
import 'package:biashara_yangu/pages/collaborateurs_stats_page.dart';

// ================== MODULE 1 : ENTREPRISES ==================
import 'package:biashara_yangu/pages/entreprise_detail_page.dart';
import 'package:biashara_yangu/pages/entreprise_form_page.dart';

// ============ MODULE 2 : ACTIVITÉS & GROUPES TARIFAIRES ============
import 'package:biashara_yangu/pages/activite_form_page.dart';
import 'package:biashara_yangu/pages/activites_page.dart';
import 'package:biashara_yangu/pages/groupe_tarifaire_form_page.dart';
import 'package:biashara_yangu/pages/groupes_tarifaires_page.dart';

// ================== NAV KEYS ==================
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> shellNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> settingsBranchKey = GlobalKey<NavigatorState>();

// ================== ROUTER ==================
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/login',

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
        GoRoute(
          path: 'entreprises/:id',
          name: 'entreprise-detail',
          builder: (context, state) => EntrepriseDetailPage(
            entreprise: state.extra is Entreprise ? state.extra as Entreprise : null,
            entrepriseId: state.pathParameters['id'],
          ),
          routes: [
            GoRoute(
              path: 'edit',
              name: 'entreprise-edit',
              builder: (context, state) => EntrepriseFormPage(
                entreprise: state.extra is Entreprise ? state.extra as Entreprise : null,
                entrepriseId: state.pathParameters['id'],
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
                activite: state.extra is Activite ? state.extra as Activite : null,
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
                GoRoute(
                  path: 'new-sale',
                  name: 'new-sale',
                  builder: (context, state) => const NewSalePage(),
                ),
                GoRoute(
                  path: 'stock',
                  name: 'stock',
                  builder: (context, state) => const StockPage(),
                ),
                GoRoute(
                  path: 'add-product',
                  name: 'add-product',
                  builder: (context, state) => const AddProductPage(),
                ),
                GoRoute(
                  path: 'edit-product',
                  name: 'edit-product',
                  builder: (context, state) => AddProductPage(
                    produitToEdit: state.extra as Produit?,
                  ),
                ),

                // ⭐ ROUTES COMMERCIALES
                GoRoute(
                  path: 'commercial',
                  name: 'commercial',
                  builder: (context, state) => const CommercialHubPage(),
                ),
                GoRoute(
                  path: 'depenses',
                  name: 'depenses',
                  builder: (context, state) => const DepensesPage(),
                ),
                GoRoute(
                  path: 'dettes',
                  name: 'dettes',
                  builder: (context, state) => const DettesPage(),
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
              ],
            ),
          ],
        ),

        // 📊 BRANCHE 2 : RAPPORTS
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/reports',
              name: 'reports',
              builder: (context, state) => const ReportsPage(),
            ),
          ],
        ),

        // 📦 BRANCHE 3 : GESTION DE STOCK
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/stock-management',
              name: 'stock-management',
              builder: (context, state) => const StockManagementPage(),
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