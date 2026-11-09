// test/avoir_pdf_test.dart
//
// 🧾 MODULE 32/34 — LE DOCUMENT « AVOIR » ET LE RETOUR DE MARCHANDISE.
//
// Ce que l'on vérifie (aucun réseau) :
//   • le nom du fichier PDF est sûr (sans espace ni accent) ;
//   • le message WhatsApp dit la bonne chose (avoir ou remboursement) ;
//   • les numéros de téléphone sont normalisés pour wa.me ;
//   • le document A4 se construit réellement (donc il s'imprime) ;
//   • un avoir annulé ou déjà rentré en stock ne peut plus rentrer en stock.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/note_credit.dart';
import 'package:biashara_yangu/services/avoir_pdf_service.dart';

const Etablissement _boutique = Etablissement(
  nom: 'Boutique Kivu',
  telephone: '+243 990 000 000',
  devise: 'CDF',
);

NoteCredit _avoir({
  String id = 'n-1',
  String numero = 'AV-20261108-0001',
  double montant = 12000,
  TypeAvoir type = TypeAvoir.avoir,
  StatutAvoir statut = StatutAvoir.emis,
  DateTime? retourStockLe,
  String? motif = 'Article défectueux',
  String? client = 'Mama Sarah',
}) {
  return NoteCredit(
    id: id,
    numero: numero,
    montant: montant,
    type: type,
    statut: statut,
    motif: motif,
    clientNom: client,
    clientTelephone: '+243990111222',
    date: DateTime(2026, 11, 8),
    retourStockLe: retourStockLe,
  );
}

void main() {
  group('DonneesAvoir — nom du fichier', () {
    test('utilise le numéro de l\'avoir', () {
      final DonneesAvoir d = DonneesAvoir(
        avoir: _avoir(),
        etablissement: _boutique,
      );
      expect(d.nomFichier, 'avoir-AV-20261108-0001.pdf');
    });

    test('nettoie les caractères interdits', () {
      final DonneesAvoir d = DonneesAvoir(
        avoir: _avoir(numero: 'AV 08/11 #1'),
        etablissement: _boutique,
      );
      expect(d.nomFichier, 'avoir-AV-08-11--1.pdf');
      expect(d.nomFichier.contains(' '), isFalse);
    });

    test('retombe sur « avoir » quand le numéro est vide', () {
      final DonneesAvoir d = DonneesAvoir(
        avoir: _avoir(numero: '   '),
        etablissement: _boutique,
      );
      expect(d.nomFichier, 'avoir-avoir.pdf');
    });
  });

  group('DonneesAvoir — message WhatsApp', () {
    test('annonce un avoir avec son numéro et sa date', () {
      final String texte = DonneesAvoir(
        avoir: _avoir(),
        etablissement: _boutique,
      ).messageWhatsApp();

      expect(texte, contains('Bonjour Mama Sarah'));
      expect(texte, contains('un avoir de'));
      expect(texte, contains('AV-20261108-0001'));
      expect(texte, contains('08/11/2026'));
      expect(texte, contains('Boutique Kivu'));
      expect(texte, contains('Motif : Article défectueux'));
    });

    test('parle de remboursement quand l\'argent est rendu', () {
      final String texte = DonneesAvoir(
        avoir: _avoir(type: TypeAvoir.remboursement),
        etablissement: _boutique,
      ).messageWhatsApp();

      expect(texte, contains('nous vous avons remboursé'));
      expect(texte, isNot(contains('un avoir de')));
    });

    test('reste poli quand le client n\'est pas nommé', () {
      final String texte = DonneesAvoir(
        avoir: _avoir(client: '   '),
        etablissement: _boutique,
      ).messageWhatsApp();

      expect(texte, startsWith('Bonjour cher client'));
    });

    test('n\'invente pas de motif', () {
      final String texte = DonneesAvoir(
        avoir: _avoir(motif: null),
        etablissement: _boutique,
      ).messageWhatsApp();

      expect(texte, isNot(contains('Motif')));
    });
  });

  group('AvoirPdfService.normaliserTelephone', () {
    test('retire les séparateurs et garde l\'indicatif', () {
      expect(
        AvoirPdfService.normaliserTelephone('+243 990 111 222'),
        '243990111222',
      );
    });

    test('convertit un numéro local en numéro international', () {
      expect(AvoirPdfService.normaliserTelephone('0990111222'), '243990111222');
      expect(AvoirPdfService.normaliserTelephone('990111222'), '243990111222');
    });

    test('gère le préfixe 00', () {
      expect(AvoirPdfService.normaliserTelephone('00243990111222'),
          '243990111222');
    });

    test('laisse un numéro déjà propre intact', () {
      expect(AvoirPdfService.normaliserTelephone('243990111222'),
          '243990111222');
    });
  });

  group('Le document se construit', () {
    test('avoir simple', () async {
      final DonneesAvoir d = DonneesAvoir(
        avoir: _avoir(),
        etablissement: _boutique,
      );
      final List<int> octets = await (await AvoirPdfService.instance
              .construire(d))
          .save();
      expect(octets.length, greaterThan(1000));
      // Signature d'un PDF : %PDF
      expect(octets.take(4).toList(), <int>[0x25, 0x50, 0x44, 0x46]);
    });

    test('avoir avec marchandise rendue', () async {
      final DonneesAvoir d = DonneesAvoir(
        avoir: _avoir(),
        etablissement: _boutique,
        lignesRetour: const <LigneRetourAvoir>[
          LigneRetourAvoir(designation: 'Riz 5 kg', quantite: 2, unite: 'sac'),
          LigneRetourAvoir(designation: 'Huile 1 L', quantite: 1.5),
        ],
      );
      final List<int> octets = await (await AvoirPdfService.instance
              .construire(d))
          .save();
      expect(octets.length, greaterThan(1000));
    });

    test('avoir annulé', () async {
      final DonneesAvoir d = DonneesAvoir(
        avoir: _avoir(statut: StatutAvoir.annule),
        etablissement: _boutique,
      );
      final List<int> octets = await (await AvoirPdfService.instance
              .construire(d))
          .save();
      expect(octets.length, greaterThan(1000));
    });
  });

  group('Retour de marchandise — règles du modèle', () {
    test('un avoir émis et jamais rendu peut rentrer en stock', () {
      expect(_avoir().peutRentrerEnStock, isTrue);
    });

    test('un avoir annulé ne rentre pas en stock', () {
      expect(
        _avoir(statut: StatutAvoir.annule).peutRentrerEnStock,
        isFalse,
      );
    });

    test('un avoir déjà rendu ne rentre pas deux fois en stock', () {
      expect(
        _avoir(retourStockLe: DateTime(2026, 11, 9)).peutRentrerEnStock,
        isFalse,
      );
    });

    test('la date de retour est lue depuis le serveur', () {
      final NoteCredit n = NoteCredit.fromMap(<String, dynamic>{
        'id': 'n-2',
        'numero': 'AV-20261108-0002',
        'montant': '5000',
        'statut': 'EMIS',
        'retour_stock_le': '2026-11-09T10:00:00+00:00',
      });
      expect(n.retourStockLe, isNotNull);
      expect(n.retourStockLe!.year, 2026);
      expect(n.peutRentrerEnStock, isFalse);
    });

    test('sans date de retour, le retour reste possible', () {
      final NoteCredit n = NoteCredit.fromMap(<String, dynamic>{
        'id': 'n-3',
        'montant': '5000',
        'statut': 'EMIS',
      });
      expect(n.retourStockLe, isNull);
      expect(n.peutRentrerEnStock, isTrue);
    });
  });
}
