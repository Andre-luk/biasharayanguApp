// lib/services/audit_service.dart
//
// MODULE 12 — SERVICE DU JOURNAL D'AUDIT.
//
//   • `logger(...)`              → écrit une entrée via `rpc_audit_logger`
//     (CONNEXION, DECONNEXION, exports…). Écriture BEST-EFFORT : une
//     défaillance du journal ne casse jamais l'action métier ;
//   • `listerAvecFiltres(...)`   → liste paginée via `rpc_audit_lister`
//     (filtres : utilisateur, action, niveau, période, entreprise, recherche) ;
//   • `verifierIntegrite(...)`   → contrôle de la chaîne d'empreintes
//     (réservé au personnel plateforme) ;
//   • `exporterAuditPDF(...)`    → export PDF « signé » (référence + empreinte
//     visibles), lui-même journalisé (action `RAPPORT`).
//
// ⚠️ Le journal est APPEND-ONLY côté serveur : ces méthodes n'offrent
// volontairement AUCUNE fonction de modification ou de suppression.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/audit.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart' show reponseRpcEnMap;
import 'package:biashara_yangu/utils/fichiers_locaux.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Nature d'une erreur du journal d'audit (pour adapter l'interface).
enum TypeErreurAudit { droits, validation, reseau, inconnu }

/// Erreur métier du journal d'audit (message déjà en français).
class AuditServiceException implements Exception {
  const AuditServiceException(
    this.message, {
    this.type = TypeErreurAudit.inconnu,
  });

  final String message;
  final TypeErreurAudit type;

  @override
  String toString() => message;
}

/// Journal d'audit et exports. Singleton : `AuditService.instance`.
class AuditService {
  AuditService._();

  static final AuditService instance = AuditService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Nombre maximal de lignes exportées en un PDF.
  static const int maxLignesExport = 500;

  // ---------------------------------------------------------------------------
  // 1. ÉCRITURE — `logger`
  // ---------------------------------------------------------------------------

  /// Journalise une action applicative. Best-effort : renvoie `null` si le
  /// serveur refuse ou si le réseau est absent (jamais d'exception).
  ///
  /// Le contexte (boutique, portée, IP, User-Agent) est complété côté serveur.
  Future<Map<String, dynamic>?> logger(
    String action, {
    Map<String, dynamic>? details,
    String? entrepriseId,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'rpc_audit_logger',
        params: <String, dynamic>{
          'p_action': action,
          'p_details': details ?? const <String, dynamic>{},
          if (entrepriseId != null) 'p_entreprise_id': entrepriseId,
        },
      );
      return reponseRpcEnMap(reponse);
    } catch (e) {
      // Le journal ne doit JAMAIS faire échouer l'action de l'utilisateur.
      debugPrint('AuditService.logger($action) ignoré : $e');
      return null;
    }
  }

  /// Trace une connexion réussie (session active).
  Future<void> connexion({String? email}) {
    return logger(
      'CONNEXION',
      details: <String, dynamic>{
        'plateforme': PermissionService.instance.estPlateforme,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
  }

  /// Trace une déconnexion. À appeler AVANT de fermer la session.
  Future<void> deconnexion({String? email}) {
    return logger(
      'DECONNEXION',
      details: <String, dynamic>{
        'plateforme': PermissionService.instance.estPlateforme,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
  }

  /// Trace un échec de connexion — SEUL cas autorisé SANS session.
  ///
  /// Les détails sont volontairement réduits (email + message) : le serveur
  /// ignore silencieusement tout autre champ (anti-spam).
  Future<void> echecConnexion(String email, String message) {
    return logger(
      'CONNEXION_ECHEC',
      details: <String, dynamic>{
        'email': email,
        'message': message,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 2. LECTURE — `listerAvecFiltres`
  // ---------------------------------------------------------------------------

  /// Liste filtrée et paginée du journal.
  ///
  /// La portée est déduite par le serveur : personnel plateforme (`audit/voir`)
  /// → toutes les lignes ; boutique → uniquement les siennes.
  Future<PageAudit> listerAvecFiltres({
    String? utilisateurId,
    String? action,
    String? niveau,
    DateTime? debut,
    DateTime? fin,
    String? entrepriseId,
    String? recherche,
    int limit = 50,
    int offset = 0,
  }) async {
    final dynamic reponse = await _executer(
      () => _client.rpc(
        'rpc_audit_lister',
        params: <String, dynamic>{
          if (utilisateurId != null) 'p_utilisateur': utilisateurId,
          if (action != null && action.isNotEmpty) 'p_action': action,
          if (niveau != null && niveau.isNotEmpty) 'p_niveau': niveau,
          if (debut != null) 'p_debut': dateSeule(debut),
          if (fin != null) 'p_fin': dateSeule(fin),
          if (entrepriseId != null) 'p_entreprise': entrepriseId,
          if (recherche != null && recherche.trim().isNotEmpty)
            'p_recherche': recherche.trim(),
          'p_limit': limit,
          'p_offset': offset,
        },
      ),
      actionLibelle: 'le chargement du journal',
    );

    return PageAudit.depuisRpc(reponse);
  }

  /// Contrôle d'intégrité de la chaîne d'empreintes (plateforme uniquement).
  Future<VerificationAudit> verifierIntegrite({int limit = 200}) async {
    final dynamic reponse = await _executer(
      () => _client.rpc(
        'rpc_audit_verifier',
        params: <String, dynamic>{'p_limit': limit},
      ),
      actionLibelle: 'la vérification du journal',
    );

    return VerificationAudit.depuisRpc(reponse);
  }

  // ---------------------------------------------------------------------------
  // 3. EXPORT PDF — `exporterAuditPDF`
  // ---------------------------------------------------------------------------

  /// Exporte la vue courante du journal en PDF et renvoie le chemin du fichier.
  ///
  /// Le document porte une RÉFÉRENCE et une EMPREINTE SHA-256 (les mêmes que
  /// la trace `RAPPORT` enregistrée juste après) : un exemplaire imprimé peut
  /// être relié à sa ligne du journal par ces deux valeurs.
  Future<String> exporterAuditPDF({
    String? utilisateurId,
    String? action,
    String? niveau,
    DateTime? debut,
    DateTime? fin,
    String? entrepriseId,
    String? recherche,
    String? nomEntreprise,
    int maxLignes = maxLignesExport,
  }) async {
    final PageAudit page = await listerAvecFiltres(
      utilisateurId: utilisateurId,
      action: action,
      niveau: niveau,
      debut: debut,
      fin: fin,
      entrepriseId: entrepriseId,
      recherche: recherche,
      limit: maxLignes,
      offset: 0,
    );

    if (page.lignes.isEmpty) {
      throw const AuditServiceException(
        'Aucune entrée à exporter : ajustez les filtres ou la période.',
        type: TypeErreurAudit.validation,
      );
    }

    final String reference = genererReferenceExport();
    final String empreinte = empreinteExport(page.lignes, reference);

    final Uint8List octets = await construirePDF(
      lignes: page.lignes,
      total: page.total,
      portee: page.portee,
      reference: reference,
      empreinte: empreinte,
      nomEntreprise: nomEntreprise,
      filtres: <String, dynamic>{
        if (action != null && action.isNotEmpty) 'action': action,
        if (niveau != null && niveau.isNotEmpty) 'niveau': niveau,
        if (debut != null) 'debut': dateSeule(debut),
        if (fin != null) 'fin': dateSeule(fin),
        if (recherche != null && recherche.trim().isNotEmpty)
          'recherche': recherche.trim(),
      },
    );

    final String chemin = await _ecrireFichier(
      octets,
      'journal_audit_${dateCompacte(DateTime.now())}.pdf',
      mimeType: 'application/pdf',
    );

    // Trace de l'export (action RAPPORT → niveau INFO côté serveur).
    await logger(
      'RAPPORT',
      details: <String, dynamic>{
        'type': 'audit',
        'format': 'pdf',
        'nb_lignes': page.lignes.length,
        'total_ecran': page.total,
        'reference': reference,
        'empreinte': empreinte,
        'filtres': <String, dynamic>{
          if (action != null && action.isNotEmpty) 'action': action,
          if (niveau != null && niveau.isNotEmpty) 'niveau': niveau,
          if (debut != null) 'debut': dateSeule(debut),
          if (fin != null) 'fin': dateSeule(fin),
        },
      },
      entrepriseId: entrepriseId,
    );

    return chemin;
  }

  /// Construit le PDF du journal (séparé pour être testable sans écriture).
  Future<Uint8List> construirePDF({
    required List<EntreeAudit> lignes,
    required int total,
    required String portee,
    required String reference,
    required String empreinte,
    String? nomEntreprise,
    Map<String, dynamic>? filtres,
  }) async {
    final pw.Document document = pw.Document(
      title: 'Journal d\'audit — $reference',
      author: 'Biashara Yangu',
    );

    final DateTime genereLe = DateTime.now();
    final int nbImprimes = lignes.length;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (pw.Context context) => _entetePdf(
          nomEntreprise: nomEntreprise,
          portee: portee,
          filtres: filtres,
          total: total,
          nbImprimes: nbImprimes,
        ),
        footer: (pw.Context context) => _piedDePagePdf(
          context,
          reference: reference,
          empreinte: empreinte,
          genereLe: genereLe,
        ),
        build: (pw.Context context) => <pw.Widget>[
          pw.SizedBox(height: 10),
          _tableauPdf(lignes),
        ],
      ),
    );

    return document.save();
  }

  // ---------------------------------------------------------------------------
  // 4. OUTILS PURS (référence, empreinte, formats)
  // ---------------------------------------------------------------------------

  /// Référence lisible d'un export : `AUD-AAAAMMJJ-XXXXXX`.
  static String genererReferenceExport({DateTime? maintenant, String? suffixe}) {
    final DateTime date = maintenant ?? DateTime.now();
    final String jour = dateCompacte(date);

    String alea = suffixe ?? '';
    if (alea.isEmpty) {
      final Random hasard = Random.secure();
      final StringBuffer buffer = StringBuffer();
      for (int i = 0; i < 6; i++) {
        buffer.write(hasard.nextInt(16).toRadixString(16).toUpperCase());
      }
      alea = buffer.toString();
    }
    return 'AUD-$jour-$alea';
  }

  /// SHA-256 des entrées exportées + référence : « signe » le document.
  static String empreinteExport(List<EntreeAudit> lignes, String reference) {
    final String canonique = jsonEncode(<String, dynamic>{
      'reference': reference,
      'lignes': lignes
          .map((EntreeAudit e) => <String, dynamic>{
                'seq': e.seq,
                'id': e.id,
                'action': e.action,
                'niveau': e.niveau.code,
                'utilisateur': e.utilisateurId,
                'created_at': e.createdAt?.toIso8601String(),
              })
          .toList(growable: false),
    });
    return sha256.convert(utf8.encode(canonique)).toString();
  }

  /// Empreinte abrégée (12 caractères) affichée sur le document.
  static String empreinteCourte(String empreinte) => empreinte.length <= 12
      ? empreinte.toUpperCase()
      : empreinte.substring(0, 12).toUpperCase();

  /// `AAAA-MM-JJ` — convention de dates du projet (UTC).
  static String dateSeule(DateTime date) {
    final String mois = date.month.toString().padLeft(2, '0');
    final String jour = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mois-$jour';
  }

  static String dateCompacte(DateTime date) {
    final String mois = date.month.toString().padLeft(2, '0');
    final String jour = date.day.toString().padLeft(2, '0');
    return '${date.year}$mois$jour';
  }

  /// Extrait le message utilisateur d'une erreur serveur préfixée
  /// (`CODE|message`), comme les autres services du projet.
  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  static TypeErreurAudit _typeDepuisMessage(String brut) {
    final String code = brut.trim().split('|').first.trim().toUpperCase();
    switch (code) {
      case 'DROIT_REFUSE':
      case 'ACCES_REFUSE':
      case 'SESSION_ABSENTE':
      case 'HORS_BOUTIQUE':
        return TypeErreurAudit.droits;
      case 'AUDIT_ACTION_INVALIDE':
        return TypeErreurAudit.validation;
      default:
        return TypeErreurAudit.inconnu;
    }
  }

  // ---------------------------------------------------------------------------
  // 5. INTERNES
  // ---------------------------------------------------------------------------

  Future<T> _executer<T>(
    Future<T> Function() action, {
    required String actionLibelle,
  }) async {
    try {
      return await action();
    } on AuditServiceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('AuditService ($actionLibelle) : ${e.message}');
      throw AuditServiceException(
        messageErreur(e.message),
        type: _typeDepuisMessage(e.message),
      );
    } catch (e) {
      debugPrint('AuditService ($actionLibelle) : $e');
      throw const AuditServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurAudit.reseau,
      );
    }
  }

  /// Enregistre le fichier dans « Téléchargements/audit » (Android /
  /// Windows / Linux) ou le télécharge via le navigateur (web — PHASE F).
  Future<String> _ecrireFichier(
    Uint8List octets,
    String nomFichier, {
    String mimeType = 'application/octet-stream',
  }) async {
    try {
      return await enregistrerDansTelechargements(
            sousDossier: 'audit',
            nomFichier: nomFichier,
            octets: octets,
            mimeType: mimeType,
          ) ??
          nomFichier;
    } catch (e, st) {
      debugPrint('AuditService (écriture fichier) : $e\n$st');
      throw const AuditServiceException(
        "Impossible d'enregistrer le fichier. Vérifiez l'espace de stockage puis réessayez.",
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 6. RENDU PDF (PRIVÉ)
  // ---------------------------------------------------------------------------

  pw.Widget _entetePdf({
    String? nomEntreprise,
    required String portee,
    Map<String, dynamic>? filtres,
    required int total,
    required int nbImprimes,
  }) {
    final List<String> resumeFiltres = <String>[];
    (filtres ?? const <String, dynamic>{}).forEach((String cle, dynamic valeur) {
      if (valeur == null || valeur.toString().isEmpty) return;
      resumeFiltres.add('$cle : $valeur');
    });

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  'Journal d\'audit',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (nomEntreprise != null && nomEntreprise.isNotEmpty)
                  pw.Text(
                    _textePdf(nomEntreprise),
                    style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                  ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(
                color: PdfColors.blueGrey50,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                portee == 'plateforme' ? 'Portée : plateforme' : 'Portée : entreprise',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Entrées affichées : $nbImprimes sur $total — '
          'journal inaltérable (append-only, empreintes chaînées SHA-256).',
          style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
        ),
        if (resumeFiltres.isNotEmpty)
          pw.Text(
            'Filtres : ${resumeFiltres.join(' · ')}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        pw.Divider(height: 14, thickness: 0.8, color: PdfColors.grey400),
      ],
    );
  }

  pw.Widget _piedDePagePdf(
    pw.Context context, {
    required String reference,
    required String empreinte,
    required DateTime genereLe,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Divider(height: 10, thickness: 0.5, color: PdfColors.grey400),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              'Réf. $reference · empreinte ${empreinteCourte(empreinte)} · '
              'généré le ${formatDateHeure(genereLe)}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.Text(
              'Page ${context.pageNumber}/${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _tableauPdf(List<EntreeAudit> lignes) {
    final List<pw.TableRow> rangees = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
        children: <pw.Widget>[
          _celluleEntete('Date'),
          _celluleEntete('Utilisateur'),
          _celluleEntete('Action'),
          _celluleEntete('Niveau'),
          _celluleEntete('Détails'),
        ],
      ),
    ];

    for (final EntreeAudit entree in lignes) {
      rangees.add(pw.TableRow(
        children: <pw.Widget>[
          _cellule(formatDateHeure(entree.createdAt)),
          _cellule(entree.anonyme ? '(sans session)' : entree.utilisateur),
          _cellule(entree.libelleAction),
          _cellule(entree.niveau.libelle),
          _cellule(_resumeDetails(entree.details)),
        ],
      ));
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1.35),
        1: pw.FlexColumnWidth(1.15),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(0.7),
        4: pw.FlexColumnWidth(2.1),
      },
      children: rangees,
    );
  }

  pw.Widget _celluleEntete(String texte) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        texte,
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _cellule(String texte) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        _textePdf(texte),
        style: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  static String _resumeDetails(Map<String, dynamic> details) {
    if (details.isEmpty) return '—';
    try {
      final String texte = jsonEncode(details);
      return texte.length <= 120 ? texte : '${texte.substring(0, 117)}…';
    } catch (_) {
      return '—';
    }
  }

  /// Remplace les caractères non pris en charge par les polices PDF standard.
  static String _textePdf(String texte) =>
      texte.replaceAll('\u2014', '-').replaceAll('\u2013', '-');
}
