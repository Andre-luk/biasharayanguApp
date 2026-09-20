// lib/pages/scaffold_with_nav_bar.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/widgets/banniere_abonnement.dart';

/// Branche de navigation principale, avec les pages qui la rendent légitime.
///
/// 🔐 MODULE 4 — une branche n'est proposée que si le rôle possède AU MOINS
/// une des pages qu'elle contient (en lecture). L'ordre des branches dans
/// `app_router.dart` reste la référence : cet index ne sert qu'à l'affichage.
///
/// 🧩 MODULE 16 — une branche peut en plus dépendre de l'ACTIVITÉ
/// ([activite]) : un hôtel n'a pas d'onglet « Stock ».
class _BrancheNav {
  const _BrancheNav({required this.index, required this.pages, this.activite});

  final int index;
  final List<PageAccess> pages;

  /// Condition d'activité (module 16) : la branche n'est proposée que si elle
  /// renvoie `true`. `null` = aucune restriction d'activité.
  final bool Function(Set<String> modules, bool profilCharge)? activite;
}

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
  static const List<_BrancheNav> _toutesLesBranches = <_BrancheNav>[
    _BrancheNav(
      index: 0,
      pages: <PageAccess>[
        PageAccess.dashboard,
        PageAccess.caisse,
        PageAccess.ventes,
        PageAccess.scanner,
        PageAccess.panier,
      ],
    ),
    _BrancheNav(
      index: 1,
      pages: <PageAccess>[PageAccess.rapports],
      // 🧩 MODULE 16 — l'onglet « Rapports » suit l'activité.
      activite: ReglesActivite.module(ModuleCode.rapports),
    ),
    _BrancheNav(
      index: 2,
      pages: <PageAccess>[PageAccess.stock, PageAccess.articles],
      // 🧩 MODULE 16 — pas de stock ni de catalogue (hôtel) → pas d'onglet.
      activite: ReglesActivite.stock,
    ),
    _BrancheNav(index: 3, pages: <PageAccess>[PageAccess.parametres]),
  ];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    // 🧩 MODULE 16 — le profil de modules de l'activité arrive en arrière-plan
    // (réseau) : dès qu'il est chargé, la barre se reconstruit et les onglets
    // hors activité disparaissent.
    ModulesService.instance.modules.addListener(_onModulesChange);
  }

  @override
  void dispose() {
    ModulesService.instance.modules.removeListener(_onModulesChange);
    super.dispose();
  }

  void _onModulesChange() {
    if (mounted) setState(() {});
  }

  /// 🔐 MODULE 4 — contrôle du rôle à l'entrée de l'espace entreprise.
  ///
  /// Les quatre rôles de la plateforme La Perle n'ont rien à faire ici : ils
  /// sont renvoyés vers l'administration, même si leur session locale est
  /// obsolète (le rôle est relu depuis la base).
  Future<void> _checkUserRole() async {
    final userIdString = await SessionManager.getUserId();

    if (userIdString == null) {
      if (mounted) context.go('/login');
      return;
    }

    final user = await DBHelper.instance.getUtilisateurById(userIdString);
    final RoleUtilisateur role =
        PermissionService.roleDepuisUtilisateur(user);

    PermissionService.instance.definirRoleCourant(role);

    if (mounted) {
      if (role.estPlateforme) {
        context.go('/admin');
        return;
      }

      setState(() {
        _loading = false;
      });
    }
  }

  /// Branches proposées au rôle connecté (au moins la branche d'accueil).
  List<_BrancheNav> get _branchesVisibles {
    final PermissionService permissions = PermissionService.instance;
    final Set<String> modules = ModulesService.instance.modules.value;
    final bool profilCharge = ModulesService.instance.charge;

    final List<_BrancheNav> visibles = _toutesLesBranches
        .where((_BrancheNav branche) =>
            branche.pages.any((PageAccess page) => permissions.peutVoir(page)) &&
            (branche.activite == null ||
                branche.activite!(modules, profilCharge)))
        .toList(growable: false);

    return visibles.isEmpty
        ? <_BrancheNav>[_toutesLesBranches.first]
        : visibles;
  }

  // Méthode pour basculer entre les onglets
  void _onTap(List<_BrancheNav> visibles, int indexAffiche) {
    final _BrancheNav branche = visibles[indexAffiche];
    widget.navigationShell.goBranch(branche.index);
  }

  @override
  Widget build(BuildContext context) {
    // Si l'utilisateur est en cours de vérification, afficher le chargement
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: ModernLoader(
            taille: 46,
            legende: 'Chargement de votre espace…',
          ),
        ),
      );
    }

    // Si l'utilisateur a été redirigé (par exemple vers /admin), ce code ne sera pas atteint.
    final T = AppLocalizations.of(context)!;
    final List<_BrancheNav> visibles = _branchesVisibles;

    // ⚠️ L'index affiché est la POSITION dans la liste filtrée, pas l'index de
    // la branche : les deux se confondent uniquement quand rien n'est masqué.
    final int positionCourante =
        visibles.indexWhere((_BrancheNav b) => b.index == widget.navigationShell.currentIndex);

    // Icônes sélectionné / non sélectionné : la barre est plus vivante.
    final List<NavigationDestination> destinations = visibles
        .map((_BrancheNav branche) { switch (branche.index) {
            case 0:
              return NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_rounded),
                label: T.navHome,
              );
            case 1:
              return NavigationDestination(
                icon: const Icon(Icons.insert_chart_outlined_rounded),
                selectedIcon: const Icon(Icons.insert_chart_rounded),
                label: T.navReports,
              );
            case 2:
              return NavigationDestination(
                icon: const Icon(Icons.inventory_2_outlined),
                selectedIcon: const Icon(Icons.inventory_2_rounded),
                label: T.navStock,
              );
            default:
              return NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings_rounded),
                label: T.navSettings,
              );
          }
        })
        .toList(growable: false);

    return Scaffold(
      // Affiche la page actuelle de la branche sélectionnée
      // 💳 MODULE 3 — La bannière « lecture seule » reste visible sur tous les
      // onglets lorsque l'abonnement de l'entreprise est échu.
      body: Column(
        children: [
          const BanniereAbonnement(),
          Expanded(child: widget.navigationShell),
        ],
      ),

      // — Barre de navigation Material 3 : indicateur arrondi, ombre douce. —
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
          selectedIndex: positionCourante < 0 ? 0 : positionCourante,
          onDestinationSelected: (int i) => _onTap(visibles, i),
          destinations: destinations,
        ),
      ),
    );
  }
}