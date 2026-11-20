// test/entreprise_metier_test.dart
//
// Correctif 174 — le TYPE affiché par l'administration doit être le MÉTIER
// réel (espaces.type), pas l'axe commercial (entreprises.type_activite).
// Ces tests protègent le modèle : les champs de confort `metier` /
// `metierLibelle` sont lus, jamais envoyés à Supabase.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/type_activite.dart';

void main() {
  group('Entreprise — métier réel (correctif 174)', () {
    test('metier et metierLibelle sont lus', () {
      final Entreprise entreprise = Entreprise.fromMap(<String, dynamic>{
        'id': '11111111-1111-4111-8111-111111111111',
        'nom': 'HEKIMA PHARMA',
        'type_activite': 'boutique',
        'metier': 'pharmacie',
        'metier_libelle': 'Pharmacie',
      });

      expect(entreprise.typeActivite, TypeActivite.boutique);
      expect(entreprise.metier, 'pharmacie');
      expect(entreprise.metierLibelle, 'Pharmacie');
    });

    test('sans métier, les champs restent nuls (repli sur l\'axe)', () {
      final Entreprise entreprise = Entreprise.fromMap(<String, dynamic>{
        'id': '22222222-2222-4222-8222-222222222222',
        'nom': 'Boutique simple',
        'type_activite': 'boutique',
      });

      expect(entreprise.metier, isNull);
      expect(entreprise.metierLibelle, isNull);
    });

    test('copyWith propage le métier', () {
      final Entreprise base = Entreprise.fromMap(<String, dynamic>{
        'id': '33333333-3333-4333-8333-333333333333',
        'nom': 'Pressing Test',
      });

      final Entreprise copie = base.copyWith(
        metier: 'pressing',
        metierLibelle: 'Pressing & Blanchisserie',
      );

      expect(copie.metier, 'pressing');
      expect(copie.metierLibelle, 'Pressing & Blanchisserie');
      // Le reste de la fiche est conservé.
      expect(copie.id, base.id);
      expect(copie.nom, base.nom);
    });

    test('le métier n\'est JAMAIS envoyé à Supabase (toMap)', () {
      final Entreprise entreprise = Entreprise.fromMap(<String, dynamic>{
        'id': '44444444-4444-4444-8444-444444444444',
        'nom': 'Pharmacie du centre',
        'metier': 'pharmacie',
        'metier_libelle': 'Pharmacie',
      });

      final Map<String, dynamic> map = entreprise.toMap();
      expect(map.containsKey('metier'), isFalse);
      expect(map.containsKey('metier_libelle'), isFalse);
    });
  });
}
