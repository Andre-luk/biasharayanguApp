// lib/services/facture_abonnement_service.dart
//
// 🧩 CORRECTIF 67 — FACTURES D'ABONNEMENT TRAÇABLES.
//
// Façade Dart des RPC livrées par la migration 67 :
//   • `rpc_abonnement_factures_lister`             → consulter ;
//   • `rpc_abonnement_factures_a_envoyer`          → ce qui reste à envoyer ;
//   • `rpc_abonnement_facture_generer`             → éditer (Finance/Super) ;
//   • `rpc_abonnement_facture_marquer_envoyee`     → tracer l'envoi WhatsApp ;
//   • `rpc_abonnement_facture_annuler`             → annuler (motif obligatoire) ;
//   • `rpc_abonnement_factures_rattraper`          → réparer l'historique.
//
// ⚠️ Les factures AUTOMATIQUES ne passent pas par ici : elles sont écrites en
// base par un déclencheur, à CHAQUE encaissement, quel que soit le rôle de
// celui qui encaisse. C'est délibéré — la facture est la contrepartie de
// l'argent reçu, elle ne doit pas dépendre du bon vouloir de celui qui le
// reçoit. Le service ne fait que les lire, les envoyer et les tracer.
//
// ⚠️ Aucune écriture directe sur la table : la migration n'accorde AUCUNE
// policy d'écriture (une facture réécrite après coup ne prouverait plus rien).

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:biashara_yangu/models/facture_abonnement.dart';
import 'package:biashara_yangu/utils/fichiers_locaux.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
// ⚠️ Import PRÉFIXÉ : la classe expose elle-même une méthode `lienWhatsApp`
// (qui compose le récapitulatif de la facture). Sans préfixe, l'appel
// s'adresserait à la méthode elle-même — une récursion infinie.
import 'package:biashara_yangu/utils/geo_utils.dart' as geo;
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier d'une facture d'abonnement.
class FactureAbonnementException implements Exception {
  const FactureAbonnementException(this.message, {this.type = TypeErreurFacture.inconnu});

  /// Message déjà rédigé en français, affichable tel quel.
  final String message;

  final TypeErreurFacture type;

  @override
  String toString() => message;
}

/// Nature de l'échec, pour que l'écran réagisse correctement.
enum TypeErreurFacture {
  /// La base n'a pas encore reçu la migration 67.
  nonDeploye,

  /// Rôle insuffisant (ex. un vendeur qui voudrait annuler).
  droits,

  /// Aucun numéro WhatsApp utilisable pour ce client.
  telephone,

  /// La facture ne peut plus être modifiée (déjà annulée, ou elle atteste
  /// un versement réel).
  verrouillee,

  introuvable,
  validation,
  reseau,
  inconnu,
}

/// Ce qui reste à envoyer, avec le compte pour le badge de l'écran.
class FacturesAEnvoyer {
  const FacturesAEnvoyer({this.total = 0, this.factures = const <FactureAbonnement>[]});

  final int total;
  final List<FactureAbonnement> factures;

  bool get vide => total <= 0;
}

/// Résultat d'une réparation d'historique.
class ResultatRattrapageFactures {
  const ResultatRattrapageFactures({this.creees = 0, this.ignorees = 0});

  final int creees;
  final int ignorees;

  factory ResultatRattrapageFactures.depuisJson(Map<String, dynamic> map) {
    return ResultatRattrapageFactures(
      creees: parseInt(map['creees']),
      ignorees: parseInt(map['ignorees']),
    );
  }
}

/// Service des factures d'abonnement.
class FactureAbonnementService {
  FactureAbonnementService._();

  static final FactureAbonnementService instance = FactureAbonnementService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // LECTURE
  // ---------------------------------------------------------------------------

  /// Liste les factures visibles par l'appelant.
  ///
  /// La visibilité est décidée par le serveur (`facture_abonnement_visible`) :
  /// la plateforme voit tout, un client ses propres factures, un agent de
  /// terrain celles des comptes qu'il suit.
  Future<List<FactureAbonnement>> lister({
    String? entrepriseId,
    int limite = 100,
    bool inclureAnnulees = false,
  }) {
    return _executer(() async {
      final dynamic brut = await _client.rpc(
        'rpc_abonnement_factures_lister',
        params: <String, dynamic>{
          'p_entreprise_id': entrepriseId,
          'p_limite': limite,
          'p_inclure_annulees': inclureAnnulees,
        },
      );

      return _factures(brut);
    }, messageEchec: 'Impossible de lire les factures. Vérifiez votre connexion internet.');
  }

  /// Factures émises et pas encore envoyées (badge de l'écran).
  Future<FacturesAEnvoyer> aEnvoyer({String? entrepriseId}) {
    return _executer(() async {
      final dynamic brut = await _client.rpc(
        'rpc_abonnement_factures_a_envoyer',
        params: <String, dynamic>{'p_entreprise_id': entrepriseId},
      );

      final Map<String, dynamic>? map = parseMap(brut);
      if (map == null) return const FacturesAEnvoyer();

      final int total = parseInt(map['total']);
      final List<FactureAbonnement> factures = _factures(map['factures']);

      return FacturesAEnvoyer(
        // Le compte vient du serveur : il reste juste même si la liste est
        // tronquée à 200 lignes.
        total: total > 0 ? total : factures.length,
        factures: factures,
      );
    }, messageEchec: 'Impossible de lire les factures à envoyer.');
  }

  // ---------------------------------------------------------------------------
  // ÉCRITURES (toujours par RPC : la table est en lecture seule)
  // ---------------------------------------------------------------------------

  /// Édite une facture à la main (Finance ou Super Admin).
  ///
  /// À utiliser pour un état de compte ou une facture d'échéance. Les factures
  /// d'encaissement, elles, sont produites automatiquement.
  Future<FactureAbonnement?> generer(
    String entrepriseId, {
    String type = 'MANUELLE',
    String? note,
  }) {
    return _executer(() async {
      final dynamic brut = await _client.rpc(
        'rpc_abonnement_facture_generer',
        params: <String, dynamic>{
          'p_entreprise_id': entrepriseId,
          'p_type': type,
          'p_note': note,
        },
      );

      final String? numero = parseMap(brut)?['numero']?.toString();
      if (numero == null || numero.isEmpty) return null;

      // On relit la fiche complète pour disposer de tous les montants : la
      // RPC ne renvoie que l'identifiant et le numéro.
      final List<FactureAbonnement> recentes = await lister(
        entrepriseId: entrepriseId,
        limite: 1,
      );

      return recentes.isEmpty ? null : recentes.first;
    }, messageEchec: 'Impossible d\'éditer la facture.');
  }

  /// Trace l'envoi d'une facture (qui, quand, à quel numéro, par quel canal).
  ///
  /// ⚠️ On ne peut PAS savoir depuis l'application que le message a été
  /// réellement délivré : WhatsApp est une application tierce. On trace donc
  /// l'ENVOI demandé, ce qui est le maximum honnête — et suffisant pour
  /// savoir qui a présenté la facture au client.
  Future<void> marquerEnvoyee(
    String factureId, {
    String? telephone,
    String canal = 'whatsapp',
  }) {
    return _executer(() async {
      await _client.rpc(
        'rpc_abonnement_facture_marquer_envoyee',
        params: <String, dynamic>{
          'p_facture_id': factureId,
          'p_telephone': telephone,
          'p_canal': canal,
        },
      );
    }, messageEchec: 'Impossible de tracer l\'envoi de la facture.');
  }

  /// Annule une facture. Le motif est OBLIGATOIRE et conservé avec la facture.
  ///
  /// Le serveur refuse si la facture atteste d'un versement réel : faire
  /// disparaître la preuve d'un argent reçu est exactement le défaut que cette
  /// facture existe pour empêcher.
  Future<void> annuler(String factureId, String motif) {
    return _executer(() async {
      await _client.rpc(
        'rpc_abonnement_facture_annuler',
        params: <String, dynamic>{
          'p_facture_id': factureId,
          'p_motif': motif,
        },
      );
    }, messageEchec: 'Impossible d\'annuler la facture.');
  }

  /// Reconstruit les factures manquantes depuis l'historique des encaissements.
  ///
  /// Sert aux encaissements antérieurs au correctif 67, et à réparer un échec
  /// du déclencheur. Plateforme uniquement.
  Future<ResultatRattrapageFactures> rattraper({String? entrepriseId}) {
    return _executer(() async {
      final dynamic brut = await _client.rpc(
        'rpc_abonnement_factures_rattraper',
        params: <String, dynamic>{'p_entreprise_id': entrepriseId},
      );

      final Map<String, dynamic>? map = parseMap(brut);
      if (map == null) return const ResultatRattrapageFactures();

      return ResultatRattrapageFactures.depuisJson(map);
    }, messageEchec: 'Impossible de réparer l\'historique des factures.');
  }

  // ---------------------------------------------------------------------------
  // ENVOI WHATSAPP
  // ---------------------------------------------------------------------------

  /// Lien `wa.me` pré-rempli du récapitulatif, ou `null` si aucun numéro
  /// utilisable n'est connu.
  String? lienWhatsApp(
    FactureAbonnement facture, {
    String? nomEtablissement,
  }) {
    return geo.lienWhatsApp(
      facture.clientTelephone,
      message: messageWhatsAppFacture(facture, nomEtablissement: nomEtablissement),
    );
  }

  /// Ouvre WhatsApp sur le numéro du client, puis trace l'envoi.
  ///
  /// Renvoie `true` si WhatsApp a bien été ouvert. La trace est écrite APRÈS
  /// l'ouverture : on n'inscrit pas « envoyée » pour un envoi qui n'a pas eu
  /// lieu. Si la trace échoue, l'ouverture reste valable — on ne fait pas
  /// échouer l'action de l'utilisateur pour un problème de journalisation.
  Future<bool> envoyerParWhatsApp(
    FactureAbonnement facture, {
    String? nomEtablissement,
  }) async {
    final String? lien = lienWhatsApp(facture, nomEtablissement: nomEtablissement);

    if (lien == null) {
      throw const FactureAbonnementException(
        'Aucun numéro WhatsApp connu pour ce client. Renseignez le téléphone du '
        'propriétaire, puis renvoyez la facture.',
        type: TypeErreurFacture.telephone,
      );
    }

    final Uri? uri = Uri.tryParse(lien);
    if (uri == null) {
      throw const FactureAbonnementException(
        'Le numéro de ce client est inutilisable.',
        type: TypeErreurFacture.telephone,
      );
    }

    final bool ouvert = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ouvert) {
      throw const FactureAbonnementException(
        'WhatsApp n\'a pas pu être ouvert sur cet appareil.',
        type: TypeErreurFacture.reseau,
      );
    }

    try {
      await marquerEnvoyee(
        facture.id,
        telephone: facture.clientTelephone,
        canal: 'whatsapp',
      );
    } catch (e) {
      debugPrint('FactureAbonnementService (trace d\'envoi) : $e');
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------------

  /// Construit le PDF A4 de la facture.
  ///
  /// [chargerPolices] est désactivable pour les tests (évite tout accès réseau).
  Future<Uint8List> construirePDF(
    FactureAbonnement facture, {
    String nomEtablissement = 'Biashara Yangu',
    Uint8List? logo,
    bool chargerPolices = true,
  }) async {
    final pw.ThemeData? theme = chargerPolices ? await _chargerThemePdf() : null;
    final pw.Document document = pw.Document(theme: theme);

    // ⚠️ Toutes les chaînes sont formatées AVANT d'entrer dans le PDF : on ne
    // laisse aucune mise en forme dépendante de la locale se faire dans le
    // moteur de rendu.
    final String titre = 'FACTURE D\'ABONNEMENT';
    final String reference = facture.numero;
    final String emiseLe = formatDateHeure(facture.genereLe);
    final String nature = facture.libelleType;
    final String client = facture.nomAffiche;
    final String telephone = facture.clientTelephone ?? 'Non renseigné';
    final String periode = facture.libellePeriode;
    final String devise = facture.devise;

    final String installation = facture.installationAffichee;
    final String mensuel = facture.mensuelAffiche;
    final String total = facture.totalAffiche;
    final String avance = facture.avanceAffichee;
    final String regle = facture.regleAffiche;
    final String paye = facture.payeAffiche;
    final String solde = facture.soldeAffiche;
    final bool soldee = facture.estSoldee;
    final String? limiteComplement = facture.dateLimiteComplement == null
        ? null
        : formatDate(facture.dateLimiteComplement);

    final String emetteur = facture.resumeEmetteur;
    final String motifAnnulation = facture.estAnnulee
        ? (facture.note ?? 'Annulée')
        : '';

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 32, 30, 30),
        build: (pw.Context context) => <pw.Widget>[
          _entetePdf(titre, reference, emiseLe, nature, logo, nomEtablissement),
          pw.SizedBox(height: 16),
          _blocClient(client, telephone, periode, devise),
          pw.SizedBox(height: 16),
          _tableauTarifs(installation, mensuel),
          pw.SizedBox(height: 14),
          _tableauDecompte(total, avance, regle, paye),
          pw.SizedBox(height: 14),
          _encadreSolde(solde, soldee, limiteComplement),
          if (facture.estAnnulee) ...<pw.Widget>[
            pw.SizedBox(height: 12),
            _bandeauAnnulation(motifAnnulation),
          ],
          pw.SizedBox(height: 18),
          _blocTracabilite(emetteur, facture.resumeEnvoi),
          pw.SizedBox(height: 10),
          _mentionLegale(),
        ],
      ),
    );

    return document.save();
  }

  /// Enregistre le PDF dans les téléchargements. Renvoie le nom du fichier ou
  /// le chemin, selon la plateforme (`null` = téléchargement navigateur).
  Future<String?> exporterPDF(
    FactureAbonnement facture, {
    String nomEtablissement = 'Biashara Yangu',
  }) async {
    final Uint8List octets = await construirePDF(
      facture,
      nomEtablissement: nomEtablissement,
    );

    return enregistrerDansTelechargements(
      sousDossier: 'factures',
      nomFichier: nomFichierFacture(facture),
      octets: octets,
      mimeType: 'application/pdf',
    );
  }

  /// Partage le PDF (c'est ainsi qu'on joint la facture à WhatsApp : le lien
  /// `wa.me` transporte le texte, le partage transporte le document).
  Future<void> partagerPDF(
    FactureAbonnement facture, {
    String nomEtablissement = 'Biashara Yangu',
  }) async {
    final Uint8List octets = await construirePDF(
      facture,
      nomEtablissement: nomEtablissement,
    );

    await Printing.sharePdf(
      bytes: octets,
      filename: nomFichierFacture(facture),
    );
  }

  /// Ouvre l'aperçu d'impression du PDF.
  Future<void> imprimerPDF(
    FactureAbonnement facture, {
    String nomEtablissement = 'Biashara Yangu',
  }) async {
    final Uint8List octets = await construirePDF(
      facture,
      nomEtablissement: nomEtablissement,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => octets,
      name: nomFichierFacture(facture),
      format: PdfPageFormat.a4,
    );
  }

  /// Nom de fichier lisible et unique : `facture_FA-2026-000001.pdf`.
  static String nomFichierFacture(FactureAbonnement facture) {
    final String base = facture.numero
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-')
        .replaceAll(RegExp('-+'), '-');
    return 'facture_${base.isEmpty ? facture.id : base}.pdf';
  }

  // ---------------------------------------------------------------------------
  // PIÈCES INTERNES
  // ---------------------------------------------------------------------------

  static List<FactureAbonnement> _factures(dynamic valeur) {
    final List<Map<String, dynamic>> lignes = parseMapList(valeur);
    return lignes.map(FactureAbonnement.fromMap).toList(growable: false);
  }

  Future<pw.ThemeData?> _chargerThemePdf() async {
    try {
      final pw.Font base = await PdfGoogleFonts.robotoRegular();
      final pw.Font gras = await PdfGoogleFonts.robotoBold();
      final pw.Font italique = await PdfGoogleFonts.robotoItalic();
      return pw.ThemeData.withFont(base: base, bold: gras, italic: italique);
    } catch (e) {
      // Sans réseau, on garde les polices de repli : une facture lisible vaut
      // mieux qu'une facture impossible à produire.
      debugPrint('FactureAbonnementService (polices PDF) : $e');
      return null;
    }
  }

  pw.Widget _entetePdf(
    String titre,
    String reference,
    String emiseLe,
    String nature,
    Uint8List? logo,
    String nomEtablissement,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        if (logo != null)
          pw.Container(
            width: 54,
            height: 54,
            margin: const pw.EdgeInsets.only(right: 12),
            child: pw.Image(pw.MemoryImage(logo)),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                nomEtablissement.toUpperCase(),
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(titre,
                  style: const pw.TextStyle(fontSize: 16, color: PdfColors.grey800)),
              pw.SizedBox(height: 4),
              pw.Text('N° $reference — $nature',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.Text('Émise le $emiseLe',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _blocClient(
    String client,
    String telephone,
    String periode,
    String devise,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          _lignePdf('Client', client),
          _lignePdf('Téléphone WhatsApp', telephone),
          _lignePdf('Période couverte', periode),
          _lignePdf('Devise', devise),
        ],
      ),
    );
  }

  pw.Widget _tableauTarifs(String installation, String mensuel) {
    return _tableau(
      titre: 'TARIFS DE RÉFÉRENCE',
      lignes: <List<String>>[
        <String>['Installation (le 1er mois est inclus)', installation],
        <String>['Abonnement par mois', mensuel],
      ],
    );
  }

  pw.Widget _tableauDecompte(
    String total,
    String avance,
    String regle,
    String paye,
  ) {
    return _tableau(
      titre: 'DÉCOMPTE DU MOIS',
      lignes: <List<String>>[
        <String>['Montant dû', total],
        <String>['Avance déjà versée', avance],
        <String>['Versement reçu', regle],
        <String>['Total payé à ce jour', paye],
      ],
      grasDerniereLigne: true,
    );
  }

  pw.Widget _tableau({
    required String titre,
    required List<List<String>> lignes,
    bool grasDerniereLigne = false,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(titre,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const <int, pw.TableColumnWidth>{
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(2),
          },
          children: <pw.TableRow>[
            for (int i = 0; i < lignes.length; i++)
              pw.TableRow(
                children: <pw.Widget>[
                  _cellulePdf(lignes[i][0], gras: i == lignes.length - 1 && grasDerniereLigne),
                  _cellulePdf(
                    lignes[i][1],
                    gras: i == lignes.length - 1 && grasDerniereLigne,
                    aligneDroite: true,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  pw.Widget _encadreSolde(
    String solde,
    bool soldee,
    String? limiteComplement,
  ) {
    final PdfColor fond = soldee ? PdfColors.green50 : PdfColors.orange50;
    final PdfColor bord = soldee ? PdfColors.green700 : PdfColors.orange800;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: fond,
        border: pw.Border.all(color: bord, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            soldee
                ? 'CYCLE ENTIÈREMENT RÉGLÉ — solde : $solde'
                : 'RESTE À PAYER : $solde',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: bord,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            soldee
                ? 'Aucun complément n\'est attendu : le premier mois est payé en entier.'
                : (limiteComplement == null
                    ? 'Le complément est attendu dans les meilleurs délais.'
                    : 'Le complément est attendu sous $delaiComplementJours jours, '
                        'soit avant le $limiteComplement.'),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
          ),
        ],
      ),
    );
  }

  pw.Widget _bandeauAnnulation(String motif) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.red50,
        border: pw.Border.all(color: PdfColors.red700, width: 0.8),
      ),
      child: pw.Text('FACTURE ANNULÉE — $motif',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.red800)),
    );
  }

  pw.Widget _blocTracabilite(String emetteur, String envoi) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text('TRAÇABILITÉ',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        _lignePdf('Facture générée par', emetteur),
        _lignePdf('Envoi', envoi),
      ],
    );
  }

  pw.Widget _mentionLegale() {
    return pw.Text(
      'Document établi automatiquement à partir des encaissements enregistrés. '
      'Il fait foi du montant reçu et du solde restant à la date d\'émission.',
      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
    );
  }

  pw.Widget _lignePdf(String libelle, String valeur) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.SizedBox(
            width: 130,
            child: pw.Text(libelle,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ),
          pw.Expanded(
            child: pw.Text(valeur, style: const pw.TextStyle(fontSize: 9.5)),
          ),
        ],
      ),
    );
  }

  pw.Widget _cellulePdf(String texte, {bool gras = false, bool aligneDroite = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        texte,
        textAlign: aligneDroite ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ERREURS
  // ---------------------------------------------------------------------------

  /// Extrait le message utile d'une erreur serveur au format `CODE|texte fr`.
  ///
  /// Même convention que les autres services du projet : le serveur lève
  /// `raise exception 'CODE|texte francais'` et seule la partie droite est
  /// montrée à l'utilisateur.
  static String messageErreur(String brut, {required String repli}) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return repli;
    return texte.substring(separateur + 1).trim();
  }

  /// Déduit la nature de l'échec du code serveur, pour adapter l'écran.
  static TypeErreurFacture typeDepuisMessage(String? brut) {
    final String code = (brut ?? '').toUpperCase();

    if (code.contains('PGRST202') || code.contains('NON_DEPLOYE')) {
      return TypeErreurFacture.nonDeploye;
    }
    if (code.contains('ACCES_REFUSE')) return TypeErreurFacture.droits;
    if (code.contains('SANS_TELEPHONE')) return TypeErreurFacture.telephone;
    if (code.contains('FACTURE_ATTESTE') ||
        code.contains('DEJA_ANNULEE') ||
        code.contains('FACTURE_ANNULEE')) {
      return TypeErreurFacture.verrouillee;
    }
    if (code.contains('FACTURE_INTROUVABLE')) return TypeErreurFacture.introuvable;
    if (code.contains('MOTIF_REQUIS') ||
        code.contains('CANAL_INVALIDE') ||
        code.contains('ENTREPRISE_INTROUVABLE')) {
      return TypeErreurFacture.validation;
    }
    return TypeErreurFacture.inconnu;
  }

  Future<T> _executer<T>(
    Future<T> Function() action, {
    required String messageEchec,
  }) async {
    try {
      return await action();
    } on FactureAbonnementException {
      rethrow;
    } catch (e) {
      final String brut = e is PostgrestException ? e.message : e.toString();
      debugPrint('FactureAbonnementService : $e');
      throw FactureAbonnementException(
        messageErreur(brut, repli: messageEchec),
        type: typeDepuisMessage(brut),
      );
    }
  }
}
