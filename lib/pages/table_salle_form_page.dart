// lib/pages/table_salle_form_page.dart
//
// 🍽️ MODULE 16 (phase C3) — RESTAURANT : FORMULAIRE DE TABLE.
//
// Création (`tables/créer`) ou modification (`tables/modifier`) via la RPC
// `rpc_table_enregistrer` (unicité du numéro par boutique).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/table_salle.dart';
import 'package:biashara_yangu/services/restaurant_service.dart';

class TableSalleFormPage extends StatefulWidget {
  const TableSalleFormPage({super.key, this.table});

  /// Table à modifier (`null` = création).
  final TableSalle? table;

  @override
  State<TableSalleFormPage> createState() => _TableSalleFormPageState();
}

class _TableSalleFormPageState extends State<TableSalleFormPage> {
  late final TextEditingController _numeroCtrl;
  late final TextEditingController _zoneCtrl;
  late final TextEditingController _placesCtrl;

  late bool _actif;
  bool _enregistrement = false;

  TableSalle? get _table => widget.table;

  @override
  void initState() {
    super.initState();
    final TableSalle? t = widget.table;
    _numeroCtrl = TextEditingController(text: t?.numero ?? '');
    _zoneCtrl = TextEditingController(text: t?.zone ?? '');
    _placesCtrl = TextEditingController(text: (t?.places ?? 2).toString());
    _actif = t?.actif ?? true;
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _zoneCtrl.dispose();
    _placesCtrl.dispose();
    super.dispose();
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
      _afficherErreur('Le numéro de la table est obligatoire.');
      return;
    }

    final int places = int.tryParse(_placesCtrl.text.trim()) ?? 0;
    if (places < 1 || places > 50) {
      _afficherErreur('Le nombre de places doit être compris entre 1 et 50.');
      return;
    }

    setState(() => _enregistrement = true);
    try {
      final TableSalle table = await RestaurantService.instance.enregistrerTable(
        id: _table?.id,
        numero: numero,
        zone: _zoneCtrl.text.trim(),
        places: places,
        actif: _actif,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_table == null
              ? 'Table ${table.numero} créée.'
              : 'Table ${table.numero} enregistrée.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      Navigator.of(context).pop(true);
    } on RestaurantServiceException catch (e) {
      if (mounted) _afficherErreur(e.message);
    } catch (e) {
      if (mounted) _afficherErreur('Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool creation = _table == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(creation ? 'Nouvelle table' : 'Modifier la table'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          TextField(
            controller: _numeroCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: _decoration('Numéro *',
                hint: '5, T-12, VIP…',
                icone: Icons.confirmation_number_rounded),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _zoneCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration('Zone (facultatif)',
                hint: 'Salle, Terrasse, Étage…',
                icone: Icons.map_rounded),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _placesCtrl,
            keyboardType: TextInputType.number,
            decoration: _decoration('Places *',
                icone: Icons.groups_rounded, suffixe: 'pers.'),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Table active'),
            subtitle: const Text(
              'Une table inactive reste dans l\'historique mais n\'est plus '
              'proposée aux commandes.',
            ),
            value: _actif,
            onChanged: (bool valeur) => setState(() => _actif = valeur),
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
            label: Text(creation ? 'Créer la table' : 'Enregistrer'),
          ),
        ],
      ),
    );
  }
}
