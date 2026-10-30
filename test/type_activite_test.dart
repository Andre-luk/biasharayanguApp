// test/type_activite_test.dart
//
// REFONTE ABONNEMENTS & DISTRIBUTION — type d'activité (boutique /
// distribution) : conversion, règles de masquage et filtrage des cartes
// d'accueil. Tests PURS (sans réseau, sans Supabase).

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/type_activite.dart';
import 'package:biashara_yangu/ui/accueil/cartes_accueil.dart';

void main() {
  group('TypeActivite.depuis', () {
    test('reconnaît les codes exacts', () {
      expect(TypeActivite.depuis('boutique'), TypeActivite.boutique);
      expect(TypeActivite.depuis('distribution'), TypeActivite.distribution);
    });

    test('tolère la casse et les espaces', () {
      expect(TypeActivite.depuis('  BOUTIQUE '), TypeActivite.boutique);
      expect(TypeActivite.depuis('Distribution'), TypeActivite.distribution);
    });

    test('tolère les variantes métier', () {
      expect(TypeActivite.depuis('distributeur'), TypeActivite.distribution);
      expect(TypeActivite.depuis('magasin'), TypeActivite.boutique);
    });

    test('renvoie null pour une valeur vide ou inconnue', () {
      expect(TypeActivite.depuis(null), isNull);
      expect(TypeActivite.depuis(''), isNull);
      expect(TypeActivite.depuis('hotel'), isNull);
    });
  });

  group('ReglesTypeActivite.masque', () {
    test('une entrée commune n’est jamais masquée', () {
      expect(ReglesTypeActivite.masque(null, null), isFalse);
      expect(ReglesTypeActivite.masque(TypeActivite.boutique, null), isFalse);
    });

    test('fail-open : type non renseigné → rien n’est masqué', () {
      expect(
        ReglesTypeActivite.masque(null, TypeActivite.distribution),
        isFalse,
      );
    });

    test('le type connu filtre les entrées de l’autre métier', () {
      expect(
        ReglesTypeActivite.masque(
          TypeActivite.boutique,
          TypeActivite.distribution,
        ),
        isTrue,
      );
      expect(
        ReglesTypeActivite.masque(
          TypeActivite.distribution,
          TypeActivite.distribution,
        ),
        isFalse,
      );
    });
  });

  group('CarteAccueil.visibles — séparation boutique / distribution', () {
    List<String> ids(TypeActivite? type) => CarteAccueil.visibles(
          modules: const <String>{},
          profilCharge: false,
          autorise: (PageAccess page, ActionAccess action) => true,
          typeActivite: type,
        ).map((CarteAccueil c) => c.id).toList(growable: false);

    test('type non renseigné → les cartes de distribution restent visibles', () {
      final List<String> liste = ids(null);
      expect(liste, contains('tournees'));
      expect(liste, contains('consignes'));
      expect(liste, contains('ma-tournee'));
    });

    test('entreprise de distribution → cartes de distribution visibles', () {
      final List<String> liste = ids(TypeActivite.distribution);
      expect(liste, contains('tournees'));
      expect(liste, contains('ma-tournee'));
      expect(liste, contains('recipients'));
    });

    test('boutique → aucune carte de distribution', () {
      final List<String> liste = ids(TypeActivite.boutique);
      expect(liste, isNot(contains('tournees')));
      expect(liste, isNot(contains('consignes')));
      expect(liste, isNot(contains('ma-tournee')));
      expect(liste, isNot(contains('recipients')));
    });

    test('boutique → les cartes communes restent présentes', () {
      final List<String> liste = ids(TypeActivite.boutique);
      expect(liste, contains('produits'));
      expect(liste, contains('ventes'));
    });
  });
}
