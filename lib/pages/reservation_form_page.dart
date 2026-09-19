// lib/pages/reservation_form_page.dart
//
// 🏨 MODULE 16 (phase C2) — HÔTEL : FORMULAIRE DE RÉSERVATION.
//
// Chambre (prix pré-rempli, modifiable pour un tarif négocié), client
// (fiche existante ou simple nom), dates, personnes, avance et note.
// L'écriture passe par `rpc_reservation_creer` : vérification du
// chevauchement des séjours, de la capacité et des montants côté serveur.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/chambre.dart';
import 'package:biashara_yangu/services/hotel_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class ReservationFormPage extends StatefulWidget {
  const ReservationFormPage({super.key, this.chambreInitiale});

  /// Chambre présélectionnée (ouverture depuis une fiche chambre).
  final Chambre? chambreInitiale;

  @override
  State<ReservationFormPage> createState() => _ReservationFormPageState();
}

class _ReservationFormPageState extends State<ReservationFormPage> {
  final HotelService _service = HotelService.instance;

  final TextEditingController _personnesCtrl = TextEditingController(text: '1');
  final TextEditingController _prixCtrl = TextEditingController();
  final TextEditingController _avanceCtrl = TextEditingController();
  final TextEditingController _nomCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  List<Chambre> _chambres = const <Chambre>[];
  List<ClientHotelOption> _clients = const <ClientHotelOption>[];

  Chambre? _chambre;
  ClientHotelOption? _client;
  late DateTime _arrivee;
  late DateTime _depart;
  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    final DateTime maintenant = DateTime.now();
    _arrivee = DateTime(maintenant.year, maintenant.month, maintenant.day);
    _depart = _arrivee.add(const Duration(days: 1));
    _charger();
  }

  @override
  void dispose() {
    _personnesCtrl.dispose();
    _prixCtrl.dispose();
    _avanceCtrl.dispose();
    _nomCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final List<Chambre> chambres = await _service.listerChambres();
      final List<ClientHotelOption> clients = await _service.listerClients();
      if (!mounted) return;
      setState(() {
        _chambres = chambres;
        _clients = clients;
        final Chambre? initiale = widget.chambreInitiale;
        if (_chambre == null && initiale != null) {
          for (final Chambre chambre in chambres) {
            if (chambre.id == initiale.id) {
              _chambre = chambre;
              break;
            }
          }
        }
        _prefillPrix();
      });
    } on HotelServiceException catch (e) {
      if (!mounted) return;
      _afficherErreur(e.message);
    } catch (e) {
      if (!mounted) return;
      _afficherErreur('Impossible de charger les chambres et clients : $e');
    }
  }

  /// Pré-remplit le prix avec celui de la chambre (si le champ est vide).
  void _prefillPrix() {
    final Chambre? chambre = _chambre;
    if (chambre == null) return;
    if (_prixCtrl.text.trim().isNotEmpty) return;
    _prixCtrl.text = _nombre(chambre.prixNuit);
  }

  static String _nombre(double valeur) => valeur == valeur.roundToDouble()
      ? valeur.toStringAsFixed(0)
      : valeur.toString();

  static double _parseMontant(String texte) {
    return double.tryParse(texte.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
  }

  int get _nuits => _depart.difference(_arrivee).inDays;
  double get _prix => _parseMontant(_prixCtrl.text);
  double get _total => _nuits > 0 ? _nuits * _prix : 0;
  double get _avance => _parseMontant(_avanceCtrl.text);
  double get _reste {
    final double reste = _total - _avance;
    return reste < 0 ? 0 : reste;
  }

  void _afficherErreur(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _choisirDate({required bool arrivee}) async {
    final DateTime maintenant = DateTime.now();
    final DateTime aujourdHui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);

    final DateTime? choix = await showDatePicker(
      context: context,
      initialDate: arrivee ? _arrivee : _depart,
      firstDate: arrivee
          ? aujourdHui
          : _arrivee.add(const Duration(days: 1)),
      lastDate: DateTime(maintenant.year + 2),
      helpText: arrivee ? 'Date d\'arrivée' : 'Date de départ',
    );
    if (choix == null) return;

    setState(() {
      if (arrivee) {
        _arrivee = choix;
        if (!_depart.isAfter(_arrivee)) {
          _depart = _arrivee.add(const Duration(days: 1));
        }
      } else {
        _depart = choix;
      }
    });
  }

  Future<void> _enregistrer() async {
    final Chambre? chambre = _chambre;
    if (chambre == null) {
      _afficherErreur('Choisissez une chambre.');
      return;
    }

    final int personnes = int.tryParse(_personnesCtrl.text.trim()) ?? 0;
    if (personnes < 1) {
      _afficherErreur('Indiquez au moins une personne.');
      return;
    }
    if (personnes > chambre.capacite) {
      _afficherErreur(
          'La chambre ${chambre.numero} accueille ${chambre.capacite} '
          'personne(s) au maximum.');
      return;
    }

    final String nomLibre = _nomCtrl.text.trim();
    if (_client == null && nomLibre.isEmpty) {
      _afficherErreur('Choisissez un client ou saisissez son nom.');
      return;
    }

    if (_prix < 0) {
      _afficherErreur('Le prix par nuit ne peut pas être négatif.');
      return;
    }
    if (_avance < 0) {
      _afficherErreur('L\'avance ne peut pas être négative.');
      return;
    }
    if (_avance > _total) {
      _afficherErreur(
          'L\'avance dépasse le montant total du séjour (${formatMontant(_total)}).');
      return;
    }

    setState(() => _enregistrement = true);
    try {
      await _service.creerReservation(
        chambreId: chambre.id,
        dateArrivee: _arrivee,
        dateDepart: _depart,
        nbPersonnes: personnes,
        clientId: _client?.id,
        clientNom: nomLibre.isEmpty ? null : nomLibre,
        prixNuit: _prix,
        avance: _avance,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Réservation enregistrée : chambre ${chambre.numero}, '
            '${_nuits} nuit${_nuits > 1 ? 's' : ''}, '
            'total ${formatMontant(_total)}.',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      Navigator.of(context).pop(true);
    } on HotelServiceException catch (e) {
      if (mounted) _afficherErreur(e.message);
    } catch (e) {
      if (mounted) _afficherErreur('Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool pret = _chambres.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle réservation')),
      body: !pret
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: <Widget>[
                AppDropdownField<Chambre>(
                  label: 'Chambre *',
                  value: _chambre,
                  hint: 'Choisir une chambre',
                  prefixIcon: Icons.king_bed_rounded,
                  items: _chambres
                      .map(
                        (Chambre chambre) => DropdownMenuItem<Chambre>(
                          value: chambre,
                          child: Text(
                            '${chambre.designation} '
                            '($chambre.capacite pers. • '
                            '${formatMontant(chambre.prixNuit)}/nuit)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (Chambre? chambre) => setState(() {
                    _chambre = chambre;
                    _prefillPrix();
                  }),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _caseDate(
                        label: 'Arrivée',
                        date: _arrivee,
                        onTap: () => _choisirDate(arrivee: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _caseDate(
                        label: 'Départ',
                        date: _depart,
                        onTap: () => _choisirDate(arrivee: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _personnesCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Personnes *',
                    prefixIcon: const Icon(Icons.groups_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                AppDropdownField<ClientHotelOption>(
                  label: 'Client existant (facultatif)',
                  value: _client,
                  hint: 'Aucun — saisir le nom ci-dessous',
                  prefixIcon: Icons.person_search_rounded,
                  items: _clients
                      .map(
                        (ClientHotelOption client) =>
                            DropdownMenuItem<ClientHotelOption>(
                          value: client,
                          child: Text(client.nom,
                              overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (ClientHotelOption? client) =>
                      setState(() => _client = client),
                ),
                if (_client != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _client = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Retirer la fiche client'),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nomCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Nom du client (sans fiche)',
                    hintText: 'Ex. : M. Kabila',
                    prefixIcon: const Icon(Icons.badge_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _prixCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Prix / nuit',
                          prefixIcon: const Icon(Icons.payments_rounded),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _avanceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Avance',
                          prefixIcon:
                              const Icon(Icons.account_balance_wallet_rounded),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: <Widget>[
                        _ligneResume(theme, 'Nuits', '$_nuits'),
                        _ligneResume(theme, 'Montant total',
                            formatMontant(_total), gras: true),
                        _ligneResume(
                            theme, 'Avance', formatMontant(_avance)),
                        _ligneResume(theme, 'Reste à payer',
                            formatMontant(_reste), gras: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Note (facultatif)',
                    hintText: 'Lit bébé, arrivée tardive…',
                    prefixIcon: const Icon(Icons.sticky_note_2_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _enregistrement ? null : _enregistrer,
                  icon: _enregistrement
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Enregistrer la réservation'),
                ),
              ],
            ),
    );
  }

  Widget _caseDate({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.event_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: theme.textTheme.bodySmall),
                  Text(
                    formatDate(date),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneResume(ThemeData theme, String libelle, String valeur,
      {bool gras = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(libelle, style: theme.textTheme.bodyMedium),
          Text(
            valeur,
            style: gras
                ? theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
