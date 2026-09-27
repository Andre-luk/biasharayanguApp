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

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PhotoBiashara(
                url: boutique.logoUrl ?? boutique.photoUrl,
                largeur: 58,
                hauteur: 58,
                rayon: 14,
                icone: Icons.storefront_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            boutique.nom,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (distance != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppCouleurs.marine.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              distance,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppCouleurs.marine,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      boutique.typeLibelle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppCouleurs.orangeFonce,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
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
                      const SizedBox(height: 6),
                      Row(
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
                          if (boutique.localisationVerifiee) ...<Widget>[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: AppCouleurs.succes,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Position confirmée',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppCouleurs.succes,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
