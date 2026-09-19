// lib/widgets/statut_reservation_chip.dart
import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/reservation.dart';

/// Puce colorée du statut d'une réservation / séjour.
class StatutReservationChip extends StatelessWidget {
  const StatutReservationChip({
    super.key,
    required this.statut,
    this.compact = false,
  });

  final StatutReservation statut;
  final bool compact;

  /// Couleur associée au statut.
  static Color couleur(StatutReservation statut) {
    switch (statut) {
      case StatutReservation.reservee:
        return const Color(0xFFF59E0B);
      case StatutReservation.enCours:
        return const Color(0xFF2563EB);
      case StatutReservation.terminee:
        return const Color(0xFF16A34A);
      case StatutReservation.annulee:
        return const Color(0xFF64748B);
    }
  }

  /// Icône associée au statut.
  static IconData icone(StatutReservation statut) {
    switch (statut) {
      case StatutReservation.reservee:
        return Icons.schedule_rounded;
      case StatutReservation.enCours:
        return Icons.meeting_room_rounded;
      case StatutReservation.terminee:
        return Icons.check_circle_rounded;
      case StatutReservation.annulee:
        return Icons.cancel_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color couleur = StatutReservationChip.couleur(statut);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: couleur.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icone(statut), size: compact ? 13 : 15, color: couleur),
          const SizedBox(width: 4),
          Text(
            statut.libelle,
            style: TextStyle(
              color: couleur,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 12.5,
            ),
          ),
        ],
      ),
    );
  }
}
