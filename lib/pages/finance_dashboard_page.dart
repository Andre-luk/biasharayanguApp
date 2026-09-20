// lib/pages/finance_dashboard_page.dart
//
// MODULE 10 — ÉCRAN « FINANCE / TABLEAU DE BORD ».
//
//   • chiffre d'affaires, dépenses et bénéfice net (jour / semaine / mois) ;
//   • graphiques simples sur les séries de 7 et 30 jours (fl_chart) ;
//   • top articles des 30 derniers jours.
//
// ⚠️ La finance de l'ENTREPRISE est isolée de la finance plateforme La Perle.
//    Le serveur ne renvoie ces chiffres qu'aux membres ayant `finance/voir`.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/finance_stats.dart';
import 'package:biashara_yangu/models/permission.dart';
// 🪙 MODULE 18 — devise de travail et équivalences de change.
import 'package:biashara_yangu/services/devise_service.dart';
import 'package:biashara_yangu/services/finance_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class FinanceDashboardPage extends StatefulWidget {
  const FinanceDashboardPage({super.key});

  @override
  State<FinanceDashboardPage> createState() => _FinanceDashboardPageState();
}

class _FinanceDashboardPageState extends State<FinanceDashboardPage> {
  final FinanceService _finance = FinanceService.instance;

  bool _chargement = true;
  String? _erreur;
  TableauBordFinance? _bord;

  /// Période affichée : `jour`, `semaine` ou `mois`.
  String _periode = 'jour';

  /// Taille de la série graphique : 7 ou 30 jours.
  int _serieJours = 7;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = _bord == null;
      _erreur = null;
    });
    try {
      final TableauBordFinance bord = await _finance.tableauBord();
      if (!mounted) return;
      setState(() => _bord = bord);
    } on FinanceServiceException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'Impossible de charger la finance : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  StatsPeriode get _stats {
    final TableauBordFinance? bord = _bord;
    if (bord == null) return StatsPeriode.vide;
    switch (_periode) {
      case 'semaine':
        return bord.semaine;
      case 'mois':
        return bord.mois;
      default:
        return bord.jour;
    }
  }

  List<PointSerieFinance> get _serie {
    final TableauBordFinance? bord = _bord;
    if (bord == null) return const <PointSerieFinance>[];
    return _serieJours == 7 ? bord.series7 : bord.series30;
  }

  // ---------------------------------------------------------------------------
  // RENDU
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool peutRapports =
        PermissionService.instance.peutVoir(PageAccess.rapports) ||
            PermissionService.instance.peutVoir(PageAccess.finance);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Finance',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: <Widget>[
          if (peutRapports)
            IconButton(
              tooltip: 'Rapports détaillés',
              onPressed: () => context.push('/main/finance/rapports'),
              icon: const Icon(Icons.bar_chart_rounded),
            ),
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

    final ThemeData theme = Theme.of(context);
    final StatsPeriode stats = _stats;

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'jour', label: Text('Jour')),
                ButtonSegment<String>(value: 'semaine', label: Text('Semaine')),
                ButtonSegment<String>(value: 'mois', label: Text('Mois')),
              ],
              selected: <String>{_periode},
              onSelectionChanged: (Set<String> selection) {
                setState(() => _periode = selection.first);
              },
            ),
          ),
          const SizedBox(height: 16),
          _carteChiffreAffaires(stats),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _carteMontant(
                  titre: 'DÉPENSES',
                  valeur: formatMontant(stats.depenses),
                  detail: '${stats.nbDepenses} dépense(s)',
                  couleur: Colors.red.shade700,
                  icone: Icons.payments_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _carteMontant(
                  titre: 'BÉNÉFICE NET',
                  valeur: formatMontant(stats.beneficeNet),
                  detail:
                      'Marge : ${stats.tauxMarge.toStringAsFixed(1)} %',
                  couleur: stats.beneficeNet >= 0
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  icone: stats.beneficeNet >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  _ligneDetail('Coût des marchandises vendues',
                      formatMontant(stats.coutMarchandises)),
                  const Divider(height: 16),
                  _ligneDetail('Marge brute', formatMontant(stats.margeBrute)),
                  const Divider(height: 16),
                  _ligneDetail('Nombre de ventes', '${stats.nbVentes}'),
                  // 🪙 MODULE 18 — équivalence dans l'autre devise.
                  if (DeviseService.instance
                      .equivalent(stats.beneficeNet)
                      .isNotEmpty) ...<Widget>[
                    const Divider(height: 16),
                    _ligneDetail(
                      'Bénéfice net (${DeviseService.instance.configuration.deviseOpposee.symbole})',
                      DeviseService.instance.equivalent(stats.beneficeNet),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _carteGraphiqueLignes(theme),
          const SizedBox(height: 16),
          _carteGraphiqueBenefice(theme),
          const SizedBox(height: 16),
          _carteTopArticles(theme),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- cartes

  Widget _carteChiffreAffaires(StatsPeriode stats) {
    final ThemeData theme = Theme.of(context);
    final String libelle = switch (_periode) {
      'semaine' => 'Chiffre d\'affaires — semaine',
      'mois' => 'Chiffre d\'affaires — mois',
      _ => 'Chiffre d\'affaires — aujourd\'hui',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[theme.colorScheme.primary, theme.colorScheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.show_chart_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  libelle.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatMontant(stats.chiffreAffaires),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${stats.nbVentes} vente(s) sur la période',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteMontant({
    required String titre,
    required String valeur,
    required String detail,
    required Color couleur,
    required IconData icone,
  }) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: couleur.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, color: couleur, size: 20),
          const SizedBox(height: 8),
          Text(
            titre,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valeur,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: couleur,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligneDetail(String libelle, String valeur) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(libelle,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(
          valeur,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- graphiques

  Widget _carteGraphiqueLignes(ThemeData theme) {
    final List<PointSerieFinance> serie = _serie;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Évolution du chiffre d\'affaires',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ChoiceChip(
                  label: const Text('7 j'),
                  selected: _serieJours == 7,
                  onSelected: (bool selection) {
                    if (selection) setState(() => _serieJours = 7);
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('30 j'),
                  selected: _serieJours == 30,
                  onSelected: (bool selection) {
                    if (selection) setState(() => _serieJours = 30);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (serie.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('Aucune donnée sur la période.')),
              )
            else
              SizedBox(
                height: 200,
                child: LineChart(_donneesLignes(theme, serie)),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _legende(theme.colorScheme.primary, 'Chiffre d\'affaires'),
                const SizedBox(width: 16),
                _legende(Colors.orange.shade700, 'Dépenses'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legende(Color couleur, String libelle) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(libelle, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  LineChartData _donneesLignes(ThemeData theme, List<PointSerieFinance> serie) {
    final List<FlSpot> spotsCa = <FlSpot>[
      for (int i = 0; i < serie.length; i++)
        FlSpot(i.toDouble(), serie[i].chiffreAffaires),
    ];
    final List<FlSpot> spotsDepenses = <FlSpot>[
      for (int i = 0; i < serie.length; i++)
        FlSpot(i.toDouble(), serie[i].depenses),
    ];

    return LineChartData(
      minY: 0,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 1,
            getTitlesWidget: _titreJour,
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (List<LineBarSpot> touches) => touches
              .map((LineBarSpot spot) => LineTooltipItem(
                    formatMontant(spot.y),
                    const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ))
              .toList(),
        ),
      ),
      lineBarsData: <LineChartBarData>[
        LineChartBarData(
          spots: spotsCa,
          isCurved: true,
          barWidth: 3,
          color: theme.colorScheme.primary,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
          ),
        ),
        LineChartBarData(
          spots: spotsDepenses,
          isCurved: true,
          barWidth: 3,
          color: Colors.orange.shade700,
          dotData: const FlDotData(show: false),
        ),
      ],
    );
  }

  Widget _carteGraphiqueBenefice(ThemeData theme) {
    final List<PointSerieFinance> serie = _serie;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Bénéfice net par jour',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (serie.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('Aucune donnée sur la période.')),
              )
            else
              SizedBox(
                height: 180,
                child: BarChart(_donneesBenefice(theme, serie)),
              ),
          ],
        ),
      ),
    );
  }

  BarChartData _donneesBenefice(ThemeData theme, List<PointSerieFinance> serie) {
    double minY = 0;
    double maxY = 0;
    for (final PointSerieFinance point in serie) {
      if (point.beneficeNet < minY) minY = point.beneficeNet;
      if (point.beneficeNet > maxY) maxY = point.beneficeNet;
    }
    final double marge = (maxY - minY) * 0.1;

    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      minY: minY < 0 ? minY - marge : 0,
      maxY: maxY > 0 ? maxY + marge : marge + 1,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 1,
            getTitlesWidget: _titreJour,
          ),
        ),
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (BarChartGroupData group, int groupIndex,
                  BarChartRodData rod, int rodIndex) =>
              BarTooltipItem(
            formatMontant(serie[group.x].beneficeNet),
            TextStyle(
              color:
                  serie[group.x].beneficeNet >= 0 ? Colors.green.shade800 : Colors.red.shade800,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
      barGroups: <BarChartGroupData>[
        for (int i = 0; i < serie.length; i++)
          BarChartGroupData(
            x: i,
            barRods: <BarChartRodData>[
              BarChartRodData(
                fromY: serie[i].beneficeNet < 0 ? serie[i].beneficeNet : 0,
                toY: serie[i].beneficeNet < 0 ? 0 : serie[i].beneficeNet,
                width: _serieJours == 7 ? 12 : 6,
                borderRadius: BorderRadius.circular(3),
                color: serie[i].beneficeNet >= 0
                    ? Colors.green.shade600
                    : Colors.red.shade600,
              ),
            ],
          ),
      ],
    );
  }

  Widget _titreJour(double value, TitleMeta meta) {
    final List<PointSerieFinance> serie = _serie;
    final int index = value.round();
    if (index < 0 || index >= serie.length) return const SizedBox.shrink();

    final DateTime? jour = serie[index].jour;
    if (jour == null) return const SizedBox.shrink();

    final bool afficher =
        serie.length <= 10 || index % (serie.length > 10 ? 5 : 1) == 0;
    if (!afficher) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '${jour.day}/${jour.month}',
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- top articles

  Widget _carteTopArticles(ThemeData theme) {
    final List<ArticleTopFinance> articles =
        _bord?.topArticles ?? const <ArticleTopFinance>[];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Top articles (30 derniers jours)',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (articles.isEmpty)
              Text(
                'Aucune vente sur les 30 derniers jours.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...List<Widget>.generate(articles.length, (int index) {
                final ArticleTopFinance article = articles[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              article.nom,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${formatQuantite(article.quantite)} vendu(s)',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            formatMontant(article.ca),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Marge ${formatMontant(article.marge)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
