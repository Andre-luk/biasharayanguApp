// lib/services/pressing_atelier_pdf_service.dart
//
// 🧺 MODULE 35 — LE BORDEREAU D'ATELIER (imprimable).
//
// À QUOI ÇA SERT
//   L'atelier travaille debout, souvent loin de l'écran. Le bordereau est la
//   feuille que l'on punaise au mur ou que l'on donne à l'agent : la liste des
//   vêtements à traiter, REGROUPÉS PAR ÉTAPE, avec une case à cocher pour
//   marquer ce qui est fait à la main.
//
// CE QU'IL CONTIENT
//   • l'en-tête du pressing (nom, adresse, téléphone) et l'heure d'édition ;
//   • le résumé : vêtements, dossiers, urgents, en retard ;
//   • une section par étape : chaque vêtement avec n° de dossier, client,
//     description, défauts constatés au dépôt et date de retrait prévue ;
//   • une ligne de signature en bas de chaque page.
//
// ⚠️ Document de TRAVAIL interne : il ne remplace pas le reçu du client et
//    n'affiche aucun montant.

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/pressing.dart';
import 'package:biashara_yangu/utils/partage_pdf.dart';

/// Tout ce dont le bordereau a besoin.
class DonneesBordereauAtelier {
  DonneesBordereauAtelier({
    required this.etablissement,
    required this.lignes,
    this.filtreLibelle,
    this.mesVetementsSeulement = false,
    DateTime? genereLe,
  }) : genereLe = genereLe ?? DateTime.now();

  final Etablissement etablissement;
  final List<PressingLigneAtelier> lignes;

  /// Étape filtrée sur l'écran (`null` = toutes les étapes).
  final String? filtreLibelle;

  /// L'agent n'a demandé que SES vêtements.
  final bool mesVetementsSeulement;

  final DateTime genereLe;

  int get nbVetements => lignes.length;

  int get nbDossiers =>
      lignes.map((PressingLigneAtelier l) => l.commandeId).toSet().length;

  int get nbUrgents =>
      lignes.where((PressingLigneAtelier l) => l.urgence).length;

  int get nbEnRetard =>
      lignes.where((PressingLigneAtelier l) => l.enRetard).length;

  String get nomFichier {
    final String date = DateFormat('yyyyMMdd-HHmm').format(genereLe);
    return 'bordereau-atelier-$date.pdf';
  }

  /// Regroupe les lignes par étape, dans l'ordre des étapes fourni.
  Map<String, List<PressingLigneAtelier>> parEtape(List<PressingEtape> etapes) {
    final Map<String, List<PressingLigneAtelier>> groupes =
        <String, List<PressingLigneAtelier>>{};

    final List<PressingEtape> triees = <PressingEtape>[...etapes]
      ..sort((PressingEtape a, PressingEtape b) => a.ordre.compareTo(b.ordre));

    for (final PressingEtape etape in triees) {
      final List<PressingLigneAtelier> duGroupe = lignes
          .where((PressingLigneAtelier l) => l.etapeCode == etape.code)
          .toList(growable: false);
      if (duGroupe.isNotEmpty) groupes[etape.libelle] = duGroupe;
    }

    // Étapes inconnues (circuit modifié après le dépôt) : jamais perdues.
    final List<PressingLigneAtelier> orphelines = lignes
        .where((PressingLigneAtelier l) => !groupes.values
            .any((List<PressingLigneAtelier> g) => g.contains(l)))
        .toList(growable: false);
    if (orphelines.isNotEmpty) {
      final Map<String, List<PressingLigneAtelier>> parLibelle =
          <String, List<PressingLigneAtelier>>{};
      for (final PressingLigneAtelier l in orphelines) {
        final String libelle = (l.etapeLibelle ?? l.etapeCode).trim();
        parLibelle.putIfAbsent(libelle, () => <PressingLigneAtelier>[]).add(l);
      }
      groupes.addAll(parLibelle);
    }

    return groupes;
  }
}

/// Génère, imprime et partage le bordereau d'atelier.
class PressingAtelierPdfService {
  PressingAtelierPdfService._();

  static final PressingAtelierPdfService instance =
      PressingAtelierPdfService._();

  static const PdfColor _marine = PdfColor.fromInt(0xFF1F3864);
  static const PdfColor _orange = PdfColor.fromInt(0xFFF08A4B);
  static const PdfColor _gris = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _bordure = PdfColor.fromInt(0xFFE2E8F0);

  Future<pw.Document> construire(
    DonneesBordereauAtelier donnees,
    List<PressingEtape> etapes,
  ) async {
    final pw.Document document = pw.Document(
      title: 'Bordereau d\'atelier',
      author: donnees.etablissement.nomAffiche,
      subject: 'Liste des vêtements à traiter',
    );

    pw.ThemeData? theme;
    try {
      final pw.Font base = await PdfGoogleFonts.robotoRegular();
      final pw.Font gras = await PdfGoogleFonts.robotoBold();
      theme = pw.ThemeData.withFont(base: base, bold: gras);
    } catch (e) {
      debugPrint(
          'PressingAtelierPdfService : police Unicode indisponible ($e)');
    }

    final Map<String, List<PressingLigneAtelier>> groupes =
        donnees.parEtape(etapes);

    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 34),
        footer: _piedDePage,
        build: (pw.Context context) => <pw.Widget>[
          _entete(donnees),
          pw.SizedBox(height: 12),
          _resume(donnees),
          pw.SizedBox(height: 14),
          if (groupes.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 24),
              child: pw.Center(
                child: pw.Text(
                  'Aucun vêtement à traiter pour ce filtre.',
                  style: const pw.TextStyle(fontSize: 11, color: _gris),
                ),
              ),
            )
          else
            ...groupes.entries.expand(
              (MapEntry<String, List<PressingLigneAtelier>> e) => <pw.Widget>[
                _titreEtape(e.key, e.value.length),
                pw.SizedBox(height: 4),
                _tableau(e.value),
                pw.SizedBox(height: 14),
              ],
            ),
          _signature(),
        ],
      ),
    );

    return document;
  }

  // ---------------------------------------------------------------------------
  //  SECTIONS
  // ---------------------------------------------------------------------------

  pw.Widget _entete(DonneesBordereauAtelier d) {
    final Etablissement e = d.etablissement;
    final List<String> coordonnees = <String>[
      if ((e.adresse ?? '').trim().isNotEmpty) e.adresse!.trim(),
      if ((e.telephone ?? '').trim().isNotEmpty) 'Tél. ${e.telephone!.trim()}',
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _marine, width: 2)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  e.nomAffiche,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: _marine,
                  ),
                ),
                if (coordonnees.isNotEmpty)
                  pw.Text(
                    coordonnees.join(' · '),
                    style: const pw.TextStyle(fontSize: 8, color: _gris),
                  ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                'BORDEREAU D\'ATELIER',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: _orange,
                ),
              ),
              pw.Text(
                'Édité le ${DateFormat('dd/MM/yyyy à HH:mm').format(d.genereLe)}',
                style: const pw.TextStyle(fontSize: 8, color: _gris),
              ),
              if ((d.filtreLibelle ?? '').trim().isNotEmpty)
                pw.Text(
                  'Filtre : ${d.filtreLibelle!.trim()}',
                  style: const pw.TextStyle(fontSize: 8, color: _gris),
                ),
              if (d.mesVetementsSeulement)
                pw.Text(
                  'Mes vêtements uniquement',
                  style: const pw.TextStyle(fontSize: 8, color: _gris),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _resume(DonneesBordereauAtelier d) {
    pw.Widget _vignette(String libelle, String valeur, PdfColor couleur) {
      return pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF8FAFC),
            borderRadius: pw.BorderRadius.circular(4),
            border: pw.Border.all(color: _bordure),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                libelle,
                style: const pw.TextStyle(fontSize: 7, color: _gris),
              ),
              pw.Text(
                valeur,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: couleur,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Row(
      children: <pw.Widget>[
        _vignette('VÊTEMENTS', '${d.nbVetements}', _marine),
        _vignette('DOSSIERS', '${d.nbDossiers}', _marine),
        _vignette('URGENTS', '${d.nbUrgents}', _orange),
        _vignette(
            'EN RETARD', '${d.nbEnRetard}', const PdfColor.fromInt(0xFFC62828)),
      ],
    );
  }

  pw.Widget _titreEtape(String libelle, int nombre) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: _marine,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            libelle.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
          pw.Text(
            '$nombre vêtement${nombre > 1 ? 's' : ''}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
          ),
        ],
      ),
    );
  }

  pw.Widget _tableau(List<PressingLigneAtelier> lignes) {
    final List<PressingLigneAtelier> triees = <PressingLigneAtelier>[...lignes]
      ..sort((PressingLigneAtelier a, PressingLigneAtelier b) {
        final DateTime? da = a.datePrevue;
        final DateTime? db = b.datePrevue;
        if (da != null && db != null) return da.compareTo(db);
        return a.numero.compareTo(b.numero);
      });

    final pw.TableRow entete = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
      children: <pw.Widget>[
        _cellule('FAIT', gras: true, largeur: 0.7),
        _cellule('DOSSIER', gras: true, largeur: 1.1),
        _cellule('CLIENT', gras: true, largeur: 1.6),
        _cellule('VÊTEMENT', gras: true, largeur: 2.4),
        _cellule('DÉFAUTS AU DÉPÔT', gras: true, largeur: 1.7),
        _cellule('RETRAIT', gras: true, largeur: 1.0),
      ],
    );

    return pw.Table(
      border: pw.TableBorder.all(color: _bordure, width: 0.5),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(0.7),
        1: pw.FlexColumnWidth(1.1),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FlexColumnWidth(2.4),
        4: pw.FlexColumnWidth(1.7),
        5: pw.FlexColumnWidth(1.0),
      },
      children: <pw.TableRow>[
        entete,
        ...triees.map((PressingLigneAtelier l) {
          final String vetement = l.details.trim().isEmpty
              ? l.titre
              : '${l.titre} — ${l.details.trim()}';
          return pw.TableRow(
            children: <pw.Widget>[
              // Case à cocher : l'agent marque au stylo ce qui est terminé.
              _cellule('☐', centre: true),
              _cellule(l.numero, mono: true),
              _cellule((l.clientNom ?? '—').trim()),
              _cellule(vetement),
              _cellule(
                (l.defauts ?? '').trim().isEmpty ? '—' : l.defauts!.trim(),
                petite: true,
              ),
              _cellule(
                l.datePrevue == null
                    ? '—'
                    : DateFormat('dd/MM').format(l.datePrevue!),
                centre: true,
                couleur: l.enRetard ? const PdfColor.fromInt(0xFFC62828) : null,
              ),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _cellule(
    String texte, {
    bool gras = false,
    bool centre = false,
    bool mono = false,
    bool petite = false,
    double? largeur,
    PdfColor? couleur,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: pw.Text(
        texte.isEmpty ? '—' : texte,
        textAlign: centre ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: petite ? 7 : 8,
          fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: couleur ?? PdfColors.black,
          font: mono ? pw.Font.courier() : null,
        ),
      ),
    );
  }

  pw.Widget _signature() {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _bordure)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            'Visa atelier : ______________________',
            style: const pw.TextStyle(fontSize: 8, color: _gris),
          ),
          pw.Text(
            'Contrôle qualité : ______________________',
            style: const pw.TextStyle(fontSize: 8, color: _gris),
          ),
        ],
      ),
    );
  }

  pw.Widget _piedDePage(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 6),
      child: pw.Text(
        'Page ${context.pageNumber} / ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 7, color: _gris),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> imprimer(
    DonneesBordereauAtelier donnees,
    List<PressingEtape> etapes,
  ) async {
    final pw.Document document = await construire(donnees, etapes);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => document.save(),
      name: donnees.nomFichier,
    );
  }

  Future<void> partagerPdf(
    DonneesBordereauAtelier donnees,
    List<PressingEtape> etapes,
  ) async {
    final pw.Document document = await construire(donnees, etapes);
    final Uint8List bytes = await document.save();
    await PartagePdf.partager(bytes, nomFichier: donnees.nomFichier);
  }
}
