// ⚠️ FICHIER LEGACY — PLUS RELIÉ À LA NAVIGATION.
// L'écran Stock officiel est `stock_gestion_page.dart` (Module 9, Supabase) :
// route `/main/stock`. Fichier conservé pour référence uniquement.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/produit.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/services/sync_service.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

class StockManagementPage extends StatefulWidget {
  const StockManagementPage({super.key});

  @override
  State<StockManagementPage> createState() => _StockManagementPageState();
}

class _StockManagementPageState extends State<StockManagementPage> {
  static const int _lowStockThreshold = 5;

  List<Produit> produits = [];
  List<Produit> filtered = [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();

  String? _currentOwnerId;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double _qtyValue(Produit p) => p.quantite ?? 0.0;

  String _formatQty(double qty) {
    return qty == qty.toInt() ? qty.toInt().toString() : qty.toStringAsFixed(1);
  }

  Color _stockColor(double qty) {
    if (qty <= 0) return Colors.red.shade700;
    if (qty <= _lowStockThreshold) return Colors.orange.shade700;
    return Colors.green.shade600;
  }

  Future<void> _initData() async {
    final userId = await SessionManager.getUserId();
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    _currentOwnerId = userId;

    try {
      await SyncService.instance.syncAll();
    } catch (e) {
      debugPrint('Erreur sync initiale: $e');
    } finally {
      await _loadProduits();
    }
  }

  Future<void> _loadProduits() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final userIdString = await SessionManager.getUserId();
    if (userIdString == null) {
      if (mounted) {
        setState(() {
          produits = [];
          filtered = [];
          _loading = false;
        });
      }
      return;
    }

    final data = await DBHelper.instance.getProduits(ownerId: userIdString);

    if (!mounted) return;

    setState(() {
      produits = data;
      _loading = false;
      final currentQuery = _searchController.text;
      if (currentQuery.isNotEmpty) {
        _filter(currentQuery);
      } else {
        filtered = data;
      }
    });
  }

  void _filter(String q) {
    if (!mounted) return;

    if (q.trim().isEmpty) {
      setState(() => filtered = produits);
      return;
    }

    final val = q.toLowerCase();
    setState(() {
      filtered = produits.where((p) {
        return (p.nom ?? '').toLowerCase().contains(val) ||
            (p.categorie ?? '').toLowerCase().contains(val);
      }).toList();
    });
  }

  Future<void> _navigateToEditProduct(Produit produit) async {
    final res = await context.push('/main/edit-product', extra: produit);
    if (res == true) await _loadProduits();
  }

  Future<void> _navigateToAddProduct() async {
    final res = await context.push('/main/add-product');
    if (res == true) await _loadProduits();
  }

  Future<void> _showStockDialog(Produit p) async {
    final T = AppLocalizations.of(context)!;
    final qtyController = TextEditingController();
    final priceController = TextEditingController();

    bool replaceMode = false;

    final currentQty = _qtyValue(p);
    qtyController.text = currentQty.toStringAsFixed(currentQty == currentQty.toInt() ? 0 : 1);

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        bool isProcessing = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final qtyLabel = replaceMode ? 'Nouvelle quantité' : T.supplyQuantityHint;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                T.supplyProductTitle(p.nom),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.blue.shade100),
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
                            '${_formatQty(currentQty)} ${p.uniteMesure ?? T.productUnitDefault}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Remplacement de Row par Wrap pour éviter les débordements horizontaux
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        ChoiceChip(
                          label: const Text('Ajouter'),
                          selected: !replaceMode,
                          onSelected: isProcessing
                              ? null
                              : (_) => setDialogState(() => replaceMode = false),
                        ),
                        ChoiceChip(
                          label: const Text('Remplacer'),
                          selected: replaceMode,
                          onSelected: isProcessing
                              ? null
                              : (_) => setDialogState(() => replaceMode = true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: qtyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: qtyLabel,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: T.supplyPriceHint,
                        prefixText: '${T.currencyUnit} ',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.of(dialogContext).pop(false),
                  child: Text(T.cancelButton),
                ),
                FilledButton(
                  onPressed: isProcessing
                      ? null
                      : () async {
                    final qtyText = qtyController.text.replaceAll(',', '.');
                    final priceText = priceController.text.replaceAll(',', '.');

                    final double? inputQty = double.tryParse(qtyText);
                    final double? newPurchasePrice = double.tryParse(priceText);

                    if (inputQty == null || inputQty <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(T.invalidQuantity)),
                      );
                      return;
                    }

                    if (newPurchasePrice == null || newPurchasePrice <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(T.invalidPrice)),
                      );
                      return;
                    }

                    final ownerId = await SessionManager.getUserId();
                    if (ownerId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(T.sessionExpired)),
                      );
                      return;
                    }

                    setDialogState(() => isProcessing = true);

                    try {
                      if (replaceMode) {
                        await DBHelper.instance.updateProduitQuantity(
                          product: p,
                          newQuantity: inputQty,
                          purchasePrice: newPurchasePrice,
                          ownerId: ownerId,
                        );
                      } else {
                        await DBHelper.instance.addStockAndLog(
                          p.copyWith(ownerId: ownerId),
                          inputQty,
                          newPurchasePrice,
                        );
                      }

                      await SyncService.instance.syncAll();
                      await _loadProduits();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              replaceMode
                                  ? 'Stock remplacé avec succès.'
                                  : T.supplySuccess(
                                inputQty.toStringAsFixed(1),
                                p.uniteMesure ?? T.productUnitDefault,
                              ),
                            ),
                          ),
                        );
                      }

                      Navigator.of(dialogContext).pop(true);
                    } catch (e) {
                      debugPrint('Erreur stock: $e');
                      setDialogState(() => isProcessing = false);

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(T.genericError)),
                      );
                    }
                  },
                  child: isProcessing
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Text(T.saveButton),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showTraceabilityHistory(Produit p) async {
    final T = AppLocalizations.of(context)!;
    if (p.id == null) return;

    final historique = await DBHelper.instance.getHistoriqueApprovisionnement(p.id!);
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(T.traceabilityHistoryTitle(p.nom)),
          content: SizedBox(
            width: double.maxFinite,
            child: historique.isEmpty
                ? Center(child: Text(T.traceabilityEmpty))
                : ListView.builder(
              shrinkWrap: true,
              itemCount: historique.length,
              itemBuilder: (context, index) {
                final appro = historique[index];
                final date = DateTime.tryParse(appro.dateApprovisionnement);
                final dateFormatted = date != null ? T.formatDate(date) : T.dateUnknown;

                return ListTile(
                  leading: const Icon(Icons.history, color: Colors.indigo),
                  title: Text(
                    '+${appro.quantiteAjoutee.toStringAsFixed(p.uniteMesure == 'unité' ? 0 : 1)} ${p.uniteMesure}',
                  ),
                  subtitle: Text(
                    '${T.atDate}: $dateFormatted\n${T.atPrice}: ${appro.prixAchatUnitaire.toStringAsFixed(0)} ${T.currencyUnit}',
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(T.closeButton),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteProduct(Produit p) async {
    final T = AppLocalizations.of(context)!;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(T.confirmDeleteProductTitle),
        content: Text(T.confirmDeleteProductMessage(p.nom)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(T.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(T.deleteButton),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (p.supabaseId != null) {
          await Supabase.instance.client.from('produits').delete().eq('id', p.supabaseId!);
        }
        await DBHelper.instance.deleteProduit(p.id!);
        await _loadProduits();
      } catch (e) {
        debugPrint('Erreur suppression: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(T.stockManagementTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: T.searchProductHint,
              ),
              onChanged: _filter,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                final userId = await SessionManager.getUserId();
                if (userId != null) {
                  await SyncService.instance.syncAll();
                  await _loadProduits();
                }
              },
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final p = filtered[index];
                  final double quantite = _qtyValue(p);
                  final Color stockColor = _stockColor(quantite);
                  final String quantityStr = _formatQty(quantite);
                  final String unitLabel = p.uniteMesure ?? T.productUnitDefault;

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: stockColor.withOpacity(0.12)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      leading: GestureDetector(
                        onTap: () => _showStockDialog(p),
                        child: Container(
                          width: 64, // Légèrement élargi
                          height: 64, // Légèrement allongé
                          padding: const EdgeInsets.all(4), // Ajout de padding interne
                          decoration: BoxDecoration(
                            color: stockColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: stockColor.withOpacity(0.35)),
                          ),
                          // Ajout de FittedBox pour éviter tout débordement (Overflow)
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Stock',
                                  style: TextStyle(fontSize: 11, color: Colors.black54),
                                ),
                                Text(
                                  quantityStr,
                                  style: TextStyle(
                                    color: stockColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  unitLabel,
                                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        p.nom ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${p.categorie ?? ''} | ${p.prixVente?.toStringAsFixed(0) ?? '0'} ${T.currencyUnit} / $unitLabel',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add_box, color: Colors.green),
                            onPressed: () => _showStockDialog(p),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (val) {
                              if (val == 'edit') _navigateToEditProduct(p);
                              if (val == 'history') _showTraceabilityHistory(p);
                              if (val == 'delete') _deleteProduct(p);
                            },
                            // 🔐 MODULE 4 — « modifier » et « supprimer » un
                            // article dépendent des permissions du rôle : un
                            // magasinier ne verra que l'historique.
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'history',
                                child: Text("Historique"),
                              ),
                              if (PermissionService.instance
                                  .peutModifier(PageAccess.articles))
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(T.updateButton),
                                ),
                              if (PermissionService.instance
                                  .peutSupprimer(PageAccess.articles)) ...[
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'delete',
                                  textStyle: const TextStyle(color: Colors.red),
                                  child: Text(T.deleteButton),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      // 🔐 MODULE 4 — créer un article exige la permission correspondante.
      floatingActionButton: PermissionGate(
        page: PageAccess.articles,
        action: ActionAccess.creer,
        child: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: Text(T.buttonAddProduct),
          onPressed: _navigateToAddProduct,
        ),
      ),
    );
  }
}