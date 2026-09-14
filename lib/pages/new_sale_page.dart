// lib/pages/new_sale_page.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/client.dart';
import 'package:biashara_yangu/models/dette.dart';
import 'package:biashara_yangu/models/produit.dart';
import 'package:biashara_yangu/models/vente.dart';
import 'package:biashara_yangu/services/invoice_service.dart';
import 'package:biashara_yangu/services/sync_service.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import '../ui/widgets/primary_loader.dart';

class NewSalePage extends StatefulWidget {
  const NewSalePage({super.key});

  @override
  State<NewSalePage> createState() => _NewSalePageState();
}

class _NewSalePageState extends State<NewSalePage> {
  final StreamController<List<Produit>> _productsController =
  StreamController<List<Produit>>.broadcast();

  RealtimeChannel? _productsChannel;

  List<Produit> produits = [];
  List<Client> clients = [];
  Client? selectedClient;
  bool isModeDette = false;

  final Map<int, double> panier = {};
  String modePaiement = 'cash';
  bool _loading = true;
  String _searchQuery = '';

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();

  final Map<String, IconData> _paymentModes = {
    'cash': Icons.money,
    'carte': Icons.credit_card,
    'm-pesa': Icons.phone_android,
  };

  String? _currentUserId;
  String? _effectiveOwnerId;

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
    _quantityController.dispose();

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
    final supabase = Supabase.instance.client;

    _productsChannel = supabase
        .channel('new-sale-products')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'produits',
      callback: (payload) {
        if (!mounted) return;
        _reloadData(showLoading: false, syncBeforeLoad: false);
      },
    )
        .subscribe();
  }

  Future<void> _initializeData() async {
    _startRealtimeListener();
    await _reloadData(showLoading: true, syncBeforeLoad: true);
  }

  Future<void> _reloadData({
    required bool showLoading,
    required bool syncBeforeLoad,
  }) async {
    if (!mounted) return;

    if (showLoading) {
      setState(() => _loading = true);
    }

    try {
      _currentUserId = await SessionManager.getUserId();

      if (_currentUserId == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        if (context.mounted) {
          context.go('/login');
        }
        return;
      }

      _effectiveOwnerId =
      await DBHelper.instance.resolveEffectiveOwnerId(_currentUserId!);

      final ownerId = _effectiveOwnerId ?? _currentUserId!;

      if (syncBeforeLoad) {
        try {
          await SyncService.instance.syncAll();
        } catch (e) {
          debugPrint('⚠️ Sync initiale ignorée: $e');
        }
      }

      final data = await Future.wait([
        DBHelper.instance.getProduits(ownerId: ownerId),
        DBHelper.instance.getClients(ownerId: ownerId),
      ]);

      if (!mounted) return;

      final loadedProducts = data[0] as List<Produit>;
      final loadedClients = data[1] as List<Client>;

      setState(() {
        produits = loadedProducts;
        clients = loadedClients;
        _loading = false;
      });

      if (!_productsController.isClosed) {
        _productsController.add(loadedProducts);
      }
    } catch (e) {
      debugPrint('Erreur chargement new sale: $e');
      if (!mounted) return;

      setState(() => _loading = false);

      if (!_productsController.isClosed) {
        _productsController.addError(e);
      }
    }
  }

  void _updateQuantity(Produit p, double qty) {
    if (p.id == null) return;

    if (qty <= 0) {
      setState(() => panier.remove(p.id));
      return;
    }

    if (qty > p.quantite) {
      _showSnackBar(AppLocalizations.of(context)!.outOfStock, isError: true);
      return;
    }

    setState(() => panier[p.id!] = qty);
  }

  void _setProductQuantity(Produit p, double qty) => _updateQuantity(p, qty);

  void _incrementProductQuantity(Produit p, {double step = 1.0}) {
    if (p.id == null) return;
    final current = panier[p.id] ?? 0.0;
    _updateQuantity(p, current + step);
  }

  double get total {
    double sum = 0;
    for (var item in panier.entries) {
      final p = produits.firstWhere((prod) => prod.id == item.key);
      sum += p.prixVente * item.value;
    }
    return sum;
  }

  Future<void> _confirmCancelSale() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Annuler la vente ?"),
        content: const Text(
          "Voulez-vous vraiment vider le panier et annuler cette vente en cours ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Non"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Oui, annuler"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        panier.clear();
        selectedClient = null;
        isModeDette = false;
        _searchController.clear();
      });
      _showSnackBar("Vente annulée");
    }
  }

  Future<void> _save() async {
    final T = AppLocalizations.of(context)!;
    if (panier.isEmpty) return;

    if (isModeDette && selectedClient == null) {
      _showSnackBar(
        "Veuillez sélectionner un client pour le crédit",
        isError: true,
      );
      return;
    }

    final ownerId = _effectiveOwnerId ?? _currentUserId;
    if (ownerId == null) return;

    setState(() => _loading = true);

    try {
      final now = DateTime.now();
      final String nowIso = now.toIso8601String();
      final ventes = <Vente>[];
      final invoiceItems = <InvoiceItem>[];
      final double currentTotal = total;

      for (var e in panier.entries) {
        final p = produits.firstWhere((pr) => pr.id == e.key);
        final totalAmount = p.prixVente * e.value;

        ventes.add(
          Vente(
            produitId: p.id!,
            quantite: e.value,
            prix: totalAmount,
            modePaiement: isModeDette ? 'dette' : modePaiement,
            createdAt: nowIso,
            ownerId: ownerId,
            sellerId: _currentUserId,
            clientId: selectedClient?.id,
          ),
        );

        invoiceItems.add(
          InvoiceItem(
            name: p.nom,
            quantity: e.value,
            unit: p.uniteMesure,
            pricePerUnit: p.prixVente,
            total: totalAmount,
          ),
        );

        p.quantite -= e.value;
      }

      final invoiceId =
      await DBHelper.instance.insertMultipleVentesWithStockUpdate(ventes);

      if (isModeDette && selectedClient != null) {
        await DBHelper.instance.insertDette(
          Dette(
            ownerId: ownerId,
            clientId: selectedClient!.id!,
            venteId: invoiceId,
            montantTotal: currentTotal,
            dateCreation: nowIso,
          ),
        );
      }

      if (mounted) {
        setState(() {
          panier.clear();
          selectedClient = null;
          isModeDette = false;
          _loading = false;
        });

        final user = await DBHelper.instance.getUtilisateurById(ownerId);
        final invoiceService = InvoiceService(
          T: T,
          userName: user?.nom ?? T.defaultStoreName,
          paymentMode: isModeDette ? "Crédit" : modePaiement,
          totalAmount: currentTotal,
          items: invoiceItems,
          saleDate: now,
          invoiceId: invoiceId,
        );

        _showPrintSelectionDialog(invoiceService);
      }

      _triggerImmediateSync();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnackBar("${T.saleError}: $e", isError: true);
      }
    }
  }

  void _triggerImmediateSync() {
    SyncService.instance.syncAll().then((_) async {
      debugPrint("🚀 Sync OK");
      await _reloadData(showLoading: false, syncBeforeLoad: false);
    }).catchError((e) {
      debugPrint("⚠️ Sync Fail: $e");
    });
  }

  void _showSetQuantityDialog(Produit p) {
    final T = AppLocalizations.of(context)!;
    final currentQty = panier[p.id] ?? 1.0;
    _quantityController.text = currentQty.toStringAsFixed(
      currentQty.truncateToDouble() == currentQty ? 0 : 2,
    );

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          T.addToCartTitle(p.nom),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stock actuel : ${p.quantite} ${p.uniteMesure}'),
            const SizedBox(height: 16),
            TextField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: T.dialogQuantityLabel(p.uniteMesure),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(T.cancelButton),
          ),
          FilledButton(
            onPressed: () {
              final qty = double.tryParse(
                _quantityController.text.replaceAll(',', '.'),
              );

              if (qty == null || qty <= 0) {
                _showSnackBar(T.invalidQuantity, isError: true);
                return;
              }

              if (qty > p.quantite) {
                _showSnackBar(
                  T.insufficientStock(
                    p.quantite.toStringAsFixed(2),
                    p.uniteMesure,
                  ),
                  isError: true,
                );
                return;
              }

              Navigator.pop(dialogContext);
              setState(() => _setProductQuantity(p, qty));
            },
            child: Text(T.addButton),
          ),
        ],
      ),
    );
  }

  void _showClientSelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scroll) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Sélectionner un Client",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: clients.length,
                itemBuilder: (context, i) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(clients[i].nom),
                  subtitle: Text(clients[i].telephone ?? ""),
                  onTap: () {
                    setState(() => selectedClient = clients[i]);
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;

    if (_loading) {
      return const Scaffold(
        body: Center(child: PrimaryLoader(size: 36)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(T.newSaleTitle),
        elevation: 0,
        actions: [
          if (panier.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              tooltip: "Annuler la vente",
              onPressed: _confirmCancelSale,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: T.searchProductLabel,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    FocusScope.of(context).unfocus();
                  },
                )
                    : null,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Produit>>(
              stream: _productsController.stream,
              builder: (context, snapshot) {
                final currentProducts = snapshot.data ?? produits;

                final filteredProduits = currentProducts
                    .where(
                      (p) => p.nom.toLowerCase().contains(_searchQuery),
                )
                    .toList();

                if (filteredProduits.isEmpty) {
                  return const Center(
                    child: Icon(Icons.search_off, size: 64, color: Colors.grey),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredProduits.length,
                  itemBuilder: (context, i) =>
                      _buildProductCard(filteredProduits[i], T),
                );
              },
            ),
          ),
          _buildCheckoutPanel(T),
        ],
      ),
    );
  }

  Widget _buildProductCard(Produit p, AppLocalizations T) {
    final theme = Theme.of(context);
    final q = panier[p.id] ?? 0.0;
    final isSelected = q > 0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withOpacity(0.3)
          : theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _pickImage(p),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: p.photo != null && File(p.photo!).existsSync()
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(p.photo!),
                    fit: BoxFit.cover,
                  ),
                )
                    : Icon(
                  Icons.add_a_photo,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nom,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                  ),
                  Text(
                    '${p.prixVente.toStringAsFixed(0)} ${T.currencyUnit} / ${p.uniteMesure}',
                    style: TextStyle(
                      color: theme.colorScheme.secondary,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Stock: ${p.quantite.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: p.quantite <= 5 ? Colors.red : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                if (isSelected)
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          onPressed: () => _updateQuantity(p, q - 1),
                        ),
                        InkWell(
                          onTap: () => _showSetQuantityDialog(p),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              q.toStringAsFixed(
                                q == q.truncateToDouble() ? 0 : 2,
                              ),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () => _incrementProductQuantity(p),
                        ),
                      ],
                    ),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () => _updateQuantity(p, 1),
                    child: Text(T.addButton),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutPanel(AppLocalizations T) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GestureDetector(
                  onTap: _showClientSelection,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    constraints: const BoxConstraints(maxWidth: 200),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            selectedClient?.nom ?? "Client (Opt)",
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selectedClient != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() => selectedClient = null),
                          ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Dette",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Switch(
                      value: isModeDette,
                      onChanged: (v) => setState(() => isModeDette = v),
                      activeColor: Colors.orange,
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL', style: theme.textTheme.bodySmall),
                Text(
                  '${total.toStringAsFixed(0)} ${T.currencyUnit}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!isModeDette)
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: modePaiement,
                      items: _paymentModes.entries
                          .map(
                            (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(T.paymentMode(e.key)),
                        ),
                      )
                          .toList(),
                      onChanged: (v) => setState(() => modePaiement = v ?? 'cash'),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                if (!isModeDette) const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: panier.isNotEmpty ? _save : null,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                        isModeDette ? Colors.orange : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(
                        isModeDette ? Icons.warning_amber : Icons.check_circle,
                      ),
                      label: Text(
                        isModeDette ? "CRÉDIT" : T.recordSaleButton,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPrintSelectionDialog(InvoiceService service) {
    final T = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          T.saleRecordedAndInvoiceGenerated,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 60),
            SizedBox(height: 16),
            Text("Prêt pour la facture ?"),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                service.generateAndPrintInvoice(isTicket: true);
              },
              icon: const Icon(Icons.receipt_long),
              label: const Text("Ticket (58mm)"),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                service.generateAndPrintInvoice(isTicket: false);
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text("PDF / A4"),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(T.cancelButton),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickImage(Produit p) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => p.photo = image.path);
      await DBHelper.instance.updateProduitPhoto(p.id!, image.path);
    }
  }
}