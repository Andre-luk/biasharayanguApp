// test/packs_test.dart
//
// 🧩 MODULE 16 (phase E) — Tests PURS des packs par modules : lecture /
// écriture du jsonb `modules` du groupe tarifaire, normalisation, résumé et
// sémantique « vide = aucun filtre ». Aucun réseau.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/groupe_tarifaire.dart';

void main() {
  group('GroupeTarifaire — modules du pack', () {
    test('fromMap lit le tableau jsonb de modules', () {
      final GroupeTarifaire pack = GroupeTarifaire.fromMap(<String, dynamic>{
        'id': 'g-1',
        'nom': 'Essentiel',
        'montant_abonnement': 20000.0,
        'modules': <dynamic>['ventes', 'stock', 'caisse', 'rapports'],
      });

      expect(pack.modules,
          <String>{'ventes', 'stock', 'caisse', 'rapports'});
      expect(pack.filtreModules, isTrue);
      expect(pack.resumeModules, '4 modules');
    });

    test('modules absent → aucun filtre (comportement historique)', () {
      final GroupeTarifaire pack = GroupeTarifaire.fromMap(<String, dynamic>{
        'id': 'g-2',
        'nom': 'Standard',
      });

      expect(pack.modules, isEmpty);
      expect(pack.filtreModules, isFalse);
      expect(pack.resumeModules, 'Tous modules');
    });

    test('tableau vide → aucun filtre', () {
      final GroupeTarifaire pack = GroupeTarifaire.fromMap(<String, dynamic>{
        'id': 'g-3',
        'nom': 'Libre',
        'modules': <dynamic>[],
      });

      expect(pack.filtreModules, isFalse);
    });

    test('normalisation : casse, espaces, doublons, valeurs invalides', () {
      final GroupeTarifaire pack = GroupeTarifaire.fromMap(<String, dynamic>{
        'id': 'g-4',
        'nom': 'Bricolé',
        'modules': <dynamic>[
          ' VENTES ',
          'Ventes',
          'stock',
          42,
          null,
          <String>['imbriqué'],
        ],
      });

      expect(pack.modules, <String>{'ventes', 'stock'},
          reason: 'casse repliée, doublons et valeurs non textuelles écartés');
    });

    test('toMap envoie les modules sous forme de tableau', () {
      const GroupeTarifaire pack = GroupeTarifaire(
        id: 'g-5',
        nom: 'Avancé',
        modules: <String>{'ventes', 'assistant_ia'},
      );

      final List<dynamic> modules =
          pack.toMap()['modules'] as List<dynamic>;
      expect(modules, hasLength(2));
      expect(modules, containsAll(<String>['ventes', 'assistant_ia']));
    });

    test('copyWith conserve et modifie les modules', () {
      const GroupeTarifaire pack = GroupeTarifaire(
        id: 'g-6',
        nom: 'Spécialisé',
        modules: <String>{'ventes', 'chambres'},
      );

      expect(pack.copyWith(nom: 'Spécialisé+').modules,
          <String>{'ventes', 'chambres'});
      expect(
        pack.copyWith(modules: <String>{'ventes'}).modules,
        <String>{'ventes'},
      );
      expect(pack.copyWith(modules: const <String>{}).filtreModules, isFalse);
    });

    test('les autres champs du pack restent inchangés (copie Phase E)', () {
      final GroupeTarifaire pack = GroupeTarifaire.fromMap(<String, dynamic>{
        'id': 'g-7',
        'nom': 'Hôtel Avancé',
        'frais_ouverture': 5000.0,
        'montant_abonnement': 50000.0,
        'duree_essai_jours': 7,
        'duree_abonnement_jours': 30,
        'prix_par_collaborateur': 0.5,
        'max_espaces': 3,
        'modules': <dynamic>['ventes', 'chambres', 'reservations'],
      });

      expect(pack.nom, 'Hôtel Avancé');
      expect(pack.montantAbonnement, 50000);
      expect(pack.maxEspaces, 3);
      expect(pack.packMulti, isTrue);
      expect(pack.modules,
          <String>{'ventes', 'chambres', 'reservations'});
    });
  });
}
