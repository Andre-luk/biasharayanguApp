// lib/pages/commandes_page.dart
//
// 🍽️ MODULE 16 (phase C3) — RESTAURANT : COMMANDES.
//
// Liste filtrable des commandes (actives → clôturées), ouverture d'une
// nouvelle commande sur une table libre, suivi complet dans le détail
// (lignes, envoi cuisine, service, encaissement via la caisse).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/commande.dart';
import 'package:biashara_yangu/models/table_salle.dart';
import 'package:biashara_yangu/services/restaurant_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/statut_restaurant_chips.dart';

/// Filtres rapides de la liste.
enum _FiltreCommandes {
  actives('Actives'),
  enCuisine('En cuisine'),
  pretes('Prêtes'),
  servies('Servies'),
  cloturees('Clôturées'),
  toutes('Toutes');

  const _FiltreCommandes(this.libelle);

  final String libelle;

  bool accepte(Commande c) {
    switch (this) {
      case _FiltreCommandes.actives:
        return c.statut.estActive;
      case _FiltreCommandes.enCuisine:
        return c.statut == StatutCommande.envoyee ||
            c.statut == StatutCommande.enPreparation;
      case _FiltreCommandes.pretes:
        return c.statut == StatutCommande.prete;
      case _FiltreCommandes.servies:
        return c.statut == StatutCommande.servie;
      case _FiltreCommandes.cloturees:
        return !c.statut.estActive;
      case _FiltreCommandes.toutes:
        return true;
    }
  }
}

class CommandesPage extends StatefulWidget {
  const CommandesPage({super.key});

  @override
  State<CommandesPage> createState() => _CommandesPageState();
}

class _CommandesPageState extends State<CommandesPage> {
  final RestaurantService _service = RestaurantService.instance;

  List<Commande> _commandes = const <Commande>[];
  _FiltreCommandes _filtre = _FiltreCommandes.actives;

  bool _chargement = true;
  String? _erreur;
  bool _creationEnCours = false;

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
    List<Commande> commandes = const <Commande>[];

    try {
      commandes = await _service.listerCommandes();
    } on RestaurantServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('CommandesPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des commandes.';
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
      _commandes = commandes;
      _erreur = null;
      _chargement = false;
    });
  }

  int _compter(_FiltreCommandes filtre) =>
      _commandes.where(filtre.accepte).length;

  List<Commande> get _filtrees =>
      _commandes.where(_filtre.accepte).toList(growable: false);

  void _message(String texte, {bool erreur = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _ouvrirDetail(Commande commande) async {
    await context.push<Object?>(
      '/main/restaurant/commandes/${commande.id}',
      extra: commande,
    );
    _charger(silencieux: true);
  }

  Future<void> _nouvelleCommande() async {
    setState(() => _creationEnCours = true);

    List<TableSalle> tables = const <TableSalle>[];
    try {
      tables = await _service.listerTables();
    } on RestaurantServiceException catch (e) {
      if (mounted) {
        setState(() => _creationEnCours = false);
        _message(e.message, erreur: true);
      }
      return;
    }

    if (!mounted) return;
    setState(() => _creationEnCours = false);

    final List<TableSalle> libres = tables
        .where((TableSalle t) => t.actif && t.statut != TableStatut.occupee)
        .toList(growable: false);

    if (libres.isEmpty) {
      _message('Aucune table disponible : libérez une table ou ajoutez-en une.',
          erreur: true);
      return;
    }

    TableSalle? choisie;
    final TextEditingController clientCtrl = TextEditingController();

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          title: const Text('Nouvelle commande'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppDropdownField<TableSalle>(
                label: 'Table *',
                value: choisie,
                hint: 'Choisir une table',
                prefixIcon: Icons.table_restaurant_rounded,
                items: libres
                    .map(
                      (TableSalle table) => DropdownMenuItem<TableSalle>(
                        value: table,
                        child: Text(
                          '${table.designation} (${table.places} places)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (TableSalle? table) =>
                    setDialogState(() => choisie = table),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: clientCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Client (facultatif)',
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
      ),
    );

    if (confirme != true || choisie == null || !mounted) {
      clientCtrl.dispose();
      return;
    }

    final String client = clientCtrl.text.trim();
    clientCtrl.dispose();

    try {
      final Commande commande = await _service.creerCommande(
        tableId: choisie!.id,
        clientNom: client.isEmpty ? null : client,
      );
      if (!mounted) return;
      await _ouvrirDetail(commande);
    } on RestaurantServiceException catch (e) {
      if (mounted) _message(e.message, erreur: true);
    } catch (e) {
      if (mounted) _message('Erreur inattendue : $e', erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commandes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creationEnCours ? null : _nouvelleCommande,
        icon: _creationEnCours
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_rounded),
        label: const Text('Nouvelle commande'),
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
                          children: _FiltreCommandes.values
                              .map(
                                (_FiltreCommandes filtre) => ChoiceChip(
                                  label: Text(
                                      '${filtre.libelle} (${_compter(filtre)})'),
                                  selected: _filtre == filtre,
                                  onSelected: (_) =>
                                      setState(() => _filtre = filtre),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _filtrees.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Aucune commande pour ce filtre.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 8, 12, 96),
                              itemCount: _filtrees.length,
                              itemBuilder: (BuildContext context, int index) =>
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

  Widget _carte(Commande commande) {
    final ThemeData theme = Theme.of(context);
    final Color couleur = StatutCommandeChip.couleur(commande.statut);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _ouvrirDetail(commande),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: couleur.withValues(alpha: 0.14),
          child: Icon(StatutCommandeChip.icone(commande.statut),
              size: 20, color: couleur),
        ),
        title: Text(
          '${commande.tableNumero.isEmpty ? 'Commande' : 'Table ${commande.tableNumero}'}'
          '${commande.numero == null ? '' : ' • ${commande.numero}'}',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              commande.resume,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              '${formatMontant(commande.montantTotal)} • '
              '${commande.nbArticles} article${commande.nbArticles > 1 ? 's' : ''}'
              '${commande.clientNom == null ? '' : ' • ${commande.clientNom}'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        trailing: StatutCommandeChip(statut: commande.statut, compact: true),
      ),
    );
  }
}
