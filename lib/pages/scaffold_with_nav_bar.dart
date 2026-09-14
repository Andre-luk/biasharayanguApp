// lib/pages/scaffold_with_nav_bar.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

// Ce widget est le 'Shell' qui enveloppe les pages principales (/main, /reports, /catalog, /settings)
class ScaffoldWithNavBar extends StatefulWidget {
  // Le 'shell' est fourni par GoRouter et permet de basculer entre les branches.
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({
    super.key,
    required this.navigationShell,
  });

  @override
  State<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends State<ScaffoldWithNavBar> {
  bool _isAdmin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  // Logique transférée de l'ancienne MainPage
  Future<void> _checkUserRole() async {
    // 1. Lire l'ID de la session (String? - UUID)
    final userIdString = await SessionManager.getUserId();

    if (userIdString == null) {
      if (mounted) context.go('/login');
      return;
    }

    // ❌ CORRECTION: Suppression de la conversion int.tryParse et de la variable userIdInt
    // L'ID est passé directement comme String? au DBHelper.

    // 🔑 CORRECTION (Ancienne Ligne 41) : Utiliser l'ID String pour la base de données
    final user = await DBHelper.instance.getUtilisateurById(userIdString);

    if (mounted) {
      // 🔑 Si l'utilisateur est admin, on le redirige vers l'interface admin.
      if (user?.role == 'admin') {
        context.go('/admin');
        return;
      }

      setState(() {
        _isAdmin = false; // Maintenant, seul le rôle de vendeur passe ici
        _loading = false;
      });
    }
  }

  // Méthode pour basculer entre les onglets
  void _onTap(int index) {
    // 🔑 Utilise la méthode goBranch du shell pour naviguer
    widget.navigationShell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    // Si l'utilisateur est en cours de vérification, afficher le chargement
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Si l'utilisateur a été redirigé (par exemple vers /admin), ce code ne sera pas atteint.
    final T = AppLocalizations.of(context)!;

    return Scaffold(
      // Affiche la page actuelle de la branche sélectionnée
      body: widget.navigationShell,

      // Barre de navigation
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: widget.navigationShell.currentIndex,
        onTap: _onTap,
        items: [
          // L'ordre DOIT correspond à l'ordre des branches dans app_router.dart
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: T.navHome),
          BottomNavigationBarItem(icon: const Icon(Icons.bar_chart), label: T.navReports),
          // 🔑 MODIFIÉ : Utilise Icons.inventory_2 et la clé T.navStock pour le libellé
          BottomNavigationBarItem(icon: const Icon(Icons.inventory_2), label: T.navStock),
          BottomNavigationBarItem(icon: const Icon(Icons.settings), label: T.navSettings),
        ],
      ),
    );
  }
}