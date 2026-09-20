// lib/utils/image_locale_stub.dart
//
// 🌐 PHASE F (web) — Images par URL : `blob:` (fichier choisi localement)
// et `data:`/`http(s):` fonctionnent via `Image.network` / `NetworkImage`.

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Affiche une image à partir d'un chemin/URL compatible navigateur.
Widget imageFichierLocal(
  String chemin, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return Image.network(
    chemin,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: errorBuilder,
  );
}

/// Dans un navigateur, un `blob:` est toujours accessible.
bool imageLocaleExiste(String chemin) => true;

/// Fournisseur d'image (avatars…) compatible navigateur.
ImageProvider imageProviderLocal(String chemin) => NetworkImage(chemin);

/// Variante « si existe » : toujours non-nulle sur le web.
ImageProvider? imageProviderLocalSiExiste(String chemin) =>
    NetworkImage(chemin);

/// Lit les octets d'un `blob:`/`data:`/`http(s):` — `null` si introuvable.
Future<Uint8List?> lireOctetsFichierLocal(String chemin) async {
  try {
    final html.HttpRequest reponse = await html.HttpRequest.request(
      chemin,
      responseType: 'arraybuffer',
    );
    final dynamic data = reponse.response;
    if (data is ByteBuffer) return data.asUint8List();
    if (data is List<int>) return Uint8List.fromList(data);
    return null;
  } catch (e) {
    debugPrint('Lecture de $chemin impossible : $e');
    return null;
  }
}
