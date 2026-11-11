// test/equipe_entreprise_test.dart
//
// 🧩 MODULE 15 — ÉQUIPE ET AFFECTATION À UNE BOUTIQUE.
//
// Ce que l'on protège :
//   • la lecture d'un collaborateur renvoyé par `rpc_collaborateurs_lister`
//     (rôle, état, boutique) sans jamais lever d'exception sur un champ absent ;
//   • l'affichage : nom complet, initiales, libellé du rôle ;
//   • la boutique : absente = « boutique principale » (comportement historique).
//
// Aucun accès réseau.
//
//     flutter test test/equipe_entreprise_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/collaborateur_entreprise.dart';

void main() {
  group('CollaborateurEntreprise — lecture serveur', () {
    test('lit tous les champs, boutique comprise', () {
      final CollaborateurEntreprise c = CollaborateurEntreprise.depuisJson(
        <String, dynamic>{
          'id': 'u-1',
          'nom': 'Kabasele',
          'prenom': 'Rachel',
          'email': 'rachel@biashara.com',
          'telephone': '+243810000000',
          'role': 'VENDEUR',
          'actif': true,
          'espace_id': 'espace-2',
          'espace_nom': 'Deuxième boutique',
        },
      );

      expect(c.nomComplet, 'Rachel Kabasele');
      expect(c.initiales, 'RK');
      expect(c.role, 'VENDEUR');
      expect(c.espaceId, 'espace-2');
      expect(c.espaceNom, 'Deuxième boutique');
      expect(c.actif, isTrue);
    });

    test('boutique absente = boutique principale (aucune erreur)', () {
      final CollaborateurEntreprise c = CollaborateurEntreprise.depuisJson(
        <String, dynamic>{
          'id': 'u-2',
          'nom': 'Abigaïl',
          'email': 'abi@biashara.com',
          'role': 'vendEur',
          'actif': 1,
          'espace_id': null,
          'espace_nom': null,
        },
      );

      expect(c.espaceId, isNull);
      expect(c.espaceNom, '');
      expect(c.role, 'VENDEUR', reason: 'Le rôle est normalisé en majuscules.');
      expect(c.actif, isTrue);
    });

    test('un compte désactivé est signalé', () {
      final CollaborateurEntreprise c = CollaborateurEntreprise.depuisJson(
        <String, dynamic>{
          'id': 'u-3',
          'nom': 'Martin',
          'email': 'martin@gmail.com',
          'role': 'MAGASINIER',
          'actif': false,
        },
      );

      expect(c.actif, isFalse);
      expect(c.libelleRoleCourt, 'Magasinier / stock');
    });

    test('sans nom, l’e-mail sert de libellé (jamais de case vide)', () {
      final CollaborateurEntreprise c = CollaborateurEntreprise.depuisJson(
        <String, dynamic>{'id': 'u-4', 'email': 'inconnu@biashara.com'},
      );

      expect(c.nomComplet, 'inconnu@biashara.com');
      expect(c.initiales, '?');
    });
  });

  group('CollaborateurEntreprise — libellés de rôle', () {
    test('les quatre rôles d’entreprise sont traduits', () {
      expect(
        CollaborateurEntreprise.libelleRole('PROPRIETAIRE'),
        'Responsable (tous les droits)',
      );
      expect(
          CollaborateurEntreprise.libelleRole('VENDEUR'), 'Vendeur / caissier');
      expect(
        CollaborateurEntreprise.libelleRole('MAGASINIER'),
        'Magasinier / stock',
      );
      expect(
        CollaborateurEntreprise.libelleRole('COMPTABLE_ENTREPRISE'),
        'Comptable',
      );
    });

    test('un rôle inconnu reste lisible (pas de « null » à l’écran)', () {
      expect(CollaborateurEntreprise.libelleRole('TESTEUR'), 'TESTEUR');
      expect(CollaborateurEntreprise.libelleRole(''), 'Collaborateur');
    });
  });
}
