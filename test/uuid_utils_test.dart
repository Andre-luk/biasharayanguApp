// test/uuid_utils_test.dart
//
// Correctif 174 — « invalid input syntax for type uuid ».
// On vérifie ici la règle unique de l'application : un identifiant absent est
// `null`, jamais une chaîne vide, et un code de module n'est pas un UUID.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/utils/uuid_utils.dart';

void main() {
  group('UuidValide.ouNull', () {
    test('une chaîne vide devient null', () {
      expect(UuidValide.ouNull(''), isNull);
      expect(UuidValide.ouNull('   '), isNull);
      expect(UuidValide.ouNull(null), isNull);
    });

    test('les faux identifiants textuels deviennent null', () {
      for (final String valeur in <String>[
        'null',
        'NULL',
        'undefined',
        'None',
        '0',
        '-1',
      ]) {
        expect(UuidValide.ouNull(valeur), isNull, reason: valeur);
      }
    });

    test('un code de module ou un nom de type n\'est PAS un UUID', () {
      expect(UuidValide.ouNull('boutique'), isNull);
      expect(UuidValide.ouNull('pharmacie'), isNull);
      expect(UuidValide.ouNull('press_depots'), isNull);
      expect(UuidValide.ouNull('123'), isNull);
    });

    test('un UUID valide est accepté et normalisé en minuscules', () {
      const String uuid = '9F1C2B7A-4E3D-4A55-9C11-0A1B2C3D4E5F';
      expect(
        UuidValide.ouNull(uuid),
        '9f1c2b7a-4e3d-4a55-9c11-0a1b2c3d4e5f',
      );
      expect(
        UuidValide.ouNull('  9f1c2b7a-4e3d-4a55-9c11-0a1b2c3d4e5f  '),
        '9f1c2b7a-4e3d-4a55-9c11-0a1b2c3d4e5f',
      );
    });

    test('un UUID tronqué ou mal formé est refusé', () {
      expect(UuidValide.ouNull('9f1c2b7a-4e3d-4a55-9c11'), isNull);
      expect(UuidValide.ouNull('zzzzzzzz-4e3d-4a55-9c11-0a1b2c3d4e5f'), isNull);
    });
  });

  group('UuidValide.estValide / requis / texteOuNull', () {
    test('estValide', () {
      expect(UuidValide.estValide('9f1c2b7a-4e3d-4a55-9c11-0a1b2c3d4e5f'),
          isTrue);
      expect(UuidValide.estValide('boutique'), isFalse);
      expect(UuidValide.estValide(null), isFalse);
    });

    test('requis lève une erreur explicite sur une valeur absente', () {
      expect(
        () => UuidValide.requis('', champ: 'entreprise'),
        throwsA(isA<FormatException>()),
      );
      expect(
        UuidValide.requis('9f1c2b7a-4e3d-4a55-9c11-0a1b2c3d4e5f'),
        '9f1c2b7a-4e3d-4a55-9c11-0a1b2c3d4e5f',
      );
    });

    test('texteOuNull garde un code de module (ce n\'est pas un identifiant)',
        () {
      expect(UuidValide.texteOuNull('pharmacie'), 'pharmacie');
      expect(UuidValide.texteOuNull(''), isNull);
      expect(UuidValide.texteOuNull('null'), isNull);
    });
  });

  group('messageErreurBaseDeDonnees', () {
    test('22P02 devient un message français actionnable', () {
      final String message = messageErreurBaseDeDonnees(
        'PostgrestException(message: invalid input syntax for type uuid: "", '
        'code: 22P02)',
      );
      expect(message.toLowerCase(), contains('identifiant'));
      expect(message.toLowerCase(), isNot(contains('invalid input syntax')));
      expect(message.toLowerCase(), isNot(contains('22p02')));
    });

    test('les autres codes ont aussi un message dédié', () {
      expect(messageErreurBaseDeDonnees('code: 23505'), contains('existe déjà'));
      expect(
        messageErreurBaseDeDonnees('code: 42501'),
        contains('droits'),
      );
      expect(
        messageErreurBaseDeDonnees('PGRST202 could not find the function'),
        contains('migration'),
      );
    });

    test('une erreur inconnue retombe sur le message de repli', () {
      expect(
        messageErreurBaseDeDonnees(Exception('boum'), repli: 'Repli'),
        'Repli',
      );
    });
  });
}
