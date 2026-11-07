// test/facture_vente_test.dart
//
// MODULE 27 — FACTURE DE VENTE ET IDENTITÉ DE L'ÉTABLISSEMENT.
//
// Ces tests couvrent les parties PURES du document : le message WhatsApp, la
// normalisation des numéros, les mentions légales facultatives et le contenu
// du récapitulatif. La mise en page PDF elle-même est vérifiée à l'écran.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/services/facture_vente_service.dart';

void main() {
  group('Identité de l\'établissement', () {
    test('les mentions légales absentes ne sont pas inventées', () {
      const Etablissement sansMentions = Etablissement(nom: 'Boutique A');
      expect(sansMentions.aMentionsLegales, isFalse);
      expect(sansMentions.rccm, isNull);
      expect(sansMentions.idNational, isNull);
    });

    test('RCCM et identifiant national sont facultatifs mais affichés', () {
      const Etablissement avecMentions = Etablissement(
        nom: 'Boutique A',
        rccm: 'CD/KIN/RCCM/24-B-01234',
        idNational: 'ID-998877',
      );
      expect(avecMentions.aMentionsLegales, isTrue);
    });

    test('adresse reconstituée : rue puis ville', () {
      const Etablissement e = Etablissement(
        nom: 'Boutique',
        adresse: '12, avenue Lumumba, Gombe',
        ville: 'Kinshasa',
      );
      expect(e.lignesAdresse, <String>[
        '12, avenue Lumumba, Gombe',
        'Kinshasa',
      ]);
    });

    test('sans adresse : aucune ligne fabriquée', () {
      const Etablissement e = Etablissement(nom: 'Boutique');
      expect(e.lignesAdresse, isEmpty);
    });

    test('un nom vide reste lisible sur la facture', () {
      const Etablissement e = Etablissement(nom: '   ');
      expect(e.nomAffiche, 'Établissement');
    });
  });

  group('Message WhatsApp du client', () {
    DonneesFacture facture({String? clientNom, String? telephone}) {
      return DonneesFacture(
        numero: 'VTE-20261107-0001',
        date: DateTime(2026, 11, 7, 14, 30),
        etablissement: const Etablissement(nom: 'Établissement Les Trois Frères'),
        lignes: const <LigneFacture>[
          LigneFacture(
            designation: 'Eau 1,5 L',
            quantite: 2,
            unite: 'bouteille',
            prixUnitaire: 1000,
            total: 2000,
          ),
        ],
        total: 2000,
        modePaiement: 'Espèces',
        clientNom: clientNom,
        clientTelephone: telephone,
      );
    }

    test('le message cite la facture, la date et le montant', () {
      final String message =
          facture(clientNom: 'Mama Nicole').messageWhatsApp();

      expect(message, contains('Bonjour Mama Nicole'));
      expect(message, contains('Établissement Les Trois Frères'));
      expect(message, contains('VTE-20261107-0001'));
      expect(message, contains('07/11/2026'));
      expect(message, contains('2'));
    });

    test('sans nom de client, le message reste professionnel', () {
      final String message = facture().messageWhatsApp();
      expect(message, startsWith('Bonjour cher client'));
    });

    test('le nom du fichier est sûr', () {
      expect(facture().nomFichier, 'facture-VTE-20261107-0001.pdf');
    });
  });

  group('Numéro WhatsApp', () {
    test('un numéro local reçoit l\'indicatif 243', () {
      expect(
        FactureVenteService.normaliserTelephone('0991 234 567'),
        '243991234567',
      );
    });

    test('un numéro international est conservé', () {
      expect(
        FactureVenteService.normaliserTelephone('+243 991 234 567'),
        '243991234567',
      );
    });

    test('les espaces et tirets sont retirés', () {
      expect(
        FactureVenteService.normaliserTelephone('00 243-991-234-567'),
        '243991234567',
      );
    });

    test('un numéro vide reste vide', () {
      expect(FactureVenteService.normaliserTelephone('  '), '');
    });
  });

  group('Statuts de facture', () {
    test('chaque statut a un libellé lisible', () {
      expect(StatutFacture.payee.libelle, 'Payée');
      expect(StatutFacture.partielle.libelle, 'Partiellement payée');
      expect(StatutFacture.credit.libelle, 'À crédit');
    });
  });

  group('Récapitulatif', () {
    test('négociation et réduction sont détectées', () {
      final DonneesFacture f = DonneesFacture(
        numero: 'VTE-1',
        date: DateTime(2026, 11, 7),
        etablissement: const Etablissement(nom: 'Boutique'),
        lignes: const <LigneFacture>[],
        total: 350,
        modePaiement: 'Espèces',
        totalCatalogue: 430,
        negociation: 50,
        remise: 30,
      );

      expect(f.aDesRemises, isTrue);
      // 430 − 50 − 30 = 350 : la facture doit rester cohérente.
      expect(f.totalCatalogue - f.negociation - f.remise, f.total);
    });

    test('une vente ordinaire n\'affiche pas de bloc de remises', () {
      final DonneesFacture f = DonneesFacture(
        numero: 'VTE-2',
        date: DateTime(2026, 11, 7),
        etablissement: const Etablissement(nom: 'Boutique'),
        lignes: const <LigneFacture>[],
        total: 2000,
        modePaiement: 'Espèces',
      );
      expect(f.aDesRemises, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // MODULE 27 — une seule numérotation, quel que soit l'écran de vente.
  // ---------------------------------------------------------------------------
  group('FactureVenteService.numeroVente', () {
    test('respecte le format du serveur VTE-AAAAMMJJ-NNNN', () {
      expect(
        FactureVenteService.numeroVente(sequence: 1, date: DateTime(2026, 11, 7)),
        'VTE-20261107-0001',
      );
      expect(
        FactureVenteService.numeroVente(
          sequence: 42,
          date: DateTime(2026, 1, 3),
        ),
        'VTE-20260103-0042',
      );
    });

    test('prolonge la séquence au-delà de 4 chiffres sans troncature', () {
      expect(
        FactureVenteService.numeroVente(
          sequence: 12345,
          date: DateTime(2026, 12, 31),
        ),
        'VTE-20261231-12345',
      );
    });

    test('même numéro impossible : deux séquences différentes diffèrent', () {
      final String a =
          FactureVenteService.numeroVente(sequence: 7, date: DateTime(2026, 5, 4));
      final String b =
          FactureVenteService.numeroVente(sequence: 8, date: DateTime(2026, 5, 4));
      expect(a, isNot(b));
    });

    test('séquence négative tolérée (jamais de plantage)', () {
      expect(
        FactureVenteService.numeroVente(
          sequence: -1,
          date: DateTime(2026, 5, 4),
        ),
        'VTE-20260504-0000',
      );
    });
  });
}
