// lib/widgets/hotel_dialogues.dart
//
// 🏨 MODULE 16 (phase C2) — HÔTEL : DIALOGUES D'ACTION DES SÉJOURS.
//
// Encaissement (avance / acompte), départ avec règlement du solde,
// annulation motivée et confirmation d'arrivée : partagés par le planning
// des réservations ET l'écran Réception.
//
// Chaque fonction renvoie `true` quand l'action a été exécutée : l'écran
// appelant recharge alors ses données.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/reservation.dart';
import 'package:biashara_yangu/services/hotel_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

/// Saisie montant + mode de paiement.
class _MontantEtMode {
  const _MontantEtMode(this.montant, this.mode);

  final double montant;
  final String mode;
}

double _parseMontant(String texte) {
  return double.tryParse(texte.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
}

String _nombre(double valeur) => valeur == valeur.roundToDouble()
    ? valeur.toStringAsFixed(0)
    : valeur.toString();

void _message(BuildContext context, String texte, {bool erreur = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(texte),
      backgroundColor: erreur ? Colors.red.shade700 : null,
    ),
  );
}

/// Encaisse une avance ou un acompte (montant ≤ reste à payer).
Future<bool> dialogueEncaisserSejour(
  BuildContext context, {
  required String reservationId,
  required String clientNom,
  required double solde,
  required HotelService service,
}) async {
  if (solde <= 0) {
    _message(context, 'Ce séjour est déjà entièrement payé.');
    return false;
  }

  final _MontantEtMode? saisie = await _dialogueMontantEtMode(
    context,
    titre: 'Encaisser un séjour',
    sousTitre: '$clientNom • reste à payer ${formatMontant(solde)}',
    maximum: solde,
    montantInitial: solde,
    labelMontant: 'Montant encaissé',
  );
  if (saisie == null || !context.mounted) return false;

  try {
    final Reservation reservation = await service.encaisser(
      reservationId,
      saisie.montant,
      modePaiement: saisie.mode,
    );
    if (!context.mounted) return true;
    _message(
      context,
      'Encaissé : ${formatMontant(saisie.montant)} • solde restant '
      '${formatMontant(reservation.solde)}.',
    );
    return true;
  } on HotelServiceException catch (e) {
    if (context.mounted) _message(context, e.message, erreur: true);
    return false;
  }
}

/// Enregistre le départ : solde encaissé puis chambre « à nettoyer ».
Future<bool> dialogueCheckoutSejour(
  BuildContext context, {
  required String reservationId,
  required String clientNom,
  required double solde,
  required HotelService service,
}) async {
  double montant = 0;
  String mode = 'especes';

  if (solde > 0) {
    final _MontantEtMode? saisie = await _dialogueMontantEtMode(
      context,
      titre: 'Enregistrer le départ',
      sousTitre: '$clientNom • reste à payer ${formatMontant(solde)}',
      maximum: solde,
      montantInitial: solde,
      labelMontant: 'Solde encaissé',
      labelValider: 'Départ + encaissement',
    );
    if (saisie == null || !context.mounted) return false;
    montant = saisie.montant;
    mode = saisie.mode;
  } else {
    final bool confirme = await _confirmation(
      context,
      titre: 'Enregistrer le départ de $clientNom ?',
      message:
          'Le séjour sera clôturé et la chambre passera « à nettoyer ».',
      labelValider: 'Enregistrer le départ',
    );
    if (!confirme || !context.mounted) return false;
  }

  try {
    await service.checkout(
      reservationId,
      montantPaye: montant > 0 ? montant : null,
      modePaiement: mode,
    );
    if (!context.mounted) return true;
    _message(
      context,
      'Départ enregistré'
      '${montant > 0 ? ' • ${formatMontant(montant)} encaissés' : ''} '
      '• chambre à nettoyer.',
    );
    return true;
  } on HotelServiceException catch (e) {
    if (context.mounted) _message(context, e.message, erreur: true);
    return false;
  }
}

/// Confirme puis enregistre l'arrivée du client (check-in).
Future<bool> confirmerCheckin(
  BuildContext context, {
  required String reservationId,
  required String clientNom,
  required String chambre,
  required HotelService service,
}) async {
  final bool confirme = await _confirmation(
    context,
    titre: 'Arrivée de $clientNom ?',
    message: 'Chambre $chambre : le séjour passera « en cours » et la '
        'chambre « occupée ».',
    labelValider: 'Enregistrer l\'arrivée',
  );
  if (!confirme || !context.mounted) return false;

  try {
    await service.checkin(reservationId);
    if (!context.mounted) return true;
    _message(context, 'Arrivée enregistrée (chambre $chambre).');
    return true;
  } on HotelServiceException catch (e) {
    if (context.mounted) _message(context, e.message, erreur: true);
    return false;
  }
}

/// Annule une réservation en attente (motif facultatif).
Future<bool> dialogueAnnulerSejour(
  BuildContext context, {
  required String reservationId,
  required String clientNom,
  required HotelService service,
}) async {
  final TextEditingController motifCtrl = TextEditingController();

  final String? motif = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogueContext) => AlertDialog(
      title: Text('Annuler la réservation de $clientNom ?'),
      content: TextField(
        controller: motifCtrl,
        decoration: InputDecoration(
          labelText: 'Motif (facultatif)',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogueContext).pop(),
          child: const Text('Retour'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogueContext).pop(motifCtrl.text.trim()),
          child: const Text('Annuler la réservation'),
        ),
      ],
    ),
  );
  motifCtrl.dispose();

  if (motif == null || !context.mounted) return false;

  try {
    await service.annuler(
      reservationId,
      motif: motif.isEmpty ? null : motif,
    );
    if (!context.mounted) return true;
    _message(context, 'Réservation annulée.');
    return true;
  } on HotelServiceException catch (e) {
    if (context.mounted) _message(context, e.message, erreur: true);
    return false;
  }
}

// ---------------------------------------------------------------------------
// OUTILS INTERNES
// ---------------------------------------------------------------------------

Future<bool> _confirmation(
  BuildContext context, {
  required String titre,
  required String message,
  required String labelValider,
}) async {
  final bool? confirme = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogueContext) => AlertDialog(
      title: Text(titre),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogueContext).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogueContext).pop(true),
          child: Text(labelValider),
        ),
      ],
    ),
  );
  return confirme == true;
}

Future<_MontantEtMode?> _dialogueMontantEtMode(
  BuildContext context, {
  required String titre,
  required String sousTitre,
  required double maximum,
  required double montantInitial,
  required String labelMontant,
  String labelValider = 'Valider',
}) async {
  final TextEditingController montantCtrl = TextEditingController(
    text: montantInitial <= 0 ? '' : _nombre(montantInitial),
  );
  String mode = 'especes';
  String? erreur;

  final _MontantEtMode? resultat = await showDialog<_MontantEtMode>(
    context: context,
    builder: (BuildContext dialogueContext) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setEtat) => AlertDialog(
        title: Text(titre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(sousTitre, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: montantCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: labelMontant,
                errorText: erreur,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            AppDropdownField<String>(
              label: 'Mode de paiement',
              value: mode,
              items: HotelService.modesPaiement.entries
                  .map(
                    (MapEntry<String, String> e) => DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(e.value),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (String? valeur) =>
                  setEtat(() => mode = valeur ?? 'especes'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogueContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final double montant = _parseMontant(montantCtrl.text);
              if (montant <= 0) {
                setEtat(() => erreur = 'Montant invalide.');
                return;
              }
              if (maximum > 0 && montant > maximum + 0.001) {
                setEtat(() =>
                    erreur = 'Maximum ${formatMontant(maximum)}.');
                return;
              }
              Navigator.of(dialogueContext)
                  .pop(_MontantEtMode(montant, mode));
            },
            child: Text(labelValider),
          ),
        ],
      ),
    ),
  );

  montantCtrl.dispose();
  return resultat;
}
