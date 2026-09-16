// lib/ui/widgets/primary_loader.dart
//
// Ancien indicateur de chargement — conservé pour compatibilité avec les
// écrans existants (`new_sale_page`, …). Il délègue désormais au loader
// moderne commun : anneau dégradé animé (voir `modern_loader.dart`).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/ui/widgets/modern_loader.dart';

class PrimaryLoader extends StatelessWidget {
  final double size;
  const PrimaryLoader({this.size = 24, super.key});

  @override
  Widget build(BuildContext context) {
    return ModernLoader(
      taille: size,
      epaisseur: size <= 28 ? 2.6 : 3.4,
    );
  }
}
