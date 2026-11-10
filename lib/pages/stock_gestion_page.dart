// lib/pages/stock_gestion_page.dart
//
// MODULE 9 — ÉCRAN « STOCK » (tableau de bord magasinier).
//
//   • résumé : articles, alertes, valeur du stock (prix d'achat) ;
//   • bannière d'ALERTES : ruptures (urgence) et articles sous le seuil ;
//   • liste des articles : stock en unité de base, décomposition en
//     conditionnements (ex. « 83 × Farde de 12 + 8 bouteilles »), seuil,
//     statut OK / Faible / Rupture ;
//   • filtres : catégorie, statut ; recherche nom / code-barre ;
//   • actions rapides par article : entrée de stock, ajustement ;
//   • accès à la clôture d'inventaire quotidien.
//
// Toutes les données viennent de Supabase (`public.produits` + seuil d'alerte
// ajouté par la migration Module 9). Le stock est rafraîchi en temps réel :
// chaque mouvement (vente, approvisionnement, ajustement) modifie
// `produits.quantite` côté serveur.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/categorie.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/statut_stock.dart';
import 'package:biashara_yangu/models/stock_article.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/stock_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';
import 'package:biashara_yangu/widgets/statut_stock_chip.dart';

/// Filtre de statut de la liste.
enum _FiltreStatut {
  tous('Tous'),
  ok('OK'),
  faible('Faible'),
  rupture('Rupture');

  const _FiltreStatut(this.libelle);

  final String libelle;

  StatutStock? get statut => switch (this) {
        _FiltreStatut.tous => null,
        _FiltreStatut.ok => StatutStock.ok,
        _FiltreStatut.faible => StatutStock.faible,
        _FiltreStatut.rupture => StatutStock.rupture,
      };
}

/// Écran principal de gestion du stock (Module 9).
class StockGestionPage extends StatefulWidget {
  const StockGestionPage({super.key});

  @override
  State<StockGestionPage> createState() => _StockGestionPageState();
}

class _StockGestionPageState extends State<StockGestionPage> {
  final StockService _service = StockService.instance;
  final TextEditingController _rechercheController = TextEditingController();

  List<Article> _articles = const <Article>[];
  List<Categorie> _categories = const <Categorie>[];
  bool _chargement = true;
  String? _erreur;

  _FiltreStatut _filtreStatut = _FiltreStatut.tous;
  String? _filtreCategorie;

  RealtimeChannel? _canalTempsReel;
  Timer? _antiRebond;

  @override
  void initState() {
    super.initState();
    _rechercheController.addListener(_rafraichir);
    _demarrerEcouteTempsReel();
    _charger();
  }

  @override
  void dispose() {
    _antiRebond?.cancel();

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
      debugPrint('StockGestionPage : temps réel indisponible ($e)');
    }
  }

  void _planifierRechargement() {
    _antiRebond?.cancel();
    _antiRebond = Timer(const Duration(milliseconds: 800), () {
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
        _service.getStock(),
        ArticleService.instance.getCategories(),
      ]);
      articles = resultats[0] as List<Article>;
      categories = resultats[1] as List<Categorie>;
    } on ArticleServiceException catch (e) {
      messageErreur = e.message;
    } on StockServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('StockGestionPage._charger: $e\n$st');
      messageErreur = 'Une erreur inattendue est survenue lors du chargement du stock.';
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
  // FILTRES
  // ---------------------------------------------------------------------------

  /// Articles après recherche + filtre catégorie (avant filtre statut).
  List<Article> get _baseFiltree => ArticleService.filtrer(
        _articles,
        recherche: _rechercheController.text,
        categorie: _filtreCategorie,
      );

  /// Liste affichée : filtres + tri par urgence (ruptures d'abord).
  List<Article> get _articlesAffiches {
    final StatutStock? statut = _filtreStatut.statut;
    final List<Article> liste = statut == null
        ? _baseFiltree
        : _baseFiltree
            .where((Article a) => StockCalculs.statut(a) == statut)
            .toList(growable: false);
    return StockCalculs.trierParUrgence(liste);
  }

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

  int _nombrePour(_FiltreStatut filtre) {
    final StatutStock? statut = filtre.statut;
    if (statut == null) return _baseFiltree.length;
    return _baseFiltree
        .where((Article a) => StockCalculs.statut(a) == statut)
        .length;
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirDetail(Article article) async {
    await context.push<bool>('/main/stock/${article.id}', extra: article);
    if (!mounted) return;
    await _charger(silencieux: true);
  }

  Future<void> _ouvrirApprovisionnement(Article? article) async {
    final bool? change = await context.push<bool>(
      '/main/stock/approvisionnement',
      extra: article,
    );
    if (!mounted || change != true) return;
    _afficherMessage("Entrée de stock enregistrée.");
    await _charger(silencieux: true);
  }

  Future<void> _ouvrirAjustement(Article article) async {
    final bool? change = await context.push<bool>(
      '/main/stock/ajustement',
      extra: article,
    );
    if (!mounted || change != true) return;
    _afficherMessage('Stock ajusté.');
    await _charger(silencieux: true);
  }

  Future<void> _ouvrirInventaire() async {
    final bool? cloture = await context.push<bool>('/main/stock/inventaire');
    if (!mounted || cloture != true) return;
    _afficherMessage('Inventaire clôturé.');
    await _charger(silencieux: true);
  }

  /// 📦 SORTIES DE STOCK SPÉCIALES — consommation du propriétaire, article
  /// offert, perte, casse, retour fournisseur… Le stock diminue, la caisse NON.
  Future<void> _ouvrirSorties(Article? article) async {
    await context.push<bool>('/main/stock/sorties', extra: article);
    if (!mounted) return;
    await _charger(silencieux: true);
  }

  Future<void> _ouvrirAlertes() async {
    final List<Article> alertes = StockCalculs.enAlerte(_articles);
    if (alertes.isEmpty) return;

    final Article? choisi = await showModalBottomSheet<Article>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return _PanneauAlertes(alertes: alertes);
      },
    );

    if (!mounted || choisi == null) return;
    await _ouvrirDetail(choisi);
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

  /// Décomposition courte pour la carte : « 83 × Farde de 12 + 8 bouteilles ».
  String? _decompositionCourte(Article article) {
    final DecompositionStock? decomposition =
        StockCalculs.decompositionPrincipale(article);
    if (decomposition == null || decomposition.exemplaires <= 0) return null;

    final String groupe = '${decomposition.exemplaires} × '
        '${decomposition.conditionnement.libelle}';
    if (decomposition.estExact) return '= $groupe';
    return '$groupe + ${formatQuantite(decomposition.reste)} ${article.uniteMesure}';
  }

  Widget _carteStatistique(String libelle, String valeur, {Color? couleur}) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            valeur,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: couleur,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            libelle,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _entete() {
    final ThemeData theme = Theme.of(context);
    final int ruptures = StockCalculs.compter(_articles, StatutStock.rupture);
    final int faibles = StockCalculs.compter(_articles, StatutStock.faible);
    final int alertes = ruptures + faibles;
    final double valeur = StockCalculs.valeurAchat(_articles);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ------------------------------------------------ résumé magasinier
          Card(
            elevation: 0,
            color: theme.colorScheme.primary.withValues(alpha: 0.07),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: <Widget>[
                  _carteStatistique('Articles', '${_articles.length}'),
                  _carteStatistique(
                    'En alerte',
                    '$alertes',
                    couleur: alertes > 0 ? Colors.orange.shade800 : null,
                  ),
                  _carteStatistique('Valeur stock', formatMontant(valeur)),
                ],
              ),
            ),
          ),

          // ------------------------------------------------------- alertes
          if (alertes > 0) ...<Widget>[
            const SizedBox(height: 8),
            Material(
              color: (ruptures > 0 ? Colors.red.shade700 : Colors.orange.shade800)
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _ouvrirAlertes,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        ruptures > 0
                            ? Icons.error_rounded
                            : Icons.warning_amber_rounded,
                        color: ruptures > 0
                            ? Colors.red.shade700
                            : Colors.orange.shade800,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ruptures > 0
                              ? '$ruptures article(s) en rupture'
                                  '${faibles > 0 ? ' · $faibles sous le seuil' : ''}'
                              : '$faibles article(s) sous le seuil d\'alerte',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ruptures > 0
                                ? Colors.red.shade700
                                : Colors.orange.shade900,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // ------------------------------------------------- recherche/filtres
          const SizedBox(height: 10),
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
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _FiltreStatut.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (BuildContext context, int index) {
                final _FiltreStatut filtre = _FiltreStatut.values[index];
                final bool selectionne = filtre == _filtreStatut;
                final int nombre = _nombrePour(filtre);
                final Color? couleur =
                    filtre.statut == null ? null : couleurStatutStock(filtre.statut!);

                return ChoiceChip(
                  label: Text('${filtre.libelle} ($nombre)'),
                  selected: selectionne,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selectionne ? FontWeight.w700 : FontWeight.w500,
                    // Sélectionné : couleur du thème (lisible sur le fond
                    // marine) ; sinon : couleur du statut, avec repli lisible.
                    color: selectionne
                        ? Theme.of(context).colorScheme.onPrimary
                        : (couleur ??
                            Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  onSelected: (_) => setState(() => _filtreStatut = filtre),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteArticle(Article article) {
    final ThemeData theme = Theme.of(context);
    final StatutStock statut = article.statutStock;
    final Color couleur = couleurStatutStock(statut);
    final String? decomposition = _decompositionCourte(article);

    final bool peutEntrer = PermissionService.instance.peutCreer(PageAccess.stock);
    final bool peutAjuster = PermissionService.instance.peutModifier(PageAccess.stock);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.inventory_2_rounded, color: couleur, size: 22),
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                article.nom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            StatutStockChip(statut: statut),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${article.categorie.trim().isEmpty ? 'Sans catégorie' : article.categorie}'
                ' · Seuil : ${formatQuantite(article.seuilAlerte)} ${article.uniteMesure}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              if (decomposition != null)
                Text(
                  decomposition,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  formatQuantite(article.quantite),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: couleur,
                  ),
                ),
                Text(
                  article.uniteMesure,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (peutEntrer || peutAjuster)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                tooltip: 'Actions',
                onSelected: (String action) {
                  if (action == 'appro') {
                    _ouvrirApprovisionnement(article);
                  } else if (action == 'ajust') {
                    _ouvrirAjustement(article);
                  } else if (action == 'sortie') {
                    _ouvrirSorties(article);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  if (peutEntrer)
                    const PopupMenuItem<String>(
                      value: 'appro',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.add_box_outlined),
                        title: Text('Entrée de stock'),
                      ),
                    ),
                  if (peutAjuster)
                    const PopupMenuItem<String>(
                      value: 'ajust',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.tune_rounded),
                        title: Text('Ajuster le stock'),
                      ),
                    ),
                  if (peutAjuster)
                    const PopupMenuItem<String>(
                      value: 'sortie',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.outbox_rounded),
                        title: Text('Sortie de stock'),
                        subtitle: Text('Perte, casse, offert, consommation…'),
                      ),
                    ),
                ],
              ),
          ],
        ),
        onTap: () => _ouvrirDetail(article),
      ),
    );
  }

  Widget _vueVide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _articles.isEmpty
                  ? "Aucun article dans le stock.\nCréez d'abord un article dans le catalogue."
                  : 'Aucun article ne correspond aux filtres.',
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
          children: <Widget>[
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
    final List<Article> affiches = _articlesAffiches;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Stock',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          PermissionGate(
            page: PageAccess.stock,
            action: ActionAccess.modifier,
            child: IconButton(
              onPressed: () => _ouvrirSorties(null),
              icon: const Icon(Icons.outbox_rounded),
              tooltip: 'Sorties de stock (perte, casse, offert…)',
            ),
          ),
          PermissionGate(
            page: PageAccess.stock,
            action: ActionAccess.modifier,
            child: IconButton(
              onPressed: _ouvrirInventaire,
              icon: const Icon(Icons.fact_check_outlined),
              tooltip: "Clôture d'inventaire",
            ),
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
                  children: <Widget>[
                    _entete(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () => _charger(silencieux: true),
                        color: Theme.of(context).colorScheme.primary,
                        child: affiches.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: <Widget>[
                                  SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.35,
                                    child: _vueVide(),
                                  ),
                                ],
                              )
                            : ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                                children: affiches.map(_carteArticle).toList(),
                              ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: PermissionGateBouton(
        page: PageAccess.stock,
        action: ActionAccess.creer,
        builder: (BuildContext context) => FloatingActionButton.extended(
          onPressed: () => _ouvrirApprovisionnement(null),
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Entrée de stock'),
        ),
      ),
    );
  }
}

/// Panneau (bottom sheet) listant les articles en alerte.
class _PanneauAlertes extends StatelessWidget {
  const _PanneauAlertes({required this.alertes});

  final List<Article> alertes;

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
              'Alertes de stock',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Touchez un article pour ouvrir sa fiche stock.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: alertes.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final Article article = alertes[index];
                  final StatutStock statut = article.statutStock;
                  final Color couleur = couleurStatutStock(statut);

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(iconeStatutStock(statut), color: couleur),
                    title: Text(
                      article.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${formatQuantite(article.quantite)} ${article.uniteMesure}'
                      ' · seuil ${formatQuantite(article.seuilAlerte)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: StatutStockChip(statut: statut),
                    onTap: () => Navigator.of(context).pop(article),
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
