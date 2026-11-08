// test/note_credit_test.dart
//
// 🧾 MODULE 32 — AVOIRS / NOTES DE CRÉDIT.
//
// Un avoir ne supprime jamais la vente d'origine. Ces tests vérifient la
// lecture des documents renvoyés par le serveur et les règles d'affichage
// (type, statut, montant, auteur).

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/note_credit.dart';

void main() {
  group('TypeAvoir', () {
    test('les deux types sont reconnus', () {
      expect(TypeAvoir.fromCode('AVOIR'), TypeAvoir.avoir);
      expect(TypeAvoir.fromCode('REMBOURSEMENT'), TypeAvoir.remboursement);
      expect(TypeAvoir.fromCode('remboursement'), TypeAvoir.remboursement);
    });

    test('une valeur inconnue ou vide retombe sur AVOIR', () {
      expect(TypeAvoir.fromCode(null), TypeAvoir.avoir);
      expect(TypeAvoir.fromCode(''), TypeAvoir.avoir);
      expect(TypeAvoir.fromCode('XYZ'), TypeAvoir.avoir);
    });
  });

  group('StatutAvoir', () {
    test('EMIS par défaut, ANNULE si annulé', () {
      expect(StatutAvoir.fromCode('EMIS'), StatutAvoir.emis);
      expect(StatutAvoir.fromCode('ANNULE'), StatutAvoir.annule);
      expect(StatutAvoir.fromCode(null), StatutAvoir.emis);
    });
  });

  group('NoteCredit', () {
    test('lit un avoir complet', () {
      final NoteCredit n = NoteCredit.fromMap(<String, dynamic>{
        'id': 'n-1',
        'numero': 'AV-20261108-0001',
        'vente_id': 'v-9',
        'facture_numero': 'VTE-20261107-0001',
        'client_nom': 'Mama Jeanne',
        'client_telephone': '243990000000',
        'montant': 5000,
        'devise': 'CDF',
        'type': 'REMBOURSEMENT',
        'mode_remboursement': 'especes',
        'motif': 'Retour de 2 savons',
        'statut': 'EMIS',
        'date': '2026-11-08T09:30:00Z',
        'auteur': 'Jean Kabila',
      });

      expect(n.numero, 'AV-20261108-0001');
      expect(n.factureNumero, 'VTE-20261107-0001');
      expect(n.clientNom, 'Mama Jeanne');
      expect(n.montant, 5000);
      expect(n.estRemboursement, isTrue);
      expect(n.estAnnule, isFalse);
      expect(n.libelle, 'Avoir AV-20261108-0001');
      expect(n.auteur, 'Jean Kabila');
      expect(n.date, isNotNull);
    });

    test('un avoir annulé garde son motif d\'annulation', () {
      final NoteCredit n = NoteCredit.fromMap(<String, dynamic>{
        'id': 'n-2',
        'numero': 'AV-20261108-0002',
        'montant': 3000,
        'type': 'AVOIR',
        'statut': 'ANNULE',
        'annule_le': '2026-11-08T12:00:00Z',
        'motif_annulation': 'Erreur de saisie',
      });

      expect(n.estAnnule, isTrue);
      expect(n.estRemboursement, isFalse);
      expect(n.annuleLe, isNotNull);
      expect(n.motifAnnulation, 'Erreur de saisie');
    });

    test('une réponse incomplète ne plante pas', () {
      final NoteCredit n = NoteCredit.fromMap(<String, dynamic>{'id': 'x'});

      expect(n.numero, '');
      expect(n.montant, 0);
      expect(n.devise, 'CDF');
      expect(n.type, TypeAvoir.avoir);
      expect(n.statut, StatutAvoir.emis);
      expect(n.clientNom, isNull);
    });

    test('le montant tolère un entier ou une chaîne', () {
      expect(
        NoteCredit.fromMap(<String, dynamic>{'id': 'a', 'montant': 1500})
            .montant,
        1500,
      );
      expect(
        NoteCredit.fromMap(<String, dynamic>{'id': 'b', 'montant': '2500.50'})
            .montant,
        2500.5,
      );
    });
  });
}
