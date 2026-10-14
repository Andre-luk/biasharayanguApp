// test/montant_saisi_test.dart
//
// Lecture d'un montant SAISI À LA MAIN.
//
// Ce test garde une correction précise : « 30.000 » (trente mille, écriture
// courante en RDC) était lu **30** par `double.tryParse`. Le prix saisi devenait
// donc dérisoire sans le moindre message — d'où le constat « le prix que je
// donne ne joue aucun rôle, c'est le pack qui est pris ».
//
//     flutter test test/montant_saisi_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/utils/format_utils.dart';

void main() {
  group('parseMontantSaisi — séparateur de milliers', () {
    test('« 30.000 » vaut trente mille, pas trente', () {
      expect(parseMontantSaisi('30.000'), 30000);
      expect(parseMontantSaisi('30,000'), 30000);
      expect(parseMontantSaisi('30 000'), 30000);
      expect(parseMontantSaisi('30000'), 30000);
    });

    test('milliers et devise collée', () {
      expect(parseMontantSaisi('30 000 CDF'), 30000);
      expect(parseMontantSaisi('1.500.000 CDF'), 1500000);
      expect(parseMontantSaisi('30000 FC'), 30000);
    });

    test('espace insécable et espaces multiples', () {
      expect(parseMontantSaisi('30\u00A0000'), 30000);
      expect(parseMontantSaisi('  12   500  '), 12500);
    });
  });

  group('parseMontantSaisi — parties décimales', () {
    test('un ou deux chiffres après le séparateur = décimales', () {
      expect(parseMontantSaisi('12,5'), 12.5);
      expect(parseMontantSaisi('30 000,50'), 30000.50);
      expect(parseMontantSaisi('1.500,50'), 1500.50);
      expect(parseMontantSaisi('12.50'), 12.50);
    });

    test('trois chiffres après le séparateur = milliers', () {
      expect(parseMontantSaisi('1.500'), 1500);
      expect(parseMontantSaisi('1,500'), 1500);
      expect(parseMontantSaisi('1.000.000'), 1000000);
    });

    test('décimal sans partie entière', () {
      expect(parseMontantSaisi(',50'), 0.50);
      expect(parseMontantSaisi('.75'), 0.75);
    });
  });

  group('parseMontantSaisi — saisies inutilisables', () {
    test('vide ou illisible renvoie null (jamais un montant inventé)', () {
      expect(parseMontantSaisi(null), isNull);
      expect(parseMontantSaisi(''), isNull);
      expect(parseMontantSaisi('   '), isNull);
      expect(parseMontantSaisi('abc'), isNull);
      expect(parseMontantSaisi('CDF'), isNull);
    });

    test('zéro reste lisible', () {
      expect(parseMontantSaisi('0'), 0);
    });

    test('négatif conservé (utile aux ajustements)', () {
      expect(parseMontantSaisi('-1.500'), -1500);
    });
  });
}
