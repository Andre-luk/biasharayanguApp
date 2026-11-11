// test/pressing_notification_test.dart
//
// MODULE 35 — PRÉVENIR LE CLIENT.
//
// Le message qui part sur WhatsApp est la SEULE chose que le client lit du
// pressing : il doit dire juste (numéro, date, montant), et ne jamais annoncer
// « prête » quand rien n'est prêt. Ces tests verrouillent les trois cas réels :
// commande prête et soldée, commande partiellement prête, commande en retard.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/pressing.dart';
import 'package:biashara_yangu/services/pressing_notification_service.dart';

const Etablissement _etab = Etablissement(nom: 'Pressing La Grâce');

PressingCommande _commande({
  String? clientNom = 'Mme Kabila',
  String? telephone = '0990000000',
  double solde = 0,
  DateTime? datePrevue,
  List<PressingLigne> lignes = const <PressingLigne>[],
}) {
  return PressingCommande(
    id: 'c1',
    numero: 'PR-2026-000123',
    clientNom: clientNom,
    clientTelephone: telephone,
    datePrevue: datePrevue,
    solde: solde,
    total: 7000,
    montantPaye: 7000 - solde,
    lignes: lignes,
  );
}

PressingLigne _ligne({required bool prete, bool remis = false}) {
  return PressingLigne(
    id: 'l${prete ? 1 : 2}${remis ? 'r' : ''}',
    designation: 'Chemise',
    quantite: 1,
    prix: 1000,
    estPrete: prete,
    remisLe: remis ? DateTime(2026, 11, 9) : null,
  );
}

void main() {
  group('Message « commande prête »', () {
    test('nomme le client, le numéro, l\'établissement et le solde', () {
      final PressingCommande c = _commande(
        solde: 2500,
        datePrevue: DateTime(2026, 11, 12),
      );
      final String msg = PressingNotificationService.instance.message(
        commande: c,
        etablissement: _etab,
      );

      expect(msg, startsWith('Bonjour Mme Kabila, '));
      expect(msg, contains('votre commande PR-2026-000123 est prête'));
      expect(msg, contains('Pressing La Grâce'));
      expect(msg, contains('12/11/2026'));
      expect(msg, contains('Reste à payer'));
      expect(msg, isNot(contains('entièrement réglée')));
    });

    test('dit que tout est réglé quand le solde est nul', () {
      final PressingCommande c = _commande(solde: 0);
      final String msg = PressingNotificationService.instance.message(
        commande: c,
        etablissement: _etab,
      );
      expect(msg, contains('entièrement réglée'));
      expect(msg, isNot(contains('Reste à payer')));
    });

    test('annonce « une partie » quand tout n\'est pas prêt', () {
      final PressingCommande c = _commande(
        lignes: <PressingLigne>[
          _ligne(prete: true),
          _ligne(prete: false),
        ],
      );
      final String msg = PressingNotificationService.instance.message(
        commande: c,
        etablissement: _etab,
        partiel: true,
      );
      expect(msg, contains('une partie de votre commande'));
    });

    test('sans nom de client, le message reste correct', () {
      final PressingCommande c = _commande(clientNom: null);
      final String msg = PressingNotificationService.instance.message(
        commande: c,
        etablissement: _etab,
      );
      expect(msg, startsWith('Bonjour, '));
      expect(msg, contains('PR-2026-000123'));
    });
  });

  group('Message « retard »', () {
    test('reconnaît le retard, rappelle la date et s\'excuse', () {
      final PressingCommande c = _commande(
        solde: 1000,
        datePrevue: DateTime(2026, 11, 5),
      );
      final String msg = PressingNotificationService.instance.message(
        commande: c,
        etablissement: _etab,
        type: TypeMessagePressing.retard,
      );

      expect(msg, contains('dépasse la date de retrait prévue'));
      expect(msg, contains('attendue le 05/11/2026'));
      expect(msg, contains('Solde restant'));
      expect(msg, contains('excuser'));
      expect(msg, isNot(contains('est prête')));
    });

    test('sans date prévue, le message ne fabrique pas de date', () {
      final PressingCommande c = _commande(datePrevue: null);
      final String msg = PressingNotificationService.instance.message(
        commande: c,
        etablissement: _etab,
        type: TypeMessagePressing.retard,
      );
      expect(msg, contains('PR-2026-000123'));
      expect(msg, isNot(contains('attendue le')));
    });
  });
}
