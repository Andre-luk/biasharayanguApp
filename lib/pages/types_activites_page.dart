// lib/pages/types_activites_page.dart
//
// 🧩 MODULE 16 — « TYPES D'ACTIVITÉS » (liste, administration plateforme).
//
// Un type d'activité (boutique, hôtel, pharmacie…) référence un PROFIL DE
// MODULES : c'est lui qui détermine les écrans affichés dans l'application
// de chaque entreprise. L'« Expert Administrateur » crée ici de nouveaux
// types (ex : « Salon de coiffure ») et coche leurs modules — aucune mise à
// jour de l'application n'est nécessaire.
//
// Le profil « Boutique » est le profil de repli universel : il ne peut pas
// être désactivé.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/services/modules_service.dart';

class TypesActivitesPage extends StatefulWidget {
  const TypesActivitesPage({super.key});

  @override
  State<TypesActivitesPage> createState() => _TypesActivitesPageState();
}

class _TypesActivitesPageState extends State<TypesActivitesPage> {
  final ModulesService _service = ModulesService.instance;

  List<ProfilModules> _profils = const <ProfilModules>[];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  /// [silencieux] évite l'écran de chargement complet lors d'un
  /// rafraîchissement de fond (retour depuis le formulaire, pull-to-refresh…).
  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    String? messageErreur;
    List<ProfilModules> profils = const <ProfilModules>[];

    try {
      profils = await _service.listerProfils();
    } on ModulesServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('TypesActivitesPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des types.';
    }

    if (!mounted) return;

    if (messageErreur != null) {
      if (silencieux) {
        _afficherMessage(messageErreur, estErreur: true);
        return;
      }
      setState(() {
        _erreur = messageErreur;
        _chargement = false;
      });
      return;
    }

    setState(() {
      _profils = profils;
      _erreur = null;
      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  Future<void> _ouvrir({ProfilModules? profil}) async {
    final GoRouter router = GoRouter.of(context);
    final Object? resultat = await router.push<Object?>(
      profil == null
          ? '/admin/types-activites/new'
          : '/admin/types-activites/${profil.type}',
      extra: profil,
    );

    if (!mounted || resultat == null) return;
    await _charger(silencieux: true);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  void _afficherMessage(String message, {bool estErreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: estErreur
            ? Colors.red.shade700
            : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Icône illustrant un type d'activité (types libres : puzzle).
  static IconData _iconeType(String type) {
    switch (type) {
      case 'boutique':
        return Icons.storefront_rounded;
      case 'hotel':
        return Icons.hotel;
      case 'pharmacie':
        return Icons.local_pharmacy;
      case 'restaurant':
        return Icons.restaurant;
      case 'depot':
        return Icons.warehouse_rounded;
      case 'autre':
        return Icons.category_rounded;
      default:
        return Icons.extension_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Types d'activités",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      floatingActionButton: (_chargement || _erreur != null)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _ouvrir(),
              icon: const Icon(Icons.add),
              label: const Text('Nouveau type'),
            ),
      body: _construireCorps(theme),
    );
  }

  Widget _construireCorps(ThemeData theme) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreur != null) {
      return _vueErreur(theme);
    }

    return RefreshIndicator(
      onRefresh: () => _charger(),
      color: theme.colorScheme.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text(
            'Modules par activité',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Le type d'activité d'une entreprise détermine les modules "
            'affichés dans son application. Créez un type et cochez ses '
            'modules : les entreprises qui l\'utilisent s\'adaptent '
            'automatiquement.',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          for (final ProfilModules profil in _profils) ...[
            _carteProfil(theme, profil),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          _note(theme),
        ],
      ),
    );
  }

  Widget _carteProfil(ThemeData theme, ProfilModules profil) {
    final List<String> modules = ModulesService.ordonnerModules(profil.modules);
    const int apercu = 5;

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _ouvrir(profil: profil),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      _iconeType(profil.type),
                      size: 22,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                profil.libelle,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (profil.profilDefaut) ...[
                              const SizedBox(width: 8),
                              _puce(
                                theme,
                                'Défaut',
                                theme.colorScheme.primary,
                                theme.colorScheme.primaryContainer,
                              ),
                            ],
                            if (!profil.actif) ...[
                              const SizedBox(width: 8),
                              _puce(
                                theme,
                                'Inactif',
                                theme.colorScheme.error,
                                theme.colorScheme.errorContainer,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${profil.type} • ${profil.modules.length} module'
                          '${profil.modules.length > 1 ? 's' : ''} • '
                          '${profil.nbEspaces} entreprise'
                          '${profil.nbEspaces > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (modules.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final String code in modules.take(apercu))
                      _puce(
                        theme,
                        ModuleActivite.parCode(code)?.libelle ?? code,
                        theme.colorScheme.onSurfaceVariant,
                        theme.colorScheme.surfaceContainerHighest,
                      ),
                    if (modules.length > apercu)
                      _puce(
                        theme,
                        '+${modules.length - apercu}',
                        theme.colorScheme.onSurfaceVariant,
                        theme.colorScheme.surfaceContainerHighest,
                      ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  'Aucun module — l\'application restera en mode standard '
                  '(tout est visible).',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _puce(
    ThemeData theme,
    String texte,
    Color couleurTexte,
    Color couleurFond,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: couleurFond,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: couleurTexte,
        ),
      ),
    );
  }

  Widget _note(ThemeData theme) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Un module ne fait que MASQUER les écrans qui ne concernent '
                'pas l\'activité : les données restent intactes. Si un profil '
                'est vide ou absent, l\'application garde son comportement '
                'standard — aucune entreprise n\'est bloquée.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vueErreur(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              _erreur ?? 'Erreur inconnue.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _charger(),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
