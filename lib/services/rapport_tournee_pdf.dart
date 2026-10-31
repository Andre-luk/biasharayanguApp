// lib/services/rapport_tournee_pdf.dart
//
// 🖨️ LE RAPPORT DE TOURNÉE, SUR PAPIER.
//
// Une feuille A4 qui répond aux questions du patron sans qu'il ait à faire de
// calculs :
//   • ce qui a été CONFIÉ à l'agent, produit par produit ;
//   • ce qu'il a VENDU, RENDU, OFFERT, CASSÉ ;
//   • ce qui MANQUE, et combien cela vaut ;
//   • ce qui a été PRODUIT ce jour-là (entré en stock) ;
//   • les REÇUS (numéro, heure, montant) ;
//   • deux lignes de signature : l'agent et le responsable.
//
// ⚠️ Aucune donnée n'est calculée ici : le PDF met en page ce que
//    `rpc_rapport_tournee_detail` a relu dans les tables de faits.

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:biashara_yangu/models/distribution_terrain.dart';

class RapportTourneePdf {
  RapportTourneePdf._();

  /// Ouvre l'aperçu d'impression du système (A4).
  static Future<void> imprimer(RapportTournee rapport) async {
    final Uint8List bytes = await construire(rapport);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name:
          'Tournee_${rapport.reference.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}',
      format: PdfPageFormat.a4,
    );
  }

  /// Construit le PDF en mémoire (testable, partageable).
  static Future<Uint8List> construire(RapportTournee rapport) async {
    final pw.Document doc = pw.Document();

    // Les polices Google sont jolies mais exigent le réseau la première fois.
    // En cas d'échec (hors ligne, terrain), on retombe sur les polices PDF
    // standard, qui gèrent correctement les accents français.
    pw.Font base = pw.Font.helvetica();
    pw.Font gras = pw.Font.helveticaBold();
    try {
      base = await PdfGoogleFonts.robotoRegular();
      gras = await PdfGoogleFonts.robotoBold();
    } catch (_) {
      // On garde Helvetica : mieux vaut imprimer que planter.
    }

    final pw.ThemeData theme = pw.ThemeData.withFont(base: base, bold: gras);

    final DateFormat jour = DateFormat('dd/MM/yyyy');
    final DateFormat heure = DateFormat('HH:mm');

    final String dateTexte =
        rapport.dateTournee == null ? '—' : jour.format(rapport.dateTournee!);

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 28),
        header: (pw.Context ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                rapport.entreprise.isEmpty
                    ? 'Biashara Yangu'
                    : rapport.entreprise,
                style: pw.TextStyle(font: gras, fontSize: 13),
              ),
              pw.Text(
                'Rapport de tournée',
                style: pw.TextStyle(font: gras, fontSize: 13),
              ),
            ],
          ),
        ),
        footer: (pw.Context ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                'Édité le ${jour.format(DateTime.now())} à '
                '${heure.format(DateTime.now())}',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
              pw.Text(
                'Page ${ctx.pageNumber}/${ctx.pagesCount}',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
        build: (pw.Context ctx) => <pw.Widget>[
          _entete(rapport, dateTexte, gras),
          pw.SizedBox(height: 10),
          _blocTotaux(rapport, gras),
          pw.SizedBox(height: 12),
          _tableauLignes(rapport, gras),
          pw.SizedBox(height: 12),
          if (rapport.productions.isNotEmpty) ...<pw.Widget>[
            _blocProductions(rapport, gras),
            pw.SizedBox(height: 12),
          ],
          if (rapport.recus.isNotEmpty) ...<pw.Widget>[
            _blocRecus(rapport, gras, heure),
            pw.SizedBox(height: 12),
          ],
          if (rapport.noteStock.isNotEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                rapport.noteStock,
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
              ),
            ),
          pw.SizedBox(height: 24),
          _signatures(),
        ],
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // BLOCS
  // ---------------------------------------------------------------------------

  static pw.Widget _entete(
    RapportTournee r,
    String dateTexte,
    pw.Font gras,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                'Réf. ${r.reference}',
                style: pw.TextStyle(font: gras, fontSize: 12),
              ),
              pw.Text('Date : $dateTexte',
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            <String>[
              'Agent : ${r.agentNom.isEmpty ? '—' : r.agentNom}',
              if (r.zone.isNotEmpty) 'Zone : ${r.zone}',
              'Statut : ${_statut(r.statut)}',
            ].join('   •   '),
            style: const pw.TextStyle(fontSize: 10),
          ),
          if (r.objectifMontant != null &&
              r.objectifMontant! > 0) ...<pw.Widget>[
            pw.SizedBox(height: 4),
            pw.Text(
              'Objectif : ${_montant(r.objectifMontant!)} ${r.devise} — '
              'réalisé ${_montant(r.chiffreAffaires)} ${r.devise} '
              '(${(r.chiffreAffaires / r.objectifMontant! * 100).clamp(0, 999).toStringAsFixed(0)} %)'
              '${r.commissionTaux != null ? '   •   Commission ${_nombre(r.commissionTaux!)} % = ${_montant(r.commissionMontant)} ${r.devise}' : ''}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _blocTotaux(RapportTournee r, pw.Font gras) {
    final List<List<String>> cases = <List<String>>[
      <String>['Confié', _nombre(r.confie)],
      <String>['Vendu', _nombre(r.vendu)],
      <String>['Rendu', _nombre(r.rendu)],
      <String>['Offert', _nombre(r.offert)],
      <String>['Cassé', _nombre(r.casse)],
      <String>['Manquant', _nombre(r.manquant)],
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: r.aUnManquant ? PdfColors.red50 : PdfColors.green50,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Row(
            children: cases
                .map((List<String> c) => pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: <pw.Widget>[
                          pw.Text(c[0],
                              style: const pw.TextStyle(
                                  fontSize: 8, color: PdfColors.grey700)),
                          pw.Text(c[1],
                              style: pw.TextStyle(font: gras, fontSize: 12)),
                        ],
                      ),
                    ))
                .toList(),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Chiffre d\'affaires : ${_montant(r.chiffreAffaires)} ${r.devise} '
            'sur ${r.nbRecus} reçu(s)'
            '${r.aUnManquant ? '   •   Valeur du manquant : ${_montant(r.valeurManquant)} ${r.devise}' : '   •   Aucun manquant'}',
            style: pw.TextStyle(font: gras, fontSize: 9),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableauLignes(RapportTournee r, pw.Font gras) {
    final pw.TextStyle petit = const pw.TextStyle(fontSize: 8);
    final pw.TextStyle petitGras = pw.TextStyle(font: gras, fontSize: 8);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text('Mouvement par produit',
            style: pw.TextStyle(font: gras, fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: <String>[
            'Produit',
            'Confié',
            'Vendu',
            'Rendu',
            'Offert',
            'Cassé',
            'Manquant',
            'Valeur manquant',
          ],
          data: r.lignes
              .map((LigneRapportTournee l) => <String>[
                    l.nom.isEmpty ? 'Article #${l.produitId}' : l.nom,
                    _nombre(l.confie),
                    _nombre(l.vendu),
                    _nombre(l.rendu),
                    l.offert == 0 ? '—' : _nombre(l.offert),
                    l.casse == 0 ? '—' : _nombre(l.casse),
                    l.manquant == 0 ? '—' : _nombre(l.manquant),
                    l.valeurManquant == 0
                        ? '—'
                        : '${_montant(l.valeurManquant)} ${r.devise}',
                  ])
              .toList(),
          headerStyle: petitGras,
          cellStyle: petit,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellHeight: 16,
          cellAlignments: <int, pw.Alignment>{
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
            7: pw.Alignment.centerRight,
          },
        ),
      ],
    );
  }

  static pw.Widget _blocProductions(RapportTournee r, pw.Font gras) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text('Production du jour (entrée en stock)',
            style: pw.TextStyle(font: gras, fontSize: 11)),
        pw.SizedBox(height: 4),
        ...r.productions.map((ProductionDuJour p) => pw.Text(
              '• ${p.nom} : ${_nombre(p.produite)} produit(s)'
              '${p.pertes > 0 ? ' — pertes ${_nombre(p.pertes)}' : ''}'
              '${p.nb > 0 ? ' (${p.nb} fabrication(s))' : ''}',
              style: const pw.TextStyle(fontSize: 9),
            )),
      ],
    );
  }

  static pw.Widget _blocRecus(
    RapportTournee r,
    pw.Font gras,
    DateFormat heure,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text('Reçus de la tournée',
            style: pw.TextStyle(font: gras, fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: <String>['N° du reçu', 'Heure', 'Articles', 'Montant'],
          data: r.recus
              .map((RecuTournee c) => <String>[
                    c.numero,
                    c.heure == null ? '—' : heure.format(c.heure!),
                    '${c.nbLignes}',
                    '${_montant(c.total)} ${r.devise}',
                  ])
              .toList(),
          headerStyle: pw.TextStyle(font: gras, fontSize: 8),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellHeight: 14,
          cellAlignments: <int, pw.Alignment>{
            1: pw.Alignment.center,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
        ),
      ],
    );
  }

  static pw.Widget _signatures() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        _ligneSignature('L\'agent'),
        _ligneSignature('Le responsable'),
      ],
    );
  }

  static pw.Widget _ligneSignature(String titre) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(titre, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 26),
        pw.Container(
          width: 150,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey500)),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // FORMATAGE (local : le PDF ne dépend d'aucun service de l'application)
  // ---------------------------------------------------------------------------

  static String _statut(String code) {
    switch (code) {
      case 'preparee':
        return 'Préparée';
      case 'en_cours':
        return 'En cours';
      case 'cloturee':
        return 'Clôturée';
      case 'annulee':
        return 'Annulée';
      default:
        return code.isEmpty ? '—' : code;
    }
  }

  /// 1500 → « 1 500 » ; 12.5 → « 12,5 » (les quantités restent lisibles).
  static String _nombre(double valeur) {
    final bool entier = (valeur - valeur.roundToDouble()).abs() < 0.0001;
    final String brut =
        entier ? valeur.round().toString() : valeur.toStringAsFixed(2);
    final List<String> parts = brut.split('.');
    final String entierGroupe = _grouper(parts.first);
    return parts.length > 1 ? '$entierGroupe,${parts[1]}' : entierGroupe;
  }

  static String _montant(double valeur) => _grouper(valeur.round().toString());

  static String _grouper(String chiffres) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < chiffres.length; i++) {
      if (i > 0 && (chiffres.length - i) % 3 == 0) sb.write(' ');
      sb.write(chiffres[i]);
    }
    return sb.toString();
  }
}
