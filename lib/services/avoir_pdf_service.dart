// lib/services/avoir_pdf_service.dart
//
// 🧾 MODULE 32/34 — LE DOCUMENT « AVOIR » (A4).
//
// Même présentation que la facture de vente (Module 27) : en-tête de
// l'établissement, bloc client, corps, récapitulatif, pied de page
// « Solution fournie par Biashara Group ».
//
// ⚠️ Aucune valeur inventée : un champ absent (téléphone, RCCM…) est masqué.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/note_credit.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Tout ce dont le document a besoin.
class DonneesAvoir {
  DonneesAvoir({
    required this.avoir,
    required this.etablissement,
    this.lignesRetour = const <LigneRetourAvoir>[],
  });

  final NoteCredit avoir;
  final Etablissement etablissement;

  /// Marchandise rendue (facultatif : un avoir peut n'être que financier).
  final List<LigneRetourAvoir> lignesRetour;

  String get nomFichier {
    final String base =
        avoir.numero.trim().isEmpty ? 'avoir' : avoir.numero.trim();
    return 'avoir-${base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}.pdf';
  }

  /// Message prêt à envoyer au client sur WhatsApp.
  String messageWhatsApp() {
    final String nom = (avoir.clientNom ?? '').trim().isEmpty
        ? 'cher client'
        : avoir.clientNom!.trim();
    final StringBuffer sb = StringBuffer();
    sb.write('Bonjour $nom, ');
    sb.write(avoir.estRemboursement
        ? 'nous vous avons remboursé ${formatMontant(avoir.montant)} '
        : 'un avoir de ${formatMontant(avoir.montant)} ');
    sb.write('chez ${etablissement.nomAffiche} ');
    sb.write('(avoir n° ${avoir.numero} du '
        '${DateFormat('dd/MM/yyyy').format(avoir.date ?? DateTime.now())}). ');
    if ((avoir.motif ?? '').isNotEmpty) sb.write('Motif : ${avoir.motif}. ');
    sb.write('Merci de votre confiance.');
    return sb.toString();
  }
}

/// Une ligne de marchandise rendue.
class LigneRetourAvoir {
  const LigneRetourAvoir({
    required this.designation,
    required this.quantite,
    this.unite = '',
  });

  final String designation;
  final double quantite;
  final String unite;
}

/// Génère, imprime et partage le document d'avoir.
///
/// Singleton : `AvoirPdfService.instance`.
class AvoirPdfService {
  AvoirPdfService._();

  static final AvoirPdfService instance = AvoirPdfService._();

  static const PdfColor _marine = PdfColor.fromInt(0xFF1F3864);
  static const PdfColor _orange = PdfColor.fromInt(0xFFF08A4B);
  static const PdfColor _gris = PdfColor.fromInt(0xFF6B7280);

  // ---------------------------------------------------------------------------
  // DOCUMENT
  // ---------------------------------------------------------------------------

  Future<pw.Document> construire(DonneesAvoir donnees) async {
    final pw.Document document = pw.Document(
      title: 'Avoir ${donnees.avoir.numero}',
      author: donnees.etablissement.nomAffiche,
      subject: 'Avoir / note de crédit',
    );

    // 🔤 Une police Unicode (accents français, « é », « ₣ »…).
    //    Si la police ne peut pas être obtenue (hors ligne, test), on retombe
    //    sur la police intégrée : le document s'imprime quand même.
    pw.ThemeData? theme;
    try {
      final pw.Font base = await PdfGoogleFonts.robotoRegular();
      final pw.Font gras = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: base, bold: gras);
    } catch (e) {
      debugPrint('AvoirPdfService : police Unicode indisponible ($e)');
    }

    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
        footer: (pw.Context context) => _piedDePage(context, donnees),
        build: (pw.Context context) => <pw.Widget>[
          _entete(donnees),
          pw.SizedBox(height: 18),
          _blocTitre(donnees),
          pw.SizedBox(height: 14),
          _blocClient(donnees),
          pw.SizedBox(height: 14),
          if (donnees.lignesRetour.isNotEmpty) ...<pw.Widget>[
            _tableauRetour(donnees),
            pw.SizedBox(height: 14),
          ],
          _recapitulatif(donnees),
          if ((donnees.avoir.motif ?? '').isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 14),
            _blocMotif(donnees),
          ],
          if (donnees.avoir.estAnnule) ...<pw.Widget>[
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.red700, width: 1.2),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'AVOIR ANNULÉ'
                '${(donnees.avoir.motifAnnulation ?? '').isNotEmpty ? ' — ${donnees.avoir.motifAnnulation}' : ''}',
                style: pw.TextStyle(
                  color: PdfColors.red700,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return document;
  }

  // ---------------------------------------------------------------------------
  // SECTIONS
  // ---------------------------------------------------------------------------

  pw.Widget _entete(DonneesAvoir d) {
    final Etablissement e = d.etablissement;
    final List<String> coordonnees = <String>[
      if (e.lignesAdresse.isNotEmpty) e.lignesAdresse.join(', '),
      if ((e.telephone ?? '').isNotEmpty) 'Tél. ${e.telephone}',
      if ((e.email ?? '').isNotEmpty) e.email!,
      if ((e.rccm ?? '').isNotEmpty) 'RCCM : ${e.rccm}',
      if ((e.idNational ?? '').isNotEmpty) 'ID national : ${e.idNational}',
    ];

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                e.nomAffiche,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: _marine,
                ),
              ),
              pw.SizedBox(height: 3),
              ...coordonnees.map(
                (String l) => pw.Text(
                  l,
                  style: const pw.TextStyle(fontSize: 8.5, color: _gris),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(
                color: _orange,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                d.avoir.estRemboursement ? 'REMBOURSEMENT' : 'AVOIR',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _blocTitre(DonneesAvoir d) {
    final NoteCredit a = d.avoir;
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF4F6FB),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          _paire('N° AVOIR', a.numero.isEmpty ? '—' : a.numero),
          _paire('DATE', formatDate(a.date)),
          if ((a.factureNumero ?? '').isNotEmpty)
            _paire('FACTURE D\'ORIGINE', a.factureNumero!),
        ],
      ),
    );
  }

  pw.Widget _blocClient(DonneesAvoir d) {
    final NoteCredit a = d.avoir;
    final bool vide = (a.clientNom ?? '').isEmpty &&
        (a.clientTelephone ?? '').isEmpty;
    if (vide) return pw.SizedBox.shrink();

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            'CLIENT',
            style: pw.TextStyle(
              fontSize: 8,
              color: _gris,
              letterSpacing: 0.6,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            (a.clientNom ?? '').isEmpty ? '—' : a.clientNom!,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          if ((a.clientTelephone ?? '').isNotEmpty)
            pw.Text(
              a.clientTelephone!,
              style: const pw.TextStyle(fontSize: 9, color: _gris),
            ),
        ],
      ),
    );
  }

  pw.Widget _tableauRetour(DonneesAvoir d) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.6),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(6),
        1: pw.FlexColumnWidth(2),
      },
      children: <pw.TableRow>[
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _marine),
          children: <pw.Widget>[
            _celluleEntete('Article remis en stock'),
            _celluleEntete('Quantité'),
          ],
        ),
        ...d.lignesRetour.map(
          (LigneRetourAvoir l) => pw.TableRow(
            children: <pw.Widget>[
              _cellule(l.designation),
              _cellule(
                '${_nombre(l.quantite)} ${l.unite}'.trim(),
                aligne: pw.TextAlign.right,
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _recapitulatif(DonneesAvoir d) {
    final NoteCredit a = d.avoir;
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: <pw.Widget>[
        pw.Container(
          width: 220,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: _marine,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                a.estRemboursement ? 'MONTANT REMBOURSÉ' : 'MONTANT DE L\'AVOIR',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey300,
                  letterSpacing: 0.6,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                formatMontant(a.montant, devise: a.devise),
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              if ((a.modeRemboursement ?? '').isNotEmpty) ...<pw.Widget>[
                pw.SizedBox(height: 4),
                pw.Text(
                  'Rendu en : ${_libelleMode(a.modeRemboursement!)}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey300,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _blocMotif(DonneesAvoir d) {
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
            'MOTIF',
            style: pw.TextStyle(
              fontSize: 8,
              color: _gris,
              letterSpacing: 0.6,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(d.avoir.motif!, style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  pw.Widget _piedDePage(pw.Context context, DonneesAvoir d) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        pw.Divider(color: PdfColor.fromInt(0xFFE2E8F0), height: 12),
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

  pw.Widget _paire(String libelle, String valeur) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          libelle,
          style: pw.TextStyle(fontSize: 7.5, color: _gris, letterSpacing: 0.5),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          valeur,
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _celluleEntete(String texte) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        texte,
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

  String _libelleMode(String code) {
    switch (code) {
      case 'especes':
        return 'Espèces';
      case 'mobile_money':
        return 'Mobile Money';
      case 'carte':
        return 'Carte';
      default:
        return code;
    }
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

  /// Télécharge le PDF sur l'appareil. Renvoie `true` en cas de succès.
  Future<bool> telecharger(DonneesAvoir donnees) async {
    try {
      final pw.Document document = await construire(donnees);
      final Uint8List bytes = await document.save();
      await Printing.sharePdf(bytes: bytes, filename: donnees.nomFichier);
      return true;
    } catch (e) {
      debugPrint('AvoirPdfService.telecharger : $e');
      return false;
    }
  }

  /// Ouvre la boîte d'impression du système.
  Future<void> imprimer(DonneesAvoir donnees) async {
    final pw.Document document = await construire(donnees);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => document.save(),
      name: donnees.nomFichier,
    );
  }

  /// Partage le PDF (WhatsApp, e-mail, Drive…).
  Future<void> partagerPdf(DonneesAvoir donnees) async {
    final pw.Document document = await construire(donnees);
    final Uint8List bytes = await document.save();
    await Printing.sharePdf(bytes: bytes, filename: donnees.nomFichier);
  }

  /// Ouvre WhatsApp avec le message et le numéro du client.
  Future<bool> envoyerParWhatsApp(DonneesAvoir donnees) async {
    final String? numero = donnees.avoir.clientTelephone;
    final String texte = Uri.encodeComponent(donnees.messageWhatsApp());
    final String base = (numero ?? '').trim().isEmpty
        ? 'https://wa.me/?text=$texte'
        : 'https://wa.me/${normaliserTelephone(numero!)}?text=$texte';
    try {
      return await launchUrl(
        Uri.parse(base),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('AvoirPdfService.envoyerParWhatsApp : $e');
      return false;
    }
  }

  /// « +243 990 000 000 » → « 243990000000 ».
  static String normaliserTelephone(String brut) {
    final String chiffres = brut.replaceAll(RegExp(r'[^0-9+]'), '');
    String net = chiffres.replaceAll('+', '');
    if (net.startsWith('00')) net = net.substring(2);
    if (net.startsWith('0')) net = '243${net.substring(1)}';
    if (net.length == 9) net = '243$net';
    return net;
  }
}

/// Ouvre la feuille d'actions du document d'avoir.
Future<void> afficherActionsAvoir(
  BuildContext context,
  DonneesAvoir donnees, {
  bool telechargeeAutomatiquement = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.receipt_long_rounded),
            title: Text('Avoir ${donnees.avoir.numero}'),
            subtitle: Text(
              telechargeeAutomatiquement
                  ? 'PDF enregistré sur cet appareil'
                  : 'Document prêt à être partagé',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.print_rounded),
            title: const Text('Imprimer'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await AvoirPdfService.instance.imprimer(donnees);
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_rounded),
            title: const Text('Télécharger / partager le PDF'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await AvoirPdfService.instance.partagerPdf(donnees);
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
            title: const Text('Envoyer sur WhatsApp'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await AvoirPdfService.instance.envoyerParWhatsApp(donnees);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
