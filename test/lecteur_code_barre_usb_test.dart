// test/lecteur_code_barre_usb_test.dart
//
// 🔌 MODULE 28 — LECTEUR DE CODES-BARRES USB (CLAVIER HID).
//
// Ces tests vérifient la SEULE chose qui compte : distinguer
//   • une rafale très rapide suivie d'Entrée  → un VRAI scan ;
//   • une frappe humaine lente               → PAS un scan.
//
// Aucune interface, aucun matériel : uniquement des horodatages.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/services/lecteur_code_barre_usb.dart';

/// Simule une rafale de frappe : [intervalle] entre chaque caractère.
List<String?> _taper(
  TamponScannerUsb tampon,
  String texte, {
  required Duration intervalle,
  DateTime? debut,
}) {
  final DateTime depart = debut ?? DateTime(2026, 11, 7, 10, 0, 0);
  final List<String?> resultats = <String?>[];
  for (int i = 0; i < texte.length; i++) {
    resultats.add(
      tampon.ajouter(
        texte[i],
        maintenant: depart.add(intervalle * i),
      ),
    );
  }
  return resultats;
}

void main() {
  group('TamponScannerUsb — reconnaissance d\'un scan', () {
    test('un code rapide suivi d\'Entrée est reconnu', () {
      final TamponScannerUsb tampon = TamponScannerUsb();
      final DateTime depart = DateTime(2026, 11, 7, 10, 0, 0);

      // Un lecteur envoie ses caractères toutes les 10 ms.
      _taper(
        tampon,
        '6001234567890',
        intervalle: const Duration(milliseconds: 10),
        debut: depart,
      );

      final String? code = tampon.ajouter(
        '\n',
        maintenant: depart.add(const Duration(milliseconds: 140)),
      );

      expect(code, '6001234567890');
      expect(tampon.vide, isTrue, reason: 'le tampon doit être vidé');
    });

    test('une frappe humaine lente n\'est jamais un scan', () {
      final TamponScannerUsb tampon = TamponScannerUsb();
      final DateTime depart = DateTime(2026, 11, 7, 10, 0, 0);

      // 350 ms entre chaque touche : c'est une personne qui tape.
      _taper(
        tampon,
        '1234',
        intervalle: const Duration(milliseconds: 350),
        debut: depart,
      );

      final String? code = tampon.ajouter(
        '\n',
        maintenant: depart.add(const Duration(milliseconds: 1400)),
      );

      expect(code, isNull);
      expect(tampon.vide, isTrue);
    });

    test('une pause au milieu annule le code', () {
      final TamponScannerUsb tampon = TamponScannerUsb();
      final DateTime depart = DateTime(2026, 11, 7, 10, 0, 0);

      _taper(
        tampon,
        '60012',
        intervalle: const Duration(milliseconds: 10),
        debut: depart,
      );

      // La personne s'arrête puis reprend : plus aucune rafale valable.
      final String? code = tampon.ajouter(
        '\n',
        maintenant: depart.add(const Duration(seconds: 5)),
      );

      expect(code, isNull);
    });

    test('un code trop court est ignoré (protection contre la frappe)', () {
      final TamponScannerUsb tampon = TamponScannerUsb();
      final DateTime depart = DateTime(2026, 11, 7, 10, 0, 0);

      _taper(
        tampon,
        '12',
        intervalle: const Duration(milliseconds: 5),
        debut: depart,
      );

      final String? code = tampon.ajouter(
        '\n',
        maintenant: depart.add(const Duration(milliseconds: 20)),
      );

      expect(code, isNull);
    });

    test('Tab termine aussi un code (réglage fréquent des lecteurs)', () {
      final TamponScannerUsb tampon = TamponScannerUsb();
      final DateTime depart = DateTime(2026, 11, 7, 10, 0, 0);

      _taper(
        tampon,
        'COND:abc-123',
        intervalle: const Duration(milliseconds: 8),
        debut: depart,
      );

      final String? code = tampon.ajouter(
        '\t',
        maintenant: depart.add(const Duration(milliseconds: 120)),
      );

      expect(code, 'COND:abc-123');
    });

    test('les caractères de contrôle sont ignorés', () {
      final TamponScannerUsb tampon = TamponScannerUsb();

      expect(tampon.ajouter('\u0000'), isNull);
      expect(tampon.ajouter(''), isNull);
      expect(tampon.vide, isTrue);
    });

    test('deux scans successifs sont indépendants', () {
      final TamponScannerUsb tampon = TamponScannerUsb();
      final DateTime depart = DateTime(2026, 11, 7, 10, 0, 0);

      _taper(
        tampon,
        '111111',
        intervalle: const Duration(milliseconds: 10),
        debut: depart,
      );
      final String? premier = tampon.ajouter(
        '\n',
        maintenant: depart.add(const Duration(milliseconds: 70)),
      );

      final DateTime second = depart.add(const Duration(seconds: 2));
      _taper(
        tampon,
        '222222',
        intervalle: const Duration(milliseconds: 10),
        debut: second,
      );
      final String? deuxieme = tampon.ajouter(
        '\n',
        maintenant: second.add(const Duration(milliseconds: 70)),
      );

      expect(premier, '111111');
      expect(deuxieme, '222222');
    });

    test('reinitialiser() vide le tampon', () {
      final TamponScannerUsb tampon = TamponScannerUsb();
      _taper(tampon, '60012', intervalle: const Duration(milliseconds: 5));
      expect(tampon.vide, isFalse);

      tampon.reinitialiser();
      expect(tampon.vide, isTrue);
      expect(tampon.contenu, '');
    });
  });

  group('ressembleACodeBarre', () {
    test('un code-barres EAN est reconnu', () {
      expect(ressembleACodeBarre('6001234567890'), isTrue);
    });

    test('une étiquette de l\'application est reconnue', () {
      expect(ressembleACodeBarre('PROD:123'), isTrue);
      expect(ressembleACodeBarre('COND:3f2a0000-0000'), isTrue);
      expect(ressembleACodeBarre('BAL:123:1500'), isTrue);
    });

    test('une recherche saisie à la main n\'est pas un code', () {
      expect(ressembleACodeBarre('eau casino'), isFalse);
      expect(ressembleACodeBarre('savon'), isFalse);
      expect(ressembleACodeBarre('savonnette'), isFalse);
      expect(ressembleACodeBarre('ab'), isFalse);
      expect(ressembleACodeBarre(''), isFalse);
    });

    test('un code alphanumerique reste un code', () {
      expect(ressembleACodeBarre('AB123456'), isTrue);
      expect(ressembleACodeBarre('PARA-5000'), isTrue);
    });
  });
}
