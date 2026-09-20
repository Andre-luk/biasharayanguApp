// lib/utils/sqlite_local.dart
//
// 🌐 PHASE F (web) — SQLITE LOCAL (bureau / mobile).
//
// Délègue la préparation de SQLite natif (sqflite_common_ffi + bibliothèque
// embarquée) aux plateformes natives ; sur le web, SQLite n'existe PAS :
// `sqliteLocalDisponible` vaut `false` et la base locale est désactivée
// (l'application web fonctionne entièrement sur Supabase).

export 'sqlite_local_stub.dart' if (dart.library.io) 'sqlite_local_native.dart';
