// test/modules_test.dart
//
// 🧩 MODULE 16 (phase A) — Tests des parties PURES du référentiel des
// modules : catalogue, profils, garde « fail-open » et outils de la couche
// service (slug, tri). Aucun réseau, aucun greffon.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/services/modules_service.dart';

void main() {
  group('ModuleActivite — catalogue', () {
    test('les codes sont uniques et bien formés (snake_case)', () {
      final Set<String> vus = <String>{};
      final RegExp format = RegExp(r'^[a-z][a-z0-9_]*$');

      for (final ModuleActivite module in ModuleActivite.catalogue) {
        expect(
          vus.add(module.code),
          isTrue,
          reason: 'Code dupliqué dans le catalogue : ${module.code}',
        );
        expect(
          format.hasMatch(module.code),
          isTrue,
          reason: 'Code mal formé : ${module.code}',
        );
        expect(module.libelle.trim(), isNotEmpty);
      }
    });

    test('parCode retrouve un module connu, null sinon', () {
      expect(ModuleActivite.parCode(ModuleCode.ventes)?.libelle,
          'Ventes & panier');
      expect(ModuleActivite.parCode('inconnu_xyz'), isNull);
      expect(ModuleActivite.codeConnu(ModuleCode.assistantIa), isTrue);
      expect(ModuleActivite.codeConnu('inconnu_xyz'), isFalse);
    });

    test('les 10 modules de base existent et sont disponibles', () {
      for (final String code in ModulesService.modulesBase) {
        final ModuleActivite? module = ModuleActivite.parCode(code);
        expect(module, isNotNull, reason: 'Module de base absent : $code');
        expect(module!.disponible, isTrue,
            reason: 'Un module de base doit être disponible : $code');
      }
      expect(ModulesService.modulesBase.length, 10);
    });

    test('les modules métier des phases C sont pré-déclarés « bientôt »', () {
      for (final String code in <String>[
        ModuleCode.chambres,
        ModuleCode.reservations,
        ModuleCode.checkin,
        ModuleCode.tables,
        ModuleCode.commandes,
        ModuleCode.cuisine,
        ModuleCode.salles,
        ModuleCode.evenements,
        ModuleCode.lotsExpiration,
        ModuleCode.production,
        ModuleCode.pesee,
        ModuleCode.variantes,
      ]) {
        final ModuleActivite? module = ModuleActivite.parCode(code);
        expect(module, isNotNull, reason: 'Module pré-déclaré absent : $code');
        expect(module!.disponible, isFalse,
            reason: 'Un module non codé doit être marqué « bientôt » : $code');
      }
    });
  });

  group('ProfilModules — analyse des réponses serveur', () {
    test('modulesDepuisJson : normalise, déduplique, ignore l\'invalide', () {
      final Set<String> modules = ProfilModules.modulesDepuisJson(
        <dynamic>[
          'ventes',
          ' VENTES ',
          'Produits',
          42,
          null,
          '',
          'stock',
        ],
      );

      expect(modules, <String>{'ventes', 'produits', 'stock'});
    });

    test('modulesDepuisJson : entrée non-tableau => ensemble vide', () {
      expect(ProfilModules.modulesDepuisJson(null), isEmpty);
      expect(ProfilModules.modulesDepuisJson('ventes'), isEmpty);
      expect(ProfilModules.modulesDepuisJson(<String, dynamic>{}), isEmpty);
    });

    test('fromMap : profil complet', () {
      final ProfilModules profil = ProfilModules.fromMap(<String, dynamic>{
        'type': 'hotel',
        'libelle': 'Hôtel',
        'modules': <dynamic>['ventes', 'chambres', 'reservations'],
        'actif': true,
        'nb_espaces': 2,
        'updated_at': '2026-09-18T12:00:00Z',
      });

      expect(profil.type, 'hotel');
      expect(profil.libelle, 'Hôtel');
      expect(profil.modules, <String>{'ventes', 'chambres', 'reservations'});
      expect(profil.actif, isTrue);
      expect(profil.nbEspaces, 2);
      expect(profil.updatedAt, isNotNull);
      expect(profil.profilDefaut, isFalse);
      expect(profil.modulesInconnus, isEmpty);
    });

    test('fromMap : valeurs par défaut (actif, nb_espaces)', () {
      final ProfilModules profil = ProfilModules.fromMap(<String, dynamic>{
        'type': 'boutique',
        'libelle': 'Boutique',
        'modules': <dynamic>[],
      });

      expect(profil.actif, isTrue);
      expect(profil.nbEspaces, 0);
      expect(profil.updatedAt, isNull);
      expect(profil.profilDefaut, isTrue);
    });

    test('modulesInconnus : codes plus récents que l\'application', () {
      final ProfilModules profil = ProfilModules.fromMap(<String, dynamic>{
        'type': 'autre',
        'libelle': 'Autre',
        'modules': <dynamic>['ventes', 'module_du_futur'],
      });

      expect(profil.modulesInconnus, <String>{'module_du_futur'});
    });
  });

  group('ModulesService — garde fail-open', () {
    test('non chargé => tout est actif (comportement historique)', () {
      expect(
        ModulesService.estActif(<String>{}, false, ModuleCode.rapports),
        isTrue,
      );
    });

    test('profil vide => tout est actif', () {
      expect(
        ModulesService.estActif(<String>{}, true, ModuleCode.rapports),
        isTrue,
      );
    });

    test('profil chargé : le module listé est actif, l\'autre non', () {
      const Set<String> profil = <String>{'ventes', 'produits'};

      expect(ModulesService.estActif(profil, true, ModuleCode.ventes), isTrue);
      expect(
        ModulesService.estActif(profil, true, ModuleCode.rapports),
        isFalse,
      );
    });
  });

  group('ModulesService — outils', () {
    test('ordonnerModules : ordre du catalogue, inconnus à la fin', () {
      final List<String> ordonnes = ModulesService.ordonnerModules(
        <String>{'stock', 'ventes', 'zzz_inconnu', 'aaa_inconnu'},
      );

      // ventes et stock existent dans l'ordre du catalogue.
      final int indexVentes = ordonnes.indexOf(ModuleCode.ventes);
      final int indexStock = ordonnes.indexOf(ModuleCode.stock);
      expect(indexVentes, greaterThanOrEqualTo(0));
      expect(indexVentes, lessThan(indexStock));

      // Inconnus triés alphabétiquement, en fin de liste.
      expect(ordonnes.sublist(ordonnes.length - 2),
          <String>['aaa_inconnu', 'zzz_inconnu']);
    });

    test('codeProfilDepuisLibelle : slug standard', () {
      expect(
        ModulesService.codeProfilDepuisLibelle('Salon de coiffure'),
        'salon_de_coiffure',
      );
      expect(
        ModulesService.codeProfilDepuisLibelle('Dépôt'),
        'depot',
      );
      expect(
        ModulesService.codeProfilDepuisLibelle('Épicerie & Tabac'),
        'epicerie_tabac',
      );
    });

    test('codeProfilDepuisLibelle : espaces multiples et bords nettoyés', () {
      expect(
        ModulesService.codeProfilDepuisLibelle('  Boutique   Pro  '),
        'boutique_pro',
      );
      expect(
        ModulesService.codeProfilDepuisLibelle('Hôtel — Bar'),
        'hotel_bar',
      );
    });

    test('codeProfilDepuisLibelle : ne commence jamais par un chiffre', () {
      expect(
        ModulesService.codeProfilDepuisLibelle('3 étoiles'),
        'type_3_etoiles',
      );
    });

    test('codeProfilDepuisLibelle : vide => « type », longueur limitée', () {
      expect(ModulesService.codeProfilDepuisLibelle('   '), 'type');
      expect(ModulesService.codeProfilDepuisLibelle('!!!'), 'type');

      final String long = ModulesService.codeProfilDepuisLibelle(
        List<String>.filled(80, 'a').join(),
      );
      expect(long.length, lessThanOrEqualTo(40));
      expect(long.endsWith('_'), isFalse);
    });

    test('les slugs générés respectent la validation SQL', () {
      final RegExp validationSql = RegExp(r'^[a-z][a-z0-9_]{1,40}$');

      for (final String libelle in <String>[
        'Salon de coiffure',
        'Dépôt',
        'Épicerie & Tabac',
        'Boutique Pro',
        'Hôtel — Bar',
        '3 étoiles',
        'Quincaillerie du Peuple',
      ]) {
        final String code = ModulesService.codeProfilDepuisLibelle(libelle);
        expect(
          validationSql.hasMatch(code),
          isTrue,
          reason: 'Slug invalide pour « $libelle » : $code',
        );
      }
    });
  });
}
