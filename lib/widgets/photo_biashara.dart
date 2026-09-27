// lib/widgets/photo_biashara.dart
//
// 🛒 MODULE 19 — VISUEL TOLÉRANT (photo d'article, logo, devanture).
//
// Les photos du catalogue public vivent dans Supabase Storage (bucket public
// « articles » ou « boutiques »). Elles peuvent être absentes, ou
// momentanément indisponibles (réseau lent) : l'interface ne doit jamais
// afficher un rectangle rouge ni bloquer le visiteur.
//
// ⚠️ Un article SANS photo reste parfaitement affichable : il obtient un
//    visuel de repli aux couleurs de Biashara. C'est une règle de visibilité
//    volontaire — une petite boutique qui n'a pas encore de photos ne
//    disparaît pas du catalogue.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/ui/theme/app_theme.dart';

class PhotoBiashara extends StatelessWidget {
  const PhotoBiashara({
    super.key,
    this.url,
    this.largeur,
    this.hauteur,
    this.rayon = 16,
    this.icone = Icons.storefront_rounded,
    this.pleinEcran = false,
  });

  /// Adresse publique de l'image (`null` = aucune photo).
  final String? url;

  final double? largeur;
  final double? hauteur;
  final double rayon;

  /// Icône de repli (varie selon l'usage : article, boutique, publicité).
  final IconData icone;

  /// `true` pour occuper toute la largeur disponible.
  final bool pleinEcran;

  @override
  Widget build(BuildContext context) {
    final Widget visuel = _construire(context);

    if (!pleinEcran && (largeur != null || hauteur != null)) {
      return SizedBox(
        width: largeur,
        height: hauteur,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(rayon),
          child: visuel,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(rayon),
      child: AspectRatio(aspectRatio: 4 / 3, child: visuel),
    );
  }

  Widget _construire(BuildContext context) {
    final String? adresse = url?.trim();
    if (adresse == null || adresse.isEmpty) return _repli(context, false);

    return Image.network(
      adresse,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // Erreur réseau ou fichier supprimé : repli discret, jamais d'écran cassé.
      errorBuilder: (_, __, ___) => _repli(context, true),
      loadingBuilder: (BuildContext ctx, Widget enfant, ImageChunkEvent? progres) {
        if (progres == null) return enfant;
        return _repli(ctx, false, chargement: true);
      },
    );
  }

  Widget _repli(BuildContext context, bool erreur, {bool chargement = false}) {
    final ThemeData theme = Theme.of(context);
    final bool sombre = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: sombre ? AppDegrades.fondSombre : AppDegrades.fondClair,
      ),
      child: Center(
        child: Icon(
          chargement ? Icons.hourglass_empty_rounded : icone,
          size: 30,
          color: erreur
              ? theme.colorScheme.onSurfaceVariant
              : AppCouleurs.marine.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
