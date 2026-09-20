// lib/services/rapport_service.dart
//
// MODULE 11 — RAPPORTS & EXPORTS.
//
// Chaîne complète du module :
//   1. GÉNÉRATION — `generer()` appelle `rpc_rapport_entreprise` ou
//      `rpc_rapport_plateforme` (selon l'espace du type demandé) et renvoie
//      un [ResultatRapport] : données + référence + empreinte SHA-256.
//   2. TRACABILITÉ — chaque génération et chaque export est enregistré par
//      `rpc_rapport_tracer` (registre `rapports_generes` + journal d'audit).
//   3. EXPORTS — `construirePDF` / `construireExcel` fabriquent les fichiers ;
//      `exporterPDF` / `exporterExcel` les enregistrent dans
//      « Téléchargements/rapports » ; `partagerPDF` / `imprimerPDF` passent
//      par la boîte de dialogue du système (package `printing`).
//
// Les PDF et Excel portent la RÉFÉRENCE et l'EMPREINTE de l'export : un
// document imprimé peut ainsi être relié à sa ligne du registre (« export
// signé et traçable »).
//
// ⚠️ Les contrôles de droits sont faits par le SERVEUR (voir la migration
// `20260916000012_module11_rapports.sql`) : un vendeur, qui n'a pas la page
// `rapports`, reçoit DROIT_REFUSE même s'il contournait l'interface.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/rapport.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart' show reponseRpcEnMap;
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/fichiers_locaux.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Nature d'une erreur de rapport (pour adapter l'interface).
enum TypeErreurRapport { droits, validation, reseau, inconnu }

/// Erreur métier du module Rapports (message déjà rédigé en français).
class RapportServiceException implements Exception {
  const RapportServiceException(
    this.message, {
    this.type = TypeErreurRapport.inconnu,
  });

  final String message;
  final TypeErreurRapport type;

  @override
  String toString() => message;
}

/// Génération et export des rapports. Singleton : `RapportService.instance`.
class RapportService {
  RapportService._();

  static final RapportService instance = RapportService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Nombre de lignes de données par bloc PDF (les grands tableaux sont
  /// découpés pour se répartir proprement sur plusieurs pages).
  static const int lignesParBlocPdf = 24;

  // ---------------------------------------------------------------------------
  // 1. GÉNÉRATION
  // ---------------------------------------------------------------------------

  /// Génère un rapport et le trace (`format = 'apercu'`).
  ///
  /// [filtres] dépend du type : `{'groupe': 'jour'}` (ventes, nouveaux
  /// comptes), `{'limite': 10}` (top produits), `{'categorie': …, 'alerte_
  /// seulement': bool}` (stock), `{'detail': bool}` (dépenses),
  /// `{'statut': 'non_paye'|'partiel'|'paye'}` (dettes).
  Future<ResultatRapport> generer({
    required TypeRapport type,
    DateTime? debut,
    DateTime? fin,
    Map<String, dynamic>? filtres,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      type.estPlateforme ? 'rpc_rapport_plateforme' : 'rpc_rapport_entreprise',
      params: <String, dynamic>{
        'p_type': type.code,
        if (debut != null) 'p_debut': _dateSeule(debut),
        if (fin != null) 'p_fin': _dateSeule(fin),
        if (filtres != null && filtres.isNotEmpty) 'p_filtres': filtres,
      },
      actionLibelle: 'la génération du rapport',
    );

    if (map == null) {
      throw const RapportServiceException(
        'Réponse inattendue du serveur : le rapport est vide.',
      );
    }

    final RapportDonnees donnees = RapportDonnees.depuisRpc(map);
    final String reference = genererReferenceRapport();
    final String empreinte = empreinteRapport(donnees);

    await _tracer(
      espace: type.espace,
      type: type.code,
      debut: debut,
      fin: fin,
      format: FormatExportRapport.apercu,
      reference: reference,
      empreinte: empreinte,
      parametres: filtres,
    );

    return ResultatRapport(
      donnees: donnees,
      reference: reference,
      empreinte: empreinte,
    );
  }

  /// Ventes par période (`groupe` : jour, semaine ou mois) ou variante
  /// (par article, par catégorie, par vendeur, top produits).
  Future<ResultatRapport> genererRapportVentes({
    DateTime? debut,
    DateTime? fin,
    GroupePeriodeRapport groupe = GroupePeriodeRapport.jour,
    TypeRapport variante = TypeRapport.ventes,
    int limiteTop = 10,
  }) {
    final Map<String, dynamic> filtres = variante == TypeRapport.topProduits
        ? <String, dynamic>{'limite': limiteTop}
        : (variante == TypeRapport.ventes
            ? <String, dynamic>{'groupe': groupe.code}
            : const <String, dynamic>{});
    return generer(
      type: variante,
      debut: debut,
      fin: fin,
      filtres: filtres,
    );
  }

  /// État du stock : alertes, ruptures, valeur.
  Future<ResultatRapport> genererRapportStock({
    String? categorie,
    bool alerteSeulement = false,
  }) {
    return generer(
      type: TypeRapport.stock,
      filtres: <String, dynamic>{
        if (categorie != null && categorie.trim().isNotEmpty)
          'categorie': categorie.trim(),
        'alerte_seulement': alerteSeulement,
      },
    );
  }

  /// Chiffre d'affaires, coût des marchandises, dépenses et bénéfice net.
  Future<ResultatRapport> genererRapportFinance({
    required DateTime debut,
    required DateTime fin,
  }) {
    return generer(type: TypeRapport.finance, debut: debut, fin: fin);
  }

  /// Flux de caisse (entrées / sorties / net) sur une période.
  Future<ResultatRapport> genererRapportCaisse({
    required DateTime debut,
    required DateTime fin,
  }) {
    return generer(type: TypeRapport.caisse, debut: debut, fin: fin);
  }

  /// Dépenses par catégorie (ou détail ligne à ligne).
  Future<ResultatRapport> genererRapportDepenses({
    required DateTime debut,
    required DateTime fin,
    bool detail = false,
  }) {
    return generer(
      type: TypeRapport.depenses,
      debut: debut,
      fin: fin,
      filtres: <String, dynamic>{'detail': detail},
    );
  }

  /// Dettes clients (`statut` : `non_paye`, `partiel`, `paye` ou `null`).
  Future<ResultatRapport> genererRapportDettes({String? statut}) {
    return generer(
      type: TypeRapport.dettes,
      filtres: <String, dynamic>{
        if (statut != null && statut.isNotEmpty) 'statut': statut,
      },
    );
  }

  /// Vue plateforme : abonnements, impayés, nouveaux comptes (selon
  /// [variante]), réservée au personnel La Perle.
  Future<ResultatRapport> genererRapportAbonnements({
    DateTime? debut,
    DateTime? fin,
    TypeRapport variante = TypeRapport.plateformeAbonnements,
    GroupePeriodeRapport groupe = GroupePeriodeRapport.jour,
  }) {
    return generer(
      type: variante,
      debut: debut,
      fin: fin,
      filtres: variante == TypeRapport.plateformeNouveauxComptes
          ? <String, dynamic>{'groupe': groupe.code}
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // 2. RÉFÉRENCE & EMPREINTE (EXPORTS SIGNÉS)
  // ---------------------------------------------------------------------------

  /// Référence lisible d'une opération : `RPT-AAAAMMJJ-XXXXXX`.
  ///
  /// [maintenant] et [suffixe] sont injectables pour les tests.
  static String genererReferenceRapport({DateTime? maintenant, String? suffixe}) {
    final DateTime date = maintenant ?? DateTime.now();
    final String jour = '${date.year}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';

    String alea = suffixe ?? '';
    if (alea.isEmpty) {
      final Random hasard = Random.secure();
      final StringBuffer buffer = StringBuffer();
      for (int i = 0; i < 6; i++) {
        buffer.write(hasard.nextInt(16).toRadixString(16).toUpperCase());
      }
      alea = buffer.toString();
    }
    return 'RPT-$jour-$alea';
  }

  /// SHA-256 (hexadécimal) du contenu d'un rapport.
  ///
  /// Le même rapport produit toujours la même empreinte ; deux rapports
  /// différents (même d'un seul chiffre) ont des empreintes distinctes. C'est
  /// elle qui « signe » les exports PDF/Excel imprimés.
  static String empreinteRapport(RapportDonnees donnees) {
    final Map<String, dynamic> canonique = <String, dynamic>{
      'type': donnees.type,
      'portee': donnees.portee,
      'debut': donnees.debut?.toIso8601String(),
      'fin': donnees.fin?.toIso8601String(),
      'parametres': donnees.parametres,
      'lignes': donnees.lignes,
      'totaux': donnees.totaux,
    };
    final List<int> octets = utf8.encode(jsonEncode(canonique));
    return sha256.convert(octets).toString();
  }

  /// Empreinte abrégée (12 caractères) affichée sur les documents.
  static String empreinteCourte(String empreinte) =>
      empreinte.length <= 12 ? empreinte : empreinte.substring(0, 12).toUpperCase();

  /// Nom de fichier d'un rapport : `rapport_<type>_<début>_<fin>.<ext>`.
  static String nomFichierRapport({
    required String type,
    DateTime? debut,
    DateTime? fin,
    required String extension,
  }) {
    final StringBuffer nom = StringBuffer('rapport_${_slug(type)}');
    if (debut != null) nom.write('_${_dateCompacte(debut)}');
    if (fin != null) nom.write('_${_dateCompacte(fin)}');
    nom.write('.$extension');
    return nom.toString();
  }

  // ---------------------------------------------------------------------------
  // 3. PDF
  // ---------------------------------------------------------------------------

  /// Construit le PDF d'un rapport (en-tête entreprise + période, totaux,
  /// pied de page avec pagination, référence et empreinte).
  ///
  /// [chargerPolices] est désactivable pour les tests (évite tout accès
  /// réseau : les polices Google sont un « bonus » best-effort).
  Future<Uint8List> construirePDF(
    ResultatRapport resultat, {
    String? nomEntreprise,
    Uint8List? logo,
    String? reference,
    bool chargerPolices = true,
  }) async {
    final RapportDonnees donnees = resultat.donnees;
    final String referenceDocument = reference ?? resultat.reference;
    final DateTime genereLe = DateTime.now();

    final pw.ThemeData? theme =
        chargerPolices ? await _chargerThemePdf() : null;
    final pw.Document document = pw.Document(theme: theme);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 30, 28, 34),
        header: (pw.Context context) => context.pageNumber == 1
            ? _entetePdfComplet(
                donnees, nomEntreprise, logo, referenceDocument, genereLe)
            : _entetePdfSuite(donnees),
        footer: (pw.Context context) => _piedDePagePdf(
          context, donnees, referenceDocument, resultat.empreinte, genereLe),
        build: (pw.Context context) => <pw.Widget>[
          if (donnees.resume.isNotEmpty) ...<pw.Widget>[
            _bandeauResumePdf(donnees.resume),
            pw.SizedBox(height: 12),
          ],
          if (donnees.estVide)
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                'Aucune donnée sur la période sélectionnée.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            )
          else
            ..._tableauxPdf(donnees),
        ],
      ),
    );

    return document.save();
  }

  /// Enregistre le PDF dans « Téléchargements/rapports » (repli : documents
  /// de l'application) et renvoie le chemin du fichier créé. L'export est
  /// tracé (`format = 'pdf'`) avec sa propre référence.
  Future<String> exporterPDF(
    ResultatRapport resultat, {
    String? nomEntreprise,
    Uint8List? logo,
  }) async {
    final String reference = genererReferenceRapport();
    final Uint8List octets = await construirePDF(
      resultat,
      nomEntreprise: nomEntreprise,
      logo: logo,
      reference: reference,
    );

    final String chemin = await _ecrireFichier(
      octets,
      nomFichierRapport(
        type: resultat.donnees.type,
        debut: resultat.donnees.debut,
        fin: resultat.donnees.fin,
        extension: 'pdf',
      ),
      mimeType: 'application/pdf',
    );

    await _tracer(
      espace: _espaceDepuisPortee(resultat.donnees.portee),
      type: resultat.donnees.type,
      debut: resultat.donnees.debut,
      fin: resultat.donnees.fin,
      format: FormatExportRapport.pdf,
      reference: reference,
      empreinte: resultat.empreinte,
      parametres: resultat.donnees.parametres,
    );

    return chemin;
  }

  /// Partage le PDF (feuille de partage du système) — tracé `partage`.
  Future<void> partagerPDF(
    ResultatRapport resultat, {
    String? nomEntreprise,
    Uint8List? logo,
  }) async {
    final String reference = genererReferenceRapport();
    final Uint8List octets = await construirePDF(
      resultat,
      nomEntreprise: nomEntreprise,
      logo: logo,
      reference: reference,
    );

    final String nomFichier = nomFichierRapport(
      type: resultat.donnees.type,
      debut: resultat.donnees.debut,
      fin: resultat.donnees.fin,
      extension: 'pdf',
    );

    await Printing.sharePdf(bytes: octets, filename: nomFichier);

    await _tracer(
      espace: _espaceDepuisPortee(resultat.donnees.portee),
      type: resultat.donnees.type,
      debut: resultat.donnees.debut,
      fin: resultat.donnees.fin,
      format: FormatExportRapport.partage,
      reference: reference,
      empreinte: resultat.empreinte,
      parametres: resultat.donnees.parametres,
    );
  }

  /// Ouvre la boîte de dialogue d'impression du système — tracé
  /// `impression`.
  Future<void> imprimerPDF(
    ResultatRapport resultat, {
    String? nomEntreprise,
    Uint8List? logo,
  }) async {
    final String reference = genererReferenceRapport();
    final Uint8List octets = await construirePDF(
      resultat,
      nomEntreprise: nomEntreprise,
      logo: logo,
      reference: reference,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => octets,
      name: nomFichierRapport(
        type: resultat.donnees.type,
        debut: resultat.donnees.debut,
        fin: resultat.donnees.fin,
        extension: 'pdf',
      ),
    );

    await _tracer(
      espace: _espaceDepuisPortee(resultat.donnees.portee),
      type: resultat.donnees.type,
      debut: resultat.donnees.debut,
      fin: resultat.donnees.fin,
      format: FormatExportRapport.impression,
      reference: reference,
      empreinte: resultat.empreinte,
      parametres: resultat.donnees.parametres,
    );
  }

  // ---------------------------------------------------------------------------
  // 4. EXCEL
  // ---------------------------------------------------------------------------

  /// Construit le classeur Excel (.xlsx) d'un rapport : titre, entête
  /// (entreprise, période, référence, empreinte), colonnes, lignes, totaux.
  ///
  /// Les colonnes numériques sont écrites en NOMBRES (pas en texte) : le
  /// classeur reste calculable dans Excel / LibreOffice.
  Future<Uint8List> construireExcel(
    ResultatRapport resultat, {
    String? nomEntreprise,
    String? reference,
  }) async {
    final RapportDonnees donnees = resultat.donnees;
    final String referenceDocument = reference ?? resultat.reference;
    final DateTime genereLe = DateTime.now();

    final xls.Excel classeur = xls.Excel.createExcel();
    const String nomFeuille = 'Rapport';
    final xls.Sheet feuille = classeur[nomFeuille];

    final String? feuilleParDefaut = classeur.getDefaultSheet();
    if (feuilleParDefaut != null && feuilleParDefaut != nomFeuille) {
      classeur.delete(feuilleParDefaut);
    }

    final int nbColonnes = max(donnees.colonnes.length, 1);
    int ligne = 0;

    // ----- entête (titre + informations) -------------------------------------
    feuille.appendRow(<xls.CellValue?>[
      xls.TextCellValue(
          '${nomEntreprise == null ? '' : '$nomEntreprise — '}${donnees.titre}'),
    ]);
    _fusionnerTitre(feuille, ligne, nbColonnes);
    _styliserLigne(feuille, ligne, nbColonnes, gras: true, taille: 14);
    ligne++;

    if (donnees.periodeTexte != null) {
      feuille.appendRow(<xls.CellValue?>[
        xls.TextCellValue('Période : ${donnees.periodeTexte}'),
      ]);
      ligne++;
    }

    // 🪙 MODULE 18 — devise de travail des montants du rapport.
    feuille.appendRow(<xls.CellValue?>[
      xls.TextCellValue(
          'Devise : ${FormatMonetaire.code} (${FormatMonetaire.symbole})'),
    ]);
    ligne++;

    feuille.appendRow(<xls.CellValue?>[
      xls.TextCellValue('Généré le ${formatDateHeure(genereLe)}'),
    ]);
    ligne++;

    feuille.appendRow(<xls.CellValue?>[
      xls.TextCellValue(
          'Référence : $referenceDocument  ·  Empreinte : ${empreinteCourte(resultat.empreinte)}'),
    ]);
    ligne++;

    if (donnees.resume.isNotEmpty) {
      ligne++; // ligne vide
      for (final LigneResumeRapport indicateur in donnees.resume) {
        feuille.appendRow(<xls.CellValue?>[
          xls.TextCellValue(indicateur.libelle),
          _valeurExcel(indicateur.valeur, indicateur.type),
        ]);
        _styliserLigne(feuille, ligne, 2, gras: false, taille: 11);
        ligne++;
      }
    }

    ligne++; // ligne vide avant le tableau

    // ----- tableau ------------------------------------------------------------
    final int ligneEntetes = ligne;
    feuille.appendRow(<xls.CellValue?>[
      for (final ColonneRapport colonne in donnees.colonnes)
        xls.TextCellValue(colonne.libelle),
    ]);
    _styliserLigne(feuille, ligneEntetes, nbColonnes,
        gras: true, taille: 11, couleurFond: '#DDEBF7');
    ligne++;

    for (final Map<String, dynamic> donneeLigne in donnees.lignes) {
      feuille.appendRow(<xls.CellValue?>[
        for (final ColonneRapport colonne in donnees.colonnes)
          _valeurExcel(donneeLigne[colonne.cle], colonne.type),
      ]);
      ligne++;
    }

    // ----- totaux ---------------------------------------------------------------
    final bool aDesTotaux = donnees.colonnes.any(donnees.aTotal);
    if (aDesTotaux) {
      feuille.appendRow(<xls.CellValue?>[
        for (final ColonneRapport colonne in donnees.colonnes)
          colonne.cle == donnees.colonnes.first.cle
              ? xls.TextCellValue('TOTAUX')
              : (donnees.aTotal(colonne)
                  ? _valeurExcel(donnees.totaux[colonne.cle], colonne.type)
                  : null),
      ]);
      _styliserLigne(feuille, ligne, nbColonnes,
          gras: true, taille: 11, couleurFond: '#FCE4D6');
      ligne++;
    }

    // ----- largeurs de colonnes ---------------------------------------------------
    for (int i = 0; i < donnees.colonnes.length; i++) {
      feuille.setColumnWidth(i, _largeurExcel(donnees.colonnes[i]));
    }

    final List<int>? octets = classeur.save();
    if (octets == null) {
      throw const RapportServiceException(
        "Impossible de construire le fichier Excel.",
        type: TypeErreurRapport.inconnu,
      );
    }
    return Uint8List.fromList(octets);
  }

  /// Enregistre l'Excel dans « Téléchargements/rapports » et renvoie le
  /// chemin du fichier créé. L'export est tracé (`format = 'excel'`).
  Future<String> exporterExcel(
    ResultatRapport resultat, {
    String? nomEntreprise,
  }) async {
    final String reference = genererReferenceRapport();
    final Uint8List octets = await construireExcel(
      resultat,
      nomEntreprise: nomEntreprise,
      reference: reference,
    );

    final String chemin = await _ecrireFichier(
      octets,
      nomFichierRapport(
        type: resultat.donnees.type,
        debut: resultat.donnees.debut,
        fin: resultat.donnees.fin,
        extension: 'xlsx',
      ),
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );

    await _tracer(
      espace: _espaceDepuisPortee(resultat.donnees.portee),
      type: resultat.donnees.type,
      debut: resultat.donnees.debut,
      fin: resultat.donnees.fin,
      format: FormatExportRapport.excel,
      reference: reference,
      empreinte: resultat.empreinte,
      parametres: resultat.donnees.parametres,
    );

    return chemin;
  }

  // ---------------------------------------------------------------------------
  // 5. HISTORIQUE & CONTEXTE
  // ---------------------------------------------------------------------------

  /// Derniers rapports générés (registre `rapports_generes`).
  Future<List<EntreeHistoriqueRapport>> historique({int limit = 50}) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_rapports_historique',
      params: <String, dynamic>{'p_limit': limit},
      actionLibelle: "la lecture de l'historique des rapports",
    );

    if (map == null) return const <EntreeHistoriqueRapport>[];
    return (map['lignes'] is List
            ? (map['lignes'] as List)
                .whereType<Map>()
                .map((Map<dynamic, dynamic> element) =>
                    EntreeHistoriqueRapport.depuisJson(
                        Map<String, dynamic>.from(element)))
                .toList()
            : const <EntreeHistoriqueRapport>[])
        .cast<EntreeHistoriqueRapport>();
  }

  /// Nom de l'entreprise du compte connecté (`utilisateurs.entreprise_id` →
  /// `entreprises.nom`), ou `null` si introuvable.
  Future<String?> nomEntrepriseCourante() async {
    try {
      final String? userId = _client.auth.currentUser?.id;
      if (userId == null) return null;

      final dynamic utilisateur = await _client
          .from('utilisateurs')
          .select('entreprise_id')
          .eq('id', userId)
          .maybeSingle();
      final String? entrepriseId =
          (utilisateur is Map ? utilisateur['entreprise_id'] : null) as String?;
      if (entrepriseId == null) return null;

      final dynamic entreprise = await _client
          .from('entreprises')
          .select('nom')
          .eq('id', entrepriseId)
          .maybeSingle();
      final String? nom =
          (entreprise is Map ? entreprise['nom'] : null) as String?;
      return (nom == null || nom.trim().isEmpty) ? null : nom.trim();
    } catch (e) {
      debugPrint('RapportService (nom entreprise): $e');
      return null;
    }
  }

  /// Logo utilisé dans l'en-tête des PDF (best-effort : `null` si absent).
  Future<Uint8List?> chargerLogo() async {
    try {
      final ByteData data = await rootBundle.load('assets/Biashara_app_off-.png');
      return data.buffer.asUint8List();
    } catch (e) {
      debugPrint('RapportService (logo indisponible): $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // 6. OUTILS PARTAGÉS (RPC, TRACE, FICHIERS)
  // ---------------------------------------------------------------------------

  /// Extrait le message utilisateur d'une erreur serveur (code séparé par «|»).
  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  static TypeErreurRapport _typeDepuisMessage(String brut) {
    final String code = brut.trim().split('|').first.trim().toUpperCase();
    switch (code) {
      case 'SESSION_ABSENTE':
      case 'ACCES_REFUSE':
      case 'DROIT_REFUSE':
        return TypeErreurRapport.droits;
      case 'PERIODE_INVALIDE':
      case 'TYPE_INVALIDE':
      case 'GROUPE_INVALIDE':
      case 'STATUT_INVALIDE':
      case 'FORMAT_INVALIDE':
      case 'PORTEE_INVALIDE':
        return TypeErreurRapport.validation;
      default:
        return TypeErreurRapport.inconnu;
    }
  }

  /// Enregistre une opération dans le registre + le journal d'audit.
  ///
  /// Best-effort : une trace manquée (réseau) n'empêche pas l'utilisateur de
  /// consulter ou d'exporter son rapport — un avertissement est journalisé.
  Future<bool> _tracer({
    required EspaceRapport espace,
    required String type,
    required DateTime? debut,
    required DateTime? fin,
    required FormatExportRapport format,
    required String reference,
    required String? empreinte,
    Map<String, dynamic>? parametres,
  }) async {
    try {
      await _client.rpc('rpc_rapport_tracer', params: <String, dynamic>{
        'p_portee': espace.code,
        'p_type': type,
        if (debut != null) 'p_debut': _dateSeule(debut),
        if (fin != null) 'p_fin': _dateSeule(fin),
        'p_format': format.code,
        'p_reference': reference,
        if (empreinte != null) 'p_empreinte': empreinte,
        if (parametres != null && parametres.isNotEmpty)
          'p_parametres': parametres,
      });
      return true;
    } catch (e) {
      debugPrint('RapportService (trace $type/${format.code}): $e');
      return false;
    }
  }

  /// Appelle une RPC du module et renvoie sa réponse en `Map` (ou `null`).
  Future<Map<String, dynamic>?> _appelerRpc(
    String fonction, {
    required Map<String, dynamic> params,
    required String actionLibelle,
  }) async {
    dynamic reponse;
    try {
      reponse = await _client.rpc(fonction, params: params);
    } on PostgrestException catch (e) {
      debugPrint(
          'RapportService ($actionLibelle) PostgrestException: ${e.code} ${e.message}');
      throw RapportServiceException(
        messageErreur(e.message),
        type: _typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('RapportService ($actionLibelle): $e\n$st');
      throw const RapportServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurRapport.reseau,
      );
    }

    return reponseRpcEnMap(reponse);
  }

  /// Enregistre le fichier dans « Téléchargements/rapports » (Android /
  /// Windows / Linux) ou le télécharge via le navigateur (web — PHASE F).
  /// Renvoie le chemin complet (natif) ou le nom du fichier (web).
  Future<String> _ecrireFichier(
    Uint8List octets,
    String nomFichier, {
    String mimeType = 'application/octet-stream',
  }) async {
    try {
      return await enregistrerDansTelechargements(
            sousDossier: 'rapports',
            nomFichier: nomFichier,
            octets: octets,
            mimeType: mimeType,
          ) ??
          nomFichier;
    } catch (e, st) {
      debugPrint('RapportService (écriture fichier): $e\n$st');
      throw const RapportServiceException(
        "Impossible d'enregistrer le fichier. Vérifiez l'espace de stockage puis réessayez.",
      );
    }
  }

  /// `AAAA-MM-JJ` — convention de dates du projet (UTC).
  static String _dateSeule(DateTime date) {
    final String mois = date.month.toString().padLeft(2, '0');
    final String jour = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mois-$jour';
  }

  static String _dateCompacte(DateTime date) {
    final String mois = date.month.toString().padLeft(2, '0');
    final String jour = date.day.toString().padLeft(2, '0');
    return '${date.year}$mois$jour';
  }

  static String _slug(String texte) => texte
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  static EspaceRapport _espaceDepuisPortee(String portee) =>
      portee.trim().toLowerCase() == 'plateforme'
          ? EspaceRapport.plateforme
          : EspaceRapport.entreprise;

  /// Remplace les caractères non pris en charge par les polices PDF standard
  /// (tiret cadratin, tiret demi-cadratin) par un simple tiret : le document
  /// reste lisible même si les polices Google n'ont pas pu être téléchargées
  /// (mode hors ligne).
  static String _textePdf(String texte) =>
      texte.replaceAll('\u2014', '-').replaceAll('\u2013', '-');

  // ---------------------------------------------------------------------------
  // 7. RENDU PDF (PRIVÉ)
  // ---------------------------------------------------------------------------

  /// Polices Google (best-effort) — repli silencieux sur les polices PDF
  /// standard si le téléchargement échoue (hors ligne).
  Future<pw.ThemeData?> _chargerThemePdf() async {
    try {
      final pw.Font base = await PdfGoogleFonts.robotoRegular();
      final pw.Font gras = await PdfGoogleFonts.robotoBold();
      final pw.Font italique = await PdfGoogleFonts.robotoItalic();
      return pw.ThemeData.withFont(base: base, bold: gras, italic: italique);
    } catch (e) {
      debugPrint('RapportService (polices PDF): $e');
      return null;
    }
  }

  pw.Widget _entetePdfComplet(
    RapportDonnees donnees,
    String? nomEntreprise,
    Uint8List? logo,
    String reference,
    DateTime genereLe,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            if (logo != null) ...<pw.Widget>[
              pw.Image(pw.MemoryImage(logo), width: 42, height: 42),
              pw.SizedBox(width: 10),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    _textePdf(nomEntreprise ?? 'Biashara Yangu'),
                    style: pw.TextStyle(
                        fontSize: 15, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Rapport généré par Biashara Yangu',
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                pw.Text(
                  _textePdf(donnees.titre),
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.right,
                ),
                if (donnees.periodeTexte != null)
                  pw.Text(
                    'Période : ${donnees.periodeTexte}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                // 🪙 MODULE 18 — devise de travail (toutes les colonnes
                // monétaires du rapport sont exprimées dans cette devise).
                pw.Text(
                  'Devise : ${FormatMonetaire.code} '
                  '(${FormatMonetaire.symbole})',
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Généré le ${formatDateHeure(genereLe)}',
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 0.8, color: PdfColors.blueGrey800),
        pw.SizedBox(height: 4),
      ],
    );
  }

  pw.Widget _entetePdfSuite(RapportDonnees donnees) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              _textePdf(donnees.titre),
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            if (donnees.periodeTexte != null)
              pw.Text(
                donnees.periodeTexte!,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.SizedBox(height: 4),
      ],
    );
  }

  pw.Widget _piedDePagePdf(
    pw.Context context,
    RapportDonnees donnees,
    String reference,
    String empreinte,
    DateTime genereLe,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              'Réf. $reference · Empreinte ${empreinteCourte(empreinte)}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
            pw.Text(
              formatDate(genereLe),
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _bandeauResumePdf(List<LigneResumeRapport> resume) {
    return pw.Wrap(
      spacing: 8,
      runSpacing: 6,
      children: resume
          .map(
            (LigneResumeRapport indicateur) => pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('EDF3FA'),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    _textePdf(indicateur.libelle),
                    style:
                        const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text(
                    _textePdf(indicateur.valeurFormatee),
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  /// Blocs de tableaux (découpés pour tenir sur plusieurs pages).
  List<pw.Widget> _tableauxPdf(RapportDonnees donnees) {
    final List<pw.Widget> widgets = <pw.Widget>[];
    final List<String> entetes = donnees.colonnes
        .map((ColonneRapport colonne) => _textePdf(colonne.libelle))
        .toList(growable: false);

    final Map<int, pw.Alignment> alignements =
        <int, pw.Alignment>{
      for (int i = 0; i < donnees.colonnes.length; i++)
        if (donnees.colonnes[i].type == TypeColonneRapport.montant ||
            donnees.colonnes[i].type == TypeColonneRapport.nombre ||
            donnees.colonnes[i].type == TypeColonneRapport.pourcentage)
          i: pw.Alignment.centerRight,
    };

    final List<List<Map<String, dynamic>>> blocs = _decouper(
      donnees.lignes,
      lignesParBlocPdf,
    );

    for (int index = 0; index < blocs.length; index++) {
      widgets.add(
        pw.TableHelper.fromTextArray(
          headers: entetes,
          data: blocs[index]
              .map(
                (Map<String, dynamic> ligne) => donnees.colonnes
                    .map((ColonneRapport colonne) =>
                        _textePdf(donnees.valeurFormatee(ligne, colonne)))
                    .toList(growable: false),
              )
              .toList(growable: false),
          headerStyle: pw.TextStyle(
              fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration:
              pw.BoxDecoration(color: PdfColor.fromHex('37474F')),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
          cellAlignments: alignements,
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
          oddRowDecoration:
              pw.BoxDecoration(color: PdfColor.fromHex('F5F7F9')),
        ),
      );

      // Total sous le dernier bloc.
      if (index == blocs.length - 1 && donnees.colonnes.any(donnees.aTotal)) {
        widgets.add(
          pw.SizedBox(height: 6),
        );
        widgets.add(
          pw.TableHelper.fromTextArray(
            headers: entetes,
            data: <List<String>>[
              <String>[
                for (int i = 0; i < donnees.colonnes.length; i++)
                  i == 0
                      ? 'TOTAUX'
                      : _textePdf(
                          donnees.totalFormate(donnees.colonnes[i]) ?? ''),
              ],
            ],
            headerStyle: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration:
                pw.BoxDecoration(color: PdfColor.fromHex('37474F')),
            cellStyle: pw.TextStyle(
                fontSize: 7.5, fontWeight: pw.FontWeight.bold),
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
            cellAlignments: alignements,
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
            rowDecoration: pw.BoxDecoration(color: PdfColor.fromHex('FCE4D6')),
          ),
        );
      } else if (index < blocs.length - 1) {
        widgets.add(pw.SizedBox(height: 10));
      }
    }

    return widgets;
  }

  static List<List<T>> _decouper<T>(List<T> source, int taille) {
    if (source.isEmpty) return const <List<Never>>[];
    final List<List<T>> blocs = <List<T>>[];
    for (int i = 0; i < source.length; i += taille) {
      blocs.add(source.sublist(i, min(i + taille, source.length)));
    }
    return blocs;
  }

  // ---------------------------------------------------------------------------
  // 8. RENDU EXCEL (PRIVÉ)
  // ---------------------------------------------------------------------------

  static xls.CellValue? _valeurExcel(Object? valeur, TypeColonneRapport type) {
    if (valeur == null) return null;
    if (type == TypeColonneRapport.montant ||
        type == TypeColonneRapport.nombre ||
        type == TypeColonneRapport.pourcentage) {
      if (valeur is num) return xls.DoubleCellValue(valeur.toDouble());
      final double? converti = double.tryParse(valeur.toString());
      if (converti != null) return xls.DoubleCellValue(converti);
    }
    return xls.TextCellValue(formaterValeurRapport(valeur, type));
  }

  static double _largeurExcel(ColonneRapport colonne) {
    switch (colonne.type) {
      case TypeColonneRapport.montant:
        return 18;
      case TypeColonneRapport.nombre:
      case TypeColonneRapport.pourcentage:
        return 12;
      case TypeColonneRapport.date:
        return 14;
      case TypeColonneRapport.texte:
        return colonne.libelle.length < 12 ? 18 : 26;
    }
  }

  static void _styliserLigne(
    xls.Sheet feuille,
    int indexLigne,
    int nbColonnes, {
    required bool gras,
    required int taille,
    String? couleurFond,
  }) {
    final xls.CellStyle style = xls.CellStyle(
      bold: gras,
      fontSize: taille,
      backgroundColorHex: couleurFond == null
          ? xls.ExcelColor.none
          : xls.ExcelColor.fromHexString(couleurFond),
    );
    for (int i = 0; i < nbColonnes; i++) {
      feuille
          .cell(xls.CellIndex.indexByColumnRow(
              columnIndex: i, rowIndex: indexLigne))
          .cellStyle = style;
    }
  }

  static void _fusionnerTitre(xls.Sheet feuille, int indexLigne, int nbColonnes) {
    if (nbColonnes <= 1) return;
    feuille.merge(
      xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: indexLigne),
      xls.CellIndex.indexByColumnRow(
          columnIndex: nbColonnes - 1, rowIndex: indexLigne),
    );
  }
}
