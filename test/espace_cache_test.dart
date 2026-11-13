// test/espace_cache_test.dart
//
// 🧩 MODULE 15 — « LA BONNE ENTREPRISE DÈS LA PREMIÈRE SECONDE ».
//
// Le contexte d'entreprise venait UNIQUEMENT du réseau : au démarrage sur
// réseau lent/instable, la liste n'arrivait pas, le sélecteur disparaissait et
// les lectures retombaient sur la PREMIÈRE entreprise du compte (celle qui
// porte l'UUID du patron). Symptôme vécu : « je rouvre l'application et les
// produits de la pharmacie sont devenus ceux de la boutique ».
//
// Ces tests vérifient SANS réseau :
//   • la restauration du dernier état connu (`restaurerDepuisCache`) ;
//   • la publication immédiate de la portée de travail (`ScopeDonnees`) ;
//   • la remise à zéro à la déconnexion (le compte suivant n'hérite de rien).
//
//     flutter test test/espace_cache_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:biashara_yangu/services/espace_service.dart';
import 'package:biashara_yangu/services/scope_donnees.dart';

/// Réponse type de `rpc_espaces_lister` (compte à deux entreprises).
Map<String, dynamic> reponseDeuxEntreprises() => <String, dynamic>{
      'role': 'PROPRIETAIRE',
      'raison': 'quota',
      'espaces': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': '07a0cdf1-50d6-444a-a559-e17d8e0ef4d8',
          'nom': 'Urembo Market',
          'type': 'boutique',
          'actif': true,
          'est_actif': false,
        },
        <String, dynamic>{
          'id': 'be5a5d15-b682-4990-8ad4-11b61002bddd',
          'nom': 'HEKIMA PHARMA',
          'type': 'pharmacie',
          'actif': true,
          'est_actif': true,
        },
      ],
      'actif_id': 'be5a5d15-b682-4990-8ad4-11b61002bddd',
      'peut_creer': false,
      'max_espaces': 2,
      'nb_entreprises': 2,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Aucun cache au départ : chaque test pose son propre état.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    EspaceService.instance.reinitialiser();
    ScopeDonnees.reinitialiser();
  });

  test('aucun cache → rien n\'est publié (comportement historique)', () async {
    await EspaceService.instance.restaurerDepuisCache();

    expect(EspaceService.instance.etat.value, isNull);
    expect(EspaceService.instance.restaureeDepuisCache, isFalse);
    expect(ScopeDonnees.espaceActif, isNull);
  });

  test('cache présent → l\'entreprise active est connue AVANT le réseau',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      EspaceService.cleCache: jsonEncode(reponseDeuxEntreprises()),
    });

    await EspaceService.instance.restaurerDepuisCache();

    // 1. la liste est publiée : le sélecteur peut s'afficher ;
    expect(EspaceService.instance.etat.value, isNotNull);
    expect(EspaceService.instance.nombre, 2);
    expect(EspaceService.instance.multiEntreprises, isTrue);
    // 2. l'entreprise ACTIVE est celle de la dernière session (la pharmacie),
    //    pas la première de la liste.
    expect(
      EspaceService.instance.actif?.nom,
      'HEKIMA PHARMA',
    );
    // 3. la portée de travail est publiée : les lectures/écritures visent la
    //    pharmacie et non plus l'UUID du patron (boutique).
    expect(
      ScopeDonnees.espaceActif,
      'be5a5d15-b682-4990-8ad4-11b61002bddd',
    );
    expect(EspaceService.instance.restaureeDepuisCache, isTrue);
  });

  test('cache illisible → ignoré, aucune exception', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      EspaceService.cleCache: 'pas du json',
    });

    await EspaceService.instance.restaurerDepuisCache();

    expect(EspaceService.instance.etat.value, isNull);
    expect(ScopeDonnees.espaceActif, isNull);
  });

  test('cache vide (aucune entreprise) → ignoré', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      EspaceService.cleCache: jsonEncode(<String, dynamic>{
        'espaces': <dynamic>[],
        'actif_id': null,
        'max_espaces': 1,
      }),
    });

    await EspaceService.instance.restaurerDepuisCache();

    expect(EspaceService.instance.etat.value, isNull);
    expect(ScopeDonnees.espaceActif, isNull);
  });

  test('déconnexion → état ET portée remis à zéro', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      EspaceService.cleCache: jsonEncode(reponseDeuxEntreprises()),
    });

    await EspaceService.instance.restaurerDepuisCache();
    expect(ScopeDonnees.espaceActif, isNotNull);

    EspaceService.instance.reinitialiser();

    expect(EspaceService.instance.etat.value, isNull);
    expect(EspaceService.instance.restaureeDepuisCache, isFalse);
    expect(ScopeDonnees.espaceActif, isNull);
  });
}
