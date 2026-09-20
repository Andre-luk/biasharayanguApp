// lib/utils/fichiers_locaux_stub.dart
//
// 🌐 PHASE F (web) — Téléchargement de fichiers via le NAVIGATEUR :
// un blob est créé puis « cliqué » comme un lien de téléchargement.

import 'dart:html' as html;
import 'dart:typed_data';

/// Déclenche le téléchargement du navigateur. Renvoie `null` (aucun chemin
/// local : le fichier va dans les téléchargements du navigateur).
Future<String?> enregistrerDansTelechargements({
  required String sousDossier,
  required String nomFichier,
  required List<int> octets,
  String mimeType = 'application/octet-stream',
}) async {
  final html.Blob blob = html.Blob(<Object>[Uint8List.fromList(octets)], mimeType);
  final String url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = nomFichier
    ..click();
  html.Url.revokeObjectUrl(url);
  return null;
}

/// Faux : aucun fichier local dans un navigateur.
Future<bool> fichierLocalExiste(String chemin) async => false;

/// Copie de fichiers indisponible dans un navigateur.
Future<void> copierFichierLocal({
  required String depuis,
  required String vers,
}) async {
  throw UnsupportedError('Copie de fichiers indisponible sur le web.');
}

/// Aucun dossier de sauvegarde locale dans un navigateur.
Future<String?> trouverDernierBackupLocal(String cheminBase) async => null;
