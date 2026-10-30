// test/recipients_test.dart
//
// REFONTE ABONNEMENTS & DISTRIBUTION — récipients, échanges et bonus.
// Tests PURS : les trois cas de vente, la dette de récipients et les règles
// de bonus (aucun réseau, aucune base).

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/recipients.dart';

void main() {
  group('Cas 1 — vente d’eau avec un NOUVEAU récipient (12 000 FC)', () {
    test('facture l’eau ET le récipient', () {
      final MontantsVenteRecipient m = CalculRecipient.montants(
        mode: ModeVenteRecipient.nouveau,
        prixEau: 8000,
        prixRecipient: 4000,
      );
      expect(m.montantEau, 8000);
      expect(m.montantRecipient, 4000);
      expect(m.total, 12000);
      expect(m.mouvements, 1, reason: 'un récipient vendu');
    });
  });

  group('Cas 2 — vente avec ÉCHANGE (4 000 FC)', () {
    test('ne facture que l’eau', () {
      final MontantsVenteRecipient m = CalculRecipient.montants(
        mode: ModeVenteRecipient.echange,
        prixEau: 4000,
        prixRecipient: 4000,
      );
      expect(m.montantEau, 4000);
      expect(m.montantRecipient, 0, reason: 'le récipient est échangé, pas vendu');
      expect(m.total, 4000);
      expect(m.mouvements, 2, reason: 'un vide repris + un plein livré');
    });
  });

  group('Cas 3 — le client possède déjà son récipient', () {
    test('ne facture que le remplissage, sans mouvement de récipient', () {
      final MontantsVenteRecipient m = CalculRecipient.montants(
        mode: ModeVenteRecipient.propre,
        prixEau: 4000,
        prixRecipient: 4000,
      );
      expect(m.total, 4000);
      expect(m.mouvements, 0, reason: 'aucun récipient de l’entreprise');
    });
  });

  group('Quantités et garde-fous', () {
    test('multiplie par la quantité', () {
      final MontantsVenteRecipient m = CalculRecipient.montants(
        mode: ModeVenteRecipient.nouveau,
        prixEau: 4000,
        prixRecipient: 4000,
        quantite: 3,
      );
      expect(m.total, 24000);
    });

    test('quantité nulle ou négative → 1', () {
      final MontantsVenteRecipient m = CalculRecipient.montants(
        mode: ModeVenteRecipient.echange,
        prixEau: 4000,
        prixRecipient: 0,
        quantite: 0,
      );
      expect(m.quantite, 1);
    });

    test('un prix négatif ne crée pas de crédit', () {
      final MontantsVenteRecipient m = CalculRecipient.montants(
        mode: ModeVenteRecipient.nouveau,
        prixEau: -1000,
        prixRecipient: -500,
      );
      expect(m.total, 0);
    });
  });

  group('Dette de récipients d’un client', () {
    test('livrés − récupérés − perdus − cassés', () {
      expect(
        CalculRecipient.detenus(livres: 10, recuperes: 6, perdus: 1, casses: 1),
        2,
      );
    });

    test('ne descend jamais sous zéro', () {
      expect(CalculRecipient.detenus(livres: 2, recuperes: 5), 0);
    });
  });

  group('Règles de bonus', () {
    test('5 fardes achetées = 1 offerte', () {
      const RegleBonus r = RegleBonus(
        id: 'r1',
        libelle: '5 fardes = 1 offerte',
        quantiteDeclencheur: 5,
        quantiteOfferte: 1,
      );
      expect(r.bonusPour(4), 0);
      expect(r.bonusPour(5), 1);
      expect(r.bonusPour(11), 2);
      expect(r.bonusPour(0), 0);
    });

    test('10 fardes achetées = 2 offertes', () {
      const RegleBonus r = RegleBonus(
        id: 'r2',
        libelle: '10 fardes = 2 offertes',
        quantiteDeclencheur: 10,
        quantiteOfferte: 2,
      );
      expect(r.bonusPour(9), 0);
      expect(r.bonusPour(10), 2);
      expect(r.bonusPour(25), 4);
    });

    test('une règle inactive n’offre rien', () {
      const RegleBonus r = RegleBonus(
        id: 'r3',
        libelle: 'inactive',
        quantiteDeclencheur: 5,
        quantiteOfferte: 1,
        actif: false,
      );
      expect(r.bonusPour(50), 0);
    });
  });

  group('Tableau de bord des récipients', () {
    test('taux de récupération borné à 1', () {
      const TableauBordRecipients t = TableauBordRecipients(
        livres: 10,
        vendus: 10,
        recuperes: 40,
      );
      expect(t.tauxRecuperation, 1);
    });

    test('aucun mouvement → taux 1 (rien à récupérer)', () {
      expect(TableauBordRecipients.vide.tauxRecuperation, 1);
    });
  });

  group('ModeVenteRecipient.depuis', () {
    test('reconnaît les codes et retombe sur « propre »', () {
      expect(ModeVenteRecipient.depuis('nouveau'), ModeVenteRecipient.nouveau);
      expect(ModeVenteRecipient.depuis('ECHANGE'), ModeVenteRecipient.echange);
      expect(ModeVenteRecipient.depuis('inconnu'), ModeVenteRecipient.propre);
    });
  });
}
