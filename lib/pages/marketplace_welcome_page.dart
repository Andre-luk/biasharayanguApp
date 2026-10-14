// lib/pages/marketplace_welcome_page.dart
//
// 🛒 MODULE 19 — PAGE PUBLIQUE « BIASHARA » (ACCESSIBLE SANS COMPTE).
//
// C'est la porte d'entrée du module : un visiteur — y compris un étranger qui
// ne connaît pas la ville — doit comprendre en quelques secondes qu'il peut
// « rechercher un produit et découvrir où l'acheter autour de lui ».
//
// Confidentialité : la position n'est demandée QUE si le visiteur touche
// « Autour de moi ». Elle sert au calcul des distances et n'est jamais
// transmise à Biashara ni conservée après la fermeture de l'application.
// Le bouton « Choisir une ville » offre exactement le même service sans
// aucun partage de position.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/accueil_public.dart';
import 'package:biashara_yangu/models/produit_public.dart';
import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/services/marketplace_service.dart';
import 'package:biashara_yangu/ui/mise_en_page_adaptative.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/geolocalisation.dart';
import 'package:biashara_yangu/widgets/carte_boutique_publique.dart';
import 'package:biashara_yangu/widgets/carte_produit_public.dart';
import 'package:biashara_yangu/widgets/choix_ville_sheet.dart';
import 'package:biashara_yangu/widgets/encart_publicitaire.dart';

class MarketplaceWelcomePage extends StatefulWidget {
  const MarketplaceWelcomePage({super.key});

  @override
  State<MarketplaceWelcomePage> createState() => _MarketplaceWelcomePageState();
}

class _MarketplaceWelcomePageState extends State<MarketplaceWelcomePage> {
  final TextEditingController _recherche = TextEditingController();
  final MarketplaceService _marketplace = MarketplaceService.instance;

  AccueilPublic? _accueil;
  bool _chargement = true;
  String? _erreur;
  bool _localisationEnCours = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    if (mounted) setState(() => _chargement = true);

    try {
      final AccueilPublic accueil = await _marketplace.accueil();
      if (!mounted) return;
      setState(() {
        _accueil = accueil;
        _erreur = null;
        _chargement = false;
      });

      // Mesure de VISIBILITÉ : on enregistre l'affichage effectif des
      // produits de l'accueil (jamais avant leur rendu à l'écran).
      await _marketplace.impressionsResultats(accueil.produits);
      for (final PubliciteBiashara pub in accueil.publicites) {
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

  /// « Autour de moi » : demande la position, puis recalcule tout.
  Future<void> _autourDeMoi() async {
    setState(() => _localisationEnCours = true);

    final ResultatPosition resultat =
        await Geolocalisation.instance.positionActuelle();

    if (!mounted) return;
    setState(() => _localisationEnCours = false);

    final PositionUtilisateur? position = resultat.position;
    if (position == null) {
      // Refus ou indisponibilité : on propose TOUT DE SUITE l'alternative,
      // sans insister ni redemander.
      _afficherMessage(resultat.message ?? 'Position indisponible.');
      final bool? choisir = await _confirmer(
        'Choisir une ville ?',
        'La recherche dans une ville donne exactement les mêmes résultats, '
            'sans partager votre position.',
      );
      if (choisir == true) await _choisirVille();
      return;
    }

    _marketplace.definirPosition(position.latitude, position.longitude);
    _afficherMessage('Position utilisée pour calculer les distances '
        '${position.precisionLibelle ?? ''}'.trim());
    await _charger();
  }

  /// Recherche dans une ville choisie (aucune géolocalisation requise).
  Future<void> _choisirVille() async {
    final ville = await ouvrirChoixVille(context);
    if (ville == null || !mounted) return;

    _marketplace.definirVille(ville.id, ville.nom);
    _afficherMessage('Recherche limitée à ${ville.nom}.');
    await _charger();
  }

  void _rechercher({String? texte}) {
    final String requete = (texte ?? _recherche.text).trim();
    final String suffixe =
        requete.isEmpty ? '' : '?q=${Uri.encodeComponent(requete)}';
    context.push('/biashara/recherche$suffixe');
  }

  void _rechercherCategorie(String categorie) {
    context.push(
      '/biashara/recherche?categorie=${Uri.encodeComponent(categorie)}',
    );
  }

  void _afficherMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _confirmer(String titre, String message) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(titre),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Choisir une ville'),
          ),
        ],
      ),
    );
  }

  /// Localité affichée dans l'en-tête (« Lubumbashi », « Toute la RDC »…).
  String get _contexteLocalisation {
    final String? ville = _marketplace.villeNomCourante;
    if (ville != null && ville.isNotEmpty) return ville;
    if (_marketplace.aPosition) return 'Autour de moi';
    return 'Toute la RDC';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _charger,
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            _entete(context),
            if (_chargement)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: ModernLoader(taille: 48)),
              )
            else if (_erreur != null)
              _etatErreur(context)
            else ..._sections(context),
            _piedDePage(context),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EN-TÊTE (HERO)
  // ---------------------------------------------------------------------------

  Widget _entete(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(gradient: AppDegrades.hero),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/Biashara_app_off-.png',
                    height: 38,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Biashara',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const Spacer(),
                // Accès au compte : discret mais explicite. Le visiteur peut
                // consulter tout le catalogue SANS se connecter ; ce bouton
                // sert uniquement aux commerçants et aux personnes déjà
                // inscrites (publication, gestion, favoris synchronisés).
                OutlinedButton.icon(
                  onPressed: () => context.go('/login'),
                  icon: const Icon(Icons.person_outline_rounded,
                      size: 18, color: Colors.white),
                  label: const Text(
                    'Mon compte',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Accroche de marque : elle donne l'identité du marketplace avant
            // la promesse fonctionnelle qui suit.
            Text(
              'Achetez. Vendez. Grandissez.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.94),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Trouvez ce dont vous avez besoin près de vous.',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                height: 1.15,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Recherchez un produit et découvrez où l\'acheter autour de '
              'vous — prix, boutique et distance.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _recherche,
              textInputAction: TextInputAction.search,
              onSubmitted: (String _) => _rechercher(),
              decoration: InputDecoration(
                hintText: 'Que recherchez-vous ? (riz, téléphone, chaussures…)',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: theme.colorScheme.surface,
                suffixIcon: IconButton(
                  tooltip: 'Rechercher',
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () => _rechercher(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                // Le champ de recherche ci-dessus possède déjà son bouton de
                // validation : un second bouton « Rechercher » faisait doublon
                // et consommait la largeur utile sur téléphone. L'espace gagné
                // revient à l'action propre au marketplace : la proximité.
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _localisationEnCours ? null : _autourDeMoi,
                    icon: _localisationEnCours
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded, size: 18),
                    label: const Text('Autour de moi'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _choisirVille,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.place_rounded,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      _contexteLocalisation,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _marketplace.aPosition
                          ? '· changer'
                          : '· changer de ville',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTIONS
  // ---------------------------------------------------------------------------

  List<Widget> _sections(BuildContext context) {
    final AccueilPublic accueil = _accueil ?? const AccueilPublic();

    if (accueil.vide) return <Widget>[_etatVide(context)];

    return <Widget>[
      // Publicités (emplacement dédié, jamais mêlé aux résultats organiques).
      if (accueil.publicites.isNotEmpty)
        _section(
          context,
          titre: 'À découvrir',
          sousTitre: 'Contenus sponsorisés, clairement identifiés',
          enfant: Column(
            children: <Widget>[
              for (final PubliciteBiashara pub in accueil.publicites)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: EncartPublicitaire(
                    publicite: pub,
                    onTap: () => _ouvrirPublicite(pub),
                  ),
                ),
            ],
          ),
        ),

      if (accueil.categories.isNotEmpty)
        _section(
          context,
          titre: 'Catégories populaires',
          enfant: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final CategoriePublique categorie in accueil.categories)
                ActionChip(
                  avatar: const Icon(Icons.local_offer_rounded, size: 16),
                  label: Text(
                    '${categorie.libelleAffiche}'
                    '${categorie.nbProduits > 0 ? ' (${categorie.nbProduits})' : ''}',
                  ),
                  onPressed: () => _rechercherCategorie(categorie.categorie),
                ),
            ],
          ),
        ),

      if (accueil.produits.isNotEmpty)
        _section(
          context,
          titre: 'Produits autour de vous',
          sousTitre:
              'Photo, prix, boutique et distance — comme dans une vitrine',
          enfant: Column(
            children: <Widget>[
              // 🎨 CORRECTIF 76 — la vitrine passe de la vignette horizontale à
              // une GRILLE : 2 colonnes sur téléphone, plus large sur tablette
              // et bureau. La proportion s'adapte à l'échelle de texte pour
              // qu'aucune carte ne déborde en accessibilité.
              LayoutBuilder(
                builder: (BuildContext ctx, BoxConstraints contraintes) {
                  final int colonnes = contraintes.maxWidth < 520
                      ? 2
                      : (contraintes.maxWidth < 900 ? 3 : 4);
                  return GridView.count(
                    crossAxisCount: colonnes,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: MiseEnPageAdaptative.proportionCarte(
                      context,
                      0.66,
                      minimum: 0.52,
                    ),
                    children: <Widget>[
                      for (final ProduitPublic produit in accueil.produits)
                        CarteProduitPublic(
                          produit: produit,
                          compacte: true,
                          onTap: () => _ouvrirProduit(produit),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/biashara/recherche'),
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                label: const Text('Voir tout le catalogue'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),

      if (accueil.boutiques.isNotEmpty)
        _section(
          context,
          titre: 'Boutiques à proximité',
          sousTitre: _marketplace.aPosition
              ? 'Classées par distance'
              : 'Dans la ville sélectionnée',
          enfant: Column(
            children: <Widget>[
              for (final boutique in accueil.boutiques)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CarteBoutiquePublique(
                    boutique: boutique,
                    onTap: () => _ouvrirBoutique(boutique.slug),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => context.push('/biashara/carte'),
                icon: const Icon(Icons.map_rounded, size: 18),
                label: const Text('Voir toutes les boutiques sur la carte'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),

      _sectionCommercants(context),
    ];
  }

  /// Bloc « POUR LES COMMERÇANTS » (acquisition).
  Widget _sectionCommercants(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppDegrades.primaire,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.storefront_rounded, color: Colors.white, size: 30),
            const SizedBox(height: 10),
            const Text(
              'Donnez plus de visibilité à votre boutique avec Biashara.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Votre boutique apparaît auprès des clients qui cherchent vos '
              'produits autour d\'eux. Suivez les vues, les appels et les '
              'itinéraires demandés.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => context.go('/setup'),
              icon: const Icon(Icons.add_business_rounded, size: 18),
              label: const Text('Enregistrer ma boutique'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppCouleurs.marine,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vous avez déjà un compte ?',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/login'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text(
                'Se connecter à mon espace',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String titre,
    required Widget enfant,
    String? sousTitre,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                titre,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              if (sousTitre != null)
                Text(
                  sousTitre,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
        ),
        if (enfant is SizedBox) enfant else Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: enfant,
        ),
      ],
    );
  }

  Widget _etatVide(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 40, 18, 10),
      child: Column(
        children: <Widget>[
          const Icon(Icons.storefront_rounded,
              size: 44, color: AppCouleurs.orange),
          const SizedBox(height: 12),
          Text(
            'Le catalogue Biashara se remplit.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Aucune boutique n\'est encore visible ici. Les commerçants '
            'rejoignent Biashara progressivement : republiez votre recherche '
            'dans quelques jours, ou inscrivez votre propre boutique.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          _sectionCommercants(context),
        ],
      ),
    );
  }

  Widget _etatErreur(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 40, 18, 20),
      child: Column(
        children: <Widget>[
          const Icon(Icons.wifi_off_rounded,
              size: 42, color: AppCouleurs.alerte),
          const SizedBox(height: 12),
          Text(
            _erreur ?? 'Catalogue indisponible.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
          const SizedBox(height: 26),
          // Le catalogue est injoignable (hors ligne, maintenance…) : on
          // laisse malgré tout au commerçant le chemin vers son espace ou vers
          // l'inscription, afin qu'AUCUN écran d'erreur ne soit une impasse.
          _sectionCommercants(context),
        ],
      ),
    );
  }

  Widget _piedDePage(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      child: Column(
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: <Widget>[
              TextButton(
                onPressed: () => context.push('/politique-confidentialite'),
                child: const Text('Confidentialité'),
              ),
              TextButton(
                onPressed: () => context.push('/conditions-utilisation'),
                child: const Text('Conditions d\'utilisation'),
              ),
            ],
          ),
          Text(
            'Biashara Tech — Lubumbashi, RDC',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Votre position sert uniquement à calculer les distances : elle '
            'n\'est ni transmise ni conservée.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION & MESURES
  // ---------------------------------------------------------------------------

  void _ouvrirProduit(ProduitPublic produit) {
    // INTÉRÊT : la fiche produit est consultée.
    _marketplace.evenement(
      type: 'vue_produit',
      entiteType: 'produit',
      entiteId: produit.publicationId,
      quartier: produit.boutique.quartier,
      distanceKm: produit.distanceKm,
    );
    context.push('/biashara/produit/${produit.publicationId}');
  }

  void _ouvrirBoutique(String? slug) {
    if (slug == null || slug.isEmpty) return;
    context.push('/biashara/boutique/$slug');
  }

  void _ouvrirPublicite(PubliciteBiashara pub) {
    // INTÉRÊT : clic sur une publicité (distinct du résultat organique).
    _marketplace.evenement(
      type: 'clic_publicite',
      entiteType: 'publicite',
      publiciteId: pub.id,
    );

    final String? chemin = pub.cheminPublic;
    if (chemin != null) context.push(chemin);
  }
}
