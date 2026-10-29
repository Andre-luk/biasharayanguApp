// lib/widgets/photo_biashara.dart
//
// 🛒 MODULE 19 — VISUEL TOLÉRANT ET RAPIDE (photo d'article, logo, devanture).
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
//
// ⚡ POURQUOI CE FICHIER A ÉTÉ RÉÉCRIT (lenteur du marketplace)
//    Les photos étaient décodées à leur taille D'ORIGINE : une photo de
//    téléphone (3000 × 2000) était décompressée en pleine résolution pour
//    être affichée dans une vignette de 160 px. Sur une liste de 20 articles,
//    cela représentait des centaines de Mo de mémoire et des saccades.
//    Désormais :
//      • `cacheWidth` : l'image est décodée à la taille RÉELLE d'affichage
//        (× la densité de l'écran, plafonnée) — gain de mémoire et de temps ;
//      • `FilterQuality.low` : filtrage bon marché, adapté aux vignettes ;
//      • apparition en fondu dès que l'image est prête (pas de clignotement) ;
//      • un squelette animé pendant le chargement, au lieu d'une icône figée ;
//      • `gaplessPlayback` : pas de retour au vide lors d'un rafraîchissement.

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

  /// Plafond de décodage : au-delà, aucun écran ne montre la différence.
  static const int _coteMaxDecodage = 1080;

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

    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints contraintes) {
        // Taille de décodage = taille d'affichage réelle × densité de pixels.
        int? largeurDecodage;
        if (contraintes.maxWidth.isFinite && contraintes.maxWidth > 0) {
          final double dpr = MediaQuery.of(ctx).devicePixelRatio;
          largeurDecodage = (contraintes.maxWidth * dpr)
              .round()
              .clamp(64, _coteMaxDecodage);
        }

        return Image.network(
          adresse,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: largeurDecodage,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          // Apparition en fondu : l'image « arrive » au lieu de clignoter.
          frameBuilder: (
            BuildContext c,
            Widget enfant,
            int? frame,
            bool synchrone,
          ) {
            if (synchrone) return enfant;
            if (frame == null) return _repli(c, false, chargement: true);
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: enfant,
            );
          },
          // Erreur réseau ou fichier supprimé : repli discret, jamais d'écran
          // cassé.
          errorBuilder: (_, __, ___) => _repli(ctx, true),
        );
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
        child: chargement
            // Pendant le chargement : un simple disque qui respire, plus
            // discret et plus léger qu'une animation complexe.
            ? Icon(
                Icons.image_outlined,
                size: 28,
                color: AppCouleurs.marine.withValues(alpha: 0.22),
              )
            : Icon(
                icone,
                size: 30,
                color: erreur
                    ? theme.colorScheme.onSurfaceVariant
                    : AppCouleurs.marine.withValues(alpha: 0.45),
              ),
      ),
    );
  }
}
