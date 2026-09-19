// lib/pages/productions_page.dart
//
// 🥖 MODULE 16 (phase C5) — BOULANGERIE : PRODUCTIONS DE L'ATELIER.
//
// Tableau de bord du jour (alertes matières, productions, quantité, pertes,
// coût) puis liste des productions (en cours / terminées / annulées) avec
// accès au dossier complet (matières consommées, clôture, annulation).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/production.dart';
import 'package:biashara_yangu/models/production_tableau_bord.dart';
import 'package:biashara_yangu/services/production_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/statut_production_chip.dart';

/// Filtres rapides de la liste.
enum _FiltreProduction {
  toutes('Toutes'),
  enCours('En cours'),
  terminees('Terminées'),
  annulees('Annulées');

  const _FiltreProduction(this.libelle);

  final String libelle;
}

class ProductionsPage extends StatefulWidget {
  const ProductionsPage({super.key});

  @override
  State<ProductionsPage> createState() => _ProductionsPageState();
}

class _ProductionsPageState extends State<ProductionsPage> {
  final ProductionService _service = ProductionService.instance;

  List<Production> _productions = const <Production>[];
  TableauBordProduction _bord = const TableauBordProduction();
  _FiltreProduction _filtre = _FiltreProduction.toutes;

  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    String? messageErreur;
    List<Production> productions = const <Production>[];
    TableauBordProduction bord = _bord;

    try {
      productions = await _service.listerProductions();
      try {
        bord = await _service.tableauBord();
      } catch (e) {
        debugPrint('ProductionsPage tableau de bord (ignoré) : $e');
      }
    } on ProductionServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ProductionsPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des productions.';
    }

    if (!mounted) return;

    if (messageErreur != null) {
      if (silencieux) {
        _message(messageErreur, erreur: true);
        return;
      }
      setState(() {
        _erreur = messageErreur;
        _chargement = false;
      });
      return;
    }

    setState(() {
      _productions = productions;
      _bord = bord;
      _erreur = null;
      _chargement = false;
    });
  }

  void _message(String texte, {bool erreur = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red.shade700 : null,
      ),
    );
  }

  bool _correspond(Production production) {
    switch (_filtre) {
      case _FiltreProduction.toutes:
        return true;
      case _FiltreProduction.enCours:
        return production.statut == StatutProduction.enCours;
      case _FiltreProduction.terminees:
        return production.statut == StatutProduction.terminee;
      case _FiltreProduction.annulees:
        return production.statut == StatutProduction.annulee;
    }
  }

  int _compter(_FiltreProduction filtre) {
    final _FiltreProduction precedent = _filtre;
    _filtre = filtre;
    final int total = _productions.where(_correspond).length;
    _filtre = precedent;
    return total;
  }

  Future<void> _ouvrirNouvelle() async {
    final bool? ok = await context.push<bool>('/main/production/new');
    if (ok == true) _charger(silencieux: true);
  }

  Future<void> _ouvrirDetail(Production production) async {
    final bool? modifie = await context.push<bool>('/main/production/${production.id}');
    if (modifie == true) _charger(silencieux: true);
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productions'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Matières premières',
            onPressed: () async {
              await context.pushNamed('production-matieres');
              _charger(silencieux: true);
            },
            icon: const Icon(Icons.science_outlined),
          ),
          IconButton(
            tooltip: 'Guide d\'utilisation',
            onPressed: () => context.pushNamed('guide-utilisation'),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ouvrirNouvelle,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle production'),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur()
              : _contenu(),
    );
  }

  Widget _vueErreur() {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.cloud_off_rounded,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(_erreur!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _charger(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenu() {
    final ThemeData theme = Theme.of(context);
    final List<Production> affichees =
        _productions.where(_correspond).toList(growable: false);

    return RefreshIndicator(
      onRefresh: () => _charger(silencieux: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: <Widget>[
          _bandeauBord(theme),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final _FiltreProduction filtre in _FiltreProduction.values)
                  ChoiceChip(
                    label: Text('${filtre.libelle} (${_compter(filtre)})'),
                    selected: _filtre == filtre,
                    onSelected: (_) => setState(() => _filtre = filtre),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (affichees.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: <Widget>[
                  Icon(Icons.bakery_dining_outlined,
                      size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(
                    _productions.isEmpty
                        ? 'Aucune production enregistrée.\n'
                            'Lancez votre première fournée : choisissez le '
                            'produit fini et la quantité prévue.'
                        : 'Aucune production pour ce filtre.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            for (final Production production in affichees)
              _carte(production),
        ],
      ),
    );
  }

  Widget _bandeauBord(ThemeData theme) {
    Widget tuile(String libelle, String valeur, IconData icone, Color couleur) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: couleur.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: <Widget>[
              Icon(icone, size: 20, color: couleur),
              const SizedBox(height: 6),
              Text(
                valeur,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(libelle,
                  style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_bord.matieresAlerte > 0)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.35)),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFDC2626), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_bord.matieresAlerte} matière'
                    '${_bord.matieresAlerte > 1 ? 's' : ''} en alerte de '
                    'stock — pensez à réapprovisionner.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await context.pushNamed('production-matieres');
                    _charger(silencieux: true);
                  },
                  child: const Text('Voir'),
                ),
              ],
            ),
          ),
        Text(
          'Aujourd\'hui',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            tuile('Productions', '${_bord.productionsJour}',
                Icons.bakery_dining_rounded, const Color(0xFFB45309)),
            const SizedBox(width: 8),
            tuile(
                'Produit',
                Production.nombre(_bord.quantiteJour),
                Icons.inventory_rounded,
                const Color(0xFF16A34A)),
            const SizedBox(width: 8),
            tuile('Pertes', Production.nombre(_bord.pertesJour),
                Icons.trending_down_rounded, const Color(0xFFDC2626)),
            const SizedBox(width: 8),
            tuile('Coût', formatMontant(_bord.coutJour),
                Icons.payments_rounded, const Color(0xFF2563EB)),
          ],
        ),
      ],
    );
  }

  Widget _carte(Production production) {
    final ThemeData theme = Theme.of(context);
    final bool enCours = production.statut == StatutProduction.enCours;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _ouvrirDetail(production),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      production.produitNom.isEmpty
                          ? 'Production'
                          : production.produitNom,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatutProductionChip(statut: production.statut, compact: true),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${production.numero ?? 'Production'} • '
                'prévu : ${Production.nombre(production.quantitePrevue)}'
                '${production.statut == StatutProduction.terminee ? ' • produit : ${Production.nombre(production.quantiteReelle)}' : ''}',
                style: theme.textTheme.bodySmall,
              ),
              if (production.consommations.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '${production.consommations.length} matière'
                  '${production.consommations.length > 1 ? 's' : ''} • '
                  'coût matières : ${formatMontant(production.coutMatieres)}'
                  '${production.coutUnitaire > 0 ? ' • revient unitaire : ${formatMontant(production.coutUnitaire)}' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (production.pertesAffichees > 0)
                Text(
                  'Pertes : ${Production.nombre(production.pertesAffichees)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFFDC2626)),
                ),
              if (enCours) ...[
                const SizedBox(height: 4),
                Text(
                  'En cours — touchez pour saisir les matières et clôturer.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFFB45309)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
