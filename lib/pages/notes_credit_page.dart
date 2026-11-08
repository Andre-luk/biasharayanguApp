// lib/pages/notes_credit_page.dart
//
// 🧾 MODULE 32 — AVOIRS / NOTES DE CRÉDIT.
//
// Écran du propriétaire :
//   • la liste des avoirs émis (numéro, client, montant, motif, auteur) ;
//   • « Nouvel avoir » : montant, motif, type (avoir ou remboursement) ;
//   • annulation d'un avoir (jamais de suppression).
//
// ⚠️ Aucun montant n'est calculé ici : le serveur vérifie le plafond
//    (impossible de rendre plus que ce qui a été encaissé), numérote et
//    journalise.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/note_credit.dart';
import 'package:biashara_yangu/services/note_credit_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class NotesCreditPage extends StatefulWidget {
  const NotesCreditPage({super.key});

  @override
  State<NotesCreditPage> createState() => _NotesCreditPageState();
}

class _NotesCreditPageState extends State<NotesCreditPage> {
  final TextEditingController _recherche = TextEditingController();

  bool _chargement = true;
  String? _erreur;
  List<NoteCredit> _avoirs = const <NoteCredit>[];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  bool get _peutEmettre =>
      PermissionService.instance.peut(PageAccess.caisse, ActionAccess.creer);

  Future<void> _charger() async {
    setState(() {
      _chargement = _avoirs.isEmpty;
      _erreur = null;
    });
    try {
      final List<NoteCredit> liste = await NoteCreditService.instance.lister(
        recherche: _recherche.text.trim().isEmpty ? null : _recherche.text,
      );
      if (!mounted) return;
      setState(() {
        _avoirs = liste;
        _chargement = false;
      });
    } on NoteCreditException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? AppCouleurs.danger : null,
      ),
    );
  }

  /// Formulaire d'émission d'un avoir.
  Future<void> _nouvelAvoir() async {
    final TextEditingController montant = TextEditingController();
    final TextEditingController motif = TextEditingController();
    final TextEditingController client = TextEditingController();
    final TextEditingController facture = TextEditingController();
    final GlobalKey<FormState> cle = GlobalKey<FormState>();
    TypeAvoir type = TypeAvoir.avoir;
    String mode = 'especes';

    final bool? envoye = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setEtat) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Nouvel avoir'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Form(
                key: cle,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextFormField(
                      controller: montant,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Montant à créditer',
                        suffixText: '',
                        border: OutlineInputBorder(),
                      ),
                      validator: (String? v) {
                        final double? d =
                            double.tryParse((v ?? '').replaceAll(',', '.'));
                        if (d == null || d <= 0) return 'Montant invalide.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: client,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Client (facultatif)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: facture,
                      decoration: const InputDecoration(
                        labelText: 'Facture d\'origine (facultatif)',
                        hintText: 'VTE-20261108-0001',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: motif,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Motif',
                        hintText: 'Retour, erreur de prix, article défectueux…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<TypeAvoir>(
                      initialValue: type,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                      ),
                      items: TypeAvoir.values
                          .map(
                            (TypeAvoir t) => DropdownMenuItem<TypeAvoir>(
                              value: t,
                              child: Text(t.libelle),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (TypeAvoir? v) =>
                          setEtat(() => type = v ?? TypeAvoir.avoir),
                    ),
                    if (type == TypeAvoir.remboursement) ...<Widget>[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: mode,
                        decoration: const InputDecoration(
                          labelText: 'Rendu en',
                          border: OutlineInputBorder(),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                            value: 'especes',
                            child: Text('Espèces'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'mobile_money',
                            child: Text('Mobile Money'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'carte',
                            child: Text('Carte'),
                          ),
                        ],
                        onChanged: (String? v) =>
                            setEtat(() => mode = v ?? 'especes'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (cle.currentState?.validate() == true) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: const Text('Émettre l\'avoir'),
            ),
          ],
        ),
      ),
    );

    final String montantTexte = montant.text;
    final String motifTexte = motif.text.trim();
    final String clientTexte = client.text.trim();
    final String factureTexte = facture.text.trim();
    montant.dispose();
    motif.dispose();
    client.dispose();
    facture.dispose();

    if (envoye != true) return;

    final double? valeur =
        double.tryParse(montantTexte.replaceAll(',', '.'));
    if (valeur == null || valeur <= 0) return;

    try {
      final NoteCredit note = await NoteCreditService.instance.creer(
        montant: valeur,
        type: type,
        motif: motifTexte.isEmpty ? null : motifTexte,
        clientNom: clientTexte.isEmpty ? null : clientTexte,
        factureNumero: factureTexte.isEmpty ? null : factureTexte,
        modeRemboursement: type == TypeAvoir.remboursement ? mode : null,
      );
      _message('${note.libelle} émis : ${formatMontant(note.montant)}.');
      await _charger();
    } on NoteCreditException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _annuler(NoteCredit note) async {
    final TextEditingController motif = TextEditingController();
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Annuler ${note.numero} ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'L\'avoir ne sera pas supprimé : il sera marqué ANNULÉ, avec '
              'votre nom et le motif.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motif,
              decoration: const InputDecoration(
                labelText: 'Motif de l\'annulation',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Non'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppCouleurs.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Annuler l\'avoir'),
          ),
        ],
      ),
    );
    final String motifTexte = motif.text.trim();
    motif.dispose();

    if (confirme != true) return;

    try {
      await NoteCreditService.instance.annuler(
        note.id,
        motif: motifTexte.isEmpty ? null : motifTexte,
      );
      _message('Avoir ${note.numero} annulé.');
      await _charger();
    } on NoteCreditException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avoirs & notes de crédit'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _peutEmettre
          ? FloatingActionButton.extended(
              onPressed: _nouvelAvoir,
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('Nouvel avoir'),
            )
          : null,
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur(_erreur!)
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: <Widget>[
                      TextField(
                        controller: _recherche,
                        decoration: InputDecoration(
                          hintText: 'Numéro, client, motif…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onSubmitted: (_) => _charger(),
                      ),
                      const SizedBox(height: 12),
                      if (_avoirs.isEmpty)
                        _vide()
                      else
                        ..._avoirs.map(_tuile),
                    ],
                  ),
                ),
    );
  }

  Widget _vueErreur(String message) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const SizedBox(height: 40),
        Icon(Icons.error_outline, size: 48, color: AppCouleurs.danger),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ),
      ],
    );
  }

  Widget _vide() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: <Widget>[
          Icon(Icons.receipt_long_rounded,
              size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            'Aucun avoir pour le moment.\nUn avoir sert à rendre de l\'argent '
            'sans annuler la vente d\'origine.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _tuile(NoteCredit note) {
    final bool annule = note.estAnnule;
    final Color accent =
        annule ? Colors.grey.shade600 : AppCouleurs.marineClair;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        onTap: annule ? null : () => _annuler(note),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.15),
          child: Icon(
            note.estRemboursement
                ? Icons.payments_rounded
                : Icons.receipt_long_rounded,
            color: accent,
          ),
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                note.numero,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: annule ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            Text(
              formatMontant(note.montant, devise: note.devise),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: annule ? Colors.grey.shade600 : null,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              <String>[
                note.type.libelle.split(' (').first,
                if ((note.clientNom ?? '').isNotEmpty) note.clientNom!,
                if ((note.factureNumero ?? '').isNotEmpty)
                  'facture ${note.factureNumero}',
                formatDate(note.date),
              ].join(' • '),
              style: const TextStyle(fontSize: 12),
            ),
            if ((note.motif ?? '').isNotEmpty)
              Text(
                note.motif!,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
              ),
            if (annule)
              Text(
                'Annulé le ${formatDate(note.annuleLe)}'
                '${(note.motifAnnulation ?? '').isNotEmpty ? ' — ${note.motifAnnulation}' : ''}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppCouleurs.danger,
                ),
              )
            else if ((note.auteur ?? '').isNotEmpty)
              Text(
                'Émis par ${note.auteur}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
    );
  }
}
