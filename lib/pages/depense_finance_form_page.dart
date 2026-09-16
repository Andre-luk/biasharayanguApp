// lib/pages/depense_finance_form_page.dart
//
// MODULE 10 — FORMULAIRE « NOUVELLE DÉPENSE ».
//
// Motif, montant, catégorie et date — l'écriture passe par `rpc_depense_creer`
// (droit `depenses/creer`, journalisée dans `journal_audit`).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/depense_finance.dart';
import 'package:biashara_yangu/services/finance_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class DepenseFinanceFormPage extends StatefulWidget {
  const DepenseFinanceFormPage({super.key});

  @override
  State<DepenseFinanceFormPage> createState() =>
      _DepenseFinanceFormPageState();
}

class _DepenseFinanceFormPageState extends State<DepenseFinanceFormPage> {
  final FinanceService _finance = FinanceService.instance;

  final TextEditingController _motifCtrl = TextEditingController();
  final TextEditingController _montantCtrl = TextEditingController();

  String _categorie = 'autre';
  DateTime _date = DateTime.now();
  bool _enregistrement = false;

  @override
  void dispose() {
    _motifCtrl.dispose();
    _montantCtrl.dispose();
    super.dispose();
  }

  double get _montant {
    final String texte =
        _montantCtrl.text.replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(texte) ?? 0;
  }

  Future<void> _choisirDate() async {
    final DateTime maintenant = DateTime.now();
    final DateTime? choix = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(maintenant.year - 2),
      lastDate: DateTime(maintenant.year, maintenant.month, maintenant.day),
      helpText: 'Date de la dépense',
    );
    if (choix != null) setState(() => _date = choix);
  }

  Future<void> _enregistrer() async {
    final String motif = _motifCtrl.text.trim();
    if (motif.length < 2) {
      _afficherErreur('Indiquez le motif de la dépense (2 caractères minimum).');
      return;
    }
    if (_montant <= 0) {
      _afficherErreur('Le montant de la dépense doit être supérieur à zéro.');
      return;
    }

    setState(() => _enregistrement = true);
    try {
      final DepenseFinance depense = await _finance.creerDepense(
        motif: motif,
        montant: _montant,
        date: _date,
        categorie: _categorie,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Dépense enregistrée : ${depense.motif} — ${formatMontant(depense.montant)}',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      Navigator.of(context).pop(true);
    } on FinanceServiceException catch (e) {
      if (!mounted) return;
      _afficherErreur(e.message);
    } catch (e) {
      if (!mounted) return;
      _afficherErreur('Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  void _afficherErreur(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nouvelle dépense',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _motifCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Motif *',
              hintText: 'Ex. : transport marchandises, loyer du mois…',
              prefixIcon: const Icon(Icons.edit_note_rounded),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _montantCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Montant (CDF) *',
              hintText: 'Ex. : 15 000',
              prefixIcon: const Icon(Icons.payments_rounded),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          AppDropdownField<String>(
            label: 'Catégorie',
            value: _categorie,
            prefixIcon: Icons.label_outline_rounded,
            items: FinanceService.categoriesParDefaut
                .map((String categorie) => DropdownMenuItem<String>(
                      value: categorie,
                      child: Text(categorie),
                    ))
                .toList(growable: false),
            onChanged: (String? valeur) {
              if (valeur != null) setState(() => _categorie = valeur);
            },
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: ListTile(
              leading: const Icon(Icons.event_rounded),
              title: const Text('Date de la dépense'),
              subtitle: Text(formatDate(_date)),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: _choisirDate,
            ),
          ),
          const SizedBox(height: 24),
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
              label: Text(
                _enregistrement ? 'Enregistrement…' : 'Enregistrer la dépense',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Les dépenses sont des SORTIES de caisse : elles apparaissent dans '
            'l\'historique de la caisse et réduisent le bénéfice net.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
