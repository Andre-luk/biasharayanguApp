// lib/widgets/statut_abonnement_chip.dart
import 'package:flutter/material.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';

/// Badge coloré représentant le statut d'abonnement d'une entreprise.
///
/// Les couleurs sont centralisées ici : les écrans ne doivent jamais coder en
/// dur une couleur liée à un [StatutAbonnement].
class StatutAbonnementChip extends StatelessWidget {
  const StatutAbonnementChip({
    super.key,
    required this.statut,
    this.compact = false,
  });

  final StatutAbonnement statut;

  /// Réduit la taille du badge (utilisé dans les listes denses).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final _PaletteStatut palette = _PaletteStatut.pour(statut);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: palette.fond,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.bordure),
      ),
      child: Text(
        statut.libelle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.texte,
          fontSize: compact ? 10.5 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Couleurs associées à un statut (valeurs fixes de la palette Material,
/// indépendantes du thème clair/sombre et sans usage de `withOpacity`).
class _PaletteStatut {
  const _PaletteStatut({
    required this.fond,
    required this.texte,
    required this.bordure,
  });

  final Color fond;
  final Color texte;
  final Color bordure;

  static _PaletteStatut pour(StatutAbonnement statut) {
    switch (statut) {
      case StatutAbonnement.essai7j:
        return const _PaletteStatut(
          fond: Color(0xFFFFF3E0),
          texte: Color(0xFFE65100),
          bordure: Color(0xFFFFCC80),
        );
      case StatutAbonnement.actif:
        return const _PaletteStatut(
          fond: Color(0xFFE8F5E9),
          texte: Color(0xFF2E7D32),
          bordure: Color(0xFFA5D6A7),
        );
      case StatutAbonnement.expire:
        return const _PaletteStatut(
          fond: Color(0xFFFFEBEE),
          texte: Color(0xFFC62828),
          bordure: Color(0xFFEF9A9A),
        );
      case StatutAbonnement.suspendu:
        return const _PaletteStatut(
          fond: Color(0xFFEEEEEE),
          texte: Color(0xFF424242),
          bordure: Color(0xFFBDBDBD),
        );
      case StatutAbonnement.enAttenteComplement:
        return const _PaletteStatut(
          fond: Color(0xFFF3E5F5),
          texte: Color(0xFF6A1B9A),
          bordure: Color(0xFFCE93D8),
        );
      case StatutAbonnement.inconnu:
        return const _PaletteStatut(
          fond: Color(0xFFECEFF1),
          texte: Color(0xFF455A64),
          bordure: Color(0xFFB0BEC5),
        );
    }
  }
}
