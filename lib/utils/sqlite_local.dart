// lib/utils/sqlite_local.dart
//
// 🌐 SQLITE LOCAL — sélection de l'implémentation selon la plateforme.
//
//   • Android / iOS / Windows / Linux / macOS → `sqlite_local_native.dart`
//     (sqflite + bibliothèque SQLite embarquée) ;
//   • navigateur → `sqlite_local_web.dart` (SQLite compilé en WebAssembly,
//     persisté dans IndexedDB) : la version web a donc ELLE AUSSI sa propre
//     base locale, exactement comme les applications installées.
//
// La bascule est faite par le compilateur : `dart.library.io` n'existe pas
// dans un navigateur.

export 'sqlite_local_web.dart' if (dart.library.io) 'sqlite_local_native.dart';
