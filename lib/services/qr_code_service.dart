// lib/services/qr_code_service.dart
//
// MODULE 6 — GÉNÉRATION, TÉLÉCHARGEMENT ET IMPRESSION DES QR CODES
//
//   • génération d'images PNG en haute résolution (300 DPI) ;
//   • génération vectorielle SVG ;
//   • étiquettes PDF A4 (grille 3 × 4, texte optionnel, date d'impression) ;
//   • impression et partage via le paquet `printing`.
//
// ⚠️ RÈGLE ABSOLUE (cahier des charges) : un QR code ne contient JAMAIS de
// prix. Il encode seulement `PROD:<id>` ou `COND:<uuid>`. Le prix est relu
// dans la base de données au moment du scan : il peut donc changer sans
// invalider les étiquettes déjà imprimées.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr/qr.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/etiquette_qr.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/fichiers_locaux.dart';

/// Erreur métier du module « QR codes ».
///
/// [message] est toujours rédigé en français et peut être affiché tel quel
/// à l'utilisateur (SnackBar, écran d'erreur…).
class QrCodeServiceException implements Exception {
  const QrCodeServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Format de fichier téléchargeable pour un QR code.
enum QrFormatFichier {
  png('png', 'PNG (image)'),
  svg('svg', 'SVG (vectoriel)');

  const QrFormatFichier(this.extension, this.libelle);

  final String extension;
  final String libelle;
}

/// Génération, export et impression des QR codes des articles et de leurs
/// conditionnements.
class QrCodeService {
  QrCodeService._();

  static final QrCodeService instance = QrCodeService._();

  /// Résolution des exports PNG : 300 DPI (exigence d'impression).
  static const int dpi = 300;

  /// Marge blanche normalisée autour du QR (4 modules, norme ISO/IEC 18004).
  static const int quietZoneModules = 4;

  /// Niveau de correction d'erreur : M (robuste à ~15 % de dégradation —
  /// adapté aux étiquettes collées sur des produits).
  static const int niveauCorrection = QrErrorCorrectLevel.M;

  /// Taille de référence d'un QR imprimé, en millimètres.
  static const double tailleParDefautMm = 40;

  /// Tailles proposées dans les écrans (en millimètres).
  static const List<double> taillesMm = <double>[30, 40, 50];

  /// Taille des lots de la génération en masse (exigence : 10 par 10).
  static const int tailleLotDefaut = 10;

  /// Grille des planches PDF : 3 colonnes × 4 lignes = 12 étiquettes / page.
  static const int colonnesParPage = 3;
  static const int lignesParPage = 4;
  static const int etiquettesParPage = colonnesParPage * lignesParPage;

  final Map<String, Uint8List> _cachePng = <String, Uint8List>{};

  // ---------------------------------------------------------------------------
  // 1. GÉNÉRATION D'UNE IMAGE QR
  // ---------------------------------------------------------------------------

  /// Convertit une taille en millimètres en pixels à 300 DPI.
  static double pixelsPourMillimetres(double millimetres) {
    return millimetres / 25.4 * dpi;
  }

  /// `genererQrCode(data)` — image PNG du QR code, fond blanc + marge
  /// normalisée, rendue en 300 DPI par défaut.
  ///
  /// [data] est le contenu ENTIER du QR (`PROD:123`, `COND:<uuid>`) :
  /// jamais un prix.
  Future<Uint8List> genererQrCode(String data, {double? taillePixels}) {
    return _executer(
      () async {
        final double pixels =
            taillePixels ?? pixelsPourMillimetres(tailleParDefautMm);
        final int cote = pixels.ceil().clamp(64, 4096);

        final String cle = '$data|$cote';
        final Uint8List? enCache = _cachePng[cle];
        if (enCache != null) return enCache;

        final Uint8List bytes = await _rendrePng(data, cote);
        _cachePng[cle] = bytes;

        // Le cache reste borné : les plus anciens exports sont oubliés.
        while (_cachePng.length > 64) {
          _cachePng.remove(_cachePng.keys.first);
        }
        return bytes;
      },
      actionLibelle: 'la génération du QR code',
      messageEchec:
          'Impossible de générer le QR code. Vérifiez les données puis réessayez.',
    );
  }

  /// `genererQrCodesEnMasse(produitIds)` — prépare (et met en cache) les
  /// étiquettes des articles demandés, **par lots de 10**, avec progression.
  ///
  /// Renvoie les étiquettes prêtes : articles (`PROD:…`) puis, pour chacun,
  /// ses conditionnements (`COND:…`).
  Future<List<EtiquetteQr>> genererQrCodesEnMasse(
    List<int> produitIds, {
    void Function(int faits, int total)? onProgression,
    int tailleLot = tailleLotDefaut,
    double tailleMm = tailleParDefautMm,
    bool inclureConditionnements = true,
  }) {
    return _executer(
      () async {
        final List<Article> articles =
            await ArticleService.instance.getArticles();

        final Set<int> ids = produitIds.toSet();
        final List<Article> selection = ids.isEmpty
            ? articles
            : articles
                .where((Article article) => ids.contains(article.id))
                .toList();

        final List<EtiquetteQr> etiquettes = etiquettesPourArticles(
          selection,
          inclureConditionnements: inclureConditionnements,
        );

        await preparerEtiquettes(
          etiquettes,
          onProgression: onProgression,
          tailleLot: tailleLot,
          tailleMm: tailleMm,
        );
        return etiquettes;
      },
      actionLibelle: 'la génération des QR codes en masse',
      messageEchec:
          'Impossible de générer les QR codes en masse. Vérifiez votre connexion internet puis réessayez.',
    );
  }

  /// Pré-génère les PNG des [etiquettes] par lots de [tailleLot] avec
  /// remontée de progression `(faits, total)`.
  Future<void> preparerEtiquettes(
    List<EtiquetteQr> etiquettes, {
    void Function(int faits, int total)? onProgression,
    int tailleLot = tailleLotDefaut,
    double tailleMm = tailleParDefautMm,
  }) {
    return _executer(
      () async {
        final List<List<EtiquetteQr>> lots =
            _decouperEnLots(etiquettes, tailleLot);
        int faits = 0;

        for (final List<EtiquetteQr> lot in lots) {
          for (final EtiquetteQr etiquette in lot) {
            await genererQrCode(
              etiquette.code,
              taillePixels: pixelsPourMillimetres(tailleMm),
            );
            faits++;
            onProgression?.call(faits, etiquettes.length);
          }
        }
      },
      actionLibelle: 'la préparation des QR codes',
      messageEchec: 'Impossible de préparer les QR codes.',
    );
  }

  // ---------------------------------------------------------------------------
  // 2. GÉNÉRATION VECTORIELLE (SVG)
  // ---------------------------------------------------------------------------

  /// QR code au format SVG — vectoriel, donc imprimable à n'importe quelle
  /// taille sans perte. La taille est exprimée en millimètres.
  String genererSvgQrCode(String data, {double tailleMm = tailleParDefautMm}) {
    final QrImage qrImage = _matrice(data);
    final int totalModules = qrImage.moduleCount + quietZoneModules * 2;
    final String taille = _nombreTexte(tailleMm);

    final StringBuffer svg = StringBuffer()
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" '
          'width="${taille}mm" height="${taille}mm" '
          'viewBox="0 0 $totalModules $totalModules" '
          'shape-rendering="crispEdges">')
      ..writeln('  <rect width="$totalModules" height="$totalModules" '
          'fill="#FFFFFF"/>')
      ..write('  <path fill="#000000" d="');

    for (int ligne = 0; ligne < qrImage.moduleCount; ligne++) {
      for (int colonne = 0; colonne < qrImage.moduleCount; colonne++) {
        if (!qrImage.isDark(ligne, colonne)) continue;
        svg.write(
            'M${colonne + quietZoneModules} ${ligne + quietZoneModules}h1v1h-1z');
      }
    }

    svg
      ..writeln('"/>')
      ..writeln('</svg>');

    return svg.toString();
  }

  // ---------------------------------------------------------------------------
  // 3. ÉTIQUETTES (ARTICLE + CONDITIONNEMENTS)
  // ---------------------------------------------------------------------------

  /// Construit les étiquettes d'une liste d'articles : chaque article donne
  /// une étiquette `PROD:<id>` puis, si [inclureConditionnements], une
  /// étiquette `COND:<qr_code_id>` par conditionnement.
  ///
  /// Méthode pure (aucun réseau) — utilisée par les écrans et les tests.
  static List<EtiquetteQr> etiquettesPourArticles(
    List<Article> articles, {
    bool inclureConditionnements = true,
  }) {
    final List<EtiquetteQr> etiquettes = <EtiquetteQr>[];

    for (final Article article in articles) {
      etiquettes.add(EtiquetteQr(
        type: TypeQrCode.article,
        identifiant: '${article.id}',
        articleId: article.id,
        titre: article.nom,
      ));

      if (!inclureConditionnements) continue;

      for (final Conditionnement conditionnement in article.conditionnements) {
        etiquettes.add(EtiquetteQr(
          type: TypeQrCode.conditionnement,
          identifiant: conditionnement.qrCodeId,
          articleId: article.id,
          titre: article.nom,
          sousTitre: '${conditionnement.libelle} — '
              '${_nombreTexte(conditionnement.quantiteUnitesBase)} '
              '${Conditionnement.pluriel(article.uniteMesure, conditionnement.quantiteUnitesBase)}',
        ));
      }
    }

    return etiquettes;
  }

  // ---------------------------------------------------------------------------
  // 4. TÉLÉCHARGEMENT (PNG / SVG)
  // ---------------------------------------------------------------------------

  /// `telechargerQrCode(qrCodeId, format)` — enregistre le QR code sur
  /// l'appareil et renvoie le chemin du fichier créé.
  ///
  /// [etiquette] porte le code encodé (`PROD:…` / `COND:…`) et le nom du
  /// fichier. Le dossier utilisé est « Téléchargements/qrcodes » (repli :
  /// documents de l'application sur mobile).
  Future<String> telechargerQrCode(
    EtiquetteQr etiquette, {
    QrFormatFichier format = QrFormatFichier.png,
    double tailleMm = tailleParDefautMm,
  }) {
    return _executer(
      () async {
        final String nomFichier =
            '${etiquette.nomFichierBase}.${format.extension}';

        switch (format) {
          case QrFormatFichier.png:
            final Uint8List bytes = await genererQrCode(
              etiquette.code,
              taillePixels: pixelsPourMillimetres(tailleMm),
            );
            final String? chemin = await enregistrerDansTelechargements(
              sousDossier: 'qrcodes',
              nomFichier: nomFichier,
              octets: bytes,
              mimeType: 'image/png',
            );
            return chemin ?? nomFichier;
          case QrFormatFichier.svg:
            final String? chemin = await enregistrerDansTelechargements(
              sousDossier: 'qrcodes',
              nomFichier: nomFichier,
              octets: utf8.encode(
                genererSvgQrCode(etiquette.code, tailleMm: tailleMm),
              ),
              mimeType: 'image/svg+xml',
            );
            return chemin ?? nomFichier;
        }
      },
      actionLibelle: 'le téléchargement du QR code',
      messageEchec:
          "Impossible d'enregistrer le QR code sur l'appareil. Vérifiez l'espace de stockage puis réessayez.",
    );
  }

  /// Télécharge une liste d'étiquettes par lots de [tailleLot], avec
  /// progression. Renvoie les chemins des fichiers créés.
  Future<List<String>> telechargerQrCodes(
    List<EtiquetteQr> etiquettes, {
    QrFormatFichier format = QrFormatFichier.png,
    double tailleMm = tailleParDefautMm,
    int tailleLot = tailleLotDefaut,
    void Function(int faits, int total)? onProgression,
  }) {
    return _executer(
      () async {
        final List<String> chemins = <String>[];
        final List<List<EtiquetteQr>> lots =
            _decouperEnLots(etiquettes, tailleLot);
        int faits = 0;

        for (final List<EtiquetteQr> lot in lots) {
          for (final EtiquetteQr etiquette in lot) {
            chemins.add(await telechargerQrCode(
              etiquette,
              format: format,
              tailleMm: tailleMm,
            ));
            faits++;
            onProgression?.call(faits, etiquettes.length);
          }
        }

        return chemins;
      },
      actionLibelle: 'le téléchargement des QR codes',
      messageEchec:
          "Impossible d'enregistrer les QR codes sur l'appareil. Vérifiez l'espace de stockage puis réessayez.",
    );
  }

  // ---------------------------------------------------------------------------
  // 5. PLANCHES PDF (IMPRESSION D'ÉTIQUETTES)
  // ---------------------------------------------------------------------------

  /// `imprimerEtiquettes(qrCodeIds)` — construit la planche PDF A4 puis
  /// ouvre la boîte de dialogue d'impression du système.
  ///
  /// Grille 3 × 4 (12 étiquettes par page), nom de l'article sous chaque QR,
  /// date d'impression en tête de chaque page.
  Future<void> imprimerEtiquettes(
    List<EtiquetteQr> etiquettes, {
    bool avecTexte = true,
    double? tailleQrPoints,
    String nomTravail = 'Etiquettes QR',
  }) {
    return _executer(
      () async {
        final Uint8List bytes = await construirePlanchePdf(
          etiquettes,
          avecTexte: avecTexte,
          tailleQrPoints: tailleQrPoints,
        );

        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => bytes,
          name: nomTravail,
          format: PdfPageFormat.a4,
        );
      },
      actionLibelle: "l'impression des étiquettes",
      messageEchec:
          "L'impression a échoué. Vérifiez qu'une imprimante est disponible puis réessayez.",
    );
  }

  /// Partage la planche PDF des étiquettes (mail, messagerie…).
  Future<void> partagerEtiquettes(
    List<EtiquetteQr> etiquettes, {
    bool avecTexte = true,
    String nomFichier = 'etiquettes_qr.pdf',
  }) {
    return _executer(
      () async {
        final Uint8List bytes = await construirePlanchePdf(
          etiquettes,
          avecTexte: avecTexte,
        );

        await Printing.sharePdf(bytes: bytes, filename: nomFichier);
      },
      actionLibelle: 'le partage des étiquettes',
      messageEchec: 'Impossible de partager les étiquettes. Réessayez.',
    );
  }

  /// Construit la planche PDF complète (A4, 300 DPI) et renvoie les octets.
  Future<Uint8List> construirePlanchePdf(
    List<EtiquetteQr> etiquettes, {
    bool avecTexte = true,
    double? tailleQrPoints,
    DateTime? dateImpression,
  }) {
    return _executer(
      () async {
        if (etiquettes.isEmpty) {
          throw const QrCodeServiceException(
            'Aucune étiquette à imprimer : sélectionnez au moins un article ou un conditionnement.',
          );
        }

        final _MetriquesPlanche metriques =
            _MetriquesPlanche.calculer(avecTexte: avecTexte, souhaitee: tailleQrPoints);

        // Les images sont fabriquées à la résolution exacte de l'impression
        // (300 DPI une fois posées sur la page) puis réutilisées.
        final Map<String, pw.MemoryImage> images = <String, pw.MemoryImage>{};
        for (final EtiquetteQr etiquette in etiquettes) {
          final Uint8List bytes = await genererQrCode(
            etiquette.code,
            taillePixels: (metriques.qrPoints / 72 * dpi).ceilToDouble(),
          );
          images[etiquette.code] = pw.MemoryImage(bytes);
        }

        final pw.ThemeData? theme = await _chargerTheme();
        final String dateTexte =
            formatDateHeure(dateImpression ?? DateTime.now());

        final pw.Document pdf = pw.Document();
        final List<List<EtiquetteQr>> pages =
            _decouperEnLots(etiquettes, etiquettesParPage);

        for (int page = 0; page < pages.length; page++) {
          pdf.addPage(_construirePage(
            etiquettes: pages[page],
            images: images,
            metriques: metriques,
            avecTexte: avecTexte,
            dateTexte: dateTexte,
            theme: theme,
            numeroPage: page + 1,
            totalPages: pages.length,
          ));
        }

        return pdf.save();
      },
      actionLibelle: 'la construction de la planche PDF',
      messageEchec:
          'Impossible de construire la planche PDF. Réessayez dans un instant.',
    );
  }

  pw.Page _construirePage({
    required List<EtiquetteQr> etiquettes,
    required Map<String, pw.MemoryImage> images,
    required _MetriquesPlanche metriques,
    required bool avecTexte,
    required String dateTexte,
    required pw.ThemeData? theme,
    required int numeroPage,
    required int totalPages,
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_MetriquesPlanche.margePage),
      theme: theme,
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Étiquettes QR — Biashara Yangu',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  'Imprimé le $dateTexte   ·   page $numeroPage/$totalPages',
                  style: const pw.TextStyle(
                      fontSize: 8.5, color: PdfColors.grey700),
                ),
              ],
            ),
            pw.Divider(thickness: 0.7, color: PdfColors.grey400),
            pw.SizedBox(height: _MetriquesPlanche.espacementGrille),
            pw.Wrap(
              spacing: _MetriquesPlanche.espacementGrille,
              runSpacing: _MetriquesPlanche.espacementGrille,
              children: [
                for (final EtiquetteQr etiquette in etiquettes)
                  _celluleEtiquette(
                    etiquette: etiquette,
                    image: images[etiquette.code]!,
                    metriques: metriques,
                    avecTexte: avecTexte,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  pw.Widget _celluleEtiquette({
    required EtiquetteQr etiquette,
    required pw.MemoryImage image,
    required _MetriquesPlanche metriques,
    required bool avecTexte,
  }) {
    return pw.Container(
      width: metriques.largeurCellule,
      height: metriques.hauteurCellule,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5, color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Image(image, width: metriques.qrPoints, height: metriques.qrPoints),
          if (avecTexte) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              etiquette.titre,
              maxLines: 2,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: 8.5, fontWeight: pw.FontWeight.bold),
            ),
            if ((etiquette.sousTitre ?? '').trim().isNotEmpty)
              pw.Text(
                etiquette.sousTitre!,
                maxLines: 1,
                textAlign: pw.TextAlign.center,
                style:
                    const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
              ),
            pw.SizedBox(height: 2),
            pw.Text(
              etiquette.code,
              style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey500),
            ),
          ],
        ],
      ),
    );
  }

  /// Polices Roboto (accents propres et rendu homogène). En cas d'échec
  /// (hors ligne), les polices PDF intégrées prennent le relais.
  Future<pw.ThemeData?> _chargerTheme() async {
    try {
      final pw.Font base = await PdfGoogleFonts.robotoRegular();
      final pw.Font gras = await PdfGoogleFonts.robotoBold();
      return pw.ThemeData.withFont(base: base, bold: gras);
    } catch (e) {
      debugPrint('QrCodeService (polices PDF par défaut): $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // OUTILS INTERNES
  // ---------------------------------------------------------------------------

  /// Matrice du QR code (contenu → modules noirs/blancs).
  static QrImage _matrice(String data) {
    if (data.trim().isEmpty) {
      throw const QrCodeServiceException(
        'Impossible de générer un QR code vide.',
      );
    }
    try {
      final QrCode qrCode =
          QrCode.fromData(data: data, errorCorrectLevel: niveauCorrection);
      return QrImage(qrCode);
    } on InputTooLongException {
      throw const QrCodeServiceException(
        'Le contenu est trop long pour un QR code.',
      );
    }
  }

  /// Dessine le QR code module par module sur un fond blanc, avec la marge
  /// normalisée, puis exporte l'image en PNG.
  Future<Uint8List> _rendrePng(String data, int cotePixels) async {
    final QrImage qrImage = _matrice(data);
    final int totalModules = qrImage.moduleCount + quietZoneModules * 2;
    final int modulePixels = math.max(1, (cotePixels / totalModules).ceil());
    final int cote = modulePixels * totalModules;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);

    final ui.Paint fond = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..isAntiAlias = false;
    final ui.Paint noir = ui.Paint()
      ..color = const ui.Color(0xFF000000)
      ..isAntiAlias = false;

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, cote.toDouble(), cote.toDouble()),
      fond,
    );

    for (int ligne = 0; ligne < qrImage.moduleCount; ligne++) {
      for (int colonne = 0; colonne < qrImage.moduleCount; colonne++) {
        if (!qrImage.isDark(ligne, colonne)) continue;
        canvas.drawRect(
          ui.Rect.fromLTWH(
            ((colonne + quietZoneModules) * modulePixels).toDouble(),
            ((ligne + quietZoneModules) * modulePixels).toDouble(),
            modulePixels.toDouble(),
            modulePixels.toDouble(),
          ),
          noir,
        );
      }
    }

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(cote, cote);
    final ByteData? octets = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();

    if (octets == null) {
      throw const QrCodeServiceException(
        "La génération de l'image QR a échoué.",
      );
    }
    return octets.buffer.asUint8List();
  }

  /// Découpe une liste en lots de [taille] (le dernier lot peut être plus
  /// petit). Utilisé pour la génération « 10 par 10 » et les pages PDF.
  static List<List<T>> _decouperEnLots<T>(List<T> elements, int taille) {
    if (taille <= 0) return <List<T>>[elements];
    final List<List<T>> lots = <List<T>>[];
    for (int debut = 0; debut < elements.length; debut += taille) {
      final int fin = math.min(debut + taille, elements.length);
      lots.add(elements.sublist(debut, fin));
    }
    return lots;
  }

  /// « 12 » pour un entier, « 1,5 » sinon.
  static String _nombreTexte(double valeur) {
    if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
    return valeur
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  /// Exécute [action] en traduisant toute erreur en [QrCodeServiceException].
  Future<T> _executer<T>(
    Future<T> Function() action, {
    required String actionLibelle,
    required String messageEchec,
  }) async {
    try {
      return await action();
    } on QrCodeServiceException {
      rethrow;
    } on ArticleServiceException catch (e) {
      throw QrCodeServiceException(e.message);
    } catch (e, st) {
      debugPrint('QrCodeService ($actionLibelle): $e\n$st');
      throw QrCodeServiceException(messageEchec);
    }
  }
}

/// Dimensions de la grille d'étiquettes sur une page A4.
///
/// Calculées une seule fois : les images QR sont générées à la taille EXACTE
/// où elles seront posées (300 DPI effectifs une fois imprimées).
class _MetriquesPlanche {
  const _MetriquesPlanche({
    required this.largeurCellule,
    required this.hauteurCellule,
    required this.qrPoints,
  });

  static const double margePage = 24;
  static const double espacementGrille = 12;
  static const double hauteurEnTete = 30;

  final double largeurCellule;
  final double hauteurCellule;
  final double qrPoints;

  factory _MetriquesPlanche.calculer({
    required bool avecTexte,
    double? souhaitee,
  }) {
    const int colonnes = QrCodeService.colonnesParPage;
    const int lignes = QrCodeService.lignesParPage;

    final double largeurContenu = PdfPageFormat.a4.width - margePage * 2;
    final double hauteurContenu =
        PdfPageFormat.a4.height - margePage * 2 - hauteurEnTete;

    final double largeurCellule =
        (largeurContenu - espacementGrille * (colonnes - 1)) / colonnes;
    final double hauteurCellule =
        (hauteurContenu - espacementGrille * (lignes - 1)) / lignes;

    // Au-dessus du QR : le titre, le sous-titre, le code et les marges.
    final double reserveTexte = avecTexte ? 44 : 14;
    final double disponible = math.min(
      largeurCellule - 12,
      hauteurCellule - reserveTexte,
    );

    final double qrPoints = math.min(souhaitee ?? disponible, disponible);

    return _MetriquesPlanche(
      largeurCellule: largeurCellule,
      hauteurCellule: hauteurCellule,
      qrPoints: qrPoints,
    );
  }
}
