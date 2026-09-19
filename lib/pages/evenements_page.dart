// lib/pages/evenements_page.dart
//
// 🎉 MODULE 16 (phase C4) — SALLE DES FÊTES : CALENDRIER DES ÉVÉNEMENTS.
//
// Liste filtrable (à venir / en cours / terminés / annulés), recherche par
// titre, client, salle ou numéro, et accès au dossier complet (prestations,
// encaissements, cycle de vie).
//
// Accessible quand le module `evenements` est actif ; les droits fins sont
// revérifiés par les RPC serveur.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/evenement.dart';
import 'package:biashara_yangu/services/salle_fete_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/statut_evenement_chip.dart';

/// Filtres rapides du calendrier.
enum _FiltreEvenement {
  tous('Tous'),
  aVenir('À venir'),
  enCours('En cours'),
  termines('Terminés'),
  annules('Annulés');

  const _FiltreEvenement(this.libelle);

  final String libelle;
}

class EvenementsPage extends StatefulWidget {
  const EvenementsPage({super.key});

  @override
  State<EvenementsPage> createState() => _EvenementsPageState();
}

class _EvenementsPageState extends State<EvenementsPage> {
  final SalleFeteService _service = SalleFeteService.instance;
  final TextEditingController _rechercheCtrl = TextEditingController();

  List<Evenement> _evenements = const <Evenement>[];
  _FiltreEvenement _filtre = _FiltreEvenement.tous;

  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
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
    List<Evenement> evenements = const <Evenement>[];

    try {
      evenements = await _service.listerEvenements();
    } on SalleFeteServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('EvenementsPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des événements.';
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
      _evenements = evenements;
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
  // FILTRES & ACTIONS
  // ---------------------------------------------------------------------------

  bool _correspondFiltre(Evenement e) {
    final DateTime maintenant = DateTime.now();
    final DateTime jour = DateTime(maintenant.year, maintenant.month, maintenant.day);

    switch (_filtre) {
      case _FiltreEvenement.tous:
        return true;
      case _FiltreEvenement.aVenir:
        return e.statut.occupeLaSalle &&
            (e.dateDebut?.isAfter(jour) ?? false) &&
            !e.enCoursAujourdhui(jour);
      case _FiltreEvenement.enCours:
        return e.statut.occupeLaSalle && e.enCoursAujourdhui(jour);
      case _FiltreEvenement.termines:
        return e.statut == StatutEvenement.termine;
      case _FiltreEvenement.annules:
        return e.statut == StatutEvenement.annule;
    }
  }

  List<Evenement> get _affiches {
    final List<Evenement> filtres = _evenements
        .where(_correspondFiltre)
        .toList(growable: false);
    return SalleFeteService.filtrer(filtres, _rechercheCtrl.text);
  }

  int _compter(_FiltreEvenement filtre) {
    final _FiltreEvenement precedent = _filtre;
    _filtre = filtre;
    final int total = _evenements.where(_correspondFiltre).length;
    _filtre = precedent;
    return total;
  }

  Future<void> _ouvrirForm() async {
    final bool? ok = await context.push<bool>('/main/evenements/new');
    if (ok == true) _charger(silencieux: true);
  }

  Future<void> _ouvrirDetail(Evenement evenement) async {
    final bool? modifie = await context.push<bool>(
      '/main/evenements/${evenement.id}',
      extra: evenement,
    );
    if (modifie == true) _charger(silencieux: true);
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Événements'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Salles',
            onPressed: () => context.pushNamed('evenements-salles'),
            icon: const Icon(Icons.meeting_room_outlined),
          ),
          IconButton(
            tooltip: 'Guide d\'utilisation',
            onPressed: () => context.pushNamed('guide-utilisation'),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ouvrirForm,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvel événement'),
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
    final List<Evenement> affiches = _affiches;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _rechercheCtrl,
            decoration: InputDecoration(
              hintText: 'Rechercher (titre, client, salle, numéro)…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _rechercheCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () => setState(() => _rechercheCtrl.clear()),
                    ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final _FiltreEvenement filtre in _FiltreEvenement.values)
                  ChoiceChip(
                    label: Text('${filtre.libelle} (${_compter(filtre)})'),
                    selected: _filtre == filtre,
                    onSelected: (_) => setState(() => _filtre = filtre),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: affiches.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.celebration_outlined,
                            size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          _evenements.isEmpty
                              ? 'Aucun événement enregistré.\n'
                                  'Créez vos salles puis ajoutez vos premiers '
                                  'événements.'
                              : 'Aucun événement pour ce filtre.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _charger(silencieux: true),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    itemCount: affiches.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _carte(affiches[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _carte(Evenement evenement) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _ouvrirDetail(evenement),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      evenement.titre,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatutEvenementChip(statut: evenement.statut, compact: true),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Icon(Icons.meeting_room_rounded,
                      size: 15, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      evenement.salleNom.isEmpty
                          ? 'Salle'
                          : evenement.salleNom,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.person_outline_rounded,
                      size: 15, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      evenement.clientNom,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Icon(Icons.event_rounded,
                      size: 15, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      evenement.periode +
                          ((evenement.heureDebut ?? '').isEmpty
                              ? ''
                              : ' • ${evenement.heureDebut}'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    formatMontant(evenement.montantTotal),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (evenement.statut != StatutEvenement.annule) ...[
                const SizedBox(height: 4),
                Text(
                  evenement.estSolde
                      ? '✅ Soldé'
                      : 'Solde restant : ${formatMontant(evenement.solde)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: evenement.estSolde
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFB45309),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
