// lib/pages/add_product_page.dart
import 'package:biashara_yangu/utils/image_locale.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// --- Imports Locaux ---
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/produit.dart';
import 'package:biashara_yangu/models/approvisionnement.dart';
import 'package:biashara_yangu/services/image_service.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
// 🪙 MODULE 18 — devise de travail (suffixes des champs de prix).
import 'package:biashara_yangu/services/devise_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/services/sync_service.dart';

// 🔑 NOTE: Ce fichier utilise toujours DBHelper (SQLite).

class AddProductPage extends StatefulWidget {
  final Produit? produitToEdit;

  const AddProductPage({super.key, this.produitToEdit});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  // --- Clés de Formulaire ---
  final _formKey = GlobalKey<FormState>();
  final _stockFormKey = GlobalKey<FormState>();

  // --- Contrôleurs de Texte ---
  final _nomController = TextEditingController();
  final _prixAchatController = TextEditingController();
  final _prixVenteController = TextEditingController();
  final _quantiteController = TextEditingController();
  final _quantiteAjoutController = TextEditingController();
  final _prixAchatNewController = TextEditingController();

  // --- Données d'État ---
  List<Approvisionnement> _historique = [];
  bool _isLoadingHistory = false;
  bool _isEditMode = false;
  bool _saving = false;
  bool _picking = false;
  bool _isInitializing = true;

  // --- Données Produit ---
  int? _produitId;
  String? _currentOwnerId;
  String? _photoPath;

  // --- Catégories et Unités ---
  String? _selectedCategory; // peut être null = aucune catégorie
  String? _selectedUnit;
  Future<List<String>> _categoriesFuture = Future.value([]);
  List<String> _categories = []; // Liste remplie par le FutureBuilder
  List<String> _unitOptions = [];

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.produitToEdit != null;
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      // 1. Charger l'ID de l'utilisateur
      _currentOwnerId = await SessionManager.getUserId();

      // 2. Initialiser les contrôleurs en mode édition
      if (widget.produitToEdit != null) {
        final p = widget.produitToEdit!;
        _produitId = p.id;

        _nomController.text = p.nom;
        _prixAchatController.text = p.prixAchat?.toString() ?? '';
        _prixVenteController.text = p.prixVente.toString();
        _quantiteController.text = p.quantite.toString();

        _selectedCategory = (p.categorie != null && p.categorie!.isNotEmpty) ? p.categorie : null;
        _selectedUnit = (p.uniteMesure != null && p.uniteMesure!.isNotEmpty) ? p.uniteMesure : null;
        _photoPath = p.photo;

        _prixAchatNewController.text = (p.prixAchat ?? 0.0).toString();

        // 3. Charger l'historique
        _loadHistorique();
      }

      // 4. Définir le Future pour le chargement des catégories
      _categoriesFuture = _loadCategories(_currentOwnerId);
    } catch (e) {
      debugPrint('Erreur initialisation AddProductPage: $e');
      _categoriesFuture = Future.value([]);
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<List<String>> _loadCategories(String? ownerId) async {
    try {
      if (ownerId == null) return [];
      // 🔑 OPTIMISATION: Le chargement des catégories est fait une seule fois ici.
      final List<String> cats = await DBHelper.instance.getDistinctCategories(ownerId: ownerId);
      return cats;
    } catch (e) {
      debugPrint('Erreur de chargement des catégories: ${e.toString()}');
      return [];
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final T = AppLocalizations.of(context)!;

    // Calcul des options d'unité (dépend de la locale T)
    final rawUnitSet = <String>{
      T.unitUnity, T.unitKg, T.unitDozen, T.unitLiter, T.unitMeter
    };

    // Mettre à jour la liste des options d'unité
    _unitOptions = rawUnitSet.toList();

    // S'assurer que _selectedUnit est une option valide
    if (_selectedUnit == null || !_unitOptions.contains(_selectedUnit)) {
      _selectedUnit = _unitOptions.isNotEmpty ? _unitOptions.first : null;
    }
  }

  @override
  void dispose() {
    _nomController.dispose();
    _prixAchatController.dispose();
    _prixVenteController.dispose();
    _quantiteController.dispose();
    _quantiteAjoutController.dispose();
    _prixAchatNewController.dispose();
    super.dispose();
  }

  Future<void> _loadHistorique() async {
    if (!_isEditMode || widget.produitToEdit?.id == null) return;

    if (mounted) {
      setState(() {
        _isLoadingHistory = true;
      });
    }

    try {
      final historique = await DBHelper.instance.getHistoriqueApprovisionnement(widget.produitToEdit!.id!);
      if (mounted) {
        setState(() {
          _historique = historique;
        });
      }
    } catch (e) {
      _showSnackBar(AppLocalizations.of(context)!.loadingHistoryError(e.toString()), isError: true);
    } finally {
      if (mounted) setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  // MÉTHODE POUR AJOUTER DU STOCK ET ENREGISTRER LE LOG
  Future<void> _addStock() async {
    final T = AppLocalizations.of(context)!;

    if (!_stockFormKey.currentState!.validate()) return;
    if (widget.produitToEdit == null || widget.produitToEdit!.id == null) return;

    // 🔑 OPTIMISATION: Parsing des valeurs une seule fois au début
    final quantiteAjout = double.tryParse(_quantiteAjoutController.text.trim().replaceAll(',', '.')) ?? 0.0;
    final nouveauPrixAchat = double.tryParse(_prixAchatNewController.text.trim().replaceAll(',', '.')) ?? 0.0;

    if (quantiteAjout <= 0 || nouveauPrixAchat <= 0) {
      _showSnackBar(T.msgInvalidStockInput, isError: true);
      return;
    }

    if (_saving) return;

    setState(() => _saving = true);

    try {
      final oldProduct = widget.produitToEdit!;

      await DBHelper.instance.addStockAndLog(
        oldProduct,
        quantiteAjout,
        nouveauPrixAchat,
      );

      // Mise à jour de l'état local du produit et des contrôleurs
      if (mounted) {
        final updatedProduct = await DBHelper.instance.getProduitById(oldProduct.id!);

        if (updatedProduct != null) {
          setState(() {
            // Mise à jour de l'objet local
            widget.produitToEdit!.quantite = updatedProduct.quantite;
            widget.produitToEdit!.prixAchat = updatedProduct.prixAchat;

            _quantiteController.text = updatedProduct.quantite.toString();
            _prixAchatController.text = (updatedProduct.prixAchat ?? 0.0).toString();

            _quantiteAjoutController.clear();
            _prixAchatNewController.text = (updatedProduct.prixAchat ?? 0.0).toString();

            _loadHistorique();
          });
        }

        _showSnackBar(T.msgStockAddedSuccess);

        // 🔑 OPTIMISATION: Lancement de la synchronisation en tâche de fond (non bloquant)
        SyncService.instance.syncAll().then((_) {
          debugPrint('SyncService: syncAll() complété après ajout de stock.');
        }).catchError((e) {
          debugPrint('SyncService: erreur lors du sync après ajout de stock: $e');
        });
      }
    } catch (e) {
      if (mounted) _showSnackBar('${T.msgStockAddFailure} : ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _refreshCategories() {
    if (mounted) {
      // Redéfinir le Future force le FutureBuilder à se relancer
      setState(() {
        _categoriesFuture = _loadCategories(_currentOwnerId);
      });
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _onPickFromGallery() async {
    setState(() => _picking = true);
    try {
      final path = await ImageService.pickFromGallery();
      if (path != null && mounted) setState(() => _photoPath = path);
    } catch (e) {
      if (mounted) _showSnackBar(AppLocalizations.of(context)!.errorGallery(e.toString()), isError: true);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _onPickFromCamera() async {
    setState(() => _picking = true);
    try {
      final path = await ImageService.pickFromCamera();
      if (path != null && mounted) setState(() => _photoPath = path);
    } catch (e) {
      if (mounted) _showSnackBar(AppLocalizations.of(context)!.errorCamera(e.toString()), isError: true);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _saveProduct() async {
    final T = AppLocalizations.of(context)!;

    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    // 🔑 OPTIMISATION: Parsing des valeurs une seule fois
    final prixAchatRaw = _prixAchatController.text.trim();
    final prixAchat = prixAchatRaw.isEmpty
        ? 0.0
        : (double.tryParse(prixAchatRaw.replaceAll(',', '.')) ?? 0.0);

    final prixVente = double.tryParse(_prixVenteController.text.trim().replaceAll(',', '.')) ?? 0.0;
    final quantite = double.tryParse(_quantiteController.text.trim().replaceAll(',', '.')) ?? 0.0;

    // Validation des prix : prix de vente doit être > 0
    if (prixVente <= 0) {
      _showSnackBar(T.priceValidation, isError: true);
      return;
    }

    // Si prixAchat fourni (>0), s'assurer que prixVente > prixAchat
    if (prixAchat > 0 && prixVente <= prixAchat) {
      _showSnackBar(T.priceMarkupValidation, isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final ownerId = _currentOwnerId;

      if (ownerId == null) {
        if (mounted) {
          _showSnackBar(T.errorUserNotLoggedIn, isError: true);
          setState(() => _saving = false);
        }
        return;
      }

      final produit = Produit(
        id: _produitId,
        supabaseId: widget.produitToEdit?.supabaseId,
        isSynced: widget.produitToEdit?.isSynced,
        nom: _nomController.text.trim(),
        // Catégorie facultative : on sauvegarde null ou chaîne vide selon ton modèle DB (ici on sauvegarde empty string si null)
        categorie: _selectedCategory ?? '',
        // Prix d'achat facultatif (on enregistre 0.0 si absent)
        prixAchat: prixAchat > 0 ? prixAchat : 0.0,
        prixVente: prixVente,
        quantite: quantite,
        uniteMesure: _selectedUnit ?? T.unitUnity,
        photo: _photoPath,
        createdAt: widget.produitToEdit?.createdAt ?? DateTime.now().toIso8601String(),
        ownerId: ownerId,
      );

      final int localId = await DBHelper.instance.saveProduit(produit);

      if (_produitId == null) {
        _produitId = localId;
        if (mounted) _showSnackBar(T.productAdded);
      } else {
        if (mounted) _showSnackBar(T.productUpdated);
      }

      // 🔑 OPTIMISATION: Lancement de la synchronisation en tâche de fond (non bloquant)
      SyncService.instance.syncAll().then((_) {
        debugPrint('SyncService: syncAll() complété après sauvegarde produit (local ID: $localId).');
      }).catchError((e) {
        debugPrint('SyncService: erreur lors du sync après sauvegarde produit: $e');
      });

      if (!mounted) return;

      // Retourne 'true' pour indiquer à la page précédente de rafraîchir
      context.pop(true);
    } catch (e) {
      if (mounted) _showSnackBar('${T.saveError} : ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showPickOptions(AppLocalizations T) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(T.photoOptionTitle, style: Theme.of(context).textTheme.titleLarge),
              const Divider(height: 20),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(T.photoOptionGallery),
                onTap: () {
                  context.pop();
                  _onPickFromGallery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(T.photoOptionCamera),
                onTap: () {
                  context.pop();
                  _onPickFromCamera();
                },
              ),
              if (_photoPath != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: Text(T.photoOptionDelete, style: const TextStyle(color: Colors.red)),
                  onTap: () {
                    context.pop();
                    setState(() => _photoPath = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoSelector(AppLocalizations T) {
    if (_picking) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).cardColor,
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      height: 180,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(color: Colors.grey.shade300)
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_photoPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: imageFichierLocal(_photoPath!, fit: BoxFit.cover),
            ),

          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showPickOptions(T),
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_photoPath != null ? Colors.black54 : Theme.of(context).colorScheme.primary.withOpacity(0.8)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _photoPath != null ? Icons.change_circle : Icons.camera_alt,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _photoPath != null ? T.changePhoto : T.addPhoto,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // WIDGET: Panneau pour l'ajout de stock en mode édition
  Widget _buildStockAdditionPanel(AppLocalizations T) {
    return Form(
      key: _stockFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 40),
          Text(T.headerAddStock, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _quantiteAjoutController,
                  decoration: InputDecoration(
                    labelText: T.labelQuantityToAdd,
                    suffixText: widget.produitToEdit?.uniteMesure ?? T.unitUnity,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final number = double.tryParse(value?.trim().replaceAll(',', '.') ?? '');
                    if (number == null || number <= 0) return T.validationInvalidNumber;
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _prixAchatNewController,
                  decoration: InputDecoration(
                    labelText: T.labelNewPurchasePrice,
                    suffixText: DeviseService.instance.symbole,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final number = double.tryParse(value?.trim().replaceAll(',', '.') ?? '');
                    if (number == null || number <= 0) return T.validationInvalidNumber;
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _addStock,
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add_shopping_cart),
              label: Text(T.buttonAddToStock),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // WIDGET: Panneau pour afficher l'historique d'approvisionnement
  Widget _buildHistoryPanel(AppLocalizations T) {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 40),
        Text(T.headerStockHistory, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),

        if (_historique.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(T.msgNoHistoryFound, style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey.shade600)),
          ),

        ..._historique.map((appro) {
          final date = DateTime.tryParse(appro.dateApprovisionnement);
          final formattedDate = date != null
              ? DateFormat('dd/MM/yy HH:mm').format(date.toLocal())
              : T.labelUnknownDate;

          return Card(
            elevation: 1,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              leading: const Icon(Icons.receipt_long, color: Colors.blueGrey),
              title: Text(
                '${T.labelAdded} ${appro.quantiteAjoutee.toStringAsFixed(2)} ${widget.produitToEdit?.uniteMesure ?? T.unitUnity}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${T.labelPurchasePrice}: ${formatMontant(appro.prixAchatUnitaire)}',
              ),
              trailing: Text(formattedDate, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
          );
        }).toList(),
      ],
    );
  }

  // NOUVELLE MÉTHODE : Pour gérer la logique des catégories après chargement
  void _processCategories(List<String> loadedCats, AppLocalizations T) {
    // Ne pas forcer une valeur — on autorise 'aucune catégorie' représentée par null
    final uniqueCats = <String>{...loadedCats};

    final sortedOtherCats = uniqueCats.toList()..sort();
    _categories = sortedOtherCats;

    // Si la catégorie sélectionnée n'est plus présente, on la laisse (peut être valeur libre) ou null
    if (_selectedCategory != null && !_categories.contains(_selectedCategory)) {
      // laissez-la, ou mettez-la à null pour forcer "aucune"
      // ici on la conserve si elle est non vide, sinon null
      if (_selectedCategory!.isEmpty) {
        _selectedCategory = null;
      }
    }

    // si aucune sélection, garder null (aucune catégorie)
    if (_selectedCategory == null && _categories.isNotEmpty) {
      // Ne pas forcer, on laisse vide pour l'utilisateur choisir
    }
  }

  // NOUVEAU WIDGET: Isoler la construction du formulaire pour la clarté
  Widget _buildProductForm(AppLocalizations T, String title) {
    // 🔑 OPTIMISATION: Assurer la validité de _selectedUnit ici
    final uniqueUnitOptions = _unitOptions.toSet().toList();
    if (_selectedUnit == null || !uniqueUnitOptions.contains(_selectedUnit)) {
      _selectedUnit = uniqueUnitOptions.isNotEmpty ? uniqueUnitOptions.first : null;
    }

    // Build category items but allow null (aucune catégorie)
    final List<DropdownMenuItem<String?>> categoryItems = [
      DropdownMenuItem<String?>(value: null, child: Text(T.categoryNone ?? 'Aucune')),
      ..._categories.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.category_sharp),
            tooltip: T.manageCategories,
            onPressed: () async {
              final bool? changed = await context.push('/settings/manage-categories');
              if (changed == true) {
                _refreshCategories();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Sélecteur de Photo
              _buildPhotoSelector(T),
              const SizedBox(height: 20),

              // 2. Nom du Produit
              TextFormField(
                controller: _nomController,
                decoration: InputDecoration(
                  labelText: T.productNameLabel,
                  prefixIcon: const Icon(Icons.label_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? T.nameRequired : null,
              ),
              const SizedBox(height: 16),

              // 3. Catégorie (Dropdown de la BD) — facultatif
              DropdownButtonFormField<String?>(
                value: _selectedCategory,
                decoration: InputDecoration(
                  labelText: T.productCategoryLabel,
                  prefixIcon: const Icon(Icons.category_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: categoryItems,
                onChanged: (String? newValue) {
                  setState(() { _selectedCategory = newValue; });
                },
                // plus de validation obligatoire — champ facultatif
                validator: (_) => null,
              ),
              const SizedBox(height: 16),

              // 4. Prix d'Achat & Prix de Vente
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _prixAchatController,
                      decoration: InputDecoration(
                        labelText: T.productPriceCost + ' (${T.optionalLabel})',
                        prefixIcon: const Icon(Icons.money_off),
                        suffixText: DeviseService.instance.symbole,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      // prix d'achat facultatif -> validator autorise vide ou nombre >= 0
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final val = double.tryParse(v.trim().replaceAll(',', '.'));
                        if (val == null || val < 0) return T.validationInvalidNumber;
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _prixVenteController,
                      decoration: InputDecoration(
                        labelText: T.productPriceSell,
                        prefixIcon: const Icon(Icons.attach_money),
                        suffixText: DeviseService.instance.symbole,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return T.priceRequired;
                        final val = double.tryParse(v.trim().replaceAll(',', '.'));
                        if (val == null || val <= 0) return T.priceRequired;
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 5. Quantité et Unité de Mesure
              Row(
                children: [
                  // Champ Quantité
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _quantiteController,
                      decoration: InputDecoration(
                        labelText: T.productQuantityLabel,
                        prefixIcon: const Icon(Icons.exposure),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabled: !_isEditMode,
                        fillColor: _isEditMode ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
                        filled: _isEditMode,
                      ),
                      readOnly: _isEditMode,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return T.quantityRequired;
                        final val = double.tryParse(v.trim().replaceAll(',', '.'));
                        if (val == null || val < 0) return T.validationInvalidNumber;
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Unité de Mesure
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedUnit,
                      decoration: InputDecoration(
                        labelText: T.unitLabel,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: uniqueUnitOptions.map((String unit) {
                        return DropdownMenuItem<String>(
                          value: unit,
                          child: Text(unit),
                        );
                      }).toList(),
                      onChanged: _isEditMode ? null : (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedUnit = newValue;
                          });
                        }
                      },
                      validator: (value) => (value == null || value.isEmpty) ? T.unitRequired : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // PANNEAU AJOUT DE STOCK (UNIQUEMENT EN MODE ÉDITION)
              if (_isEditMode) _buildStockAdditionPanel(T),

              // PANNEAU HISTORIQUE (UNIQUEMENT EN MODE ÉDITION)
              if (_isEditMode) _buildHistoryPanel(T),

              const SizedBox(height: 30),

              // 6. Bouton d'Enregistrement
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveProduct,
                  icon: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_saving
                      ? T.saving
                      : (_produitId == null ? T.saveButton : T.updateButton)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;
    final String title = _produitId == null ? T.addProductTitle : T.setupTitleEdit;

    // Gestion de l'initialisation (écran de chargement)
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Gestion de l'erreur critique (utilisateur non connecté)
    if (_currentOwnerId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(T.errorUserNotLoggedIn, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ),
      );
    }

    // FutureBuilder pour le chargement des catégories (Unique élément asynchrone restant)
    return FutureBuilder<List<String>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  T.loadingError(snapshot.error.toString()),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          );
        }

        if (snapshot.hasData) {
          // Mettre à jour les listes de catégories basées sur les données chargées
          _processCategories(snapshot.data!, T);

          // Afficher le formulaire après le chargement des données
          return _buildProductForm(T, title);
        }

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Center(child: Text(T.internalLoadingError)),
        );
      },
    );
  }
}
