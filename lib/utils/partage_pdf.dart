// lib/utils/partage_pdf.dart
//
// 📤 POINT D'ENTRÉE UNIQUE POUR PARTAGER UN PDF.
//
//   • Android / iOS        → feuille de partage avec le FICHIER joint
//   • Ordi (Linux/Win/mac) → enregistré dans « Téléchargements/Biashara
//                            Yangu/Factures » puis ouvert (avec repli sur des
//                            lecteurs connus, puis sur le dossier)
//   • Web                  → téléchargé par le navigateur
//
// Aucun écran n'appelle plus `Printing.sharePdf` directement : c'est ici que
// se règle le « ce fichier ne contient pas d'application associée… » de Linux.

import 'dart:typed_data';

import 'package:biashara_yangu/models/resultat_partage.dart';

import 'package:biashara_yangu/utils/partage_pdf_stub.dart'
    if (dart.library.io) 'package:biashara_yangu/utils/partage_pdf_native.dart'
    as impl;

export 'package:biashara_yangu/models/resultat_partage.dart';
export 'package:biashara_yangu/utils/partage_pdf_stub.dart'
    if (dart.library.io) 'package:biashara_yangu/utils/partage_pdf_native.dart'
    show
        enregistrerPdf,
        nomFichierPdf,
        ouvrirDossier,
        ouvrirFichier,
        ouvrirWhatsApp,
        partagerPdf;

/// Raccourci lisible : `PartagePdf.partager(octets, nomFichier: …)`.
class PartagePdf {
  const PartagePdf._();

  /// Partage le PDF comme FICHIER (jamais comme texte seul).
  static Future<ResultatPartage> partager(
    Uint8List octets, {
    required String nomFichier,
    String? texte,
    String? sujet,
  }) =>
      impl.partagerPdf(
        octets,
        nomFichier: nomFichier,
        texte: texte,
        sujet: sujet,
      );

  /// Enregistre sans ouvrir (téléchargement silencieux).
  static Future<String?> enregistrer(
    Uint8List octets, {
    required String nomFichier,
  }) =>
      impl.enregistrerPdf(octets, nomFichier: nomFichier);

  /// Ouvre un fichier déjà enregistré avec l'application du système.
  static Future<bool> ouvrir(String chemin) => impl.ouvrirFichier(chemin);

  /// Ouvre le dossier contenant [chemin].
  static Future<bool> ouvrirLeDossier(String chemin) =>
      impl.ouvrirDossier(chemin);

  /// Ouvre une conversation WhatsApp avec un message pré-rempli.
  static Future<bool> whatsApp(String numero, {String? texte}) =>
      impl.ouvrirWhatsApp(numero, texte: texte);
}
