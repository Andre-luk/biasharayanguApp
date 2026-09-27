// lib/pages/marketplace_recherche_page.dart
//
// 🛒 MODULE 19 — RÉSULTATS DE RECHERCHE PUBLIQUE.
//
// Répond à la promesse centrale : « Produit → Prix → Boutique → Distance ».
// Ajoute trois choses demandées explicitement :
//   • un CHOIX DE TRI (Plus proche / Prix le plus bas / Pertinence) — le
//     produit le moins cher n'est donc pas présenté d'office comme le
//     meilleur choix ;
//   • une COMPARAISON DES PRIX entre boutiques proposant le même produit ;
//   • un emplacement PUBLICITAIRE séparé, jamais mêlé aux résultats.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/produit_public.dart';
import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/services/marketplace_service.dart';
import 'package:biashara_yangu/ui/mise_en_page_adaptative.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/carte_produit_public.dart';
import 'package:biashara_yangu/widgets/choix_ville_sheet.dart';
import 'package:biashara_yangu/widgets/encart_publicitaire.dart';

class MarketplaceRecherchePage extends StatefulWidget {
  const MarketplaceRecherchePage({
    super.key,
    this.requeteInitiale,
    this.categorieInitiale,
    this.triInitial,
  });

  final String? requeteInitiale;
  final String? categorieInitiale;
  final String? triInitial;

  @override
  State<MarketplaceRecherchePage> createState() =>
      _MarketplaceRecherchePageState();
}

class _MarketplaceRecherchePageState extends State<MarketplaceRecherchePage> {
  final MarketplaceService _marketplace = MarketplaceService.instance;
  late final TextEditingController _texte;

  List<ProduitPublic> _resultats = <ProduitPublic>[];
  List<PubliciteBiashara> _publicites = <PubliciteBiashara>[];
  TriRecherche _tri = TriRecherche.pertinence;
  String? _categorie;
  int _total = 0;
  int _nbBoutiques = 0;
  int? _rechercheId;

  bool _chargement = true;
  bool _chargementPlus = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _tri = TriRecherche.fromCode(widget.triInitial);
    _categorie = widget.categorieInitiale;
    _texte = TextEditingController(text: widget.requeteInitiale ?? '');
    _rechercher(enregistrer: true);
  }

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  Future<void> _rechercher({bool enregistrer = true, bool plus = false}) async {
    if (plus) {
      setState(() => _chargementPlus = true);
    } else {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    try {
      final ResultatRecherchePublic resultat = await _marketplace.rechercher(
        texte: _texte.text.trim().isEmpty ? null : _texte.text.trim(),
        tri: _tri,
        categorie: _categorie,
        decalage: plus ? _resultats.length : 0,
        limite: 20,
        enregistrer: enregistrer,
      );

      if (!mounted) return;

      setState(() {
        _resultats = plus
            ? <ProduitPublic>[..._resultats, ...resultat.resultats]
            : resultat.resultats;
        _publicites = resultat.publicites;
        _total = resultat.total;
        _nbBoutiques = resultat.nbBoutiques;
        _rechercheId = resultat.rechercheId;
        _chargement = false;
        _chargementPlus = false;
      });

      // VISIBILITÉ : on mesure l'affichage RÉEL des résultats, après rendu.
      await _marketplace.impressionsResultats(
        resultat.resultats,
        rechercheId: resultat.rechercheId,
      );
      for (final PubliciteBiashara pub in resultat.publicites) {
        await _marketplace.impressionPublicite(pub);
      }
    } on MarketplaceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
        _chargementPlus = false;
      });
    }
  }

  Future<void> _choisirVille() async {
    final ville = await ouvrirChoixVille(context);
    if (ville == null || !mounted) return;
    _marketplace.definirVille(ville.id, ville.nom);
    await _rechercher();
  }

  void _changerTri(TriRecherche tri) {
    if (_tri == tri) return;
    setState(() => _tri = tri);
    _rechercher(enregistrer: false);
  }

  void _ouvrirProduit(ProduitPublic produit) {
    _marketplace.evenement(
      type: 'vue_produit',
      entiteType: 'produit',
      entiteId: produit.publicationId,
      quartier: produit.boutique.quartier,
      distanceKm: produit.distanceKm,
      rechercheId: _rechercheId,
    );
    context.push('/biashara/produit/${produit.publicationId}');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recherche'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Changer de ville',
            onPressed: _choisirVille,
            icon: const Icon(Icons.location_city_rounded),
          ),
          IconButton(
            tooltip: 'Voir sur la carte',
            onPressed: () => context.push('/biashara/carte'),
            icon: const Icon(Icons.map_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _barreRecherche(theme),
          _barreTri(theme),
          if (!_chargement && _erreur == null && _resultats.isNotEmpty)
            _bandeauResultats(theme),
          Expanded(child: _corps(theme)),
        ],
      ),
    );
  }

  Widget _barreRecherche(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _texte,
              textInputAction: TextInputAction.search,
              onSubmitted: (String _) => _rechercher(),
              decoration: const InputDecoration(
                hintText: 'Que recherchez-vous ?',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Rechercher',
            onPressed: () => _rechercher(),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }

  Widget _barreTri(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Text(
              'Trier par',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
          for (final TriRecherche tri in TriRecherche.values) ...<Widget>[
            ChoiceChip(
              label: Text(tri.libelle),
              selected: _tri == tri,
              onSelected: (_) => _changerTri(tri),
            ),
            const SizedBox(width: 8),
          ],
          if (_categorie != null && _categorie!.isNotEmpty)
            InputChip(
              avatar: const Icon(Icons.local_offer_rounded, size: 16),
              label: Text(_categorie!),
              onDeleted: () {
                setState(() => _categorie = null);
                _rechercher();
              },
            ),
        ],
      ),
    );
  }

  Widget _bandeauResultats(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$_total résultat${_total > 1 ? 's' : ''} chez $_nbBoutiques '
              'boutique${_nbBoutiques > 1 ? 's' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_marketplace.villeNomCourante != null)
            Text(
              '📍 ${_marketplace.villeNomCourante}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppCouleurs.marine,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }

  Widget _corps(ThemeData theme) {
    if (_chargement) {
      return const Center(child: ModernLoader(taille: 46));
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.wifi_off_rounded,
                  size: 40, color: AppCouleurs.alerte),
              const SizedBox(height: 12),
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _rechercher(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (_resultats.isEmpty) return _aucunResultat(theme);

    final double largeur = MediaQuery.sizeOf(context).width;
    final bool grille = largeur >= 780;

    final List<ComparaisonPrix> comparaisons =
        ComparaisonPrix.depuisProduits(_resultats);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
      children: <Widget>[
        if (comparaisons.isNotEmpty) _blocComparaison(theme, comparaisons),

        if (_publicites.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          for (final PubliciteBiashara pub in _publicites)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EncartPublicitaire(
                publicite: pub,
                onTap: () {
                  _marketplace.evenement(
                    type: 'clic_publicite',
                    entiteType: 'publicite',
                    publiciteId: pub.id,
                  );
                  final String? chemin = pub.cheminPublic;
                  if (chemin != null) context.push(chemin);
                },
              ),
            ),
        ],

        if (grille)
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // ♿ Proportion corrigée de l'échelle de texte : nom + prix +
            // ville + vendeur sur une carte mobile étroite.
            childAspectRatio:
                MiseEnPageAdaptative.proportionCarte(context, 0.72, minimum: 0.5),
            children: <Widget>[
              for (final ProduitPublic produit in _resultats)
                CarteProduitPublic(
                  produit: produit,
                  compacte: true,
                  onTap: () => _ouvrirProduit(produit),
                ),
            ],
          )
        else
          for (final ProduitPublic produit in _resultats)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CarteProduitPublic(
                produit: produit,
                onTap: () => _ouvrirProduit(produit),
              ),
            ),

        if (_resultats.length < _total)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: OutlinedButton.icon(
              onPressed: _chargementPlus ? null : () => _rechercher(plus: true),
              icon: _chargementPlus
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text('Charger plus (${_total - _resultats.length} restants)'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
      ],
    );
  }

  /// COMPARAISON DES PRIX — un même produit chez plusieurs boutiques.
  ///
  /// Présentée en cartes (pas seulement en tableau) : chaque ligne reste
  /// cliquable vers la fiche produit de la boutique concernée.
  Widget _blocComparaison(ThemeData theme, List<ComparaisonPrix> groupes) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        leading: const Icon(Icons.compare_arrows_rounded,
            color: AppCouleurs.marine),
        title: const Text(
          'Comparer les prix',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${groupes.length} produit${groupes.length > 1 ? 's' : ''} proposé'
          '${groupes.length > 1 ? 's' : ''} par plusieurs boutiques',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        children: <Widget>[
          for (final ComparaisonPrix groupe in groupes) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          groupe.nom,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (groupe.ecartPourcent != null &&
                          groupe.ecartPourcent! > 0)
                        Text(
                          'écart ${groupe.ecartPourcent} %',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppCouleurs.alerte,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final ProduitPublic offre in groupe.offres)
                    InkWell(
                      onTap: () => _ouvrirProduit(offre),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              flex: 3,
                              child: Text(
                                offre.boutique.nom,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                offre.distanceLibelle ?? '—',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                offre.prixAvecUnite(
                                    formatMontant(offre.prix)),
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: offre.prix == groupe.prixMin
                                      ? AppCouleurs.succes
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Divider(height: 18),
                ],
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Le prix le moins cher n\'est pas forcément le meilleur choix : '
              'tenez compte de la distance et de la disponibilité.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aucunResultat(ThemeData theme) {
    final String requete = _texte.text.trim();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.search_off_rounded,
                size: 46, color: AppCouleurs.orange),
            const SizedBox(height: 12),
            Text(
              requete.isEmpty
                  ? 'Aucun produit publié pour le moment.'
                  : 'Aucun résultat pour « $requete ».',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Essayez un mot plus simple (« riz », « téléphone »), changez de '
              'ville, ou parcourez les boutiques autour de vous.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _choisirVille,
                  icon: const Icon(Icons.location_city_rounded, size: 18),
                  label: const Text('Changer de ville'),
                ),
                FilledButton.icon(
                  onPressed: () => context.push('/biashara/carte'),
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: const Text('Voir la carte'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
