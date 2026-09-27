// lib/widgets/encart_publicitaire.dart
//
// 🛒 MODULE 19 — EMPLACEMENT PUBLICITAIRE « PUBLICITÉ ».
//
// Exigences tenues par ce widget :
//   • la mention « PUBLICITÉ » est TOUJOURS affichée, en clair, en haut de
//     l'encart : impossible de la confondre avec un résultat organique ;
//   • l'encart est visuellement DISTINCT (bordure, fond légèrement coloré,
//     mention explicite) : il n'est jamais inséré dans une liste de résultats ;
//   • il n'est PAS intrusif : une seule annonce par emplacement, sans
//     animation ni recouvrement.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/photo_biashara.dart';

class EncartPublicitaire extends StatelessWidget {
  const EncartPublicitaire({
    super.key,
    required this.publicite,
    this.onTap,
  });

  final PubliciteBiashara publicite;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool sombre = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppCouleurs.orange.withValues(alpha: 0.55),
          width: 1.2,
        ),
        color: sombre
            ? AppCouleurs.orange.withValues(alpha: 0.06)
            : AppCouleurs.orange.withValues(alpha: 0.05),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Bandeau de mention : l'information « PUBLICITÉ » est portée par
            // le widget lui-même, pas par la page qui l'utilise.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: const BoxDecoration(
                color: AppCouleurs.orange,
                borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.campaign_rounded,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    publicite.mention.isEmpty ? 'PUBLICITÉ' : publicite.mention,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  if (publicite.boutiqueNom != null)
                    Flexible(
                      child: Text(
                        publicite.boutiqueNom!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (publicite.imageUrl != null)
                    PhotoBiashara(
                      url: publicite.imageUrl,
                      largeur: 66,
                      hauteur: 66,
                      rayon: 12,
                      icone: Icons.campaign_rounded,
                    ),
                  if (publicite.imageUrl != null) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          publicite.titre,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (publicite.message != null &&
                            publicite.message!.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            publicite.message!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            if (publicite.prixPromo != null)
                              Text(
                                formatMontant(publicite.prixPromo!),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: AppCouleurs.orangeFonce,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            const Spacer(),
                            if (onTap != null)
                              Text(
                                'Découvrir',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppCouleurs.marine,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
