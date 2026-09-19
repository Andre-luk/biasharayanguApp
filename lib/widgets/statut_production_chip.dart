// lib/widgets/statut_production_chip.dart
import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/production.dart';

/// Puce colorée du statut d'une production (en cours / terminée / annulée).
class StatutProductionChip extends StatelessWidget {
  const StatutProductionChip({
    super.key,
    required this.statut,
    this.compact = false,
  });

  final StatutProduction statut;
  final bool compact;

  /// Couleur associée au statut.
  static Color couleur(StatutProduction statut) {
    switch (statut) {
      case StatutProduction.enCours:
        return const Color(0xFFF59E0B);
      case StatutProduction.terminee:
        return const Color(0xFF16A34A);
      case StatutProduction.annulee:
        return const Color(0xFFDC2626);
    }
  }

  /// Icône associée au statut.
  static IconData icone(StatutProduction statut) {
    switch (statut) {
      case StatutProduction.enCours:
        return Icons.bakery_dining_rounded;
      case StatutProduction.terminee:
        return Icons.task_alt_rounded;
      case StatutProduction.annulee:
        return Icons.cancel_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color couleur = StatutProductionChip.couleur(statut);
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
