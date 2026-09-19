// lib/pages/reception_page.dart
//
// 🏨 MODULE 16 (phase C2) — HÔTEL : RÉCEPTION (ARRIVÉES & DÉPARTS).
//
// Tableau du jour : occupation des chambres, arrivées attendues (check-in),
// départs à enregistrer (check-out + encaissement du solde), réservations en
// attente à encaisser ou annuler, et chambres à nettoyer à remettre en
// service.
//
// Accessible quand le module `checkin` est actif ; chaque action est
// revérifiée côté serveur (droits `reception/créer`).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/chambre.dart';
import 'package:biashara_yangu/models/hotel_tableau_bord.dart';
import 'package:biashara_yangu/services/hotel_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/hotel_dialogues.dart';

class ReceptionPage extends StatefulWidget {
  const ReceptionPage({super.key});

  @override
  State<ReceptionPage> createState() => _ReceptionPageState();
}

class _ReceptionPageState extends State<ReceptionPage> {
  final HotelService _service = HotelService.instance;

  TableauBordHotel? _bord;
  List<Chambre> _aNettoyer = const <Chambre>[];

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
    TableauBordHotel? bord;
    List<Chambre> aNettoyer = const <Chambre>[];

    try {
      bord = await _service.tableauBord();
      final List<Chambre> chambres = await _service.listerChambres();
      aNettoyer = chambres
          .where((Chambre c) => c.statut == ChambreStatut.aNettoyer)
          .toList(growable: false);
    } on HotelServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ReceptionPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement de la réception.';
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
      _bord = bord;
      _aNettoyer = aNettoyer;
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

  Future<void> _checkin(SejourJour sejour) async {
    final bool fait = await confirmerCheckin(
      context,
      reservationId: sejour.id,
      clientNom: sejour.client,
      chambre: sejour.chambre,
      service: _service,
    );
    if (fait) _charger(silencieux: true);
  }

  Future<void> _checkout(SejourJour sejour) async {
    final bool fait = await dialogueCheckoutSejour(
      context,
      reservationId: sejour.id,
      clientNom: sejour.client,
      solde: sejour.solde,
      service: _service,
    );
    if (fait) _charger(silencieux: true);
  }

  Future<void> _encaisser(SejourJour sejour) async {
    final bool fait = await dialogueEncaisserSejour(
      context,
      reservationId: sejour.id,
      clientNom: sejour.client,
      solde: sejour.solde,
      service: _service,
    );
    if (fait) _charger(silencieux: true);
  }

  Future<void> _annuler(SejourJour sejour) async {
    final bool fait = await dialogueAnnulerSejour(
      context,
      reservationId: sejour.id,
      clientNom: sejour.client,
      service: _service,
    );
    if (fait) _charger(silencieux: true);
  }

  Future<void> _remiseEnService(Chambre chambre) async {
    try {
      await _service.changerStatutChambre(chambre.id, ChambreStatut.libre);
      _message('Chambre ${chambre.numero} remise en service (libre).');
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
      appBar: AppBar(title: const Text('Réception')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur()
              : RefreshIndicator(
                  onRefresh: () => _charger(silencieux: true),
                  child: _contenu(),
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

  Widget _contenu() {
    final TableauBordHotel bord = _bord ?? const TableauBordHotel();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: <Widget>[
        _carteOccupation(bord),
        _titreSection('Arrivées attendues', Icons.login_rounded,
            bord.arriveesCount),
        if (bord.arrivees.isEmpty)
          _vide('Aucune arrivée en attente. Les réservations du jour '
              'apparaîtront ici.')
        else
          ...bord.arrivees.map(_carteArrivee),
        const SizedBox(height: 8),
        _titreSection(
            'Départs à enregistrer', Icons.logout_rounded, bord.departsCount),
        if (bord.departs.isEmpty)
          _vide('Aucun départ à enregistrer pour le moment.')
        else
          ...bord.departs.map(_carteDepart),
        const SizedBox(height: 8),
        _titreSection('Chambres à nettoyer', Icons.cleaning_services_rounded,
            _aNettoyer.length),
        if (_aNettoyer.isEmpty)
          _vide('Aucune chambre en attente de nettoyage.')
        else
          ..._aNettoyer.map(_ligneNettoyage),
      ],
    );
  }

  Widget _carteOccupation(TableauBordHotel bord) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Occupation des chambres',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _stat('${bord.occupees}/${bord.total}', 'Occupées'),
                _stat('${bord.occupation}%', 'Taux'),
                _stat('${bord.libres}', 'Libres'),
                _stat('${bord.reservees}', 'Réservées'),
              ],
            ),
            if (bord.aNettoyer > 0) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(Icons.cleaning_services_rounded,
                      size: 18, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 6),
                  Text(
                    '${bord.aNettoyer} chambre${bord.aNettoyer > 1 ? 's' : ''} à nettoyer',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String valeur, String libelle) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            valeur,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(libelle, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _titreSection(String texte, IconData icone, int nombre) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: <Widget>[
          Icon(icone, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texte,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (nombre > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$nombre',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _vide(String texte) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Text(
        texte,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _carteArrivee(SejourJour sejour) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 20,
              backgroundColor:
                  theme.colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.login_rounded,
                  color: theme.colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Chambre ${sejour.chambre} • ${sejour.client}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${sejour.dateArrivee} → ${sejour.dateDepart} • '
                    '${sejour.nbPersonnes} pers.',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (sejour.solde > 0)
                    Text(
                      'Solde à payer : ${formatMontant(sejour.solde)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (sejour.retard) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      'En retard',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: () => _checkin(sejour),
                  child: const Text('Arrivée'),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Autres actions',
                  onSelected: (String valeur) {
                    switch (valeur) {
                      case 'encaisser':
                        _encaisser(sejour);
                      case 'annuler':
                        _annuler(sejour);
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    if (sejour.solde > 0)
                      const PopupMenuItem<String>(
                        value: 'encaisser',
                        child: ListTile(
                          leading: Icon(Icons.payments_rounded),
                          title: Text('Encaisser'),
                          dense: true,
                        ),
                      ),
                    const PopupMenuItem<String>(
                      value: 'annuler',
                      child: ListTile(
                        leading: Icon(Icons.cancel_outlined),
                        title: Text('Annuler'),
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _carteDepart(SejourJour sejour) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.tertiary
                  .withValues(alpha: 0.14),
              child: Icon(Icons.logout_rounded,
                  color: theme.colorScheme.tertiary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Chambre ${sejour.chambre} • ${sejour.client}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${sejour.dateArrivee} → ${sejour.dateDepart} • '
                    '${sejour.nbPersonnes} pers.',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    sejour.solde > 0
                        ? 'Solde à encaisser : ${formatMontant(sejour.solde)}'
                        : 'Séjour soldé',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: sejour.solde > 0
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (sejour.retard) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      'Départ en retard',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: () => _checkout(sejour),
                  child: const Text('Départ'),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Autres actions',
                  onSelected: (String valeur) {
                    if (valeur == 'encaisser') _encaisser(sejour);
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    if (sejour.solde > 0)
                      const PopupMenuItem<String>(
                        value: 'encaisser',
                        child: ListTile(
                          leading: Icon(Icons.payments_rounded),
                          title: Text('Encaisser'),
                          dense: true,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneNettoyage(Chambre chambre) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.cleaning_services_rounded,
            color: theme.colorScheme.tertiary),
        title: Text(chambre.designation),
        subtitle: Text(
          chambre.equipements == null || chambre.equipements!.isEmpty
              ? 'À nettoyer'
              : 'À nettoyer • ${chambre.equipements}',
        ),
        trailing: TextButton(
          onPressed: () => _remiseEnService(chambre),
          child: const Text('Marquer libre'),
        ),
      ),
    );
  }
}
