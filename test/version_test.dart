// test/version_test.dart
//
// 📌 GARDE-FOU DE VERSION.
//
// Le splash annonçait « v1.0.0 » et la page À propos « 3.2.0 (36) » alors que
// l'application était ailleurs. Ce test échoue dès que la version affichée
// n'est plus celle du `pubspec.yaml` : impossible de livrer une version
// mensongère au support.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/config/app_version.dart';

void main() {
  group('AppVersion', () {
    test('correspond exactement au pubspec.yaml', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final RegExp version = RegExp(r'^version:\s*([^\s#]+)', multiLine: true);
      final RegExpMatch? trouve = version.firstMatch(pubspec);

      expect(trouve, isNotNull, reason: 'pubspec.yaml sans ligne version:');
      expect(
        trouve!.group(1)!.trim(),
        '${AppVersion.numero}+${AppVersion.build}',
        reason: 'Mettre à jour AppVersion ET pubspec.yaml ensemble.',
      );
    });

    test('les libellés sont cohérents', () {
      expect(AppVersion.complet, '${AppVersion.numero} (${AppVersion.build})');
      expect(AppVersion.libelle, contains(AppVersion.numero));
      expect(AppVersion.mention, contains(AppVersion.build));
    });
  });
}
