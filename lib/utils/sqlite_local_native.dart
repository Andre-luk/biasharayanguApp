// lib/utils/sqlite_local_native.dart
//
// 🖥️📱 SQLite natif (Windows / Linux / macOS / Android / iOS) :
//   • ouverture FFI (sqflite_common_ffi) sur les plateformes de bureau ;
//   • chargement PRIORITAIRE de la bibliothèque embarquée du paquet
//     (`lib/libsqlite3.so` sur Linux, `sqlite3.dll` à côté du programme
//     sur Windows) — sans quoi : « Failed to load dynamic library ».

import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite_open;

/// Vrai : la base SQLite locale est utilisable sur cette plateforme.
bool get sqliteLocalDisponible => true;

bool _prepare = false;

/// Prépare SQLite (une seule fois) : FFI + bibliothèque embarquée.
void preparerSqliteLocal() {
  if (_prepare) return;
  _prepare = true;

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    _chargerSqlite3Embrique();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

/// 🐧🪟 SQLite EMBARQUÉ — le paquet Linux/Windows fournit sa propre
/// bibliothèque (`lib/libsqlite3.so` sur Linux, `sqlite3.dll` à côté du
/// programme sur Windows). On la charge en PRIORITÉ ; si elle est absente,
/// on retombe sur la bibliothèque du système.
void _chargerSqlite3Embrique() {
  try {
    final String dossier = File(Platform.resolvedExecutable).parent.path;
    final String? candidat = Platform.isLinux
        ? join(dossier, 'lib', 'libsqlite3.so')
        : Platform.isWindows
            ? join(dossier, 'sqlite3.dll')
            : null;
    if (candidat == null || !File(candidat).existsSync()) return;

    sqlite_open.open.overrideFor(
      Platform.isLinux
          ? sqlite_open.OperatingSystem.linux
          : sqlite_open.OperatingSystem.windows,
      () => DynamicLibrary.open(candidat),
    );
    debugPrint('SQLite embarqué chargé : $candidat');
  } catch (e) {
    debugPrint('SQLite embarqué non chargé (bibliothèque système utilisée) : $e');
  }
}
