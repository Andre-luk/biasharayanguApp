// lib/pages/articles_page.dart
//
// MODULE 5 — ÉCRAN « LISTE DES ARTICLES »
//
//   • liste depuis `public.produits` filtrée sur la boutique courante ;
//   • colonnes : nom, catégorie, prix de vente, stock (unité de base),
//     nombre de conditionnements ;
//   • recherche par nom / code (code-barre ou QR des conditionnements) ;
//   • filtre par catégorie (référentiel `public.categories`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/categorie.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/statut_expiration.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/peremption_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/code_barre_lecteur.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Liste des articles de la boutique (Module 5).
class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  static const int _seuilStockBas = 5;

  final ArticleService _service = ArticleService.instance;
  final TextEditingController _rechercheController = TextEditingController();

  // -------------------------------------------------------------------------
  // 🏷️ CORRECTIF 59 — RECHERCHE PAR CODE-BARRES
  // -------------------------------------------------------------------------

  /// Retrouve un article en scannant son code-barres.
  ///
  /// Le nom trouvé est placé dans le champ de recherche : la liste se filtre
  /// aussitôt sur le bon produit. C'est le geste attendu au comptoir quand on
  /// ne connaît pas le libellé exact de l'article.
  Future<void> _scannerPourRechercher() async {
    final String? code = await lireCodeBarre(
      context,
      titre: 'Rechercher un article',
      aide: 'Visez le code-barres du produit.',
    );
    if (code == null || !mounted) return;

    try {
      final Article? article =
          await ArticleService.instance.trouverParCodeBarre(code);
      if (!mounted) return;

      if (article == null) {
        _messageScan('Aucun article ne porte le code « $code ».\n'
            'Vous pouvez l\'ajouter depuis le formulaire d\'article.');
        return;
      }

      setState(() => _rechercheController.text = article.nom);
      _messageScan('${article.nom} trouvé.');
    } catch (e) {
      debugPrint('ArticlesPage._scannerPourRechercher : $e');
      if (mounted) {
        _messageScan('Recherche impossible : vérifiez votre réseau.');
      }
    }
  }

  void _messageScan(String texte) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texte), duration: const Duration(seconds: 3)),
    );
  }

  /// 🧮 CORRECTIF 72 — lit le délai d'alerte de péremption de la boutique.
  ///
  /// Best-effort : si la lecture échoue (réseau, migration non exécutée), le
  /// délai reste celui par défaut. Aucun écran ne doit se vider parce qu'un
  /// réglage n'a pas pu être lu.
  Future<void> _chargerDelaiPeremption() async {
    final int delai = await PeremptionService.instance.charger();
    if (!mounted || delai == _delaiPeremption) return;
    setState(() => _delaiPeremption = delai);
  }

  List<Article> _articles = const <Article>[];
  List<Categorie> _categories = const <Categorie>[];
  bool _chargement = true;
  String? _erreur;

  /// 🧮 CORRECTIF 72 — délai d'alerte de péremption RÉGLÉ PAR LA BOUTIQUE.
  ///
  /// Le service le garde en mémoire après la première lecture : les cartes de
  /// la liste n'attendent donc rien. Sa valeur par défaut (30 jours) est celle
  /// qui avait cours avant le correctif — aucune alerte ne change de camp au
  /// premier affichage.
  int _delaiPeremption = PeremptionService.delaiParDefaut;

  /// `null` = toutes les catégories.
  String? _filtreCategorie;

  RealtimeChannel? _canalTempsReel;
  Timer? _antiRebondTempsReel;

  @override
  void initState() {
    super.initState();
    _rechercheController.addListener(_rafraichir);
    _demarrerEcouteTempsReel();
    _chargerDelaiPeremption();
    _charger();
  }

  @override
  void dispose() {
    _antiRebondTempsReel?.cancel();

    final RealtimeChannel? canal = _canalTempsReel;
    if (canal != null) {
      unawaited(_service.arreterEcoute(canal));
    }

    _rechercheController.removeListener(_rafraichir);
    _rechercheController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // TEMPS RÉEL
  // ---------------------------------------------------------------------------

  void _demarrerEcouteTempsReel() {
    try {
      _canalTempsReel = _service.ecouterChangements(_planifierRechargement);
    } catch (e) {
      // Le temps réel est un confort : son indisponibilité ne doit jamais
      // empêcher l'écran de fonctionner.
      debugPrint('ArticlesPage : temps réel indisponible ($e)');
    }
  }

  void _planifierRechargement() {
    _antiRebondTempsReel?.cancel();
    _antiRebondTempsReel = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _charger(silencieux: true);
    });
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    List<Article> articles = const <Article>[];
    List<Categorie> categories = const <Categorie>[];
    String? messageErreur;

    try {
      final List<dynamic> resultats = await Future.wait<dynamic>(<Future<dynamic>>[
        _service.getArticles(),
        _service.getCategories(),
      ]);
      articles = resultats[0] as List<Article>;
      categories = resultats[1] as List<Categorie>;
    } on ArticleServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ArticlesPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des articles.';
    }

    if (!mounted) return;

    if (messageErreur != null) {
      if (silencieux) {
        _afficherMessage(messageErreur, estErreur: true);
        return;
      }
      setState(() {
        _erreur = messageErreur;
        _chargement = false;
      });
      return;
    }

    setState(() {
      _articles = articles;
      _categories = categories;
      _erreur = null;
      _chargement = false;

      // Un filtre qui ne correspond plus à aucune catégorie connue est
      // réinitialisé (évite une sélection fantôme dans la liste déroulante).
      if (_filtreCategorie != null &&
          !_categoriesDisponibles.contains(_filtreCategorie)) {
        _filtreCategorie = null;
      }
    });
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // FILTRAGE
  // ---------------------------------------------------------------------------

  List<Article> get _articlesFiltres => ArticleService.filtrer(
        _articles,
        recherche: _rechercheController.text,
        categorie: _filtreCategorie,
      );

  /// Catégories proposées en filtre : le référentiel, complété par les
  /// catégories réellement utilisées par les articles (données historiques
  /// saisies avant le référentiel).
  List<String> get _categoriesDisponibles {
    final Set<String> noms = <String>{
      for (final Categorie categorie in _categories)
        if (categorie.nom.trim().isNotEmpty) categorie.nom.trim(),
      for (final Article article in _articles)
        if (article.categorie.trim().isNotEmpty) article.categorie.trim(),
    };
    final List<String> liste = noms.toList()..sort();
    return liste;
  }

  List<DropdownMenuItem<String?>> get _itemsCategories {
    return <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Toutes les catégories'),
      ),
      ..._categoriesDisponibles.map(
        (String nom) => DropdownMenuItem<String?>(
          value: nom,
          child: Text(nom, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirCreation() async {
    final bool? cree = await context.push<bool>('/main/articles/new');
    if (!mounted || cree != true) return;

    _afficherMessage('Article créé avec succès.');
    await _charger(silencieux: true);
  }

  Future<void> _ouvrirDetail(Article article) async {
    await context.push<bool>('/main/articles/${article.id}', extra: article);
    if (!mounted) return;
    await _charger(silencieux: true);
  }

  Future<void> _ouvrirCategories() async {
    await context.push<bool>('/main/articles/categories');
    if (!mounted) return;
    await _charger(silencieux: true);
  }

  /// 🗂️ MODULE 12 — import rapide d'articles (CSV/TSV), journalisé
  /// (`IMPORT_PRODUITS`). La permission `articles/creer` est exigée par la
  /// route ET par la RPC serveur.
  Future<void> _ouvrirImport() async {
    final bool? importe = await context.push<bool>('/import-produits');
    if (!mounted) return;
    if (importe == true) {
      _afficherMessage('Import terminé : la liste a été actualisée.');
    }
    await _charger(silencieux: true);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  void _afficherMessage(String message, {bool estErreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: estErreur
            ? Colors.red.shade700
            : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatQuantite(double quantite) {
    if (quantite == quantite.roundToDouble()) {
      return quantite.toStringAsFixed(0);
    }
    return quantite
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  Color _couleurStock(double quantite) {
    if (quantite <= 0) return Colors.red.shade700;
    if (quantite <= _seuilStockBas) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  Widget _vignette(Article article) {
    final String? photo = article.photo;
    if (photo != null && photo.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          photo,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconeParDefaut(),
        ),
      );
    }
    return _iconeParDefaut();
  }

  Widget _iconeParDefaut() {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.inventory_2_rounded, color: colorScheme.primary),
    );
  }

  Widget _carteArticle(Article article) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: _vignette(article),
        title: Text(
          article.nom,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${article.categorie.trim().isEmpty ? 'Sans catégorie' : article.categorie}'
                ' · ${formatMontant(article.prixVente)}'
                // 🥩 MODULE 16 C6 — boucherie : prix au kg bien visible.
                '${article.vendableAuPoids ? ' / kg 🥩' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              // 👕 MODULE 16 C8 — mode : variantes (M · Bleu · Casino…).
              if (article.aVariantes)
                Text(
                  '👕 ${article.resumeVariantes}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              // 🧮 CORRECTIF 72 — la péremption, visible ICI, dans la boutique.
              if (article.aDateExpiration) _lignePeremption(article),
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${_formatQuantite(article.quantite)} ${article.uniteMesure}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _couleurStock(article.quantite),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              article.nombreConditionnements == 1
                  ? '1 conditionnement'
                  : '${article.nombreConditionnements} conditionnements',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        onTap: () => _ouvrirDetail(article),
      ),
    );
  }

  /// 🧮 CORRECTIF 72 — la péremption d'un article, lisible d'un coup d'œil
  /// DANS la boutique.
  ///
  /// Avant, il fallait penser à ouvrir l'écran « Expirations » : un commerçant
  /// qui parcourait son catalogue ne voyait **rien**. Le modèle exposait
  /// pourtant `estExpire` et `expireBientot` — aucun écran ne les utilisait.
  ///
  /// La couleur suit le statut calculé avec le DÉLAI DE LA BOUTIQUE, pas avec
  /// un 30 jours figé : une pharmacie qui règle 90 jours doit voir la même
  /// alerte ici que sur l'écran Expirations.
  Widget _lignePeremption(Article article) {
    final StatutExpiration? statut =
        article.statutExpirationSelon(_delaiPeremption);
    if (statut == null) return const SizedBox.shrink();

    final int? jours = StatutExpiration.joursRestants(article.dateExpiration);

    final (IconData icone, Color couleur) = switch (statut) {
      StatutExpiration.expire => (Icons.dangerous_rounded, Colors.red.shade700),
      StatutExpiration.proche => (
          Icons.schedule_rounded,
          Colors.orange.shade800
        ),
      StatutExpiration.valide => (
          Icons.event_available_rounded,
          Colors.grey.shade700
        ),
    };

    final String lot =
        (article.lotNumero ?? '').trim().isEmpty ? '' : 'Lot ${article.lotNumero} · ';

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: <Widget>[
          Icon(icone, size: 14, color: couleur),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '$lot${_jourAffiche(article.dateExpiration!)}'
              ' · ${StatutExpiration.libelleJours(jours)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: couleur,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _jourAffiche(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  Widget _vueVide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _articles.isEmpty
                  ? "Aucun article pour le moment.\nAjoutez votre premier article pour commencer."
                  : 'Aucun article ne correspond à la recherche.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vueErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              _erreur ?? 'Erreur inconnue.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _charger(),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Article> affiches = _articlesFiltres;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Articles',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          // La gestion des catégories exige « articles / modifier » : le
          // bouton est masqué pour les rôles en lecture seule.
          PermissionGate(
            page: PageAccess.articles,
            action: ActionAccess.modifier,
            child: IconButton(
              onPressed: _ouvrirCategories,
              icon: const Icon(Icons.category_outlined),
              tooltip: 'Gérer les catégories',
            ),
          ),
          // 🔳 MODULE 6 — gestion et impression des QR codes.
          PermissionGate(
            page: PageAccess.qrCodes,
            action: ActionAccess.voir,
            child: IconButton(
              onPressed: () => context.push('/main/qr-codes'),
              icon: const Icon(Icons.qr_code_2_rounded),
              tooltip: 'Gestion des QR codes',
            ),
          ),
          // 🗂️ MODULE 12 — import rapide d'articles (coller un CSV ou
          // choisir un fichier) ; le stock existant n'est jamais écrasé.
          PermissionGate(
            page: PageAccess.articles,
            action: ActionAccess.creer,
            child: IconButton(
              onPressed: _ouvrirImport,
              icon: const Icon(Icons.upload_file_rounded),
              tooltip: 'Importer des articles (CSV)',
            ),
          ),
          // 🏷️ CORRECTIF 59 — retrouver un article en scannant son code.
          IconButton(
            onPressed: _scannerPourRechercher,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Rechercher par code-barres',
          ),
          IconButton(
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _chargement && _articles.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null && _articles.isEmpty
              ? _vueErreur()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Column(
                        children: [
                          TextField(
                            controller: _rechercheController,
                            decoration: InputDecoration(
                              hintText: 'Rechercher un article (nom, code-barre…)',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          AppDropdownField<String?>(
                            label: 'Catégorie',
                            value: _filtreCategorie,
                            prefixIcon: Icons.filter_alt_outlined,
                            items: _itemsCategories,
                            onChanged: (String? valeur) {
                              setState(() => _filtreCategorie = valeur);
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () => _charger(silencieux: true),
                        color: Theme.of(context).colorScheme.primary,
                        child: affiches.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height:
                                        MediaQuery.of(context).size.height * 0.4,
                                    child: _vueVide(),
                                  ),
                                ],
                              )
                            : ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                                children:
                                    affiches.map(_carteArticle).toList(),
                              ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: PermissionGateBouton(
        page: PageAccess.articles,
        action: ActionAccess.creer,
        builder: (BuildContext context) => FloatingActionButton.extended(
          onPressed: _ouvrirCreation,
          icon: const Icon(Icons.add),
          label: const Text('Nouvel article'),
        ),
      ),
    );
  }
}
