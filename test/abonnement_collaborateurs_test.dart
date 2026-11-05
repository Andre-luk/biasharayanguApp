// test/abonnement_collaborateurs_test.dart
//
// MODULE 26 — abonnement au nombre de collaborateurs actifs.
//
// Règle : abonnement de base + (collaborateurs ACTIFS × 2 500 FC).
// Ces tests vérifient l'arithmétique et la lecture du détail renvoyé par le
// serveur ; le comptage lui-même (propriétaire exclu, comptes désactivés
// ignorés, doublons exclus) est fait en base par
// `abonnement_collaborateurs_actifs(uuid)` — migration 0109.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/abonnement_collaborateurs.dart';

void main() {
  group('Supplément par collaborateur', () {
    test('trois collaborateurs actifs sur une base de 30 000', () {
      expect(
        AbonnementCollaborateurs.calculerSupplement(
          nbCollaborateurs: 3,
          prixUnitaire: 2500,
        ),
        7500,
      );
      expect(
        AbonnementCollaborateurs.calculerTotal(
          base: 30000,
          nbCollaborateurs: 3,
          prixUnitaire: 2500,
        ),
        37500,
      );
    });

    test('six collaborateurs actifs sur une base de 30 000', () {
      expect(
        AbonnementCollaborateurs.calculerSupplement(
          nbCollaborateurs: 6,
          prixUnitaire: 2500,
        ),
        15000,
      );
      expect(
        AbonnementCollaborateurs.calculerTotal(
          base: 30000,
          nbCollaborateurs: 6,
          prixUnitaire: 2500,
        ),
        45000,
      );
    });

    test('aucun collaborateur : seul l\'abonnement de base est dû', () {
      expect(
        AbonnementCollaborateurs.calculerTotal(
          base: 30000,
          nbCollaborateurs: 0,
          prixUnitaire: 2500,
        ),
        30000,
      );
    });

    test('désactiver un collaborateur fait baisser le supplément', () {
      final double avant = AbonnementCollaborateurs.calculerSupplement(
        nbCollaborateurs: 3,
        prixUnitaire: 2500,
      );
      final double apres = AbonnementCollaborateurs.calculerSupplement(
        nbCollaborateurs: 2,
        prixUnitaire: 2500,
      );

      expect(avant, 7500);
      expect(apres, 5000);
      expect(
        AbonnementCollaborateurs.calculerTotal(
          base: 30000,
          nbCollaborateurs: 2,
          prixUnitaire: 2500,
        ),
        35000,
      );
    });

    test('sans prix de base, aucun total n\'est inventé', () {
      expect(
        AbonnementCollaborateurs.calculerTotal(
          base: 0,
          nbCollaborateurs: 6,
          prixUnitaire: 2500,
        ),
        0,
      );
    });

    test('le prix unitaire reste configurable', () {
      expect(
        AbonnementCollaborateurs.calculerSupplement(
          nbCollaborateurs: 4,
          prixUnitaire: 1000,
        ),
        4000,
      );
    });
  });

  group('Lecture du détail serveur', () {
    test('les montants du serveur sont repris tels quels', () {
      final AbonnementCollaborateurs detail =
          AbonnementCollaborateurs.fromMap(<String, dynamic>{
        'base': 30000,
        'nb_collaborateurs': 3,
        'prix_unitaire': 2500,
        'supplement': 7500,
        'total_prochain_cycle': 37500,
        'supplement_cycle_en_cours': 7500,
        'deja_paye': 10000,
        'solde_restant': 27500,
        'prorata': false,
        'devise': 'CDF',
      });

      expect(detail.base, 30000);
      expect(detail.nbCollaborateurs, 3);
      expect(detail.prixUnitaire, 2500);
      expect(detail.supplement, 7500);
      expect(detail.totalProchainCycle, 37500);
      expect(detail.soldeRestant, 27500);
      expect(detail.prorata, isFalse);
    });

    test('un champ manquant est recalculé localement', () {
      final AbonnementCollaborateurs detail =
          AbonnementCollaborateurs.fromMap(<String, dynamic>{
        'base': 30000,
        'nb_collaborateurs': 6,
        'prix_unitaire': 2500,
      });

      expect(detail.supplement, 15000);
      expect(detail.totalProchainCycle, 45000);
    });

    test('le prorata est reconnu', () {
      final AbonnementCollaborateurs detail =
          AbonnementCollaborateurs.fromMap(<String, dynamic>{
        'base': 10000,
        'nb_collaborateurs': 1,
        'prix_unitaire': 2500,
        'prorata': true,
      });
      expect(detail.prorata, isTrue);
    });
  });
}
