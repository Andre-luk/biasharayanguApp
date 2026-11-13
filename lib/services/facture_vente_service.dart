// lib/services/facture_vente_service.dart
//
// MODULE 27 — LA FACTURE DE VENTE, UN SEUL MODÈLE POUR TOUS LES ÉCRANS.
//
// Le problème constaté : la caisse imprimait un ticket 58 mm, « New Sale »
// produisait un document différent, et aucune des deux n'affichait l'adresse,
// le RCCM ou un pied de page digne d'un logiciel commercial.
//
// Ici :
//   • UN document A4 professionnel (en-tête, tableau, récapitulatif, mentions
//     légales, pied de page) ;
//   • les mêmes données pour toutes les pages de vente : elles construisent un
//     [DonneesFacture] et appellent ce service ;
//   • téléchargement À LA DEMANDE, impression, partage du PDF et
//     message WhatsApp prêt pour le client ;
//   • aucune information inventée : un champ absent est simplement masqué.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/services/etablissement_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/partage_pdf.dart';

/// Statut de paiement d'une facture.
enum StatutFacture {
  payee('Payée', PdfColors.green800),
  partielle('Partiellement payée', PdfColors.orange800),
  credit('À crédit', PdfColors.red800),
  annulee('Annulée', PdfColors.grey700);

  const StatutFacture(this.libelle, this.couleur);

  final String libelle;
  final PdfColor couleur;
}

/// Une ligne facturée (ou offerte).
class LigneFacture {
  const LigneFacture({
    required this.designation,
    required this.quantite,
    required this.prixUnitaire,
    required this.total,
    this.unite = '',
    this.estCadeau = false,
  });

  final String designation;
  final double quantite;
  final String unite;
  final double prixUnitaire;
  final double total;

  /// 🎁 Ligne offerte : affichée mais JAMAIS facturée.
  final bool estCadeau;
}

/// Tout ce dont le document a besoin. Construit par l'écran de vente.
class DonneesFacture {
  DonneesFacture({
    required this.numero,
    required this.date,
    required this.etablissement,
    required this.lignes,
    required this.total,
    required this.modePaiement,
    this.statut = StatutFacture.payee,
    this.clientNom,
    this.clientTelephone,
    this.clientAdresse,
    this.totalCatalogue = 0,
    this.negociation = 0,
    this.remise = 0,
    this.remiseLibelle,
    this.valeurCadeaux = 0,
    this.cadeaux = const <String>[],
    this.montantPaye,
    this.solde = 0,
    this.venteId,
    this.devise = 'CDF',
  });

  final String numero;
  final DateTime date;
  final Etablissement etablissement;
  final List<LigneFacture> lignes;

  final StatutFacture statut;

  final String? clientNom;
  final String? clientTelephone;
  final String? clientAdresse;

  /// Somme au prix catalogue (avant négociation / réduction).
  final double totalCatalogue;

  final double negociation;
  final double remise;
  final String? remiseLibelle;

  final double valeurCadeaux;

  /// Libellés des produits offerts (« 1 × Savon »).
  final List<String> cadeaux;

  final double total;
  final double? montantPaye;
  final double solde;
  final String modePaiement;
  final String devise;

  /// Référence locale de la vente (traçabilité).
  final int? venteId;

  /// Nom de fichier du PDF : `facture-VTE-20261107-0001.pdf`.
  String get nomFichier {
    final String base = numero.trim().isEmpty ? 'facture' : numero.trim();
    return 'facture-${base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}.pdf';
  }

  bool get aDesRemises => negociation > 0.009 || remise > 0.009;

  /// Message professionnel prêt à envoyer au client.
  String messageWhatsApp() {
    final StringBuffer sb = StringBuffer();
    final String nomClient =
        (clientNom ?? '').trim().isEmpty ? 'cher client' : clientNom!.trim();
    sb.write('Bonjour $nomClient, merci pour votre achat chez '
        '${etablissement.nomAffiche}. ');
    sb.write('Votre facture n° $numero du '
        '${DateFormat('dd/MM/yyyy').format(date)} ');
    sb.write('d\'un montant de ${formatMontant(total)} $devise. ');
    sb.write('Merci pour votre confiance.');
    return sb.toString();
  }
}

/// Génère et partage les factures de vente (A4).
///
/// Singleton : `FactureVenteService.instance`.
class FactureVenteService {
  FactureVenteService._();

  static final FactureVenteService instance = FactureVenteService._();

  /// Où le dernier PDF est allé (feuille de partage, téléchargement,
  /// enregistrement sur le disque). Lu par les écrans pour afficher un message
  /// exact — par exemple le chemin du fichier sur ordinateur.
  ResultatPartage? dernierPartage;

  /// Couleur de la marque sur le document.
  static const PdfColor _marine = PdfColor.fromInt(0xFF1F3864);
  static const PdfColor _orange = PdfColor.fromInt(0xFFF08A4B);

  /// 🧾 MODULE 27 — UNE SEULE NUMÉROTATION POUR TOUTES LES VENTES.
  ///
  /// Format identique à celui du serveur (`VTE-AAAAMMJJ-NNNN`, migration 000009) :
  ///   • la caisse en ligne reçoit son numéro de `rpc_vente_valider` ;
  ///   • la vente hors ligne (téléphone) construit le sien ICI, avec le même
  ///     préfixe, pour qu'un client ne voie jamais deux formats différents.
  ///
  /// [sequence] est l'identifiant local de la vente : il est unique et
  /// strictement croissant, ce qui garantit qu'un même numéro ne peut pas être
  /// réutilisé — même hors connexion.
  static String numeroVente({
    required int sequence,
    DateTime? date,
    String prefixe = 'VTE',
  }) {
    final DateTime jour = date ?? DateTime.now();
    final String mois = jour.month.toString().padLeft(2, '0');
    final String j = jour.day.toString().padLeft(2, '0');
    final String suite = sequence < 0 ? '0' : sequence.toString();
    return '$prefixe-${jour.year}$mois$j-${suite.padLeft(4, '0')}';
  }

  // ---------------------------------------------------------------------------
  // CONSTRUCTION DU DOCUMENT
  // ---------------------------------------------------------------------------

  /// Construit le PDF (A4). Une seule fonction de mise en page pour toute
  /// l'application : caisse, New Sale, historique.
  Future<Uint8List> construire(DonneesFacture d) async {
    final pw.Document document = pw.Document(
      title: 'Facture ${d.numero}',
      author: d.etablissement.nomAffiche,
      subject: 'Facture de vente',
    );

    final pw.Font base = await PdfGoogleFonts.robotoRegular();
    final pw.Font gras = await PdfGoogleFonts.robotoBold();
    final pw.Font italique = await PdfGoogleFonts.robotoItalic();
    final pw.MemoryImage? logo = await _chargerLogo(d.etablissement.logoUrl);

    final pw.ThemeData theme = pw.ThemeData.withFont(
      base: base,
      bold: gras,
      italic: italique,
    );

    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(38, 34, 38, 46),
        footer: (pw.Context context) => _piedDePage(context, d),
        build: (pw.Context context) => <pw.Widget>[
          _entete(d, logo),
          pw.SizedBox(height: 18),
          _blocParties(d),
          pw.SizedBox(height: 18),
          _tableau(d),
          pw.SizedBox(height: 14),
          _recapitulatif(d),
          if (d.cadeaux.isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 12),
            _blocCadeaux(d),
          ],
        ],
      ),
    );

    return document.save();
  }

  // ---------------------------------------------------------------------------
  // EN-TÊTE
  // ---------------------------------------------------------------------------

  pw.Widget _entete(DonneesFacture d, pw.MemoryImage? logo) {
    return pw.Column(
      children: <pw.Widget>[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            // Bloc établissement
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  if (logo != null) ...<pw.Widget>[
                    pw.Container(
                      width: 54,
                      height: 54,
                      padding: const pw.EdgeInsets.all(2),
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(4),
                        border: pw.Border.all(color: PdfColors.grey400),
                      ),
                      child: pw.Image(logo, fit: pw.BoxFit.contain),
                    ),
                    pw.SizedBox(width: 12),
                  ],
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        pw.Text(
                          d.etablissement.nomAffiche.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: _marine,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        ...d.etablissement.lignesAdresse.map(
                          (String ligne) => pw.Text(
                            ligne,
                            style: const pw.TextStyle(
                                fontSize: 8.5, color: PdfColors.grey700),
                          ),
                        ),
                        if (d.etablissement.telephone != null)
                          pw.Text(
                            'Tél. ${d.etablissement.telephone}',
                            style: const pw.TextStyle(
                                fontSize: 8.5, color: PdfColors.grey700),
                          ),
                        if (d.etablissement.email != null)
                          pw.Text(
                            d.etablissement.email!,
                            style: const pw.TextStyle(
                                fontSize: 8.5, color: PdfColors.grey700),
                          ),
                        // Mentions légales : UNIQUEMENT si renseignées.
                        if (d.etablissement.rccm != null)
                          pw.Text(
                            'RCCM : ${d.etablissement.rccm}',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        if (d.etablissement.idNational != null)
                          pw.Text(
                            'ID national : ${d.etablissement.idNational}',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            // Bloc titre
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                pw.Text(
                  'FACTURE',
                  style: pw.TextStyle(
                    fontSize: 26,
                    fontWeight: pw.FontWeight.bold,
                    color: _marine,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.Container(width: 62, height: 3, color: _orange),
                pw.SizedBox(height: 6),
                pw.Text(
                  d.numero,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  DateFormat('dd/MM/yyyy  HH:mm').format(d.date),
                  style: const pw.TextStyle(
                      fontSize: 8.5, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: d.statut.couleur,
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  child: pw.Text(
                    d.statut.libelle.toUpperCase(),
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(height: 1.2, color: _marine),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // CLIENT
  // ---------------------------------------------------------------------------

  pw.Widget _blocParties(DonneesFacture d) {
    final bool aClient = (d.clientNom ?? '').trim().isNotEmpty ||
        (d.clientTelephone ?? '').trim().isNotEmpty ||
        (d.clientAdresse ?? '').trim().isNotEmpty;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(
          flex: 3,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  'FACTURÉ À',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                    letterSpacing: 0.6,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  aClient
                      ? ((d.clientNom ?? '').trim().isEmpty
                          ? 'Client'
                          : d.clientNom!.trim())
                      : 'Client comptant',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                if ((d.clientTelephone ?? '').trim().isNotEmpty)
                  pw.Text(d.clientTelephone!.trim(),
                      style: const pw.TextStyle(fontSize: 8.5)),
                if ((d.clientAdresse ?? '').trim().isNotEmpty)
                  pw.Text(d.clientAdresse!.trim(),
                      style: const pw.TextStyle(fontSize: 8.5)),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                'MODE DE PAIEMENT',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700,
                  letterSpacing: 0.6,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                d.modePaiement,
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              if (d.montantPaye != null)
                pw.Text(
                  'Payé : ${formatMontant(d.montantPaye!)} ${d.devise}',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
              if (d.solde > 0.009)
                pw.Text(
                  'Reste à payer : ${formatMontant(d.solde)} ${d.devise}',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red800,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TABLEAU DES ARTICLES
  // ---------------------------------------------------------------------------

  pw.Widget _tableau(DonneesFacture d) {
    final List<List<String>> lignes = d.lignes.map((LigneFacture l) {
      return <String>[
        l.designation,
        _nombre(l.quantite),
        l.unite,
        formatMontant(l.prixUnitaire),
        l.estCadeau ? 'OFFERT' : formatMontant(l.total),
      ];
    }).toList(growable: false);

    return pw.Table(
      columnWidths: <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(4.2),
        1: const pw.FixedColumnWidth(46),
        2: const pw.FixedColumnWidth(54),
        3: const pw.FixedColumnWidth(74),
        4: const pw.FixedColumnWidth(82),
      },
      children: <pw.TableRow>[
        // En-tête
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _marine),
          children: <pw.Widget>[
            _cellule('DÉSIGNATION', gras: true, clair: true),
            _cellule('QTÉ', gras: true, clair: true, droite: true),
            _cellule('UNITÉ', gras: true, clair: true),
            _cellule('P.U.', gras: true, clair: true, droite: true),
            _cellule('TOTAL', gras: true, clair: true, droite: true),
          ],
        ),
        ...lignes.asMap().entries.map((MapEntry<int, List<String>> e) {
          final bool pair = e.key.isOdd;
          final bool offert = e.value[4] == 'OFFERT';
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: pair ? PdfColors.grey100 : PdfColors.white,
            ),
            children: <pw.Widget>[
              _cellule(e.value[0]),
              _cellule(e.value[1], droite: true),
              _cellule(e.value[2]),
              _cellule(e.value[3], droite: true),
              _cellule(
                e.value[4],
                droite: true,
                gras: true,
                couleur: offert ? PdfColors.green800 : null,
              ),
            ],
          );
        }),
      ],
      border: pw.TableBorder.symmetric(
        inside: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
    );
  }

  pw.Widget _cellule(
    String texte, {
    bool gras = false,
    bool droite = false,
    bool clair = false,
    PdfColor? couleur,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        texte,
        textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: clair ? PdfColors.white : (couleur ?? PdfColors.black),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RÉCAPITULATIF
  // ---------------------------------------------------------------------------

  pw.Widget _recapitulatif(DonneesFacture d) {
    final List<pw.Widget> lignes = <pw.Widget>[];

    void ajouter(String libelle, String montant,
        {bool gras = false, PdfColor? couleur}) {
      lignes.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(libelle,
                style: pw.TextStyle(
                  fontSize: gras ? 9.5 : 8.5,
                  fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
                )),
            pw.Text(montant,
                style: pw.TextStyle(
                  fontSize: gras ? 9.5 : 8.5,
                  fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: couleur,
                )),
          ],
        ),
      ));
    }

    if (d.aDesRemises) {
      ajouter('Sous-total (prix catalogue)',
          '${formatMontant(d.totalCatalogue > 0 ? d.totalCatalogue : d.total)} ${d.devise}');
      if (d.negociation > 0.009) {
        ajouter('Négociation accordée',
            '- ${formatMontant(d.negociation)} ${d.devise}',
            couleur: PdfColors.orange800);
      }
      if (d.remise > 0.009) {
        ajouter(
          'Réduction${d.remiseLibelle == null ? '' : ' (${d.remiseLibelle})'}',
          '- ${formatMontant(d.remise)} ${d.devise}',
          couleur: PdfColors.orange800,
        );
      }
    }

    ajouter('TOTAL À PAYER', '${formatMontant(d.total)} ${d.devise}',
        gras: true, couleur: _marine);

    return pw.Row(
      children: <pw.Widget>[
        pw.Expanded(flex: 3, child: pw.SizedBox()),
        pw.Expanded(
          flex: 2,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: lignes,
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _blocCadeaux(DonneesFacture d) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.green400, width: 0.8),
        color: PdfColors.green50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            'PRODUITS OFFERTS — NON FACTURÉS',
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green800,
              letterSpacing: 0.5,
            ),
          ),
          pw.SizedBox(height: 3),
          ...d.cadeaux.map((String c) => pw.Text(
                '• $c',
                style: const pw.TextStyle(fontSize: 8.5),
              )),
          if (d.valeurCadeaux > 0.009)
            pw.Text(
              'Valeur commerciale offerte : ${formatMontant(d.valeurCadeaux)} ${d.devise}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.green800),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PIED DE PAGE
  // ---------------------------------------------------------------------------

  pw.Widget _piedDePage(pw.Context context, DonneesFacture d) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        pw.Container(height: 0.6, color: PdfColors.grey400),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              d.etablissement.nomAffiche,
              style:
                  const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
            ),
            pw.Text(
              'Page ${context.pageNumber} / ${context.pagesCount}',
              style:
                  const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'Solution fournie par Biashara Group',
            style: pw.TextStyle(
              fontSize: 7.5,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey600,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // LOGO (chargé en mémoire, jamais bloquant)
  // ---------------------------------------------------------------------------

  Future<pw.MemoryImage?> _chargerLogo(String? url) async {
    final String? lien = url?.trim();
    if (lien == null || lien.isEmpty) return null;
    try {
      final http.Response reponse =
          await http.get(Uri.parse(lien)).timeout(const Duration(seconds: 6));
      if (reponse.statusCode != 200 || reponse.bodyBytes.isEmpty) return null;
      return pw.MemoryImage(reponse.bodyBytes);
    } catch (e) {
      debugPrint('FactureVenteService : logo ignoré ($e)');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  /// 💾 Téléchargement À LA DEMANDE (bouton « TÉLÉCHARGER LA FACTURE »).
  ///
  /// ⛔ CORRECTIF 14/11/2026 : plus aucun écran ne l'appelle tout seul. Après
  /// une vente, l'application ouvre la feuille d'actions ; c'est le patron qui
  /// décide de télécharger, d'envoyer sur WhatsApp ou d'imprimer. L'ancien
  /// enchaînement automatique ouvrait le PDF et déclenchait sous Windows
  /// « ce fichier ne contient pas d'application associée… ».
  ///
  /// Sur téléphone, la feuille de partage s'ouvre avec le PDF ; sur
  /// ordinateur le fichier est enregistré dans « Téléchargements/Biashara
  /// Yangu/Factures » SANS être ouvert ; sur le web, le navigateur télécharge
  /// le fichier. En cas de refus (permission, navigateur), on renvoie `false`.
  Future<bool> telecharger(DonneesFacture d) async {
    final ResultatPartage resultat = await partager(d);
    return resultat.ok;
  }

  /// 📎 Partage / enregistrement du PDF, avec le détail de ce qui s'est passé.
  ///
  /// [texte] accompagne le fichier sur mobile (corps du message WhatsApp) ;
  /// il est ignoré là où il n'existe pas de feuille de partage avec pièce
  /// jointe.
  Future<ResultatPartage> partager(
    DonneesFacture d, {
    String? texte,
  }) async {
    try {
      final Uint8List octets = await construire(d);
      final ResultatPartage resultat = await PartagePdf.partager(
        octets,
        nomFichier: d.nomFichier,
        texte: texte,
        sujet: 'Facture ${d.numero} — ${d.etablissement.nomAffiche}',
      );
      dernierPartage = resultat;
      return resultat;
    } catch (e) {
      debugPrint('FactureVenteService.partager : $e');
      const ResultatPartage echec = ResultatPartage.echec(
        'La facture n\'a pas pu être générée sur cet appareil. '
        'Essayez « Imprimer » puis « Enregistrer en PDF ».',
      );
      dernierPartage = echec;
      return echec;
    }
  }

  /// 🖨️ Impression directe (dialogue du système).
  Future<bool> imprimer(DonneesFacture d) async {
    try {
      final Uint8List octets = await construire(d);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => octets,
        name: d.nomFichier,
      );
      return true;
    } catch (e) {
      debugPrint('FactureVenteService.imprimer : $e');
      return false;
    }
  }

  /// 📎 Partage du PDF (feuille de partage : WhatsApp, e-mail, Drive…).
  Future<bool> partagerPdf(DonneesFacture d) async {
    final ResultatPartage resultat = await partager(d);
    return resultat.ok;
  }

  /// 💬 Envoie la facture au client sur WhatsApp — LE FICHIER, PAS LE TEXTE.
  ///
  /// 📱 Mobile : la feuille de partage s'ouvre avec le PDF joint et le message
  ///    du client ; l'utilisateur choisit WhatsApp puis le contact. C'est le
  ///    seul moyen d'envoyer réellement un fichier (un lien `wa.me` ne
  ///    transporte que du texte).
  /// 🖥️ Ordinateur : le PDF est enregistré (WhatsApp Desktop n'accepte pas de
  ///    pièce jointe par lien) puis la conversation du client s'ouvre avec le
  ///    message et le nom du fichier à joindre.
  Future<bool> envoyerParWhatsApp(
    DonneesFacture d, {
    required String telephone,
    bool pdfDejaTelecharge = true,
  }) async {
    final String numero = normaliserTelephone(telephone);
    final String message = d.messageWhatsApp();

    // 1. Le fichier d'abord.
    final ResultatPartage partage = await partager(d, texte: message);

    // 2. Feuille de partage (mobile/web) : WhatsApp est dans la liste, avec le
    //    PDF joint. On n'ouvre PAS `wa.me` en plus, sinon l'utilisateur
    //    enverrait un texte sans fichier.
    if (partage.fichierJoint && partage.mode != ModePartage.enregistre) {
      return true;
    }
    if (!partage.ok) return false;

    // 3. Ordinateur : conversation pré-remplie, fichier déjà sur le disque.
    final StringBuffer texte = StringBuffer(message);
    if (partage.chemin != null) {
      texte.write('\n\nLe PDF est enregistré sur cet appareil : '
          '${partage.chemin}');
    }
    return PartagePdf.whatsApp(numero, texte: texte.toString());
  }

  /// Conserve les chiffres, ajoute l'indicatif RDC (243) si le numéro est
  /// saisi en local (`09…` / `8…`).
  static String normaliserTelephone(String brut) {
    String chiffres = brut.replaceAll(RegExp(r'[^0-9]'), '');
    if (chiffres.isEmpty) return '';
    if (chiffres.startsWith('00')) chiffres = chiffres.substring(2);
    if (chiffres.startsWith('0')) chiffres = '243${chiffres.substring(1)}';
    if (!chiffres.startsWith('243') && chiffres.length == 9) {
      chiffres = '243$chiffres';
    }
    return chiffres;
  }

  /// « 12 » pour une quantité entière, « 1,5 » sinon.
  static String _nombre(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  // ---------------------------------------------------------------------------
  // AIDES POUR LES ÉCRANS
  // ---------------------------------------------------------------------------

  /// Construit les données d'une vente à partir d'un récapitulatif serveur
  /// (`VenteEnregistree`) — caisse ET New Sale passent par ici.
  Future<DonneesFacture> depuisVente({
    required String numero,
    required DateTime date,
    required List<LigneFacture> lignes,
    required double total,
    required String modePaiement,
    StatutFacture statut = StatutFacture.payee,
    String? clientNom,
    String? clientTelephone,
    String? clientAdresse,
    double totalCatalogue = 0,
    double negociation = 0,
    double remise = 0,
    String? remiseLibelle,
    double valeurCadeaux = 0,
    List<String> cadeaux = const <String>[],
    double? montantPaye,
    double solde = 0,
    int? venteId,
  }) async {
    final Etablissement etablissement =
        await EtablissementService.instance.charger();
    return DonneesFacture(
      numero: numero,
      date: date,
      etablissement: etablissement,
      lignes: lignes,
      total: total,
      modePaiement: modePaiement,
      statut: statut,
      clientNom: clientNom,
      clientTelephone: clientTelephone,
      clientAdresse: clientAdresse,
      totalCatalogue: totalCatalogue,
      negociation: negociation,
      remise: remise,
      remiseLibelle: remiseLibelle,
      valeurCadeaux: valeurCadeaux,
      cadeaux: cadeaux,
      montantPaye: montantPaye,
      solde: solde,
      venteId: venteId,
      devise: etablissement.devise,
    );
  }

  /// Demande le numéro WhatsApp du client (si absent) puis envoie LE FICHIER.
  ///
  /// Sur mobile, c'est la feuille de partage qui porte le PDF ; le numéro sert
  /// de repli quand aucune application de partage n'est disponible.
  Future<bool> proposerEnvoiWhatsApp(
    BuildContext context,
    DonneesFacture d,
  ) async {
    String? numero = d.clientTelephone;

    final String? saisie = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => _DialogueWhatsApp(
        numeroInitial: numero,
        nomClient: d.clientNom,
      ),
    );
    if (saisie == null) return false;
    numero = saisie;

    return envoyerParWhatsApp(d, telephone: numero);
  }
}

/// Saisie / confirmation du numéro du client avant l'envoi WhatsApp.
class _DialogueWhatsApp extends StatefulWidget {
  const _DialogueWhatsApp({this.numeroInitial, this.nomClient});

  final String? numeroInitial;
  final String? nomClient;

  @override
  State<_DialogueWhatsApp> createState() => _DialogueWhatsAppState();
}

class _DialogueWhatsAppState extends State<_DialogueWhatsApp> {
  late final TextEditingController _controleur =
      TextEditingController(text: widget.numeroInitial ?? '');
  String? _erreur;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String nom = (widget.nomClient ?? '').trim();
    return AlertDialog(
      title: Text(nom.isEmpty ? 'Envoyer par WhatsApp' : 'Envoyer à $nom'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Le PDF est enregistré sur l\'appareil, puis WhatsApp s\'ouvre avec '
            'le message pré-rempli : joignez le fichier depuis vos '
            'téléchargements. Sur téléphone, la feuille de partage s\'ouvre '
            'directement avec le PDF.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controleur,
            keyboardType: TextInputType.phone,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Numéro WhatsApp du client',
              hintText: '09… ou +243…',
              errorText: _erreur,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: () {
            final String numero =
                FactureVenteService.normaliserTelephone(_controleur.text);
            if (numero.length < 9) {
              setState(() =>
                  _erreur = 'Numéro invalide : indiquez au moins 9 chiffres.');
              return;
            }
            Navigator.of(context).pop(_controleur.text);
          },
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Ouvrir WhatsApp'),
        ),
      ],
    );
  }
}
