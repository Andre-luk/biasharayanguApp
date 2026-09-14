// lib/pages/inventaires_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/models/inventaire_quotidien.dart';
import 'package:biashara_yangu/models/produit.dart';
import 'package:biashara_yangu/services/sync_service.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

enum InventoryFilter { all, ok, surplus, shortage }

class InventairesPage extends StatefulWidget {
  const InventairesPage({super.key});

  @override
  State<InventairesPage> createState() => _InventairesPageState();
}

class _InventairesPageState extends State<InventairesPage> {
  final DBHelper _db = DBHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  String? _ownerId;
  bool _loading = true;
  String _search = '';
  InventoryFilter _filter = InventoryFilter.all;

  List<InventaireQuotidien> _inventaires = [];
  Map<int, String> _produitNames = {};
  Map<int, Produit> _produitsById = {};

  static const double _diffTolerance = 0.000001;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _init();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() => _search = _searchController.text.trim().toLowerCase());
  }

  Future<void> _init() async {
    final userId = await SessionManager.getUserId();
    if (!mounted) return;

    setState(() {
      _ownerId = userId;
    });

    if (_ownerId != null) {
      await _reload();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    if (_ownerId == null) return;
    // On ne vérifie pas !mounted ici car on veut lancer le chargement,
    // on vérifiera juste avant le setState.

    setState(() => _loading = true);

    try {
      // 1. Chargement parallèle pour plus de rapidité
      final results = await Future.wait([
        _db.getProduits(ownerId: _ownerId!),
        _db.getInventairesQuotidiens(ownerId: _ownerId!),
      ]);

      final List<Produit> produits = results[0] as List<Produit>;
      final List<InventaireQuotidien> data = results[1] as List<InventaireQuotidien>;

      final Map<int, String> namesMap = {};
      final Map<int, Produit> productsMap = {};

      for (final p in produits) {
        if (p.id == null) continue;

        // Conversion sécurisée en int
        final int id = int.tryParse(p.id.toString()) ?? 0;
        if (id != 0) {
          namesMap[id] = p.nom.trim();
          productsMap[id] = p;
        }
      }

      if (!mounted) return;

      setState(() {
        _produitNames = namesMap;
        _produitsById = productsMap;
        _inventaires = data;
        _loading = false;
      });

      // Debug optionnel pour vérifier en console si la Map est remplie
      // print("Noms chargés : ${_produitNames.length} produits");

    } catch (e) {
      debugPrint('Erreur Biashara Yangu (Reload): $e');
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur de chargement : $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  double _varianceOf(InventaireQuotidien i) {
    final physical = i.quantitePhysique ?? i.quantiteTheorique;
    return physical - i.quantiteTheorique;
  }

  bool _isOk(InventaireQuotidien i) => _varianceOf(i).abs() <= _diffTolerance;
  bool _isSurplus(InventaireQuotidien i) => _varianceOf(i) > _diffTolerance;
  bool _isShortage(InventaireQuotidien i) => _varianceOf(i) < -_diffTolerance;

  String _formatQty(double qty) {
    return qty == qty.toInt() ? qty.toInt().toString() : qty.toStringAsFixed(2);
  }

  String _formatDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd/MM/yyyy').format(parsed);
  }

  Color _statusColor(InventaireQuotidien i) {
    if (_isOk(i)) return Colors.green;
    if (_isShortage(i)) return Colors.red;
    return Colors.blue;
  }

  String _statusLabel(InventaireQuotidien i) {
    if (_isOk(i)) return 'OK';
    if (_isShortage(i)) return 'Manquant';
    return 'Excédent';
  }

  List<InventaireQuotidien> get _filteredInventaires {
    final filtered = _inventaires.where((i) {
      // ➔ ON FORCE EN INT ICI
      final int pId = int.tryParse(i.produitId.toString()) ?? 0;
      final name = _produitNames[pId]?.toLowerCase() ?? '';

      final byId = i.produitId.toString().contains(_search);

      final matchesSearch = _search.isEmpty ||
          name.contains(_search) ||
          byId;

      final matchesFilter = switch (_filter) {
        InventoryFilter.all => true,
        InventoryFilter.ok => _isOk(i),
        InventoryFilter.surplus => _isSurplus(i),
        InventoryFilter.shortage => _isShortage(i),
      };

      return matchesSearch && matchesFilter;
    }).toList();

    filtered.sort((a, b) => b.dateCloture.compareTo(a.dateCloture));
    return filtered;
  }

  int get _totalInventories => _inventaires.length;
  int get _okCount => _inventaires.where(_isOk).length;
  int get _surplusCount => _inventaires.where(_isSurplus).length;
  int get _shortageCount => _inventaires.where(_isShortage).length;

  double get _totalVariance =>
      _inventaires.fold(0.0, (sum, i) => sum + _varianceOf(i));

  Future<void> _showAddInventaireDialog() async {
    if (_ownerId == null) return;

    final allProducts = await _db.getProduits(ownerId: _ownerId!);
    if (!mounted) return;

    if (allProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun produit disponible pour inventaire.')),
      );
      return;
    }

    int? selectedProductId;
    String dialogSearch = '';
    String physicalText = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true, // Indispensable pour monter au-dessus du clavier
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                bool saving = false;

                // --- LOGIQUE DE FILTRAGE ---
                final filteredProducts = allProducts.where((p) {
                  final query = dialogSearch.trim().toLowerCase();
                  if (query.isEmpty) return true;
                  return p.nom.toLowerCase().contains(query) ||
                      (p.categorie ?? '').toLowerCase().contains(query);
                }).toList();

                final selectedProduit = allProducts.cast<Produit?>().firstWhere(
                      (p) => p?.id == selectedProductId,
                  orElse: () => null,
                );

                final double currentStock = selectedProduit?.quantite ?? 0.0;
                final double? physicalQty = double.tryParse(physicalText.trim().replaceAll(',', '.'));
                final double? diff = (selectedProduit != null && physicalQty != null)
                    ? physicalQty - currentStock
                    : null;

                // Définition des couleurs d'écart
                Color diffColor = Colors.grey;
                String diffLabel = '—';
                if (diff != null) {
                  if (diff.abs() <= 0.01) {
                    diffColor = Colors.green;
                    diffLabel = 'Écart: 0';
                  } else if (diff < 0) {
                    diffColor = Colors.red;
                    diffLabel = 'Écart: ${diff.toStringAsFixed(2)}';
                  } else {
                    diffColor = Colors.blue;
                    diffLabel = 'Écart: +${diff.toStringAsFixed(2)}';
                  }
                }

                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      // --- EN-TÊTE FIXE ---
                      const SizedBox(height: 12),
                      Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Clôturer un inventaire',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),

                      // --- ZONE DÉFILANTE (S'adapte à la taille de l'écran) ---
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          // Le padding 'bottom' repousse le contenu au-dessus du clavier
                          padding: EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: MediaQuery.of(context).viewInsets.bottom + 24
                          ),
                          children: [
                            TextField(
                              decoration: InputDecoration(
                                labelText: 'Rechercher un produit',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onChanged: (value) => setDialogState(() => dialogSearch = value),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<Produit>(
                              isExpanded: true,
                              value: selectedProduit,
                              decoration: InputDecoration(
                                labelText: 'Sélectionner le produit',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                prefixIcon: const Icon(Icons.inventory_2_outlined),
                              ),
                              items: filteredProducts.map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.nom, overflow: TextOverflow.ellipsis),
                              )).toList(),
                              onChanged: (val) => setDialogState(() => selectedProductId = val?.id),
                            ),

                            if (selectedProduit != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.blue.withOpacity(0.1)),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Stock en système :'),
                                        Text(currentStock.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Écart constaté :'),
                                        Text(diffLabel, style: TextStyle(fontWeight: FontWeight.bold, color: diffColor)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),
                            TextField(
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Quantité physique comptée',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                prefixIcon: const Icon(Icons.calculate_outlined),
                              ),
                              onChanged: (value) => setDialogState(() => physicalText = value),
                            ),

                            const SizedBox(height: 32),

                            // --- BOUTONS INTÉGRÉS DANS LA LISTE ---
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton( // Utilisation d'un OutlinedButton pour l'annulation (plus élégant)
                                    onPressed: () => Navigator.pop(sheetContext),
                                    child: const Text('Annuler'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: (selectedProduit == null || saving)
                                        ? null
                                        : () async {
                                      final physique = double.tryParse(physicalText.trim().replaceAll(',', '.'));
                                      if (physique == null || physique < 0) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quantité invalide')));
                                        return;
                                      }

                                      setDialogState(() => saving = true);
                                      try {
                                        await _db.insertInventaireQuotidien(InventaireQuotidien(
                                          ownerId: _ownerId!,
                                          produitId: selectedProduit.id!,
                                          quantiteTheorique: selectedProduit.quantite,
                                          quantitePhysique: physique,
                                          dateCloture: DateTime.now().toIso8601String().substring(0, 10),
                                        ));

                                        final diffAction = physique - selectedProduit.quantite;
                                        if (diffAction != 0) {
                                          await _db.insertAjustement(
                                            produitId: selectedProduit.id!,
                                            quantite: diffAction,
                                            raison: 'Auto-ajustement via inventaire',
                                          );
                                        }

                                        // Si SyncService est défini dans votre projet
                                        try {
                                          await SyncService.instance.syncAll();
                                        } catch (_) {}

                                        if (!mounted) return;
                                        Navigator.pop(sheetContext);
                                        _reload();
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Inventaire clôturé !')));
                                      } catch (e) {
                                        setDialogState(() => saving = false);
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                                      }
                                    },
                                    child: saving
                                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Text('Clôturer'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showInventoryDetails(InventaireQuotidien i) {
    // 1. FORCE LA CONVERSION : Indispensable pour la correspondance avec la Map
    final int pId = int.tryParse(i.produitId.toString()) ?? 0;

    // 2. RÉCUPÉRATION DU NOM : On utilise le pId converti
    final prodName = _produitNames[pId]?.trim().isNotEmpty == true
        ? _produitNames[pId]!
        : 'Produit $pId';

    final variance = _varianceOf(i);
    final statusColor = _statusColor(i);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white, // Fond blanc propre
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Barre de drag (le petit trait gris en haut)
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Titre : Nom du produit
                  Text(
                    prodName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 6),
                  Text(
                    'Détails de l\'inventaire du ${_formatDate(i.dateCloture)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),

                  const SizedBox(height: 24),

                  // Lignes de détails
                  _detailRow('Stock théorique', _formatQty(i.quantiteTheorique)),
                  const Divider(height: 24, thickness: 0.5),
                  _detailRow(
                    'Stock physique',
                    _formatQty(i.quantitePhysique ?? 0),
                  ),
                  const Divider(height: 24, thickness: 0.5),
                  _detailRow(
                    'Écart constaté',
                    variance == 0
                        ? '0'
                        : variance > 0
                        ? '+${_formatQty(variance)}'
                        : _formatQty(variance),
                    valueColor: statusColor,
                  ),

                  const SizedBox(height: 24),

                  // Badge de statut
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: statusColor.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: statusColor, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _statusLabel(i),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Bouton fermer
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Fermer'),
                    ),
                  ),
                  // Padding supplémentaire pour le confort en bas de page
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color.withOpacity(0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, InventoryFilter filter) {
    final selected = _filter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (value) {
        if (!value) return;
        setState(() => _filter = filter);
      },
    );
  }

  Widget _buildInventoryCard(InventaireQuotidien i, ThemeData theme, AppLocalizations T) {
    // 1. FORCE LA CONVERSION : Indispensable pour faire le pont entre String (DB) et Int (Map)
    final int pId = int.tryParse(i.produitId.toString()) ?? 0;

    // 2. RÉCUPÉRATION DU NOM : Utilise l'ID nettoyé pour piocher dans le dictionnaire
    final prodName = (_produitNames[pId]?.trim().isNotEmpty ?? false)
        ? _produitNames[pId]!
        : 'Produit $pId';

    final variance = _varianceOf(i);
    final statusColor = _statusColor(i);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4), // Légère marge pour l'espacement
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: statusColor.withOpacity(0.12)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showInventoryDetails(i),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Indicateur visuel du statut
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.fact_check_outlined, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),

              // Section centrale : Nom et Date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      prodName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(i.dateCloture),
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Théorique: ${_formatQty(i.quantiteTheorique)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

              // Section droite : Physique et Écart
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Phys: ${_formatQty(i.quantitePhysique ?? 0)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _statusLabel(i) == 'OK'
                          ? 'OK'
                          : variance > 0
                          ? '+${_formatQty(variance)}'
                          : _formatQty(variance),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
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
          suffixIcon: _search.isNotEmpty
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

  Widget _buildSummarySection(AppLocalizations T) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Inventaires',
                  value: _totalInventories.toString(),
                  icon: Icons.fact_check_outlined,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSummaryCard(
                  title: 'OK',
                  value: _okCount.toString(),
                  icon: Icons.verified_outlined,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Excédents',
                  value: _surplusCount.toString(),
                  icon: Icons.arrow_upward_rounded,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Manquants',
                  value: _shortageCount.toString(),
                  icon: Icons.arrow_downward_rounded,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.orange.withOpacity(0.15)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Variation totale',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _totalVariance >= 0
                        ? '+${_formatQty(_totalVariance)}'
                        : _formatQty(_totalVariance),
                    style: TextStyle(
                      color: _totalVariance == 0
                          ? Colors.green
                          : _totalVariance < 0
                          ? Colors.red
                          : Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('Tous', InventoryFilter.all),
            const SizedBox(width: 8),
            _buildFilterChip('OK', InventoryFilter.ok),
            const SizedBox(width: 8),
            _buildFilterChip('Excédents', InventoryFilter.surplus),
            const SizedBox(width: 8),
            _buildFilterChip('Manquants', InventoryFilter.shortage),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final filtered = _filteredInventaires;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi des inventaires'),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddInventaireDialog,
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Nouvel inventaire'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _reload,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 750;

              return CustomScrollView(
                // physics: AlwaysScrollable pour que le RefreshIndicator fonctionne même si la liste est courte
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // 1. Les en-têtes qui défilent si besoin
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _buildToolbar(T),
                        _buildSummarySection(T),
                        const SizedBox(height: 4),
                        _buildFilterBar(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                  // 2. Cas où la liste est vide
                  if (filtered.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 100),
                          child: Text('Aucun inventaire trouvé.'),
                        ),
                      ),
                    )
                  else
                  // 3. La grille d'inventaires
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 100), // Marge pour le FAB
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isWide ? 2 : 1,
                          mainAxisExtent: 130, // Légèrement augmenté pour éviter l'overflow interne
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                              (context, index) {
                            return _buildInventoryCard(filtered[index], theme, T);
                          },
                          childCount: filtered.length,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}