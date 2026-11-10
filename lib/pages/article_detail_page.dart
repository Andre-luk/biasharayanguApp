// lib/pages/article_detail_page.dart
//
// MODULE 5 — ÉCRAN « DÉTAIL ARTICLE »
//
//   • toutes les informations de l'article (prix, stock, catégorie…) ;
//   • liste des conditionnements avec leurs QR codes ;
//   • historique des mouvements de stock (entrées / sorties) ;
//   • actions : modifier, ajouter un conditionnement, supprimer l'article.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/etiquette_qr.dart';
import 'package:biashara_yangu/models/mouvement_article.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/qr_code_service.dart';
import 'package:biashara_yangu/utils/devise_produit.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

class ArticleDetailPage extends StatefulWidget {
  const ArticleDetailPage({super.key, required this.articleId, this.article});

  /// Identifiant de l'article (route `/main/articles/:id`).
  final int articleId;

  /// Article déjà chargé (passé en `extra` par la liste) : affichage
  /// immédiat, la fiche complète est rechargée juste après.
  final Article? article;

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  static const int _seuilStockBas = 5;

  final ArticleService _service = ArticleService.instance;

  Article? _article;
  List<MouvementArticle> _mouvements = const <MouvementArticle>[];
  bool _chargement = true;
  String? _erreur;
  bool _impressionEtiquettes = false;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    // Un article déjà passé en `extra` s'affiche immédiatement : le
    // rechargement (fiche complète + mouvements) se fait en silence.
    _chargement = widget.article == null;
    _charger();
  }

  Future<void> _charger() async {
    if (!mounted) return;

    if (_article == null) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    Article? article;
    List<MouvementArticle> mouvements = const <MouvementArticle>[];
    String? messageErreur;

    try {
      article = await _service.getArticleById(widget.articleId);
      if (article == null) {
        messageErreur = "Cet article n'existe plus dans la base de données.";
      } else {
        mouvements = await _service.getMouvements(article.id);
      }
    } on ArticleServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ArticleDetailPage._charger: $e\n$st');
      messageErreur =
          "Une erreur inattendue est survenue lors du chargement de l'article.";
    }

    if (!mounted) return;

    setState(() {
      if (messageErreur != null) {
        _erreur = messageErreur;
      } else {
        _article = article;
        _mouvements = mouvements;
        _erreur = null;
      }
      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _modifier() async {
    final Article? article = _article;
    if (article == null) return;

    final bool? modifie = await context.push<bool>(
      '/main/articles/${article.id}/edit',
      extra: article,
    );
    if (modifie == true) await _charger();
  }

  Future<void> _ajouterConditionnement() async {
    final Article? article = _article;
    if (article == null) return;

    final bool? cree = await context
        .push<bool>('/main/articles/${article.id}/conditionnements/new');
    if (cree == true) await _charger();
  }

  Future<void> _modifierConditionnement(Conditionnement conditionnement) async {
    final Article? article = _article;
    if (article == null) return;

    final bool? modifie = await context.push<bool>(
      '/main/articles/${article.id}/conditionnements/${conditionnement.id}/edit',
      extra: conditionnement,
    );
    if (modifie == true) await _charger();
  }

  // ---------------------------------------------------------------------------
  // QR CODES (Module 6)
  // ---------------------------------------------------------------------------

  /// `true` si le rôle connecté peut consulter les QR codes.
  bool get _peutVoirQr =>
      PermissionService.instance.peut(PageAccess.qrCodes, ActionAccess.voir);

  EtiquetteQr _etiquetteArticle(Article article) => EtiquetteQr(
        type: TypeQrCode.article,
        identifiant: '${article.id}',
        articleId: article.id,
        titre: article.nom,
      );

  EtiquetteQr _etiquetteConditionnement(
    Article article,
    Conditionnement conditionnement,
  ) =>
      EtiquetteQr(
        type: TypeQrCode.conditionnement,
        identifiant: conditionnement.qrCodeId,
        articleId: article.id,
        titre: article.nom,
        sousTitre: '${conditionnement.libelle} — '
            '${_formatQuantite(conditionnement.quantiteUnitesBase)} '
            '${Conditionnement.pluriel(article.uniteMesure, conditionnement.quantiteUnitesBase)}',
      );

  void _ouvrirApercuQr(EtiquetteQr etiquette) {
    context.push('/main/qr-codes/apercu', extra: etiquette);
  }

  /// Imprime une planche contenant l'article ET tous ses conditionnements.
  Future<void> _imprimerEtiquettes() async {
    final Article? article = _article;
    if (article == null) return;

    setState(() => _impressionEtiquettes = true);
    try {
      await QrCodeService.instance.imprimerEtiquettes(
        QrCodeService.etiquettesPourArticles(<Article>[article]),
        nomTravail: 'Etiquettes_article_${article.id}',
      );
      _afficherMessage('Planche PDF envoyée à l\'impression.');
    } on QrCodeServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    } finally {
      if (mounted) setState(() => _impressionEtiquettes = false);
    }
  }

  Future<void> _supprimerConditionnement(Conditionnement conditionnement) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Supprimer ce conditionnement ?'),
        content: Text('« ${conditionnement.libelle} » sera retiré du catalogue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (!mounted || confirme != true) return;

    try {
      await _service.supprimerConditionnement(conditionnement.id);
      _afficherMessage('Conditionnement supprimé.');
      await _charger();
    } on ArticleServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    }
  }

  Future<void> _supprimerArticle() async {
    final Article article = _article!;

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text("Supprimer cet article ?"),
        content: Text(
          '« ${article.nom} » et ses '
          '${article.nombreConditionnements} conditionnement(s) seront '
          'définitivement supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (!mounted || confirme != true) return;

    try {
      await _service.supprimerArticle(article.id);
      if (!mounted) return;
      _afficherMessage('Article supprimé.');
      context.pop(true);
    } on ArticleServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    }
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

  Widget _enTete(Article article) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((article.photo ?? '').isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  article.photo!,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 84,
                    height: 84,
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    child: Icon(Icons.inventory_2_rounded,
                        color: colorScheme.primary),
                  ),
                ),
              )
            else
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.inventory_2_rounded,
                    size: 40, color: colorScheme.primary),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.nom,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    article.categorie.trim().isEmpty
                        ? 'Sans catégorie'
                        : article.categorie,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if ((article.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      article.description!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneInfo(String libelle, String valeur, {Color? couleurValeur}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(libelle, style: const TextStyle(color: Colors.grey)),
          ),
          Text(
            valeur,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: couleurValeur,
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteInformations(Article article) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Informations',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _ligneInfo("Prix d'achat (unité)",
                prixArticle(article.prixAchat, article.devise)),
            _ligneInfo('Prix de vente (unité)',
                prixArticle(article.prixVente, article.devise)),
            _ligneInfo('Unité de base', article.uniteMesure),
            _ligneInfo(
              'Stock (unités de base)',
              '${_formatQuantite(article.quantite)} ${article.uniteMesure}',
              couleurValeur: _couleurStock(article.quantite),
            ),
            _ligneInfo(
              'Conditionnements',
              '${article.nombreConditionnements}',
            ),
            _ligneInfo(
              'Créé le',
              formatDateHeure(article.createdAt),
            ),
            _ligneInfo(
              'Modifié le',
              formatDateHeure(article.updatedAt),
            ),
          ],
        ),
      ),
    );
  }

  /// Carte « stock en unités de base » : total + équivalents en
  /// conditionnements (formule du cahier des charges).
  Widget _carteStock(Article article) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock total : ${_formatQuantite(article.quantite)} '
              '${Conditionnement.pluriel(article.uniteMesure, article.quantite)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if (article.conditionnements.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...article.conditionnements.map((Conditionnement c) {
                final int exemplaires = c.exemplairesContenusDans(article.quantite);
                final double reste =
                    article.quantite - exemplaires * c.quantiteUnitesBase;

                final StringBuffer texte = StringBuffer(
                  exemplaires > 0
                      ? 'soit $exemplaires × ${c.libelle}'
                      : 'moins de 1 × ${c.libelle}',
                );
                if (exemplaires > 0 && reste > 0) {
                  texte.write(
                      ' (reste ${_formatQuantite(reste)} ${article.uniteMesure})');
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• $texte',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _carteConditionnement(Article article, Conditionnement c) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: _peutVoirQr
                  ? 'Aperçu / télécharger / imprimer'
                  : c.codeBarreTexte == null
                      ? ''
                      : 'Code-barre : ${c.codeBarreTexte}',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _peutVoirQr
                    ? () => _ouvrirApercuQr(
                        _etiquetteConditionnement(article, c))
                    : null,
                child: QrImageView(
                  data: c.qrCodeId,
                  version: QrVersions.auto,
                  size: 96,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.libelle,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '= ${_formatQuantite(c.quantiteUnitesBase)} '
                    '${Conditionnement.pluriel(article.uniteMesure, c.quantiteUnitesBase)} '
                    'pour ${prixArticle(c.prixVente, article.devise)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if ((c.codeBarreTexte ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Code-barre : ${c.codeBarreTexte}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      PermissionGate(
                        page: PageAccess.articles,
                        action: ActionAccess.modifier,
                        child: TextButton.icon(
                          onPressed: () => _modifierConditionnement(c),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Modifier'),
                        ),
                      ),
                      PermissionGate(
                        page: PageAccess.articles,
                        action: ActionAccess.supprimer,
                        child: TextButton.icon(
                          onPressed: () => _supprimerConditionnement(c),
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: Colors.red.shade700),
                          label: Text('Supprimer',
                              style: TextStyle(color: Colors.red.shade700)),
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
    );
  }

  Widget _sectionMouvements() {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historique des mouvements',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Entrées (approvisionnements) et sorties (ventes, ajustements).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_mouvements.isEmpty)
              Text(
                'Aucun mouvement enregistré pour cet article.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey.shade600),
              )
            else
              ..._mouvements.map((MouvementArticle mouvement) {
                final bool entree = mouvement.estEntree;
                final Color couleur =
                    entree ? Colors.green.shade700 : Colors.red.shade700;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    entree
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: couleur,
                  ),
                  title: Text(
                    mouvement.source.libelle +
                        ((mouvement.motif ?? '').isNotEmpty
                            ? ' · ${mouvement.motif}'
                            : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(formatDateHeure(mouvement.date)),
                  trailing: Text(
                    '${entree ? '+' : ''}${_formatQuantite(mouvement.quantite)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: couleur),
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
          "Détail de l'article",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          if (article != null)
            PermissionGate(
              page: PageAccess.qrCodes,
              action: ActionAccess.voir,
              child: IconButton(
                onPressed: () => _ouvrirApercuQr(_etiquetteArticle(article)),
                icon: const Icon(Icons.qr_code_2_rounded),
                tooltip: 'QR code de l\'article',
              ),
            ),
          if (article != null)
            PermissionGate(
              page: PageAccess.articles,
              action: ActionAccess.modifier,
              child: IconButton(
                onPressed: _modifier,
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Modifier',
              ),
            ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null || article == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 56, color: Colors.red.shade400),
                        const SizedBox(height: 12),
                        Text(
                          _erreur ?? 'Article introuvable.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Retour'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _charger,
                  color: Theme.of(context).colorScheme.primary,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _enTete(article),
                      const SizedBox(height: 12),
                      _carteStock(article),
                      const SizedBox(height: 12),
                      _carteInformations(article),
                      const SizedBox(height: 20),

                      // --------------------------------- conditionnements
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Conditionnements',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          PermissionGate(
                            page: PageAccess.qrCodes,
                            action: ActionAccess.voir,
                            child: TextButton.icon(
                              onPressed: _impressionEtiquettes
                                  ? null
                                  : _imprimerEtiquettes,
                              icon: _impressionEtiquettes
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.print_outlined, size: 18),
                              label: const Text('Étiquettes'),
                            ),
                          ),
                          PermissionGate(
                            page: PageAccess.articles,
                            action: ActionAccess.creer,
                            child: TextButton.icon(
                              onPressed: _ajouterConditionnement,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Ajouter'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (article.conditionnements.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Aucun conditionnement. Ajoutez par exemple '
                            '« Farde de 12 » ou « Carton de 24 ».',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.grey.shade600),
                          ),
                        )
                      else
                        ...article.conditionnements
                            .map((Conditionnement c) => _carteConditionnement(article, c)),
                      const SizedBox(height: 20),

                      // -------------------------------------- mouvements
                      _sectionMouvements(),
                      const SizedBox(height: 24),

                      // --------------------------------------- suppression
                      PermissionGate(
                        page: PageAccess.articles,
                        action: ActionAccess.supprimer,
                        child: OutlinedButton.icon(
                          onPressed: _supprimerArticle,
                          icon: Icon(Icons.delete_forever_outlined,
                              color: Colors.red.shade700),
                          label: Text(
                            "Supprimer l'article",
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
    );
  }
}
