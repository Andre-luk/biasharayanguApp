// lib/config/app_version.dart
//
// 📌 SOURCE UNIQUE DE LA VERSION AFFICHÉE.
//
// Constat : le splash annonçait « v1.0.0 », la page À propos « 3.2.0 (36) »
// alors que le pubspec était déjà ailleurs. Un commerçant qui appelle le
// support doit pouvoir lire UNE version, la vraie.
//
// ⚠️ À chaque publication : mettre à jour `version:` dans `pubspec.yaml`
//    ET les deux constantes ci-dessous (elles doivent rester identiques).

class AppVersion {
  AppVersion._();

  /// Version commerciale (sans le « +build »).
  static const String numero = '3.10.4';

  /// Numéro de build Android / iOS.
  static const String build = '61';

  /// « 3.4.0 » — usage courant dans les textes.
  static const String court = numero;

  /// « 3.4.0 (42) » — écrans techniques, support, à propos.
  static const String complet = '$numero ($build)';

  /// « Version 3.4.0 (42) » — pied de page.
  static const String libelle = 'Version $complet';

  /// « Biashara Yangu • v3.4.0 (42) » — splash / connexion.
  static const String mention = 'Biashara Yangu • v$complet';
}
