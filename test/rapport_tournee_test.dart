// test/rapport_tournee_test.dart
//
// 🖨️ RAPPORT DE TOURNÉE — « l'agent a emmené 200, vendu 150, rendu 30,
// il manque 20 ». Ces tests vérifient que l'application lit correctement ce
// que le serveur a calculé, et qu'elle n'invente jamais un manquant.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/distribution_terrain.dart';

void main() {
  group('LigneRapportTournee', () {
    test('lit une ligne complète', () {
      final LigneRapportTournee l =
          LigneRapportTournee.depuisJson(<String, dynamic>{
        'produit_id': 12,
        'nom': 'Eau 1,5 L',
        'unite': 'bouteille',
        'confie': 200,
        'vendu': 150,
        'rendu': 30,
        'offert': 0,
        'casse': 0,
        'manquant': 20,
        'prix_vente': 500,
        'valeur_vendue': 75000,
        'valeur_manquant': 10000,
      });

      expect(l.nom, 'Eau 1,5 L');
      expect(l.confie, 200);
      expect(l.vendu, 150);
      expect(l.rendu, 30);
      expect(l.manquant, 20);
      expect(l.valeurManquant, 10000);
      expect(l.aUnManquant, isTrue);
    });

    test('une ligne équilibrée n\'a pas de manquant', () {
      final LigneRapportTournee l =
          LigneRapportTournee.depuisJson(<String, dynamic>{
        'produit_id': 3,
        'confie': 10,
        'vendu': 8,
        'rendu': 1,
        'offert': 1,
        'casse': 0,
        'manquant': 0,
      });

      expect(l.aUnManquant, isFalse);
    });

    test('un manquant de 0,0001 n\'est pas un manquant', () {
      const LigneRapportTournee l =
          LigneRapportTournee(produitId: 1, manquant: 0.00005);

      expect(l.aUnManquant, isFalse);
    });
  });

  group('RapportTournee', () {
    final Map<String, dynamic> complet = <String, dynamic>{
      'ok': true,
      'entete': <String, dynamic>{
        'reference': 'TOU-20261031-0002',
        'date_tournee': '2026-10-31',
        'zone': 'Kinshasa-Est',
        'statut': 'cloturee',
        'agent_nom': 'Jean Kabeya',
        'entreprise': 'Perle Distribution',
        'devise': 'CDF',
        'objectif_montant': 100000,
        'commission_taux': 5,
        'commission_montant': 3750,
      },
      'lignes': <dynamic>[
        <String, dynamic>{
          'produit_id': 12,
          'nom': 'Eau 1,5 L',
          'confie': 200,
          'vendu': 150,
          'rendu': 30,
          'offert': 0,
          'casse': 0,
          'manquant': 20,
          'valeur_manquant': 10000,
        },
      ],
      'recus': <dynamic>[
        <String, dynamic>{
          'numero': 'VTE-20261031-0007',
          'heure': '2026-10-31T10:22:00Z',
          'total': 75000,
          'nb_lignes': 3,
        },
      ],
      'productions': <dynamic>[
        <String, dynamic>{
          'produit_id': 12,
          'nom': 'Eau 1,5 L',
          'produite': 500,
          'pertes': 5,
          'nb': 1,
        },
      ],
      'totaux': <String, dynamic>{
        'confie': 200,
        'vendu': 150,
        'rendu': 30,
        'offert': 0,
        'casse': 0,
        'manquant': 20,
        'valeur_manquant': 10000,
        'chiffre_affaires': 75000,
        'nb_recus': 1,
      },
      'stock_mouvemente': false,
      'note_stock': 'La dotation ne retire pas le stock.',
    };

    test('décode le rapport complet', () {
      final RapportTournee? r = RapportTournee.depuisJson(complet);

      expect(r, isNotNull);
      expect(r!.reference, 'TOU-20261031-0002');
      expect(r.agentNom, 'Jean Kabeya');
      expect(r.entreprise, 'Perle Distribution');
      expect(r.devise, 'CDF');
      expect(r.zone, 'Kinshasa-Est');
      expect(r.objectifMontant, 100000);
      expect(r.commissionTaux, 5);
      expect(r.commissionMontant, 3750);

      expect(r.lignes.single.manquant, 20);
      expect(r.recus.single.numero, 'VTE-20261031-0007');
      expect(r.recus.single.total, 75000);
      expect(r.productions.single.produite, 500);

      expect(r.confie, 200);
      expect(r.vendu, 150);
      expect(r.rendu, 30);
      expect(r.manquant, 20);
      expect(r.valeurManquant, 10000);
      expect(r.chiffreAffaires, 75000);
      expect(r.nbRecus, 1);
      expect(r.aUnManquant, isTrue);
    });

    test('« justifié » = vendu + rendu + offert + cassé', () {
      final RapportTournee r = RapportTournee.depuisJson(complet)!;

      // 150 vendues + 30 rendues : 20 restent à expliquer.
      expect(r.justifie, 180);
      expect(r.confie - r.justifie, r.manquant);
    });

    test('une tournée équilibrée n\'affiche aucun manquant', () {
      final RapportTournee r = RapportTournee.depuisJson(<String, dynamic>{
        'ok': true,
        'entete': <String, dynamic>{'reference': 'TOU-1', 'statut': 'cloturee'},
        'totaux': <String, dynamic>{
          'confie': 100,
          'vendu': 100,
          'manquant': 0,
        },
      })!;

      expect(r.aUnManquant, isFalse);
      expect(r.manquant, 0);
      expect(r.lignes, isEmpty);
      expect(r.recus, isEmpty);
    });

    test('une réponse sans en-tête ne fabrique pas de rapport', () {
      expect(RapportTournee.depuisJson(<String, dynamic>{'ok': false}), isNull);
      expect(RapportTournee.depuisJson(<String, dynamic>{'ok': true}), isNull);
    });

    test('la note sur le stock est conservée telle quelle', () {
      final RapportTournee r = RapportTournee.depuisJson(complet)!;

      expect(r.noteStock, contains('ne retire pas le stock'));
    });
  });
}
