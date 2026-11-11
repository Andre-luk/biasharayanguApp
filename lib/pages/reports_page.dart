// ⚠️ FICHIER LEGACY — PLUS RELIÉ À LA NAVIGATION.
// L'écran Rapports officiel est `rapports_page.dart` (Module 11, Supabase) :
// route `/main/rapports`. Fichier conservé pour référence uniquement.

import 'package:flutter/material.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart'; // Ensure you have this in pubspec.yaml


class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final SupabaseService _supabaseService = SupabaseService.instance;

  String period = 'day';
  List<Map<String, dynamic>> salesSeries = [];
  List<Map<String, dynamic>> topProducts = [];
  Utilisateur? currentUser;
  bool loading = true;
  String? _userId;

  /// 🧩 MODULE 15 — identifiant des DONNÉES (boutique affichée).
  String? _ownerId;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 6));
  DateTime _endDate = DateTime.now();

  // 🔴 VARIABLE DE GRAPHIQUE SUPPRIMÉE
  // double _maxTotalRevenue = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading) {
      _loadAll();
    }
  }

  String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    try {
      return v.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => loading = true);

    final T = AppLocalizations.of(context)!;
    final userIdRaw = await SessionManager.getUserId();
    final userId = _asString(userIdRaw);

    if (userId == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    _userId = userId;
    // 🧩 MODULE 15 — les chiffres du rapport sont ceux de la BOUTIQUE
    //    affichée (`_userId` reste l'identité du profil, pour le nom).
    _ownerId = await DBHelper.instance.ownerDonneesDe(userId) ?? userId;

    try {
      currentUser = await _supabaseService.getUtilisateurData(userId);

      final now = DateTime.now();
      final todayAtStart = DateTime(now.year, now.month, now.day);

      DateTime from;

      switch (period) {
        case 'day':
          from = todayAtStart.subtract(const Duration(days: 6));
          break;
        case 'week':
          from = todayAtStart.subtract(const Duration(days: 7 * 4));
          break;
        case 'month':
          from = DateTime(todayAtStart.year, todayAtStart.month - 5, 1);
          break;
        case 'year':
          from = DateTime(todayAtStart.year - 4, 1, 1);
          break;
        default:
          from = todayAtStart.subtract(const Duration(days: 6));
      }

      _startDate = from;
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

      final data = await _supabaseService.getSalesSeries(
          ownerId: _ownerId ?? userId,
          from: _startDate,
          to: _endDate,
          period: period
      );

      // Tri pour mettre aujourd'hui en haut
      data.sort((a, b) {
        final dateA = a['period']?.toString() ?? '';
        final dateB = b['period']?.toString() ?? '';
        return dateB.compareTo(dateA);
      });

      salesSeries = data;

      topProducts = await _supabaseService.getTopProducts(
          ownerId: _ownerId ?? userId,
          from: _startDate,
          to: _endDate,
          limit: 10
      );

    } catch (e) {
      debugPrint('Erreur lors du chargement des rapports: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(T.errorLoadingData)));
      }
    }

    if (mounted) setState(() => loading = false);
  }

  // AJOUTE CETTE MÉTHODE ICI :
  void _showDailyReport(String datePeriod) {
    if (period != 'day') return;

    DateTime date;
    try {
      // Le format attendu ici est généralement YYYY-MM-DD
      date = DateTime.parse(datePeriod);
    } catch (e) {
      debugPrint('Erreur de format de date pour rapport journalier: $e');
      return;
    }

    if (_userId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DailyReportPage(
          date: date,
          userName: currentUser?.nom ?? 'Boutique',
          ownerId: _ownerId ?? _userId!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;

    final title =
    currentUser?.nom != null ? T.reportsTitleUser(currentUser!.nom!) : T.reportsTitle;
    final currentLocale = Localizations.localeOf(context).toString();
    final DateFormat detailDateFormat = DateFormat('EEEE d MMMM', currentLocale);
    final DateFormat dateRangeFormat = DateFormat('d MMM yyyy', currentLocale);

    if (loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Sélecteur de période
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
                labelText: T.reportsSelectPeriod,
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            ),
            value: period,
            items: [
              DropdownMenuItem(value: 'day', child: Text(T.reportsPeriodDay)),
              DropdownMenuItem(value: 'week', child: Text(T.reportsPeriodWeek)),
              DropdownMenuItem(value: 'month', child: Text(T.reportsPeriodMonth)),
              DropdownMenuItem(value: 'year', child: Text(T.reportsPeriodYear)),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => period = v);
                _loadAll();
              }
            },
          ),
          const SizedBox(height: 8),

          // Affichage de la plage de dates exacte
          Text(
            T.reportsDateRange(
                dateRangeFormat.format(_startDate), dateRangeFormat.format(_endDate)),
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 12),

          // 🔴 GRAPHIQUE SUPPRIMÉ - L'espace Card a été retiré ici

          // Liste des ventes par période
          Align(alignment: Alignment.centerLeft, child: Text(T.reportsDetailTitle, style: Theme.of(context).textTheme.titleLarge)),
          const Divider(),
          salesSeries.isEmpty
              ? Center(child: Text(T.reportsNoData, style: TextStyle(color: Colors.grey[600])))
              : ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: salesSeries.length,
            itemBuilder: (c, i) {
              final r = salesSeries[i];

              final rawPeriod = _asString(r['period']) ?? '';
              final DateTime? parsedDate = DateTime.tryParse(rawPeriod);

              final dateLabel = (period == 'day' && parsedDate != null)
                  ? detailDateFormat.format(parsedDate)
                  : rawPeriod.isNotEmpty
                  ? rawPeriod
                  : T.noPeriodLabel;

              final double total = (r['total'] as num?)?.toDouble() ?? 0.0;
              final int qty = (r['qty'] as num?)?.toInt() ?? 0;

              final String subtitleText = T.reportsDetailSubtitle(
                  total.toStringAsFixed(2), T.currencyUnit, qty);

              return Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(dateLabel,
                      style: TextStyle(
                          fontWeight: period == 'day'
                              ? FontWeight.bold
                              : FontWeight.normal)),
                  subtitle: Text(subtitleText),
                  trailing: (period == 'day')
                      ? const Icon(Icons.arrow_forward_ios, size: 16)
                      : null,
                  onTap: (period == 'day' && parsedDate != null)
                      ? () => _showDailyReport(rawPeriod)
                      : null,
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          // Produits les plus vendus
          Align(
              alignment: Alignment.centerLeft,
              child: Text(T.reportsTopProductsTitle,
                  style: Theme.of(context).textTheme.titleLarge)),
          const Divider(),
          topProducts.isEmpty
              ? Center(child: Text(T.reportsNoData, style: TextStyle(color: Colors.grey[600])))
              : ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: topProducts.length,
            itemBuilder: (c, i) {
              final p = topProducts[i];
              final int qtySold = (p['qty_sold'] as num?)?.toInt() ?? 0;
              final double revenue = (p['revenue'] as num?)?.toDouble() ?? 0.0;

              final String subtitleText = T.reportsTopProductSubtitle(
                  qtySold, revenue.toStringAsFixed(2), T.currencyUnit);

              return Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                    leading: CircleAvatar(child: Text('#${i + 1}')),
                    title: Text(p['produit_nom'] ?? p['nom'] ?? 'Produit Inconnu'),
                    subtitle: Text(subtitleText)),
              );
            },
          ),
        ],
      ),
    );
  }
}


// NOUVEL ÉCRAN DE RAPPORT DÉTAILLÉ PAR JOUR (DailyReportPage)

class DailyReportPage extends StatefulWidget {
  final DateTime date;
  final String userName;
  final String ownerId;

  const DailyReportPage(
      {super.key, required this.date, required this.userName, required this.ownerId});

  @override
  State<DailyReportPage> createState() => _DailyReportPageState();
}

class _DailyReportPageState extends State<DailyReportPage> {
  final SupabaseService _supabaseService = SupabaseService.instance;

  bool loading = true;
  Map<String, dynamic> reportData = {
    'total_revenue': 0.0,
    'total_quantity': 0,
    'total_profit': 0.0,
    'qty_by_category': {},
    'detailed_sales': [],
    'top_products': [],
  };

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    if (!mounted) return;
    setState(() => loading = true);

    try {
      final rawData = await _supabaseService.getDailyReportDetails(
        ownerId: widget.ownerId,
        date: widget.date,
      );

      if (rawData is Map) {
        reportData = Map<String, dynamic>.from(rawData);
      } else {
        print('Erreur: Les données Supabase ne sont pas une Map.');
        reportData = {
          'total_revenue': 0.0,
          'total_quantity': 0,
          'total_profit': 0.0,
          'qty_by_category': {},
          'detailed_sales': [],
          'top_products': [],
        };
      }
    } catch (e) {
      print('Erreur lors du chargement du rapport journalier: $e');

      if (mounted) {
        final T = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(T.errorLoadingData)));
      }

      reportData = {
        'total_revenue': 0.0,
        'total_quantity': 0,
        'total_profit': 0.0,
        'qty_by_category': {},
        'detailed_sales': [],
        'top_products': [],
      };
    }

    if (mounted) setState(() => loading = false);
  }

  void _printReport() async {
    final T = AppLocalizations.of(context)!;
    if (loading) return;

    try {
      final pdfBytes = await _generatePdf(T);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: '${T.pdfReportTitle}_${DateFormat('yyyy-MM-dd').format(widget.date)}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${T.errorPrinting} : $e')));
    }
  }

  // 🔴 FONCTION CORRIGÉE : Suppression de 'defaultPageTheme'
  Future<Uint8List> _generatePdf(AppLocalizations T) async {
    final font = await PdfGoogleFonts.robotoRegular();
    final bold = await PdfGoogleFonts.robotoBold();

    final pdf = pw.Document();

    final currentLocale = Localizations.localeOf(context).toString();
    final DateFormat pdfFullDateFormat = DateFormat('EEEE d MMMM yyyy', currentLocale);

    final dateStr = pdfFullDateFormat.format(widget.date);
    final double totalRevenue = (reportData['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final int totalQuantity = (reportData['total_quantity'] as num?)?.toInt() ?? 0;
    final double totalProfit = (reportData['total_profit'] as num?)?.toDouble() ?? 0.0;

    final Map<String, dynamic> rawQtyByCategory = (reportData['qty_by_category'] is Map)
        ? Map<String, dynamic>.from(reportData['qty_by_category'] as Map)
        .map((k, v) => MapEntry(k.toString(), v))
        : {};

    final Map<String, int> qtyByCategory =
    rawQtyByCategory.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));

    final List<Map<String, dynamic>> detailedSales = (reportData['detailed_sales'] is List)
        ? (reportData['detailed_sales'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
        : [];

    final List<Map<String, dynamic>> topProducts = (reportData['top_products'] is List)
        ? (reportData['top_products'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
        : [];

    final salesTableData = [
      [T.pdfProduct, T.pdfQuantity, T.pdfAmountSold],
      ...detailedSales.map((sale) => [
        sale['produit_nom']?.toString() ?? sale['nom']?.toString() ?? 'Produit',
        (sale['quantite'] as num?)?.toInt().toString() ?? '0',
        '${(sale['montant_vente'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'} ${T.currencyUnit}',
      ]),
    ];

    final categoryTableData = [
      [T.pdfCategory, T.pdfQuantity],
      ...qtyByCategory.entries.map((e) => [
        e.key,
        e.value.toString(),
      ]),
    ];

    final topProductsTableData = [
      [T.pdfProduct, T.pdfQuantity, T.pdfAmountSold],
      ...topProducts.map((p) => [
        p['produit_nom']?.toString() ?? p['nom']?.toString() ?? 'Produit',
        (p['qty_sold'] as num?)?.toInt().toString() ?? '0',
        '${(p['revenue'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'} ${T.currencyUnit}',
      ]),
    ];

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
              T.pdfReportTitle,
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 5),
            pw.Text('${T.pdfStore}: ${widget.userName}',
                style: const pw.TextStyle(fontSize: 16)),
            pw.Text('${T.pdfReportDate}: $dateStr',
                style: const pw.TextStyle(fontSize: 16)),
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
        build: (pw.Context context) {
          return [
            pw.Header(text: T.pdfSummaryTitle, level: 1),
            _buildPdfSummaryRow(
              T.pdfTotalRevenue,
              '${totalRevenue.toStringAsFixed(2)} ${T.currencyUnit}',
            ),
            _buildPdfSummaryRow(T.pdfTotalQty, totalQuantity.toString()),
            _buildPdfSummaryRow(
              T.pdfTotalProfit,
              '${totalProfit.toStringAsFixed(2)} ${T.currencyUnit}',
              isProfit: true,
              totalProfit: totalProfit,
            ),
            pw.SizedBox(height: 20),

            pw.Header(text: T.pdfSalesByCategory, level: 1),
            qtyByCategory.isEmpty
                ? pw.Text(
              T.reportsNoCategoryData,
              style: const pw.TextStyle(color: PdfColors.grey),
            )
                : pw.Table.fromTextArray(
              headers: categoryTableData[0],
              data: categoryTableData.sublist(1),
              border: pw.TableBorder.all(color: PdfColors.grey400),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellHeight: 20,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 20),

            pw.Header(text: T.pdfDetailedSales, level: 1),
            detailedSales.isEmpty
                ? pw.Text(
              T.reportsNoData,
              style: const pw.TextStyle(color: PdfColors.grey),
            )
                : pw.Table.fromTextArray(
              headers: salesTableData[0],
              data: salesTableData.sublist(1),
              border: pw.TableBorder.all(color: PdfColors.black),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(2),
              },
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 20),

            pw.Header(text: T.pdfTopProductsTitle, level: 1),
            topProducts.isEmpty
                ? pw.Text(
              T.reportsNoData,
              style: const pw.TextStyle(color: PdfColors.grey),
            )
                : pw.Table.fromTextArray(
              headers: topProductsTableData[0],
              data: topProductsTableData.sublist(1),
              border: pw.TableBorder.all(color: PdfColors.black),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(2),
              },
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
              },
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfSummaryRow(String label, String value,
      {bool isProfit = false, double totalProfit = 0.0}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: isProfit ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
          pw.Text(value,
              style: isProfit
                  ? pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: (totalProfit > 0
                      ? PdfColors.green700
                      : PdfColors.red700))
                  : null),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;

    final currentLocale = Localizations.localeOf(context).toString();
    final DateFormat uiFullDateFormat = DateFormat('EEEE d MMMM yyyy', currentLocale);
    final DateFormat uiShortDateFormat = DateFormat('d MMMM yyyy', currentLocale);

    if (loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(T.reportTitleForDate(uiShortDateFormat.format(widget.date))),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final String dateStr = uiFullDateFormat.format(widget.date);
    final double totalRevenue = (reportData['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final int totalQuantity = (reportData['total_quantity'] as num?)?.toInt() ?? 0;
    final double totalProfit = (reportData['total_profit'] as num?)?.toDouble() ?? 0.0;

    final Map<String, dynamic> rawQtyByCategory = (reportData['qty_by_category'] is Map)
        ? Map<String, dynamic>.from(reportData['qty_by_category'] as Map)
        .map((k, v) => MapEntry(k.toString(), v))
        : {};

    final Map<String, int> qtyByCategory =
    rawQtyByCategory.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));

    final List<Map<String, dynamic>> detailedSales = (reportData['detailed_sales'] is List)
        ? (reportData['detailed_sales'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
        : [];

    final List<Map<String, dynamic>> topProducts = (reportData['top_products'] is List)
        ? (reportData['top_products'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
        : [];

    return Scaffold(
      appBar: AppBar(
        title: Text(T.reportTitleForDate(uiShortDateFormat.format(widget.date))),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printReport,
            tooltip: T.buttonPrintReport,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final summaryCrossAxisCount = width >= 900
                ? 3
                : width >= 600
                ? 3
                : 1;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  T.reportStoreName(widget.userName),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(dateStr),
                const Divider(),

                Text(
                  T.reportSummaryTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: summaryCrossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: width < 600 ? 1.8 : 1.45,
                  children: [
                    _buildSummaryStatCard(
                      T.reportTotalRevenue,
                      '${totalRevenue.toStringAsFixed(2)} ${T.currencyUnit}',
                      Icons.paid,
                      Colors.blue,
                    ),
                    _buildSummaryStatCard(
                      T.reportTotalProfit,
                      '${totalProfit.toStringAsFixed(2)} ${T.currencyUnit}',
                      Icons.trending_up,
                      totalProfit > 0 ? Colors.green : Colors.red,
                      isProfit: true,
                    ),
                    _buildSummaryStatCard(
                      T.reportTotalQty,
                      '$totalQuantity ${T.reportUnitsLabel}',
                      Icons.inventory,
                      Colors.orange,
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                Text(
                  T.reportQtyByCategory,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Divider(),
                ..._buildCategoryListWithProgress(
                  qtyByCategory,
                  totalQuantity,
                  T.reportUnitsLabel,
                ),

                const SizedBox(height: 20),
                Text(
                  T.reportDetailedSales,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Divider(),

                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        T.reportProduct,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        T.reportQty,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        T.reportAmount,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (detailedSales.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(
                      child: Text(
                        T.reportsNoData,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  )
                else
                  ...detailedSales.map((sale) {
                    final productName = sale['produit_nom']?.toString() ??
                        sale['nom']?.toString() ??
                        'Inconnu';

                    final qty = (sale['quantite'] as num?)?.toInt() ?? 0;

                    final amount = (sale['montant_vente'] as num?)?.toDouble() ??
                        (sale['prix_total'] as num?)?.toDouble() ??
                        0.0;

                    return _buildSaleDetailRow(productName, qty, amount);
                  }).toList(),

                const SizedBox(height: 20),
                Text(
                  T.reportTopProductsTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Divider(),

                if (topProducts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(
                      child: Text(
                        T.reportsNoData,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  )
                else
                  ...topProducts.map((p) {
                    final productName = p['produit_nom']?.toString() ??
                        p['nom']?.toString() ??
                        'Inconnu';

                    final qtySold = (p['qty_sold'] as num?)?.toInt() ?? 0;

                    return _buildTopProductRow(
                      productName,
                      qtySold,
                      T.reportUnitsLabel,
                    );
                  }).toList(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryStatCard(
      String title,
      String value,
      IconData icon,
      Color color, {
        bool isProfit = false,
      }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isProfit ? color : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCategoryListWithProgress(
      Map<String, int> categories,
      int totalQty,
      String unitsLabel,
      ) {
    if (totalQty == 0 || categories.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            AppLocalizations.of(context)!.reportsNoCategoryData,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      ];
    }

    return categories.entries.map((e) {
      final percentage = totalQty > 0 ? e.value / totalQty : 0.0;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.key,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${e.value} $unitsLabel (${(percentage * 100).toStringAsFixed(1)}%)',
                  textAlign: TextAlign.right,
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: percentage,
              backgroundColor: Colors.grey[300],
              color: Theme.of(context).primaryColor,
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildSaleDetailRow(String product, int qty, double amount) {
    final T = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              product,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '$qty',
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${amount.toStringAsFixed(2)} ${T.currencyUnit}',
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductRow(String product, int qtySold, String unitsLabel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '• $product',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$qtySold $unitsLabel',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}