// lib/widgets/choix_ville_sheet.dart
//
// 🛒 MODULE 19 — « RECHERCHER DANS UNE VILLE ».
//
// Repli OBLIGATOIRE quand le visiteur refuse la géolocalisation : la recherche
// doit rester parfaitement utilisable. On ne demande jamais « pourquoi » il
// refuse ; on propose simplement cette alternative.
//
// Aucune position n'est déduite ni devinée : la ville choisie est utilisée
// telle quelle pour filtrer le catalogue public.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/services/marketplace_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';

/// Ouvre la feuille de choix de ville et renvoie la ville choisie (ou `null`).
Future<VillePublique?> ouvrirChoixVille(BuildContext context) {
  return showModalBottomSheet<VillePublique>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => const _ChoixVilleSheet(),
  );
}

class _ChoixVilleSheet extends StatefulWidget {
  const _ChoixVilleSheet();

  @override
  State<_ChoixVilleSheet> createState() => _ChoixVilleSheetState();
}

class _ChoixVilleSheetState extends State<_ChoixVilleSheet> {
  late Future<List<VillePublique>> _futur;
  String _recherche = '';

  @override
  void initState() {
    super.initState();
    _futur = MarketplaceService.instance.villes();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Rechercher dans une ville',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Vous ne souhaitez pas partager votre position ? Choisissez une '
              'ville : le résultat est identique.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'Filtrer les villes…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (String valeur) => setState(() => _recherche = valeur),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.45,
              child: FutureBuilder<List<VillePublique>>(
                future: _futur,
                builder: (BuildContext ctx,
                    AsyncSnapshot<List<VillePublique>> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: ModernLoader(taille: 44));
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Impossible de charger les villes pour le moment.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    );
                  }

                  final String q = _recherche.trim().toLowerCase();
                  final List<VillePublique> villes = (snapshot.data ??
                          const <VillePublique>[])
                      .where((VillePublique v) =>
                          q.isEmpty ||
                          v.nom.toLowerCase().contains(q))
                      .toList(growable: false);

                  if (villes.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Aucune boutique publiée n\'est encore rattachée à '
                          'une ville. Essayez « Autour de moi » ou revenez '
                          'plus tard : de nouvelles boutiques arrivent '
                          'chaque jour.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: villes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext c, int i) {
                      final VillePublique ville = villes[i];
                      return ListTile(
                        leading: const Icon(Icons.location_city_rounded,
                            color: AppCouleurs.marine),
                        title: Text(ville.nom),
                        subtitle: Text(
                          ville.nbBoutiques > 0
                              ? '${ville.nbBoutiques} boutique'
                                  '${ville.nbBoutiques > 1 ? 's' : ''} visible'
                                  '${ville.nbBoutiques > 1 ? 's' : ''}'
                              : (ville.pays ?? 'Aucune boutique visible'),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pop(ville),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
