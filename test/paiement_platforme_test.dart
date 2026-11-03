// test/paiement_platforme_test.dart
//
// 💳 AUDIT DES PAIEMENTS — règle « Mobile Money = SerdiPay ».
//
// Tests PURS : la décision de routage ne touche ni réseau ni interface.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/services/paiement_platforme_service.dart';

void main() {
  group('PaiementPlatformeService — reconnaissance des modes', () {
    test('reconnaît Mobile Money sous toutes ses écritures', () {
      for (final String mode in <String>[
        'Mobile Money',
        'mobile money',
        'MOBILE_MONEY',
        'MOBILE-MONEY',
        'MobileMoney',
        'M-Pesa',
        'MPESA',
        'Orange Money',
        'ORANGE_MONEY',
        'Airtel Money',
        'MM',
      ]) {
        expect(
          PaiementPlatformeService.estMobileMoney(mode),
          isTrue,
          reason: 'le mode « $mode » doit passer par SerdiPay',
        );
      }
    });

    test('ne confond pas les espèces avec Mobile Money', () {
      for (final String mode in <String>[
        'Espèces',
        'ESPECES',
        'Espèces ',
        'Cash',
        'Liquide',
        '',
      ]) {
        expect(PaiementPlatformeService.estMobileMoney(mode), isFalse,
            reason: 'le mode « $mode » reste un encaissement classique');
        expect(PaiementPlatformeService.estEspeces(mode), isTrue);
      }
    });

    test('un mode inconnu (carte, virement) n\'est ni espèces ni SerdiPay',
        () {
      expect(PaiementPlatformeService.estMobileMoney('Carte bancaire'), isFalse);
      expect(PaiementPlatformeService.estEspeces('Carte bancaire'), isFalse);
      expect(PaiementPlatformeService.estEspeces('Virement bancaire'), isFalse);
      expect(
        PaiementPlatformeService.messageModeIndisponible('Carte bancaire'),
        contains('pas encore disponible'),
      );
    });

    test('le message Mobile Money renvoie explicitement vers SerdiPay', () {
      expect(
        PaiementPlatformeService.messageModeIndisponible('Mobile Money'),
        contains('SerdiPay'),
      );
    });
  });
}
