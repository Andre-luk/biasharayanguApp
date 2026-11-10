// lib/services/rapport_sorties_pdf_service.dart
//
// 📄 MODULE 9 — RAPPORT IMPRIMABLE DES SORTIES DE STOCK.
//
// Le commerçant doit pouvoir JUSTIFIER ce qui a quitté son stock sans être
// vendu : ce qu'il a consommé, ce qu'il a offert, ce qu'il a cassé, ce qui a
// été retourné au fournisseur. Ce document est la pièce qui le prouve.
//
// ⚠️ Aucune valeur inventée : un champ absent (adresse, téléphone, RCCM…)
//    est simplement masqué.

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/sortie_stock.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Tout ce dont le rapport a besoin.
class DonneesRapportSorties {
  const DonneesRapportSorties({
    required this.etablissement,
    required this.resume,
    this.libellePeriode,
    this.devise,
  });

  final Etablissement etablissement;
  final ResumeSortiesStock resume;

  /// « Du 01/09/2026 au 30/09/2026 » (calculée si absente).
  final String? libellePeriode;

  /// Devise d'affichage (par défaut celle de l'établissement).
  final String? devise;

  String get deviseAffichee =>
      (devise ?? etablissement.devise).trim().isEmpty
          ? 'CDF'
          : (devise ?? etablissement.devise).trim();

  String get periode {
    final String? fournie = libellePeriode;
    if (fournie != null && fournie.trim().isNotEmpty) return fournie.trim();
    final DateTime? debut = resume.debut;
    final DateTime? fin = resume.fin;
    if (debut == null && fin == null) return 'Toutes les sorties';
    final DateFormat f = DateFormat('dd/MM/yyyy');
    if (debut != null && fin != null) {
      return 'Du ${f.format(debut)} au ${f.format(fin)}';
    }
    return f.format(debut ?? fin!);
  }

  String get nomFichier {
    final String base = DateFormat('yyyyMMdd').format(DateTime.now());
    return 'sorties-stock-$base.pdf';
  }
}

/// Génère, imprime et partage le rapport des sorties de stock.
class RapportSortiesPdfService {
  RapportSortiesPdfService._();

  static final RapportSortiesPdfService instance = RapportSortiesPdfService._();

  static const PdfColor _marine = PdfColor.fromInt(0xFF1F3864);
  static const PdfColor _orange = PdfColor.fromInt(0xFFF08A4B);
  static const PdfColor _gris = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _bordure = PdfColor.fromInt(0xFFE2E8F0);

  // ---------------------------------------------------------------------------
  // DOCUMENT
  // ---------------------------------------------------------------------------

  Future<pw.Document> construire(DonneesRapportSorties donnees) async {
    final pw.Document document = pw.Document(
      title: 'Sorties de stock — ${donnees.periode}',
      author: donnees.etablissement.nomAffiche,
      subject: 'Rapport des sorties de stock non commerciales',
    );

    // 🔤 Police Unicode (accents français). Si elle est indisponible (hors
    //    ligne, test), le document s'imprime quand même avec la police
    //    intégrée.
    pw.ThemeData? theme;
    try {
      final pw.Font base = await PdfGoogleFonts.robotoRegular();
      final pw.Font gras = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: base, bold: gras);
    } catch (e) {
      debugPrint('RapportSortiesPdfService : police Unicode indisponible ($e)');
    }

    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
        footer: _piedDePage,
        build: (pw.Context context) => <pw.Widget>[
          _entete(donnees),
          pw.SizedBox(height: 14),
          _encartExplication(donnees),
          pw.SizedBox(height: 14),
          if (donnees.resume.parMotif.isNotEmpty) ...<pw.Widget>[
            _tableauMotifs(donnees),
            pw.SizedBox(height: 14),
          ],
          _tableauLignes(donnees),
          pw.SizedBox(height: 14),
          _total(donnees),
        ],
      ),
    );

    return document;
  }

  // ---------------------------------------------------------------------------
  // SECTIONS
  // ---------------------------------------------------------------------------

  pw.Widget _entete(DonneesRapportSorties d) {
    final Etablissement e = d.etablissement;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                e.nomAffiche.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: _marine,
                ),
              ),
              if ((e.adresse ?? '').trim().isNotEmpty)
                pw.Text(
                  e.adresse!.trim(),
                  style: const pw.TextStyle(fontSize: 9, color: _gris),
                ),
              if ((e.telephone ?? '').trim().isNotEmpty)
                pw.Text(
                  'Tél. ${e.telephone!.trim()}',
                  style: const pw.TextStyle(fontSize: 9, color: _gris),
                ),
              if ((e.rccm ?? '').trim().isNotEmpty)
                pw.Text(
                  'RCCM : ${e.rccm!.trim()}',
                  style: const pw.TextStyle(fontSize: 9, color: _gris),
                ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(
                color: _marine,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'SORTIES DE STOCK',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              d.periode,
              style: const pw.TextStyle(fontSize: 9, color: _gris),
            ),
            pw.Text(
              'Édité le ${DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: _gris),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _encartExplication(DonneesRapportSorties d) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFFFF7ED),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFFED7AA)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            'NATURE DU DOCUMENT',
            style: pw.TextStyle(
              fontSize: 8,
              color: _gris,
              letterSpacing: 0.6,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Articles sortis du stock SANS vente : consommation, offert, perte, '
            'casse, péremption, retour fournisseur ou usage interne. '
            'Ces mouvements ne sont PAS des encaissements : la caisse n\'est pas '
            'augmentée, le chiffre d\'affaires est inchangé.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }

  pw.Widget _tableauMotifs(DonneesRapportSorties d) {
    final List<MapEntry<String, TotalMotifSortie>> entrees =
        d.resume.motifsTries;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          'DÉTAIL PAR MOTIF',
          style: pw.TextStyle(
            fontSize: 9,
            color: _marine,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _bordure, width: 0.6),
          columnWidths: const <int, pw.TableColumnWidth>{
            0: pw.FlexColumnWidth(5),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(3),
          },
          children: <pw.TableRow>[
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _marine),
              children: <pw.Widget>[
                _celluleEntete('Motif'),
                _celluleEntete('Sorties', aligne: pw.TextAlign.right),
                _celluleEntete('Valeur', aligne: pw.TextAlign.right),
              ],
            ),
            ...entrees.map(
              (MapEntry<String, TotalMotifSortie> e) => pw.TableRow(
                children: <pw.Widget>[
                  _cellule(e.value.libelle),
                  _cellule('${e.value.nb}', aligne: pw.TextAlign.right),
                  _cellule(
                    formatMontant(e.value.valeur, devise: d.deviseAffichee),
                    aligne: pw.TextAlign.right,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _tableauLignes(DonneesRapportSorties d) {
    final List<SortieStock> lignes = d.resume.lignes;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          'DÉTAIL DES SORTIES',
          style: pw.TextStyle(
            fontSize: 9,
            color: _marine,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 6),
        if (lignes.isEmpty)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _bordure, width: 0.6),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              'Aucune sortie de stock sur la période.',
              style: const pw.TextStyle(fontSize: 9, color: _gris),
            ),
          )
        else
          pw.Table(
            border: pw.TableBorder.all(color: _bordure, width: 0.6),
            columnWidths: const <int, pw.TableColumnWidth>{
              0: pw.FlexColumnWidth(2.2),
              1: pw.FlexColumnWidth(4.4),
              2: pw.FlexColumnWidth(2.2),
              3: pw.FlexColumnWidth(3.2),
              4: pw.FlexColumnWidth(2.4),
            },
            children: <pw.TableRow>[
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _orange),
                children: <pw.Widget>[
                  _celluleEntete('Date'),
                  _celluleEntete('Article'),
                  _celluleEntete('Quantité', aligne: pw.TextAlign.right),
                  _celluleEntete('Motif'),
                  _celluleEntete('Valeur', aligne: pw.TextAlign.right),
                ],
              ),
              ...lignes.map(
                (SortieStock s) => pw.TableRow(
                  children: <pw.Widget>[
                    _cellule(
                      s.date == null
                          ? '—'
                          : DateFormat('dd/MM/yy').format(s.date!),
                    ),
                    _cellule(
                      (s.note ?? '').trim().isEmpty
                          ? s.produit
                          : '${s.produit}\n${s.note!.trim()}',
                    ),
                    _cellule(
                      '${_nombre(s.quantite)} ${s.unite}',
                      aligne: pw.TextAlign.right,
                    ),
                    _cellule(s.libelleMotif),
                    _cellule(
                      formatMontant(s.valeurTotale, devise: d.deviseAffichee),
                      aligne: pw.TextAlign.right,
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _total(DonneesRapportSorties d) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: <pw.Widget>[
        pw.Container(
          width: 240,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: _marine,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                '${d.resume.nb} SORTIE(S) — VALEUR TOTALE',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey300,
                  letterSpacing: 0.6,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                formatMontant(d.resume.valeur, devise: d.deviseAffichee),
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Aucun montant encaissé : sortie sans vente.',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey300,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _piedDePage(pw.Context context) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        pw.Divider(color: _bordure, height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              'Solution fournie par Biashara Group',
              style: pw.TextStyle(
                fontSize: 8,
                color: _marine,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'Page ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _gris),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PETITS OUTILS
  // ---------------------------------------------------------------------------

  pw.Widget _celluleEntete(String texte, {pw.TextAlign aligne = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        texte,
        textAlign: aligne,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _cellule(String texte, {pw.TextAlign aligne = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Text(
        texte,
        textAlign: aligne,
        style: const pw.TextStyle(fontSize: 9),
      ),
    );
  }

  static String _nombre(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  /// Ouvre la boîte d'impression du système.
  Future<void> imprimer(DonneesRapportSorties donnees) async {
    final pw.Document document = await construire(donnees);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => document.save(),
      name: donnees.nomFichier,
    );
  }

  /// Partage le PDF (WhatsApp, e-mail, Drive…).
  Future<void> partager(DonneesRapportSorties donnees) async {
    final pw.Document document = await construire(donnees);
    final Uint8List bytes = await document.save();
    await Printing.sharePdf(bytes: bytes, filename: donnees.nomFichier);
  }

  /// Télécharge le PDF sur l'appareil. Renvoie `true` en cas de succès.
  Future<bool> telecharger(DonneesRapportSorties donnees) async {
    try {
      final pw.Document document = await construire(donnees);
      final Uint8List bytes = await document.save();
      await Printing.sharePdf(bytes: bytes, filename: donnees.nomFichier);
      return true;
    } catch (e) {
      debugPrint('RapportSortiesPdfService.telecharger : $e');
      return false;
    }
  }
}
