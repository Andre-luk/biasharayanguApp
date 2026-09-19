// lib/pages/evenement_form_page.dart
//
// 🎉 MODULE 16 (phase C4) — SALLE DES FÊTES : FORMULAIRE D'ÉVÉNEMENT.
//
// Création (`evenements/créer`) ou modification (`evenements/modifier`) via
// la RPC `rpc_evenement_enregistrer` :
//   • la salle doit être disponible sur la période (chevauchement refusé) ;
//   • le prix par jour est négociable (pré-rempli avec le tarif de la salle) ;
//   • à la création, l'avance encaissée ne peut pas dépasser le total.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/evenement.dart';
import 'package:biashara_yangu/models/salle.dart';
import 'package:biashara_yangu/services/hotel_service.dart' show ClientHotelOption;
import 'package:biashara_yangu/services/salle_fete_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

/// Suggestions de type d'événement (texte libre conservé côté serveur).
const List<String> _typesEvenement = <String>[
  'Mariage',
  'Anniversaire',
  'Réunion',
  'Conférence',
  'Baptême',
  'Fête familiale',
  'Autre',
];

class EvenementFormPage extends StatefulWidget {
  const EvenementFormPage({super.key, this.evenement});

  /// Événement à modifier (`null` = création).
  final Evenement? evenement;

  @override
  State<EvenementFormPage> createState() => _EvenementFormPageState();
}

class _EvenementFormPageState extends State<EvenementFormPage> {
  final SalleFeteService _service = SalleFeteService.instance;

  late final TextEditingController _titreCtrl;
  late final TextEditingController _clientCtrl;
  late final TextEditingController _telephoneCtrl;
  late final TextEditingController _invitesCtrl;
  late final TextEditingController _prixCtrl;
  late final TextEditingController _heureDebutCtrl;
  late final TextEditingController _heureFinCtrl;
  late final TextEditingController _avanceCtrl;
  late final TextEditingController _noteCtrl;

  List<Salle> _salles = const <Salle>[];
  List<ClientHotelOption> _clients = const <ClientHotelOption>[];

  Salle? _salle;
  ClientHotelOption? _clientFiche;

  DateTime _dateDebut = DateTime.now().add(const Duration(days: 7));
  DateTime _dateFin = DateTime.now().add(const Duration(days: 7));

  String _type = _typesEvenement.first;

  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreurChargement;

  Evenement? get _evenement => widget.evenement;
  bool get _creation => _evenement == null;

  @override
  void initState() {
    super.initState();
    final Evenement? e = widget.evenement;

    _titreCtrl = TextEditingController(text: e?.titre ?? '');
    _clientCtrl = TextEditingController(text: e?.clientNom ?? '');
    _telephoneCtrl = TextEditingController(text: e?.telephone ?? '');
    _invitesCtrl =
        TextEditingController(text: e == null ? '' : e.nbInvites.toString());
    _prixCtrl = TextEditingController(
      text: e == null || e.prixJour == 0 ? '' : _nombre(e.prixJour),
    );
    _heureDebutCtrl = TextEditingController(text: e?.heureDebut ?? '');
    _heureFinCtrl = TextEditingController(text: e?.heureFin ?? '');
    _avanceCtrl = TextEditingController();
    _noteCtrl = TextEditingController(text: e?.note ?? '');

    if (e != null) {
      _dateDebut = e.dateDebut ?? _dateDebut;
      _dateFin = e.dateFin ?? _dateDebut;
      final String? type = e.typeEvenement;
      if ((type ?? '').isNotEmpty) {
        _type = _typesEvenement.contains(type) ? type! : _typesEvenement.last;
      }
    }

    _charger();
  }

  @override
  void dispose() {
    _titreCtrl.dispose();
    _clientCtrl.dispose();
    _telephoneCtrl.dispose();
    _invitesCtrl.dispose();
    _prixCtrl.dispose();
    _heureDebutCtrl.dispose();
    _heureFinCtrl.dispose();
    _avanceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  static String _nombre(double valeur) => valeur == valeur.roundToDouble()
      ? valeur.toStringAsFixed(0)
      : valeur.toString();

  static double _parseMontant(String texte) {
    return double.tryParse(texte.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
  }

  static String _dateCourte(DateTime date) {
    final String jour = date.day.toString().padLeft(2, '0');
    final String mois = date.month.toString().padLeft(2, '0');
    return '$jour/$mois/${date.year}';
  }

  Future<void> _charger() async {
    if (!mounted) return;

    setState(() {
      _chargement = true;
      _erreurChargement = null;
    });

    try {
      final List<Salle> salles = await _service.listerSalles();
      List<ClientHotelOption> clients = const <ClientHotelOption>[];
      try {
        clients = await _service.listerClients();
      } catch (_) {
        // Les clients sont facultatifs : silencieux.
      }

      if (!mounted) return;

      Salle? salle = _salle;
      if (salle == null && _evenement != null) {
        for (final Salle s in salles) {
          if (s.id == _evenement!.salleId) {
            salle = s;
            break;
          }
        }
      }
      salle ??= salles.isEmpty ? null : salles.first;

      setState(() {
        _salles = salles;
        _clients = clients;
        _salle = salle;
        if (_prixCtrl.text.trim().isEmpty && salle != null) {
          _prixCtrl.text = salle.prixJour == 0 ? '' : _nombre(salle.prixJour);
        }
        if (_clientFiche == null && _evenement != null) {
          for (final ClientHotelOption c in clients) {
            if (c.id == _evenement!.clientId) {
              _clientFiche = c;
              break;
            }
          }
        }
        _chargement = false;
      });
    } on SalleFeteServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreurChargement = e.message;
        _chargement = false;
      });
    } catch (e, st) {
      debugPrint('EvenementFormPage._charger: $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreurChargement =
            'Une erreur inattendue est survenue lors du chargement.';
        _chargement = false;
      });
    }
  }

  void _afficherErreur(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  // ---------------------------------------------------------------------------
  // CALCULS D'APERÇU
  // ---------------------------------------------------------------------------

  int get _jours => _dateFin.difference(_dateDebut).inDays + 1;

  double get _prixJour => _parseMontant(_prixCtrl.text);

  double get _montantSalle => _jours <= 0 ? 0 : _jours * _prixJour;

  double get _avance => _parseMontant(_avanceCtrl.text);

  // ---------------------------------------------------------------------------
  // SAISIE
  // ---------------------------------------------------------------------------

  Future<void> _choisirDate({required bool debut}) async {
    final DateTime initiale = debut ? _dateDebut : _dateFin;
    final DateTime? choisi = await showDatePicker(
      context: context,
      initialDate: initiale,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      helpText: debut ? 'Date de l\'événement' : 'Date de fin',
    );
    if (choisi == null) return;

    setState(() {
      if (debut) {
        _dateDebut = choisi;
        if (_dateFin.isBefore(_dateDebut)) _dateFin = _dateDebut;
      } else {
        _dateFin = choisi.isBefore(_dateDebut) ? _dateDebut : choisi;
      }
    });
  }

  Future<void> _enregistrer() async {
    final String titre = _titreCtrl.text.trim();
    if (titre.isEmpty) {
      _afficherErreur('Donnez un titre à l\'événement.');
      return;
    }
    if (_salle == null) {
      _afficherErreur('Choisissez une salle.');
      return;
    }
    final String client = _clientCtrl.text.trim();
    if (client.isEmpty) {
      _afficherErreur('Indiquez le nom du client.');
      return;
    }
    if (_jours > 366) {
      _afficherErreur('Un événement ne peut pas dépasser 366 jours.');
      return;
    }
    if (_prixJour < 0) {
      _afficherErreur('Le prix par jour ne peut pas être négatif.');
      return;
    }

    final int invites = int.tryParse(_invitesCtrl.text.trim()) ?? 0;
    if (invites < 0) {
      _afficherErreur('Le nombre d\'invités ne peut pas être négatif.');
      return;
    }
    if (invites > _salle!.capacite) {
      _afficherErreur(
          'La salle « ${_salle!.nom} » accueille au maximum '
          '${_salle!.capacite} personnes.');
      return;
    }

    if (_creation && _avance > 0 && _avance > _montantSalle) {
      _afficherErreur('L\'avance dépasse le montant de la salle.');
      return;
    }

    final String telephone = _telephoneCtrl.text.trim();
    final String note = _noteCtrl.text.trim();

    setState(() => _enregistrement = true);
    try {
      final Evenement evenement = await _service.enregistrerEvenement(
        id: _evenement?.id,
        salleId: _salle!.id,
        titre: titre,
        typeEvenement: _type == 'Autre' ? '' : _type,
        clientId: _clientFiche?.id,
        clientNom: client,
        telephone: telephone.isEmpty ? null : telephone,
        dateDebut: _dateDebut,
        dateFin: _dateFin,
        heureDebut: _heureDebutCtrl.text.trim().isEmpty
            ? null
            : _heureDebutCtrl.text.trim(),
        heureFin:
            _heureFinCtrl.text.trim().isEmpty ? null : _heureFinCtrl.text.trim(),
        nbInvites: invites,
        prixJour: _prixJour,
        avance: _creation ? _avance : 0,
        note: note.isEmpty ? null : note,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_creation
              ? 'Événement ${evenement.numero ?? ''} créé.'
              : 'Événement enregistré.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      Navigator.of(context).pop(true);
    } on SalleFeteServiceException catch (e) {
      if (mounted) _afficherErreur(e.message);
    } catch (e) {
      if (mounted) _afficherErreur('Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  InputDecoration _decoration(String label,
      {String? hint, IconData? icone, String? suffixe}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icone == null ? null : Icon(icone),
      suffixText: suffixe,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_creation ? 'Nouvel événement' : 'Modifier l\'événement'),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreurChargement != null
              ? _vueErreur()
              : _salles.isEmpty
                  ? _vueSansSalle()
                  : _formulaire(),
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
            Text(_erreurChargement!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vueSansSalle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.meeting_room_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Aucune salle enregistrée.\n'
              'Créez d\'abord une salle pour pouvoir enregistrer un '
              'événement.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final bool? ok = await context
                    .push<bool>('/main/evenements/salles/new');
                if (ok == true) _charger();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Créer une salle'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formulaire() {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        AppDropdownField<Salle>(
          label: 'Salle',
          value: _salle,
          prefixIcon: Icons.meeting_room_rounded,
          items: _salles
              .map(
                (Salle salle) => DropdownMenuItem<Salle>(
                  value: salle,
                  child: Text(
                    '${salle.nom} • ${salle.capacite} pers.',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (Salle? salle) {
            if (salle == null) return;
            setState(() {
              _salle = salle;
              if (_prixCtrl.text.trim().isEmpty) {
                _prixCtrl.text =
                    salle.prixJour == 0 ? '' : _nombre(salle.prixJour);
              }
            });
          },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _titreCtrl,
          textCapitalization: TextCapitalization.sentences,
          decoration: _decoration('Titre de l\'événement',
              hint: 'Mariage Kabeya', icone: Icons.celebration_rounded),
        ),
        const SizedBox(height: 14),
        AppDropdownField<String>(
          label: 'Type',
          value: _type,
          prefixIcon: Icons.category_rounded,
          items: _typesEvenement
              .map((String type) =>
                  DropdownMenuItem<String>(value: type, child: Text(type)))
              .toList(growable: false),
          onChanged: (String? type) {
            if (type != null) setState(() => _type = type);
          },
        ),
        const SizedBox(height: 14),
        _titreSection('Client'),
        const SizedBox(height: 8),
        AppDropdownField<ClientHotelOption>(
          label: 'Fiche client existante (facultatif)',
          value: _clientFiche,
          prefixIcon: Icons.people_alt_rounded,
          hint: 'Nouveau client (saisie libre)',
          items: _clients
              .map(
                (ClientHotelOption c) => DropdownMenuItem<ClientHotelOption>(
                  value: c,
                  child: Text(c.nom, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(growable: false),
          onChanged: (ClientHotelOption? client) {
            setState(() {
              _clientFiche = client;
              if (client != null) {
                _clientCtrl.text = client.nom;
                if ((client.telephone ?? '').isNotEmpty) {
                  _telephoneCtrl.text = client.telephone!;
                }
              }
            });
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _clientCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: _decoration('Nom du client', icone: Icons.person_rounded),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _telephoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: _decoration('Téléphone (facultatif)',
              icone: Icons.phone_rounded),
        ),
        const SizedBox(height: 18),
        _titreSection('Dates & horaires'),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _choisirDate(debut: true),
                icon: const Icon(Icons.event_rounded),
                label: Text('Début : ${_dateCourte(_dateDebut)}'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _choisirDate(debut: false),
                icon: const Icon(Icons.event_available_rounded),
                label: Text('Fin : ${_dateCourte(_dateFin)}'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _jours <= 1 ? '1 jour' : '$_jours jours',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _heureDebutCtrl,
                decoration: _decoration('Heure de début',
                    hint: '14:00', icone: Icons.schedule_rounded),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _heureFinCtrl,
                decoration: _decoration('Heure de fin',
                    hint: '23:00', icone: Icons.schedule_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _titreSection('Participants & prix'),
        const SizedBox(height: 8),
        TextField(
          controller: _invitesCtrl,
          keyboardType: TextInputType.number,
          decoration: _decoration('Nombre d\'invités',
              hint: '180',
              icone: Icons.groups_rounded,
              suffixe: _salle == null
                  ? null
                  : 'max ${_salle!.capacite}'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _prixCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: _decoration('Prix négocié par jour',
              hint: '150 000',
              icone: Icons.payments_rounded,
              suffixe: '/ jour'),
        ),
        const SizedBox(height: 10),
        _recapMontants(theme),
        if (_creation) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _avanceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: _decoration('Avance encaissée (facultatif)',
                hint: '100 000', icone: Icons.savings_rounded),
          ),
        ],
        const SizedBox(height: 18),
        _titreSection('Note'),
        const SizedBox(height: 8),
        TextField(
          controller: _noteCtrl,
          textCapitalization: TextCapitalization.sentences,
          minLines: 2,
          maxLines: 4,
          decoration: _decoration('Note (facultatif)',
              icone: Icons.notes_rounded),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _enregistrement ? null : _enregistrer,
            icon: _enregistrement
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_creation
                ? 'Créer l\'événement'
                : 'Enregistrer les modifications'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _creation
              ? 'Les prestations (traiteur, décoration…) s\'ajoutent depuis '
                  'le dossier de l\'événement.'
              : 'Les prestations et les encaissements se gèrent depuis le '
                  'dossier de l\'événement.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _titreSection(String titre) {
    final ThemeData theme = Theme.of(context);
    return Text(
      titre,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  Widget _recapMontants(ThemeData theme) {
    final double total = _montantSalle;
    final double solde = (_creation ? total - _avance : total);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('Montant de la salle', style: theme.textTheme.bodyMedium),
              ),
              Text(
                formatMontant(total),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          if (_creation && _avance > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child:
                      Text('Avance encaissée', style: theme.textTheme.bodySmall),
                ),
                Text(
                  formatMontant(_avance),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: const Color(0xFF16A34A)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('Solde restant', style: theme.textTheme.bodySmall),
                ),
                Text(
                  formatMontant(solde),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: const Color(0xFFB45309)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
