// lib/widgets/carte_boutique_publique.dart
//
// 🛒 MODULE 19 — CARTE BOUTIQUE PUBLIQUE.
//
// Utilisée par la page d'accueil publique (« Boutiques à proximité »), les
// résultats « Autour de moi » et la sélection sur la carte. Elle répond aux
// questions d'un visiteur qui ne connaît pas la ville : où, comment y aller,
// et que vend cette boutique.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/boutique_publique.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/widgets/photo_biashara.dart';

class CarteBoutiquePublique extends StatelessWidget {
  const CarteBoutiquePublique({
    super.key,
    required this.boutique,
    this.onTap,
    this.jamaisSansProduit = false,
  });

  final ResumeBoutique boutique;
  final VoidCallback? onTap;

  /// Affiche le nombre d'articles publiés (désactivé pour la carte/marqueurs).
  final bool jamaisSansProduit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? distance = boutique.distanceLibelle;

    return Material(
      color: theme.cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.32)),
      ),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // ------------------------------------------- bandeau vitrine
            Stack(
              children: <Widget>[
                PhotoBiashara(
                  url: boutique.photoUrl ?? boutique.logoUrl,
                  hauteur: 92,
                  rayon: 0,
                  icone: Icons.storefront_rounded,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.black.withValues(alpha: 0.05),
                            Colors.black.withValues(alpha: 0.58),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Vignette de la boutique, à cheval sur le bandeau : la même
                // lecture que la fiche d'une application (visuel + nom).
                Positioned(
                  left: 12,
                  bottom: -1,
                  child: PhotoBiashara(
                    url: boutique.logoUrl,
                    largeur: 46,
                    hauteur: 46,
                    rayon: 12,
                    icone: Icons.storefront_rounded,
                  ),
                ),
                Positioned(
                  left: 66,
                  right: 12,
                  bottom: 10,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          boutique.nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (distance != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.place_rounded,
                                  size: 12, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(
                                distance,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // ---------------------------------------------------- contenu
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    boutique.typeLibelle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppCouleurs.orangeFonce,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    boutique.adresseLisible.isEmpty
                        ? 'Adresse non renseignée'
                        : boutique.adresseLisible,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!jamaisSansProduit) ...<Widget>[
                    const SizedBox(height: 8),
                    // ♿ `Wrap` et non `Row` : à grande échelle de texte, les
                    // mentions passent à la ligne au lieu de déborder.
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${boutique.nbProduits} article'
                              '${boutique.nbProduits > 1 ? 's' : ''} visible'
                              '${boutique.nbProduits > 1 ? 's' : ''}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (boutique.localisationVerifiee)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.verified_rounded,
                                size: 14,
                                color: AppCouleurs.succes,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Position confirmée',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppCouleurs.succes,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        if (onTap != null)
                          Text(
                            'Voir la boutique',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppCouleurs.marineClair,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
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
