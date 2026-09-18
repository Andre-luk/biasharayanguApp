// test/espace_test.dart
//
// Tests unitaires du MODULE 15 — Pack avancé multi-entreprises.
//
// Aucun accès réseau : vérification des modèles (parsing des réponses des
// RPC), des règles d'affichage (quota du pack, entreprise active) et de la
// grille tarifaire étendue (max_espaces).
//
//     flutter test test/espace_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/espace.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';

void main() {
  // =========================================================================
  // 1. TYPES D'ENTREPRISE
  // =========================================================================

  group('TypeEspace', () {
    test('conversion des codes SQL', () {
      expect(TypeEspace.fromCode('boutique'), TypeEspace.boutique);
      expect(TypeEspace.fromCode('hotel'), TypeEspace.hotel);
      expect(TypeEspace.fromCode('pharmacie'), TypeEspace.pharmacie);
      expect(TypeEspace.fromCode('restaurant'), TypeEspace.restaurant);
      expect(TypeEspace.fromCode('depot'), TypeEspace.depot);
      expect(TypeEspace.fromCode('autre'), TypeEspace.autre);
    });

    test('tolérance casse et code inconnu', () {
      expect(TypeEspace.fromCode('HOTEL'), TypeEspace.hotel);
      expect(TypeEspace.fromCode(' MAGASIN '), TypeEspace.autre);
      expect(TypeEspace.fromCode(null), TypeEspace.autre);
    });
  });

  // =========================================================================
  // 2. MODÈLE ESPACE
  // =========================================================================

  group('Espace', () {
    test('parsing complet', () {
      final Espace espace = Espace.fromMap(<String, dynamic>{
        'id': 'e-1',
        'nom': 'Hôtel Royal',
        'type': 'hotel',
        'actif': true,
        'est_actif': true,
        'created_at': '2026-09-18T08:00:00Z',
      });

      expect(espace.id, 'e-1');
      expect(espace.nom, 'Hôtel Royal');
      expect(espace.type, TypeEspace.hotel);
      expect(espace.actif, isTrue);
      expect(espace.estActif, isTrue);
      expect(espace.createdAt, isNotNull);
    });

    test('champs absents tolérés (jamais d\'exception)', () {
      final Espace espace = Espace.fromMap(<String, dynamic>{
        'id': 'e-2',
        'nom': 'Boutique',
      });

      expect(espace.type, TypeEspace.autre);
      expect(espace.actif, isTrue);
      expect(espace.estActif, isFalse);
      expect(espace.createdAt, isNull);
    });

    test('copyWith modifie uniquement estActif', () {
      const Espace espace = Espace(id: 'e-3', nom: 'Pharmacie');
      final Espace bascule = espace.copyWith(estActif: true);

      expect(bascule.estActif, isTrue);
      expect(bascule.id, 'e-3');
      expect(bascule.nom, 'Pharmacie');
    });
  });

  // =========================================================================
  // 3. ÉTAT DES ESPACES (rpc_espaces_lister)
  // =========================================================================

  group('EtatEspaces', () {
    test('pack standard : une entreprise, création bloquée par quota', () {
      final EtatEspaces etat = EtatEspaces.fromMap(<String, dynamic>{
        'espaces': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'patron-1',
            'nom': 'Boutique Étoile',
            'type': 'boutique',
            'est_actif': true,
          },
        ],
        'actif_id': 'patron-1',
        'max_espaces': 1,
        'role': 'PROPRIETAIRE',
        'peut_creer': false,
        'raison': 'quota',
      });

      expect(etat.espaces.length, 1);
      expect(etat.actif?.id, 'patron-1');
      expect(etat.multiEntreprises, isFalse);
      expect(etat.packMulti, isFalse);
      expect(etat.placesRestantes, 0);
      expect(etat.peutCreer, isFalse);
      expect(etat.raison, RaisonBlocageCreation.quota);
    });

    test('pack avancé : 2/3 entreprises, une place restante', () {
      final EtatEspaces etat = EtatEspaces.fromMap(<String, dynamic>{
        'espaces': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'patron-1',
            'nom': 'Boutique Étoile',
            'type': 'boutique',
            'est_actif': false,
          },
          <String, dynamic>{
            'id': 'h-1',
            'nom': 'Hôtel Royal',
            'type': 'hotel',
            'est_actif': true,
          },
        ],
        'actif_id': 'h-1',
        'max_espaces': 3,
        'role': 'PROPRIETAIRE',
        'peut_creer': true,
      });

      expect(etat.multiEntreprises, isTrue);
      expect(etat.packMulti, isTrue);
      expect(etat.placesRestantes, 1);
      expect(etat.peutCreer, isTrue);
      expect(etat.raison, isNull);
      expect(etat.actif?.nom, 'Hôtel Royal');
      expect(etat.actif?.type, TypeEspace.hotel);
    });

    test('collaborateur : création réservée au propriétaire', () {
      final EtatEspaces etat = EtatEspaces.fromMap(<String, dynamic>{
        'espaces': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'p', 'nom': 'Boutique', 'est_actif': true},
        ],
        'actif_id': 'p',
        'max_espaces': 3,
        'role': 'VENDEUR',
        'peut_creer': false,
        'raison': 'role',
      });

      expect(etat.peutCreer, isFalse);
      expect(etat.raison, RaisonBlocageCreation.role);
      expect(etat.raison!.message, contains('propriétaire'));
    });

    test('compte sans entreprise', () {
      final EtatEspaces etat = EtatEspaces.fromMap(<String, dynamic>{
        'espaces': <dynamic>[],
        'actif_id': null,
        'max_espaces': 1,
        'peut_creer': false,
        'raison': 'aucune_entreprise',
      });

      expect(etat.espaces, isEmpty);
      expect(etat.actif, isNull);
      expect(etat.multiEntreprises, isFalse);
      expect(etat.raison, RaisonBlocageCreation.aucuneEntreprise);
    });

    test('avecActif bascule localement sans rappeler le serveur', () {
      final EtatEspaces etat = EtatEspaces.fromMap(<String, dynamic>{
        'espaces': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'nom': 'A', 'est_actif': true},
          <String, dynamic>{'id': 'b', 'nom': 'B', 'est_actif': false},
        ],
        'actif_id': 'a',
        'max_espaces': 3,
      });

      final EtatEspaces bascule = etat.avecActif('b');

      expect(bascule.actifId, 'b');
      expect(bascule.actif?.id, 'b');
      expect(bascule.espaces.firstWhere((Espace e) => e.id == 'a').estActif,
          isFalse);
      expect(bascule.maxEspaces, 3);
    });

    test('max_espaces manquant → pack standard (1)', () {
      final EtatEspaces etat =
          EtatEspaces.fromMap(<String, dynamic>{'espaces': <dynamic>[]});

      expect(etat.maxEspaces, 1);
      expect(etat.packMulti, isFalse);
    });
  });

  // =========================================================================
  // 4. GRILLE TARIFAIRE ÉTENDUE (max_espaces)
  // =========================================================================

  group('GroupeTarifaire.maxEspaces', () {
    test('parsing : valeur explicite et défaut 1', () {
      final GroupeTarifaire pack =
          GroupeTarifaire.fromMap(<String, dynamic>{
        'id': 'g-1',
        'nom': 'Pack Avancé',
        'max_espaces': 3,
      });
      final GroupeTarifaire standard =
          GroupeTarifaire.fromMap(<String, dynamic>{
        'id': 'g-2',
        'nom': 'Standard',
      });

      expect(pack.maxEspaces, 3);
      expect(pack.packMulti, isTrue);
      expect(standard.maxEspaces, 1);
      expect(standard.packMulti, isFalse);
    });

    test('valeur invalide ramenée à 1 (jamais 0)', () {
      final GroupeTarifaire groupe =
          GroupeTarifaire.fromMap(<String, dynamic>{
        'id': 'g-3',
        'nom': 'Cassé',
        'max_espaces': 0,
      });

      expect(groupe.maxEspaces, 1);
    });

    test('toMap et copyWith transmettent la valeur', () {
      const GroupeTarifaire groupe = GroupeTarifaire(
        id: 'g-4',
        nom: 'Pack',
        maxEspaces: 5,
      );

      expect(groupe.toMap()['max_espaces'], 5);
      expect(groupe.copyWith(maxEspaces: 10).maxEspaces, 10);
      expect(groupe.copyWith().maxEspaces, 5);
    });
  });
}
