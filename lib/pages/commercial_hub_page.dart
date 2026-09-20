// lib/pages/commercial_hub_page.dart
//
// 🧾 MENU « GESTION COMMERCIALE » (dépenses, dettes, clients, inventaires,
// rapports).
//
// 🧩 MODULE 16 — chaque carte suit l'ACTIVITÉ de l'entreprise : une carte dont
// le module n'est pas dans le profil disparaît (un hôtel n'a pas
// « Inventaires quotidiens »). Le contrôle des droits (module 4) reste
// appliqué en plus. Masquage uniquement — aucun écran n'est bloqué.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';

class CommercialHubPage extends StatelessWidget {
  const CommercialHubPage({super.key});

  void _goTo(BuildContext context, String routeName) {
    context.pushNamed(routeName);
  }

  /// Cartes visibles : module de l'activité **et** permission du rôle.
  List<Widget> _cartes(BuildContext context) {
    final ModulesService modules = ModulesService.instance;
    final PermissionService permissions = PermissionService.instance;

    bool actif(String code) => modules.moduleActif(code);
    bool voit(PageAccess page) => permissions.peutVoir(page);

    return <Widget>[
      if (actif(ModuleCode.finance) && voit(PageAccess.depenses))
        _CommercialActionCard(
          title: 'Dépenses',
          subtitle: 'Enregistrer les charges et suivre les sorties.',
          icon: Icons.payments_rounded,
          color: Colors.redAccent,
          onTap: () => _goTo(context, 'depenses'),
        ),
      if (actif(ModuleCode.caisse) && voit(PageAccess.caisse))
        _CommercialActionCard(
          title: 'Dettes',
          subtitle: 'Gérer les crédits clients et le suivi des paiements.',
          icon: Icons.credit_score_rounded,
          color: Colors.deepOrange,
          onTap: () => _goTo(context, 'dettes'),
        ),
      if (actif(ModuleCode.clients) && voit(PageAccess.clients))
        _CommercialActionCard(
          title: 'Mes Clients',
          subtitle: 'Gérer les coordonnées et le répertoire client.',
          icon: Icons.people_alt_rounded,
          color: Colors.teal,
          onTap: () => _goTo(context, 'clients'),
        ),
      if (actif(ModuleCode.stock) && voit(PageAccess.stock))
        _CommercialActionCard(
          title: 'Inventaires quotidiens',
          subtitle: 'Comparer le stock théorique et le stock physique.',
          icon: Icons.inventory_2_rounded,
          color: Colors.blueAccent,
          onTap: () => _goTo(context, 'inventaires'),
        ),
      if (actif(ModuleCode.rapports) && voit(PageAccess.rapports))
        _CommercialActionCard(
          title: 'Rapports',
          subtitle: 'Consulter les analyses et le résumé commercial.',
          icon: Icons.bar_chart_rounded,
          color: Colors.green,
          onTap: () => _goTo(context, 'reports'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion commerciale'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isTablet = constraints.maxWidth >= 700;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- BANNIÈRE D'ENTÊTE ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.tertiary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Centre de gestion',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Pilote tes clients, tes dettes et tes inventaires en un seul endroit.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'Modules disponibles',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // --- GRILLE OU LISTE DE MODULES (pilotée par l'activité) ---
                  // Le profil de modules peut arriver après le premier
                  // affichage (réseau) : on écoute le ValueNotifier pour que
                  // les cartes hors activité disparaissent aussitôt.
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: ModulesService.instance.modules,
                    builder: (BuildContext ctx, Set<String> _, Widget? __) {
                      final List<Widget> cartes = _cartes(ctx);

                      if (cartes.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            'Aucun écran de gestion commerciale n\'est activé '
                            'pour cette activité. Passez par l\'accueil ou '
                            'contactez votre administrateur.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        );
                      }

                      if (isTablet) {
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 2.1,
                          ),
                          itemCount: cartes.length,
                          itemBuilder: (context, index) => cartes[index],
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cartes.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) => cartes[index],
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // --- SECTION CONSEIL ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conseil de pro',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enregistre tes clients avant de créer des dettes. Cela permet un suivi automatique de leurs soldes et facilite la relance par téléphone.',
                          style: TextStyle(height: 1.4),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  FilledButton.icon(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Retour au menu'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CommercialActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CommercialActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}