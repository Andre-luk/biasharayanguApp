// lib/widgets/statut_restaurant_chips.dart
//
// 🍽️ MODULE 16 (phase C3) — puces colorées des statuts restaurant :
// table (libre / occupée / réservée) et commande (saisie → … → encaissée).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/commande.dart';
import 'package:biashara_yangu/models/table_salle.dart';

/// Puce colorée du statut d'une table.
class StatutTableChip extends StatelessWidget {
  const StatutTableChip({
    super.key,
    required this.statut,
    this.compact = false,
  });

  final TableStatut statut;
  final bool compact;

  static Color couleur(TableStatut statut) {
    switch (statut) {
      case TableStatut.libre:
        return const Color(0xFF16A34A);
      case TableStatut.occupee:
        return const Color(0xFFDC2626);
      case TableStatut.reservee:
        return const Color(0xFFF59E0B);
    }
  }

  static IconData icone(TableStatut statut) {
    switch (statut) {
      case TableStatut.libre:
        return Icons.check_circle_rounded;
      case TableStatut.occupee:
        return Icons.people_alt_rounded;
      case TableStatut.reservee:
        return Icons.event_available_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color couleur = StatutTableChip.couleur(statut);
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

/// Puce colorée du statut d'une commande.
class StatutCommandeChip extends StatelessWidget {
  const StatutCommandeChip({
    super.key,
    required this.statut,
    this.compact = false,
  });

  final StatutCommande statut;
  final bool compact;

  static Color couleur(StatutCommande statut) {
    switch (statut) {
      case StatutCommande.ouverte:
        return const Color(0xFF64748B);
      case StatutCommande.envoyee:
        return const Color(0xFFF59E0B);
      case StatutCommande.enPreparation:
        return const Color(0xFFEA580C);
      case StatutCommande.prete:
        return const Color(0xFF2563EB);
      case StatutCommande.servie:
        return const Color(0xFF0D9488);
      case StatutCommande.encaissee:
        return const Color(0xFF16A34A);
      case StatutCommande.annulee:
        return const Color(0xFF9F1239);
    }
  }

  static IconData icone(StatutCommande statut) {
    switch (statut) {
      case StatutCommande.ouverte:
        return Icons.edit_note_rounded;
      case StatutCommande.envoyee:
        return Icons.send_rounded;
      case StatutCommande.enPreparation:
        return Icons.soup_kitchen_rounded;
      case StatutCommande.prete:
        return Icons.notifications_active_rounded;
      case StatutCommande.servie:
        return Icons.room_service_rounded;
      case StatutCommande.encaissee:
        return Icons.check_circle_rounded;
      case StatutCommande.annulee:
        return Icons.cancel_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color couleur = StatutCommandeChip.couleur(statut);
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
