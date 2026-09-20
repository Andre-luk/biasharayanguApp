// lib/utils/fichiers_locaux_native.dart
//
// 🖥️📱 Enregistrement de fichiers dans « Téléchargements » (repli :
// documents de l'application) — natif uniquement (`dart:io`).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' show basename, dirname, join;
import 'package:path_provider/path_provider.dart';

/// Enregistre [octets] dans le sous-dossier des téléchargements et renvoie
/// le chemin COMPLET du fichier créé.
Future<String?> enregistrerDansTelechargements({
  required String sousDossier,
  required String nomFichier,
  required List<int> octets,
  String mimeType = 'application/octet-stream',
}) async {
  Directory? base;
  try {
    base = await getDownloadsDirectory();
  } catch (e) {
    debugPrint('Téléchargements indisponibles (repli documents) : $e');
  }
  base ??= await getApplicationDocumentsDirectory();

  final Directory dossier = Directory(join(base.path, sousDossier));
  if (!await dossier.exists()) {
    await dossier.create(recursive: true);
  }

  final File fichier = File(join(dossier.path, nomFichier));
  await fichier.writeAsBytes(octets, flush: true);
  return fichier.path;
}

/// Le fichier existe-t-il sur le disque ?
Future<bool> fichierLocalExiste(String chemin) => File(chemin).exists();

/// Copie un fichier (sauvegarde / restauration de la base locale).
Future<void> copierFichierLocal({
  required String depuis,
  required String vers,
}) async {
  await File(depuis).copy(vers);
}

/// Dernière sauvegarde `biashara_yangu_backup_*.db` à côté de la base.
Future<String?> trouverDernierBackupLocal(String cheminBase) async {
  try {
    final Directory dossier = Directory(dirname(cheminBase));
    if (!await dossier.exists()) return null;
    final List<File> backups = dossier
        .listSync()
        .whereType<File>()
        .where((File f) =>
            f.path.endsWith('.db') &&
            basename(f.path).startsWith('biashara_yangu_backup'))
        .toList();
    if (backups.isEmpty) return null;
    backups.sort((File a, File b) =>
        b.statSync().modified.compareTo(a.statSync().modified));
    return backups.first.path;
  } catch (_) {
    return null;
  }
}
