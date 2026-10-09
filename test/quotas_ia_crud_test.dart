// test/quotas_ia_crud_test.dart
//
// 🪙 CORRECTIF 68 — TESTS DU CATALOGUE DES QUOTAS IA.
//
// Ce qui est testé ici décide de ce que le client PAIE : le prix d'un pack,
// et ce qui reste reprenable à un collaborateur. Ce sont donc des fonctions
// pures, vérifiables sans réseau ni base de données.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/agent_ia.dart';

void main() {
  group('PackQuotas — catalogue venu de la base', () {
    test('lit un pack complet', () {
      final PackQuotas? pack = PackQuotas.depuisJson(<String, dynamic>{
        'id': 'p1',
        'quotas': 30,
        'prix': 2700,
        'libelle': 'Pack relais',
        'ordre': 25,
        'actif': true,
      });

      expect(pack, isNotNull);
      expect(pack!.id, 'p1');
      expect(pack.quotas, 30);
      expect(pack.prix, 2700);
      expect(pack.libelleAffiche, 'Pack relais');
      expect(pack.vientDeLaBase, isTrue);
      // 2 700 / 30 = 90 CDF par quota.
      expect(pack.prixParQuota, 90);
    });

    test('« actif » absent vaut ACTIF (une base plus ancienne ne doit pas '
        'faire disparaître le catalogue)', () {
      final PackQuotas? pack = PackQuotas.depuisJson(<String, dynamic>{
        'id': 'p1',
        'quotas': 10,
        'prix': 1000,
      });

      expect(pack!.actif, isTrue);
    });

    test('refuse un pack sans taille exploitable', () {
      expect(PackQuotas.depuisJson(<String, dynamic>{'id': 'x', 'prix': 100}),
          isNull);
      expect(
        PackQuotas.depuisJson(<String, dynamic>{'id': 'x', 'quotas': 0}),
        isNull,
      );
      expect(PackQuotas.depuisJson('pas un objet'), isNull);
    });

    test('un libellé vide retombe sur la taille, jamais sur du vide', () {
      final PackQuotas? pack = PackQuotas.depuisJson(<String, dynamic>{
        'id': 'p1',
        'quotas': 50,
        'prix': 4000,
        'libelle': '   ',
      });

      expect(pack!.libelleAffiche, '50 quotas');
    });

    test('trie par ordre voulu par le Super Admin, puis par taille', () {
      final List<PackQuotas> packs = PackQuotas.listeDepuisJson(<dynamic>[
        <String, dynamic>{'id': 'c', 'quotas': 100, 'prix': 9000, 'ordre': 40},
        <String, dynamic>{'id': 'a', 'quotas': 10, 'prix': 1000, 'ordre': 10},
        <String, dynamic>{'id': 'b', 'quotas': 50, 'prix': 4500, 'ordre': 10},
        <String, dynamic>{'id': 'd', 'quotas': 20, 'prix': 1900, 'ordre': 20},
      ]);

      // ordre 10 : 10 puis 50 quotas ; ordre 20 : 20 ; ordre 40 : 100.
      expect(packs.map((PackQuotas p) => p.quotas).toList(), <int>[10, 50, 20, 100]);
    });

    test('ignore les entrées illisibles sans perdre les autres', () {
      final List<PackQuotas> packs = PackQuotas.listeDepuisJson(<dynamic>[
        <String, dynamic>{'id': 'a', 'quotas': 10, 'prix': 1000},
        'ligne pourrie',
        <String, dynamic>{'id': 'b', 'paquets': 3},
        <String, dynamic>{'id': 'c', 'quotas': 20, 'prix': 2000},
      ]);

      expect(packs.length, 2);
      expect(packs.map((PackQuotas p) => p.quotas).toList(), <int>[10, 20]);
    });

    test('une réponse vide ne lève pas', () {
      expect(PackQuotas.listeDepuisJson(null), isEmpty);
      expect(PackQuotas.listeDepuisJson(<dynamic>[]), isEmpty);
    });
  });

  group('PackQuotas — repli local (migration non exécutée)', () {
    final AgentIaConfig config = AgentIaConfig.defaut;

    test('produit les 4 packs d\'origine, à prix proportionnels', () {
      final List<PackQuotas> packs = PackQuotas.depuisConfig(config);

      expect(packs.length, 4);
      expect(packs.map((PackQuotas p) => p.quotas).toList(),
          <int>[10, 20, 50, 100]);

      // ⚠️ Le prix du pack de 10 est la base : les autres en sont des
      // multiples STRICTS, comme avant le correctif 68. Aucune régression.
      final double base = packs.first.prix;
      expect(packs[1].prix, base * 2);
      expect(packs[2].prix, base * 5);
      expect(packs[3].prix, base * 10);
    });

    test('un pack de repli est SIGNALÉ comme ne venant pas de la base', () {
      // Sans ce marqueur, le Super Admin croirait que ses modifications ont
      // été enregistrées alors que la grille affichée est locale.
      for (final PackQuotas p in PackQuotas.depuisConfig(config)) {
        expect(p.vientDeLaBase, isFalse);
      }
    });

    test('le prix par quota est protégé contre la division par zéro', () {
      const PackQuotas pack = PackQuotas(quotas: 0, prix: 5000);
      expect(pack.prixParQuota, 0);
    });
  });

  group('AttributionQuota — le solde d\'un collaborateur', () {
    test('lit une attribution complète', () {
      final AttributionQuota? a =
          AttributionQuota.depuisJson(<String, dynamic>{
        'utilisateur_id': 'u1',
        'nom': 'Josué',
        'role': 'VENDEUR',
        'quotas_disponibles': 35,
        'quotas_utilises_total': 15,
        'quotas_achetes_total': 0,
        'attribue_par_nom': 'Andre',
      });

      expect(a, isNotNull);
      expect(a!.nom, 'Josué');
      expect(a.quotasDisponibles, 35);
      expect(a.quotasUtilisesTotal, 15);
      expect(a.attribueParNom, 'Andre');
      expect(a.peutEtreReprise, isTrue);
    });

    test('sans identifiant, la ligne est ignorée (elle serait inutilisable)', () {
      expect(
        AttributionQuota.depuisJson(<String, dynamic>{'nom': 'Josué'}),
        isNull,
      );
    });

    test('tout consommé = rien à reprendre', () {
      final AttributionQuota? a =
          AttributionQuota.depuisJson(<String, dynamic>{
        'utilisateur_id': 'u1',
        'quotas_disponibles': 0,
        'quotas_utilises_total': 50,
      });

      expect(a!.peutEtreReprise, isFalse);
    });

    test('un nom absent n\'est jamais vide à l\'écran', () {
      final AttributionQuota? a =
          AttributionQuota.depuisJson(<String, dynamic>{'utilisateur_id': 'u1'});
      expect(a!.nom, 'Collaborateur');
    });
  });

  group('AttributionsQuotas — le tableau complet', () {
    test('lit le pool et les membres, dans l\'ordre alphabétique', () {
      final AttributionsQuotas tableau =
          AttributionsQuotas.depuisJson(<String, dynamic>{
        'entreprise_id': 'e1',
        'pool_disponible': 120,
        'attributions': <dynamic>[
          <String, dynamic>{
            'utilisateur_id': 'u1',
            'nom': 'Zoé',
            'quotas_disponibles': 10,
            'quotas_utilises_total': 5,
          },
          <String, dynamic>{
            'utilisateur_id': 'u2',
            'nom': 'Andre',
            'quotas_disponibles': 30,
            'quotas_utilises_total': 20,
          },
        ],
      });

      expect(tableau.poolDisponible, 120);
      expect(tableau.attributions.map((AttributionQuota a) => a.nom).toList(),
          <String>['Andre', 'Zoé']);
      expect(tableau.totalChezLesMembres, 40);
      expect(tableau.totalConsomme, 25);
      expect(tableau.estVide, isFalse);
    });

    test('un tableau vide est reconnu comme tel, sans lever', () {
      expect(AttributionsQuotas.depuisJson(null).estVide, isTrue);
      expect(AttributionsQuotas.depuisJson(<String, dynamic>{}).estVide, isTrue);
      expect(AttributionsQuotas.vide.poolDisponible, 0);
      expect(AttributionsQuotas.vide.totalChezLesMembres, 0);
    });

    test('les totaux ne comptent QUE les quotas non consommés comme '
        'reprenables', () {
      // C'est la distinction qui protège le patron : ce qui est consommé ne
      // reviendra jamais, on ne doit donc pas le lui promettre.
      final AttributionsQuotas tableau =
          AttributionsQuotas.depuisJson(<String, dynamic>{
        'pool_disponible': 0,
        'attributions': <dynamic>[
          <String, dynamic>{
            'utilisateur_id': 'u1',
            'nom': 'A',
            'quotas_disponibles': 4,
            'quotas_utilises_total': 96,
          },
        ],
      });

      expect(tableau.totalChezLesMembres, 4);
      expect(tableau.totalConsomme, 96);
    });
  });
}
