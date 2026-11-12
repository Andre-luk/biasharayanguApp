// lib/utils/partage_pdf_native.dart
//
// 📤 PARTAGE D'UN PDF — natif (`dart:io`) : Android, iOS, Linux, Windows, macOS.
//
// POURQUOI CE FICHIER EXISTE
// --------------------------
// `Printing.sharePdf` fait deux choses TRÈS différentes selon la plateforme :
//
//   • Android / iOS : feuille de partage du système avec le VRAI fichier PDF
//     joint — c'est exactement ce qu'il faut pour WhatsApp ;
//   • Linux / Windows : écrit `/tmp/facture-….pdf` puis lance `xdg-open`
//     (ou l'équivalent). Si le système n'a aucune application associée au
//     PDF, l'utilisateur reçoit « ce fichier ne contient pas d'application
//     associée… » et le fichier est perdu dans /tmp.
//
// Sur ordinateur on enregistre donc le PDF dans « Téléchargements/Biashara
// Yangu/Factures » (fichier durable, nommé proprement) puis on essaie, dans
// l'ordre, plusieurs ouvreurs connus avant de se rabattre sur le dossier.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' show basename, join;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:biashara_yangu/models/resultat_partage.dart';
import 'package:biashara_yangu/utils/fichiers_locaux.dart';

/// Sous-dossier des factures enregistrées sur ordinateur.
const String dossierFactures = 'Biashara Yangu/Factures';

/// Nettoie un nom de fichier et garantit l'extension `.pdf`.
String nomFichierPdf(String brut) {
  String nom = brut.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
  if (nom.isEmpty) nom = 'document';
  if (!nom.toLowerCase().endsWith('.pdf')) nom = '$nom.pdf';
  return nom;
}

/// Partage (ou enregistre) [octets] comme FICHIER PDF.
///
/// [texte] accompagne le fichier (corps du message WhatsApp / e-mail) sur
/// mobile ; il est ignoré sur ordinateur où il n'existe pas de feuille de
/// partage avec pièce jointe.
Future<ResultatPartage> partagerPdf(
  Uint8List octets, {
  required String nomFichier,
  String? texte,
  String? sujet,
}) async {
  final String nom = nomFichierPdf(nomFichier);

  // 📱 Mobile : la feuille de partage reçoit le PDF lui-même. C'est le seul
  // chemin qui permet d'envoyer RÉELLEMENT le fichier sur WhatsApp (un lien
  // `wa.me` ne transporte que du texte).
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final bool ok = await Printing.sharePdf(
        bytes: octets,
        filename: nom,
        subject: sujet,
        body: texte,
      );
      if (ok) {
        return const ResultatPartage(
          mode: ModePartage.feuilleDePartage,
          message: 'Facture prête : choisissez WhatsApp (ou une autre '
              'application) pour envoyer le PDF.',
          fichierJoint: true,
        );
      }
    } catch (e) {
      debugPrint('Partage du PDF (mobile) : $e');
    }
    // Repli : on enregistre au moins le fichier.
    final String? chemin = await enregistrerPdf(octets, nomFichier: nom);
    return ResultatPartage(
      mode: chemin == null ? ModePartage.echec : ModePartage.enregistre,
      message: chemin == null
          ? 'Le partage du PDF a échoué sur cet appareil.'
          : 'PDF enregistré dans vos documents : $chemin',
      chemin: chemin,
    );
  }

  // 🖥️ Ordinateur : on enregistre d'abord, ensuite on ouvre.
  final String? chemin = await enregistrerPdf(octets, nomFichier: nom);
  if (chemin == null) {
    return const ResultatPartage.echec(
      'Impossible d\'enregistrer le PDF sur cet ordinateur.',
    );
  }

  final bool ouvert = await ouvrirFichier(chemin);
  if (ouvert) {
    return ResultatPartage(
      mode: ModePartage.enregistre,
      message: 'Facture enregistrée et ouverte : $chemin',
      chemin: chemin,
      fichierJoint: true,
    );
  }

  await ouvrirDossier(chemin);
  return ResultatPartage(
    mode: ModePartage.enregistre,
    message: 'Facture enregistrée dans « $dossierFactures » : $chemin\n'
        'Aucun lecteur PDF n\'a pu être lancé automatiquement — le dossier '
        'vient de s\'ouvrir.',
    chemin: chemin,
    fichierJoint: true,
  );
}

/// Écrit le PDF sur le disque et renvoie son chemin, ou `null` en cas d'échec.
Future<String?> enregistrerPdf(
  Uint8List octets, {
  required String nomFichier,
}) async {
  try {
    return await enregistrerDansTelechargements(
      sousDossier: dossierFactures,
      nomFichier: nomFichierPdf(nomFichier),
      octets: octets,
      mimeType: 'application/pdf',
    );
  } catch (e) {
    debugPrint('Enregistrement du PDF : $e');
    return null;
  }
}

/// Ouvre [chemin] avec l'application par défaut — puis avec des lecteurs PDF
/// connus si l'association du système est cassée.
Future<bool> ouvrirFichier(String chemin) async {
  if (Platform.isWindows) {
    return _lancer(<String>['cmd', '/c', 'start', '', chemin]);
  }
  if (Platform.isMacOS) {
    return _lancer(<String>['open', chemin]);
  }
  // Linux : le gestionnaire de fichiers (gio/open) est le plus respectueux
  // des préférences, mais une association morte (`xreader.desktop` sans
  // binaire, par exemple) renvoie une erreur — on essaie alors les lecteurs.
  for (final List<String> commande in <List<String>>[
    <String>['gio', 'open', chemin],
    <String>['xdg-open', chemin],
    <String>['evince', chemin],
    <String>['okular', chemin],
    <String>['xreader', chemin],
    <String>['firefox', chemin],
  ]) {
    if (await _lancer(commande)) return true;
  }
  return false;
}

/// Ouvre le dossier contenant [chemin] (repli quand aucun lecteur ne répond).
Future<bool> ouvrirDossier(String chemin) async {
  final String dossier = File(chemin).parent.path;
  if (Platform.isWindows) {
    return _lancer(<String>['explorer', dossier]);
  }
  if (Platform.isMacOS) {
    return _lancer(<String>['open', dossier]);
  }
  for (final List<String> commande in <List<String>>[
    <String>['gio', 'open', dossier],
    <String>['xdg-open', dossier],
    <String>['nautilus', dossier],
  ]) {
    if (await _lancer(commande)) return true;
  }
  return false;
}

/// Ouvre la conversation WhatsApp de [numero] avec [texte] pré-rempli.
///
/// Le fichier, lui, doit avoir été enregistré par [partagerPdf] : sur
/// ordinateur WhatsApp Desktop ne sait pas recevoir une pièce jointe par lien.
Future<bool> ouvrirWhatsApp(String numero, {String? texte}) async {
  final String chiffres = numero.replaceAll(RegExp(r'[^0-9]'), '');
  if (chiffres.isEmpty) return false;
  final Uri lien = Uri.parse(
    'https://wa.me/$chiffres'
    '${texte == null || texte.isEmpty ? '' : '?text=${Uri.encodeComponent(texte)}'}',
  );
  try {
    return await launchUrl(lien, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('Ouverture de WhatsApp : $e');
    return false;
  }
}

/// Lance une commande et dit si elle a démarré sans erreur.
///
/// Un délai court évite de bloquer l'interface si l'application ne rend pas
/// la main (certains lecteurs restent ouverts au premier plan).
Future<bool> _lancer(List<String> commande) async {
  try {
    final ProcessResult r = await Process.run(
      commande.first,
      commande.sublist(1),
    ).timeout(
      const Duration(seconds: 8),
      onTimeout: () => ProcessResult(0, 0, '', ''),
    );
    return r.exitCode == 0;
  } on ProcessException catch (e) {
    debugPrint('Commande indisponible (${commande.first}) : $e');
    return false;
  } catch (e) {
    debugPrint('Échec de ${commande.join(' ')} : $e');
    return false;
  }
}

/// Chemin lisible pour l'utilisateur (dossier + nom).
String cheminCourt(String chemin) =>
    join(File(chemin).parent.path, basename(chemin));
