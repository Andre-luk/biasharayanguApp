// lib/utils/image_locale_native.dart
//
// 🖥️📱 Images de fichiers natifs (`dart:io`) — `FileImage` / `Image.file`
// et lecture directe des octets.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Affiche une image depuis un chemin de fichier local.
Widget imageFichierLocal(
  String chemin, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return Image.file(
    File(chemin),
    width: width,
    height: height,
    fit: fit,
    errorBuilder: errorBuilder,
  );
}

/// Fournisseur d'image (avatars…) depuis un chemin de fichier local.
ImageProvider imageProviderLocal(String chemin) => FileImage(File(chemin));

/// Le fichier image existe-t-il sur le disque ?
bool imageLocaleExiste(String chemin) => File(chemin).existsSync();

/// Variante « si existe » : `null` quand le fichier n'existe plus.
ImageProvider? imageProviderLocalSiExiste(String chemin) {
  final File fichier = File(chemin);
  return fichier.existsSync() ? FileImage(fichier) : null;
}

/// Lit les octets du fichier — `null` s'il n'existe plus.
Future<Uint8List?> lireOctetsFichierLocal(String chemin) async {
  final File fichier = File(chemin);
  if (!await fichier.exists()) return null;
  return fichier.readAsBytes();
}
