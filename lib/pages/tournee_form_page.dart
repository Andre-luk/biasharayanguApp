// lib/pages/tournee_form_page.dart
//
// 🚚 MODULE 23 — PRÉPARER UNE DOTATION.
//
// Le propriétaire choisit l'agent, la date, la zone, puis les produits et les
// quantités confiées. La dotation est une RÉSERVATION : elle ne retire rien
// du stock de la boutique. Seules les ventes de l'agent le feront.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/distribution_terrain.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/distribution_service.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class TourneeFormPage extends StatefulWidget {
  const TourneeFormPage({super.key});

  @override
  State<TourneeFormPage> createState() => _TourneeFormPageState();
}

class _TourneeFormPageState extends State<TourneeFormPage> {
  final DistributionService _service = DistributionService.instance;
  final TextEditingController _zoneController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  // Objectif de CA et commission de l'agent : fixés AVANT le départ, et
  // calculés ensuite par le serveur sur les ventes réelles. Un pourcentage
  // promis oralement ne laisse aucune trace ; celui-ci oui.
  final TextEditingController _objectifController = TextEditingController();
  final TextEditingController _commissionController = TextEditingController();
  final TextEditingController _rechercheController = TextEditingController();

  List<AgentDistribution> _agents = const <AgentDistribution>[];
  List<Article> _articles = const <Article>[];
  final Map<int, double> _lignes = <int, double>{};

  String? _agentId;
  DateTime _date = DateTime.now();
  bool _chargement = true;
  bool _envoi = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _rechercheController.addListener(() => setState(() {}));
    _charger();
  }

  @override
  void dispose() {
    _zoneController.dispose();
    _noteController.dispose();
    _objectifController.dispose();
    _commissionController.dispose();
    _rechercheController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final List<dynamic> resultats = await Future.wait(<Future<dynamic>>[
        _service.listerAgents(),
        ArticleService.instance.getArticles(),
      ]);
      if (!mounted) return;
      setState(() {
        _agents = resultats[0] as List<AgentDistribution>;
        _articles = resultats[1] as List<Article>;
        _agentId = _agents.isNotEmpty ? _agents.first.id : null;
        _chargement = false;
      });
    } catch (e) {
      debugPrint('TourneeFormPage._charger : $e');
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = 'Impossible de charger les agents ou les articles.';
      });
    }
  }

  List<Article> get _articlesFiltres {
    final String q = _rechercheController.text.trim().toLowerCase();
    if (q.isEmpty) return _articles;
    return _articles
        .where((Article a) =>
            a.nom.toLowerCase().contains(q) ||
            a.categorie.toLowerCase().contains(q))
        .toList(growable: false);
  }

  double get _quantiteTotale =>
      _lignes.values.fold<double>(0, (double t, double q) => t + q);

  Future<void> _ajouter(Article article) async {
    final TextEditingController controller = TextEditingController(
      text: (_lignes[article.id] ?? 1).toStringAsFixed(0),
    );

    final double? quantite = await showDialog<double>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(article.nom),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: 'Quantité attribuée',
            suffixText: article.uniteMesure,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              double.tryParse(controller.text.replaceAll(',', '.')),
            ),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (quantite == null || quantite <= 0) return;
    setState(() => _lignes[article.id] = quantite);
  }

  Future<void> _enregistrer() async {
    if (_agentId == null) {
      setState(() => _erreur = 'Choisissez un agent.');
      return;
    }
    if (_lignes.isEmpty) {
      setState(() => _erreur = 'Ajoutez au moins un produit.');
      return;
    }

    setState(() {
      _envoi = true;
      _erreur = null;
    });

    try {
      final Map<String, dynamic> creation = await _service.creerTournee(
        agentId: _agentId!,
        date: _date,
        zone: _zoneController.text,
        note: _noteController.text,
        lignes: _lignes.entries
            .map((MapEntry<int, double> e) => <String, dynamic>{
                  'produit_id': e.key,
                  'quantite': e.value,
                })
            .toList(growable: false),
      );

      // L'objectif et la commission se règlent APRÈS la création (la RPC de
      // création garde sa signature). Un échec ici ne doit pas annuler la
      // dotation : la tournée existe, on prévient simplement le patron.
      final String? tourneeId =
          (creation['id'] ?? creation['tournee_id'])?.toString();
      final double? objectif = _nombreSaisi(_objectifController.text);
      final double? commission = _nombreSaisi(_commissionController.text);
      if (tourneeId != null && (objectif != null || commission != null)) {
        try {
          await _service.parametrerTournee(
            tourneeId,
            objectifMontant: objectif,
            commissionTaux: commission,
          );
        } on DistributionException catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Tournée créée, mais objectif/commission non enregistrés : '
                '${e.message}',
              ),
            ),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tournée créée. L\'agent peut la démarrer.')),
      );
      context.pop(true);
    } on DistributionException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _envoi = false;
      });
    } catch (e) {
      debugPrint('TourneeFormPage._enregistrer : $e');
      if (!mounted) return;
      setState(() {
        _erreur = 'Création impossible : réessayez.';
        _envoi = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle tournée')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _envoi || _agents.isEmpty ? null : _enregistrer,
          icon: _envoi
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_envoi ? 'Enregistrement…' : 'Créer la tournée'),
        ),
      ),
      body: _chargement
          ? const Center(child: ModernLoader(legende: 'Chargement…'))
          : _corps(),
    );
  }

  Widget _corps() {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: <Widget>[
        if (_agents.isEmpty)
          const _Avertissement(
            message: 'Aucun agent disponible. Créez d\'abord un collaborateur '
                '(Paramètres → Collaborateurs).',
          ),
        if (_erreur != null) ...<Widget>[
          _Avertissement(message: _erreur!, erreur: true),
          const SizedBox(height: 12),
        ],
        AppDropdownField<String>(
          label: 'Agent',
          value: _agentId,
          prefixIcon: Icons.person_rounded,
          items: _agents
              .map((AgentDistribution a) => DropdownMenuItem<String>(
                    value: a.id,
                    child: Text(a.libelle, overflow: TextOverflow.ellipsis),
                  ))
              .toList(growable: false),
          onChanged: (String? v) => setState(() => _agentId = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _choisirDate,
                icon: const Icon(Icons.event_rounded),
                label: Text(
                  '${_date.day.toString().padLeft(2, '0')}/'
                  '${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _zoneController,
                decoration: const InputDecoration(
                  labelText: 'Zone (facultatif)',
                  prefixIcon: Icon(Icons.place_rounded),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Note (facultatif)',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _objectifController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Objectif de vente',
                  hintText: 'facultatif',
                  prefixIcon: Icon(Icons.flag_rounded),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _commissionController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Commission (%)',
                  hintText: 'ex. 5',
                  prefixIcon: Icon(Icons.percent_rounded),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'La commission est calculée sur les ventes réellement encaissées, '
          'pas sur la dotation. Elle est figée à la clôture de la tournée.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Text('Produits attribués', style: theme.textTheme.titleMedium),
            const Spacer(),
            Text(
              '${_lignes.length} article(s) • ${formatQuantite(_quantiteTotale)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_lignes.isNotEmpty) _selection(),
        const SizedBox(height: 8),
        TextField(
          controller: _rechercheController,
          decoration: const InputDecoration(
            hintText: 'Rechercher un article…',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 8),
        ..._articlesFiltres.map((Article a) {
          final double? quantite = _lignes[a.id];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(a.nom, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              <String>[
                formatMontant(a.prixVente),
                a.stockIllimite
                    ? 'stock ∞'
                    : 'stock ${formatQuantite(a.quantite)}',
                if (a.uniteMesure.isNotEmpty) a.uniteMesure,
              ].join(' • '),
            ),
            trailing: quantite == null
                ? IconButton(
                    tooltip: 'Attribuer',
                    onPressed: () => _ajouter(a),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  )
                : Chip(
                    label: Text(formatQuantite(quantite)),
                    onDeleted: () => setState(() => _lignes.remove(a.id)),
                  ),
            onTap: () => _ajouter(a),
          );
        }),
      ],
    );
  }

  Widget _selection() {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: _lignes.entries.map((MapEntry<int, double> e) {
          final Article? article = _articles.cast<Article?>().firstWhere(
                (Article? a) => a?.id == e.key,
                orElse: () => null,
              );
          return Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  article?.nom ?? 'Article ${e.key}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${formatQuantite(e.value)} ${article?.uniteMesure ?? ''}',
                style: theme.textTheme.bodySmall,
              ),
              IconButton(
                onPressed: () => setState(() => _lignes.remove(e.key)),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          );
        }).toList(growable: false),
      ),
    );
  }

  /// Lit un montant saisi (« 1 500,5 » → 1500.5). Vide ou invalide → null.
  static double? _nombreSaisi(String brut) {
    final String propre = brut.replaceAll(' ', '').replaceAll(',', '.').trim();
    if (propre.isEmpty) return null;
    final double? valeur = double.tryParse(propre);
    if (valeur == null || valeur < 0) return null;
    return valeur;
  }

  Future<void> _choisirDate() async {
    final DateTime? choisie = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (choisie != null) setState(() => _date = choisie);
  }
}

class _Avertissement extends StatelessWidget {
  const _Avertissement({required this.message, this.erreur = false});

  final String message;
  final bool erreur;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fond = erreur
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.tertiaryContainer;
    final Color texte = erreur
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onTertiaryContainer;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(erreur ? Icons.error_outline : Icons.info_outline,
              size: 18, color: texte),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: texte))),
        ],
      ),
    );
  }
}
