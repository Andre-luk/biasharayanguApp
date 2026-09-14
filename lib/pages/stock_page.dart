// lib/pages/stock_page.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/produit.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/services/sync_service.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  static const double _lowStockThreshold = 5.0;

  final StreamController<List<Produit>> _productsController =
  StreamController<List<Produit>>.broadcast();

  RealtimeChannel? _productsChannel;

  String? _currentOwnerId;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _initializeData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();

    if (_productsChannel != null) {
      Supabase.instance.client.removeChannel(_productsChannel!);
    }

    _productsController.close();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  void _startRealtimeListener() {
    if (_productsChannel != null) return;

    final supabase = Supabase.instance.client;

    _productsChannel = supabase
        .channel('stock-updates')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'produits',
      callback: (payload) async {
        if (!mounted) return;

        // 🔥 IMPORTANT : lecture uniquement, aucune sync ici
        try {
          final products = await DBHelper.instance
              .getProduits(ownerId: _currentOwnerId!);

          if (!_productsController.isClosed) {
            _productsController.add(products);
          }
        } catch (e) {
          debugPrint('Realtime reload error: $e');
        }
      },
    )
        .subscribe();
  }

  Future<void> _initializeData() async {
    final sessionUserId = await SessionManager.getUserId();
    if (!mounted) return;

    if (sessionUserId == null) {
      if (!_productsController.isClosed) {
        _productsController.add(<Produit>[]);
      }
      return;
    }

    final localUser = await DBHelper.instance.getUtilisateurById(sessionUserId);

    final effectiveOwnerId =
    (localUser?.parentId != null && localUser!.parentId!.isNotEmpty)
        ? localUser.parentId!
        : sessionUserId;

    setState(() {
      _currentOwnerId = effectiveOwnerId;
    });

    SyncService.instance.currentOwnerId = effectiveOwnerId;

    await _reloadProducts();

    if (mounted) {
      _startRealtimeListener();
    }
  }

  Future<void> _reloadProducts() async {
    if (!mounted || _currentOwnerId == null) return;

    try {
      final updatedProducts =
      await DBHelper.instance.getProduits(ownerId: _currentOwnerId!);

      if (mounted && !_productsController.isClosed) {
        _productsController.add(updatedProducts);
      }
    } catch (e) {
      debugPrint('StockPage load error: $e');
    }
  }

  Future<void> _navigateToAddProduct() async {
    final result = await context.pushNamed('add-product');
    if (result == true) {
      await _reloadProducts();
    }
  }

  String _formatQty(double qty) {
    return qty == qty.toInt() ? qty.toInt().toString() : qty.toStringAsFixed(2);
  }

  Color _stockColor(double qty) {
    if (qty <= 0) return Colors.red.shade700;
    if (qty <= _lowStockThreshold) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  Widget _buildEmptyState(AppLocalizations T) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey),
            const SizedBox(height: 10),
            Text(
              "Aucun produit en stock.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _navigateToAddProduct,
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(T.buttonAddProduct),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAdjustStockDialog(Produit product) async {
    final result = await showDialog<_StockAdjustmentResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdjustStockDialog(product: product),
    );

    if (!mounted || result == null) return;

    if (result.message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }

    await _reloadProducts();
  }

  Widget _buildProductCard(
      Produit product,
      AppLocalizations T, {
        bool compact = false,
      }) {
    final isLowStock = product.quantite <= _lowStockThreshold;
    final stockColor = _stockColor(product.quantite);
    final quantityStr = _formatQty(product.quantite);
    final unitLabel =
    product.uniteMesure.isNotEmpty ? product.uniteMesure : T.productUnitDefault;

    final image = product.photo != null &&
        product.photo!.isNotEmpty &&
        File(product.photo!).existsSync()
        ? FileImage(File(product.photo!))
        : null;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: stockColor.withOpacity(0.15)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: compact
              ? Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: image,
                child: image == null ? const Icon(Icons.inventory) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.nom,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${T.productCategoryLabel}: ${product.categorie}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${T.productQuantityLabel}: $quantityStr $unitLabel',
                      style: TextStyle(
                        color: stockColor,
                        fontWeight:
                        isLowStock ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Vente: ${product.prixVente.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'adjust') {
                    _showAdjustStockDialog(product);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'adjust',
                    child: Text('Corriger stock'),
                  ),
                ],
              ),
            ],
          )
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage: image,
                    child: image == null ? const Icon(Icons.inventory) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.nom,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${T.productCategoryLabel}: ${product.categorie}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'adjust') {
                        _showAdjustStockDialog(product);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'adjust',
                        child: Text('Corriger stock'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: stockColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${T.productQuantityLabel}: $quantityStr $unitLabel',
                      style: TextStyle(
                        color: stockColor,
                        fontWeight:
                        isLowStock ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vente: ${product.prixVente.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(AppLocalizations T) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Rechercher un produit...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
            },
          )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;

    if (_currentOwnerId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(T.navStock),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reloadProducts,
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(T),
          Expanded(
            child: StreamBuilder<List<Produit>>(
              stream: _productsController.stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Erreur de chargement: ${snapshot.error}'),
                  );
                }

                final products = snapshot.data ?? const <Produit>[];

                final filtered = _searchQuery.isEmpty
                    ? products
                    : products.where((p) {
                  final name = p.nom.toLowerCase();
                  final category = p.categorie.toLowerCase();
                  return name.contains(_searchQuery) ||
                      category.contains(_searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return _buildEmptyState(T);
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isTablet = constraints.maxWidth >= 700;

                    return RefreshIndicator(
                      onRefresh: _reloadProducts,
                      child: isTablet
                          ? GridView.builder(
                        padding: const EdgeInsets.all(12),
                        physics: const AlwaysScrollableScrollPhysics(),
                        gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 2.3,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          return _buildProductCard(
                            filtered[index],
                            T,
                            compact: false,
                          );
                        },
                      )
                          : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final product = filtered[index];
                          return _buildProductCard(
                            product,
                            T,
                            compact: true,
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddProduct,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _StockAdjustmentResult {
  final double diff;
  final String message;

  const _StockAdjustmentResult({
    required this.diff,
    required this.message,
  });
}

class _AdjustStockDialog extends StatefulWidget {
  final Produit product;

  const _AdjustStockDialog({
    required this.product,
  });

  @override
  State<_AdjustStockDialog> createState() => _AdjustStockDialogState();
}

class _AdjustStockDialogState extends State<_AdjustStockDialog> {
  late final TextEditingController _realQtyController;
  late final TextEditingController _reasonController;

  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _realQtyController = TextEditingController();
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _realQtyController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String _formatQty(double qty) {
    return qty == qty.toInt() ? qty.toInt().toString() : qty.toStringAsFixed(2);
  }

  Future<void> _save() async {
    final product = widget.product;
    final qtyText = _realQtyController.text.trim().replaceAll(',', '.');
    final realQty = double.tryParse(qtyText);

    if (realQty == null || realQty < 0) {
      setState(() {
        _errorText = 'Quantité réelle invalide.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      final freshProduct =
      await DBHelper.instance.getProduitById(product.id!);

      if (freshProduct == null) {
        throw Exception("Produit introuvable en base locale.");
      }

      if (freshProduct.quantite == realQty) {
        if (!mounted) return;
        Navigator.of(context).pop(
          const _StockAdjustmentResult(
            diff: 0,
            message: 'Aucune modification appliquée.',
          ),
        );
        return;
      }

      // 🔥 CORRECTION ICI : On calcule la différence (le delta) !
      // Exemple : realQty (12) - ancienStock (14) = -2
      // Exemple : realQty (40) - ancienStock (10) = 30
      final double diff = realQty - freshProduct.quantite;

      await DBHelper.instance.insertAjustement(
        produitId: product.id!,
        quantite: diff, // On envoie le delta, pas la valeur absolue
        raison: _reasonController.text.trim().isEmpty
            ? 'Correction stock réel'
            : _reasonController.text.trim(),
      );

      try {
        await SyncService.instance.syncAll();
      } catch (syncError) {
        debugPrint('⚠️ sync échoué: $syncError');
      }

      if (!mounted) return;

      Navigator.of(context).pop(
        _StockAdjustmentResult(
          diff: diff,
          message: 'Stock mis à jour avec succès.',
        ),
      );
    } catch (e) {
      debugPrint('Erreur correction stock: $e');

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = 'Erreur de correction : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;
    final product = widget.product;
    final displayedQty = product.quantite;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Corriger le stock',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.nom,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stock actuel',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatQty(displayedQty)} ${product.uniteMesure}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _realQtyController,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantité réelle en boutique',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Raison de la correction (optionnel)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Exemple : si l’app indique 14 et que la boutique a 12, entrez 12.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(null),
          child: Text(T.cancelButton),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Text('Valider'),
        ),
      ],
    );
  }
}