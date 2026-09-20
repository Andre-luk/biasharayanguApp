// lib/utils/image_locale.dart
//
// 🌐 PHASE F (web) — AFFICHAGE D'IMAGES « LOCALES ».
//
//   • natif : images de fichiers (`FileImage` / `Image.file`) ;
//   • web   : images par URL (`blob:` / `data:` / `http:`) — les chemins de
//     fichiers n'existent pas dans un navigateur.

export 'image_locale_stub.dart' if (dart.library.io) 'image_locale_native.dart';
