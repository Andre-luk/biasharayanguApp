// lib/utils/json_parsing.dart
//
// Helpers de conversion tolérants pour les données renvoyées par Supabase.
//
// PostgREST déduit le type Dart d'une colonne PostgreSQL au moment du parsing :
// une colonne `numeric` contenant `5000` peut donc arriver en `int` alors que
// l'application attend un `double`. Ces fonctions évitent les `TypeError`
// silencieux en production.

/// Convertit [value] en `double` sans jamais lever d'exception.
double parseDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

/// Convertit [value] en `double`, en renvoyant `null` si la valeur est absente
/// (utile pour les colonnes numériques optionnelles).
double? parseDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

/// Convertit [value] en `int` sans jamais lever d'exception.
int parseInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

/// Convertit [value] en `String` non nulle.
String parseString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  return value.toString();
}

/// Convertit [value] en `String`, en renvoyant `null` si la valeur est absente
/// ou vide (utile pour les colonnes `uuid`/`text` optionnelles).
String? parseStringOrNull(dynamic value) {
  if (value == null) return null;
  final String texte = value.toString().trim();
  return texte.isEmpty ? null : texte;
}

/// Convertit [value] en `DateTime`, en renvoyant `null` si la conversion échoue.
DateTime? parseDateTimeOrNull(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

/// Convertit [value] en `bool` sans jamais lever d'exception.
///
/// PostgreSQL rend `true`/`false`, mais un JSON passé par un `jsonb_build_object`
/// peut arriver en texte (`"true"`), en entier (`1`) ou être absent.
bool parseBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final String texte = value.toString().trim().toLowerCase();
  if (texte == 'true' || texte == 't' || texte == '1' || texte == 'oui') {
    return true;
  }
  if (texte == 'false' || texte == 'f' || texte == '0' || texte == 'non') {
    return false;
  }
  return fallback;
}

/// Convertit une réponse PostgREST en `List<Map<String, dynamic>>`.
///
/// Toute forme inattendue (null, réponse objet unique) produit une liste vide
/// plutôt qu'une exception.
List<Map<String, dynamic>> parseMapList(dynamic data) {
  if (data is! List) return const <Map<String, dynamic>>[];
  return data
      .whereType<Map>()
      .map((Map element) => Map<String, dynamic>.from(element))
      .toList();
}

/// Convertit une réponse PostgREST en `Map<String, dynamic>` unique.
Map<String, dynamic>? parseMap(dynamic data) {
  if (data is! Map) return null;
  return Map<String, dynamic>.from(data);
}
