// lib/pages/chambres_page.dart
//
// 🏨 MODULE 16 (phase C2) — HÔTEL : GESTION DES CHAMBRES.
//
// Liste filtrable par statut, création / modification, changement de statut
// (ménage, remise en service) et suppression. La cohérence est vérifiée par
// le serveur : impossible de libérer une chambre avec un séjour en cours,
// et une chambre qui a des réservations ne peut pas être supprimée
// (la désactiver à la place).
//
// Accessible quand le module `chambres` est actif (carte d'accueil) ; les
// droits fins (`chambres/voir`, `créer`, `modifier`, `supprimer`) sont
// revérifiés par la RPC serveur.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/chambre.dart';
import 'package:biashara_yangu/services/hotel_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/statut_chambre_chip.dart';

class ChambresPage extends StatefulWidget {
  const ChambresPage({super.key});

  @override
  State<ChambresPage> createState() => _ChambresPageState();
}

class _ChambresPageState extends State<ChambresPage> {
  final HotelService _service = HotelService.instance;

  List<Chambre> _chambres = const <Chambre>[];
  ChambreStatut? _filtre;

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
    List<Chambre> chambres = const <Chambre>[];

    try {
      chambres = await _service.listerChambres();
    } on HotelServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ChambresPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des chambres.';
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
      _chambres = chambres;
      _erreur = null;
      _chargement = false;
    });
  }

  int _compter(ChambreStatut? statut) => statut == null
      ? _chambres.length
      : _chambres.where((Chambre c) => c.statut == statut).length;

  List<Chambre> get _filtrees => _filtre == null
      ? _chambres
      : _chambres
          .where((Chambre c) => c.statut == _filtre)
          .toList(growable: false);

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

  Future<void> _ouvrirForm({Chambre? chambre}) async {
    final bool? ok = chambre == null
        ? await context.push<bool>('/main/hotel/chambres/new')
        : await context.push<bool>(
            '/main/hotel/chambres/${chambre.id}/edit',
            extra: chambre,
          );
    if (ok == true) _charger(silencieux: true);
  }

  Future<void> _changerStatut(Chambre chambre) async {
    final ChambreStatut? choix = await showDialog<ChambreStatut>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: Text('Statut — chambre ${chambre.numero}'),
        children: ChambreStatut.values
            .map(
              (ChambreStatut statut) => ListTile(
                leading: Icon(
                  StatutChambreChip.icone(statut),
                  color: StatutChambreChip.couleur(statut),
                ),
                title: Text(statut.libelle),
                trailing: statut == chambre.statut
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(statut),
              ),
            )
            .toList(),
      ),
    );

    if (choix == null || choix == chambre.statut) return;

    try {
      await _service.changerStatutChambre(chambre.id, choix);
      _message('Chambre ${chambre.numero} : ${choix.libelle.toLowerCase()}.');
      _charger(silencieux: true);
    } on HotelServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _basculerActif(Chambre chambre) async {
    try {
      await _service.enregistrerChambre(
        id: chambre.id,
        numero: chambre.numero,
        typeChambre: chambre.typeChambre,
        capacite: chambre.capacite,
        prixNuit: chambre.prixNuit,
        equipements: chambre.equipements,
        actif: !chambre.actif,
      );
      _message(chambre.actif
          ? 'Chambre ${chambre.numero} désactivée.'
          : 'Chambre ${chambre.numero} réactivée.');
      _charger(silencieux: true);
    } on HotelServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _supprimer(Chambre chambre) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Supprimer la chambre ${chambre.numero} ?'),
        content: const Text(
          'La chambre disparaîtra de la liste. Si elle a des réservations, '
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
      await _service.supprimerChambre(chambre.id);
      _message('Chambre ${chambre.numero} supprimée.');
      _charger(silencieux: true);
    } on HotelServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chambres')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ouvrirForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle chambre'),
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
                _puceFiltre(null, 'Toutes'),
                for (final ChambreStatut statut in ChambreStatut.values)
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.king_bed_outlined,
                            size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          _chambres.isEmpty
                              ? 'Aucune chambre enregistrée.\n'
                                  'Ajoutez vos chambres pour gérer les réservations.'
                              : 'Aucune chambre pour ce filtre.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: _filtrees.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _carte(_filtrees[index]),
                ),
        ),
      ],
    );
  }

  Widget _puceFiltre(ChambreStatut? statut, String libelle) {
    final bool selectionne = _filtre == statut;
    return ChoiceChip(
      label: Text('$libelle (${_compter(statut)})'),
      selected: selectionne,
      onSelected: (_) => setState(() => _filtre = statut),
    );
  }

  Widget _carte(Chambre chambre) {
    final ThemeData theme = Theme.of(context);
    final Color couleur = StatutChambreChip.couleur(chambre.statut);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _ouvrirForm(chambre: chambre),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                radius: 22,
                backgroundColor: couleur.withValues(alpha: 0.14),
                child: Icon(StatutChambreChip.icone(chambre.statut),
                    color: couleur),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      chambre.designation,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${chambre.capacite} pers. • '
                      '${formatMontant(chambre.prixNuit)} / nuit'
                      '${chambre.actif ? '' : ' • Désactivée'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    StatutChambreChip(statut: chambre.statut, compact: true),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (String valeur) {
                  switch (valeur) {
                    case 'modifier':
                      _ouvrirForm(chambre: chambre);
                    case 'statut':
                      _changerStatut(chambre);
                    case 'actif':
                      _basculerActif(chambre);
                    case 'supprimer':
                      _supprimer(chambre);
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
                    value: 'statut',
                    child: ListTile(
                      leading: Icon(Icons.sync_rounded),
                      title: Text('Changer le statut'),
                      dense: true,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'actif',
                    child: ListTile(
                      leading: Icon(chambre.actif
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      title: Text(chambre.actif ? 'Désactiver' : 'Réactiver'),
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
