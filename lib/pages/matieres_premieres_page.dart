// lib/pages/matieres_premieres_page.dart
//
// 🥖 MODULE 16 (phase C5) — BOULANGERIE : MATIÈRES PREMIÈRES.
//
// Liste des matières (farine, levure, sucre…), alertes de stock,
// approvisionnement (entrée + prix), ajustement d'inventaire, création /
// modification et suppression (désactiver si déjà consommée).
//
// Accessible quand le module `production` est actif ; les droits fins sont
// revérifiés par les RPC serveur.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/matiere_premiere.dart';
import 'package:biashara_yangu/models/production.dart';
import 'package:biashara_yangu/services/production_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class MatieresPremieresPage extends StatefulWidget {
  const MatieresPremieresPage({super.key});

  @override
  State<MatieresPremieresPage> createState() => _MatieresPremieresPageState();
}

class _MatieresPremieresPageState extends State<MatieresPremieresPage> {
  final ProductionService _service = ProductionService.instance;

  List<MatierePremiere> _matieres = const <MatierePremiere>[];
  bool _seulementAlertes = false;

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
    List<MatierePremiere> matieres = const <MatierePremiere>[];

    try {
      matieres = await _service.listerMatieres();
    } on ProductionServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('MatieresPremieresPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des matières.';
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
      _matieres = matieres;
      _erreur = null;
      _chargement = false;
    });
  }

  int get _nbAlertes =>
      _matieres.where((MatierePremiere m) => m.enAlerte).length;

  List<MatierePremiere> get _affichees => _seulementAlertes
      ? _matieres.where((MatierePremiere m) => m.enAlerte).toList(growable: false)
      : _matieres;

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

  Future<void> _ouvrirForm({MatierePremiere? matiere}) async {
    final bool? ok = matiere == null
        ? await context.push<bool>('/main/production/matieres/new')
        : await context.push<bool>(
            '/main/production/matieres/${matiere.id}/edit',
            extra: matiere,
          );
    if (ok == true) _charger(silencieux: true);
  }

  Future<void> _approvisionner(MatierePremiere matiere) async {
    final TextEditingController quantiteCtrl = TextEditingController();
    final TextEditingController prixCtrl = TextEditingController(
      text: matiere.prixUnitaire == 0
          ? ''
          : Production.nombre(matiere.prixUnitaire),
    );

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Approvisionner — ${matiere.nom}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Stock actuel : '
              '${Production.nombre(matiere.stock)} ${matiere.unite}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantiteCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantité reçue',
                suffixText: matiere.unite,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: prixCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Prix par ${matiere.unite} (facultatif)',
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
            child: const Text('Ajouter au stock'),
          ),
        ],
      ),
    );

    if (valide != true) return;

    final double quantite = _parse(quantiteCtrl.text);
    if (quantite <= 0) {
      _message('La quantité doit être supérieure à zéro.', erreur: true);
      return;
    }
    final double prix = _parse(prixCtrl.text);

    try {
      final MatierePremiere maj = await _service.approvisionnerMatiere(
        id: matiere.id,
        quantite: quantite,
        prixUnitaire: prix > 0 ? prix : null,
      );
      _message('${maj.nom} : +${Production.nombre(quantite)} ${maj.unite} '
          '(stock : ${Production.nombre(maj.stock)}).');
      _charger(silencieux: true);
    } on ProductionServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _ajuster(MatierePremiere matiere) async {
    final TextEditingController stockCtrl = TextEditingController(
      text: Production.nombre(matiere.stock),
    );
    final TextEditingController raisonCtrl = TextEditingController();

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Inventaire — ${matiere.nom}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Stock enregistré : '
              '${Production.nombre(matiere.stock)} ${matiere.unite}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: stockCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Stock réellement constaté',
                suffixText: matiere.unite,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: raisonCtrl,
              decoration: const InputDecoration(
                labelText: 'Raison (obligatoire)',
                hintText: 'Pesée, casse, erreur de saisie…',
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
            child: const Text('Corriger'),
          ),
        ],
      ),
    );

    if (valide != true) return;

    final double stock = _parse(stockCtrl.text);
    if (stock < 0) {
      _message('Le stock constaté ne peut pas être négatif.', erreur: true);
      return;
    }
    final String raison = raisonCtrl.text.trim();
    if (raison.length < 3) {
      _message('Indiquez la raison de l\'ajustement.', erreur: true);
      return;
    }

    try {
      final MatierePremiere maj = await _service.ajusterMatiere(
        id: matiere.id,
        stockReel: stock,
        raison: raison,
      );
      _message('${maj.nom} : stock corrigé à '
          '${Production.nombre(maj.stock)} ${maj.unite}.');
      _charger(silencieux: true);
    } on ProductionServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _basculerActif(MatierePremiere matiere) async {
    try {
      await _service.enregistrerMatiere(
        id: matiere.id,
        nom: matiere.nom,
        unite: matiere.unite,
        seuilAlerte: matiere.seuilAlerte,
        prixUnitaire: matiere.prixUnitaire,
        actif: !matiere.actif,
      );
      _message(matiere.actif
          ? '${matiere.nom} désactivée.'
          : '${matiere.nom} réactivée.');
      _charger(silencieux: true);
    } on ProductionServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _supprimer(MatierePremiere matiere) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Supprimer « ${matiere.nom} » ?'),
        content: const Text(
          'La matière disparaîtra de la liste. Si des productions l\'ont '
          'consommée, désactivez-la plutôt que de la supprimer.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirme != true) return;

    try {
      await _service.supprimerMatiere(matiere.id);
      _message('${matiere.nom} supprimée.');
      _charger(silencieux: true);
    } on ProductionServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  static double _parse(String texte) {
    return double.tryParse(texte.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matières premières'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Guide d\'utilisation',
            onPressed: () => context.pushNamed('guide-utilisation'),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ouvrirForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle matière'),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur()
              : _liste(),
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

  Widget _liste() {
    final ThemeData theme = Theme.of(context);
    final List<MatierePremiere> affichees = _affichees;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: Text('Toutes (${_matieres.length})'),
                  selected: !_seulementAlertes,
                  onSelected: (_) => setState(() => _seulementAlertes = false),
                ),
                ChoiceChip(
                  label: Text('Alertes ($_nbAlertes)'),
                  selected: _seulementAlertes,
                  onSelected: (_) => setState(() => _seulementAlertes = true),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: affichees.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.science_outlined,
                            size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          _matieres.isEmpty
                              ? 'Aucune matière première enregistrée.\n'
                                  'Ajoutez la farine, la levure… pour suivre '
                                  'vos productions.'
                              : 'Aucune matière en alerte : tout va bien ✅',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: affichees.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _carte(affichees[index]),
                ),
        ),
      ],
    );
  }

  Widget _carte(MatierePremiere matiere) {
    final ThemeData theme = Theme.of(context);
    final Color couleur =
        matiere.enAlerte ? const Color(0xFFDC2626) : const Color(0xFF16A34A);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _ouvrirForm(matiere: matiere),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                radius: 22,
                backgroundColor: couleur.withValues(alpha: 0.14),
                child: Icon(
                  matiere.enAlerte
                      ? Icons.warning_amber_rounded
                      : Icons.science_rounded,
                  color: couleur,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      matiere.nom,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Stock : ${Production.nombre(matiere.stock)} '
                      '${matiere.unite} • Seuil : '
                      '${Production.nombre(matiere.seuilAlerte)} '
                      '${matiere.unite}'
                      '${matiere.actif ? '' : ' • Désactivée'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (matiere.enAlerte)
                      Text(
                        '⚠️ Stock bas — pensez à réapprovisionner',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: const Color(0xFFDC2626)),
                      )
                    else if (matiere.prixUnitaire > 0)
                      Text(
                        'Prix : ${formatMontant(matiere.prixUnitaire)} / '
                        '${matiere.unite}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (String valeur) {
                  switch (valeur) {
                    case 'modifier':
                      _ouvrirForm(matiere: matiere);
                    case 'appro':
                      _approvisionner(matiere);
                    case 'ajuster':
                      _ajuster(matiere);
                    case 'actif':
                      _basculerActif(matiere);
                    case 'supprimer':
                      _supprimer(matiere);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'modifier',
                    child: ListTile(
                      leading: Icon(Icons.edit_rounded),
                      title: Text('Modifier'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'appro',
                    child: ListTile(
                      leading: Icon(Icons.add_box_rounded),
                      title: Text('Approvisionner'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'ajuster',
                    child: ListTile(
                      leading: Icon(Icons.scale_rounded),
                      title: Text('Inventaire (ajuster)'),
                      dense: true,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'actif',
                    child: ListTile(
                      leading: Icon(matiere.actif
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      title: Text(matiere.actif ? 'Désactiver' : 'Réactiver'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'supprimer',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('Supprimer'),
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
