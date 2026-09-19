// lib/pages/tables_salle_page.dart
//
// 🍽️ MODULE 16 (phase C3) — RESTAURANT : PLAN DE SALLE (TABLES).
//
// Liste des tables avec leur statut ; chaque table ouvre ses actions :
// prendre une commande, réserver, libérer, modifier, désactiver, supprimer.
// Le serveur revérifie systématiquement les droits (`tables/*`,
// `commandes/creer`).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/commande.dart';
import 'package:biashara_yangu/models/table_salle.dart';
import 'package:biashara_yangu/services/restaurant_service.dart';
import 'package:biashara_yangu/widgets/statut_restaurant_chips.dart';

class TablesSallePage extends StatefulWidget {
  const TablesSallePage({super.key});

  @override
  State<TablesSallePage> createState() => _TablesSallePageState();
}

class _TablesSallePageState extends State<TablesSallePage> {
  final RestaurantService _service = RestaurantService.instance;

  List<TableSalle> _tables = const <TableSalle>[];
  TableStatut? _filtre;

  bool _chargement = true;
  String? _erreur;
  bool _actionEnCours = false;

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
    List<TableSalle> tables = const <TableSalle>[];

    try {
      tables = await _service.listerTables();
    } on RestaurantServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('TablesSallePage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des tables.';
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
      _tables = tables;
      _erreur = null;
      _chargement = false;
    });
  }

  int _compter(TableStatut? statut) => statut == null
      ? _tables.length
      : _tables.where((TableSalle t) => t.statut == statut).length;

  List<TableSalle> get _filtrees => _filtre == null
      ? _tables
      : _tables.where((TableSalle t) => t.statut == _filtre).toList();

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

  Future<void> _actions(TableSalle table) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.add_shopping_cart_rounded),
              title: const Text('Prendre une commande'),
              subtitle: table.statut == TableStatut.occupee
                  ? const Text('Table déjà occupée par une commande')
                  : null,
              enabled: table.statut != TableStatut.occupee,
              onTap: () => Navigator.of(context).pop('commande'),
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('Changer le statut'),
              onTap: () => Navigator.of(context).pop('statut'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Modifier'),
              onTap: () => Navigator.of(context).pop('modifier'),
            ),
            ListTile(
              leading: Icon(table.actif
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded),
              title: Text(table.actif ? 'Désactiver' : 'Réactiver'),
              onTap: () => Navigator.of(context).pop('actif'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Supprimer'),
              onTap: () => Navigator.of(context).pop('supprimer'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'commande':
        await _prendreCommande(table);
      case 'statut':
        await _changerStatut(table);
      case 'modifier':
        await _ouvrirForm(table: table);
      case 'actif':
        await _basculerActif(table);
      case 'supprimer':
        await _supprimer(table);
    }
  }

  Future<void> _prendreCommande(TableSalle table) async {
    final TextEditingController clientCtrl = TextEditingController();
    final TextEditingController personnesCtrl =
        TextEditingController(text: '1');

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Commande — ${table.designation}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: clientCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Client (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: personnesCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Personnes',
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
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    );

    if (confirme != true || !mounted) {
      clientCtrl.dispose();
      personnesCtrl.dispose();
      return;
    }

    final String client = clientCtrl.text.trim();
    final int personnes = int.tryParse(personnesCtrl.text.trim()) ?? 1;
    clientCtrl.dispose();
    personnesCtrl.dispose();

    setState(() => _actionEnCours = true);
    try {
      final Commande commande = await _service.creerCommande(
        tableId: table.id,
        clientNom: client.isEmpty ? null : client,
        nbPersonnes: personnes < 1 ? 1 : personnes,
      );
      if (!mounted) return;
      await context.push<Object?>(
        '/main/restaurant/commandes/${commande.id}',
        extra: commande,
      );
      _charger(silencieux: true);
    } on RestaurantServiceException catch (e) {
      if (mounted) _message(e.message, erreur: true);
    } catch (e) {
      if (mounted) _message('Erreur inattendue : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _changerStatut(TableSalle table) async {
    final TableStatut? choix = await showDialog<TableStatut>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: Text('Statut — ${table.designation}'),
        children: TableStatut.values
            .map(
              (TableStatut statut) => ListTile(
                leading: Icon(
                  StatutTableChip.icone(statut),
                  color: StatutTableChip.couleur(statut),
                ),
                title: Text(statut.libelle),
                trailing: statut == table.statut
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(statut),
              ),
            )
            .toList(),
      ),
    );

    if (choix == null || choix == table.statut) return;

    try {
      await _service.changerStatutTable(table.id, choix);
      _message('${table.designation} : ${choix.libelle.toLowerCase()}.');
      _charger(silencieux: true);
    } on RestaurantServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _ouvrirForm({TableSalle? table}) async {
    final bool? ok = table == null
        ? await context.push<bool>('/main/restaurant/tables/new')
        : await context.push<bool>(
            '/main/restaurant/tables/${table.id}/edit',
            extra: table,
          );
    if (ok == true) _charger(silencieux: true);
  }

  Future<void> _basculerActif(TableSalle table) async {
    try {
      await _service.enregistrerTable(
        id: table.id,
        numero: table.numero,
        zone: table.zone,
        places: table.places,
        actif: !table.actif,
      );
      _message(table.actif
          ? '${table.designation} désactivée.'
          : '${table.designation} réactivée.');
      _charger(silencieux: true);
    } on RestaurantServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _supprimer(TableSalle table) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Supprimer ${table.designation} ?'),
        content: const Text(
          'La table disparaîtra du plan de salle. Si elle a des commandes, '
          'désactivez-la plutôt que de la supprimer.',
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
      await _service.supprimerTable(table.id);
      _message('${table.designation} supprimée.');
      _charger(silencieux: true);
    } on RestaurantServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tables de salle')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _actionEnCours ? null : () => _ouvrirForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle table'),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur()
              : Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            _puceFiltre(null, 'Toutes'),
                            for (final TableStatut statut in TableStatut.values)
                              _puceFiltre(statut, statut.libelle),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _filtrees.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _tables.isEmpty
                                      ? 'Aucune table enregistrée.\n'
                                          'Ajoutez vos tables pour prendre les commandes.'
                                      : 'Aucune table pour ce filtre.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : GridView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 8, 12, 96),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 1.45,
                              ),
                              itemCount: _filtrees.length,
                              itemBuilder:
                                  (BuildContext context, int index) =>
                                      _carte(_filtrees[index]),
                            ),
                    ),
                  ],
                ),
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

  Widget _puceFiltre(TableStatut? statut, String libelle) {
    return ChoiceChip(
      label: Text('$libelle (${_compter(statut)})'),
      selected: _filtre == statut,
      onSelected: (_) => setState(() => _filtre = statut),
    );
  }

  Widget _carte(TableSalle table) {
    final ThemeData theme = Theme.of(context);
    final Color couleur = StatutTableChip.couleur(table.statut);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _actionEnCours ? null : () => _actions(table),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: couleur.withValues(alpha: 0.14),
                    child: Icon(StatutTableChip.icone(table.statut),
                        size: 18, color: couleur),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Table ${table.numero}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${table.zone.isEmpty ? 'Salle' : table.zone} • '
                '${table.places} places${table.actif ? '' : ' • Désactivée'}',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              StatutTableChip(statut: table.statut, compact: true),
            ],
          ),
        ),
      ),
    );
  }
}
