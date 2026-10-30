// test/mode_rapide_test.dart
//
// ⚡ MODE RAPIDE — le mode simple doit être RÉELLEMENT simple.
//
// La règle testée ici est celle qu'utilisent les deux formulaires d'article
// (`add_product_page.dart` et `article_form_page.dart`) pour décider quels
// champs afficher :
//
//   • mode COMPLET  → tous les champs (photo, catégorie, unité, prix d'achat…)
//   • mode RAPIDE   → l'essentiel seulement (nom + prix de vente)
//
// Le mode ne change QUE ce qui est demandé : les deux modes écrivent les
// mêmes données (aucune donnée perdue en changeant de mode).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:biashara_yangu/services/mode_application_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ModeApplicationService service = ModeApplicationService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    service.mode.value = ModeApplication.complet;
  });

  group('ModeApplication.fromCode', () {
    test('reconnaît le code « rapide »', () {
      expect(ModeApplication.fromCode('rapide'), ModeApplication.rapide);
    });

    test('reconnaît le code « complet »', () {
      expect(ModeApplication.fromCode('complet'), ModeApplication.complet);
    });

    test('tolère la casse et les espaces autour du code', () {
      expect(ModeApplication.fromCode('  RAPIDE  '), ModeApplication.rapide);
      expect(ModeApplication.fromCode(' Complet '), ModeApplication.complet);
    });

    test('valeur absente ou inconnue retombe sur le mode complet', () {
      // Fail-open : on n'enferme jamais un commerçant dans le mode simple
      // parce qu'une préférence est illisible.
      expect(ModeApplication.fromCode(null), ModeApplication.complet);
      expect(ModeApplication.fromCode(''), ModeApplication.complet);
      expect(ModeApplication.fromCode('expert'), ModeApplication.complet);
    });
  });

  group('réglages avancés selon le mode', () {
    test('mode complet : les réglages avancés sont proposés', () {
      service.mode.value = ModeApplication.complet;

      expect(service.rapide, isFalse);
      expect(service.afficherReglagesAvances, isTrue);
    });

    test('mode rapide : les réglages avancés sont masqués', () {
      service.mode.value = ModeApplication.rapide;

      expect(service.rapide, isTrue);
      expect(service.afficherReglagesAvances, isFalse);
    });

    test('les deux notions restent exactement complémentaires', () {
      for (final ModeApplication mode in ModeApplication.values) {
        service.mode.value = mode;
        expect(
          service.afficherReglagesAvances,
          service.rapide == false,
          reason: 'mode ${mode.code}',
        );
      }
    });
  });

  group('lecture du mode enregistré', () {
    test('lit « rapide » depuis les préférences', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{ModeApplicationService.clePreference: 'rapide'});

      await service.charger();

      expect(service.rapide, isTrue);
      expect(service.afficherReglagesAvances, isFalse);
      expect(service.charge, isTrue);
    });

    test('sans préférence enregistrée, reste en mode complet', () async {
      await service.charger();

      expect(service.rapide, isFalse);
      expect(service.afficherReglagesAvances, isTrue);
    });

    test('une valeur corrompue ne bloque pas l\'application', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ModeApplicationService.clePreference: '{"cassé":true}',
      });

      await service.charger();

      expect(service.rapide, isFalse);
      expect(service.charge, isTrue);
    });
  });

  group('changement de mode', () {
    test('definir diffuse le mode et le mémorise', () async {
      await service.definir(ModeApplication.rapide);
      expect(service.rapide, isTrue);

      // Un nouveau chargement relit bien la valeur enregistrée.
      service.mode.value = ModeApplication.complet;
      await service.charger();
      expect(service.rapide, isTrue);
    });

    test('basculer alterne entre les deux modes', () async {
      await service.basculer();
      expect(service.mode.value, ModeApplication.rapide);

      await service.basculer();
      expect(service.mode.value, ModeApplication.complet);
    });

    test('le mode est diffusé aux écrans abonnés', () async {
      final List<ModeApplication> vus = <ModeApplication>[];
      void ecouteur() => vus.add(service.mode.value);

      service.mode.addListener(ecouteur);
      addTearDown(() => service.mode.removeListener(ecouteur));

      await service.definir(ModeApplication.rapide);

      expect(vus, contains(ModeApplication.rapide));
    });
  });
}
