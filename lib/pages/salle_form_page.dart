// lib/pages/salle_form_page.dart
//
// 🎉 MODULE 16 (phase C4) — SALLE DES FÊTES : FORMULAIRE DE SALLE.
//
// Création (`salles/créer`) ou modification (`salles/modifier`) via la RPC
// `rpc_salle_enregistrer`, qui vérifie les droits et l'unicité du nom par
// boutique.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/salle.dart';
import 'package:biashara_yangu/services/salle_fete_service.dart';

class SalleFormPage extends StatefulWidget {
  const SalleFormPage({super.key, this.salle});

  /// Salle à modifier (`null` = création).
  final Salle? salle;

  @override
  State<SalleFormPage> createState() => _SalleFormPageState();
}

class _SalleFormPageState extends State<SalleFormPage> {
  late final TextEditingController _nomCtrl;
  late final TextEditingController _capaciteCtrl;
  late final TextEditingController _prixCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _equipementsCtrl;

  late bool _actif;
  bool _enregistrement = false;

  Salle? get _salle => widget.salle;

  @override
  void initState() {
    super.initState();
    final Salle? s = widget.salle;
    _nomCtrl = TextEditingController(text: s?.nom ?? '');
    _capaciteCtrl = TextEditingController(text: (s?.capacite ?? 50).toString());
    _prixCtrl = TextEditingController(
      text: s == null || s.prixJour == 0 ? '' : _nombre(s.prixJour),
    );
    _descriptionCtrl = TextEditingController(text: s?.description ?? '');
    _equipementsCtrl = TextEditingController(text: s?.equipements ?? '');
    _actif = s?.actif ?? true;
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _capaciteCtrl.dispose();
    _prixCtrl.dispose();
    _descriptionCtrl.dispose();
    _equipementsCtrl.dispose();
    super.dispose();
  }

  static String _nombre(double valeur) => valeur == valeur.roundToDouble()
      ? valeur.toStringAsFixed(0)
      : valeur.toString();

  static double _parseMontant(String texte) {
    return double.tryParse(texte.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
  }

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

  void _afficherErreur(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _enregistrer() async {
    final String nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      _afficherErreur('Le nom de la salle est obligatoire.');
      return;
    }

    final int capacite = int.tryParse(_capaciteCtrl.text.trim()) ?? 0;
    if (capacite < 1 || capacite > 10000) {
      _afficherErreur(
          'La capacité doit être comprise entre 1 et 10 000 personnes.');
      return;
    }

    final double prix = _parseMontant(_prixCtrl.text);
    if (prix < 0) {
      _afficherErreur('Le prix par jour ne peut pas être négatif.');
      return;
    }

    final String description = _descriptionCtrl.text.trim();
    final String equipements = _equipementsCtrl.text.trim();

    setState(() => _enregistrement = true);
    try {
      final Salle salle = await SalleFeteService.instance.enregistrerSalle(
        id: _salle?.id,
        nom: nom,
        capacite: capacite,
        prixJour: prix,
        description: description.isEmpty ? null : description,
        equipements: equipements.isEmpty ? null : equipements,
        actif: _actif,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_salle == null
              ? 'Salle « ${salle.nom} » créée.'
              : 'Salle « ${salle.nom} » enregistrée.'),
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool creation = _salle == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(creation ? 'Nouvelle salle' : 'Modifier la salle'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          TextField(
            controller: _nomCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration('Nom de la salle',
                hint: 'Salle principale, Terrasse…',
                icone: Icons.meeting_room_rounded),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _capaciteCtrl,
            keyboardType: TextInputType.number,
            decoration: _decoration('Capacité (personnes)',
                hint: '200', icone: Icons.groups_rounded, suffixe: 'pers.'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _prixCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration('Prix par jour',
                hint: '150 000', icone: Icons.payments_rounded, suffixe: '/ jour'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _equipementsCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration('Équipements',
                hint: 'Sono, climatisation, parking…',
                icone: Icons.weekend_rounded),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descriptionCtrl,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 4,
            decoration: _decoration('Description (facultatif)',
                icone: Icons.notes_rounded),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _actif,
            onChanged: (bool valeur) => setState(() => _actif = valeur),
            title: const Text('Salle active'),
            subtitle: const Text(
              'Une salle inactive reste dans l\'historique mais ne se '
              'réserve plus.',
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
              label: Text(creation ? 'Créer la salle' : 'Enregistrer'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Le prix par jour est un tarif proposé : il peut être négocié '
            'pour chaque événement.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
