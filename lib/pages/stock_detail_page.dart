// lib/pages/stock_detail_page.dart
//
// MODULE 9 — ÉCRAN « DÉTAIL STOCK ARTICLE ».
//
//   • stock actuel en unité de base + statut (OK / Faible / Rupture) ;
//   • décomposition en conditionnements (« 1 004 bouteilles = 83 fardes de
//     12 + 8 bouteilles ») ;
//   • seuil d'alerte CONFIGURABLE (dialog, RPC `rpc_stock_definir_seuil`) ;
//   • actions : entrée de stock, ajustement d'inventaire ;
//   • historique des mouvements (approvisionnements, ventes, ajustements).
//
// Les mouvements proviennent des trois tables historiques ; le stock affiché
// vient de `produits.quantite`, mis à jour par les triggers serveur.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/mouvement_article.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/statut_stock.dart';
import 'package:biashara_yangu/models/stock_article.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/stock_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';
import 'package:biashara_yangu/widgets/statut_stock_chip.dart';

/// Fiche stock d'un article (Module 9).
class StockDetailPage extends StatefulWidget {
  const StockDetailPage({
    super.key,
    required this.articleId,
    this.article,
  });

  final int articleId;

  /// Article transmis par la liste (affichage immédiat avant rechargement).
  final Article? article;

  @override
  State<StockDetailPage> createState() => _StockDetailPageState();
}

class _StockDetailPageState extends State<StockDetailPage> {
  final StockService _service = StockService.instance;

  Article? _article;
  List<MouvementArticle> _mouvements = const <MouvementArticle>[];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _charger();
  }

  Future<void> _charger() async {
    if (!mounted) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final Article? article = await _service.getArticle(widget.articleId);
      if (article == null) {
        if (!mounted) return;
        setState(() {
          _article = null;
          _erreur = "Cet article n'existe plus.";
          _chargement = false;
        });
        return;
      }

      List<MouvementArticle> mouvements = const <MouvementArticle>[];
      try {
        mouvements = await _service.getMouvements(article.id);
      } catch (e) {
        // L'historique est best-effort : son échec ne bloque pas la fiche.
        debugPrint('StockDetailPage historique ignoré: $e');
      }

      if (!mounted) return;
      setState(() {
        _article = article;
        _mouvements = mouvements;
        _chargement = false;
        _erreur = null;
      });
    } on ArticleServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } on StockServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e, st) {
      debugPrint('StockDetailPage._charger: $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreur = 'Une erreur inattendue est survenue.';
        _chargement = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _modifierSeuil() async {
    final Article? article = _article;
    if (article == null) return;

    final double? seuil = await showDialog<double>(
      context: context,
      builder: (BuildContext context) => _DialogSeuil(
        article: article,
        seuilActuel: article.seuilAlerte,
      ),
    );

    if (!mounted || seuil == null) return;

    try {
      await _service.definirSeuil(produitId: article.id, seuil: seuil);
      if (!mounted) return;
      _afficherMessage("Seuil d'alerte enregistré : ${formatQuantite(seuil)} ${article.uniteMesure}.");
      await _charger();
    } on StockServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    }
  }

  Future<void> _ouvrirApprovisionnement() async {
    final Article? article = _article;
    if (article == null) return;

    final bool? change =
        await context.push<bool>('/main/stock/approvisionnement', extra: article);
    if (!mounted || change != true) return;
    _afficherMessage('Entrée de stock enregistrée.');
    await _charger();
  }

  Future<void> _ouvrirAjustement() async {
    final Article? article = _article;
    if (article == null) return;

    final bool? change =
        await context.push<bool>('/main/stock/ajustement', extra: article);
    if (!mounted || change != true) return;
    _afficherMessage('Stock ajusté.');
    await _charger();
  }

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

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _carteStock(Article article) {
    final ThemeData theme = Theme.of(context);
    final StatutStock statut = article.statutStock;
    final Color couleur = couleurStatutStock(statut);
    final List<DecompositionStock> decompositions =
        StockCalculs.decompositions(article);

    return Card(
      elevation: 0,
      color: couleur.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    article.nom,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                StatutStockChip(statut: statut),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${formatQuantite(article.quantite)} ${article.uniteMesure}',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: couleur,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              statut == StatutStock.rupture
                  ? 'Rupture de stock : réapprovisionnez cet article.'
                  : statut == StatutStock.faible
                      ? "Stock faible : sous le seuil d'alerte "
                          '(${formatQuantite(article.seuilAlerte)} ${article.uniteMesure}).'
                      : 'Stock au-dessus du seuil '
                          '(${formatQuantite(article.seuilAlerte)} ${article.uniteMesure}).',
              style: theme.textTheme.bodySmall,
            ),
            if (decompositions.isNotEmpty) ...<Widget>[
              const Divider(height: 24),
              Text(
                'Décomposition en conditionnements',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              ...decompositions.map((DecompositionStock d) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.subdirectory_arrow_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          d.exemplaires > 0
                              ? '${d.exemplaires} × ${d.conditionnement.libelle}'
                                  '${d.reste > 0 ? ' + ${formatQuantite(d.reste)} ${article.uniteMesure}' : ''}'
                                  '  (= ${formatQuantite(d.quantiteRegroupee)} ${article.uniteMesure})'
                              : 'moins de 1 × ${d.conditionnement.libelle}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _carteSeuil(Article article) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          Icons.notifications_active_outlined,
          color: theme.colorScheme.primary,
        ),
        title: const Text(
          "Seuil d'alerte",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Prévient dès que le stock atteint ${formatQuantite(article.seuilAlerte)} '
          '${article.uniteMesure}.',
        ),
        trailing: PermissionGate(
          page: PageAccess.stock,
          action: ActionAccess.modifier,
          child: TextButton.icon(
            onPressed: _modifierSeuil,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Modifier'),
          ),
        ),
      ),
    );
  }

  Widget _carteActions() {
    return Row(
      children: <Widget>[
        Expanded(
          child: PermissionGate(
            page: PageAccess.stock,
            action: ActionAccess.creer,
            child: FilledButton.icon(
              onPressed: _ouvrirApprovisionnement,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Entrée'),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PermissionGate(
            page: PageAccess.stock,
            action: ActionAccess.modifier,
            child: OutlinedButton.icon(
              onPressed: _ouvrirAjustement,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Ajuster'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionMouvements() {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Historique des mouvements',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (_mouvements.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Aucun mouvement enregistré pour cet article.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              ..._mouvements.map((MouvementArticle mouvement) {
                final bool entree = mouvement.estEntree;
                final Color couleurEntree = Colors.green.shade700;
                final Color couleurSortie = Colors.red.shade700;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        (entree ? couleurEntree : couleurSortie).withValues(alpha: 0.12),
                    child: Icon(
                      entree ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                      size: 16,
                      color: entree ? couleurEntree : couleurSortie,
                    ),
                  ),
                  title: Text(
                    mouvement.source.libelle +
                        ((mouvement.motif ?? '').isNotEmpty
                            ? ' · ${mouvement.motif}'
                            : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    formatDateHeure(mouvement.date),
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Text(
                    formatQuantiteSignee(mouvement.quantite),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: entree ? couleurEntree : couleurSortie,
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Article? article = _article;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Fiche stock',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          IconButton(
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _chargement && article == null
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null && article == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _erreur!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                )
              : article == null
                  ? const Center(child: Text('Article introuvable.'))
                  : RefreshIndicator(
                      onRefresh: _charger,
                      color: Theme.of(context).colorScheme.primary,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: <Widget>[
                          _carteStock(article),
                          const SizedBox(height: 12),
                          _carteActions(),
                          const SizedBox(height: 12),
                          _carteSeuil(article),
                          const SizedBox(height: 12),
                          _sectionMouvements(),
                          const SizedBox(height: 12),
                          if (article.conditionnements.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: OutlinedButton.icon(
                                onPressed: () => context.push(
                                  '/main/articles/${article.id}',
                                  extra: article,
                                ),
                                icon: const Icon(Icons.inventory_2_outlined),
                                label: const Text('Ouvrir la fiche article'),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }
}

/// Dialog de modification du seuil d'alerte.
class _DialogSeuil extends StatefulWidget {
  const _DialogSeuil({required this.article, required this.seuilActuel});

  final Article article;
  final double seuilActuel;

  @override
  State<_DialogSeuil> createState() => _DialogSeuilState();
}

class _DialogSeuilState extends State<_DialogSeuil> {
  late final TextEditingController _controller;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: formatQuantite(widget.seuilActuel));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _valider() {
    final double? valeur = double.tryParse(
      _controller.text.trim().replaceAll(',', '.'),
    );
    if (valeur == null || valeur < 0) {
      setState(() {
        _erreur = 'Saisissez un nombre positif ou nul.';
      });
      return;
    }
    Navigator.of(context).pop(valeur);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text("Seuil d'alerte", style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.article.nom,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Stock actuel : ${formatQuantite(widget.article.quantite)} '
            '${widget.article.uniteMesure}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: "Seuil (${widget.article.uniteMesure})",
              errorText: _erreur,
              prefixIcon: const Icon(Icons.notifications_active_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onSubmitted: (_) => _valider(),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valider,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
