// lib/pages/marketplace_produit_page.dart
//
// 🛒 MODULE 19 — FICHE PUBLIQUE D'UN PRODUIT (`/biashara/produit/<id>`).
//
// Répond à : « ce produit, à quel prix, chez qui, à quelle distance ? » puis
// « et ailleurs, est-ce moins cher ? ». La comparaison des prix est calculée
// par le serveur (offres correspondantes) et affichée ici en tableau lisible,
// doublé de la fiche de la boutique qui vend l'article consulté.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:biashara_yangu/models/accueil_public.dart';
import 'package:biashara_yangu/models/produit_public.dart';
import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/services/marketplace_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/geo_utils.dart';
import 'package:biashara_yangu/widgets/encart_publicitaire.dart';
import 'package:biashara_yangu/widgets/photo_biashara.dart';

class MarketplaceProduitPage extends StatefulWidget {
  const MarketplaceProduitPage({super.key, required this.publicationId});

  final String publicationId;

  @override
  State<MarketplaceProduitPage> createState() => _MarketplaceProduitPageState();
}

class _MarketplaceProduitPageState extends State<MarketplaceProduitPage> {
  final MarketplaceService _marketplace = MarketplaceService.instance;

  FicheProduitPublic? _fiche;
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
      final FicheProduitPublic fiche =
          await _marketplace.produit(widget.publicationId);

      if (!mounted) return;
      setState(() {
        _fiche = fiche;
        _chargement = false;
      });

      // VISIBILITÉ + INTÉRÊT : le produit a été affiché puis consulté.
      await _marketplace.evenement(
        type: 'impression_produit',
        entiteType: 'produit',
        entiteId: fiche.produit.publicationId,
        quartier: fiche.boutique.quartier,
        distanceKm: fiche.produit.distanceKm,
      );
      await _marketplace.evenement(
        type: 'vue_produit',
        entiteType: 'produit',
        entiteId: fiche.produit.publicationId,
        quartier: fiche.boutique.quartier,
        distanceKm: fiche.produit.distanceKm,
      );
      for (final PubliciteBiashara pub in fiche.publicites) {
        await _marketplace.impressionPublicite(pub);
      }
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

  Future<void> _itineraire() async {
    final FicheProduitPublic? fiche = _fiche;
    if (fiche == null || !fiche.boutique.aPosition) return;

    await _marketplace.evenement(
      type: 'clic_itineraire',
      entiteType: 'boutique',
      entiteId: fiche.boutique.slug ?? fiche.boutique.espaceId,
      quartier: fiche.boutique.quartier,
      distanceKm: fiche.boutique.distanceKm,
    );

    await _ouvrir(
      fiche.boutique.lienItineraireDepuis(
        lat: _marketplace.latitudeCourante,
        lng: _marketplace.longitudeCourante,
      ),
    );
  }

  Future<void> _appeler(String? telephone) async {
    if (telephone == null) return;
    await _marketplace.evenement(
      type: 'clic_telephone',
      entiteType: 'produit',
      entiteId: widget.publicationId,
    );
    await _ouvrir(lienTelephone(telephone), echec: 'Appel impossible.');
  }

  Future<void> _whatsapp(String? numero, String nomBoutique) async {
    if (numero == null) return;
    await _marketplace.evenement(
      type: 'clic_whatsapp',
      entiteType: 'produit',
      entiteId: widget.publicationId,
    );
    await _ouvrir(
      lienWhatsApp(
        numero,
        message: 'Bonjour, je vous contacte depuis Biashara au sujet de '
            '« ${_fiche?.produit.nom ?? ''} » ($nomBoutique).',
      ),
      echec: 'WhatsApp n\'est pas installé sur cet appareil.',
    );
  }

  Future<void> _partager() async {
    final FicheProduitPublic? fiche = _fiche;
    if (fiche == null) return;

    final String quartier = fiche.boutique.quartier == null
        ? ''
        : ' (${fiche.boutique.quartier})';

    final String texte = '${fiche.produit.nom} — '
        '${formatMontant(fiche.produit.prix)} / ${fiche.produit.unite}\n'
        'Chez ${fiche.boutique.nom}$quartier\n'
        'https://biashara.app/biashara/produit/${widget.publicationId}';

    await Clipboard.setData(ClipboardData(text: texte));
    await _marketplace.evenement(
      type: 'partage',
      entiteType: 'produit',
      entiteId: widget.publicationId,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Lien du produit copié.'),
          action: SnackBarAction(
            label: 'WhatsApp',
            onPressed: () => _ouvrir(
              'https://wa.me/?text=${Uri.encodeComponent(texte)}',
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produit'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Partager ce produit',
            onPressed: _fiche == null ? null : _partager,
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
            const Icon(Icons.remove_shopping_cart_rounded,
                size: 46, color: AppCouleurs.alerte),
            const SizedBox(height: 12),
            Text(
              _erreur ?? 'Produit introuvable.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
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
    final FicheProduitPublic fiche = _fiche!;
    final ProduitPublic produit = fiche.produit;
    final bool moinsCherAilleurs =
        fiche.autresBoutiques.isNotEmpty && fiche.prixMin < produit.prix;

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: <Widget>[
          PhotoBiashara(
            url: produit.photo,
            pleinEcran: true,
            rayon: 0,
            icone: Icons.inventory_2_rounded,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  produit.nom,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                if (produit.categorie != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    produit.categorie!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (produit.resumeVariantes != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    produit.resumeVariantes!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppCouleurs.marineClair,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      formatMontant(produit.prix),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: AppCouleurs.orangeFonce,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '/ ${produit.unite}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: produit.disponible
                            ? AppCouleurs.succes.withValues(alpha: 0.14)
                            : AppCouleurs.danger.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        produit.disponible ? 'Disponible' : 'Indisponible',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: produit.disponible
                              ? AppCouleurs.succes
                              : AppCouleurs.danger,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                if (produit.vendableAuPoids) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    '🥩 Article vendu au poids : le prix indiqué est le prix '
                    'au kilo.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppCouleurs.marine,
                    ),
                  ),
                ],
                if (produit.description != null &&
                    produit.description!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  Text(
                    produit.description!,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ],
              ],
            ),
          ),

          // ---- Boutique qui vend ce produit ----
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        PhotoBiashara(
                          url: fiche.boutique.logoUrl,
                          largeur: 52,
                          hauteur: 52,
                          rayon: 14,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                fiche.boutique.nom,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                fiche.boutique.adresseLisible.isEmpty
                                    ? fiche.boutique.typeLibelle
                                    : fiche.boutique.adresseLisible,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (fiche.boutique.distanceLibelle != null)
                          Column(
                            children: <Widget>[
                              const Icon(Icons.near_me_rounded,
                                  size: 18, color: AppCouleurs.marine),
                              Text(
                                fiche.boutique.distanceLibelle!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: AppCouleurs.marine,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: () => context.push(
                            '/biashara/boutique/'
                            '${fiche.boutique.slug ?? fiche.boutique.espaceId}',
                          ),
                          icon: const Icon(Icons.storefront_rounded, size: 18),
                          label: const Text('Voir la boutique'),
                        ),
                        if (fiche.boutique.aPosition)
                          OutlinedButton.icon(
                            onPressed: _itineraire,
                            icon: const Icon(Icons.directions_rounded, size: 18),
                            label: const Text('Itinéraire'),
                          ),
                        if (fiche.boutique.telephone != null)
                          OutlinedButton.icon(
                            onPressed: () => _appeler(fiche.boutique.telephone),
                            icon: const Icon(Icons.call_rounded, size: 18),
                            label: const Text('Appeler'),
                          ),
                        if (fiche.boutique.whatsapp != null)
                          OutlinedButton.icon(
                            onPressed: () => _whatsapp(
                              fiche.boutique.whatsapp,
                              fiche.boutique.nom,
                            ),
                            icon: const Icon(Icons.chat_rounded, size: 18),
                            label: const Text('WhatsApp'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ---- Comparaison des prix ----
          if (fiche.nbBoutiques > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(Icons.compare_arrows_rounded,
                              color: AppCouleurs.marine),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Comparer les prix (${fiche.nbBoutiques} '
                              'boutiques)',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      if (moinsCherAilleurs) ...<Widget>[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppCouleurs.succes.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.savings_rounded,
                                  size: 18, color: AppCouleurs.succes),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Moins cher ailleurs : '
                                  '${formatMontant(fiche.prixMin)} / '
                                  '${produit.unite}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppCouleurs.succes,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      for (final ProduitPublic offre in fiche.comparaisonTriees)
                        _ligneComparaison(theme, offre, fiche),
                      const SizedBox(height: 6),
                      Text(
                        'Vérifiez toujours la distance et la disponibilité '
                        'avant de vous déplacer.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (fiche.publicites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
              child: Column(
                children: <Widget>[
                  for (final PubliciteBiashara pub in fiche.publicites)
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
        ],
      ),
    );
  }

  /// Une ligne de comparaison « boutique · distance · prix ».
  Widget _ligneComparaison(
    ThemeData theme,
    ProduitPublic offre,
    FicheProduitPublic fiche,
  ) {
    final bool estConsulte =
        offre.publicationId == fiche.produit.publicationId;

    return InkWell(
      onTap: estConsulte
          ? null
          : () => context.push('/biashara/produit/${offre.publicationId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 4,
              child: Row(
                children: <Widget>[
                  if (estConsulte)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.check_circle_rounded,
                          size: 14, color: AppCouleurs.marine),
                    ),
                  Expanded(
                    child: Text(
                      offre.boutique.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight:
                            estConsulte ? FontWeight.w900 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
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
                formatMontant(offre.prix),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: offre.prix == fiche.prixMin
                      ? AppCouleurs.succes
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
