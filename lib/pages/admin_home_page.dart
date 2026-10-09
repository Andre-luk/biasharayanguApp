// lib/pages/admin_home_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

// 🔐 MODULE 4 — Permissions
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

// 🔐 MODULE 12 — Journal d'audit & sécurité (journalisation des sessions)
import 'package:biashara_yangu/services/audit_service.dart';

// Importation des pages enfants (assurez-vous que ces imports sont valides)
import 'package:biashara_yangu/pages/admin_users_page.dart';
import 'package:biashara_yangu/pages/admin_categories_page.dart';
import 'package:biashara_yangu/pages/admin_maintenance_page.dart';
import 'package:biashara_yangu/pages/abonnements_laperle_page.dart';
import 'package:biashara_yangu/pages/entreprise_list_page.dart';
import 'package:biashara_yangu/pages/permissions_role_page.dart';
import 'package:biashara_yangu/pages/referentiels_hub_page.dart';
// 📊 MODULE 11 — rapports de la plateforme (exports PDF/Excel tracés).
import 'package:biashara_yangu/pages/rapports_page.dart';
// 🧾 MODULE 14 — workflow d'activation à double validation.
import 'package:biashara_yangu/pages/activations_finance_page.dart';
import 'package:biashara_yangu/pages/comptes_verification_page.dart';
// 🛡️ MODULE 20 — administration plateforme : parc des boutiques et modération
// du catalogue public (manques relevés par l'audit final).
import 'package:biashara_yangu/pages/admin_boutiques_page.dart';
import 'package:biashara_yangu/pages/admin_moderation_page.dart';
import 'package:biashara_yangu/pages/agent_terrain_fiche_page.dart';


// ====================================================================
// ADMIN HOME PAGE (Conteneur avec BottomNavigationBar)
// ====================================================================

/// Onglet de l'espace d'administration.
///
/// `pages` liste les permissions qui rendent l'onglet visible : l'onglet
/// apparaît dès que le rôle possède l'une d'elles en lecture.
class _OngletAdmin {
  const _OngletAdmin({
    required this.label,
    required this.icone,
    required this.pages,
    required this.builder,
  });

  final String label;
  final IconData icone;
  final List<PageAccess> pages;
  final WidgetBuilder builder;

  bool estVisible(PermissionService permissions) => pages.any(
        (PageAccess page) => permissions.peutVoir(page),
      );
}

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  int _selectedIndex = 0;

  /// Tous les onglets possibles, dans l'ordre d'affichage. Le filtre par
  /// permissions est appliqué dans `_onglets`.
  static final List<_OngletAdmin> _tousLesOnglets = <_OngletAdmin>[
    _OngletAdmin(
      label: 'Tableau',
      icone: Icons.dashboard_customize,
      pages: const <PageAccess>[PageAccess.dashboard],
      // 🧑‍🌾 MODULE 21 ter — un agent terrain n'a rien à voir dans les revenus
      // globaux de la plateforme : son « Tableau » est SA fiche.
      builder: (_) => const _TableauAdmin(),
    ),
    _OngletAdmin(
      label: 'Utilisateurs',
      icone: Icons.people_alt,
      pages: const <PageAccess>[PageAccess.utilisateurs],
      builder: (_) => const AdminUsersWrapper(),
    ),
    _OngletAdmin(
      label: 'Entreprises',
      icone: Icons.business_rounded,
      pages: const <PageAccess>[PageAccess.entreprises],
      // 🏢 Module « Gestion des entreprises » : la page fournit son propre
      // Scaffold (FAB, rafraîchissement) mais pas sa barre de titre.
      builder: (_) => const EntrepriseListPage(showAppBar: false),
    ),
    _OngletAdmin(
      label: 'Abonnements',
      icone: Icons.card_membership_rounded,
      pages: const <PageAccess>[PageAccess.abonnements, PageAccess.paiements],
      builder: (_) => const AbonnementsLaperlePage(),
    ),
    // 🧾 MODULE 14 — première validation : le gestionnaire des comptes
    // vérifie les dossiers des nouvelles entreprises et les transmet à la
    // finance (il n'active jamais lui-même).
    _OngletAdmin(
      label: 'Vérifications',
      icone: Icons.fact_check_rounded,
      pages: const <PageAccess>[PageAccess.verificationComptes],
      builder: (_) => const ComptesVerificationPage(),
    ),
    // 🧾 MODULE 14 — deuxième validation : la finance confirme le paiement
    // puis l'activation du compte est automatique (total = 30 j ;
    // partiel = 7 jours d'essai + solde).
    _OngletAdmin(
      label: 'Activations',
      icone: Icons.rocket_launch_rounded,
      pages: const <PageAccess>[PageAccess.activationsFinance],
      builder: (_) => const ActivationsFinancePage(),
    ),
    _OngletAdmin(
      label: 'Boutiques',
      icone: Icons.store_mall_directory_rounded,
      // 🛡️ MODULE 20 — parc complet des boutiques de la plateforme :
      // activation/désactivation et retrait du catalogue public.
      pages: const <PageAccess>[PageAccess.boutiques],
      builder: (_) => const AdminBoutiquesPage(showAppBar: false),
    ),
    _OngletAdmin(
      label: 'Modération',
      icone: Icons.gavel_rounded,
      // 🛡️ MODULE 20 — modération du catalogue public : retrait motivé d'un
      // article (le motif reste visible du commerçant).
      pages: const <PageAccess>[PageAccess.moderation],
      builder: (_) => const AdminModerationPage(showAppBar: false),
    ),
    _OngletAdmin(
      label: 'Référentiels',
      icone: Icons.category_rounded,
      // 📚 Module « Activités & groupes tarifaires » (Module 2) : hub d'accès
      // aux référentiels, sans AppBar propre (fournie par AdminHomePage).
      pages: const <PageAccess>[
        PageAccess.activites,
        PageAccess.groupesTarifaires,
        PageAccess.villes,
      ],
      builder: (_) => const ReferentielsHubPage(),
    ),
    _OngletAdmin(
      label: 'Rapports',
      icone: Icons.insert_chart_rounded,
      // 📊 MODULE 11 — rapports plateforme : revenus globaux, abonnements,
      // impayés, revenus par ville / activité, nouveaux comptes.
      // (AppBar fournie par AdminHomePage → showAppBar: false.)
      pages: const <PageAccess>[PageAccess.rapports],
      builder: (_) => const RapportsPage(showAppBar: false),
    ),
    _OngletAdmin(
      label: 'Système',
      icone: Icons.settings_applications,
      pages: const <PageAccess>[PageAccess.parametres],
      builder: (_) => const AdminSettingsPage(),
    ),
  ];

  late final List<_OngletAdmin> _onglets = _tousLesOnglets
      .where((_OngletAdmin o) => o.estVisible(PermissionService.instance))
      .toList(growable: false);

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _logout() async {
    // 🔐 MODULE 12 — déconnexion tracée (best-effort, AVANT de fermer la session).
    await AuditService.instance.deconnexion();
    await SessionManager.clearSession();
    PermissionService.instance.reinitialiser();
    if (mounted) GoRouter.of(context).go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_onglets.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Administration',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.logout, color: colorScheme.error),
              onPressed: _logout,
              tooltip: 'Déconnexion',
            ),
          ],
        ),
        body: const AccesRefuse(
          message: 'Votre rôle ne donne accès à aucun écran de la plateforme.',
        ),
      );
    }

    final int index = _selectedIndex.clamp(0, _onglets.length - 1);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_onglets[index].label),
        actions: [
          // 🔐 MODULE 4 — nom du rôle connecté, visible en permanence :
          // l'administrateur sait immédiatement avec quels droits il agit.
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                PermissionService.instance.roleCourant.libelle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: colorScheme.error),
            onPressed: _logout,
            tooltip: 'Déconnexion du panneau Administrateur',
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Le IndexedStack gère la transition entre les pages sans les reconstruire
      body: IndexedStack(
        index: index,
        children: _onglets
            .map((_OngletAdmin onglet) => onglet.builder(context))
            .toList(growable: false),
      ),

      // — Barre de navigation Material 3 (identique à l'espace entreprise). —
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: _onItemTapped,
          destinations: _onglets
              .map((_OngletAdmin onglet) => NavigationDestination(
                    icon: Icon(onglet.icone),
                    label: onglet.label,
                  ))
              .toList(growable: false),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------

// ====================================================================
// ADMIN DASHBOARD PAGE (Tableau de bord global avec statistiques)
// ====================================================================

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool _loading = true;
  double totalSystemRevenue = 0.0;
  int totalUsers = 0;
  int totalProducts = 0;

  @override
  void initState() {
    super.initState();
    _loadAdminStats();
  }

  Future<void> _loadAdminStats() async {
    setState(() => _loading = true);
    final db = DBHelper.instance;

    try {
      final revenue = await db.getTotalVentesAmount();
      final users = await db.getUtilisateurCount();
      final products = await db.getProduitsCount();

      if (mounted) {
        setState(() {
          totalSystemRevenue = revenue;
          totalUsers = users;
          totalProducts = products;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de chargement des stats: ${e.toString()}')));
        setState(() => _loading = false);
      }
    }
  }

  // 🚀 NOUVEAU _buildStatCard basé sur ListTile pour éviter l'overflow
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    // Utilisation d'un Card pleine largeur pour un design plus simple et robuste
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 30, color: color),
        ),
        title: Text(
          value,
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
            title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey
            )
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final basePadding = 16.0;

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
      onRefresh: _loadAdminStats,
      color: Theme.of(context).colorScheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(basePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aperçu des Performances', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 16),

            // 🚀 CORRECTION : Remplacement du GridView par une Column de StatCards
            Column(
              children: [
                _buildStatCard(
                    'CA Global (Total)',
                    '${totalSystemRevenue.toStringAsFixed(0)} CDF',
                    Icons.monetization_on,
                    Colors.green.shade700
                ),
                _buildStatCard(
                    'Utilisateurs Actifs',
                    '$totalUsers',
                    Icons.people_alt_rounded,
                    Colors.blue.shade700
                ),
                _buildStatCard(
                    'Produits Catalogués',
                    '$totalProducts',
                    Icons.inventory_2_rounded,
                    Colors.deepOrange.shade700
                ),
              ],
            ),
            // Fin de la section Statistiques

            const SizedBox(height: 32),
            const Text('Visualisation des Tendances', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 16),

            // ZONE GRAPHIQUE (Card stylisée)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              height: 250,
              width: double.infinity,
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    "Espace pour les graphiques de tendances (ventes, utilisateurs...).",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------

// ====================================================================
// WRAPPER POUR USERS PAGE
// ====================================================================

class AdminUsersWrapper extends StatelessWidget {
  const AdminUsersWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // La page enfant doit gérer sa propre mise en page pour ne pas avoir d'AppBar double
    return const AdminUsersPage();
  }
}

// --------------------------------------------------------------------

// ====================================================================
// ADMIN SETTINGS PAGE (Paramètres système)
// ====================================================================

class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  Future<void> _logout(BuildContext context) async {
    // 🔐 MODULE 12 — déconnexion tracée (best-effort, AVANT de fermer la session).
    await AuditService.instance.deconnexion();
    await SessionManager.clearSession();
    PermissionService.instance.reinitialiser();
    if (context.mounted) GoRouter.of(context).go('/login');
  }

  void _openCategories(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminCategoriesPage()));
  }

  void _openMaintenance(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminMaintenancePage()));
  }

  /// 🔐 MODULE 4 — écran « Modifier les permissions d'un rôle ».
  ///
  /// Réservé au SUPER_ADMIN : le middleware de navigation exige
  /// `parametres / modifier`, et l'écran lui-même vérifie le rôle.
  void _openPermissions(BuildContext context, {RoleUtilisateur? role}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PermissionsRolePage(roleInitial: role),
    ));
  }

  // Helper pour l'en-tête de section
  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
              title,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary
              )
          ),
        ],
      ),
    );
  }

  // Helper pour les tuiles de paramètres
  Widget _buildSettingsTile({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(icon, color: color, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final basePadding = 16.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(basePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🛠️ Section Outils
          _buildSectionHeader(context, 'Configuration Globale', Icons.build_circle),

          _buildSettingsTile(
            context: context,
            icon: Icons.category_rounded,
            color: Colors.orange.shade700,
            title: 'Gérer les Catégories Globales',
            subtitle: 'Ajouter ou modifier les listes de catégories utilisées par toutes les boutiques.',
            onTap: () => _openCategories(context),
          ),

          _buildSettingsTile(
            context: context,
            icon: Icons.person_add_alt_1_rounded,
            color: colorScheme.secondary,
            title: 'Inviter un nouvel utilisateur/Admin',
            subtitle: 'Créer rapidement un nouveau compte vendeur ou administrateur.',
            onTap: () => GoRouter.of(context).push('/setup?adminCreating=true'),
          ),

          // 🤖 MODULE 13 — configuration de l'assistant IA (Super Admin).
          PermissionGate(
            page: PageAccess.parametres,
            action: ActionAccess.modifier,
            fallback: const SizedBox.shrink(),
            child: _buildSettingsTile(
              context: context,
              icon: Icons.smart_toy_rounded,
              color: Colors.teal.shade600,
              title: 'Configuration IA',
              subtitle:
                  'Tarifs (CDF/quota), pack de 10, quotas offerts et activation de l\'assistant.',
              onTap: () => GoRouter.of(context).push('/agent-ia-config'),
            ),
          ),

          // 🪙 MODULE 13 bis — gestion RÉELLE des tokens : coût DeepSeek,
          // bénéfice, solde du compte, distribution et usage par entreprise.
          PermissionGate(
            page: PageAccess.parametres,
            action: ActionAccess.modifier,
            fallback: const SizedBox.shrink(),
            child: _buildSettingsTile(
              context: context,
              icon: Icons.data_usage_rounded,
              color: Colors.deepPurple.shade600,
              title: 'Tokens IA — coûts & bénéfice',
              subtitle:
                  'Saisir la recharge DeepSeek, suivre le coût réel, la marge, '
                  'les questions restantes et la distribution par entreprise.',
              onTap: () => GoRouter.of(context).push('/tokens-ia'),
            ),
          ),

          // 🧩 CORRECTIF 65 — NIVEAUX D'ABONNEMENT : ce que chaque niveau
          // ouvre comme fonctionnalités (l'activité dit ce qui a du sens, le
          // niveau dit ce qui est payé).
          PermissionGate(
            page: PageAccess.groupesTarifaires,
            action: ActionAccess.modifier,
            fallback: const SizedBox.shrink(),
            child: _buildSettingsTile(
              context: context,
              icon: Icons.workspace_premium_rounded,
              color: Colors.amber.shade800,
              title: 'Niveaux d\'abonnement',
              subtitle:
                  'Définir ce que chaque niveau ouvre : fonctionnalités, prix '
                  'conseillé, ordre d\'affichage. Tant qu\'aucun niveau n\'est '
                  'affecté, tout reste visible.',
              onTap: () => GoRouter.of(context).push('/niveaux-abonnement'),
            ),
          ),

          // 🪙 MODULE 18 — taux de change par défaut de la plateforme et
          // configuration d'une entreprise (Super Admin).
          PermissionGate(
            page: PageAccess.parametres,
            action: ActionAccess.modifier,
            fallback: const SizedBox.shrink(),
            child: _buildSettingsTile(
              context: context,
              icon: Icons.currency_exchange_rounded,
              color: Colors.green.shade700,
              title: 'Devises & taux',
              subtitle:
                  'Taux de change par défaut (1 USD = X CDF) et devise d\'une entreprise.',
              onTap: () => GoRouter.of(context).push('/admin/devises'),
            ),
          ),

          // 🧾 CORRECTIF 67 — FACTURES D'ABONNEMENT : chaque encaissement
          // produit automatiquement une facture figée (installation, mensuel,
          // avance, reste à payer) qui dit QUI l'a générée et sur quel numéro
          // elle a été envoyée au client.
          PermissionGate(
            page: PageAccess.facturesAbonnement,
            action: ActionAccess.voir,
            fallback: const SizedBox.shrink(),
            child: _buildSettingsTile(
              context: context,
              icon: Icons.description_rounded,
              color: Colors.indigo.shade600,
              title: 'Factures d\'abonnement',
              subtitle:
                  'Consulter, envoyer sur WhatsApp, imprimer ou annuler les '
                  'factures des boutiques. Chaque encaissement en crée une '
                  'automatiquement.',
              onTap: () => GoRouter.of(context).push('/factures-abonnement'),
            ),
          ),

          const SizedBox(height: 24),

          // 🛡️ Section Maintenance
          _buildSectionHeader(context, 'Maintenance & Sécurité', Icons.security_rounded),

          _buildSettingsTile(
            context: context,
            icon: Icons.cloud_download_rounded,
            color: Colors.blue.shade700,
            title: 'Sauvegarde / Restauration (Cloud)',
            subtitle: 'Gérer la sauvegarde et la restauration de la base de données.',
            onTap: () => _openMaintenance(context),
          ),

          _buildSettingsTile(
            context: context,
            icon: Icons.history_edu_rounded,
            color: Colors.green.shade700,
            title: 'Journal d\'audit',
            subtitle:
                'Actions tracées (CRITIQUE → INFO), filtres, détail JSON et export PDF signé.',
            onTap: () => GoRouter.of(context).push('/audit'),
          ),

          // 🏢 MODE PLATEFORME — production des étiquettes QR des boutiques.
          PermissionGate(
            page: PageAccess.qrCodes,
            action: ActionAccess.voir,
            fallback: const SizedBox.shrink(),
            child: _buildSettingsTile(
              context: context,
              icon: Icons.qr_code_2_rounded,
              color: Colors.brown.shade600,
              title: 'QR codes produits',
              subtitle:
                  'Produire et imprimer les étiquettes QR des articles d\'une boutique.',
              onTap: () => GoRouter.of(context).push('/admin/qr-codes'),
            ),
          ),

          // � MODULE 19 — modération des campagnes publicitaires : seules les
          // campagnes ACTIVÉES ici sont diffusées dans le catalogue public.
          PermissionGate(
            page: PageAccess.publicites,
            action: ActionAccess.voir,
            fallback: const SizedBox.shrink(),
            child: _buildSettingsTile(
              context: context,
              icon: Icons.campaign_rounded,
              color: Colors.deepOrange.shade400,
              title: 'Publicités Biashara',
              subtitle:
                  'Valider, activer ou refuser les campagnes des boutiques (toujours marquées « PUBLICITÉ »).',
              onTap: () => GoRouter.of(context).push('/admin/publicites'),
            ),
          ),

          // �🔐 MODULE 12 — écran Sécurité, réservé au personnel plateforme.
          PermissionGate(
            page: PageAccess.securite,
            action: ActionAccess.voir,
            fallback: const SizedBox.shrink(),
            child: _buildSettingsTile(
              context: context,
              icon: Icons.security_rounded,
              color: Colors.indigo.shade400,
              title: 'Sécurité',
              subtitle:
                  'Connexions, tentatives échouées, IP suspectes, réinitialisation des permissions.',
              onTap: () => GoRouter.of(context).push('/securite'),
            ),
          ),

          // 🔐 MODULE 4 — Permissions des rôles (Super Admin uniquement).
          PermissionGate(
            page: PageAccess.parametres,
            action: ActionAccess.modifier,
            fallback: const SizedBox.shrink(),
            child: _buildSettingsTile(
              context: context,
              icon: Icons.admin_panel_settings_rounded,
              color: Colors.deepPurple.shade400,
              title: 'Permissions des rôles',
              subtitle:
                  'Autoriser ou interdire chaque page et chaque action pour les 8 rôles.',
              onTap: () => _openPermissions(context),
            ),
          ),

          const SizedBox(height: 32),

          // 🚪 Action de déconnexion
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.exit_to_app, color: Colors.red),
              label: const Text('Déconnexion Administrateur', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: BorderSide(color: Colors.red.shade200),
              ),
              onPressed: () => _logout(context),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// 🧑‍🌾 MODULE 21 ter — l'onglet « Tableau » de l'administration.
///
/// Un AGENT TERRAIN voit SA fiche (ses clients, ses boutiques, ses QR codes,
/// ses revenus) : les revenus globaux de la plateforme ne le concernent pas.
/// Les autres rôles gardent le tableau de bord plateforme.
class _TableauAdmin extends StatelessWidget {
  const _TableauAdmin();

  @override
  Widget build(BuildContext context) {
    if (PermissionService.instance.estAgentTerrain) {
      return const AgentTerrainFichePage();
    }
    return const AdminDashboardPage();
  }
}