// lib/pages/referentiels_hub_page.dart
//
// MODULE 2 — Point d'entrée « Activités & groupes tarifaires ».
//
// Cet écran est l'onglet « Référentiels » de l'espace administrateur : il
// présente les deux référentiels, leur volume, puis ouvre leurs écrans de
// gestion respectifs.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/activite.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/services/referentiel_service.dart';

class ReferentielsHubPage extends StatefulWidget {
  const ReferentielsHubPage({super.key});

  @override
  State<ReferentielsHubPage> createState() => _ReferentielsHubPageState();
}

class _ReferentielsHubPageState extends State<ReferentielsHubPage> {
  final ReferentielService _service = ReferentielService.instance;

  bool _chargement = true;
  String? _erreur;

  int _nbActivites = 0;
  int _nbGroupes = 0;
  int _nbEntreprises = 0;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    String? messageErreur;
    int nbActivites = 0;
    int nbGroupes = 0;
    int nbEntreprises = 0;

    try {
      final List<dynamic> resultats = await Future.wait<dynamic>(
        <Future<dynamic>>[
          _service.getActivites(),
          _service.getGroupesTarifaires(),
          _service.getCompteursEntreprises(),
        ],
      );

      final List<Activite> activites = resultats[0] as List<Activite>;
      final List<GroupeTarifaire> groupes =
          resultats[1] as List<GroupeTarifaire>;
      final CompteursEntreprises compteurs =
          resultats[2] as CompteursEntreprises;

      nbActivites = activites.length;
      nbGroupes = groupes.length;
      nbEntreprises = compteurs.parActivite.values.fold<int>(
        0,
        (int total, int valeur) => total + valeur,
      );
    } on ReferentielServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ReferentielsHubPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des référentiels.';
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
      _nbActivites = nbActivites;
      _nbGroupes = nbGroupes;
      _nbEntreprises = nbEntreprises;
      _erreur = null;
      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirActivites() async {
    final GoRouter router = GoRouter.of(context);
    await router.push<void>('/admin/activites');

    if (!mounted) return;
    await _charger(silencieux: true);
  }

  Future<void> _ouvrirGroupes() async {
    final GoRouter router = GoRouter.of(context);
    await router.push<void>('/admin/groupes-tarifaires');

    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

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
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Activités & groupes tarifaires',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Gérez le catalogue des activités commerciales et les grilles '
            'tarifaires appliquées aux entreprises.',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _carteReferentiel(
            theme,
            icone: Icons.storefront_rounded,
            titre: 'Activités',
            description:
                'Créer, renommer et organiser les activités proposées aux '
                'entreprises.',
            statistiques: '$_nbActivites activité'
                '${_nbActivites > 1 ? 's' : ''} • $_nbEntreprises entreprise'
                '${_nbEntreprises > 1 ? 's' : ''} rattachée'
                '${_nbEntreprises > 1 ? 's' : ''}',
            onTap: _ouvrirActivites,
          ),
          const SizedBox(height: 12),
          _carteReferentiel(
            theme,
            icone: Icons.sell_rounded,
            titre: 'Groupes tarifaires',
            description:
                "Définir les montants d'abonnement, les frais d'ouverture, "
                "les durées d'essai et le prix par collaborateur.",
            statistiques: '$_nbGroupes groupe'
                '${_nbGroupes > 1 ? 's' : ''} tarifaire'
                '${_nbGroupes > 1 ? 's' : ''}',
            onTap: _ouvrirGroupes,
          ),
          const SizedBox(height: 20),
          _note(theme),
        ],
      ),
    );
  }

  Widget _carteReferentiel(
    ThemeData theme, {
    required IconData icone,
    required String titre,
    required String description,
    required String statistiques,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  icone,
                  size: 22,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      statistiques,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
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
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Une activité ou un groupe tarifaire encore utilisé par une '
                'entreprise ne peut pas être supprimé : modifiez d\'abord les '
                'entreprises concernées.',
                style: TextStyle(
                  fontSize: 12,
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Chargement impossible',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _erreur ?? 'Erreur inconnue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
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
