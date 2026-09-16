// lib/ui/widgets/modern_loader.dart
//
// ⏳ INDICATEURS DE CHARGEMENT MODERNES
//
//   • `ModernLoader`      — anneau animé (dégradé) utilisé aux lancements et
//                           pour les chargements pleine page ;
//   • `BarreProgressionModerne` — fine barre dégradée qui balaie l'écran ;
//   • `Squelette` / `SquelettePulse` — placeholders gris animés pendant que
//                           les données arrivent (au lieu d'un spinner nu).
//
// Les animations sont isolées dans des `RepaintBoundary` : elles ne
// déclenchent JAMAIS de reconstruction du reste de la page (performance).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:biashara_yangu/ui/theme/app_theme.dart';

/// Anneau de chargement dégradé, moderne.
class ModernLoader extends StatefulWidget {
  const ModernLoader({
    super.key,
    this.taille = 40,
    this.epaisseur = 4,
    this.couleur,
    this.couleurSecondaire,
    this.legende,
  });

  /// Diamètre de l'anneau, en pixels logiques.
  final double taille;

  /// Épaisseur du trait.
  final double epaisseur;

  /// Couleur principale (défaut : couleur primaire du thème).
  final Color? couleur;

  /// Couleur de la pointe (défaut : orange de la marque).
  final Color? couleurSecondaire;

  /// Texte optionnel affiché sous l'anneau.
  final String? legende;

  @override
  State<ModernLoader> createState() => _ModernLoaderState();
}

class _ModernLoaderState extends State<ModernLoader>
    with TickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
    lowerBound: 0.90,
    upperBound: 1.0,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _rotation.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color couleur = widget.couleur ?? scheme.primary;
    final Color couleurSecondaire = widget.couleurSecondaire ?? AppCouleurs.orange;

    final Widget anneau = RepaintBoundary(
      child: ScaleTransition(
        scale: _pulse,
        child: RotationTransition(
          turns: _rotation,
          child: CustomPaint(
            size: Size.square(widget.taille),
            painter: _PeintreAnneau(
              couleur: couleur,
              couleurSecondaire: couleurSecondaire,
              epaisseur: widget.epaisseur,
            ),
          ),
        ),
      ),
    );

    if (widget.legende == null) return anneau;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        anneau,
        const SizedBox(height: 16),
        Text(
          widget.legende!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _PeintreAnneau extends CustomPainter {
  _PeintreAnneau({
    required this.couleur,
    required this.couleurSecondaire,
    required this.epaisseur,
  });

  final Color couleur;
  final Color couleurSecondaire;
  final double epaisseur;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect zone =
        (Offset.zero & size).deflate(epaisseur / 2 + 0.5);

    // Piste de fond très discrète.
    canvas.drawArc(
      zone,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = epaisseur
        ..strokeCap = StrokeCap.round
        ..color = couleur.withValues(alpha: 0.13),
    );

    // Arc en dégradé : transparent → couleur → orange.
    final Paint trace = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = epaisseur
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: <Color>[
          couleur.withValues(alpha: 0),
          couleur.withValues(alpha: 0.65),
          couleurSecondaire,
        ],
        stops: const <double>[0.0, 0.6, 1.0],
      ).createShader(zone);

    canvas.drawArc(zone, -math.pi / 2, math.pi * 1.55, false, trace);
  }

  @override
  bool shouldRepaint(_PeintreAnneau ancien) =>
      ancien.couleur != couleur ||
      ancien.couleurSecondaire != couleurSecondaire ||
      ancien.epaisseur != epaisseur;
}

/// Fine barre dégradée indéterminée (haut de page pendant un rechargement).
class BarreProgressionModerne extends StatefulWidget {
  const BarreProgressionModerne({super.key, this.hauteur = 3});

  final double hauteur;

  @override
  State<BarreProgressionModerne> createState() =>
      _BarreProgressionModerneState();
}

class _BarreProgressionModerneState extends State<BarreProgressionModerne>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controleur = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: SizedBox(
        height: widget.hauteur,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _controleur,
          builder: (BuildContext context, Widget? child) {
            return CustomPaint(
              painter: _PeintreBarre(
                progression: _controleur.value,
                couleur: scheme.primary,
                couleurSecondaire: AppCouleurs.orange,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PeintreBarre extends CustomPainter {
  _PeintreBarre({
    required this.progression,
    required this.couleur,
    required this.couleurSecondaire,
  });

  final double progression;
  final Color couleur;
  final Color couleurSecondaire;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fond = Paint()..color = couleur.withValues(alpha: 0.12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height),
      ),
      fond,
    );

    final double largeur = size.width * 0.35;
    final double gauche = (size.width + largeur) * progression - largeur;
    final Rect segment = Rect.fromLTWH(gauche, 0, largeur, size.height);

    canvas.drawRRect(
      RRect.fromRectAndRadius(segment, Radius.circular(size.height)),
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[couleur.withValues(alpha: 0), couleur, couleurSecondaire],
        ).createShader(segment),
    );
  }

  @override
  bool shouldRepaint(_PeintreBarre ancien) =>
      ancien.progression != progression ||
      ancien.couleur != couleur ||
      ancien.couleurSecondaire != couleurSecondaire;
}

/// Bloc gris arrondi remplaçant un contenu pendant son chargement.
class Squelette extends StatelessWidget {
  const Squelette({
    super.key,
    this.largeur,
    this.hauteur = 14,
    this.rayon = 10,
  });

  final double? largeur;
  final double hauteur;
  final double rayon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: largeur,
      height: hauteur,
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(rayon),
      ),
    );
  }
}

/// Fait « respirer » un groupe de squelettes (une seule animation partagée).
class SquelettePulse extends StatefulWidget {
  const SquelettePulse({super.key, required this.child});

  final Widget child;

  @override
  State<SquelettePulse> createState() => _SquelettePulseState();
}

class _SquelettePulseState extends State<SquelettePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controleur = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
    upperBound: 1.0,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(opacity: _controleur, child: widget.child),
    );
  }
}
