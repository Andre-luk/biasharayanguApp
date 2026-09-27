// lib/pages/facture_sejour_page.dart
//
// 🏨 MODULE 16 (phase C2) — HÔTEL : FACTURE DE SÉJOUR.
//
// Document construit localement depuis la réservation (aucun appel réseau) :
// référence, client, chambre, dates, nuits × prix, avance et reste à payer.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/reservation.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/statut_reservation_chip.dart';

class FactureSejourPage extends StatelessWidget {
  const FactureSejourPage({super.key, this.reservation});

  /// Séjour facturé (transmis par le planning ou la réception).
  final Reservation? reservation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Reservation? sejour = reservation;

    if (sejour == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Facture de séjour')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aucun séjour sélectionné.\n'
              'Ouvrez la facture depuis le planning des réservations.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final FactureSejour facture = FactureSejour.depuisReservation(sejour);

    return Scaffold(
      appBar: AppBar(title: const Text('Facture de séjour')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.receipt_long_rounded,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'FACTURE DE SÉJOUR',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      StatutReservationChip(
                          statut: sejour.statut, compact: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Référence ${facture.reference} • '
                    'émise le ${formatDate(DateTime.now())}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Divider(height: 24),
                  _ligne(theme, 'Client',
                      sejour.clientTelephone == null ||
                              sejour.clientTelephone!.isEmpty
                          ? sejour.clientNom
                          : '${sejour.clientNom} • ${sejour.clientTelephone}'),
                  _ligne(theme, 'Chambre',
                      sejour.chambreNumero.isEmpty ? '—' : sejour.chambreNumero),
                  _ligne(
                    theme,
                    'Séjour',
                    '${formatDate(sejour.dateArrivee)} → '
                    '${formatDate(sejour.dateDepart)} '
                    '(${sejour.nuits} nuit${sejour.nuits > 1 ? 's' : ''}, '
                    '${sejour.nbPersonnes} pers.)',
                  ),
                  const Divider(height: 24),
                  for (final LigneFactureSejour ligne in facture.lignes)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // ♿ AUDIT FINAL — libellés longs : sans `Expanded`, le
                        // montant était poussé hors de l'écran sur un téléphone
                        // étroit (débordement « BOTTOM OVERFLOWED »).
                        Expanded(
                          child: Text(ligne.libelle,
                              style: theme.textTheme.bodyMedium),
                        ),
                        const SizedBox(width: 12),
                        Text(formatMontant(ligne.montant),
                            style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text('TOTAL',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatMontant(facture.total),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Expanded(child: Text('Déjà payé')),
                      const SizedBox(width: 12),
                      Text(
                        formatMontant(facture.paye),
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text('Reste à payer',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        facture.solde > 0
                            ? formatMontant(facture.solde)
                            : 'Soldé',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: facture.solde > 0
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (sejour.note != null && sejour.note!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.sticky_note_2_rounded),
                title: const Text('Note'),
                subtitle: Text(sejour.note!),
              ),
            ),
          ],
          if (sejour.statut == StatutReservation.annulee &&
              sejour.motifAnnulation != null &&
              sejour.motifAnnulation!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Réservation annulée'),
                subtitle: Text('Motif : ${sejour.motifAnnulation}'),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Center(
            child: Text(
              'Merci de votre séjour.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligne(ThemeData theme, String libelle, String valeur) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(libelle, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(valeur, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
