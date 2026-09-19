// lib/widgets/statut_chambre_chip.dart
import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/chambre.dart';

/// Puce colorée du statut d'une chambre (libre / réservée / occupée /
/// à nettoyer).
class StatutChambreChip extends StatelessWidget {
  const StatutChambreChip({
    super.key,
    required this.statut,
    this.compact = false,
  });

  final ChambreStatut statut;
  final bool compact;

  /// Couleur associée au statut (partagée avec les cartes et dialogues).
  static Color couleur(ChambreStatut statut) {
    switch (statut) {
      case ChambreStatut.libre:
        return const Color(0xFF16A34A);
      case ChambreStatut.reservee:
        return const Color(0xFFF59E0B);
      case ChambreStatut.occupee:
        return const Color(0xFFDC2626);
      case ChambreStatut.aNettoyer:
        return const Color(0xFF0284C7);
    }
  }

  /// Icône associée au statut.
  static IconData icone(ChambreStatut statut) {
    switch (statut) {
      case ChambreStatut.libre:
        return Icons.check_circle_rounded;
      case ChambreStatut.reservee:
        return Icons.event_available_rounded;
      case ChambreStatut.occupee:
        return Icons.person_rounded;
      case ChambreStatut.aNettoyer:
        return Icons.cleaning_services_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color couleur = StatutChambreChip.couleur(statut);
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
