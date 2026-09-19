// lib/pages/evenement_detail_page.dart
//
// 🎉 MODULE 16 (phase C4) — SALLE DES FÊTES : DOSSIER D'UN ÉVÉNEMENT.
//
// Tout se pilote ici :
//   • fiche complète (salle, client, dates, invités, montants) ;
//   • prestations (traiteur, décoration…) ajoutées ou retirées ;
//   • cycle de vie : confirmer → en cours → terminer (ou annuler motif) ;
//   • encaissement des avances, acomptes et du solde.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/evenement.dart';
import 'package:biashara_yangu/services/salle_fete_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/statut_evenement_chip.dart';

class EvenementDetailPage extends StatefulWidget {
  const EvenementDetailPage({
    super.key,
    required this.evenementId,
    this.evenement,
  });

  final String evenementId;

  /// Événement déjà connu (évite un premier écran vide).
  final Evenement? evenement;

  @override
  State<EvenementDetailPage> createState() => _EvenementDetailPageState();
}

class _EvenementDetailPageState extends State<EvenementDetailPage> {
  final SalleFeteService _service = SalleFeteService.instance;

  Evenement? _evenement;
  bool _chargement = true;
  bool _actionEnCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _evenement = widget.evenement;
    _charger();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux) {
      setState(() {
        _chargement = _evenement == null;
        _erreur = null;
      });
    }

    String? messageErreur;
    Evenement? evenement;

    try {
      evenement = await _service.chargerEvenement(widget.evenementId);
    } on SalleFeteServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('EvenementDetailPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement du dossier.';
    }

    if (!mounted) return;

    if (messageErreur != null) {
      if (silencieux && _evenement != null) {
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
      if (evenement != null) _evenement = evenement;
      _erreur = evenement == null
          ? 'Événement introuvable : il a peut-être été supprimé.'
          : null;
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

  Future<void> _executer(Future<Evenement> Function() action,
      {required String succes}) async {
    setState(() => _actionEnCours = true);
    try {
      final Evenement evenement = await action();
      if (!mounted) return;
      setState(() => _evenement = evenement);
      _message(succes);
      await _charger(silencieux: true);
    } on SalleFeteServiceException catch (e) {
      if (mounted) _message(e.message, erreur: true);
    } catch (e) {
      if (mounted) _message('Erreur inattendue : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _modifier() async {
    final Evenement? evenement = _evenement;
    if (evenement == null) return;
    final bool? ok = await context.push<bool>(
      '/main/evenements/${evenement.id}/edit',
      extra: evenement,
    );
    if (ok == true) {
      await _charger(silencieux: true);
      if (mounted) setState(() {});
    }
  }

  Future<void> _avancer(StatutEvenement statut) async {
    final Evenement? evenement = _evenement;
    if (evenement == null) return;
    await _executer(
      () => _service.changerStatut(evenement.id, statut),
      succes: 'Événement : ${statut.libelle.toLowerCase()}.',
    );
  }

  Future<void> _annuler() async {
    final Evenement? evenement = _evenement;
    if (evenement == null) return;

    final TextEditingController motifCtrl = TextEditingController();
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Annuler l\'événement ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'L\'événement restera dans l\'historique avec le statut '
              '« Annulé ». Les paiements déjà encaissés restent tracés.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motifCtrl,
              decoration: const InputDecoration(
                labelText: 'Motif (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Annuler l\'événement'),
          ),
        ],
      ),
    );

    if (confirme != true) return;

    final String motif = motifCtrl.text.trim();
    await _executer(
      () => _service.changerStatut(evenement.id, StatutEvenement.annule,
          motif: motif.isEmpty ? null : motif),
      succes: 'Événement annulé.',
    );
  }

  Future<void> _ajouterPrestation() async {
    final Evenement? evenement = _evenement;
    if (evenement == null) return;

    final TextEditingController libelleCtrl = TextEditingController();
    final TextEditingController quantiteCtrl =
        TextEditingController(text: '1');
    final TextEditingController prixCtrl = TextEditingController();

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Ajouter une prestation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: libelleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Prestation',
                hintText: 'Traiteur, décoration, sonorisation…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: quantiteCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Quantité',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: prixCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Prix unitaire',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
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
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );

    if (valide != true) return;

    final String libelle = libelleCtrl.text.trim();
    if (libelle.isEmpty) {
      _message('Indiquez la prestation.', erreur: true);
      return;
    }

    final double quantite = double.tryParse(
            quantiteCtrl.text.replaceAll(' ', '').replaceAll(',', '.')) ??
        1;
    final double prix = double.tryParse(
            prixCtrl.text.replaceAll(' ', '').replaceAll(',', '.')) ??
        0;

    await _executer(
      () => _service.ajouterPrestation(
        evenementId: evenement.id,
        libelle: libelle,
        quantite: quantite <= 0 ? 1 : quantite,
        prixUnitaire: prix,
      ),
      succes: 'Prestation ajoutée.',
    );
  }

  Future<void> _retirerPrestation(LigneEvenement ligne) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Retirer « ${ligne.libelle} » ?'),
        content: Text(
            'La prestation sera retirée du total (${formatMontant(ligne.total)}).'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );

    if (confirme != true) return;

    await _executer(
      () => _service.supprimerPrestation(ligne.id),
      succes: 'Prestation retirée.',
    );
  }

  Future<void> _encaisser() async {
    final Evenement? evenement = _evenement;
    if (evenement == null) return;

    final double solde = evenement.solde;
    final TextEditingController montantCtrl = TextEditingController(
      text: solde > 0 ? _nombre(solde) : '',
    );
    final TextEditingController noteCtrl = TextEditingController();

    String mode = 'especes';
    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext stateContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setEtat) => AlertDialog(
          title: const Text('Encaisser un paiement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Solde restant : ${formatMontant(solde)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: montantCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Montant encaissé',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              AppDropdownField<String>(
                label: 'Mode de paiement',
                value: mode,
                items: SalleFeteService.modesPaiement.entries
                    .map(
                      (MapEntry<String, String> entree) =>
                          DropdownMenuItem<String>(
                        value: entree.key,
                        child: Text(entree.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (String? valeur) {
                  if (valeur != null) setEtat(() => mode = valeur);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (facultatif)',
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
              child: const Text('Encaisser'),
            ),
          ],
        ),
      ),
    );

    if (valide != true) return;

    final double montant = double.tryParse(
            montantCtrl.text.replaceAll(' ', '').replaceAll(',', '.')) ??
        0;
    if (montant <= 0) {
      _message('Le montant encaissé doit être supérieur à zéro.', erreur: true);
      return;
    }

    final String note = noteCtrl.text.trim();
    await _executer(
      () => _service.encaisser(
        id: evenement.id,
        montant: montant,
        modePaiement: mode,
        note: note.isEmpty ? null : note,
      ),
      succes: 'Paiement encaissé : ${formatMontant(montant)}.',
    );
  }

  static String _nombre(double valeur) => valeur == valeur.roundToDouble()
      ? valeur.toStringAsFixed(0)
      : valeur.toString();

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Evenement? evenement = _evenement;

    return Scaffold(
      appBar: AppBar(
        title: Text(evenement?.titre ?? 'Dossier événement'),
        actions: <Widget>[
          if (evenement != null && !evenement.statut.estClos)
            IconButton(
              tooltip: 'Modifier',
              onPressed: _modifier,
              icon: const Icon(Icons.edit_rounded),
            ),
          IconButton(
            tooltip: 'Guide d\'utilisation',
            onPressed: () => context.pushNamed('guide-utilisation'),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur()
              : _dossier(evenement!),
      floatingActionButton: evenement == null || evenement.statut.estClos
          ? null
          : FloatingActionButton.extended(
              onPressed: _actionEnCours ? null : _encaisser,
              icon: const Icon(Icons.payments_rounded),
              label: Text(evenement.estSolde
                  ? 'Encaisser'
                  : 'Encaisser ${formatMontant(evenement.solde)}',
              ),
            ),
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

  Widget _dossier(Evenement evenement) {
    final ThemeData theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => _charger(silencieux: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  evenement.numero ?? 'Événement',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              StatutEvenementChip(statut: evenement.statut),
            ],
          ),
          const SizedBox(height: 10),
          _carteFiche(evenement, theme),
          const SizedBox(height: 14),
          _carteMontants(evenement, theme),
          const SizedBox(height: 14),
          _sectionPrestations(evenement, theme),
          const SizedBox(height: 14),
          _sectionActions(evenement, theme),
          if ((evenement.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            _carteTexte('Note', evenement.note!, theme, Icons.notes_rounded),
          ],
          if ((evenement.motifAnnulation ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            _carteTexte('Motif d\'annulation', evenement.motifAnnulation!,
                theme, Icons.event_busy_rounded,
                rouge: true),
          ],
        ],
      ),
    );
  }

  Widget _carteFiche(Evenement evenement, ThemeData theme) {
    Widget ligne(IconData icone, String texte) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            Icon(icone, size: 17, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(child: Text(texte, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
    }

    final String heures = (evenement.heureDebut ?? '').isEmpty
        ? ''
        : ' • ${evenement.heureDebut}'
            '${(evenement.heureFin ?? '').isEmpty ? '' : ' → ${evenement.heureFin}'}';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              evenement.titre,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if ((evenement.typeEvenement ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(evenement.typeEvenement!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 10),
            ligne(Icons.meeting_room_rounded,
                'Salle : ${evenement.salleNom.isEmpty ? '—' : evenement.salleNom}'),
            ligne(Icons.person_rounded, 'Client : ${evenement.clientNom}'),
            if ((evenement.telephone ?? '').isNotEmpty)
              ligne(Icons.phone_rounded, evenement.telephone!),
            ligne(Icons.event_rounded,
                '${evenement.periode} (${evenement.nbJours} jour'
                '${evenement.nbJours > 1 ? 's' : ''})$heures'),
            ligne(Icons.groups_rounded,
                '${evenement.nbInvites} invité${evenement.nbInvites > 1 ? 's' : ''}'),
          ],
        ),
      ),
    );
  }

  Widget _carteMontants(Evenement evenement, ThemeData theme) {
    Widget ligne(String libelle, String valeur,
        {Color? couleur, bool gras = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(libelle, style: theme.textTheme.bodyMedium),
            ),
            Text(
              valeur,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: gras ? FontWeight.w800 : FontWeight.w600,
                color: couleur,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Montants',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ligne(
                'Salle (${evenement.nbJours} × ${formatMontant(evenement.prixJour)})',
                formatMontant(evenement.montantSalle)),
            ligne(
                'Prestations (${evenement.lignes.length})',
                formatMontant(
                    evenement.montantTotal - evenement.montantSalle)),
            const Divider(height: 16),
            ligne('Total', formatMontant(evenement.montantTotal), gras: true),
            ligne('Encaissé', formatMontant(evenement.montantPaye),
                couleur: const Color(0xFF16A34A)),
            ligne(
              'Solde restant',
              evenement.estSolde ? '—' : formatMontant(evenement.solde),
              couleur: evenement.estSolde
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFB45309),
              gras: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionPrestations(Evenement evenement, ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('Prestations',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (!evenement.statut.estClos)
                  TextButton.icon(
                    onPressed: _actionEnCours ? null : _ajouterPrestation,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Ajouter'),
                  ),
              ],
            ),
            if (evenement.lignes.isEmpty)
              Text(
                'Aucune prestation. Ajoutez le traiteur, la décoration, '
                'la sonorisation…',
                style: theme.textTheme.bodySmall,
              )
            else
              for (final LigneEvenement ligne in evenement.lignes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(ligne.libelle),
                  subtitle: Text(
                    '${_nombre(ligne.quantite)} × ${formatMontant(ligne.prixUnitaire)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        formatMontant(ligne.total),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (!evenement.statut.estClos)
                        IconButton(
                          tooltip: 'Retirer',
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 20),
                          onPressed: _actionEnCours
                              ? null
                              : () => _retirerPrestation(ligne),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _sectionActions(Evenement evenement, ThemeData theme) {
    final List<Widget> boutons = <Widget>[];

    switch (evenement.statut) {
      case StatutEvenement.reserve:
        boutons.add(FilledButton.icon(
          onPressed: _actionEnCours
              ? null
              : () => _avancer(StatutEvenement.confirme),
          icon: const Icon(Icons.verified_rounded),
          label: const Text('Confirmer'),
        ));
      case StatutEvenement.confirme:
        boutons.add(FilledButton.icon(
          onPressed:
              _actionEnCours ? null : () => _avancer(StatutEvenement.enCours),
          icon: const Icon(Icons.celebration_rounded),
          label: const Text('Démarrer (en cours)'),
        ));
        boutons.add(OutlinedButton.icon(
          onPressed:
              _actionEnCours ? null : () => _avancer(StatutEvenement.termine),
          icon: const Icon(Icons.task_alt_rounded),
          label: const Text('Terminer'),
        ));
      case StatutEvenement.enCours:
        boutons.add(FilledButton.icon(
          onPressed:
              _actionEnCours ? null : () => _avancer(StatutEvenement.termine),
          icon: const Icon(Icons.task_alt_rounded),
          label: const Text('Terminer'),
        ));
      case StatutEvenement.termine:
      case StatutEvenement.annule:
        break;
    }

    if (evenement.statut.occupeLaSalle) {
      boutons.add(OutlinedButton.icon(
        onPressed: _actionEnCours ? null : _annuler,
        icon: const Icon(Icons.event_busy_rounded),
        label: const Text('Annuler'),
      ));
    }

    if (boutons.isEmpty) {
      return Text(
        evenement.statut == StatutEvenement.termine
            ? 'Événement terminé.'
            : 'Événement annulé.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Wrap(spacing: 10, runSpacing: 10, children: boutons);
  }

  Widget _carteTexte(String titre, String texte, ThemeData theme,
      IconData icone,
      {bool rouge = false}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icone,
                    size: 18,
                    color: rouge
                        ? const Color(0xFFDC2626)
                        : theme.colorScheme.outline),
                const SizedBox(width: 8),
                Text(titre,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 6),
            Text(texte, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
