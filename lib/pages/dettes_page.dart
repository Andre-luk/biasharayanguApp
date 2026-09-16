// lib/pages/dettes_page.dart
//
// ⚠️ FICHIER LEGACY — PLUS RELIÉ À LA NAVIGATION.
// L'écran Dettes officiel est `dettes_clients_page.dart` (Module 10,
// Supabase) : route `/main/dettes`. Fichier conservé pour référence.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/models/client.dart';
import 'package:biashara_yangu/models/dette.dart';
import 'package:biashara_yangu/services/sync_service.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

class DettesPage extends StatefulWidget {
  const DettesPage({super.key});

  @override
  State<DettesPage> createState() => _DettesPageState();
}

class _DettesPageState extends State<DettesPage> {
  final DBHelper _db = DBHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  String? _ownerId;
  bool _loading = true;
  String _search = '';

  List<Dette> _dettes = [];
  List<Client> _clients = [];
  Map<int, Client> _clientsById = {};

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
    setState(() {
      _search = _searchController.text.trim().toLowerCase();
    });
  }

  Future<void> _init() async {
    _ownerId = await SessionManager.getUserId();

    if (_ownerId == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    await _reload();
  }

  Future<void> _pushChanges() async {
    try {
      await SyncService.instance.syncAll();
    } catch (e) {
      debugPrint('Sync dettes error: $e');
    }
  }

  Future<void> _reload() async {
    if (_ownerId == null) return;

    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final dataDettes = await _db.getDettes(ownerId: _ownerId!);
      final dataClients = await _db.getClients(ownerId: _ownerId!);

      if (!mounted) return;

      setState(() {
        _dettes = dataDettes;
        _clients = dataClients;
        _clientsById = {
          for (final c in dataClients)
            if (c.id != null) c.id!: c,
        };
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

  double get _totalRestant => _dettes.fold(
    0.0,
        (sum, d) => sum + (d.montantTotal - d.montantPaye),
  );

  String _clientDisplayName(int? clientId) {
    if (clientId == null) return 'Client inconnu';

    final client = _clientsById[clientId];
    final name = client?.nom.trim();

    if (name != null && name.isNotEmpty) {
      return name;
    }

    return 'Client n°$clientId';
  }

  List<Dette> get _filteredDettes {
    final filtered = _dettes.where((d) {
      final clientName = _clientDisplayName(d.clientId).toLowerCase();
      final matchesSearch =
          clientName.contains(_search) || d.statut.toLowerCase().contains(_search);

      final isStillDue = (d.montantTotal - d.montantPaye) > 0;
      return matchesSearch && isStillDue;
    }).toList();

    filtered.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
    return filtered;
  }

  Future<void> _showPaymentDialog(Dette dette) async {
    final remaining = dette.montantTotal - dette.montantPaye;
    final payController = TextEditingController(
      text: remaining.toStringAsFixed(0),
    );

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          bool isProcessing = false;

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Text("Enregistrer un paiement"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Reste à payer : ${remaining.toStringAsFixed(0)}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: payController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Montant payé aujourd'hui",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: isProcessing ? null : () => Navigator.pop(dialogContext),
                    child: const Text("Annuler"),
                  ),
                  FilledButton(
                    onPressed: isProcessing
                        ? null
                        : () async {
                      final payAmount = double.tryParse(
                        payController.text.replaceAll(',', '.'),
                      );

                      if (payAmount == null || payAmount <= 0) {
                        _showSnackBar(
                          "Veuillez entrer un montant valide",
                          isError: true,
                        );
                        return;
                      }

                      final newTotalPaid = dette.montantPaye + payAmount;

                      if (newTotalPaid > dette.montantTotal) {
                        _showSnackBar("Le montant dépasse la dette !", isError: true);
                        return;
                      }

                      setDialogState(() => isProcessing = true);

                      final String newStatus =
                      (dette.montantTotal - newTotalPaid) <= 0
                          ? 'paye'
                          : 'partiel';

                      try {
                        await _db.updateDetteStatus(
                          dette.id!,
                          newTotalPaid,
                          newStatus,
                        );
                        await _pushChanges();

                        if (!mounted) return;
                        Navigator.pop(dialogContext);
                        await _reload();
                        _showSnackBar("Paiement enregistré avec succès !");
                      } catch (e) {
                        setDialogState(() => isProcessing = false);
                        _showSnackBar("Erreur : $e", isError: true);
                      }
                    },
                    child: isProcessing
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Text("Confirmer"),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      payController.dispose();
    }
  }

  Future<void> _deleteDette(Dette dette) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ?"),
        content: const Text(
          "Voulez-vous supprimer cette dette ? Cette action est irréversible.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Non"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Oui, supprimer"),
          ),
        ],
      ),
    );

    if (confirm != true || dette.id == null) return;

    try {
      if (dette.supabaseId != null && dette.supabaseId!.isNotEmpty) {
        await Supabase.instance.client
            .from('dettes')
            .delete()
            .eq('supabase_id', dette.supabaseId!);
      }

      await _db.deleteDetteById(dette.id!);
      await _pushChanges();
      await _reload();
      _showSnackBar("Dette supprimée.");
    } catch (e) {
      _showSnackBar("Erreur suppression : $e", isError: true);
    }
  }

  Future<void> _showAddDetteDialog() async {
    if (_ownerId == null) return;

    final montantController = TextEditingController();

    if (_clients.isEmpty) {
      final clientsFromDb = await _db.getClients(ownerId: _ownerId!);
      if (clientsFromDb.isEmpty) {
        _showSnackBar("Veuillez d'abord créer un client", isError: true);
        montantController.dispose();
        return;
      }
      _clients = clientsFromDb;
      _clientsById = {
        for (final c in clientsFromDb)
          if (c.id != null) c.id!: c,
      };
    }

    Client? selectedClient;

    try {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          bool saving = false;

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                title: const Text('Nouvelle Dette'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<Client>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Client',
                          border: OutlineInputBorder(),
                        ),
                        items: _clients
                            .map(
                              (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c.nom.trim().isNotEmpty ? c.nom.trim() : 'Client n°${c.id}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                            .toList(),
                        onChanged: (val) {
                          setDialogState(() => selectedClient = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: montantController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Montant total',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.money_off),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Annuler'),
                  ),
                  FilledButton(
                    onPressed: (saving || selectedClient == null)
                        ? null
                        : () async {
                      final montant = double.tryParse(
                        montantController.text.replaceAll(',', '.'),
                      );

                      if (montant == null || montant <= 0) {
                        _showSnackBar(
                          'Veuillez entrer un montant valide',
                          isError: true,
                        );
                        return;
                      }

                      setDialogState(() => saving = true);

                      try {
                        await _db.insertDette(
                          Dette(
                            ownerId: _ownerId!,
                            clientId: selectedClient!.id!,
                            montantTotal: montant,
                            montantPaye: 0,
                            dateCreation: DateTime.now().toIso8601String(),
                            statut: 'non_paye',
                          ),
                        );

                        await _pushChanges();

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
      montantController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Gestion des Dettes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDetteDialog,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une dette'),
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildHeader(T, theme),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _reload,
              child: _filteredDettes.isEmpty
                  ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  Icon(Icons.thumb_up_outlined,
                      size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      "Aucune dette active",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              )
                  : LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 750;

                  if (!isWide) {
                    return ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding:
                      const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: _filteredDettes.length,
                      itemBuilder: (context, index) =>
                          _buildDetteCard(
                            _filteredDettes[index],
                            theme,
                            T,
                          ),
                    );
                  }

                  return GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 400,
                      mainAxisExtent: 170,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _filteredDettes.length,
                    itemBuilder: (context, index) =>
                        _buildDetteCard(
                          _filteredDettes[index],
                          theme,
                          T,
                        ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations T, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Rechercher un client...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                },
              )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Total à recouvrer :",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                "${_totalRestant.toStringAsFixed(0)} ${T.currencyUnit}",
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetteCard(Dette d, ThemeData theme, AppLocalizations T) {
    final remaining = d.montantTotal - d.montantPaye;
    final clientName = _clientDisplayName(d.clientId);
    final double progress = d.montantTotal > 0
        ? (d.montantPaye / d.montantTotal).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (progress > 0 ? Colors.blue : Colors.orange)
                        .withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.pending_actions,
                    color: progress > 0 ? Colors.blue : Colors.orange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clientName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Total: ${d.montantTotal.toStringAsFixed(0)} ${T.currencyUnit}",
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "${remaining.toStringAsFixed(0)} ${T.currencyUnit}",
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200],
              color: Colors.green,
              minHeight: 6,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showPaymentDialog(d),
                  icon: const Icon(Icons.add_card),
                  label: const Text("Payer"),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _deleteDette(d),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 22,
                    color: Colors.grey,
                  ),
                  tooltip: "Supprimer",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}