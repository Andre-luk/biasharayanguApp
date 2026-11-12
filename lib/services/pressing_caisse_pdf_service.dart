// lib/services/pressing_caisse_pdf_service.dart
//
// 🧺 MODULE 35 — RAPPORT DE CAISSE DU PRESSING (A4).
//
// C'est la feuille que le patron garde et que le comptable demande : combien
// est entré, par quel moyen, ce qui a été annulé, ce qui reste dû, et le détail
// de chaque encaissement (n° de dossier, client, heure, agent).
//
// ⚠️ Aucune valeur inventée : un total absent s'affiche à zéro, une liste vide
//    le dit explicitement.

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/pressing_caisse.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/partage_pdf.dart';

class DonneesCaissePressing {
  const DonneesCaissePressing({
    required this.etablissement,
    required this.caisse,
    this.devise = 'CDF',
  });

  final Etablissement etablissement;
  final CaisseJourPressing caisse;
  final String devise;

  String get nomFichier {
    final DateTime jour = caisse.date ?? DateTime.now();
    return 'caisse-pressing-${DateFormat('yyyyMMdd').format(jour)}.pdf';
  }

  String get periode {
    final DateTime? jour = caisse.date;
    if (jour == null) return "Aujourd'hui";
    // `formatDate` est déjà utilisé partout dans l'application : il évite de
    // dépendre de l'initialisation des locales d'intl.
    return 'Journée du ${formatDate(jour)}';
  }
}

class PressingCaissePdfService {
  PressingCaissePdfService._();

  static final PressingCaissePdfService instance = PressingCaissePdfService._();

  static const PdfColor _marine = PdfColor.fromInt(0xFF1F3864);
  static const PdfColor _orange = PdfColor.fromInt(0xFFF08A4B);
  static const PdfColor _gris = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _bordure = PdfColor.fromInt(0xFFE2E8F0);

  Future<pw.Document> construire(DonneesCaissePressing d) async {
    final pw.Document document = pw.Document(
      title: 'Caisse du pressing — ${d.periode}',
      author: d.etablissement.nomAffiche,
      subject: 'Rapport de caisse',
    );

    pw.ThemeData? theme;
    try {
      final pw.Font base = await PdfGoogleFonts.robotoRegular();
      final pw.Font gras = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: base, bold: gras);
    } catch (e) {
      debugPrint('PressingCaissePdfService : police Unicode indisponible ($e)');
    }

    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
        footer: _piedDePage,
        build: (pw.Context context) => <pw.Widget>[
          _entete(d),
          pw.SizedBox(height: 14),
          _chiffres(d),
          pw.SizedBox(height: 14),
          if (d.caisse.modesTries.isNotEmpty) ...<pw.Widget>[
            _tableauModes(d),
            pw.SizedBox(height: 14),
          ],
          _tableauPaiements(d),
        ],
      ),
    );

    return document;
  }

  pw.Widget _entete(DonneesCaissePressing d) {
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
                  fontSize: 15,
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
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(
                color: _marine,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'CAISSE DU PRESSING',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(d.periode,
                style: const pw.TextStyle(fontSize: 9, color: _gris)),
          ],
        ),
      ],
    );
  }

  pw.Widget _chiffres(DonneesCaissePressing d) {
    final CaisseJourPressing c = d.caisse;
    return pw.Column(
      children: <pw.Widget>[
        pw.Row(
          children: <pw.Widget>[
            pw.Expanded(
              child: _bloc(
                'ENCAISSÉ',
                formatMontant(c.encaisse, devise: d.devise),
                fond: _marine,
                clair: true,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _bloc(
                'ANNULÉ (${c.nbAnnules})',
                formatMontant(c.annule, devise: d.devise),
                fond: PdfColor.fromInt(0xFFFDECEC),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: <pw.Widget>[
            pw.Expanded(
              child: _bloc('DÉPÔTS', '${c.depots}'),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _bloc(
                'FACTURÉ',
                formatMontant(c.montantFacture, devise: d.devise),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _bloc('REMISES', '${c.remises}'),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _bloc(
                'RESTE DÛ',
                formatMontant(c.resteDu, devise: d.devise),
                alerte: c.resteDu > 0,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _bloc(
    String libelle,
    String valeur, {
    PdfColor? fond,
    bool clair = false,
    bool alerte = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: fond ?? PdfColor.fromInt(0xFFF8FAFC),
        borderRadius: pw.BorderRadius.circular(5),
        border:
            fond == null ? pw.Border.all(color: _bordure, width: 0.6) : null,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            libelle,
            style: pw.TextStyle(
              fontSize: 7.5,
              letterSpacing: 0.5,
              color: clair ? PdfColors.grey300 : _gris,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            valeur,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: clair
                  ? PdfColors.white
                  : (alerte ? PdfColor.fromInt(0xFFB91C1C) : _marine),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _tableauModes(DonneesCaissePressing d) {
    return pw.Table(
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
            _celluleEntete('Moyen de paiement'),
            _celluleEntete('Nombre', aligne: pw.TextAlign.right),
            _celluleEntete('Montant', aligne: pw.TextAlign.right),
          ],
        ),
        ...d.caisse.modesTries.map(
          (TotalModeJour m) => pw.TableRow(
            children: <pw.Widget>[
              _cellule(m.libelle),
              _cellule('${m.nb}', aligne: pw.TextAlign.right),
              _cellule(
                formatMontant(m.montant, devise: d.devise),
                aligne: pw.TextAlign.right,
              ),
            ],
          ),
        ),
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
          children: <pw.Widget>[
            _cellule('TOTAL ENCAISSÉ', gras: true),
            _cellule('${d.caisse.nbPaiements}',
                aligne: pw.TextAlign.right, gras: true),
            _cellule(
              formatMontant(d.caisse.encaisse, devise: d.devise),
              aligne: pw.TextAlign.right,
              gras: true,
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _tableauPaiements(DonneesCaissePressing d) {
    final List<PaiementJourPressing> lignes = d.caisse.paiements;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          'DÉTAIL DES ENCAISSEMENTS',
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
              'Aucun encaissement ce jour.',
              style: const pw.TextStyle(fontSize: 9, color: _gris),
            ),
          )
        else
          pw.Table(
            border: pw.TableBorder.all(color: _bordure, width: 0.6),
            columnWidths: const <int, pw.TableColumnWidth>{
              0: pw.FlexColumnWidth(1.8),
              1: pw.FlexColumnWidth(2.6),
              2: pw.FlexColumnWidth(3.4),
              3: pw.FlexColumnWidth(2.2),
              4: pw.FlexColumnWidth(2.4),
              5: pw.FlexColumnWidth(2.6),
            },
            children: <pw.TableRow>[
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _orange),
                children: <pw.Widget>[
                  _celluleEntete('Heure'),
                  _celluleEntete('Dossier'),
                  _celluleEntete('Client'),
                  _celluleEntete('Mode'),
                  _celluleEntete('Montant', aligne: pw.TextAlign.right),
                  _celluleEntete('Agent'),
                ],
              ),
              ...lignes.map(
                (PaiementJourPressing p) => pw.TableRow(
                  children: <pw.Widget>[
                    _cellule(
                      p.encaisseLe == null
                          ? '—'
                          : DateFormat('HH:mm').format(p.encaisseLe!.toLocal()),
                    ),
                    _cellule(p.annule ? '${p.numero} (annulé)' : p.numero),
                    _cellule(p.client),
                    _cellule(p.libelleMode),
                    _cellule(
                      formatMontant(p.montant, devise: d.devise),
                      aligne: pw.TextAlign.right,
                    ),
                    _cellule(p.agent),
                  ],
                ),
              ),
            ],
          ),
        if (d.caisse.nbAnnules > 0) ...<pw.Widget>[
          pw.SizedBox(height: 8),
          pw.Text(
            'Les encaissements annulés restent dans l\'historique avec leur '
            'motif : ils ne sont jamais supprimés.',
            style: const pw.TextStyle(fontSize: 8, color: _gris),
          ),
        ],
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

  pw.Widget _celluleEntete(String texte,
      {pw.TextAlign aligne = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      child: pw.Text(
        texte,
        textAlign: aligne,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _cellule(
    String texte, {
    pw.TextAlign aligne = pw.TextAlign.left,
    bool gras = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      child: pw.Text(
        texte,
        textAlign: aligne,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// Ouvre la boîte d'impression du système.
  Future<void> imprimer(DonneesCaissePressing donnees) async {
    final pw.Document document = await construire(donnees);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => document.save(),
      name: donnees.nomFichier,
    );
  }

  /// Partage le PDF (WhatsApp, e-mail, Drive…).
  Future<void> partager(DonneesCaissePressing donnees) async {
    final pw.Document document = await construire(donnees);
    await PartagePdf.partager(
      await document.save(),
      nomFichier: donnees.nomFichier,
    );
  }
}
