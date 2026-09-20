// lib/utils/sqlite_local_stub.dart
//
// 🌐 PHASE F (web) — SQLite indisponible dans le navigateur : la base
// locale est désactivée, l'application travaille uniquement avec Supabase.

/// Faux : aucune base SQLite locale n'est disponible sur le web.
bool get sqliteLocalDisponible => false;

/// No-op : rien à préparer sans SQLite.
void preparerSqliteLocal() {}
