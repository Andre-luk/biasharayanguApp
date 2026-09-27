// lib/pages/marketplace_boutique_page.dart
//
// 🛒 MODULE 19 — FICHE PUBLIQUE D'UNE BOUTIQUE (`/biashara/boutique/<slug>`).
//
// Pensée pour un visiteur ÉTRANGER ou nouveau dans la ville : où se trouve la
// boutique (adresse complète + point de repère + quartier + ville), comment y
// aller (« Voir l'itinéraire »), comment la contacter (appel, WhatsApp) et ce
// qu'elle vend. La page est PARTAGEABLE par lien.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:biashara_yangu/models/boutique_publique.dart';
import 'package:biashara_yangu/models/produit_public.dart';
import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/services/marketplace_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/geo_utils.dart';
import 'package:biashara_yangu/widgets/carte_produit_public.dart';
import 'package:biashara_yangu/widgets/encart_publicitaire.dart';
import 'package:biashara_yangu/widgets/photo_biashara.dart';

class MarketplaceBoutiquePage extends StatefulWidget {
  const MarketplaceBoutiquePage({super.key, required this.slugOuId});

  final String slugOuId;

  @override
  State<MarketplaceBoutiquePage> createState() =>
      _MarketplaceBoutiquePageState();
}

class _MarketplaceBoutiquePageState extends State<MarketplaceBoutiquePage> {
  final MarketplaceService _marketplace = MarketplaceService.instance;

  BoutiquePublique? _boutique;
  List<ProduitPublic> _produits = <ProduitPublic>[];
  bool _chargement = true;
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
      final BoutiquePublique boutique =
          await _marketplace.boutique(widget.slugOuId);

      if (!mounted) return;

      // Les produits arrivent « à plat » : on leur rattache la boutique.
      final List<ProduitPublic> produits = boutique.produits
          .map((Map<String, dynamic> brut) => ProduitPublic.fromMap(
                <String, dynamic>{...brut, 'boutique': <String, dynamic>{
                  'espace_id': boutique.resume.espaceId,
                  'nom': boutique.resume.nom,
                  'slug': boutique.resume.slug,
                  'type': boutique.resume.type,
                  'logo_url': boutique.resume.logoUrl,
                  'quartier': boutique.resume.quartier,
                  'adresse': boutique.resume.adresse,
                  'ville': boutique.resume.ville,
                  'telephone': boutique.telephone,
                  'whatsapp': boutique.whatsapp,
                  'latitude': boutique.resume.latitude,
                  'longitude': boutique.resume.longitude,
                  'distance_km': boutique.resume.distanceKm,
                  'localisation_verifiee':
                      boutique.resume.localisationVerifiee,
                }},
              ))
          .toList(growable: false);

      setState(() {
        _boutique = boutique;
        _produits = produits;
        _chargement = false;
      });

      // INTÉRÊT : consultation de la fiche boutique + visibilité des articles.
      await _marketplace.evenement(
        type: 'vue_boutique',
        entiteType: 'boutique',
        entiteId: boutique.slug ?? boutique.resume.espaceId,
        quartier: boutique.resume.quartier,
        distanceKm: boutique.resume.distanceKm,
      );
      await _marketplace.impressionsResultats(produits);
    } on MarketplaceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  Future<void> _ouvrir(String? url, {String? echec}) async {
    if (url == null) return;
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;

    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _message(echec ?? 'Impossible d\'ouvrir ce lien sur cet appareil.');
    }
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  /// INTENTION : itinéraire demandé (le niveau d'engagement le plus fort avant
  /// l'achat). On le mesure AVANT d'ouvrir l'application de cartographie, car
  /// l'utilisateur peut changer d'avis.
  Future<void> _itineraire() async {
    final BoutiquePublique? boutique = _boutique;
    if (boutique == null || !boutique.aPosition) return;

    await _marketplace.evenement(
      type: 'clic_itineraire',
      entiteType: 'boutique',
      entiteId: boutique.slug ?? boutique.resume.espaceId,
      quartier: boutique.resume.quartier,
      distanceKm: boutique.resume.distanceKm,
    );

    await _ouvrir(
      boutique.resume.lienItineraireDepuis(
        lat: _marketplace.latitudeCourante,
        lng: _marketplace.longitudeCourante,
      ),
      echec: 'Aucune application de cartographie n\'est disponible.',
    );
  }

  Future<void> _appeler() async {
    final String? telephone = _boutique?.telephone;
    if (telephone == null) return;

    await _marketplace.evenement(
      type: 'clic_telephone',
      entiteType: 'boutique',
      entiteId: _boutique!.slug ?? _boutique!.resume.espaceId,
      distanceKm: _boutique!.resume.distanceKm,
    );
    await _ouvrir(lienTelephone(telephone), echec: 'Appel impossible.');
  }

  Future<void> _whatsapp() async {
    final String? numero = _boutique?.whatsapp;
    if (numero == null) return;

    await _marketplace.evenement(
      type: 'clic_whatsapp',
      entiteType: 'boutique',
      entiteId: _boutique!.slug ?? _boutique!.resume.espaceId,
      distanceKm: _boutique!.resume.distanceKm,
    );

    await _ouvrir(
      lienWhatsApp(
        numero,
        message: 'Bonjour, je vous contacte depuis Biashara à propos de '
            '${_boutique!.nom}.',
      ),
      echec: 'WhatsApp n\'est pas installé sur cet appareil.',
    );
  }

  Future<void> _partager() async {
    final BoutiquePublique? boutique = _boutique;
    if (boutique == null) return;

    final String lien = 'https://biashara.app/biashara/boutique/'
        '${boutique.slug ?? boutique.resume.espaceId}';
    final String texte =
        '${boutique.nom} — ${boutique.typeLibelle}\n'
        '${boutique.adresseLisible}\n$lien';

    await Clipboard.setData(ClipboardData(text: texte));

    await _marketplace.evenement(
      type: 'partage',
      entiteType: 'boutique',
      entiteId: boutique.slug ?? boutique.resume.espaceId,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Lien de la boutique copié.'),
          action: SnackBarAction(
            label: 'WhatsApp',
            // Partage SANS numéro destinataire : WhatsApp laisse choisir le
            // contact (lien `wa.me/?text=`).
            onPressed: () => _ouvrir(
              'https://wa.me/?text=${Uri.encodeComponent(texte)}',
            ),
          ),
        ),
      );
  }

  void _ouvrirProduit(ProduitPublic produit) {
    _marketplace.evenement(
      type: 'vue_produit',
      entiteType: 'produit',
      entiteId: produit.publicationId,
      quartier: produit.boutique.quartier,
      distanceKm: produit.distanceKm,
    );
    context.push('/biashara/produit/${produit.publicationId}');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_boutique?.nom ?? 'Boutique'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Partager cette boutique',
            onPressed: _boutique == null ? null : _partager,
            icon: const Icon(Icons.share_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: ModernLoader(taille: 46))
          : (_erreur != null ? _etatErreur(theme) : _contenu(theme)),
    );
  }

  Widget _etatErreur(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.store_mall_directory_outlined,
                size: 46, color: AppCouleurs.alerte),
            const SizedBox(height: 12),
            Text(
              _erreur ?? 'Boutique introuvable.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ce lien est peut-être incomplet, ou la boutique a quitté '
              'Biashara.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/biashara'),
              icon: const Icon(Icons.explore_rounded),
              label: const Text('Explorer Biashara'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenu(ThemeData theme) {
    final BoutiquePublique boutique = _boutique!;
    final List<String> horaires = boutique.horairesLisibles;
    final List<PubliciteBiashara> publicites = boutique.publicites;

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
        children: <Widget>[
          Stack(
            children: <Widget>[
              PhotoBiashara(
                url: boutique.photoUrl ?? boutique.logoUrl,
                pleinEcran: true,
                rayon: 0,
                icone: Icons.storefront_rounded,
              ),
              Positioned(
                left: 16,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: PhotoBiashara(
                    url: boutique.logoUrl,
                    largeur: 52,
                    hauteur: 52,
                    rayon: 14,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        boutique.nom,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    if (boutique.distanceLibelle != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppCouleurs.marine.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '📍 ${boutique.distanceLibelle}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppCouleurs.marine,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Text(
                      boutique.typeLibelle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppCouleurs.orangeFonce,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (boutique.localisationVerifiee) ...<Widget>[
                      const SizedBox(width: 8),
                      const Icon(Icons.verified_rounded,
                          size: 15, color: AppCouleurs.succes),
                      const SizedBox(width: 3),
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
                const SizedBox(height: 14),

                // ---- Actions de contact ----
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (boutique.aPosition)
                      FilledButton.icon(
                        onPressed: _itineraire,
                        icon: const Icon(Icons.directions_rounded, size: 18),
                        label: const Text('Voir l\'itinéraire'),
                      ),
                    if (boutique.telephone != null)
                      OutlinedButton.icon(
                        onPressed: _appeler,
                        icon: const Icon(Icons.call_rounded, size: 18),
                        label: const Text('Appeler'),
                      ),
                    if (boutique.whatsapp != null)
                      OutlinedButton.icon(
                        onPressed: _whatsapp,
                        icon: const Icon(Icons.chat_rounded, size: 18),
                        label: const Text('WhatsApp'),
                      ),
                  ],
                ),

                const SizedBox(height: 16),
                _blocAdresse(theme, boutique),

                if (horaires.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  _titreSection(theme, 'Horaires'),
                  const SizedBox(height: 6),
                  for (final String ligne in horaires)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.schedule_rounded,
                              size: 15,
                              color: AppCouleurs.marine),
                          const SizedBox(width: 8),
                          Text(ligne, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                ],

                if (boutique.description != null &&
                    boutique.description!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  _titreSection(theme, 'À propos'),
                  const SizedBox(height: 6),
                  Text(
                    boutique.description!,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ],
              ],
            ),
          ),

          if (publicites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _titreSection(theme, 'À découvrir'),
                  const SizedBox(height: 10),
                  for (final PubliciteBiashara pub in publicites)
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
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
            child: _titreSection(
              theme,
              'Produits publiés'
              '${boutique.nbProduits > 0 ? ' (${boutique.nbProduits})' : ''}',
            ),
          ),

          if (_produits.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Text(
                'Cette boutique n\'a pas encore publié de produit. Revenez '
                'bientôt, ou contactez-la directement.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Column(
                children: <Widget>[
                  for (final ProduitPublic produit in _produits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: CarteProduitPublic(
                        produit: produit,
                        onTap: () => _ouvrirProduit(produit),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _blocAdresse(ThemeData theme, BoutiquePublique boutique) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppCouleurs.marine.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.place_rounded, color: AppCouleurs.marine, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  boutique.adresseLisible.isEmpty
                      ? 'Adresse non renseignée'
                      : boutique.adresseLisible,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (boutique.pointRepere != null &&
                    boutique.pointRepere!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Point de repère : ${boutique.pointRepere}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (!boutique.aPosition) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Position non renseignée par la boutique : demandez-lui '
                    'le chemin par téléphone.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppCouleurs.alerte,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _titreSection(ThemeData theme, String titre) {
    return Text(
      titre,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}
