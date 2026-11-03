// lib/pages/distribution_journal_page.dart
//
// 🚚 MODULE 24 — JOURNAL DE TRAÇABILITÉ DE LA DISTRIBUTION.
//
// Lecture seule du journal `dist_journal` (alimenté par `dist_journaliser`) :
// qui a fait quoi, quand, sur quelle entité. Sert aux contrôles de la
// direction : réceptions, productions, ventes, retours, remises, dépenses,
// anomalies, paramètres.
//
// Aucune écriture n'est possible depuis cet écran — c'est volontaire : la
// traçabilité doit rester incontestable.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/services/distribution_gestion_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class DistributionJournalPage extends StatefulWidget {
  const DistributionJournalPage({super.key});

  @override
  State<DistributionJournalPage> createState() =>
      _DistributionJournalPageState();
}

class _DistributionJournalPageState extends State<DistributionJournalPage> {
  static const String _toutes = 'TOUTES';

  final DistributionGestionService _service =
      DistributionGestionService.instance;

  bool _chargement = true;
  String? _erreur;
  List<EntreeJournalDistribution> _entrees =
      const <EntreeJournalDistribution>[];
  String _filtre = _toutes;

  /// Familles proposées au filtre (codes réels écrits par les RPC).
  static const Map<String, String> _familles = <String, String>{
    'TOUTES': 'Toutes les opérations',
    'RECEPTION_INTRANTS_CREE': 'Réceptions — création',
    'RECEPTION_INTRANTS_CONFIRMEE': 'Réceptions — confirmation',
    'RECEPTION_INTRANTS_REFUSEE': 'Réceptions — refus',
    'PRODUCTION_ENREGISTREE': 'Productions — déclaration',
    'PRODUCTION_RECEPTIONNEE': 'Productions — réception stock',
    'VENTE_ENREGISTREE': 'Ventes',
    'RETOUR_DECLARE': 'Retours — déclaration',
    'RETOUR_RECEPTIONNE': 'Retours — réception',
    'REMISE_DECLAREE': 'Remises — déclaration',
    'REMISE_RECEPTIONNEE': 'Remises — réception',
    'REMISE_VALIDEE': 'Remises — validation',
    'DEPENSE_CREEE': 'Dépenses — création',
    'DEPENSE_VALIDEE': 'Dépenses — validation',
    'STOCK_AJUSTE': 'Stock — ajustements',
    'ANOMALIE_RESOLUE': 'Anomalies — résolutions',
  };

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = _entrees.isEmpty;
      _erreur = null;
    });

    try {
      final List<EntreeJournalDistribution> entrees = await _service.journal(
        action: _filtre == _toutes ? null : _filtre,
        limite: 200,
      );
      if (!mounted) return;
      setState(() => _entrees = entrees);
    } on DistributionGestionException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'Impossible de charger le journal : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  IconData _icone(String action) {
    if (action.startsWith('RECEPTION')) return Icons.inventory_2_outlined;
    if (action.startsWith('PRODUCTION')) return Icons.factory_outlined;
    if (action.startsWith('VENTE')) return Icons.point_of_sale_rounded;
    if (action.startsWith('RETOUR')) return Icons.assignment_return_rounded;
    if (action.startsWith('REMISE')) return Icons.payments_rounded;
    if (action.startsWith('DEPENSE')) return Icons.money_off_rounded;
    if (action.startsWith('STOCK')) return Icons.swap_vert_rounded;
    if (action.startsWith('DEMANDE')) return Icons.assignment_outlined;
    if (action.startsWith('ANOMALIE')) return Icons.warning_amber_rounded;
    if (action.startsWith('COLLABORATEUR')) return Icons.groups_2_outlined;
    return Icons.history_rounded;
  }

  Color _couleur(String action, ThemeData theme) {
    if (action.contains('REFUSEE')) return AppCouleurs.danger;
    if (action.startsWith('ANOMALIE')) return AppCouleurs.alerte;
    if (action.startsWith('DEPENSE')) return AppCouleurs.danger;
    if (action.startsWith('RECEPTION') || action.startsWith('PRODUCTION')) {
      return AppCouleurs.info;
    }
    return theme.colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Traçabilité',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _construireCorps(),
    );
  }

  Widget _construireCorps() {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.cloud_off_rounded,
                  size: 56, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _charger,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          AppDropdownField<String>(
            label: 'Type d\'opération',
            value: _filtre,
            prefixIcon: Icons.filter_alt_outlined,
            items: _familles.entries
                .map((MapEntry<String, String> e) => DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(e.value),
                    ))
                .toList(growable: false),
            onChanged: (String? valeur) {
              if (valeur == null) return;
              setState(() => _filtre = valeur);
              _charger();
            },
          ),
          const SizedBox(height: 12),
          Text(
            '${_entrees.length} opération(s) — la plus récente en premier.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          if (_entrees.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Column(
                children: <Widget>[
                  Icon(Icons.history_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 8),
                  const Text('Aucune opération pour ce filtre.'),
                ],
              ),
            )
          else
            for (final EntreeJournalDistribution entree in _entrees)
              _ligne(entree),
        ],
      ),
    );
  }

  Widget _ligne(EntreeJournalDistribution entree) {
    final ThemeData theme = Theme.of(context);
    final Color couleur = _couleur(entree.action, theme);
    final String details = entree.resume;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icone(entree.action), size: 20, color: couleur),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entree.libelle,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    if (entree.auteur.isNotEmpty) entree.auteur,
                    if (entree.role.isNotEmpty) entree.role,
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDateHeure(entree.date),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (details.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    details,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
