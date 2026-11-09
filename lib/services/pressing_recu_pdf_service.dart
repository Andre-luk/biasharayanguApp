// lib/services/pressing_recu_pdf_service.dart
//
// 🧺 MODULE 35 — LE REÇU DE DÉPÔT DU PRESSING (A4 + QR code).
//
// POURQUOI CE DOCUMENT EST DIFFÉRENT D'UNE FACTURE
//   Une facture prouve une VENTE. Un reçu de dépôt prouve qu'on a CONFIÉ des
//   vêtements à un pressing : il doit permettre de les récupérer. D'où :
//     • le détail de CHAQUE vêtement (état au dépôt, défauts constatés) ;
//     • la date de récupération prévue ;
//     • un QR code qui retrouve le dossier en un scan ;
//     • la mention de ce qui reste à payer, distincte du total.
//
// ⚠️ Le QR ne contient JAMAIS un identifiant de la base : uniquement le jeton
//    aléatoire fourni par le serveur (64 caractères), qui ne révèle rien.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/pressing.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Tout ce dont le reçu a besoin.
class DonneesRecuPressing {
  DonneesRecuPressing({
    required this.commande,
    required this.etablissement,
    this.soldeObligatoire = true,
  });

  final PressingCommande commande;
  final Etablissement etablissement;

  /// Politique du pressing : le solde est-il exigé avant la remise ?
  final bool soldeObligatoire;

  String get nomFichier {
    final String base = commande.numero.trim().isEmpty
        ? 'depot'
        : commande.numero.trim();
    return 'recu-${base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}.pdf';
  }

  /// Message prêt à envoyer au client sur WhatsApp.
  String messageWhatsApp() {
    final String nom = (commande.clientNom ?? '').trim().isEmpty
        ? 'Bonjour'
        : 'Bonjour ${commande.clientNom!.trim()}';
    final StringBuffer sb = StringBuffer();
    sb.write('$nom, ');
    sb.write('vos ${commande.nbLignes} vêtement(s) ont été déposés chez '
        '${etablissement.nomAffiche}. ');
    sb.write('Commande n° ${commande.numero}. ');
    final DateTime? prevue = commande.datePrevue;
    if (prevue != null) {
      sb.write('Retrait prévu le ${DateFormat('dd/MM/yyyy').format(prevue)}. ');
    }
    sb.write('Total ${formatMontant(commande.total, devise: commande.devise)}, '
        'déjà payé ${formatMontant(commande.montantPaye, devise: commande.devise)}, '
        'reste ${formatMontant(commande.solde, devise: commande.devise)}. ');
    sb.write('Merci de votre confiance.');
    return sb.toString();
  }
}

/// Génère, imprime et partage le reçu de dépôt.
///
/// Singleton : `PressingRecuPdfService.instance`.
class PressingRecuPdfService {
  PressingRecuPdfService._();

  static final PressingRecuPdfService instance = PressingRecuPdfService._();

  static const PdfColor _marine = PdfColor.fromInt(0xFF1F3864);
  static const PdfColor _orange = PdfColor.fromInt(0xFFF08A4B);
  static const PdfColor _gris = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _bordure = PdfColor.fromInt(0xFFE2E8F0);

  // ---------------------------------------------------------------------------
  // DOCUMENT
  // ---------------------------------------------------------------------------

  Future<pw.Document> construire(DonneesRecuPressing donnees) async {
    final pw.Document document = pw.Document(
      title: 'Reçu ${donnees.commande.numero}',
      author: donnees.etablissement.nomAffiche,
      subject: 'Reçu de dépôt pressing',
    );

    // Police Unicode (accents) avec repli silencieux hors ligne.
    pw.ThemeData? theme;
    try {
      final pw.Font base = await PdfGoogleFonts.robotoRegular();
      final pw.Font gras = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: base, bold: gras);
    } catch (e) {
      debugPrint('PressingRecuPdfService : police Unicode indisponible ($e)');
    }

    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 38),
        footer: (pw.Context context) => _piedDePage(context, donnees),
        build: (pw.Context context) => <pw.Widget>[
          _entete(donnees),
          pw.SizedBox(height: 16),
          _blocIdentite(donnees),
          pw.SizedBox(height: 12),
          _blocClient(donnees),
          pw.SizedBox(height: 14),
          _tableauVetements(donnees),
          pw.SizedBox(height: 12),
          _blocTotaux(donnees),
          pw.SizedBox(height: 14),
          _blocQr(donnees),
          pw.SizedBox(height: 12),
          _conditions(donnees),
        ],
      ),
    );

    return document;
  }

  // ---------------------------------------------------------------------------
  // SECTIONS
  // ---------------------------------------------------------------------------

  pw.Widget _entete(DonneesRecuPressing d) {
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
        pw.SizedBox(width: 14),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
            color: _orange,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(
            'REÇU DE DÉPÔT',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.7,
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _blocIdentite(DonneesRecuPressing d) {
    final PressingCommande c = d.commande;
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF4F6FB),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _bordure),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          _paire('N° DE COMMANDE', c.numero.isEmpty ? '—' : c.numero),
          _paire('DÉPOSÉ LE', formatDate(c.dateDepot)),
          _paire('RETRAIT PRÉVU', formatDate(c.datePrevue)),
          if (c.urgence) _paire('SERVICE', 'EXPRESS'),
        ],
      ),
    );
  }

  pw.Widget _blocClient(DonneesRecuPressing d) {
    final PressingCommande c = d.commande;
    if ((c.clientNom ?? '').trim().isEmpty &&
        (c.clientTelephone ?? '').trim().isEmpty) {
      return pw.SizedBox.shrink();
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _bordure),
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
            (c.clientNom ?? '').trim().isEmpty ? '—' : c.clientNom!.trim(),
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          if ((c.clientTelephone ?? '').trim().isNotEmpty)
            pw.Text(
              c.clientTelephone!.trim(),
              style: const pw.TextStyle(fontSize: 9, color: _gris),
            ),
        ],
      ),
    );
  }

  pw.Widget _tableauVetements(DonneesRecuPressing d) {
    final List<PressingLigne> lignes = d.commande.lignes;

    return pw.Table(
      border: pw.TableBorder.all(color: _bordure, width: 0.6),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(22),
        1: pw.FlexColumnWidth(5),
        2: pw.FlexColumnWidth(3),
        3: pw.FlexColumnWidth(2),
        4: pw.FlexColumnWidth(2),
      },
      children: <pw.TableRow>[
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _marine),
          children: <pw.Widget>[
            _enteteCellule('#'),
            _enteteCellule('Vêtement'),
            _enteteCellule('Prestation'),
            _enteteCellule('Qté'),
            _enteteCellule('Prix', aligne: pw.TextAlign.right),
          ],
        ),
        ...lignes.map((PressingLigne l) {
          final List<String> details = <String>[
            if (l.details.isNotEmpty) l.details,
            if ((l.etatDepot ?? '').trim().isNotEmpty)
              'état : ${l.etatDepot!.trim()}',
            if ((l.defauts ?? '').trim().isNotEmpty)
              'défaut signalé : ${l.defauts!.trim()}',
          ];

          return pw.TableRow(
            children: <pw.Widget>[
              _cellule('${l.position}'),
              _cellule(
                (l.designation ?? l.categorieNom ?? 'Vêtement').trim(),
                sousTitre: details.isEmpty ? null : details.join(' · '),
              ),
              _cellule((l.prestationNom ?? '—').trim()),
              _cellule(_nombre(l.quantite), aligne: pw.TextAlign.center),
              _cellule(
                formatMontant(l.prix, devise: d.commande.devise),
                aligne: pw.TextAlign.right,
              ),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _blocTotaux(DonneesRecuPressing d) {
    final PressingCommande c = d.commande;
    final List<pw.Widget> lignes = <pw.Widget>[
      _ligneTotal('Total', formatMontant(c.total, devise: c.devise)),
      if (c.remise > 0)
        _ligneTotal(
          'Remise',
          '- ${formatMontant(c.remise, devise: c.devise)}',
        ),
      if (c.supplement > 0)
        _ligneTotal(
          'Supplément',
          '+ ${formatMontant(c.supplement, devise: c.devise)}',
        ),
      _ligneTotal(
        'Déjà payé',
        formatMontant(c.montantPaye, devise: c.devise),
      ),
    ];

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Container(
          width: 250,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _bordure),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              ...lignes,
              pw.Divider(color: _bordure, height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: <pw.Widget>[
                  pw.Text(
                    c.solde > 0 ? 'RESTE À PAYER' : 'SOLDÉ',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: c.solde > 0 ? PdfColors.red700 : _marine,
                    ),
                  ),
                  pw.Text(
                    formatMontant(c.solde, devise: c.devise),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: c.solde > 0 ? PdfColors.red700 : _marine,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _blocQr(DonneesRecuPressing d) {
    final String token = (d.commande.qrToken ?? '').trim();

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF9FAFB),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _bordure),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          if (token.isEmpty)
            pw.SizedBox.shrink()
          else
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: token,
              width: 78,
              height: 78,
              drawText: false,
            ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  'PRÉSENTEZ CE REÇU AU RETRAIT',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _marine,
                    letterSpacing: 0.5,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Le code QR ci-contre permet à l\'agent de retrouver votre '
                  'dossier et de vérifier les vêtements prêts. Il ne remplace '
                  'pas le contrôle de la commande : le pressing vérifie '
                  'toujours les vêtements avant de les remettre.',
                  style: const pw.TextStyle(fontSize: 8, color: _gris),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Commande ${d.commande.numero}'
                  '${d.commande.qrVersion > 1 ? ' · QR réédité (v${d.commande.qrVersion})' : ''}',
                  style: const pw.TextStyle(fontSize: 8, color: _gris),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _conditions(DonneesRecuPressing d) {
    return pw.Container(
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
            'CONDITIONS DE RETRAIT',
            style: pw.TextStyle(
              fontSize: 8,
              color: _gris,
              letterSpacing: 0.6,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            d.soldeObligatoire
                ? 'Le solde doit être réglé avant la remise des vêtements.'
                : 'La remise est possible même si un solde reste dû, selon les '
                    'règles du pressing.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Les défauts constatés au dépôt sont mentionnés ci-dessus : ils ne '
            'peuvent pas être reprochés au pressing après le traitement.',
            style: const pw.TextStyle(fontSize: 8, color: _gris),
          ),
        ],
      ),
    );
  }

  pw.Widget _piedDePage(pw.Context context, DonneesRecuPressing d) {
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
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _enteteCellule(String texte,
      {pw.TextAlign aligne = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
    String? sousTitre,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Column(
        crossAxisAlignment: aligne == pw.TextAlign.right
            ? pw.CrossAxisAlignment.end
            : pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            texte.isEmpty ? '—' : texte,
            textAlign: aligne,
            style: const pw.TextStyle(fontSize: 8.5),
          ),
          if (sousTitre != null)
            pw.Text(
              sousTitre,
              style: const pw.TextStyle(fontSize: 7, color: _gris),
            ),
        ],
      ),
    );
  }

  pw.Widget _ligneTotal(String libelle, String valeur) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            libelle,
            style: const pw.TextStyle(fontSize: 9, color: _gris),
          ),
          pw.Text(valeur, style: const pw.TextStyle(fontSize: 9)),
        ],
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

  /// Télécharge / partage le PDF. Renvoie `true` en cas de succès.
  Future<bool> telecharger(DonneesRecuPressing donnees) async {
    try {
      final pw.Document document = await construire(donnees);
      final Uint8List bytes = await document.save();
      await Printing.sharePdf(bytes: bytes, filename: donnees.nomFichier);
      return true;
    } catch (e) {
      debugPrint('PressingRecuPdfService.telecharger : $e');
      return false;
    }
  }

  Future<void> imprimer(DonneesRecuPressing donnees) async {
    final pw.Document document = await construire(donnees);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => document.save(),
      name: donnees.nomFichier,
    );
  }

  Future<void> partagerPdf(DonneesRecuPressing donnees) async {
    final pw.Document document = await construire(donnees);
    final Uint8List bytes = await document.save();
    await Printing.sharePdf(bytes: bytes, filename: donnees.nomFichier);
  }

  /// Ouvre WhatsApp avec le message et le numéro du client.
  Future<bool> envoyerParWhatsApp(DonneesRecuPressing donnees) async {
    final String? numero = donnees.commande.clientTelephone;
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
      debugPrint('PressingRecuPdfService.envoyerParWhatsApp : $e');
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

/// Ouvre la feuille d'actions du reçu.
Future<void> afficherActionsRecu(
  BuildContext context,
  DonneesRecuPressing donnees, {
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
            title: Text('Reçu ${donnees.commande.numero}'),
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
              await PressingRecuPdfService.instance.imprimer(donnees);
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_rounded),
            title: const Text('Télécharger / partager le PDF'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await PressingRecuPdfService.instance.partagerPdf(donnees);
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
            title: const Text('Envoyer sur WhatsApp'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await PressingRecuPdfService.instance.envoyerParWhatsApp(donnees);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
