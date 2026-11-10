// test/sortie_stock_test.dart
//
// SORTIES DE STOCK SPÉCIALES (migration 0132).
//
// Ces tests couvrent la partie PURE du module : les motifs (codes envoyés au
// serveur, libellés affichés), la lecture des réponses du serveur, et le
// message d'erreur présenté au commerçant. Aucune connexion réseau.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/sortie_stock.dart';
import 'package:biashara_yangu/services/stock_service.dart';

void main() {
  group('MotifSortieStock', () {
    test('les codes envoyés au serveur sont ceux acceptés par la migration', () {
      const List<String> attendus = <String>[
        'consommation_proprietaire',
        'offert',
        'perte',
        'casse',
        'peremption',
        'retour_fournisseur',
        'usage_interne',
        'autre',
      ];
      expect(
        MotifSortieStock.values.map((MotifSortieStock m) => m.code).toList(),
        attendus,
      );
    });

    test('chaque motif a un libellé non vide et une explication', () {
      for (final MotifSortieStock motif in MotifSortieStock.values) {
        expect(motif.libelle.trim(), isNotEmpty, reason: motif.code);
        expect(motif.explication.trim(), isNotEmpty, reason: motif.code);
      }
    });

    test('depuisCode retrouve le motif, et retombe sur « autre »', () {
      expect(
        MotifSortieStock.depuisCode('casse'),
        MotifSortieStock.casse,
      );
      expect(
        MotifSortieStock.depuisCode('  offert  '),
        MotifSortieStock.offert,
      );
      expect(MotifSortieStock.depuisCode('inconnu'), MotifSortieStock.autre);
      expect(MotifSortieStock.depuisCode(null), MotifSortieStock.autre);
    });

    test('libelleDe / iconeDe ne lèvent jamais pour un code inconnu', () {
      expect(MotifSortieStock.libelleDe('bizarre'), 'bizarre');
      expect(MotifSortieStock.libelleDe(null), 'Motif inconnu');
      expect(MotifSortieStock.iconeDe('bizarre'), isNotNull);
    });

    test('les pertes de valeur sont identifiées', () {
      expect(MotifSortieStock.perte.estUnePerte, isTrue);
      expect(MotifSortieStock.casse.estUnePerte, isTrue);
      expect(MotifSortieStock.peremption.estUnePerte, isTrue);
      expect(MotifSortieStock.offert.estUnePerte, isFalse);
      expect(MotifSortieStock.consommationProprietaire.estUnePerte, isFalse);
    });
  });

  group('SortieStock.fromMap', () {
    test('lit une ligne complète du serveur', () {
      final SortieStock s = SortieStock.fromMap(<String, dynamic>{
        'sortie_id': 12,
        'produit_id': 508,
        'produit': 'Sucre 1 kg',
        'unite': 'kg',
        'quantite': 2,
        'motif': 'consommation_proprietaire',
        'note': 'sucre pris à la maison',
        'valeur_unitaire': 3500,
        'valeur_totale': 7000,
        'date': '2026-09-20T09:30:00Z',
      });

      expect(s.id, 12);
      expect(s.produitId, 508);
      expect(s.produit, 'Sucre 1 kg');
      expect(s.unite, 'kg');
      expect(s.quantite, 2.0);
      expect(s.libelleMotif, 'Consommation du propriétaire');
      expect(s.note, 'sucre pris à la maison');
      expect(s.valeurTotale, 7000.0);
      expect(s.date?.toUtc().hour, 9);
    });

    test('tolère les champs absents', () {
      final SortieStock s = SortieStock.fromMap(<String, dynamic>{});
      expect(s.id, 0);
      expect(s.produit, 'Article');
      expect(s.unite, 'unité');
      expect(s.motif, 'autre');
      expect(s.note, isNull);
      expect(s.valeurTotale, 0);
      expect(s.date, isNull);
    });
  });

  group('ResumeSortiesStock.fromRpc', () {
    test('lit les lignes, les totaux et le détail par motif', () {
      final ResumeSortiesStock r = ResumeSortiesStock.fromRpc(<String, dynamic>{
        'debut': '2026-09-01',
        'fin': '2026-09-30',
        'lignes': <dynamic>[
          <String, dynamic>{
            'sortie_id': 1,
            'produit_id': 10,
            'produit': 'Bouteille',
            'unite': 'pièce',
            'quantite': 3,
            'motif': 'casse',
            'valeur_unitaire': 500,
            'valeur_totale': 1500,
            'date': '2026-09-12T10:00:00Z',
          },
          <String, dynamic>{
            'sortie_id': 2,
            'produit_id': 11,
            'produit': 'Sucré',
            'unite': 'pièce',
            'quantite': 1,
            'motif': 'consommation_proprietaire',
            'valeur_unitaire': 200,
            'valeur_totale': 200,
            'date': '2026-09-13T11:00:00Z',
          },
        ],
        'totaux': <String, dynamic>{
          'nb': 2,
          'valeur': 1700,
          'par_motif': <String, dynamic>{
            'casse': <String, dynamic>{'nb': 1, 'valeur': 1500},
            'consommation_proprietaire': <String, dynamic>{
              'nb': 1,
              'valeur': 200,
            },
          },
        },
      });

      expect(r.lignes, hasLength(2));
      expect(r.nb, 2);
      expect(r.valeur, 1700);
      expect(r.parMotif['casse']?.valeur, 1500);
      expect(r.parMotif['casse']?.libelle, 'Casse');
      expect(r.estVide, isFalse);
      // Le motif le plus coûteux vient en premier.
      expect(r.motifsTries.first.key, 'casse');
    });

    test('tolère une réponse vide (aucune sortie sur la période)', () {
      final ResumeSortiesStock r =
          ResumeSortiesStock.fromRpc(<String, dynamic>{});
      expect(r.estVide, isTrue);
      expect(r.nb, 0);
      expect(r.valeur, 0);
      expect(r.parMotif, isEmpty);
      expect(r.motifsTries, isEmpty);
    });
  });

  group('StockService — messages d\'erreur', () {
    test('messageErreur retire le code technique', () {
      expect(
        StockService.messageErreur(
          'STOCK_INSUFFISANT|Il ne reste que 2 kg de « Sucre » en stock.',
        ),
        'Il ne reste que 2 kg de « Sucre » en stock.',
      );
      expect(
        StockService.messageErreur(
          'MOTIF_INVALIDE|Choisissez le motif de la sortie.',
        ),
        'Choisissez le motif de la sortie.',
      );
    });

    test('un message sans code est rendu tel quel', () {
      expect(
        StockService.messageErreur('Connexion impossible'),
        'Connexion impossible',
      );
    });
  });
}
