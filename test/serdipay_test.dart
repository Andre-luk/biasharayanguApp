// test/serdipay_test.dart
//
// Tests PURS de la passerelle SerdiPay (aucun réseau) :
//   • lecture des statuts / opérateurs / objets ;
//   • construction d'un paiement depuis l'enveloppe de l'Edge Function ;
//   • copyWith et libellés.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/paiement_serdipay.dart';

void main() {
  group('StatutPaiementSerdipay', () {
    test('reconnaît les statuts de la base', () {
      expect(
        StatutPaiementSerdipay.fromCode('en_attente'),
        StatutPaiementSerdipay.enAttente,
      );
      expect(
        StatutPaiementSerdipay.fromCode('paye'),
        StatutPaiementSerdipay.paye,
      );
      expect(
        StatutPaiementSerdipay.fromCode('echoue'),
        StatutPaiementSerdipay.echoue,
      );
      expect(
        StatutPaiementSerdipay.fromCode('annule'),
        StatutPaiementSerdipay.annule,
      );
      expect(
        StatutPaiementSerdipay.fromCode('expire'),
        StatutPaiementSerdipay.expire,
      );
    });

    test('valeur inconnue ou absente → inconnu (jamais d\'exception)', () {
      expect(
        StatutPaiementSerdipay.fromCode(null),
        StatutPaiementSerdipay.inconnu,
      );
      expect(
        StatutPaiementSerdipay.fromCode('PAYE_EN_LIGNE'),
        StatutPaiementSerdipay.inconnu,
      );
    });

    test('libellés français', () {
      expect(StatutPaiementSerdipay.enAttente.libelle, 'En attente');
      expect(StatutPaiementSerdipay.paye.libelle, 'Payé');
      expect(StatutPaiementSerdipay.echoue.libelle, 'Échoué');
    });
  });

  group('OperateurSerdipay', () {
    test('codes attendus par la passerelle', () {
      expect(OperateurSerdipay.orange.code, 'orange');
      expect(OperateurSerdipay.airtel.code, 'airtel');
      expect(OperateurSerdipay.mpesa.code, 'mpesa');
      expect(OperateurSerdipay.afrimoney.code, 'afrimoney');
      expect(OperateurSerdipay.carte.code, 'carte');
    });

    test('fromCode tolère la casse et les espaces', () {
      expect(OperateurSerdipay.fromCode(' ORANGE '), OperateurSerdipay.orange);
      expect(OperateurSerdipay.fromCode('Mpesa'), OperateurSerdipay.mpesa);
      expect(OperateurSerdipay.fromCode('inconnu'), isNull);
    });
  });

  group('PaiementSerdipay.fromMap', () {
    test('lit une ligne de paiements_serdipay', () {
      final PaiementSerdipay paiement = PaiementSerdipay.fromMap(
        <String, dynamic>{
          'id': '11111111-1111-1111-1111-111111111111',
          'reference': 'SER-20261027-AB12CD34',
          'entreprise_id': '22222222-2222-2222-2222-222222222222',
          'objet': 'abonnement',
          'montant': 30000,
          'devise': 'CDF',
          'statut': 'en_attente',
          'operateur': 'orange',
          'telephone': '243970000000',
          'url_paiement': 'https://pay.serdipay.com/x',
          'expire_le': '2026-10-27T12:30:00Z',
        },
      );

      expect(paiement.reference, 'SER-20261027-AB12CD34');
      expect(paiement.montant, 30000);
      expect(paiement.devise, 'CDF');
      expect(paiement.statut, StatutPaiementSerdipay.enAttente);
      expect(paiement.objet, ObjetPaiementSerdipay.abonnement);
      expect(paiement.operateur, OperateurSerdipay.orange);
      expect(paiement.estEnAttente, isTrue);
      expect(paiement.estPaye, isFalse);
      expect(paiement.demandeOuvertureNavigateur, isTrue);
      expect(paiement.montantLibelle, '30000 CDF');
    });

    test('un paiement sans URL (validation USSD) n\'ouvre pas de navigateur', () {
      final PaiementSerdipay paiement = PaiementSerdipay.fromMap(
        <String, dynamic>{
          'reference': 'SER-20261027-ZZ',
          'objet': 'abonnement',
          'montant': 5000,
          'statut': 'en_attente',
        },
      );

      expect(paiement.urlPaiement, isNull);
      expect(paiement.demandeOuvertureNavigateur, isFalse);
    });

    test('objet facture et montant décimal', () {
      final PaiementSerdipay paiement = PaiementSerdipay.fromMap(
        <String, dynamic>{
          'reference': 'SER-20261027-FA',
          'objet': 'facture',
          'objet_id': '33333333-3333-3333-3333-333333333333',
          'montant': 12500.5,
          'devise': 'USD',
          'statut': 'paye',
        },
      );

      expect(paiement.objet, ObjetPaiementSerdipay.facture);
      expect(paiement.objetId, '33333333-3333-3333-3333-333333333333');
      expect(paiement.estPaye, isTrue);
      expect(paiement.montantLibelle, '12500,50 USD');
    });
  });

  group('PaiementSerdipay.depuisEnveloppe', () {
    test('déballe {ok:true, paiement:{…}} et conserve le message', () {
      final PaiementSerdipay paiement = PaiementSerdipay.depuisEnveloppe(
        <String, dynamic>{
          'ok': true,
          'message': 'Validez la demande sur votre téléphone.',
          'paiement': <String, dynamic>{
            'reference': 'SER-20261027-ENV',
            'montant': 10000,
            'devise': 'CDF',
            'statut': 'en_attente',
            'url_paiement': null,
          },
        },
      );

      expect(paiement.reference, 'SER-20261027-ENV');
      expect(paiement.message, 'Validez la demande sur votre téléphone.');
      expect(paiement.demandeOuvertureNavigateur, isFalse);
    });

    test('sans clé paiement, lit directement la map', () {
      final PaiementSerdipay paiement = PaiementSerdipay.depuisEnveloppe(
        <String, dynamic>{
          'reference': 'SER-DIRECT',
          'montant': 1000,
          'statut': 'paye',
        },
      );

      expect(paiement.reference, 'SER-DIRECT');
      expect(paiement.estPaye, isTrue);
    });
  });

  group('copyWith', () {
    test('change le statut sans perdre les autres champs', () {
      final PaiementSerdipay depart = PaiementSerdipay.fromMap(
        <String, dynamic>{
          'reference': 'SER-1',
          'montant': 30000,
          'devise': 'CDF',
          'statut': 'en_attente',
        },
      );

      final PaiementSerdipay paye = depart.copyWith(
        statut: StatutPaiementSerdipay.paye,
        payeLe: DateTime.utc(2026, 10, 27, 10),
      );

      expect(paye.reference, 'SER-1');
      expect(paye.montant, 30000);
      expect(paye.estPaye, isTrue);
      expect(paye.payeLe, isNotNull);
    });
  });
}
