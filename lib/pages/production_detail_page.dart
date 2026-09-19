// lib/pages/production_detail_page.dart
//
// 🥖 MODULE 16 (phase C5) — BOULANGERIE : DOSSIER DE PRODUCTION.
//
// Tout se pilote ici : matières consommées (déduites du stock), clôture
// (le produit fini entre en stock + coût de revient) et annulation
// (matières rendues au stock).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/matiere_premiere.dart';
import 'package:biashara_yangu/models/production.dart';
import 'package:biashara_yangu/services/production_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/statut_production_chip.dart';

class ProductionDetailPage extends StatefulWidget {
  const ProductionDetailPage({
    super.key,
    required this.productionId,
    this.production,
  });

  final String productionId;

  /// Production déjà connue (évite un premier écran vide).
  final Production? production;

  @override
  State<ProductionDetailPage> createState() => _ProductionDetailPageState();
}

class _ProductionDetailPageState extends State<ProductionDetailPage> {
  final ProductionService _service = ProductionService.instance;

  Production? _production;
  List<MatierePremiere> _matieres = const <MatierePremiere>[];

  bool _chargement = true;
  bool _actionEnCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _production = widget.production;
    _charger();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux) {
      setState(() {
        _chargement = _production == null;
        _erreur = null;
      });
    }

    String? messageErreur;
    Production? production;
    List<MatierePremiere> matieres = _matieres;

    try {
      production = await _service.chargerProduction(widget.productionId);
      try {
        matieres = await _service.listerMatieres();
      } catch (e) {
        debugPrint('ProductionDetailPage matières (ignoré) : $e');
      }
    } on ProductionServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ProductionDetailPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement du dossier.';
    }

    if (!mounted) return;

    if (messageErreur != null) {
      if (silencieux && _production != null) {
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
      if (production != null) _production = production;
      _matieres = matieres;
      _erreur = production == null
          ? 'Production introuvable : elle a peut-être été supprimée.'
          : null;
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

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _executer(Future<Production> Function() action,
      {required String succes}) async {
    setState(() => _actionEnCours = true);
    try {
      await action();
      if (!mounted) return;
      _message(succes);
      await _charger(silencieux: true);
    } on ProductionServiceException catch (e) {
      if (mounted) _message(e.message, erreur: true);
    } catch (e) {
      if (mounted) _message('Erreur inattendue : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _ajouterMatiere() async {
    final Production? production = _production;
    if (production == null) return;

    if (_matieres.isEmpty) {
      _message(
          'Aucune matière première : créez-en d\'abord (bouton Sciences).',
          erreur: true);
      return;
    }

    MatierePremiere matiere = _matieres.first;
    final TextEditingController quantiteCtrl = TextEditingController();

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setEtat) => AlertDialog(
          title: const Text('Matière consommée'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppDropdownField<MatierePremiere>(
                label: 'Matière',
                value: matiere,
                items: _matieres
                    .map(
                      (MatierePremiere m) =>
                          DropdownMenuItem<MatierePremiere>(
                        value: m,
                        child: Text(
                          '${m.nom} — stock : '
                          '${Production.nombre(m.stock)} ${m.unite}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (MatierePremiere? valeur) {
                  if (valeur != null) setEtat(() => matiere = valeur);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: quantiteCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantité utilisée',
                  suffixText: matiere.unite,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Consommer'),
            ),
          ],
        ),
      ),
    );

    if (valide != true) return;

    final double quantite = _parse(quantiteCtrl.text);
    if (quantite <= 0) {
      _message('La quantité doit être supérieure à zéro.', erreur: true);
      return;
    }

    await _executer(
      () => _service.consommer(
        productionId: production.id,
        matiereId: matiere.id,
        quantite: quantite,
      ),
      succes: '${matiere.nom} : '
          '${Production.nombre(quantite)} ${matiere.unite} consommée'
          '${matiere.unite.endsWith('s') ? 's' : ''}.',
    );
  }

  Future<void> _retirerConsommation(ConsommationProduction ligne) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Retirer « ${ligne.libelle} » ?'),
        content: Text(
            'La matière sera rendue au stock (${Production.nombre(ligne.quantite)} ${ligne.unite}).'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );

    if (confirme != true) return;

    await _executer(
      () => _service.supprimerConsommation(ligne.id),
      succes: 'Matière rendue au stock.',
    );
  }

  Future<void> _terminer() async {
    final Production? production = _production;
    if (production == null) return;

    final TextEditingController quantiteCtrl = TextEditingController(
      text: Production.nombre(production.quantitePrevue),
    );

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clôturer la production'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'La quantité réellement produite entre EN STOCK et le coût '
              'de revient est calculé.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantiteCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantité réellement produite',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );

    if (valide != true) return;

    final double reelle = _parse(quantiteCtrl.text);
    if (reelle < 0) {
      _message('La quantité produite ne peut pas être négative.', erreur: true);
      return;
    }

    await _executer(
      () => _service.terminer(id: production.id, quantiteReelle: reelle),
      succes: 'Production clôturée : '
          '${Production.nombre(reelle)} en stock.',
    );
  }

  Future<void> _annuler() async {
    final Production? production = _production;
    if (production == null) return;

    final TextEditingController motifCtrl = TextEditingController();
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Annuler la production ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Les matières déjà consommées seront rendues au stock. '
              'La production restera dans l\'historique.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motifCtrl,
              decoration: const InputDecoration(
                labelText: 'Motif (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Annuler la production'),
          ),
        ],
      ),
    );

    if (confirme != true) return;

    final String motif = motifCtrl.text.trim();
    await _executer(
      () => _service.annuler(production.id,
          motif: motif.isEmpty ? null : motif),
      succes: 'Production annulée — matières rendues au stock.',
    );
  }

  static double _parse(String texte) {
    return double.tryParse(texte.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Production? production = _production;

    return Scaffold(
      appBar: AppBar(
        title: Text(production?.produitNom.isEmpty ?? true
            ? 'Dossier de production'
            : production!.produitNom),
        actions: <Widget>[
          IconButton(
            tooltip: 'Guide d\'utilisation',
            onPressed: () => context.pushNamed('guide-utilisation'),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur()
              : _dossier(production!),
    );
  }

  Widget _vueErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 48),
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

  Widget _dossier(Production production) {
    final ThemeData theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => _charger(silencieux: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  production.numero ?? 'Production',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              StatutProductionChip(statut: production.statut),
            ],
          ),
          const SizedBox(height: 10),
          _carteFiche(production, theme),
          const SizedBox(height: 14),
          _sectionMatieres(production, theme),
          const SizedBox(height: 14),
          _sectionActions(production, theme),
          if ((production.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            _carteTexte('Note', production.note!, theme, Icons.notes_rounded),
          ],
          if ((production.motifAnnulation ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            _carteTexte('Motif d\'annulation', production.motifAnnulation!,
                theme, Icons.cancel_rounded,
                rouge: true),
          ],
        ],
      ),
    );
  }

  Widget _carteFiche(Production production, ThemeData theme) {
    Widget ligne(String libelle, String valeur,
        {Color? couleur, bool gras = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(libelle, style: theme.textTheme.bodyMedium)),
            Text(
              valeur,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: gras ? FontWeight.w800 : FontWeight.w600,
                color: couleur,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Fabrication',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ligne('Produit fini',
                production.produitNom.isEmpty ? '—' : production.produitNom),
            ligne('Quantité prévue',
                Production.nombre(production.quantitePrevue)),
            if (production.statut != StatutProduction.enCours)
              ligne('Quantité produite',
                  Production.nombre(production.quantiteReelle)),
            if (production.pertesAffichees > 0)
              ligne('Pertes', Production.nombre(production.pertesAffichees),
                  couleur: const Color(0xFFDC2626)),
            if (production.surplus > 0)
              ligne('Surplus', Production.nombre(production.surplus),
                  couleur: const Color(0xFF16A34A)),
            const Divider(height: 16),
            ligne('Coût matières', formatMontant(production.coutMatieres),
                gras: true),
            if (production.statut == StatutProduction.terminee)
              ligne('Coût de revient unitaire',
                  formatMontant(production.coutUnitaire),
                  couleur: const Color(0xFF2563EB), gras: true),
            if (production.statut == StatutProduction.terminee)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '✅ Le produit fini est entré en stock automatiquement.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFF16A34A)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionMatieres(Production production, ThemeData theme) {
    final bool modifiable = production.statut.estEnCours;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('Matières consommées',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (modifiable)
                  TextButton.icon(
                    onPressed: _actionEnCours ? null : _ajouterMatiere,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Ajouter'),
                  ),
              ],
            ),
            if (production.consommations.isEmpty)
              Text(
                modifiable
                    ? 'Aucune matière : ajoutez la farine, la levure… '
                        '(le stock se déduit automatiquement).'
                    : 'Aucune matière consommée.',
                style: theme.textTheme.bodySmall,
              )
            else
              for (final ConsommationProduction ligne in production.consommations)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(ligne.libelle),
                  subtitle: Text(
                    '${Production.nombre(ligne.quantite)} ${ligne.unite} × '
                    '${formatMontant(ligne.coutUnitaire)}'
                    '${ligne.unite.isEmpty ? '' : ' / ${ligne.unite}'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        formatMontant(ligne.total),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (modifiable)
                        IconButton(
                          tooltip: 'Retirer (rendu au stock)',
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 20),
                          onPressed: _actionEnCours
                              ? null
                              : () => _retirerConsommation(ligne),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _sectionActions(Production production, ThemeData theme) {
    if (production.statut != StatutProduction.enCours) {
      return Text(
        production.statut == StatutProduction.terminee
            ? 'Production terminée le ${_date(production.termineeLe)}.'
            : 'Production annulée.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        FilledButton.icon(
          onPressed: _actionEnCours ? null : _terminer,
          icon: const Icon(Icons.task_alt_rounded),
          label: const Text('Clôturer (entrée en stock)'),
        ),
        OutlinedButton.icon(
          onPressed: _actionEnCours ? null : _annuler,
          icon: const Icon(Icons.cancel_rounded),
          label: const Text('Annuler'),
        ),
      ],
    );
  }

  static String _date(DateTime? date) {
    if (date == null) return '—';
    final String jour = date.day.toString().padLeft(2, '0');
    final String mois = date.month.toString().padLeft(2, '0');
    final String heure = date.hour.toString().padLeft(2, '0');
    final String minute = date.minute.toString().padLeft(2, '0');
    return '$jour/$mois/${date.year} à $heure:$minute';
  }

  Widget _carteTexte(String titre, String texte, ThemeData theme,
      IconData icone,
      {bool rouge = false}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icone,
                    size: 18,
                    color: rouge
                        ? const Color(0xFFDC2626)
                        : theme.colorScheme.outline),
                const SizedBox(width: 8),
                Text(titre,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 6),
            Text(texte, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
