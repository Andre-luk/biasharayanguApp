// lib/pages/manage_categories_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';

class ManageCategoriesPage extends StatefulWidget {
  const ManageCategoriesPage({super.key});

  @override
  State<ManageCategoriesPage> createState() => _ManageCategoriesPageState();
}

class _ManageCategoriesPageState extends State<ManageCategoriesPage> {
  late Future<List<String>> _categoriesFuture;

  // 🔑 CORRECTION 1: Utiliser uniquement String? pour l'ID propriétaire (UUID)
  String? _currentOwnerId;
  // ❌ Suppression de _currentOwnerIdInt

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    // 🔑 CORRECTION 2: Assigner l'ID String?
    final String? uid = await SessionManager.getUserId();
    // 🧩 MODULE 15 — les catégories sont celles de la boutique affichée.
    _currentOwnerId = uid == null
        ? null
        : await DBHelper.instance.ownerDonneesDe(uid) ?? uid;

    if (!mounted) return;

    // Si l'ID propriétaire est null, nous ne devons pas appeler DBHelper
    if (_currentOwnerId == null) {
      // Optionnel: Rediriger ou montrer une erreur si l'ID est invalide
      setState(() {
        _categoriesFuture = Future.value([]); // Afficher une liste vide
      });
      return;
    }

    setState(() {
      // 🚨 CORRECTION 3 (LIGNE 54 - ancienne): Utiliser la version String de l'ID pour DBHelper
      _categoriesFuture = DBHelper.instance.getDistinctCategories(ownerId: _currentOwnerId);
    });
  }

  void _refreshCategories() {
    if (!mounted) return;
    // 🚨 CORRECTION 4 (LIGNE 63 - ancienne): Utiliser la version String de l'ID
    if (_currentOwnerId == null) return;
    setState(() {
      _categoriesFuture = DBHelper.instance.getDistinctCategories(ownerId: _currentOwnerId);
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Theme.of(context).colorScheme.primary,
      ),
    );
  }

  // Ajout / édition (version robuste contre 'controller disposed')
  Future<void> _addOrEditCategory(AppLocalizations T, {String? currentCategory}) async {
    // Protection : ne pas créer le controller si le State est déjà démonté
    if (!mounted) return;

    final controller = TextEditingController(text: currentCategory);
    final isEditing = currentCategory != null;

    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        useRootNavigator: false, // attacher le dialog au navigator local (important dans un Shell)
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(isEditing ? 'Modifier la catégorie' : 'Ajouter une nouvelle catégorie'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: 'Nom de la catégorie'),
                autofocus: true,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(T.cancelButton),
              ),
              TextButton(
                onPressed: () {
                  final newName = controller.text.trim();
                  if (newName.isNotEmpty) {
                    Navigator.of(dialogContext).pop(newName);
                  }
                },
                child: Text(T.saveButton),
              ),
            ],
          );
        },
      );
    } catch (e, st) {
      debugPrint('Erreur showDialog _addOrEditCategory: $e\n$st');
      result = null;
    } finally {
      // NE PAS disposer immédiatement : laisser un frame au framework pour terminer la désactivation
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          controller.dispose();
        } catch (e) {
          debugPrint('Erreur lors du dispose du controller: $e');
        }
      });
    }

    if (result == null) return;
    if (!mounted) return;

    try {
      // 🚨 CORRECTION 5 (LIGNE 145 - ancienne): Vérifier et utiliser l'ID String
      if (_currentOwnerId == null) {
        _showSnackBar('Erreur: Utilisateur non identifié ou ID invalide.', isError: true);
        return;
      }

      if (isEditing) {
        // LIGNE 148 (ancienne): Correction de type String
        await DBHelper.instance.updateCategory(currentCategory!, result, _currentOwnerId!);
        _showSnackBar('Catégorie "$currentCategory" mise à jour en "$result"!');
      } else {
        // LIGNE 148 (ancienne): Correction de type String
        await DBHelper.instance.insertCategoryIfNotExists(result, ownerId: _currentOwnerId);
        _showSnackBar('Catégorie "$result" enregistrée pour utilisation immédiate.');
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshCategories();
      });
    } catch (e, st) {
      debugPrint('Erreur ajout/édition catégorie: $e\n$st');
      if (mounted) _showSnackBar('Erreur: ${e.toString()}', isError: true);
    }
  }

  // Suppression (robuste)
  Future<void> _deleteCategory(AppLocalizations T, String category) async {
    final defaultCategory = T.categoryOther;

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmation de suppression'),
        content: Text('Êtes-vous sûr de vouloir supprimer la catégorie "$category" ? Tous les produits de cette catégorie seront transférés à la catégorie "$defaultCategory".'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(T.cancelButton)),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    try {
      // 🚨 CORRECTION 6: Vérifier et utiliser l'ID String
      if (_currentOwnerId == null) {
        _showSnackBar('Erreur: Utilisateur non identifié ou ID invalide.', isError: true);
        return;
      }

      // LIGNE 191: Correction de type String
      await DBHelper.instance.deleteCategory(category, defaultCategory, _currentOwnerId!);
      _showSnackBar('Catégorie "$category" supprimée. Les produits ont été mis à jour.');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshCategories();
      });
    } catch (e, st) {
      debugPrint('Erreur suppression catégorie: $e\n$st');
      if (mounted) _showSnackBar('Erreur: ${e.toString()}', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;

    // 🚨 CORRECTION 7: Tester _currentOwnerId pour la condition de chargement
    // L'ancienne ligne 225 utilisait _currentOwnerIdInt
    if (_currentOwnerId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gestion des Catégories')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Catégories'),
        elevation: 0,
      ),
      body: FutureBuilder<List<String>>(
        future: _categoriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur: ${snapshot.error}'));
          }

          final categories = snapshot.data ?? [];
          final categoriesToManage = categories.where((c) => c != T.categoryOther).toList();

          if (categoriesToManage.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.category_outlined, size: 60, color: Colors.grey),
                    const SizedBox(height: 10),
                    const Text('Aucune catégorie trouvée.', style: TextStyle(fontSize: 18, color: Colors.grey)),
                    const SizedBox(height: 8),
                    const Text("Ajoutez la première catégorie via le bouton +.", textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: categoriesToManage.length,
            itemBuilder: (context, index) {
              final category = categoriesToManage[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.category),
                  title: Text(category),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _addOrEditCategory(T, currentCategory: category),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteCategory(T, category),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditCategory(T),
        label: const Text('Ajouter Catégorie'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}