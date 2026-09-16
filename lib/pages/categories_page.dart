// lib/pages/categories_page.dart
//
// MODULE 5 — ÉCRAN « GESTION DES CATÉGORIES »
//
//   • liste depuis le référentiel global `public.categories` ;
//   • créer / renommer / supprimer une catégorie ;
//   • comptage des articles de la boutique qui utilisent chaque catégorie.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/categorie.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final ArticleService _service = ArticleService.instance;

  List<Categorie> _categories = const <Categorie>[];
  Map<String, int> _compteurs = const <String, int>{};
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
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

    List<Categorie> categories = const <Categorie>[];
    Map<String, int> compteurs = <String, int>{};
    String? messageErreur;

    try {
      final List<dynamic> resultats = await Future.wait<dynamic>(<Future<dynamic>>[
        _service.getCategories(),
        _service.getArticles(),
      ]);

      categories = resultats[0] as List<Categorie>;

      // Nombre d'articles de la boutique par catégorie (clé normalisée).
      for (final Article article in resultats[1] as List<Article>) {
        final String cle = Categorie.normaliser(article.categorie);
        if (cle.isEmpty) continue;
        compteurs[cle] = (compteurs[cle] ?? 0) + 1;
      }
    } on ArticleServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('CategoriesPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des catégories.';
    }

    if (!mounted) return;

    setState(() {
      if (messageErreur != null) {
        _erreur = messageErreur;
      } else {
        _categories = categories;
        _compteurs = compteurs;
        _erreur = null;
      }
      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  /// Boîte de dialogue commune création / renommage.
  ///
  /// Renvoie le nom saisi, ou `null` si l'utilisateur annule.
  Future<String?> _demanderNom({String? valeurInitiale}) async {
    final TextEditingController controller =
        TextEditingController(text: valeurInitiale);

    try {
      return await showDialog<String>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(valeurInitiale == null
              ? 'Nouvelle catégorie'
              : 'Renommer la catégorie'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Nom de la catégorie'),
              onSubmitted: (String valeur) => Navigator.pop(ctx, valeur.trim()),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(valeurInitiale == null ? 'Créer' : 'Renommer'),
            ),
          ],
        ),
      );
    } finally {
      // Laisse un frame au framework pour terminer la fermeture du dialogue
      // avant de libérer le contrôleur.
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
  }

  Future<void> _creerCategorie() async {
    final String? nom = await _demanderNom();
    if (!mounted || nom == null || nom.isEmpty) return;

    try {
      final Categorie creee = await _service.creerCategorie(nom);
      _afficherMessage('Catégorie « ${creee.nom} » créée.');
      await _charger(silencieux: true);
    } on ArticleServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    }
  }

  Future<void> _renommerCategorie(Categorie categorie) async {
    final String? nom = await _demanderNom(valeurInitiale: categorie.nom);
    if (!mounted || nom == null || nom.isEmpty || nom == categorie.nom) return;

    try {
      await _service.renommerCategorie(categorie: categorie, nouveauNom: nom);
      _afficherMessage('Catégorie renommée « $nom ».');
      await _charger(silencieux: true);
    } on ArticleServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    }
  }

  Future<void> _supprimerCategorie(Categorie categorie) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Supprimer cette catégorie ?'),
        content: Text(
          '« ${categorie.nom} » disparaîtra du référentiel. '
          'Les articles qui l\'utilisaient gardent leur texte : '
          'réaffectez-les si nécessaire.',
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
      await _service.supprimerCategorie(categorie.id);
      _afficherMessage('Catégorie supprimée.');
      await _charger(silencieux: true);
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

  Widget _carteCategorie(Categorie categorie) {
    final int nombre = _compteurs[Categorie.normaliser(categorie.nom)] ?? 0;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(Icons.category_outlined,
              color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(
          categorie.nom,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(nombre <= 1 ? '$nombre article' : '$nombre articles'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PermissionGate(
              page: PageAccess.articles,
              action: ActionAccess.modifier,
              child: IconButton(
                onPressed: () => _renommerCategorie(categorie),
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Renommer',
              ),
            ),
            PermissionGate(
              page: PageAccess.articles,
              action: ActionAccess.supprimer,
              child: IconButton(
                onPressed: () => _supprimerCategorie(categorie),
                icon: Icon(Icons.delete_outline,
                    size: 20, color: Colors.red.shade700),
                tooltip: 'Supprimer',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Catégories',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 56, color: Colors.red.shade400),
                        const SizedBox(height: 12),
                        Text(_erreur!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => _charger(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _charger(silencieux: true),
                  color: Theme.of(context).colorScheme.primary,
                  child: _categories.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.category_outlined,
                                          size: 72, color: Colors.grey),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Aucune catégorie pour le moment.\n'
                                        'Créez-en une pour classer vos articles.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                          children:
                              _categories.map(_carteCategorie).toList(),
                        ),
                ),
      floatingActionButton: PermissionGateBouton(
        page: PageAccess.articles,
        action: ActionAccess.creer,
        builder: (BuildContext context) => FloatingActionButton.extended(
          onPressed: _creerCategorie,
          icon: const Icon(Icons.add),
          label: const Text('Nouvelle catégorie'),
        ),
      ),
    );
  }
}
