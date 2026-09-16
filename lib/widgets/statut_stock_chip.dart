// lib/widgets/statut_stock_chip.dart
//
// MODULE 9 — PASTILLE DE STATUT DE STOCK (OK / Faible / Rupture).
//
// Widget partagé par l'écran Stock, le détail article, les alertes et
// l'inventaire : une seule source de vérité pour les couleurs.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/statut_stock.dart';

/// Couleur associée à un statut de stock.
Color couleurStatutStock(StatutStock statut) => switch (statut) {
      StatutStock.rupture => Colors.red.shade700,
      StatutStock.faible => Colors.orange.shade800,
      StatutStock.ok => Colors.green.shade700,
    };

/// Icône associée à un statut de stock.
IconData iconeStatutStock(StatutStock statut) => switch (statut) {
      StatutStock.rupture => Icons.error_rounded,
      StatutStock.faible => Icons.warning_amber_rounded,
      StatutStock.ok => Icons.check_circle_rounded,
    };

/// Pastille colorée « OK », « Faible » ou « Rupture ».
class StatutStockChip extends StatelessWidget {
  const StatutStockChip({super.key, required this.statut});

  final StatutStock statut;

  @override
  Widget build(BuildContext context) {
    final Color couleur = couleurStatutStock(statut);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(iconeStatutStock(statut), size: 13, color: couleur),
          const SizedBox(width: 4),
          Text(
            statut.libelle,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: couleur,
            ),
          ),
        ],
      ),
    );
  }
}
