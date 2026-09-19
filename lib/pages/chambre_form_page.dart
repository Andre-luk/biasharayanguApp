// lib/pages/chambre_form_page.dart
//
// 🏨 MODULE 16 (phase C2) — HÔTEL : FORMULAIRE DE CHAMBRE.
//
// Création (`chambres/créer`) ou modification (`chambres/modifier`) via la
// RPC `rpc_chambre_enregistrer`, qui vérifie les droits et l'unicité du
// numéro par boutique.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/chambre.dart';
import 'package:biashara_yangu/services/hotel_service.dart';

class ChambreFormPage extends StatefulWidget {
  const ChambreFormPage({super.key, this.chambre});

  /// Chambre à modifier (`null` = création).
  final Chambre? chambre;

  @override
  State<ChambreFormPage> createState() => _ChambreFormPageState();
}

class _ChambreFormPageState extends State<ChambreFormPage> {
  late final TextEditingController _numeroCtrl;
  late final TextEditingController _typeCtrl;
  late final TextEditingController _capaciteCtrl;
  late final TextEditingController _prixCtrl;
  late final TextEditingController _equipementsCtrl;

  late bool _actif;
  bool _enregistrement = false;

  Chambre? get _chambre => widget.chambre;

  @override
  void initState() {
    super.initState();
    final Chambre? c = widget.chambre;
    _numeroCtrl = TextEditingController(text: c?.numero ?? '');
    _typeCtrl = TextEditingController(text: c?.typeChambre ?? '');
    _capaciteCtrl = TextEditingController(text: (c?.capacite ?? 1).toString());
    _prixCtrl = TextEditingController(
      text: c == null || c.prixNuit == 0 ? '' : _nombre(c.prixNuit),
    );
    _equipementsCtrl = TextEditingController(text: c?.equipements ?? '');
    _actif = c?.actif ?? true;
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _typeCtrl.dispose();
    _capaciteCtrl.dispose();
    _prixCtrl.dispose();
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
    final String numero = _numeroCtrl.text.trim();
    if (numero.isEmpty) {
      _afficherErreur('Le numéro de la chambre est obligatoire.');
      return;
    }

    final int capacite = int.tryParse(_capaciteCtrl.text.trim()) ?? 0;
    if (capacite < 1 || capacite > 50) {
      _afficherErreur('La capacité doit être comprise entre 1 et 50 personnes.');
      return;
    }

    final double prix = _parseMontant(_prixCtrl.text);
    if (prix < 0) {
      _afficherErreur('Le prix par nuit ne peut pas être négatif.');
      return;
    }

    final String equipements = _equipementsCtrl.text.trim();

    setState(() => _enregistrement = true);
    try {
      final Chambre chambre = await HotelService.instance.enregistrerChambre(
        id: _chambre?.id,
        numero: numero,
        typeChambre: _typeCtrl.text.trim(),
        capacite: capacite,
        prixNuit: prix,
        equipements: equipements.isEmpty ? null : equipements,
        actif: _actif,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_chambre == null
              ? 'Chambre ${chambre.numero} créée.'
              : 'Chambre ${chambre.numero} enregistrée.'),
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
    final bool creation = _chambre == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(creation ? 'Nouvelle chambre' : 'Modifier la chambre'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          TextField(
            controller: _numeroCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: _decoration('Numéro *',
                hint: '101, Suite A…', icone: Icons.confirmation_number_rounded),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _typeCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration('Type (facultatif)',
                hint: 'Simple, Double, Suite…', icone: Icons.king_bed_rounded),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _capaciteCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _decoration('Capacité *',
                      icone: Icons.groups_rounded, suffixe: 'pers.'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _prixCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _decoration('Prix / nuit',
                      icone: Icons.payments_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _equipementsCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration('Équipements / notes (facultatif)',
                hint: 'Climatisation, douche, balcon…',
                icone: Icons.room_preferences_rounded),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Chambre active'),
            subtitle: const Text(
              'Une chambre inactive reste dans l\'historique mais n\'est '
              'plus proposée à la réservation.',
            ),
            value: _actif,
            onChanged: (bool valeur) => setState(() => _actif = valeur),
          ),
          if (creation) ...<Widget>[
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.info_outline_rounded,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'La chambre démarre au statut « Libre ». Le statut '
                        'évolue ensuite avec les réservations et le ménage.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
            label: Text(creation ? 'Créer la chambre' : 'Enregistrer'),
          ),
        ],
      ),
    );
  }
}
