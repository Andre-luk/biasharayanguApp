// lib/pages/depenses_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/models/depense.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

class DepensesPage extends StatefulWidget {
  const DepensesPage({super.key});

  @override
  State<DepensesPage> createState() => _DepensesPageState();
}

class _DepensesPageState extends State<DepensesPage> {
  final DBHelper _db = DBHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  String? _ownerId;
  bool _loading = true;
  String _search = '';
  List<Depense> _depenses = [];

  final List<String> _suggestedMotifs = [
    'Transport',
    'Loyer',
    'Électricité / Eau',
    'Salaire Personnel',
    'Achat Stock',
    'Communication / Internet',
    'Divers',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() => _search = _searchController.text.trim().toLowerCase());
    });
    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _ownerId = await SessionManager.getUserId();
    if (!mounted) return;

    if (_ownerId == null) {
      setState(() => _loading = false);
      return;
    }
    await _reload();
  }

  Future<void> _reload() async {
    if (_ownerId == null) return;
    setState(() => _loading = true);

    try {
      final data = await _db.getDepenses(ownerId: _ownerId!);
      if (!mounted) return;
      setState(() {
        _depenses = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnackBar('Erreur : $e', isError: true);
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  double get _total => _depenses.fold<double>(0.0, (sum, d) => sum + d.montant);

  List<Depense> get _filteredDepenses {
    final list = _search.isEmpty
        ? _depenses
        : _depenses.where((d) {
      return d.motif.toLowerCase().contains(_search) ||
          d.montant.toString().contains(_search);
    }).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  IconData _getIconForMotif(String motif) {
    final m = motif.toLowerCase();
    if (m.contains('transport')) return Icons.directions_car;
    if (m.contains('loyer')) return Icons.home_work;
    if (m.contains('stock')) return Icons.inventory_2;
    if (m.contains('salaire')) return Icons.people;
    if (m.contains('electri') || m.contains('eau')) return Icons.bolt;
    if (m.contains('internet') || m.contains('comm')) return Icons.cell_tower;
    return Icons.shopping_bag_outlined;
  }

  Future<void> _showAddDepenseDialog() async {
    if (_ownerId == null) return;

    final motifController = TextEditingController();
    final montantController = TextEditingController();
    String? selectedSuggestion;

    try {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          bool saving = false;

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                scrollable: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                title: const Text('Nouvelle dépense'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedSuggestion,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Motif prédéfini',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.list),
                          ),
                          items: _suggestedMotifs
                              .map(
                                (m) => DropdownMenuItem(
                              value: m,
                              child: Text(
                                m,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                              .toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedSuggestion = val;
                              motifController.text = val ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Ou description personnalisée :",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: motifController,
                          decoration: const InputDecoration(
                            labelText: 'Motif détaillé',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.edit_note),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: montantController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Montant',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Annuler'),
                  ),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                      final motif = motifController.text.trim();
                      final montant = double.tryParse(
                        montantController.text.trim().replaceAll(',', '.'),
                      );

                      if (motif.isEmpty || montant == null || montant <= 0) {
                        _showSnackBar('Champs invalides', isError: true);
                        return;
                      }

                      setDialogState(() => saving = true);

                      try {
                        await _db.insertDepense(
                          Depense(
                            ownerId: _ownerId!,
                            motif: motif,
                            montant: montant,
                            date: DateTime.now().toIso8601String(),
                          ),
                        );

                        if (!mounted) return;
                        Navigator.pop(dialogContext, true);
                        await _reload();
                      } catch (e) {
                        setDialogState(() => saving = false);
                        _showSnackBar('Erreur : $e', isError: true);
                      }
                    },
                    child: saving
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Text('Enregistrer'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      motifController.dispose();
      montantController.dispose();
    }
  }

  Future<void> _showDepenseDetails(Depense d) async {
    final date = DateTime.tryParse(d.date)?.toLocal();
    final dateStr = date != null ? DateFormat('dd/MM/yyyy HH:mm').format(date) : d.date;

    final icon = _getIconForMotif(d.motif);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.red.withOpacity(0.1),
                        child: Icon(icon, color: Colors.red),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          d.motif,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _detailRow('Montant', '${d.montant.toStringAsFixed(0)} FC'),
                  _detailRow('Date', dateStr),
                  _detailRow('Statut', d.isSynced == 1 ? 'Synchronisée' : 'En attente'),
                  if (d.supabaseId != null && d.supabaseId!.isNotEmpty)
                    _detailRow('Supabase ID', d.supabaseId!),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                      label: const Text('Fermer'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Depense d) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: const Text('Voulez-vous supprimer cette dépense ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Oui'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (d.id == null) {
      _showSnackBar('Erreur : ID manquant', isError: true);
      return;
    }

    try {
      if (d.supabaseId != null && d.supabaseId!.isNotEmpty) {
        await Supabase.instance.client
            .from('depenses')
            .delete()
            .eq('id', d.supabaseId!);
      }

      await _db.deleteDepenseById(d.id!);
      await _reload();
      _showSnackBar('Dépense supprimée');
    } catch (e) {
      debugPrint('Erreur suppression dépense: $e');
      _showSnackBar('Erreur suppression : $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final filtered = _filteredDepenses;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dépenses', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDepenseDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle dépense'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 750;

            return _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
              children: [
                _buildHeader(isWide, theme, T),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _reload,
                    child: filtered.isEmpty
                        ? _buildEmptyState()
                        : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isWide ? 2 : 1,
                        mainAxisExtent: 100,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final depense = filtered[index];
                        return _buildDepenseCard(depense, theme, T);
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool isWide, ThemeData theme, AppLocalizations T) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Flex(
        direction: isWide ? Axis.horizontal : Axis.vertical,
        children: [
          Expanded(
            flex: isWide ? 2 : 0,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.4),
              ),
            ),
          ),
          SizedBox(width: isWide ? 16 : 0, height: isWide ? 0 : 12),
          Expanded(
            flex: isWide ? 1 : 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '${_total.toStringAsFixed(0)} ${T.currencyUnit}',
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.red,
                      ),
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

  Widget _buildDepenseCard(Depense d, ThemeData theme, AppLocalizations T) {
    final date = DateTime.tryParse(d.date)?.toLocal();
    final dateStr = date != null ? DateFormat('dd/MM HH:mm').format(date) : d.date;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDepenseDetails(d),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.red.withOpacity(0.1),
                child: Icon(_getIconForMotif(d.motif), color: Colors.red, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.motif,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '${d.montant.toStringAsFixed(0)} ${T.currencyUnit}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                      onPressed: () => _confirmDelete(d),
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

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 100),
        Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey),
        Center(
          child: Text(
            'Aucune dépense.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }
}