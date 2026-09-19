// lib/pages/reservations_page.dart
//
// 🏨 MODULE 16 (phase C2) — HÔTEL : PLANNING DES RÉSERVATIONS.
//
// Liste filtrable (en attente / en cours / terminées / annulées) avec, pour
// chaque séjour : check-in, départ + encaissement du solde, encaissement
// d'avance, annulation motivée et facture de séjour.
//
// Accessible quand le module `reservations` est actif ; les droits fins
// (`reservations/voir`, `créer`…) sont revérifiés par les RPC serveur.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/reservation.dart';
import 'package:biashara_yangu/services/hotel_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/hotel_dialogues.dart';
import 'package:biashara_yangu/widgets/statut_reservation_chip.dart';

class ReservationsPage extends StatefulWidget {
  const ReservationsPage({super.key});

  @override
  State<ReservationsPage> createState() => _ReservationsPageState();
}

class _ReservationsPageState extends State<ReservationsPage> {
  final HotelService _service = HotelService.instance;

  List<Reservation> _reservations = const <Reservation>[];
  StatutReservation? _filtre;

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
    List<Reservation> reservations = const <Reservation>[];

    try {
      reservations = await _service.listerReservations();
    } on HotelServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ReservationsPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des réservations.';
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
      _reservations = reservations;
      _erreur = null;
      _chargement = false;
    });
  }

  int _compter(StatutReservation? statut) => statut == null
      ? _reservations.length
      : _reservations.where((Reservation r) => r.statut == statut).length;

  List<Reservation> get _filtrees => _filtre == null
      ? _reservations
      : _reservations
          .where((Reservation r) => r.statut == _filtre)
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

  Future<void> _ouvrirForm() async {
    final bool? ok =
        await context.push<bool>('/main/hotel/reservations/new');
    if (ok == true) _charger(silencieux: true);
  }

  void _facture(Reservation reservation) {
    context.push(
      '/main/hotel/reservations/${reservation.id}/facture',
      extra: reservation,
    );
  }

  Future<void> _checkin(Reservation reservation) async {
    final bool fait = await confirmerCheckin(
      context,
      reservationId: reservation.id,
      clientNom: reservation.clientNom,
      chambre: reservation.chambreNumero,
      service: _service,
    );
    if (fait) _charger(silencieux: true);
  }

  Future<void> _checkout(Reservation reservation) async {
    final bool fait = await dialogueCheckoutSejour(
      context,
      reservationId: reservation.id,
      clientNom: reservation.clientNom,
      solde: reservation.solde,
      service: _service,
    );
    if (fait) _charger(silencieux: true);
  }

  Future<void> _encaisser(Reservation reservation) async {
    final bool fait = await dialogueEncaisserSejour(
      context,
      reservationId: reservation.id,
      clientNom: reservation.clientNom,
      solde: reservation.solde,
      service: _service,
    );
    if (fait) _charger(silencieux: true);
  }

  Future<void> _annuler(Reservation reservation) async {
    final bool fait = await dialogueAnnulerSejour(
      context,
      reservationId: reservation.id,
      clientNom: reservation.clientNom,
      service: _service,
    );
    if (fait) _charger(silencieux: true);
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réservations')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ouvrirForm,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle réservation'),
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
                for (final StatutReservation statut in StatutReservation.values)
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
                        Icon(Icons.event_busy_rounded,
                            size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          _reservations.isEmpty
                              ? 'Aucune réservation enregistrée.\n'
                                  'Créez une réservation pour occuper vos chambres.'
                              : 'Aucune réservation pour ce filtre.',
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

  Widget _puceFiltre(StatutReservation? statut, String libelle) {
    return ChoiceChip(
      label: Text('$libelle (${_compter(statut)})'),
      selected: _filtre == statut,
      onSelected: (_) => setState(() => _filtre = statut),
    );
  }

  Widget _carte(Reservation reservation) {
    final ThemeData theme = Theme.of(context);
    final Color couleur = StatutReservationChip.couleur(reservation.statut);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 22,
              backgroundColor: couleur.withValues(alpha: 0.14),
              child: Icon(StatutReservationChip.icone(reservation.statut),
                  color: couleur),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Chambre ${reservation.chambreNumero.isEmpty ? '—' : reservation.chambreNumero}'
                    ' • ${reservation.clientNom}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatDate(reservation.dateArrivee)} → '
                    '${formatDate(reservation.dateDepart)} • '
                    '${reservation.nuits} nuit${reservation.nuits > 1 ? 's' : ''} • '
                    '${reservation.nbPersonnes} pers.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Total ${formatMontant(reservation.montantTotal)} • '
                    'Payé ${formatMontant(reservation.montantPaye)} • '
                    'Solde ${formatMontant(reservation.solde)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: reservation.solde > 0
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      StatutReservationChip(
                          statut: reservation.statut, compact: true),
                      if (reservation.enRetard)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(999),
                            border:
                                Border.all(color: Colors.red.shade300),
                          ),
                          child: Text(
                            'En retard',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (String valeur) {
                switch (valeur) {
                  case 'facture':
                    _facture(reservation);
                  case 'checkin':
                    _checkin(reservation);
                  case 'checkout':
                    _checkout(reservation);
                  case 'encaisser':
                    _encaisser(reservation);
                  case 'annuler':
                    _annuler(reservation);
                }
              },
              itemBuilder: (BuildContext context) {
                final List<PopupMenuEntry<String>> entrees =
                    <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'facture',
                    child: ListTile(
                      leading: Icon(Icons.receipt_long_rounded),
                      title: Text('Facture de séjour'),
                      dense: true,
                    ),
                  ),
                ];

                if (reservation.statut == StatutReservation.reservee) {
                  entrees.add(
                    const PopupMenuItem<String>(
                      value: 'checkin',
                      child: ListTile(
                        leading: Icon(Icons.login_rounded),
                        title: Text('Enregistrer l\'arrivée'),
                        dense: true,
                      ),
                    ),
                  );
                }

                if (reservation.statut == StatutReservation.enCours) {
                  entrees.add(
                    const PopupMenuItem<String>(
                      value: 'checkout',
                      child: ListTile(
                        leading: Icon(Icons.logout_rounded),
                        title: Text('Enregistrer le départ'),
                        dense: true,
                      ),
                    ),
                  );
                }

                if (reservation.estActive && reservation.solde > 0) {
                  entrees.add(
                    const PopupMenuItem<String>(
                      value: 'encaisser',
                      child: ListTile(
                        leading: Icon(Icons.payments_rounded),
                        title: Text('Encaisser'),
                        dense: true,
                      ),
                    ),
                  );
                }

                if (reservation.statut == StatutReservation.reservee) {
                  entrees.add(
                    const PopupMenuItem<String>(
                      value: 'annuler',
                      child: ListTile(
                        leading: Icon(Icons.cancel_outlined),
                        title: Text('Annuler la réservation'),
                        dense: true,
                      ),
                    ),
                  );
                }

                return entrees;
              },
            ),
          ],
        ),
      ),
    );
  }
}
