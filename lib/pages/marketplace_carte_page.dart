// lib/pages/marketplace_carte_page.dart
//
// 🛒 MODULE 19 — CARTE INTERACTIVE DES BOUTIQUES PROCHES.
//
// Affiche :
//   • la position du visiteur (si et seulement s'il l'a autorisée) ;
//   • les boutiques participantes, sous forme de marqueurs ;
//   • le produit recherché et son prix lorsque la carte est ouverte depuis une
//     recherche.
//
// ⚠️ Fonds de carte OpenStreetMap : AUCUNE CLÉ D'API n'est nécessaire et
//    aucune n'est stockée dans l'application. Les tuiles sont chargées
//    directement depuis le service public, avec l'attribution requise.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:biashara_yangu/models/boutique_publique.dart';
import 'package:biashara_yangu/models/produit_public.dart';
import 'package:biashara_yangu/services/marketplace_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/geolocalisation.dart';
import 'package:biashara_yangu/widgets/choix_ville_sheet.dart';

/// Centre par défaut : Lubumbashi (l'application y est éditée et opérée).
const LatLng _centreParDefaut = LatLng(-11.6609, 27.4794);

class MarketplaceCartePage extends StatefulWidget {
  const MarketplaceCartePage({super.key, this.requete});

  /// Recherche éventuelle (la carte montre alors les produits trouvés).
  final String? requete;

  @override
  State<MarketplaceCartePage> createState() => _MarketplaceCartePageState();
}

class _MarketplaceCartePageState extends State<MarketplaceCartePage> {
  final MarketplaceService _marketplace = MarketplaceService.instance;
  final MapController _carte = MapController();

  List<ResumeBoutique> _boutiques = <ResumeBoutique>[];

  /// Offres par boutique, quand la carte est ouverte depuis une recherche.
  Map<String, List<ProduitPublic>> _offres = <String, List<ProduitPublic>>{};

  ResumeBoutique? _selection;
  LatLng? _maPosition;
  bool _chargement = true;
  bool _localisationEnCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final List<ResumeBoutique> boutiques =
          await _marketplace.boutiquesProches(limite: 60);

      Map<String, List<ProduitPublic>> offres = <String, List<ProduitPublic>>{};
      final String? requete = widget.requete;
      if (requete != null && requete.trim().isNotEmpty) {
        final ResultatRecherchePublic resultat =
            await _marketplace.rechercher(texte: requete.trim(), limite: 40);
        for (final ProduitPublic produit in resultat.resultats) {
          offres
              .putIfAbsent(produit.boutique.espaceId, () => <ProduitPublic>[])
              .add(produit);
        }
        // Les boutiques issues de la recherche complètent celles à proximité.
        final Set<String> connues =
            boutiques.map((ResumeBoutique b) => b.espaceId).toSet();
        offres.forEach((String espaceId, List<ProduitPublic> liste) {
          if (connues.contains(espaceId)) return;
          if (liste.isEmpty) return;
          boutiques.add(liste.first.boutique);
          connues.add(espaceId);
        });
      }

      if (!mounted) return;
      setState(() {
        _boutiques = boutiques;
        _offres = offres;
        _chargement = false;
      });

      // « Produits autour de vous » de la carte = visibilité mesurée.
      for (final List<ProduitPublic> liste in offres.values) {
        await _marketplace.impressionsResultats(liste);
      }
    } on MarketplaceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  Future<void> _autourDeMoi() async {
    setState(() => _localisationEnCours = true);
    final ResultatPosition resultat =
        await Geolocalisation.instance.positionActuelle();

    if (!mounted) return;
    setState(() => _localisationEnCours = false);

    final PositionUtilisateur? position = resultat.position;
    if (position == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(
          resultat.message ?? 'Position indisponible.',
        )));
      return;
    }

    _marketplace.definirPosition(position.latitude, position.longitude);
    setState(() {
      _maPosition = LatLng(position.latitude, position.longitude);
    });
    _carte.move(_maPosition!, 14);
    await _charger();
  }

  Future<void> _choisirVille() async {
    final ville = await ouvrirChoixVille(context);
    if (ville == null || !mounted) return;

    _marketplace.definirVille(ville.id, ville.nom);
    await _charger();

    // Recadre sur la première boutique de la ville choisie.
    if (_boutiques.isNotEmpty && _boutiques.first.aPosition) {
      _carte.move(
        LatLng(_boutiques.first.latitude!, _boutiques.first.longitude!),
        12.5,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Boutiques sur la carte'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Changer de ville',
            onPressed: _choisirVille,
            icon: const Icon(Icons.location_city_rounded),
          ),
          IconButton(
            tooltip: 'Autour de moi',
            onPressed: _localisationEnCours ? null : _autourDeMoi,
            icon: _localisationEnCours
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: ModernLoader(taille: 46))
          : Stack(
              children: <Widget>[
                _carteWidget(theme),
                if (_erreur != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Material(
                      elevation: 3,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.wifi_off_rounded,
                                color: AppCouleurs.alerte, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_erreur!)),
                            TextButton(
                              onPressed: _charger,
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_boutiques.isEmpty && _erreur == null)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Material(
                      elevation: 3,
                      borderRadius: BorderRadius.circular(14),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.map_outlined,
                                color: AppCouleurs.marine, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Aucune boutique géolocalisée pour le moment. '
                                'Choisissez une autre ville ou revenez plus '
                                'tard.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_selection != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _carteSelection(theme, _selection!),
                  ),
              ],
            ),
    );
  }

  Widget _carteWidget(ThemeData theme) {
    final LatLng centre = _maPosition ??
        (_marketplace.aPosition
            ? LatLng(_marketplace.latitudeCourante!, _marketplace.longitudeCourante!)
            : _centreParDefaut);

    return FlutterMap(
      mapController: _carte,
      options: MapOptions(
        initialCenter: centre,
        initialZoom: _marketplace.aPosition || _maPosition != null ? 13 : 12,
        onTap: (_, __) => setState(() => _selection = null),
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.biashara_yangu',
          maxZoom: 19,
        ),
        MarkerLayer(
          markers: <Marker>[
            if (_maPosition != null)
              Marker(
                point: _maPosition!,
                width: 26,
                height: 26,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppCouleurs.info,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            for (final ResumeBoutique boutique in _boutiques)
              if (boutique.aPosition)
                Marker(
                  point: LatLng(boutique.latitude!, boutique.longitude!),
                  width: 46,
                  height: 46,
                  child: GestureDetector(
                    onTap: () => setState(() => _selection = boutique),
                    child: _epingle(
                      theme,
                      selectionne: _selection?.espaceId == boutique.espaceId,
                      aDesOffres:
                          (_offres[boutique.espaceId] ?? const <ProduitPublic>[])
                              .isNotEmpty,
                    ),
                  ),
                ),
          ],
        ),
        const RichAttributionWidget(
          attributions: <SourceAttribution>[
            TextSourceAttribution('© OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }

  /// Épingle d'une boutique : orange si elle a un produit qui correspond à la
  /// recherche, marine sinon. La sélection est agrandie.
  Widget _epingle(
    ThemeData theme, {
    required bool selectionne,
    required bool aDesOffres,
  }) {
    final Color couleur = selectionne
        ? AppCouleurs.orangeFonce
        : (aDesOffres ? AppCouleurs.orange : AppCouleurs.marine);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: couleur,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: selectionne ? 3.5 : 2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.storefront_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  /// Fiche compacte du marqueur sélectionné, avec les produits trouvés.
  Widget _carteSelection(ThemeData theme, ResumeBoutique boutique) {
    final List<ProduitPublic> offres =
        _offres[boutique.espaceId] ?? const <ProduitPublic>[];

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    boutique.nom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                if (boutique.distanceLibelle != null)
                  Text(
                    '📍 ${boutique.distanceLibelle}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppCouleurs.marine,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                IconButton(
                  tooltip: 'Fermer',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _selection = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            Text(
              boutique.adresseLisible.isEmpty
                  ? boutique.typeLibelle
                  : boutique.adresseLisible,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (offres.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              for (final ProduitPublic offre in offres.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          offre.nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatMontant(offre.prix),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppCouleurs.orangeFonce,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push(
                      '/biashara/boutique/'
                      '${boutique.slug ?? boutique.espaceId}',
                    ),
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: const Text('Voir la boutique'),
                  ),
                ),
                if (boutique.aPosition) ...<Widget>[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Voir l\'itinéraire',
                    onPressed: () async {
                      await _marketplace.evenement(
                        type: 'clic_itineraire',
                        entiteType: 'boutique',
                        entiteId: boutique.slug ?? boutique.espaceId,
                        quartier: boutique.quartier,
                        distanceKm: boutique.distanceKm,
                      );
                      final String? url = boutique.lienItineraireDepuis(
                        lat: _marketplace.latitudeCourante,
                        lng: _marketplace.longitudeCourante,
                      );
                      if (url == null) return;
                      await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: const Icon(Icons.directions_rounded),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
