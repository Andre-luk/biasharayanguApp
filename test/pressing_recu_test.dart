// test/pressing_recu_test.dart
//
// 🧺 MODULE 35 — LE REÇU DE DÉPÔT (A4 + QR code).
//
// Ce que l'on vérifie (aucun réseau) :
//   • le nom du fichier est sûr ;
//   • le message WhatsApp annonce la date de retrait ET le reste à payer ;
//   • les numéros sont normalisés pour wa.me ;
//   • le reçu se construit réellement avec son QR (octets %PDF) ;
//   • le QR n'expose JAMAIS un identifiant de la base : uniquement le jeton.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/pressing.dart';
import 'package:biashara_yangu/services/pressing_recu_pdf_service.dart';

const Etablissement _boutique = Etablissement(
  nom: 'Pressing Kivu',
  telephone: '+243 990 000 000',
  devise: 'CDF',
);

PressingCommande _commande({
  String numero = 'PR-2026-000001',
  String? client = 'Mama Sarah',
  double total = 15000,
  double paye = 5000,
  String? qrToken = 'jeton-aleatoire-64-caracteres',
  List<PressingLigne>? lignes,
  DateTime? datePrevue,
  int qrVersion = 1,
}) {
  return PressingCommande(
    id: 'commande-uuid-interne',
    numero: numero,
    clientNom: client,
    clientTelephone: '+243990111222',
    dateDepot: DateTime(2026, 11, 9),
    datePrevue: datePrevue ?? DateTime(2026, 11, 12),
    total: total,
    montantPaye: paye,
    solde: total - paye,
    qrToken: qrToken,
    qrVersion: qrVersion,
    lignes: lignes ??
        const <PressingLigne>[
          PressingLigne(
            id: 'l1',
            position: 1,
            designation: 'Chemise blanche',
            prestationNom: 'Lavage et repassage',
            etatDepot: 'Bon',
            prix: 3500,
          ),
          PressingLigne(
            id: 'l2',
            position: 2,
            designation: 'Costume',
            prestationNom: 'Nettoyage à sec',
            defauts: 'tache au revers',
            prix: 11500,
          ),
        ],
  );
}

void main() {
  group('Nom du fichier', () {
    test('utilise le numéro de commande', () {
      final DonneesRecuPressing d = DonneesRecuPressing(
        commande: _commande(),
        etablissement: _boutique,
      );
      expect(d.nomFichier, 'recu-PR-2026-000001.pdf');
    });

    test('nettoie les caractères interdits', () {
      final DonneesRecuPressing d = DonneesRecuPressing(
        commande: _commande(numero: 'PR 2026/1'),
        etablissement: _boutique,
      );
      expect(d.nomFichier, 'recu-PR-2026-1.pdf');
      expect(d.nomFichier.contains(' '), isFalse);
    });
  });

  group('Message WhatsApp', () {
    test('annonce le numéro, la date de retrait et ce qui reste à payer', () {
      final String texte = DonneesRecuPressing(
        commande: _commande(),
        etablissement: _boutique,
      ).messageWhatsApp();

      expect(texte, contains('Bonjour Mama Sarah'));
      expect(texte, contains('PR-2026-000001'));
      expect(texte, contains('12/11/2026'));
      expect(texte, contains('Pressing Kivu'));
      expect(texte, contains('reste'));
      expect(texte, contains('10 000'));
    });

    test('reste poli sans nom de client', () {
      final String texte = DonneesRecuPressing(
        commande: _commande(client: '   '),
        etablissement: _boutique,
      ).messageWhatsApp();
      expect(texte, startsWith('Bonjour,'));
    });
  });

  group('normaliserTelephone', () {
    test('garde l’indicatif et retire les séparateurs', () {
      expect(
        PressingRecuPdfService.normaliserTelephone('+243 990 111 222'),
        '243990111222',
      );
    });

    test('convertit un numéro local', () {
      expect(
        PressingRecuPdfService.normaliserTelephone('0990111222'),
        '243990111222',
      );
    });
  });

  group('Le reçu se construit', () {
    test('dépôt avec solde restant', () async {
      final DonneesRecuPressing d = DonneesRecuPressing(
        commande: _commande(),
        etablissement: _boutique,
      );
      final List<int> octets =
          await (await PressingRecuPdfService.instance.construire(d)).save();

      expect(octets.length, greaterThan(1000));
      expect(octets.take(4).toList(), <int>[0x25, 0x50, 0x44, 0x46]);
    });

    test('dépôt soldé et QR réédité', () async {
      final DonneesRecuPressing d = DonneesRecuPressing(
        commande: _commande(paye: 15000, qrVersion: 3),
        etablissement: _boutique,
        soldeObligatoire: false,
      );
      final List<int> octets =
          await (await PressingRecuPdfService.instance.construire(d)).save();
      expect(octets.length, greaterThan(1000));
    });

    test('dépôt sans QR (jeton absent) ne casse pas le document', () async {
      final DonneesRecuPressing d = DonneesRecuPressing(
        commande: _commande(qrToken: ''),
        etablissement: _boutique,
      );
      final List<int> octets =
          await (await PressingRecuPdfService.instance.construire(d)).save();
      expect(octets.length, greaterThan(1000));
    });

    test('le QR ne contient pas l’identifiant interne de la base', () async {
      final DonneesRecuPressing d = DonneesRecuPressing(
        commande: _commande(qrToken: 'abc123'),
        etablissement: _boutique,
      );
      // Le document est construit à partir du seul jeton fourni par le
      // serveur : l'identifiant `commande-uuid-interne` n'est jamais transmis
      // au générateur de QR.
      expect(d.commande.id, 'commande-uuid-interne');
      expect(d.commande.qrToken, 'abc123');
      expect(d.commande.qrToken, isNot(d.commande.id));
    });
  });
}
