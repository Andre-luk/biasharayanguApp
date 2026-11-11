// test/pressing_caisse_test.dart
//
// MODULE 35 — LA CAISSE DU PRESSING.
//
// Ce qui est testé ici, c'est la lecture honnête de l'argent :
//   • un encaissement annulé ne se fond pas dans le total ;
//   • les modes de paiement sont lus même quand PostgREST renvoie des entiers ;
//   • une journée vide ne lève rien et n'invente pas de chiffre.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/pressing_caisse.dart';

void main() {
  group('PaiementJourPressing', () {
    test('lit une ligne du serveur', () {
      final PaiementJourPressing p =
          PaiementJourPressing.fromMap(<String, dynamic>{
        'id': 'p1',
        'numero': 'PR-2026-000123',
        'client': 'Mme Kabila',
        'montant': 3500,
        'mode': 'mobile_money',
        'agent': 'Paul Ilunga',
        'annule': false,
        'encaisse_le': '2026-11-10T09:15:00Z',
      });

      expect(p.numero, 'PR-2026-000123');
      expect(p.montant, 3500);
      expect(p.libelleMode, 'Mobile Money');
      expect(p.annule, isFalse);
      expect(p.encaisseLe?.toUtc().hour, 9);
    });

    test('un encaissement annulé porte son motif', () {
      final PaiementJourPressing p =
          PaiementJourPressing.fromMap(<String, dynamic>{
        'montant': 1000,
        'annule': true,
        'motif_annulation': 'saisie en double',
      });
      expect(p.annule, isTrue);
      expect(p.motifAnnulation, 'saisie en double');
    });
  });

  group('CaisseJourPressing', () {
    test('lit les totaux, le détail par mode et la liste', () {
      final CaisseJourPressing c =
          CaisseJourPressing.fromRpc(<String, dynamic>{
        'date': '2026-11-10',
        'encaisse': 8500,
        'nb_paiements': 3,
        'annule': 1000,
        'nb_annules': 1,
        'depots': 4,
        'montant_facture': 12000,
        'remises': 2,
        'reste_du': 3500,
        'par_mode': <String, dynamic>{
          'especes': <String, dynamic>{'montant': 5000, 'nb': 2},
          'mobile_money': <String, dynamic>{'montant': 3500, 'nb': 1},
        },
        'paiements': <dynamic>[
          <String, dynamic>{'montant': 5000, 'mode': 'especes'},
        ],
      });

      expect(c.encaisse, 8500);
      expect(c.nbPaiements, 3);
      expect(c.annule, 1000);
      expect(c.nbAnnules, 1);
      expect(c.depots, 4);
      expect(c.remises, 2);
      expect(c.resteDu, 3500);
      expect(c.parMode['especes']?.montant, 5000);
      expect(c.parMode['mobile_money']?.nb, 1);
      expect(c.paiements, hasLength(1));
      expect(c.estVide, isFalse);
      // Le mode le plus encaissé vient en premier.
      expect(c.modesTries.first.mode, 'especes');
    });

    test('une journée vide ne lève pas et n\'invente rien', () {
      final CaisseJourPressing c =
          CaisseJourPressing.fromRpc(<String, dynamic>{});
      expect(c.encaisse, 0);
      expect(c.nbPaiements, 0);
      expect(c.parMode, isEmpty);
      expect(c.paiements, isEmpty);
      expect(c.estVide, isTrue);
      expect(c.modesTries, isEmpty);
    });
  });

  group('Libellés des modes de paiement', () {
    test('les codes connus sont traduits', () {
      expect(libelleModePaiement('especes'), 'Espèces');
      expect(libelleModePaiement('ESPECES'), 'Espèces');
      expect(libelleModePaiement('mobile_money'), 'Mobile Money');
      expect(libelleModePaiement('carte'), 'Carte');
      expect(libelleModePaiement('virement'), 'Virement');
    });

    test('un code inconnu reste lisible, jamais vide', () {
      expect(libelleModePaiement('cheque'), 'cheque');
      expect(libelleModePaiement(null), 'Autre');
      expect(libelleModePaiement('  '), 'Autre');
    });
  });
}
