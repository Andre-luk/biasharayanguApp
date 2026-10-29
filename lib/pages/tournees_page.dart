// lib/pages/tournees_page.dart
//
// 🚚 MODULE 23 — TOURNÉES & DISTRIBUTION (vue du propriétaire).
//
// • liste des tournées sur une période (30 jours par défaut) ;
// • totaux : CA, quantités vendues, écarts, consignes ouvertes, bonus ;
// • temps réel : la liste se rafraîchit dès qu'un agent vend ou clôture ;
// • accès à la préparation d'une dotation et au détail d'une tournée.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/distribution_terrain.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/distribution_service.dart';
import 'package:biashara_yangu/services/donnees_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class TourneesPage extends StatefulWidget {
  const TourneesPage({super.key});

  @override
  State<TourneesPage> createState() => _TourneesPageState();
}

class _TourneesPageState extends State<TourneesPage> {
  final DistributionService _service = DistributionService.instance;

  RapportDistribution _rapport = const RapportDistribution();
  List<AgentDistribution> _agents = const <AgentDistribution>[];

  String? _agentFiltre;
  bool _chargement = true;
  String? _erreur;

  RealtimeChannel? _canal;
  Timer? _antiRebond;

  @override
  void initState() {
    super.initState();
    DonneesService.instance.revision.addListener(_planifier);
    _initialiser();
  }

  @override
  void dispose() {
    DonneesService.instance.revision.removeListener(_planifier);
    _antiRebond?.cancel();
    final RealtimeChannel? canal = _canal;
    if (canal != null) unawaited(_service.arreterEcoute(canal));
    super.dispose();
  }

  Future<void> _initialiser() async {
    await Future.wait(<Future<void>>[_charger(), _chargerAgents()]);
    await _demarrerTempsReel();
  }

  Future<void> _chargerAgents() async {
    final List<AgentDistribution> agents = await _service.listerAgents();
    if (mounted) setState(() => _agents = agents);
  }

  Future<void> _demarrerTempsReel() async {
    try {
      final String? ownerId =
          await ArticleService.instance.proprietaireCourant();
      if (ownerId == null || ownerId.isEmpty || !mounted) return;
      _canal = _service.ecouterChangements(ownerId, _planifier);
    } catch (e) {
      debugPrint('TourneesPage temps réel indisponible : $e');
    }
  }

  void _planifier() {
    _antiRebond?.cancel();
    _antiRebond = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _charger(silencieux: true);
    });
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;
    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    try {
      final RapportDistribution rapport =
          await _service.rapport(agentId: _agentFiltre);
      if (!mounted) return;
      setState(() {
        _rapport = rapport;
        _chargement = false;
      });
    } on DistributionException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e) {
      debugPrint('TourneesPage._charger : $e');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger les tournées.';
        _chargement = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tournées & distribution'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: () => _charger(silencieux: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final bool? cree = await context.push<bool>('/main/tournees/new');
          if (cree == true) _charger(silencieux: true);
        },
        icon: const Icon(Icons.add_road_rounded),
        label: const Text('Nouvelle tournée'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _charger(silencieux: true),
        child: _corps(),
      ),
    );
  }

  Widget _corps() {
    if (_chargement) {
      return const Center(child: ModernLoader(legende: 'Chargement…'));
    }

    if (_erreur != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _CarteErreur(
            message: _erreur!,
            onReessayer: () => _charger(),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: <Widget>[
        _resume(),
        const SizedBox(height: 12),
        if (_agents.length > 1) _filtreAgent(),
        const SizedBox(height: 8),
        if (_rapport.tournees.isEmpty)
          const _Vide()
        else
          ..._rapport.tournees.map(
            (TourneeDistribution t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CarteTournee(
                tournee: t,
                onTap: () async {
                  await context.push<void>('/main/tournees/${t.id}', extra: t);
                  _charger(silencieux: true);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _resume() {
    final TotauxDistribution t = _rapport.totaux;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppDegrades.hero,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Distribution (30 derniers jours)',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            formatMontant(t.chiffreAffaires),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: <Widget>[
              _MiniStat(label: 'Tournées', valeur: '${t.tournees}'),
              _MiniStat(
                label: 'Vendues',
                valeur: formatQuantite(t.quantiteVendue),
              ),
              _MiniStat(label: 'Écarts', valeur: formatQuantite(t.ecart)),
              _MiniStat(
                label: 'Consignes',
                valeur: formatQuantite(t.consignesOuvertes),
              ),
              _MiniStat(label: 'Bonus', valeur: formatMontant(t.bonus)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filtreAgent() {
    return AppDropdownField<String?>(
      label: 'Agent',
      value: _agentFiltre,
      prefixIcon: Icons.person_rounded,
      items: <DropdownMenuItem<String?>>[
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Tous les agents'),
        ),
        ..._agents.map(
          (AgentDistribution a) => DropdownMenuItem<String?>(
            value: a.id,
            child: Text(a.libelle, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (String? valeur) {
        setState(() => _agentFiltre = valeur);
        _charger();
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.valeur});

  final String label;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        Text(
          valeur,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _CarteTournee extends StatelessWidget {
  const _CarteTournee({required this.tournee, required this.onTap});

  final TourneeDistribution tournee;
  final VoidCallback onTap;

  Color get _couleur => switch (tournee.statut) {
        TourneeStatut.enCours => const Color(0xFF0F766E),
        TourneeStatut.cloturee => const Color(0xFF2563EB),
        TourneeStatut.annulee => const Color(0xFF64748B),
        TourneeStatut.preparee => const Color(0xFFF59E0B),
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? date = tournee.dateTournee;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      tournee.agentNom.isEmpty
                          ? 'Agent sans nom'
                          : tournee.agentNom,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _couleur.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      tournee.statut.libelle,
                      style: TextStyle(
                        color: _couleur,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                <String>[
                  tournee.reference,
                  if (date != null) _dateFr(date),
                  if (tournee.zone.isNotEmpty) tournee.zone,
                ].join(' • '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  _Valeur(label: 'Attribué', valeur: formatQuantite(tournee.quantiteAttribuee)),
                  _Valeur(label: 'Vendu', valeur: formatQuantite(tournee.quantiteVendue)),
                  _Valeur(label: 'Rendu', valeur: formatQuantite(tournee.quantiteRetournee)),
                  _Valeur(
                    label: 'Écart',
                    valeur: formatQuantite(tournee.ecart),
                    alerte: tournee.ecart > 0.0001,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(Icons.payments_rounded,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    formatMontant(tournee.chiffreAffaires),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (tournee.consignesOuvertes > 0) ...<Widget>[
                    const Icon(Icons.inventory_rounded, size: 16),
                    const SizedBox(width: 4),
                    Text('${tournee.consignesOuvertes} consigne(s)'),
                    const SizedBox(width: 12),
                  ],
                  if (tournee.bonusTotal > 0)
                    Text('Bonus ${formatMontant(tournee.bonusTotal)}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Valeur extends StatelessWidget {
  const _Valeur({
    required this.label,
    required this.valeur,
    this.alerte = false,
  });

  final String label;
  final String valeur;
  final bool alerte;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            valeur,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: alerte ? const Color(0xFFDC2626) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        children: <Widget>[
          Icon(Icons.local_shipping_outlined,
              size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'Aucune tournée sur la période.',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Préparez une dotation : l\'agent ne pourra vendre que ce que '
            'vous lui avez confié.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CarteErreur extends StatelessWidget {
  const _CarteErreur({required this.message, required this.onReessayer});

  final String message;
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            message,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onReessayer,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

String _dateFr(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';
