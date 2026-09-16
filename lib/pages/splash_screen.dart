// lib/pages/splash_screen.dart
//
// ✨ ÉCRAN DE LANCEMENT MODERNE
//
// Affiché par `main.dart` pendant l'initialisation de l'application
// (session, base locale, permissions, abonnement, synchronisation).
//
// C'est un simple habillage : il ne navigue PAS lui-même — le démarrage est
// orchestré par `BiasharaApp._handleStartup()`. Une fois prêt, l'écran
// disparaît en fondu pour révéler l'application (aucun clignotement).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entree = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final Animation<double> _fondu = CurvedAnimation(
    parent: _entree,
    curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
  );

  late final Animation<double> _echelle = Tween<double>(begin: 0.88, end: 1.0)
      .animate(CurvedAnimation(
    parent: _entree,
    curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack),
  ));

  @override
  void initState() {
    super.initState();
    _entree.forward();
  }

  @override
  void dispose() {
    _entree.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool sombre = theme.brightness == Brightness.dark;

    return Material(
      // Fond opaque : le splash recouvre totalement l'application en dessous.
      color: sombre ? AppCouleurs.fondSombre : Colors.white,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: sombre ? AppDegrades.fondSombre : AppDegrades.fondClair,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // — Cercles décoratifs (pure décoration, non interactifs) —
            Positioned(
              top: -90,
              right: -70,
              child: _Cercle(
                taille: 240,
                couleur: AppCouleurs.marine.withValues(alpha: 0.07),
              ),
            ),
            Positioned(
              bottom: -110,
              left: -80,
              child: _Cercle(
                taille: 280,
                couleur: AppCouleurs.orange.withValues(alpha: 0.10),
              ),
            ),
            Positioned(
              top: 120,
              left: -40,
              child: _Cercle(
                taille: 110,
                couleur: AppCouleurs.marineClair.withValues(alpha: 0.06),
              ),
            ),

            // — Contenu centré —
            Center(
              child: FadeTransition(
                opacity: _fondu,
                child: ScaleTransition(
                  scale: _echelle,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _Logo(theme: theme),
                      const SizedBox(height: 28),
                      Text(
                        'Biashara Yangu',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Gérez votre commerce en toute simplicité',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 44),
                    ],
                  ),
                ),
              ),
            ),

            // — Indicateur de chargement + mention de bas de page —
            Align(
              alignment: const Alignment(0, 0.62),
              child: FadeTransition(
                opacity: _fondu,
                child: const ModernLoader(
                  taille: 42,
                  legende: 'Chargement sécurisé…',
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Text(
                  'Biashara Yangu Mobile • v1.0.0',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.8),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo de l'application dans une « pastille » blanche flottante.
class _Logo extends StatelessWidget {
  const _Logo({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(36),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppCouleurs.marine.withValues(alpha: 0.16),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.asset(
          'assets/Biashara_app_off-.png',
          height: 132,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// Disque translucide décoratif.
class _Cercle extends StatelessWidget {
  const _Cercle({required this.taille, required this.couleur});

  final double taille;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 6,
      child: Container(
        width: taille,
        height: taille,
        decoration: BoxDecoration(
          color: couleur,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}