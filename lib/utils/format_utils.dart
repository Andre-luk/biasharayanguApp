// lib/utils/format_utils.dart
//
// Utilitaires d'affichage (montants, dates) pour l'interface d'administration.
//
// Le formatage est volontairement manuel : il ne dépend ni de la locale
// initialisée dans `main.dart`, ni du fuseau horaire de l'appareil.

/// Devise de la PLATEFORME (abonnements, tarifs, back-office).
const String deviseParDefaut = 'CDF';

/// 🪙 MODULE 18 — DEVISE ACTIVE de l'entreprise connectée.
///
/// Mise à jour par `DeviseService` dès que l'état de la devise est chargé
/// (démarrage, connexion, bascule d'entreprise). Comme tous les écrans
/// passent par [formatMontant], la devise choisie se propage AUTOMATIQUEMENT
/// aux prix d'achat / de vente, ventes, dépenses, caisse, rapports, reçus…
class FormatMonetaire {
  FormatMonetaire._();

  static String _code = deviseParDefaut;
  static String _symbole = 'CDF';

  /// Code de la devise active (`CDF`, `USD`).
  static String get code => _code;

  /// Unité affichée (`CDF`, `$`).
  static String get symbole => _symbole;

  /// Applique la devise de l'entreprise (`code` + `symbole`).
  static void definir({required String code, required String symbole}) {
    _code = code;
    _symbole = symbole;
  }

  /// Revient au comportement historique (CDF) — déconnexion.
  static void reinitialiser() {
    definir(code: deviseParDefaut, symbole: 'CDF');
  }
}

/// Sépare les milliers par une espace : `1234567` → `1 234 567`.
String _milliers(String chiffres) {
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) {
      buffer.write(' ');
    }
    buffer.write(chiffres[i]);
  }
  return buffer.toString();
}

/// Signe éventuel d'un montant négatif.
String _signe(double montant) => montant < 0 ? '-' : '';

/// Formate un montant avec séparateur de milliers (espace) et la devise.
///
/// Exemples :
///   • `15000` → `15 000 CDF` (franc congolais, entier) ;
///   • `12.5`  → `12,50 $`   (dollar américain, les cents comptent).
///
/// [devise] permet de forcer l'unité affichée (back-office plateforme :
/// `devise: deviseParDefaut`), sinon la devise active est utilisée.
String formatMontant(double montant, {String? devise}) {
  final String unite = devise ?? FormatMonetaire.symbole;

  if (unite == r'$') {
    final String fixe = montant.abs().toStringAsFixed(2);
    final List<String> parties = fixe.split('.');
    return '${_signe(montant)}${_milliers(parties.first)},${parties.last} $unite';
  }

  final String chiffres = montant.abs().round().toString();
  return '${_signe(montant)}${_milliers(chiffres)} $unite';
}

/// Lit un montant SAISI À LA MAIN, sans se tromper de convention.
///
/// Sans cela, « 30.000 » (trente mille, comme on l'écrit ici) était lu **30** :
/// le prix saisi devenait dérisoire sans que rien ne le signale. C'est
/// précisément ce qui faisait dire « le prix que je donne ne joue pas de rôle ».
///
/// Accepte `30 000`, `30.000`, `30,000`, `30 000,50`, `1.500,50`, `12,5`,
/// `30000`, avec ou sans devise (`30 000 CDF`).
///
/// Règle : le DERNIER séparateur est décimal **seulement s'il est suivi d'un ou
/// deux chiffres** ; sinon c'est un séparateur de milliers.
///
/// Renvoie `null` si l'on ne peut rien lire : l'appelant décide alors quoi
/// afficher (jamais un montant inventé).
double? parseMontantSaisi(String? texte) {
  if (texte == null) return null;

  // On ne garde que les chiffres et les séparateurs : espaces insécables,
  // « CDF », « $ », « FC »… n'ont rien à faire dans un calcul.
  final String nettoye =
      texte.trim().replaceAll(RegExp(r'[^0-9.,\-]'), '');
  if (nettoye.isEmpty) return null;

  final int dernierPoint = nettoye.lastIndexOf('.');
  final int derniereVirgule = nettoye.lastIndexOf(',');
  final int dernier =
      dernierPoint > derniereVirgule ? dernierPoint : derniereVirgule;

  if (dernier < 0) return double.tryParse(nettoye);

  final String apres = nettoye.substring(dernier + 1);
  final String avant =
      nettoye.substring(0, dernier).replaceAll(RegExp(r'[.,]'), '');

  // Un ou deux chiffres après le séparateur → c'est une partie décimale.
  if (apres.isNotEmpty && apres.length <= 2) {
    final String entier = avant.isEmpty ? '0' : avant;
    return double.tryParse('$entier.$apres');
  }

  // Sinon c'est un séparateur de milliers : on le retire.
  return double.tryParse(nettoye.replaceAll(RegExp(r'[.,]'), ''));
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
