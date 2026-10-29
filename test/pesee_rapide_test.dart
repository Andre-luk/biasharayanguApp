// test/pesee_rapide_test.dart
//
// ⚖️ MODULE 23 — Tests PURS de la pesée rapide : lecture du poids affiché par
// la balance, calcul du total au prix du KILO et formatage. Aucun réseau.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/pesee.dart';

void main() {
  group('PeseeCalculs.analyser', () {
    test('accepte la virgule et le point', () {
      expect(PeseeCalculs.analyser('1,250'), 1.25);
      expect(PeseeCalculs.analyser('1.250'), 1.25);
      expect(PeseeCalculs.analyser(' 0,333 '), 0.333);
    });

    test('refuse zéro, négatif et texte', () {
      expect(PeseeCalculs.analyser('0'), isNull);
      expect(PeseeCalculs.analyser('-1,5'), isNull);
      expect(PeseeCalculs.analyser('abc'), isNull);
      expect(PeseeCalculs.analyser(''), isNull);
    });

    test('arrondit au millième (précision balance)', () {
      expect(PeseeCalculs.analyser('1,23456'), 1.235);
    });
  });

  group('PeseeCalculs.total', () {
    test('poids × prix au kilo', () {
      expect(
        PeseeCalculs.total(poids: 1.25, prixUnitaire: 25000),
        31250,
      );
      expect(
        PeseeCalculs.total(poids: 0.333, prixUnitaire: 25000),
        8325,
      );
    });

    test('montant arrondi au centième', () {
      expect(
        PeseeCalculs.total(poids: 0.333, prixUnitaire: 999.99),
        333,
      );
    });

    test('un poids ou un prix nul donne zéro (jamais une vente à 0)', () {
      expect(PeseeCalculs.total(poids: 0, prixUnitaire: 25000), 0);
      expect(PeseeCalculs.total(poids: 1, prixUnitaire: 0), 0);
    });
  });

  group('PeseeCalculs.texte', () {
    test('affiche sans zéros inutiles, en virgule française', () {
      expect(PeseeCalculs.texte(1), '1');
      expect(PeseeCalculs.texte(1.25), '1,25');
      expect(PeseeCalculs.texte(0.333), '0,333');
      expect(PeseeCalculs.texte(2.500), '2,5');
    });
  });

  group('PeseeCalculs.decoderCodeBalance', () {
    test('lit produit + poids en grammes', () {
      expect(
        PeseeCalculs.decoderCodeBalance('BAL:503:1250'),
        (produitId: 503, poids: 1.25),
      );
      expect(
        PeseeCalculs.decoderCodeBalance('pesee:7:333'),
        (produitId: 7, poids: 0.333),
      );
    });

    test('tolère les espaces autour du code', () {
      expect(
        PeseeCalculs.decoderCodeBalance(' BAL:12:500 '),
        (produitId: 12, poids: 0.5),
      );
    });

    test('refuse un code ordinaire (QR, code-barres fabricant)', () {
      expect(PeseeCalculs.decoderCodeBalance('PROD:503'), isNull);
      expect(PeseeCalculs.decoderCodeBalance('8906125990016'), isNull);
      expect(PeseeCalculs.decoderCodeBalance('BAL:0:100'), isNull);
      expect(PeseeCalculs.decoderCodeBalance('BAL:5:0'), isNull);
      expect(PeseeCalculs.decoderCodeBalance(''), isNull);
    });
  });
}
