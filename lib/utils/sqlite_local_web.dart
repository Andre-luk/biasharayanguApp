// lib/utils/sqlite_local_web.dart
//
// 🌐 VERSION WEB — SQLITE DANS LE NAVIGATEUR.
//
// Pendant longtemps la version web était bridée : sans SQLite, l'application
// ne pouvait RIEN enregistrer (les comptes créés hors ligne, les ventes, le
// stock… tout vit dans la base locale avant d'être synchronisé). Résultat :
// la connexion aboutissait côté Supabase puis se cassait au premier accès à
// la base locale — « je clique sur Se connecter et il ne se passe rien ».
//
// On utilise ici l'implémentation officielle du projet sqflite : SQLite
// compilé en WebAssembly, exécuté dans un worker et PERSISTÉ dans
// IndexedDB. Le code de l'application ne change pas d'une ligne : c'est le
// même `DBHelper`, le même schéma, les mêmes requêtes SQL que sur Android ou
// sur ordinateur, donc les mêmes fonctionnalités et la même synchronisation.
//
// ⚠️ Dépend de deux fichiers placés dans `web/` par
//    `dart run sqflite_common_ffi_web:setup` :
//      • `sqlite3.wasm`   — le moteur SQLite
//      • `sqflite_sw.js`  — le worker qui le fait tourner
//    Ils sont versionnés dans le dépôt pour que le site se reconstruise
//    partout, sans accès réseau supplémentaire.

import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Vrai : la base SQLite locale est utilisable dans le navigateur.
bool get sqliteLocalDisponible => true;

bool _prepare = false;

/// Prépare SQLite (une seule fois) : fabrique « web » adossée à IndexedDB.
void preparerSqliteLocal() {
  if (_prepare) return;
  _prepare = true;
  databaseFactory = databaseFactoryFfiWeb;
}
