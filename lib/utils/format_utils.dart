// lib/utils/format_utils.dart
//
// Utilitaires d'affichage (montants, dates) pour l'interface d'administration.
//
// Le formatage est volontairement manuel : il ne dépend ni de la locale
// initialisée dans `main.dart`, ni du fuseau horaire de l'appareil.

/// Devise utilisée par l'application.
const String deviseParDefaut = 'CDF';

/// Formate un montant avec séparateur de milliers (espace) et la devise.
///
/// Exemple : `15000.0` devient `15 000 CDF`.
String formatMontant(double montant, {String devise = deviseParDefaut}) {
  final int arrondi = montant.round();
  final bool negatif = arrondi < 0;
  final String chiffres = arrondi.abs().toString();

  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) {
      buffer.write(' ');
    }
    buffer.write(chiffres[i]);
  }

  return '${negatif ? '-' : ''}$buffer $devise';
}

/// Formate une date au format `jj/mm/aaaa`.
///
/// Renvoie [valeurAbsente] si [date] est `null`.
String formatDate(DateTime? date, {String valeurAbsente = '—'}) {
  if (date == null) return valeurAbsente;

  final DateTime locale = date.toLocal();
  final String jour = locale.day.toString().padLeft(2, '0');
  final String mois = locale.month.toString().padLeft(2, '0');

  return '$jour/$mois/${locale.year}';
}

/// Formate une date et son heure au format `jj/mm/aaaa à hh:mm`.
String formatDateHeure(DateTime? date, {String valeurAbsente = '—'}) {
  if (date == null) return valeurAbsente;

  final DateTime locale = date.toLocal();
  final String heures = locale.hour.toString().padLeft(2, '0');
  final String minutes = locale.minute.toString().padLeft(2, '0');

  return '${formatDate(date)} à $heures:$minutes';
}

/// Formate une quantité de stock : entier sans décimale, sinon 2 décimales
/// significatives (ex. `85`, `10.5`).
String formatQuantite(double quantite, {String valeurAbsente = '—'}) {
  if (quantite.isNaN) return valeurAbsente;
  if (quantite == quantite.roundToDouble()) return quantite.toStringAsFixed(0);
  return quantite
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// Formate une quantité signée d'écart de stock : `+8`, `-3`, `0`.
String formatQuantiteSignee(double quantite) {
  if (quantite > 0) return '+${formatQuantite(quantite)}';
  return formatQuantite(quantite);
}
