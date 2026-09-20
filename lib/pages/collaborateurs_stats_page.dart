// lib/pages/collaborateurs_stats_page.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/collaborateur_stats.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/models/vente.dart';
// 🪙 MODULE 18 — montants formatés dans la devise de l'entreprise.
import 'package:biashara_yangu/utils/format_utils.dart';

enum StatsPeriod { today, thisWeek, thisMonth, custom }

class CollaborateursStatsPage extends StatefulWidget {
  final String ownerId;
  const CollaborateursStatsPage({super.key, required this.ownerId});

  @override
  State<CollaborateursStatsPage> createState() => _CollaborateursStatsPageState();
}

class _SellerAgg {
  int ventesCount = 0;
  double totalAmount = 0.0;
  final List<VenteDetail> details = [];

  void add(VenteDetail detail) {
    ventesCount += 1;
    totalAmount += detail.prixTotal;
    details.add(detail);
  }
}

class _CollaborateursStatsPageState extends State<CollaborateursStatsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;

  List<CollaborateurStats> _stats = [];
  Map<String, Utilisateur> _sellers = {};
  Map<int, String> _productNames = {};
  Map<String, List<VenteDetail>> _detailsBySeller = {};

  StatsPeriod _selectedPeriod = StatsPeriod.today;
  DateTimeRange? _selectedRange;

  Utilisateur? _ownerProfile;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  String _formatQty(num qty) {
    return qty == qty.truncateToDouble()
        ? qty.toInt().toString()
        : qty.toStringAsFixed(2);
  }

  String _formatRangeLabel(DateTimeRange range) {
    final start = range.start;
    final endInclusive = range.end.subtract(const Duration(days: 1));

    final startStr = DateFormat('dd/MM/yyyy').format(start);
    final endStr = DateFormat('dd/MM/yyyy').format(endInclusive);

    if (start.year == endInclusive.year &&
        start.month == endInclusive.month &&
        start.day == endInclusive.day) {
      return startStr;
    }

    return '$startStr - $endStr';
  }

  String _displayName(Utilisateur u) {
    final prenom = u.prenom.trim();
    final nom = u.nom.trim();

    if (prenom.isEmpty) return nom;
    return '$prenom $nom';
  }

  String _sellerLabel(String sellerId) {
    if (_ownerProfile != null && sellerId == _ownerProfile!.id) {
      return 'Patron';
    }

    final user = _sellers[sellerId];
    if (user != null) {
      return _displayName(user);
    }

    return 'Inconnu';
  }

  DateTimeRange _calculateRange(StatsPeriod period) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    switch (period) {
      case StatsPeriod.today:
        return DateTimeRange(
          start: todayStart,
          end: todayStart.add(const Duration(days: 1)),
        );

      case StatsPeriod.thisWeek:
        final startOfWeek = todayStart.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
          start: startOfWeek,
          end: todayStart.add(const Duration(days: 1)),
        );

      case StatsPeriod.thisMonth:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: todayStart.add(const Duration(days: 1)),
        );

      case StatsPeriod.custom:
        if (_selectedRange == null) {
          return DateTimeRange(
            start: todayStart,
            end: todayStart.add(const Duration(days: 1)),
          );
        }

        final start = DateTime(
          _selectedRange!.start.year,
          _selectedRange!.start.month,
          _selectedRange!.start.day,
        );

        final end = DateTime(
          _selectedRange!.end.year,
          _selectedRange!.end.month,
          _selectedRange!.end.day,
        ).add(const Duration(days: 1));

        return DateTimeRange(start: start, end: end);
    }
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _loadOwnerProfile(),
        _loadSellers(),
        _loadProductNames(),
      ]);

      await _loadStats();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erreur de chargement : $e';
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage!)),
      );
    }
  }

  Future<void> _loadOwnerProfile() async {
    final data = await _supabase
        .from('utilisateurs')
        .select('id, nom, prenom, avatar, role, parent_id, email, created_at, valide')
        .eq('id', widget.ownerId)
        .maybeSingle();

    if (data != null) {
      _ownerProfile = Utilisateur.fromMap(Map<String, dynamic>.from(data));
    }
  }

  Future<void> _loadSellers() async {
    final data = await _supabase
        .from('utilisateurs')
        .select('id, nom, prenom, avatar, role, parent_id, email, created_at, valide')
        .eq('parent_id', widget.ownerId);

    final list = (data as List)
        .map((e) => Utilisateur.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((u) => u.id != null)
        .toList();

    final map = <String, Utilisateur>{};

    if (_ownerProfile?.id != null) {
      map[_ownerProfile!.id!] = _ownerProfile!;
    }

    for (final u in list) {
      map[u.id!] = u;
    }

    _sellers = map;
  }

  Future<void> _loadProductNames() async {
    final data = await _supabase
        .from('produits')
        .select('id, nom')
        .eq('owner_id', widget.ownerId);

    final map = <int, String>{};

    for (final row in (data as List)) {
      final m = Map<String, dynamic>.from(row as Map);
      final id = (m['id'] as num?)?.toInt();
      final nom = (m['nom']?.toString() ?? '').trim();

      if (id != null && nom.isNotEmpty) {
        map[id] = nom;
      }
    }

    _productNames = map;
  }

  Future<void> _loadStats() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final range = _calculateRange(_selectedPeriod);

      final salesData = await _supabase
          .from('ventes')
          .select('id, produit_id, quantite, prix, date, owner_id, seller_id, mode_paiement')
          .eq('owner_id', widget.ownerId)
          .gte('date', range.start.toIso8601String())
          .lt('date', range.end.toIso8601String())
          .order('date', ascending: false);

      final Map<String, _SellerAgg> aggBySeller = {};
      final Map<String, List<VenteDetail>> detailsBySeller = {};

      for (final row in (salesData as List)) {
        final m = Map<String, dynamic>.from(row as Map);

        final sellerIdRaw = m['seller_id']?.toString();
        final sellerId = (sellerIdRaw == null || sellerIdRaw.trim().isEmpty)
            ? widget.ownerId
            : sellerIdRaw;

        final produitId = (m['produit_id'] as num?)?.toInt();
        final qty = (m['quantite'] as num?)?.toDouble() ?? 0.0;
        final total = (m['prix'] as num?)?.toDouble() ?? 0.0;
        final dateStr = m['date']?.toString() ?? '';
        final dateVente = DateTime.tryParse(dateStr) ?? DateTime.now();

        final detail = VenteDetail(
          produitNom: produitId != null
              ? (_productNames[produitId] ?? 'Produit $produitId')
              : 'Produit inconnu',
          quantite: qty,
          dateVente: dateVente,
          prixTotal: total,
          produitIdInt: produitId?.toString(),
        );

        aggBySeller.putIfAbsent(sellerId, () => _SellerAgg()).add(detail);
        detailsBySeller.putIfAbsent(sellerId, () => []).add(detail);
      }

      final results = <CollaborateurStats>[];
      for (final entry in aggBySeller.entries) {
        results.add(
          CollaborateurStats(
            sellerId: entry.key,
            ventesCount: entry.value.ventesCount,
            totalAmount: entry.value.totalAmount,
          ),
        );
      }

      results.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

      if (!mounted) return;
      setState(() {
        _stats = results;
        _detailsBySeller = detailsBySeller;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erreur de chargement des statistiques : $e';
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage!)),
      );
    }
  }

  Future<void> _downloadCollaborateurReport(
      String collabId,
      String name,
      List<VenteDetail> details,
      DateTimeRange range,
      ) async {
    try {
      final font = pw.Font.helvetica();
      final bold = pw.Font.helveticaBold();

      final totalAmount = details.fold<double>(
        0.0,
            (sum, item) => sum + item.prixTotal,
      );
      final totalQty = details.fold<double>(
        0.0,
            (sum, item) => sum + item.quantite,
      );

      final pdf = pw.Document();
      final periodText = _formatRangeLabel(range);
      final generatedAt = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(24),
            theme: pw.ThemeData.withFont(
              base: font,
              bold: bold,
            ),
          ),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Rapport vendeur',
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Vendeur : $name'),
              pw.Text('Période : $periodText'),
              pw.Text('Généré le : $generatedAt'),
              pw.Divider(),
            ],
          ),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          build: (context) => [
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Résumé',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Quantité totale'),
                      pw.Text(_formatQty(totalQty)),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Montant total'),
                      pw.Text(formatMontant(totalAmount)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Détail des ventes',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            if (details.isEmpty)
              pw.Text('Aucun article vendu sur cette période.')
            else
              pw.Table.fromTextArray(
                headers: const ['Produit', 'Qté', 'Heure', 'Montant'],
                data: details.map((d) {
                  final localDate = d.dateVente.toLocal();
                  final time = DateFormat('HH:mm').format(localDate);

                  return [
                    d.produitNom,
                    _formatQty(d.quantite),
                    time,
                    formatMontant(d.prixTotal),
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                cellStyle: const pw.TextStyle(fontSize: 10),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.center,
                  3: pw.Alignment.centerRight,
                },
                border: pw.TableBorder.all(color: PdfColors.grey400),
              ),
          ],
        ),
      );

      final Uint8List bytes = await pdf.save();
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_');
      final fileName =
          'rapport_$safeName${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors du téléchargement du rapport : $e")),
      );
    }
  }

  void _showCollaborateurDetails(String collabId, String name) async {
    final range = _calculateRange(_selectedPeriod);
    final details = _detailsBySeller[collabId] ?? const <VenteDetail>[];

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, color: Colors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Ventes de $name",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: details.isEmpty
                  ? const Center(
                child: Text("Aucun article vendu sur cette période"),
              )
                  : ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: details.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final d = details[i];
                  final localDate = d.dateVente.toLocal();
                  final time =
                      "${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}";

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blue[50],
                          child: Text(
                            _formatQty(d.quantite),
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.produitNom,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                time,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatMontant(d.prixTotal),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text("Télécharger le rapport PDF"),
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await _downloadCollaborateurReport(
                      collabId,
                      name,
                      details,
                      range,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          _filterChip("Aujourd'hui", StatsPeriod.today),
          _filterChip("Semaine", StatsPeriod.thisWeek),
          _filterChip("Mois", StatsPeriod.thisMonth),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: ActionChip(
              label: const Text("Calendrier"),
              avatar: const Icon(Icons.calendar_month, size: 16),
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() {
                    _selectedRange = picked;
                    _selectedPeriod = StatsPeriod.custom;
                  });
                  _loadStats();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, StatsPeriod period) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: ChoiceChip(
        label: Text(label),
        selected: _selectedPeriod == period,
        onSelected: (val) {
          if (val) {
            setState(() => _selectedPeriod = period);
            _loadStats();
          }
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection() {
    final ownerName = _ownerProfile != null ? _displayName(_ownerProfile!) : 'Patron';

    final totalSales = _stats.fold<double>(0.0, (sum, s) => sum + s.totalAmount);
    final totalQty = _detailsBySeller.values
        .expand((e) => e)
        .fold<double>(0.0, (sum, d) => sum + d.quantite);

    final ownerStats = _stats.where((s) => s.sellerId == widget.ownerId).toList();
    final ownerAmount = ownerStats.fold<double>(0.0, (sum, s) => sum + s.totalAmount);
    final ownerCount = ownerStats.fold<int>(0, (sum, s) => sum + s.ventesCount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          // Première ligne : Ventes totales et Montant total
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  label: 'Ventes totales',
                  value: totalQty.toStringAsFixed(0),
                  color: Colors.blue,
                  icon: Icons.shopping_cart_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  label: 'Montant total',
                  value: formatMontant(totalSales),
                  color: Colors.green,
                  icon: Icons.payments_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Deuxième ligne : Nom du patron et Nombre de ventes du patron
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  label: 'Patron',
                  value: ownerName,
                  color: Colors.deepPurple,
                  icon: Icons.badge_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  label: 'Ventes du patron',
                  value: '$ownerCount',
                  color: Colors.orange,
                  icon: Icons.storefront_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Carte du Chiffre d'Affaires du Patron (CORRIGÉE)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Expanded permet au texte de prendre la place restante sans pousser le montant
                  Expanded(
                    child: const Text(
                      'Chiffre d’affaires personnel du patron',
                      style: TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis, // Ajoute "..." si vraiment trop long
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8), // Petit espace de sécurité
                  Text(
                    formatMontant(ownerAmount),
                    style: const TextStyle(
                      color: Colors.deepPurple,
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

  Widget _buildSellerCard(CollaborateurStats s) {
    final user = _sellers[s.sellerId];
    final isOwner = s.sellerId == widget.ownerId;
    final name = isOwner
        ? (_ownerProfile != null ? _displayName(_ownerProfile!) : 'Patron')
        : (user != null ? _displayName(user) : 'Inconnu');

    final details = _detailsBySeller[s.sellerId] ?? const <VenteDetail>[];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: () => _showCollaborateurDetails(s.sellerId, name),
        leading: CircleAvatar(
          backgroundColor: isOwner ? Colors.deepPurple.shade50 : Colors.green.shade50,
          child: Icon(
            isOwner ? Icons.badge : Icons.person,
            color: isOwner ? Colors.deepPurple : Colors.green,
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${s.ventesCount} ventes enregistrées'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "${s.totalAmount.toStringAsFixed(0)} FC",
              style: TextStyle(
                color: isOwner ? Colors.deepPurple : Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              '${details.length} lignes',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _stats.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Performances des vendeurs"),
        actions: [
          IconButton(
            onPressed: _loadStats,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          _buildSummarySection(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(child: Text(_errorMessage!))
                : !hasData
                ? const Center(child: Text("Aucune vente sur cette période"))
                : ListView.builder(
              padding: const EdgeInsets.only(top: 10),
              itemCount: _stats.length,
              itemBuilder: (context, index) {
                return _buildSellerCard(_stats[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
}