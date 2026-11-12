// test/scope_donnees_test.dart
//
// 🧩 MODULE 15 — CLOISONNEMENT DES DONNÉES PAR BOUTIQUE.
//
// Ce que l'on protège ici :
//   • un compte à UNE boutique ne doit rien changer (l'espace actif est
//     l'espace par défaut, qui porte déjà l'UUID du patron) ;
//   • après une bascule, les lectures/écritures doivent viser la NOUVELLE
//     boutique — donc un identifiant différent ;
//   • la déconnexion ne doit jamais laisser fuiter l'espace du compte
//     précédent.
//
// Aucun accès réseau : `ScopeDonnees` est un simple porteur d'état.
//
//     flutter test test/scope_donnees_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/espace.dart';
import 'package:biashara_yangu/services/scope_donnees.dart';

void main() {
  setUp(ScopeDonnees.reinitialiser);
  tearDown(ScopeDonnees.reinitialiser);

  group('ScopeDonnees — valeur de travail', () {
    test('aucun espace chargé : comportement historique (null)', () {
      expect(ScopeDonnees.espaceActif, isNull);
      expect(ScopeDonnees.estDefini, isFalse);
    });

    test('un identifiant vide ne compte pas comme un espace', () {
      ScopeDonnees.definirEspaceActif('   ');
      expect(ScopeDonnees.espaceActif, isNull);
      expect(ScopeDonnees.estDefini, isFalse);
    });

    test('la bascule remplace la valeur précédente', () {
      const String boutique1 = '11111111-1111-1111-1111-111111111111';
      const String boutique2 = '22222222-2222-2222-2222-222222222222';

      ScopeDonnees.definirEspaceActif(boutique1);
      expect(ScopeDonnees.espaceActif, boutique1);

      ScopeDonnees.definirEspaceActif(boutique2);
      expect(ScopeDonnees.espaceActif, boutique2,
          reason: 'Après bascule, les données doivent viser la 2e boutique.');
    });

    test('les espaces sont nettoyés (pas d’espace parasite autour)', () {
      ScopeDonnees.definirEspaceActif('  abc-123  ');
      expect(ScopeDonnees.espaceActif, 'abc-123');
    });

    test('la déconnexion remet tout à zéro', () {
      ScopeDonnees.definirEspaceActif('33333333-3333-3333-3333-333333333333');
      ScopeDonnees.reinitialiser();
      expect(ScopeDonnees.espaceActif, isNull);
      expect(ScopeDonnees.estDefini, isFalse);
    });

    test('définir null équivaut à une remise à zéro', () {
      ScopeDonnees.definirEspaceActif('44444444-4444-4444-4444-444444444444');
      ScopeDonnees.definirEspaceActif(null);
      expect(ScopeDonnees.espaceActif, isNull);
    });
  });

  group('EtatEspaces — la boutique active désigne les données', () {
    test('actifId prime sur l’ordre de la liste', () {
      final EtatEspaces etat = EtatEspaces.fromMap(<String, dynamic>{
        'espaces': <dynamic>[
          <String, dynamic>{
            'id': 'aaaa',
            'nom': 'Portes Ouvertes',
            'type': 'boutique',
            'actif': true,
            'est_actif': true,
          },
          <String, dynamic>{
            'id': 'bbbb',
            'nom': 'Deuxième boutique',
            'type': 'boutique',
            'actif': true,
            'est_actif': false,
          },
        ],
        'actif_id': 'bbbb',
        'max_espaces': 3,
      });

      expect(etat.actif?.id, 'bbbb');
      expect(etat.multiEntreprises, isTrue);
      expect(etat.placesRestantes, 1); // 3 autorisées, 2 utilisées
    });

    test('mono-boutique : l’espace actif est celui du patron', () {
      final EtatEspaces etat = EtatEspaces.fromMap(<String, dynamic>{
        'espaces': <dynamic>[
          <String, dynamic>{
            'id': 'patron-uuid',
            'nom': 'Portes Ouvertes',
            'type': 'boutique',
            'actif': true,
            'est_actif': true,
          },
        ],
        'actif_id': 'patron-uuid',
        'max_espaces': 1,
      });

      expect(etat.multiEntreprises, isFalse);

      // C'est exactement ce que fait EspaceService après chargement : la
      // valeur publiée est l'UUID du patron, donc identique à l'historique.
      ScopeDonnees.definirEspaceActif(etat.actifId);
      expect(ScopeDonnees.espaceActif, 'patron-uuid');
    });
  });

  // ---------------------------------------------------------------------------
  // 🩺 0157 — LA PORTÉE DES DONNÉES N'EST PAS L'IDENTITÉ DU PROPRIÉTAIRE.
  // ---------------------------------------------------------------------------
  group('ScopeDonnees — propriétaire effectif (serveur)', () {
    const String espace = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    const String patron = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

    test('sans valeur serveur, on écrit dans l’espace choisi', () {
      ScopeDonnees.definirEspaceActif(espace);
      expect(ScopeDonnees.proprietaireEffectif, isNull);
      expect(ScopeDonnees.proprioPourEcriture, espace);
    });

    test('la valeur du serveur prime sur l’espace choisi', () {
      ScopeDonnees.definirEspaceActif(espace);
      ScopeDonnees.definirProprietaireEffectif(patron);

      expect(ScopeDonnees.proprioPourEcriture, patron,
          reason: 'La RLS compare owner_id à mon_proprietaire() : c’est cette '
              'valeur qui doit servir, sinon les lignes sont invisibles.');
    });

    test('changer d’espace périme la valeur serveur', () {
      ScopeDonnees.definirEspaceActif(espace);
      ScopeDonnees.definirProprietaireEffectif(patron);

      ScopeDonnees.definirEspaceActif('cccccccc-cccc-cccc-cccc-cccccccccccc');
      expect(ScopeDonnees.proprietaireEffectif, isNull);
      expect(ScopeDonnees.proprioPourEcriture,
          'cccccccc-cccc-cccc-cccc-cccccccccccc');
    });

    test('la déconnexion efface les deux valeurs', () {
      ScopeDonnees.definirEspaceActif(espace);
      ScopeDonnees.definirProprietaireEffectif(patron);
      ScopeDonnees.reinitialiser();

      expect(ScopeDonnees.espaceActif, isNull);
      expect(ScopeDonnees.proprietaireEffectif, isNull);
      expect(ScopeDonnees.proprioPourEcriture, isNull);
    });
  });
}
