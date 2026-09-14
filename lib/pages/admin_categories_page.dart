// lib/pages/admin_categories_page.dart
import 'package:flutter/material.dart';
import 'package:biashara_yangu/db_helper.dart'; // Importez votre DBHelper
import 'package:biashara_yangu/models/category.dart'; // Importez le modèle Category

class AdminCategoriesPage extends StatefulWidget {
  const AdminCategoriesPage({super.key});

  @override
  State<AdminCategoriesPage> createState() => _AdminCategoriesPageState();
}

class _AdminCategoriesPageState extends State<AdminCategoriesPage> {
  // Liste qui stocke les objets Category récupérés de la base de données
  List<Category> _categories = [];
  bool _isLoading = true;

  final TextEditingController _categoryController = TextEditingController();
  final DBHelper _dbHelper = DBHelper.instance; // Instance de DBHelper

  @override
  void initState() {
    super.initState();
    _loadCategories(); // Charger les données au démarrage
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  // ====================================================================
  // LOGIQUE DE CHARGEMENT ET CRUD BASÉE SUR DBHelper
  // ====================================================================

  /// Charge toutes les catégories depuis la base de données.
  Future<void> _loadCategories() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Utilise la méthode générale de lecture des catégories
      final categories = await _dbHelper.getCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Erreur de chargement des catégories: ${e.toString()}', isError: true);
        setState(() {
          _isLoading = false;
          _categories = [];
        });
      }
    }
  }

  /// Sauvegarde (ajoute ou modifie) une catégorie.
  Future<void> _saveCategory({int? id, required String nom}) async {
    final category = Category(id: id, nom: nom);
    try {
      if (id == null) {
        // CREATE
        await _dbHelper.insertCategory(category);
        _showSnackBar('Catégorie "$nom" ajoutée avec succès.');
      } else {
        // UPDATE
        // 🔑 CORRECTION: Utilisation d'une méthode hypothétique 'updateCategoryTable'
        // qui prend l'objet Category, à ajouter/confirmer dans DBHelper.
        // Si votre DBHelper est configuré pour accepter l'objet Category pour la MAJ :
        // await _dbHelper.updateCategory(category);
        // Si elle est nommée différemment:
        await _dbHelper.updateCategoryTable(category); // À vérifier dans DBHelper
        _showSnackBar('Catégorie mise à jour avec succès.');
      }
      _loadCategories(); // Recharger la liste après modification/ajout
    } catch (e) {
      String msg = 'Erreur lors de l\'enregistrement.';
      if (e.toString().contains('constraint failed')) {
        msg = 'Erreur: Une catégorie avec ce nom existe déjà.';
      }
      _showSnackBar(msg, isError: true);
    }
  }

  /// Supprime une catégorie par son ID.
  Future<void> _deleteCategory(int id, String nom) async {
    try {
      // 🔑 CORRECTION: Utilisation d'une méthode hypothétique 'deleteCategoryTable'
      // qui prend l'ID, à ajouter/confirmer dans DBHelper.
      // Si votre DBHelper est configuré pour accepter l'int pour la suppression :
      // await _dbHelper.deleteCategory(id);
      // Si elle est nommée différemment:
      await _dbHelper.deleteCategoryTable(id); // À vérifier dans DBHelper
      _showSnackBar('Catégorie "$nom" supprimée.', isError: true);
      _loadCategories(); // Recharger la liste après suppression
    } catch (e) {
      String msg = 'Erreur lors de la suppression.';
      _showSnackBar(msg, isError: true);
    }
  }

  // ====================================================================
  // WIDGETS D'INTERACTION (Dialogues)
  // ====================================================================

  /// Affiche la boîte de dialogue pour ajouter ou modifier.
  void _showCategoryDialog({Category? category}) {
    final bool isEditing = category != null;
    _categoryController.text = category?.nom ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Modifier la Catégorie' : 'Ajouter une Catégorie'),
          content: TextField(
            controller: _categoryController,
            autofocus: true,
            decoration: const InputDecoration(hintText: "Nom de la catégorie"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                final newName = _categoryController.text.trim();
                if (newName.isNotEmpty) {
                  Navigator.of(context).pop();
                  _saveCategory(
                    id: category?.id,
                    nom: newName,
                  );
                }
              },
              child: Text(isEditing ? 'Modifier' : 'Ajouter'),
            ),
          ],
        );
      },
    );
  }

  /// Affiche la boîte de dialogue de confirmation de suppression.
  void _showDeleteConfirmation(Category category) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmation de Suppression'),
          content: Text('Êtes-vous sûr de vouloir supprimer la catégorie "${category.nom}" ? Cette action est irréversible.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (category.id != null) {
                  _deleteCategory(category.id!, category.nom);
                }
              },
              child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  /// Affiche une barre d'information ou d'erreur.
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ====================================================================
  // WIDGET PRINCIPAL
  // ====================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Catégories', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCategories,
            tooltip: 'Actualiser la liste',
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _showCategoryDialog(),
            tooltip: 'Ajouter une nouvelle catégorie',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _categories.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category_outlined, size: 80, color: Colors.blueGrey),
            SizedBox(height: 16),
            Text('Aucune catégorie définie.', style: TextStyle(fontSize: 16, color: Colors.black54)),
            Text('Utilisez le bouton "+" pour ajouter la première catégorie.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black45)),
          ],
        ),
      )
          : ListView.builder(
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.category, color: Colors.blueGrey),
              title: Text(category.nom),
              subtitle: Text('ID: ${category.id}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _showCategoryDialog(category: category),
                    tooltip: 'Modifier',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _showDeleteConfirmation(category),
                    tooltip: 'Supprimer',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}