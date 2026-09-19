// lib/pages/matiere_form_page.dart
//
// 🥖 MODULE 16 (phase C5) — BOULANGERIE : FORMULAIRE DE MATIÈRE PREMIÈRE.
//
// Création / modification via `rpc_matiere_enregistrer` (droits
// `production/créer` ou `production/modifier`, nom unique par boutique).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/matiere_premiere.dart';
import 'package:biashara_yangu/models/production.dart';
import 'package:biashara_yangu/services/production_service.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

/// Unités proposées (texte libre possible côté serveur).
const List<String> _unites = <String>['kg', 'g', 'l', 'cl', 'piece', 'sac'];

class MatiereFormPage extends StatefulWidget {
  const MatiereFormPage({super.key, this.matiere});

  /// Matière à modifier (`null` = création).
  final MatierePremiere? matiere;

  @override
  State<MatiereFormPage> createState() => _MatiereFormPageState();
}

class _MatiereFormPageState extends State<MatiereFormPage> {
  late final TextEditingController _nomCtrl;
  late final TextEditingController _seuilCtrl;
  late final TextEditingController _prixCtrl;

  late String _unite;
  late bool _actif;
  bool _enregistrement = false;

  MatierePremiere? get _matiere => widget.matiere;

  @override
  void initState() {
    super.initState();
    final MatierePremiere? m = widget.matiere;
    _nomCtrl = TextEditingController(text: m?.nom ?? '');
    _seuilCtrl = TextEditingController(
      text: m == null || m.seuilAlerte == 0
          ? ''
          : Production.nombre(m.seuilAlerte),
    );
    _prixCtrl = TextEditingController(
      text:
          m == null || m.prixUnitaire == 0 ? '' : Production.nombre(m.prixUnitaire),
    );
    _unite = m?.unite ?? 'kg';
    if (!_unites.contains(_unite)) _unite = 'kg';
    _actif = m?.actif ?? true;
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _seuilCtrl.dispose();
    _prixCtrl.dispose();
    super.dispose();
  }

  static double _parse(String texte) {
    return double.tryParse(texte.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
  }

  void _afficherErreur(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _enregistrer() async {
    final String nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      _afficherErreur('Le nom de la matière première est obligatoire.');
      return;
    }

    final double seuil = _parse(_seuilCtrl.text);
    if (seuil < 0) {
      _afficherErreur('Le seuil d\'alerte ne peut pas être négatif.');
      return;
    }

    final double prix = _parse(_prixCtrl.text);
    if (prix < 0) {
      _afficherErreur('Le prix unitaire ne peut pas être négatif.');
      return;
    }

    setState(() => _enregistrement = true);
    try {
      final MatierePremiere matiere =
          await ProductionService.instance.enregistrerMatiere(
        id: _matiere?.id,
        nom: nom,
        unite: _unite,
        seuilAlerte: seuil,
        prixUnitaire: prix,
        actif: _actif,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_matiere == null
              ? '${matiere.nom} créée.'
              : '${matiere.nom} enregistrée.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      Navigator.of(context).pop(true);
    } on ProductionServiceException catch (e) {
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
    final bool creation = _matiere == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(creation ? 'Nouvelle matière première' : 'Modifier la matière'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          TextField(
            controller: _nomCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nom de la matière',
              hintText: 'Farine T55, Levure, Sucre…',
              prefixIcon: Icon(Icons.science_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          AppDropdownField<String>(
            label: 'Unité de mesure',
            value: _unite,
            prefixIcon: Icons.straighten_rounded,
            items: _unites
                .map((String u) =>
                    DropdownMenuItem<String>(value: u, child: Text(u)))
                .toList(growable: false),
            onChanged: (String? valeur) {
              if (valeur != null) setState(() => _unite = valeur);
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _seuilCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Seuil d\'alerte',
              hintText: '20',
              suffixText: _unite,
              prefixIcon: const Icon(Icons.warning_amber_rounded),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _prixCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Prix par $_unite (facultatif)',
              suffixText: '/ $_unite',
              prefixIcon: const Icon(Icons.payments_rounded),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _actif,
            onChanged: (bool valeur) => setState(() => _actif = valeur),
            title: const Text('Matière active'),
            subtitle: const Text(
              'Une matière inactive n\'apparaît plus dans les productions.',
            ),
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
              label: Text(creation ? 'Créer la matière' : 'Enregistrer'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Le prix par unité sert au calcul du coût de revient des '
            'productions ; il se met à jour à chaque approvisionnement.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
