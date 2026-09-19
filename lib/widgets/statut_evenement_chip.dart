// lib/widgets/statut_evenement_chip.dart
import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/evenement.dart';

/// Puce colorée du statut d'un événement (réservé / confirmé / en cours /
/// terminé / annulé).
class StatutEvenementChip extends StatelessWidget {
  const StatutEvenementChip({
    super.key,
    required this.statut,
    this.compact = false,
  });

  final StatutEvenement statut;
  final bool compact;

  /// Couleur associée au statut (partagée avec les cartes et dialogues).
  static Color couleur(StatutEvenement statut) {
    switch (statut) {
      case StatutEvenement.reserve:
        return const Color(0xFFF59E0B);
      case StatutEvenement.confirme:
        return const Color(0xFF16A34A);
      case StatutEvenement.enCours:
        return const Color(0xFF2563EB);
      case StatutEvenement.termine:
        return const Color(0xFF64748B);
      case StatutEvenement.annule:
        return const Color(0xFFDC2626);
    }
  }

  /// Icône associée au statut.
  static IconData icone(StatutEvenement statut) {
    switch (statut) {
      case StatutEvenement.reserve:
        return Icons.event_available_rounded;
      case StatutEvenement.confirme:
        return Icons.verified_rounded;
      case StatutEvenement.enCours:
        return Icons.celebration_rounded;
      case StatutEvenement.termine:
        return Icons.task_alt_rounded;
      case StatutEvenement.annule:
        return Icons.event_busy_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color couleur = StatutEvenementChip.couleur(statut);
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
