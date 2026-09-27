// lib/widgets/carte_produit_public.dart
//
// 🛒 MODULE 19 — CARTE PRODUIT DU CATALOGUE PUBLIC.
//
// Promesse de l'écran : « Produit → Prix → Boutique → Distance », lisibles
// immédiatement, sans effort. La carte est utilisée par la page Welcome, les
// résultats de recherche et la fiche boutique, ce qui garantit une lecture
// identique partout.
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

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                PhotoBiashara(
                  url: produit.photo,
                  hauteur: compacte ? 110 : 150,
                  rayon: 0,
                  icone: Icons.inventory_2_rounded,
                ),
                if (!produit.disponible)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _Etiquette(
                      texte: 'Indisponible',
                      couleur: AppCouleurs.danger,
                    ),
                  ),
                if (produit.vendableAuPoids && produit.disponible)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _Etiquette(
                      texte: '🥩 Au poids',
                      couleur: AppCouleurs.marine,
                    ),
                  ),
                if (distance != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _Etiquette(
                      texte: '📍 $distance',
                      couleur: Colors.black.withValues(alpha: 0.62),
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
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    produit.prixAvecUnite(formatMontant(produit.prix)),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppCouleurs.orangeFonce,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.storefront_rounded,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          produit.boutique.nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
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
                    if (variantes != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        variantes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppCouleurs.marineClair,
                        ),
                      ),
                    ],
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

/// Petite étiquette lisible sur une photo (distance, disponibilité…).
class _Etiquette extends StatelessWidget {
  const _Etiquette({required this.texte, required this.couleur});

  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
