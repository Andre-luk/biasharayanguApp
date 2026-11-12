// lib/services/distribution_facture_pdf.dart
//
// 🚚 MODULE 24 — FACTURE D'UNE VENTE DISTRIBUTION.
//
// Le serveur renvoie tous les montants (`dist_facture`) : ce fichier ne fait
// que les mettre en page et déclencher le partage/l'impression système.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/partage_pdf.dart';

class DistributionFacturePdf {
  DistributionFacturePdf._();

  static Future<Uint8List> construire(FactureDistribution facture) async {
    final pw.Document document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => <pw.Widget>[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    facture.entreprise,
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  if (facture.entrepriseAdresse.isNotEmpty)
                    pw.Text(facture.entrepriseAdresse),
                  if (facture.entrepriseTelephone.isNotEmpty)
                    pw.Text('Tél. ${facture.entrepriseTelephone}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: <pw.Widget>[
                  pw.Text('FACTURE',
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text(facture.numero),
                  if (facture.date != null) pw.Text(_date(facture.date!)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: <pw.Widget>[
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text('CLIENT',
                        style: pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey700)),
                    pw.Text(facture.client,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    if (facture.clientTelephone.isNotEmpty)
                      pw.Text(facture.clientTelephone),
                    if (facture.clientAdresse.isNotEmpty)
                      pw.Text(facture.clientAdresse),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: <pw.Widget>[
                    pw.Text('COMMERCIAL',
                        style: pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey700)),
                    pw.Text(facture.commercial),
                    pw.Text('Paiement : ${facture.modePaiement}'),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: <String>[
              'Désignation',
              'Quantité',
              'Prix unitaire',
              'Total'
            ],
            data: facture.lignes
                .map((LigneVenteDistribution l) => <String>[
                      l.nom,
                      formatQuantite(l.quantite),
                      formatMontant(l.prixUnitaire),
                      formatMontant(l.total),
                    ])
                .toList(growable: false),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headerStyle:
                pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: <int, pw.Alignment>{
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 210,
              child: pw.Column(
                children: <pw.Widget>[
                  _total('Total', facture.total, gras: true),
                  _total('Paiement reçu', facture.montantPaye),
                  if (facture.credit > 0.009)
                    _total('Crédit accordé', facture.credit,
                        couleur: PdfColors.red700),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Divider(color: PdfColors.grey400),
          pw.Text(
            'Facture générée par Biashara Yangu — distribution.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _total(String libelle, double montant,
      {bool gras = false, PdfColor? couleur}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(libelle,
              style: pw.TextStyle(
                  fontSize: gras ? 11 : 9,
                  fontWeight:
                      gras ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(
            formatMontant(montant),
            style: pw.TextStyle(
              fontSize: gras ? 11 : 9,
              color: couleur,
              fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime date) {
    final DateTime d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  static Future<void> partager(FactureDistribution facture) async {
    final Uint8List octets = await construire(facture);
    await PartagePdf.partager(
      octets,
      nomFichier:
          'facture-${facture.numero.isEmpty ? 'distribution' : facture.numero}.pdf',
    );
  }

  static Future<void> imprimer(FactureDistribution facture) async {
    final Uint8List octets = await construire(facture);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => octets,
      name: 'facture-${facture.numero}',
    );
  }
}
