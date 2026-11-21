// test/rapport_vendeurs_test.dart
//
// 🧑‍🤝‍🧑 CORRECTIF 179 — RAPPORT PAR COLLABORATEUR.
//
// Ces tests rejouent l'exemple exact donné par l'utilisateur :
//   5 beignets en stock ; le collaborateur A en vend 1 → il reste 4 ;
//   le collaborateur B en vend 1 → il restait 4, et c'est A qui avait vendu.
//
//     flutter test test/rapport_vendeurs_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/rapport_vendeurs.dart';

/// Réponse type de `rpc_rapport_vendeurs` pour l'exemple des beignets.
Map<String, dynamic> reponseBeignets() => <String, dynamic>{
      'entreprise': 'Boulangerie Biashara',
      'entreprise_id': 'be5a5d15-b682-4990-8ad4-11b61002bddd',
      'debut': '2026-11-20',
      'fin': '2026-11-20',
      'totaux': <String, dynamic>{
        'ca': 2000,
        'ventes': 2,
        'quantite': 2,
        'vendeurs': 2,
        'articles': 1,
        'panier_moyen': 1000,
      },
      'vendeurs': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'uuid-a',
          'nom': 'Aline Kabila',
          'ventes': 1,
          'quantite': 1,
          'ca': 1000,
          'panier_moyen': 1000,
          'premier': '2026-11-20 08:15',
          'dernier': '2026-11-20 08:15',
          'produits': <Map<String, dynamic>>[
            <String, dynamic>{'nom': 'Beignet', 'quantite': 1, 'ca': 1000},
          ],
          'journal': <Map<String, dynamic>>[
            <String, dynamic>{
              'date': '2026-11-20 08:15',
              'produit': 'Beignet',
              'quantite': 1,
              'prix': 1000,
              'stock_avant': 5,
              'stock_apres': 4,
              'vendu_avant_par': null,
            },
          ],
        },
        <String, dynamic>{
          'id': 'uuid-b',
          'nom': 'Bob Ilunga',
          'ventes': 1,
          'quantite': 1,
          'ca': 1000,
          'panier_moyen': 1000,
          'premier': '2026-11-20 09:40',
          'dernier': '2026-11-20 09:40',
          'produits': <Map<String, dynamic>>[
            <String, dynamic>{'nom': 'Beignet', 'quantite': 1, 'ca': 1000},
          ],
          'journal': <Map<String, dynamic>>[
            <String, dynamic>{
              'date': '2026-11-20 09:40',
              'produit': 'Beignet',
              'quantite': 1,
              'prix': 1000,
              'stock_avant': 4,
              'stock_apres': 3,
              'vendu_avant_par': 'Aline Kabila',
            },
          ],
        },
      ],
      'produits': <Map<String, dynamic>>[
        <String, dynamic>{
          'produit_id': '12',
          'nom': 'Beignet',
          'stock_actuel': 3,
          'stock_debut': 5,
          'vendu': 2,
          'ca': 2000,
        },
      ],
      'journal': <Map<String, dynamic>>[
        <String, dynamic>{
          'date': '2026-11-20 08:15',
          'vendeur': 'Aline Kabila',
          'produit': 'Beignet',
          'quantite': 1,
          'prix': 1000,
          'stock_avant': 5,
          'stock_apres': 4,
          'vendu_avant_par': null,
        },
        <String, dynamic>{
          'date': '2026-11-20 09:40',
          'vendeur': 'Bob Ilunga',
          'produit': 'Beignet',
          'quantite': 1,
          'prix': 1000,
          'stock_avant': 4,
          'stock_apres': 3,
          'vendu_avant_par': 'Aline Kabila',
        },
      ],
    };

void main() {
  group('RapportVendeurs — lecture de la réponse serveur', () {
    test('les totaux de la période sont lus', () {
      final RapportVendeurs r = RapportVendeurs.fromMap(reponseBeignets());

      expect(r.entreprise, 'Boulangerie Biashara');
      expect(r.totaux.ventes, 2);
      expect(r.totaux.ca, 2000);
      expect(r.totaux.vendeurs, 2);
      expect(r.totaux.articles, 1);
      expect(r.estVide, isFalse);
    });

    test('chaque vendeur porte son propre journal', () {
      final RapportVendeurs r = RapportVendeurs.fromMap(reponseBeignets());

      expect(r.vendeurs.length, 2);

      final VendeurRapport? a = r.vendeurParId('uuid-a');
      final VendeurRapport? b = r.vendeurParId('uuid-b');

      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a!.journal.length, 1);
      expect(b!.journal.length, 1);
      expect(a.nom, 'Aline Kabila');
      expect(b.nom, 'Bob Ilunga');
    });

    test('Aline a vendu le 1er beignet : stock 5 → 4', () {
      final RapportVendeurs r = RapportVendeurs.fromMap(reponseBeignets());
      final JournalVenteVendeur vente = r.vendeurParId('uuid-a')!.journal.first;

      expect(vente.produit, 'Beignet');
      expect(vente.quantite, 1);
      expect(vente.stockAvant, 5);
      expect(vente.stockApres, 4);
      expect(vente.venduAvantPar, isNull);
      expect(vente.stockConnu, isTrue);
    });

    test('Bob voit qu\'il restait 4 et que c\'est Aline qui avait vendu', () {
      final RapportVendeurs r = RapportVendeurs.fromMap(reponseBeignets());
      final JournalVenteVendeur vente = r.vendeurParId('uuid-b')!.journal.first;

      expect(vente.stockAvant, 4, reason: 'Il restait 4 beignets à son passage');
      expect(vente.stockApres, 3);
      expect(vente.venduAvantPar, 'Aline Kabila');
    });

    test('le stock restant après la dernière vente est exposé', () {
      final RapportVendeurs r = RapportVendeurs.fromMap(reponseBeignets());

      expect(r.vendeurParId('uuid-a')!.stockApresDerniereVente, 4);
      expect(r.vendeurParId('uuid-b')!.stockApresDerniereVente, 3);
    });

    test('la chronologie globale est ordonnée et nominative', () {
      final RapportVendeurs r = RapportVendeurs.fromMap(reponseBeignets());

      expect(r.journal.length, 2);
      expect(r.journal.first.vendeur, 'Aline Kabila');
      expect(r.journal.last.vendeur, 'Bob Ilunga');
      expect(r.journal.last.stockAvant, 4);
    });

    test('le tableau des articles donne stock de début et stock actuel', () {
      final RapportVendeurs r = RapportVendeurs.fromMap(reponseBeignets());

      expect(r.produits.length, 1);
      final ProduitStockRapport p = r.produits.first;
      expect(p.nom, 'Beignet');
      expect(p.stockDebut, 5);
      expect(p.stockActuel, 3);
      expect(p.vendu, 2);
      expect(p.ca, 2000);
    });
  });

  group('RapportVendeurs — réponses incomplètes', () {
    test('réponse vide → rapport vide, aucune exception', () {
      final RapportVendeurs r = RapportVendeurs.fromMap(<String, dynamic>{});

      expect(r.estVide, isTrue);
      expect(r.vendeurs, isEmpty);
      expect(r.journal, isEmpty);
      expect(r.totaux.ventes, 0);
    });

    test('article supprimé → stock inconnu (null) et non zéro', () {
      final RapportVendeurs r = RapportVendeurs.fromMap(<String, dynamic>{
        'entreprise': 'Test',
        'vendeurs': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'uuid-a',
            'nom': 'Aline',
            'ventes': 1,
            'quantite': 2,
            'ca': 500,
            'journal': <Map<String, dynamic>>[
              <String, dynamic>{
                'date': '2026-11-20 10:00',
                'produit': 'Article supprimé',
                'quantite': 2,
                'prix': 500,
                'stock_avant': null,
                'stock_apres': null,
              },
            ],
          },
        ],
      });

      final JournalVenteVendeur vente =
          r.vendeurParId('uuid-a')!.journal.first;

      expect(vente.stockConnu, isFalse);
      expect(vente.stockApres, isNull);
      expect(r.vendeurParId('uuid-a')!.stockApresDerniereVente, isNull);
    });

    test('nombres envoyés en texte (jsonb) sont acceptés', () {
      final RapportVendeurs r = RapportVendeurs.fromMap(<String, dynamic>{
        'entreprise': 'Test',
        'totaux': <String, dynamic>{'ca': '1500.5', 'ventes': '3'},
        'vendeurs': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'uuid-a',
            'nom': 'Aline',
            'ventes': '1',
            'ca': '1500.5',
            'journal': <Map<String, dynamic>>[
              <String, dynamic>{
                'date': '2026-11-20 10:00',
                'produit': 'Beignet',
                'quantite': '1',
                'prix': '1500.5',
                'stock_avant': '4',
                'stock_apres': '3',
              },
            ],
          },
        ],
      });

      expect(r.totaux.ca, 1500.5);
      expect(r.totaux.ventes, 3);
      expect(r.vendeurs.first.ca, 1500.5);
      expect(r.vendeurs.first.journal.first.stockAvant, 4);
      expect(r.vendeurs.first.journal.first.stockApres, 3);
    });
  });
}
