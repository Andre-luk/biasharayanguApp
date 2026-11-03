// lib/widgets/decaissement_caisse_dialogue.dart
//
// MODULE 10 — DIALOGUE « DÉCAISSEMENT » DE LA CAISSE.
//
// Enregistre une SORTIE de caisse (dépense) directement depuis l'écran
// « Caisse » : montant, catégorie, motif obligatoire et date.
//
// ⚠️ La caisse est CALCULÉE par le serveur : ce dialogue n'écrit jamais de
//    solde. Il crée une dépense via `rpc_depense_creer` (droit
//    `depenses/creer`, tracé dans `journal_audit`), et le solde de caisse
//    diminue donc automatiquement au rechargement.
//
// Utilisé par `CaissePage` (et réutilisable par tout écran de caisse).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/services/finance_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

/// Ouvre le dialogue de décaissement.
///
/// Renvoie `true` si une dépense a effectivement été enregistrée.
Future<bool> afficherDecaissementCaisse(
  BuildContext context, {
  double? soldeActuel,
}) async {
  final bool? enregistre = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogueContext) =>
        _DialogueDecaissement(soldeActuel: soldeActuel),
  );
  return enregistre == true;
}

class _DialogueDecaissement extends StatefulWidget {
  const _DialogueDecaissement({this.soldeActuel});

  final double? soldeActuel;

  @override
  State<_DialogueDecaissement> createState() => _DialogueDecaissementState();
}

class _DialogueDecaissementState extends State<_DialogueDecaissement> {
  final FinanceService _finance = FinanceService.instance;

  final TextEditingController _montantCtrl = TextEditingController();
  final TextEditingController _motifCtrl = TextEditingController();

  String _categorie = 'transport';
  DateTime _date = DateTime.now();
  String? _erreur;
  bool _enregistrement = false;

  @override
  void dispose() {
    _montantCtrl.dispose();
    _motifCtrl.dispose();
    super.dispose();
  }

  double get _montant => parseMontantSaisi(_montantCtrl.text) ?? 0;

  Future<void> _choisirDate() async {
    final DateTime maintenant = DateTime.now();
    final DateTime? choix = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(maintenant.year - 2),
      lastDate: DateTime(maintenant.year, maintenant.month, maintenant.day),
      helpText: 'Date du décaissement',
    );
    if (choix != null) setState(() => _date = choix);
  }

  Future<void> _enregistrer() async {
    final String motif = _motifCtrl.text.trim();

    if (_montant <= 0) {
      setState(() => _erreur = 'Saisissez un montant supérieur à zéro.');
      return;
    }
    if (motif.length < 2) {
      setState(() => _erreur = 'Indiquez le motif du décaissement.');
      return;
    }

    final double? solde = widget.soldeActuel;
    if (solde != null && _montant > solde) {
      final bool continuer = await _confirmerDepassement(solde);
      if (!continuer) return;
    }

    setState(() {
      _enregistrement = true;
      _erreur = null;
    });

    try {
      await _finance.creerDepense(
        motif: motif,
        montant: _montant,
        date: _date,
        categorie: _categorie,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FinanceServiceException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  Future<bool> _confirmerDepassement(double solde) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext confirmContext) => AlertDialog(
        title: const Text('Solde insuffisant'),
        content: Text(
          'Le solde de caisse est de ${formatMontant(solde)} : il ne couvre '
          'pas ce décaissement de ${formatMontant(_montant)}.\n\n'
          'La sortie sera quand même enregistrée et la caisse passera en '
          'négatif.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(confirmContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(confirmContext).pop(true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double? solde = widget.soldeActuel;

    return AlertDialog(
      title: const Text('Nouveau décaissement'),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        solde == null
                            ? 'Sortie de caisse — le solde sera recalculé.'
                            : 'Solde disponible : ${formatMontant(solde)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _montantCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) {
                  if (_erreur != null) setState(() => _erreur = null);
                },
                decoration: InputDecoration(
                  labelText: 'Montant *',
                  hintText: 'Ex. : 15 000',
                  prefixIcon: const Icon(Icons.money_off_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _motifCtrl,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  if (_erreur != null) setState(() => _erreur = null);
                },
                decoration: InputDecoration(
                  labelText: 'Motif *',
                  hintText: 'Ex. : carburant livraison',
                  prefixIcon: const Icon(Icons.edit_note_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.event_rounded),
                  title: const Text('Date'),
                  subtitle: Text(formatDate(_date)),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: _choisirDate,
                ),
              ),
              if (_erreur != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _erreur!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _enregistrement ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _enregistrement ? null : _enregistrer,
          icon: _enregistrement
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.south_east_rounded, size: 18),
          label: Text(_enregistrement ? 'Enregistrement…' : 'Décaisser'),
        ),
      ],
    );
  }
}
