import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class InvoiceItem {
  final String name;
  final double quantity;
  final String unit;
  final double pricePerUnit;
  final double total;

  InvoiceItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.pricePerUnit,
    required this.total,
  });
}

class InvoiceService {
  final AppLocalizations T;
  final String userName;
  final String paymentMode;
  final double totalAmount;
  final List<InvoiceItem> items;
  final DateTime saleDate;
  final int invoiceId;

  InvoiceService({
    required this.T,
    required this.userName,
    required this.paymentMode,
    required this.totalAmount,
    required this.items,
    required this.saleDate,
    required this.invoiceId,
  });

  Future<void> generateAndPrintInvoice({bool isTicket = false}) async {
    final pdfBytes = await _generatePdf(isTicket: isTicket);

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: '${T.invoiceName}_#$invoiceId',
      format: isTicket ? PdfPageFormat.roll57 : PdfPageFormat.a4,
    );
  }

  Future<Uint8List> _generatePdf({bool isTicket = false}) async {
    final pdf = pw.Document();

    // 1. Charger les polices
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontItalic = await PdfGoogleFonts.robotoItalic();

    final theme = pw.ThemeData.withFont(
      base: font,
      bold: fontBold,
      italic: fontItalic,
    );

    // --- CRUCIAL : Pré-formatage des dates sur le thread principal ---
    final currentLocale = T.localeName;
    final DateFormat fullFormatter = DateFormat('EEEE d MMMM yyyy HH:mm', currentLocale);
    final DateFormat shortFormatter = DateFormat('yyyy-MM-dd', currentLocale);

    final String fullDateStr = fullFormatter.format(saleDate);
    final String shortDateStr = shortFormatter.format(saleDate);
    // ----------------------------------------------------------------

    final pageFormat = isTicket ? PdfPageFormat.roll57 : PdfPageFormat.a4;

    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: pageFormat,
        margin: isTicket ? const pw.EdgeInsets.all(5) : const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          // On passe les Strings pré-formatées
          return isTicket
              ? _buildTicketContent(fullDateStr, shortDateStr)
              : _buildA4Content(fullDateStr, shortDateStr);
        },
      ),
    );

    // On utilise compute pour la sauvegarde (opération CPU intensive)
    return await compute(_savePdfInBackground, pdf);
  }

  /// Fonction statique pour être isolée proprement
  static Future<Uint8List> _savePdfInBackground(pw.Document doc) async {
    return await doc.save();
  }

  pw.Widget _buildTicketContent(String fullDateStr, String shortDateStr) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Text(userName.toUpperCase(),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        ),
        pw.Center(
          child: pw.Text("TICKET #$invoiceId", style: pw.TextStyle(fontSize: 10)),
        ),
        pw.Divider(thickness: 0.5),
        pw.Text('${T.pdfDate}: $fullDateStr', style: pw.TextStyle(fontSize: 8)),
        pw.Text('${T.pdfPaymentMode}: ${T.paymentMode(paymentMode)}',
            style: pw.TextStyle(fontSize: 8)),
        pw.Divider(thickness: 0.5),
        ...items.map((item) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                      child: pw.Text(item.name,
                          style: pw.TextStyle(
                              fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  pw.Text("${formatMontant(item.total)}",
                      style: pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Text(
                  "${item.quantity.toStringAsFixed(0)} ${item.unit} x ${item.pricePerUnit.toStringAsFixed(0)}",
                  style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            ],
          ),
        )),
        pw.Divider(thickness: 1),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(T.invoiceTotal.toUpperCase(),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.Text("${formatMontant(totalAmount)}",
                style:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Text(T.invoiceThankYou(shortDateStr),
              style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
        ),
      ],
    );
  }

  pw.Widget _buildA4Content(String fullDateStr, String shortDateStr) {
    final PdfColor primaryColor = PdfColor.fromInt(0xFF0D47A1);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          decoration: pw.BoxDecoration(color: primaryColor),
          padding: const pw.EdgeInsets.all(10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(T.invoiceTitle.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white)),
              pw.Text('#$invoiceId',
                  style: pw.TextStyle(fontSize: 18, color: PdfColors.white)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(T.pdfStoreInfo,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(userName),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('${T.pdfDate}: $fullDateStr'),
                pw.Text('${T.pdfPaymentMode}: ${T.paymentMode(paymentMode)}'),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headers: [T.pdfItem, T.pdfQty, T.pdfUnit, T.pdfPrice, T.pdfTotal],
          data: items
              .map((i) => [
            i.name,
            i.quantity.toStringAsFixed(0),
            i.unit,
            '${formatMontant(i.pricePerUnit)}',
            '${formatMontant(i.total)}'
          ])
              .toList(),
          border: pw.TableBorder.all(color: PdfColors.grey400),
          headerStyle:
          pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: pw.BoxDecoration(color: primaryColor),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
              '${T.invoiceTotal}: ${totalAmount.toStringAsFixed(2)} ${T.currencyUnit}',
              style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor)),
        ),
        pw.Spacer(),
        pw.Center(
            child: pw.Text(T.invoiceThankYou(shortDateStr),
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey))),
        pw.Center(
            child: pw.Text(T.invoiceTraceability(invoiceId),
                style: pw.TextStyle(fontSize: 8, color: PdfColors.red))),
      ],
    );
  }
}