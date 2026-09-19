// lib/pages/salles_page.dart
//
// 🎉 MODULE 16 (phase C4) — SALLE DES FÊTES : GESTION DES SALLES.
//
// Liste des salles (nom, capacité, prix/jour), création / modification,
// activation / désactivation et suppression. Une salle qui a des événements
// ne peut pas être supprimée : la désactiver à la place.
//
// Accessible quand le module `salles` est actif (carte d'accueil) ; les
// droits fins (`salles/voir`, `créer`, `modifier`, `supprimer`) sont
// revérifiés par la RPC serveur.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/salle.dart';
import 'package:biashara_yangu/services/salle_fete_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class SallesPage extends StatefulWidget {
  const SallesPage({super.key});

  @override
  State<SallesPage> createState() => _SallesPageState();
}

class _SallesPageState extends State<SallesPage> {
  final SalleFeteService _service = SalleFeteService.instance;

  List<Salle> _salles = const <Salle>[];
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
    List<Salle> salles = const <Salle>[];

    try {
      salles = await _service.listerSalles();
    } on SalleFeteServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('SallesPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des salles.';
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
      _salles = salles;
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

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirForm({Salle? salle}) async {
    final bool? ok = salle == null
        ? await context.push<bool>('/main/evenements/salles/new')
        : await context.push<bool>(
            '/main/evenements/salles/${salle.id}/edit',
            extra: salle,
          );
    if (ok == true) _charger(silencieux: true);
  }

  Future<void> _basculerActif(Salle salle) async {
    try {
      await _service.enregistrerSalle(
        id: salle.id,
        nom: salle.nom,
        capacite: salle.capacite,
        prixJour: salle.prixJour,
        description: salle.description,
        equipements: salle.equipements,
        actif: !salle.actif,
      );
      _message(salle.actif
          ? 'Salle « ${salle.nom} » désactivée.'
          : 'Salle « ${salle.nom} » réactivée.');
      _charger(silencieux: true);
    } on SalleFeteServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _supprimer(Salle salle) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Supprimer la salle « ${salle.nom} » ?'),
        content: const Text(
          'La salle disparaîtra de la liste. Si elle a des événements, '
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
      await _service.supprimerSalle(salle.id);
      _message('Salle « ${salle.nom} » supprimée.');
      _charger(silencieux: true);
    } on SalleFeteServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salles'),
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
        label: const Text('Nouvelle salle'),
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

    if (_salles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.meeting_room_outlined,
                  size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              const Text(
                'Aucune salle enregistrée.\n'
                'Ajoutez vos salles pour gérer les événements (mariages, '
                'anniversaires, réunions…).',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: _salles.length,
      itemBuilder: (BuildContext context, int index) =>
          _carte(_salles[index]),
    );
  }

  Widget _carte(Salle salle) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _ouvrirForm(salle: salle),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF9333EA).withValues(alpha: 0.14),
                child: const Icon(Icons.meeting_room_rounded,
                    color: Color(0xFF9333EA)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      salle.nom,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${salle.capacite} pers. • '
                      '${formatMontant(salle.prixJour)} / jour'
                      '${salle.actif ? '' : ' • Désactivée'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if ((salle.equipements ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        salle.equipements!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontStyle: FontStyle.italic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (String valeur) {
                  switch (valeur) {
                    case 'modifier':
                      _ouvrirForm(salle: salle);
                    case 'actif':
                      _basculerActif(salle);
                    case 'supprimer':
                      _supprimer(salle);
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
                  PopupMenuItem<String>(
                    value: 'actif',
                    child: ListTile(
                      leading: Icon(salle.actif
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      title: Text(salle.actif ? 'Désactiver' : 'Réactiver'),
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
