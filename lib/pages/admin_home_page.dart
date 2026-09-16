// lib/pages/admin_home_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

// Importation des pages enfants (assurez-vous que ces imports sont valides)
import 'package:biashara_yangu/pages/admin_users_page.dart';
import 'package:biashara_yangu/pages/admin_categories_page.dart';
import 'package:biashara_yangu/pages/admin_maintenance_page.dart';
import 'package:biashara_yangu/pages/entreprise_list_page.dart';
import 'package:biashara_yangu/pages/referentiels_hub_page.dart';


// ====================================================================
// ADMIN HOME PAGE (Conteneur avec BottomNavigationBar)
// ====================================================================

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  int _selectedIndex = 0;

  // Pages spécifiques à l'administrateur
  final List<Widget> _adminPages = const [
    AdminDashboardPage(),
    AdminUsersWrapper(),
    // 🏢 Module « Gestion des entreprises » : la page fournit son propre
    // Scaffold (FAB, rafraîchissement) mais pas sa barre de titre.
    EntrepriseListPage(showAppBar: false),
    // 📚 Module « Activités & groupes tarifaires » (Module 2) : hub d'accès
    // aux référentiels, sans AppBar propre (fournie par AdminHomePage).
    ReferentielsHubPage(),
    AdminSettingsPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _logout() async {
    await SessionManager.clearSession();
    if (mounted) GoRouter.of(context).go('/login');
  }

  String _getAppBarTitle(int index) {
    switch (index) {
      case 0:
        return 'Tableau de Bord Global';
      case 1:
        return 'Gestion des Utilisateurs';
      case 2:
        return 'Gestion des Entreprises';
      case 3:
        return 'Activités & Groupes tarifaires';
      case 4:
        return 'Paramètres & Maintenance';
      default:
        return 'Administration Système';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          _getAppBarTitle(_selectedIndex),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: colorScheme.error),
            onPressed: _logout,
            tooltip: 'Déconnexion du panneau Administrateur',
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Le IndexedStack gère la transition entre les pages sans les reconstruire
      body: IndexedStack(index: _selectedIndex, children: _adminPages),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: Colors.grey[600],
        backgroundColor: colorScheme.surface,
        elevation: 10,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_customize), label: 'Tableau'),
          BottomNavigationBarItem(icon: Icon(Icons.people_alt), label: 'Utilisateurs'),
          BottomNavigationBarItem(icon: Icon(Icons.business_rounded), label: 'Entreprises'),
          BottomNavigationBarItem(icon: Icon(Icons.category_rounded), label: 'Référentiels'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_applications), label: 'Système'),
        ],
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
            color: color.withOpacity(0.15),
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
                    color: Colors.grey.withOpacity(0.1),
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
    await SessionManager.clearSession();
    GoRouter.of(context).go('/login');
  }

  void _openCategories(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminCategoriesPage()));
  }

  void _openMaintenance(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminMaintenancePage()));
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
            icon: Icons.history_toggle_off_rounded,
            color: Colors.green.shade700,
            title: 'Journal des Activités (Logs)',
            subtitle: 'Consulter l\'historique des actions importantes du système.',
            onTap: () => _openMaintenance(context),
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