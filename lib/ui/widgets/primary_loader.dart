// lib/ui/widgets/primary_loader.dart
import 'package:flutter/material.dart';

class PrimaryLoader extends StatelessWidget {
  final double size;
  const PrimaryLoader({this.size = 24, super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2.4,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
