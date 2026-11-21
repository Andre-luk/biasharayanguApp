// lib/pages/rapports_finance_page.dart
//
// MODULE 10 — RAPPORTS FINANCIERS.
//
// Cinq axes d'analyse servis par `rpc_finance_rapport` :
//   • Articles            — revenus + marge par article ;
//   • Vendeurs            — chiffre d'affaires par vendeur ;
//   • Modes de paiement   — répartition par mode ;
//   • Catégories          — dépenses par catégorie ;
//   • Par jour            — CA / coût / dépenses / bénéfice net quotidiens.
//
// La période est commune aux cinq onglets ; les résultats sont mis en cache
// tant que la période ne change pas.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/finance_stats.dart';
import 'package:biashara_yangu/models/rapport_finance.dart';
import 'package:biashara_yangu/services/finance_service.dart';
// 📅 CORRECTIF 179 — date de référence fournie par le serveur.
import 'package:biashara_yangu/services/date_locale_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class RapportsFinancePage extends StatefulWidget {
  const RapportsFinancePage({super.key});

  @override
  State<RapportsFinancePage> createState() => _RapportsFinancePageState();
}

class _RapportsFinancePageState extends State<RapportsFinancePage>
    with SingleTickerProviderStateMixin {
  final FinanceService _finance = FinanceService.instance;

  late final TabController _tabs =
      TabController(length: GroupeRapportFinance.values.length, vsync: this);

  final Map<GroupeRapportFinance, RapportFinance> _cache =
      <GroupeRapportFinance, RapportFinance>{};

  late DateTime _debut;
  late DateTime _fin;

  bool _chargement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    // 📅 CORRECTIF 179 — la date de référence vient du SERVEUR : le rapport
    // couvre donc la même période que le tableau de bord, quel que soit le
    // téléphone. On démarre sur la date connue localement, puis on affine.
    final DateTime maintenant = DateLocaleService.instance.dernierConnu;
    _fin = DateTime(maintenant.year, maintenant.month, maintenant.day);
    _debut = _fin.subtract(const Duration(days: 29));
    _tabs.addListener(_surChangementOnglet);
    _chargerGroupe(GroupeRapportFinance.article);
    _synchroniserDateServeur();
  }

  /// Récupère la date du serveur puis recharge si la période change.
  Future<void> _synchroniserDateServeur() async {
    final DateTime jour = await DateLocaleService.instance.charger();
    if (!mounted) return;
    final DateTime fin = DateTime(jour.year, jour.month, jour.day);
    if (fin.year == _fin.year && fin.month == _fin.month && fin.day == _fin.day) {
      return;
    }
    setState(() {
      _fin = fin;
      _debut = fin.subtract(const Duration(days: 29));
    });
    _chargerGroupe(_groupeCourant, forcer: true);
  }

  @override
  void dispose() {
    _tabs.removeListener(_surChangementOnglet);
    _tabs.dispose();
    super.dispose();
  }

  GroupeRapportFinance get _groupeCourant =>
      GroupeRapportFinance.values[_tabs.index];

  void _surChangementOnglet() {
    if (_tabs.indexIsChanging) return;
    final GroupeRapportFinance groupe = _groupeCourant;
    if (_cache.containsKey(groupe) && _erreur == null) {
      setState(() {});
      return;
    }
    _chargerGroupe(groupe);
  }

  Future<void> _chargerGroupe(
    GroupeRapportFinance groupe, {
    bool forcer = false,
  }) async {
    if (!forcer && _cache.containsKey(groupe)) {
      setState(() {});
      return;
    }

    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final RapportFinance rapport = await _finance.rapport(
        groupe: groupe,
        debut: _debut,
        fin: _fin,
      );
      if (!mounted) return;
      setState(() => _cache[groupe] = rapport);
    } on FinanceServiceException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'Impossible de charger le rapport : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  // ---------------------------------------------------------------------------
  // PÉRIODE
  // ---------------------------------------------------------------------------

  void _appliquerPeriode(DateTime debut, DateTime fin) {
    setState(() {
      _debut = debut;
      _fin = fin;
      _cache.clear();
    });
    _chargerGroupe(_groupeCourant, forcer: true);
  }

  Future<void> _choisirPeriodePersonnalisee() async {
    final DateTime maintenant = DateTime.now();
    final DateTimeRange? choix = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(maintenant.year, maintenant.month, maintenant.day),
      initialDateRange: DateTimeRange(start: _debut, end: _fin),
      helpText: 'Période du rapport',
      saveText: 'Valider',
    );
    if (choix == null) return;
    _appliquerPeriode(choix.start, choix.end);
  }

  Widget _selecteurPeriode() {
    final ThemeData theme = Theme.of(context);

    final DateTime maintenant = DateTime.now();
    final DateTime aujourdHui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);

    bool estActif(DateTime debut) =>
        _debut.year == debut.year &&
        _debut.month == debut.month &&
        _debut.day == debut.day &&
        _fin.year == aujourdHui.year &&
        _fin.month == aujourdHui.month &&
        _fin.day == aujourdHui.day;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                ChoiceChip(
                  label: const Text('7 jours'),
                  selected: estActif(aujourdHui.subtract(const Duration(days: 6))),
                  onSelected: (bool selection) {
                    if (!selection) return;
                    _appliquerPeriode(
                        aujourdHui.subtract(const Duration(days: 6)),
                        aujourdHui);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('30 jours'),
                  selected:
                      estActif(aujourdHui.subtract(const Duration(days: 29))),
                  onSelected: (bool selection) {
                    if (!selection) return;
                    _appliquerPeriode(
                        aujourdHui.subtract(const Duration(days: 29)),
                        aujourdHui);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Ce mois'),
                  selected: _debut.day == 1 &&
                      _debut.month == aujourdHui.month &&
                      _debut.year == aujourdHui.year,
                  onSelected: (bool selection) {
                    if (!selection) return;
                    _appliquerPeriode(
                        DateTime(aujourdHui.year, aujourdHui.month, 1),
                        aujourdHui);
                  },
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.date_range_rounded, size: 16),
                  label: const Text('Personnalisé'),
                  onPressed: _choisirPeriodePersonnalisee,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Du ${formatDate(_debut)} au ${formatDate(_fin)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RENDU
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Rapports financiers',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => _chargerGroupe(_groupeCourant, forcer: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: GroupeRapportFinance.values
              .map((GroupeRapportFinance groupe) =>
                  Tab(text: groupe.libelle))
              .toList(growable: false),
        ),
      ),
      body: Column(
        children: <Widget>[
          _selecteurPeriode(),
          const Divider(height: 1),
          Expanded(child: _contenu()),
        ],
      ),
    );
  }

  Widget _contenu() {
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
                onPressed: () => _chargerGroupe(_groupeCourant, forcer: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final RapportFinance? rapport = _cache[_groupeCourant];
    if (rapport == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => _chargerGroupe(_groupeCourant, forcer: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _carteTotaux(rapport),
          const SizedBox(height: 12),
          if (rapport.lignes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Aucune donnée sur la période.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            )
          else
            ...rapport.lignes.map(
              (LigneRapportFinance ligne) => _tuileLigne(rapport, ligne),
            ),
        ],
      ),
    );
  }

  Widget _carteTotaux(RapportFinance rapport) {
    final ThemeData theme = Theme.of(context);
    final StatsPeriode totaux = rapport.totaux;
    final bool estDepenses =
        rapport.groupe == GroupeRapportFinance.categorieDepense;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Totaux — ${rapport.groupe.libelle}',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _blocTotal(
                    'Chiffre d\'affaires',
                    formatMontant(totaux.chiffreAffaires),
                    theme.colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: _blocTotal(
                    'Dépenses',
                    formatMontant(totaux.depenses),
                    Colors.red.shade700,
                  ),
                ),
                Expanded(
                  child: _blocTotal(
                    'Bénéfice net',
                    formatMontant(totaux.beneficeNet),
                    totaux.beneficeNet >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
              ],
            ),
            if (!estDepenses) ...<Widget>[
              const Divider(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('Marge brute : ${formatMontant(totaux.margeBrute)}',
                        style: theme.textTheme.bodySmall),
                  ),
                  Text('${totaux.nbVentes} vente(s)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _blocTotal(String libelle, String valeur, Color couleur) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          libelle,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          valeur,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: couleur,
          ),
        ),
      ],
    );
  }

  Widget _tuileLigne(RapportFinance rapport, LigneRapportFinance ligne) {
    final ThemeData theme = Theme.of(context);
    final double total = rapport.totalLignes;
    final bool estJour = rapport.groupe == GroupeRapportFinance.jour;

    final String libelle;
    if (rapport.groupe == GroupeRapportFinance.mode) {
      libelle = FinanceService.libelleMode(ligne.libelle);
    } else if (estJour) {
      libelle = formatDate(DateTime.tryParse(ligne.libelle));
    } else {
      libelle = ligne.libelle;
    }

    final List<String> details = <String>[
      if (ligne.nb != null)
        estJour || rapport.groupe == GroupeRapportFinance.vendeur ||
                rapport.groupe == GroupeRapportFinance.mode
            ? '${ligne.nb} vente(s)'
            : '${ligne.nb} opération(s)',
      if (ligne.quantite != null)
        'Quantité : ${formatQuantite(ligne.quantite!)}',
      if (ligne.marge != null) 'Marge : ${formatMontant(ligne.marge!)}',
      if (estJour && ligne.depenses != null)
        'Dépenses : ${formatMontant(ligne.depenses!)}',
    ];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    libelle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatMontant(ligne.montant),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (details.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                details.join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (estJour && ligne.beneficeNet != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                'Bénéfice net : ${formatMontant(ligne.beneficeNet!)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ligne.beneficeNet! >= 0
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
            ],
            if (!estJour && total > 0) ...<Widget>[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ligne.part(total).clamp(0, 1),
                  minHeight: 5,
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
