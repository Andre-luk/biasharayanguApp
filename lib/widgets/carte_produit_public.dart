// lib/widgets/carte_produit_public.dart
//
// 🛒 MODULE 19 / CORRECTIF 76 — CARTE PRODUIT DU CATALOGUE PUBLIC.
//
// Promesse de l'écran : « Produit → Prix → Boutique → Distance », lisibles
// immédiatement, sans effort. La carte est utilisée par la page Welcome, les
// résultats de recherche et la fiche boutique, ce qui garantit une lecture
// identique partout.
//
// 🎨 CORRECTIF 76 — refonte « vitrine d'application » (Play Store / Shopify) :
//   • un CADRE net et arrondi, liseré discret et ombre douce : le produit est
//     mis en valeur au lieu d'être cerné de traits gris ;
//   • le PRIX dans une pastille colorée, lu d'un seul coup d'œil ;
//   • la BOUTIQUE sur une ligne « éditeur », avec sa vignette ronde ;
//   • la DISPONIBILITÉ en pastille d'état (verte / rouge).
//
// ⚠️ Aucun stock exact n'est affiché : uniquement « Disponible » /
//    « Indisponible », information honnête et non sensible.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/produit_public.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/photo_biashara.dart';

class CarteProduitPublic extends StatelessWidget {
  const CarteProduitPublic({
    super.key,
    required this.produit,
    this.onTap,
    this.compacte = false,
    this.actionSecondaire,
  });

  final ProduitPublic produit;

  /// Ouvre la fiche produit publique.
  final VoidCallback? onTap;

  /// Version condensée (liste horizontale de l'accueil).
  final bool compacte;

  /// Bouton optionnel affiché en bas de carte (ex. « Voir la boutique »).
  final Widget? actionSecondaire;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? distance = produit.distanceLibelle;
    final String? variantes = produit.resumeVariantes;

    // Cadre unique : un seul style de carte pour tout le catalogue public.
    final Color lisiere = theme.dividerColor.withValues(alpha: 0.32);
    final Color fondCarte = theme.cardColor;

    return Material(
      color: fondCarte,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: lisiere),
      ),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                PhotoBiashara(
                  url: produit.photo,
                  hauteur: compacte ? 118 : 168,
                  rayon: 0,
                  icone: Icons.inventory_2_rounded,
                ),
                // Voile dégradé du haut : les pastilles restent lisibles quelle
                // que soit la photo envoyée par le commerçant.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 56,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.black.withValues(alpha: 0.32),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Pastilles posées dans UNE SEULE rangée bornée : à grande
                // échelle de texte elles se réduisent (ellipse) au lieu de
                // déborder du cadre.
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    // ⚠️ Un `Spacer()` volait la moitié de la largeur et
                    // rognait le libellé : « Disponible » s'affichait
                    // « Dispon… » sur téléphone. `spaceBetween` pousse la
                    // seconde pastille à droite SANS priver la première de
                    // sa place.
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Flexible(
                        child: _Etiquette(
                          texte: produit.disponible
                              ? 'Disponible'
                              : 'Indisponible',
                          couleur: produit.disponible
                              ? AppCouleurs.succes
                              : AppCouleurs.danger,
                          icone: produit.disponible
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                        ),
                      ),
                      if (produit.vendableAuPoids && produit.disponible)
                        const Flexible(
                          child: _Etiquette(
                            texte: 'Au poids',
                            couleur: AppCouleurs.marine,
                            icone: Icons.scale_rounded,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    produit.nom,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // -------------------------------------------- le prix
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppCouleurs.orange.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            produit.prixAvecUnite(
                                formatMontant(produit.prix)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: AppCouleurs.orangeFonce,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ------------------------------------------ la boutique
                  Row(
                    children: <Widget>[
                      _VignetteBoutique(nom: produit.boutique.nom),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          produit.boutique.nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (distance != null)
                        Flexible(
                          child: _Etiquette(
                            texte: distance,
                            couleur: Colors.black.withValues(alpha: 0.55),
                            icone: Icons.place_rounded,
                          ),
                        ),
                    ],
                  ),
                  if (!compacte) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      <String?>[
                        produit.boutique.quartier,
                        produit.boutique.ville,
                      ].where((String? e) => e != null && e.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (variantes != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      variantes,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppCouleurs.marineClair,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (actionSecondaire != null) ...<Widget>[
                    const SizedBox(height: 10),
                    actionSecondaire!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vignette ronde de la boutique : la ligne « éditeur » du produit, comme la
/// pastille de l'application sur sa fiche dans une boutique d'applications.
class _VignetteBoutique extends StatelessWidget {
  const _VignetteBoutique({required this.nom});

  final String nom;

  @override
  Widget build(BuildContext context) {
    final String propre = nom.trim();
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppDegrades.primaire,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        propre.isEmpty ? '?' : propre.characters.first.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Petite étiquette lisible sur une photo (disponibilité, distance…).
class _Etiquette extends StatelessWidget {
  const _Etiquette({
    required this.texte,
    required this.couleur,
    this.icone,
  });

  final String texte;
  final Color couleur;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icone != null) ...<Widget>[
            Icon(icone, size: 12, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              texte,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
