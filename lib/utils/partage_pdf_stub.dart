// lib/utils/partage_pdf_stub.dart
//
// 🌐 PARTAGE D'UN PDF — WEB : le navigateur télécharge le fichier.

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:biashara_yangu/models/resultat_partage.dart';

/// Sous-dossier des factures enregistrées sur ordinateur.
const String dossierFactures = 'Biashara Yangu/Factures';

/// Nettoie un nom de fichier et garantit l'extension `.pdf`.
String nomFichierPdf(String brut) {
  String nom = brut.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
  if (nom.isEmpty) nom = 'document';
  if (!nom.toLowerCase().endsWith('.pdf')) nom = '$nom.pdf';
  return nom;
}

/// Partage (en réalité : téléchargement) du PDF sur le web.
Future<ResultatPartage> partagerPdf(
  Uint8List octets, {
  required String nomFichier,
  String? texte,
  String? sujet,
}) async {
  try {
    final bool ok = await Printing.sharePdf(
      bytes: octets,
      filename: nomFichier,
    );
    if (ok) {
      return const ResultatPartage(
        mode: ModePartage.telecharge,
        message: 'PDF téléchargé — joignez-le à votre message WhatsApp.',
        fichierJoint: true,
      );
    }
  } catch (e) {
    debugPrint('Partage du PDF (web) : $e');
  }
  return const ResultatPartage.echec('Téléchargement du PDF impossible ici.');
}

/// Sur le web il n'y a pas de disque : rien à enregistrer séparément.
Future<String?> enregistrerPdf(
  Uint8List octets, {
  required String nomFichier,
}) async =>
    null;

Future<bool> ouvrirFichier(String chemin) async => false;

Future<bool> ouvrirDossier(String chemin) async => false;

/// Ouvre WhatsApp Web avec le message pré-rempli.
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
    debugPrint('Ouverture de WhatsApp (web) : $e');
    return false;
  }
}
