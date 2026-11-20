// lib/services/analyse_entreprise_service.dart
//
// 📊 MIGRATION 175 — RAPPORT TÉLÉCHARGEABLE PAR ENTREPRISE.
//
// Produit hebdomadaire / mensuel :
//   • meilleur produit, meilleur jour, meilleur moment ;
//   • conseils de croissance à long terme (calculés sur les ventes réelles) ;
//   • SIMULATION : « si ce produit progresse de 10 %, la boutique gagne X ».
//
// Tout le calcul est fait côté serveur par `rpc_rapport_entreprise_analyse`
// (le téléphone n'a pas forcément toutes les ventes) ; ici on ne fait que
// charger, formater et exporter en PDF.

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:biashara_yangu/models/analyse_entreprise.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/fichiers_locaux.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur lisible (message déjà en français) levée par le service.
class AnalyseEntrepriseException implements Exception {
  AnalyseEntrepriseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AnalyseEntrepriseService {
  AnalyseEntrepriseService._();

  static final AnalyseEntrepriseService instance = AnalyseEntrepriseService._();

  /// Sous-dossier d'enregistrement des rapports.
  static const String sousDossier = 'Biashara Yangu/Rapports';

  // ---------------------------------------------------------------------------
  // 1. Périodes
  // ---------------------------------------------------------------------------

  /// Semaine écoulée : les 7 derniers jours (aujourd'hui inclus).
  static (DateTime, DateTime) periodeSemaine({DateTime? reference}) {
    final DateTime fin = _jour(reference ?? DateTime.now());
    return (_reculer(fin, 6), fin);
  }

  /// Mois écoulé : les 30 derniers jours (aujourd'hui inclus).
  static (DateTime, DateTime) periodeMois({DateTime? reference}) {
    final DateTime fin = _jour(reference ?? DateTime.now());
    return (_reculer(fin, 29), fin);
  }

  /// Reculer de [jours] JOURS CALENDAIRES (jamais 24 h × n).
  ///
  /// `fin.subtract(Duration(days: n))` traversait les changements d'heure :
  /// la date de début ressortait à 01:00 et la période comptait 29 jours.
  static DateTime _reculer(DateTime jour, int jours) =>
      DateTime(jour.year, jour.month, jour.day - jours);

  static DateTime _jour(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String nomFichier(DateTime debut, DateTime fin) =>
      'analyse_${_dateIso(debut).replaceAll('-', '')}_'
      '${_dateIso(fin).replaceAll('-', '')}.pdf';

  // ---------------------------------------------------------------------------
  // 2. Chargement
  // ---------------------------------------------------------------------------

  /// Charge l'analyse d'une entreprise sur [debut] → [fin] (bornes incluses).
  Future<AnalyseEntreprise> charger({
    required String entrepriseId,
    required DateTime debut,
    required DateTime fin,
  }) async {
    try {
      final dynamic reponse = await SupabaseService.instance.client.rpc(
        'rpc_rapport_entreprise_analyse',
        params: <String, dynamic>{
          'p_entreprise_id': entrepriseId,
          'p_debut': _dateIso(debut),
          'p_fin': _dateIso(fin),
        },
      );
      final AnalyseEntreprise analyse = AnalyseEntreprise.depuisJson(
        reponse,
        entrepriseId: entrepriseId,
      );
      return analyse;
    } catch (e) {
      throw AnalyseEntrepriseException(messageErreur(e));
    }
  }

  /// Message français à partir d'une erreur serveur `CODE|message`.
  static String messageErreur(Object erreur) {
    final String brut = erreur.toString();
    final int barre = brut.indexOf('|');
    if (barre > 0 && barre < brut.length - 1) {
      final String code = brut.substring(0, barre);
      final String message = brut.substring(barre + 1).trim();
      // Certains codes remontent sous la forme `Exception: CODE|message`.
      if (code.length <= 40 && !code.contains(' ')) {
        return message;
      }
    }
    if (brut.contains('PGRST202') ||
        brut.contains('Could not find the function') ||
        brut.contains('rpc_rapport_entreprise_analyse')) {
      return 'Le rapport n\'est pas encore disponible : exécutez la migration '
          '175 dans Supabase, puis réessayez.';
    }
    if (brut.contains('SocketException') || brut.contains('ClientException')) {
      return 'Connexion impossible : vérifiez votre réseau, puis réessayez.';
    }
    debugPrint('AnalyseEntrepriseService : $brut');
    // ⛔ Ne JAMAIS masquer la cause : sans le message du serveur, personne ne
    // peut corriger (c'est exactement ce qui s'est produit avec l'ancien
    // « Impossible de produire le rapport pour le moment »).
    return 'Le serveur n\'a pas pu produire le rapport : ${_extrait(brut)}';
  }

  /// Message serveur raccourci (200 caractères) pour l'affichage.
  static String _extrait(String brut) {
    String texte = brut
        .replaceAll('PostgrestException(message: ', '')
        .replaceAll('Exception: ', '')
        .replaceAll('\n', ' ')
        .trim();
    if (texte.length > 200) {
      texte = '${texte.substring(0, 200)}…';
    }
    return texte.isEmpty ? 'erreur inconnue' : texte;
  }

  // ---------------------------------------------------------------------------
  // 3. PDF
  // ---------------------------------------------------------------------------

  /// Construit le PDF du rapport d'analyse.
  ///
  /// Polices par défaut d'Helvetica (aucun accès réseau → utilisable hors
  /// ligne, et compatible avec l'export web).
  Future<Uint8List> construirePDF(AnalyseEntreprise analyse) async {
    final pw.Document document = pw.Document();
    final String devise = analyse.devise;

    String m(dynamic valeur) => formatMontant(
          parseDouble(valeur),
          devise: devise,
        );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 34, 32, 38),
        header: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(
              'Rapport d\'analyse — ${analyse.entrepriseNom.isEmpty ? 'Entreprise' : analyse.entrepriseNom}',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green800,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Période : ${formatDate(analyse.debut)} → ${formatDate(analyse.fin)}'
              ' (${analyse.nombreDeJours} jours)',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Origine : ${analyse.libelleOrigines} · '
              '${analyse.nbProduits} produit(s) vendu(s)',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: PdfColors.grey400, height: 1),
          ],
        ),
        footer: (pw.Context context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              'Biashara Yangu — rapport généré le ${formatDate(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
        build: (pw.Context context) => <pw.Widget>[
          if (analyse.estVide)
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                'Aucune vente enregistrée sur cette période. Le rapport sera '
                'complet dès les premières ventes.',
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey700),
              ),
            )
          else ...<pw.Widget>[
            _titre('Chiffre d\'affaires'),
            _tableau(
              entetes: <String>['Indicateur', 'Valeur'],
              lignes: <List<String>>[
                <String>['Chiffre d\'affaires', m(analyse.totaux.ca)],
                <String>['Nombre de ventes', '${analyse.totaux.ventes}'],
                <String>[
                  'Articles vendus',
                  formatQuantite(analyse.totaux.articles)
                ],
                <String>[
                  'Panier moyen',
                  m(analyse.totaux.panierMoyen)
                ],
                if (analyse.totaux.marge > 0)
                  <String>['Marge brute estimée', m(analyse.totaux.marge)],
              ],
            ),
            _titre('Les trois repères de la période'),
            _tableau(
              entetes: <String>['Repère', 'Résultat', 'Montant'],
              lignes: <List<String>>[
                if (analyse.meilleurProduit != null)
                  <String>[
                    'Meilleur produit',
                    analyse.meilleurProduit!.nom,
                    m(analyse.meilleurProduit!.ca),
                  ],
                if (analyse.meilleurJour != null)
                  <String>[
                    'Meilleur jour',
                    analyse.meilleurJour!.jour,
                    m(analyse.meilleurJour!.ca),
                  ],
                if (analyse.meilleurMoment != null)
                  <String>[
                    'Meilleur moment',
                    analyse.meilleurMoment!.moment,
                    m(analyse.meilleurMoment!.ca),
                  ],
                if (analyse.meilleurProduit == null &&
                    analyse.meilleurJour == null &&
                    analyse.meilleurMoment == null)
                  <String>['—', 'Pas encore de tendance', '—'],
              ],
            ),
            if (analyse.topProduits.isNotEmpty) ...<pw.Widget>[
              _titre('Classement des produits — TOUS les produits, du meilleur '
                  'au moins vendu (${analyse.nbProduits})'),
              _tableau(
                entetes: <String>['#', 'Produit', 'Qté', 'CA', 'Part'],
                lignes: analyse.topProduits
                    .map((AnalyseProduit p) => <String>[
                          '${p.rang}',
                          p.nom,
                          formatQuantite(p.quantite),
                          m(p.ca),
                          '${p.part.toStringAsFixed(1)} %',
                        ])
                    .toList(),
              ),
            ],
            if (analyse.jours.isNotEmpty) ...<pw.Widget>[
              _titre('Chiffre d\'affaires par jour'),
              _tableau(
                entetes: <String>['Jour', 'CA', 'Ventes'],
                lignes: analyse.jours
                    .map((AnalyseJour j) => <String>[
                          j.jour,
                          m(j.ca),
                          '${j.ventes}',
                        ])
                    .toList(),
              ),
            ],
            if (analyse.moments.isNotEmpty) ...<pw.Widget>[
              _titre('Chiffre d\'affaires par moment de la journée'),
              _tableau(
                entetes: <String>['Moment', 'CA', 'Ventes'],
                lignes: analyse.moments
                    .map((AnalyseMoment m2) => <String>[
                          m2.moment,
                          m(m2.ca),
                          '${m2.ventes}',
                        ])
                    .toList(),
              ),
            ],
            if (analyse.conseils.isNotEmpty) ...<pw.Widget>[
              _titre('Conseils pour augmenter les revenus'),
              ...analyse.conseils.map(
                (AnalyseConseil c) => pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 6),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green50,
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.Text(
                        c.titre,
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green900,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        c.detail,
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (analyse.simulation != null &&
                !analyse.simulation!.estVide) ...<pw.Widget>[
              _titre('Projection : et si vous poussiez ce produit ?'),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.green700),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(
                      analyse.simulation!.message,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green900,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'CA du produit : ${m(analyse.simulation!.caActuel)} · '
                      'gain visé (+${analyse.simulation!.objectifPct.toStringAsFixed(0)} %) : '
                      '${m(analyse.simulation!.caSupplementaire)} · '
                      'CA projeté : ${m(analyse.simulation!.caProjete)}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey800),
                    ),
                  ],
                ),
              ),
            ],
            pw.SizedBox(height: 10),
            pw.Text(
              'Rapport calculé à partir des ventes réellement enregistrées '
              'dans l\'entreprise. Aucune donnée n\'est extrapolée.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _titre(String texte) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(
          texte,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey900,
          ),
        ),
      );

  pw.Widget _tableau({
    required List<String> entetes,
    required List<List<String>> lignes,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: entetes,
      data: lignes,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      headerStyle: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
      cellStyle: const pw.TextStyle(fontSize: 9, color: PdfColors.grey900),
      cellAlignments: <int, pw.Alignment>{
        0: pw.Alignment.centerLeft,
        for (int i = 1; i < entetes.length; i++) i: pw.Alignment.centerRight,
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    );
  }

  /// Génère le PDF et l'enregistre (navigateur sur le web, « Téléchargements »
  /// sur mobile / ordinateur). Renvoie le chemin du fichier, ou `null` sur le
  /// web (le fichier part dans les téléchargements du navigateur).
  Future<String?> exporterPDF(AnalyseEntreprise analyse) async {
    final Uint8List octets = await construirePDF(analyse);
    return enregistrerDansTelechargements(
      sousDossier: sousDossier,
      nomFichier: nomFichier(
        analyse.debut ?? DateTime.now(),
        analyse.fin ?? DateTime.now(),
      ),
      octets: octets,
      mimeType: 'application/pdf',
    );
  }
}
