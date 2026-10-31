// test/abonnement_autonomie_test.dart
//
// PHASE 7 — LE CLIENT PAIE SEUL.
//
// Trois règles vérifiées ici, sans base de données :
//   1. on ne demande un renouvellement QUE si l'abonnement est échu et déjà
//      soldé (sinon on facturerait deux fois le même mois) ;
//   2. une avance est un montant PARTIEL : au-delà du solde, on paie tout ;
//   3. le type d'activité se lit sur l'entreprise et reste fail-open.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/activation.dart';
import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/etat_installation.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/models/type_activite.dart';

void main() {
  final DateTime hier = DateTime.now().subtract(const Duration(days: 3));
  final DateTime demain = DateTime.now().add(const Duration(days: 10));

  group('EtatActivation — quand renouveler', () {
    test('abonnement échu et soldé : le client peut ouvrir le mois suivant', () {
      final EtatActivation etat = EtatActivation(
        etape: EtapeActivation.actif,
        statut: StatutAbonnement.expire,
        dateExpiration: hier,
        montantTotalDu: 15000,
        montantDejaPaye: 15000,
        soldeRestant: 0,
      );

      expect(etat.abonnementEchu, isTrue);
      expect(etat.estSolde, isTrue);
      expect(etat.doitRenouveler, isTrue);
    });

    test('abonnement encore valable : aucun nouveau cycle', () {
      final EtatActivation etat = EtatActivation(
        etape: EtapeActivation.actif,
        statut: StatutAbonnement.actif,
        dateExpiration: demain,
        montantTotalDu: 15000,
        montantDejaPaye: 15000,
        soldeRestant: 0,
      );

      expect(etat.abonnementEchu, isFalse);
      expect(etat.doitRenouveler, isFalse);
    });

    test('un solde restant suffit : on paie, on ne renouvelle pas encore', () {
      final EtatActivation etat = EtatActivation(
        etape: EtapeActivation.restreint,
        statut: StatutAbonnement.expire,
        dateExpiration: hier,
        montantTotalDu: 30000,
        montantDejaPaye: 25000,
        soldeRestant: 5000,
      );

      expect(etat.abonnementEchu, isTrue);
      expect(etat.doitRenouveler, isFalse,
          reason: 'le complément de 5 000 doit être payé avant tout nouveau mois');
    });

    test('date dépassée sans statut EXPIRE : reste échu', () {
      final EtatActivation etat = EtatActivation(
        etape: EtapeActivation.actif,
        statut: StatutAbonnement.actif,
        dateExpiration: hier,
        soldeRestant: 0,
      );

      expect(etat.abonnementEchu, isTrue);
    });

    test('sans date d\'échéance, on ne suppose rien', () {
      const EtatActivation etat = EtatActivation(
        etape: EtapeActivation.actif,
        statut: StatutAbonnement.actif,
      );

      expect(etat.abonnementEchu, isFalse);
      expect(etat.doitRenouveler, isFalse);
    });
  });

  group('PreparationRenouvellement', () {
    test('un cycle vient d\'être ouvert', () {
      final PreparationRenouvellement p =
          PreparationRenouvellement.depuisJson(<String, dynamic>{
        'ok': true,
        'cycle_ouvert': true,
        'motif': 'CYCLE_OUVERT',
        'solde_restant': 15000,
        'prix_mensuel': 15000,
        'devise': 'CDF',
      });

      expect(p.cycleOuvert, isTrue);
      expect(p.aPayer, isTrue);
      expect(p.soldeRestant, 15000);
    });

    test('abonnement encore en cours : rien à payer', () {
      final PreparationRenouvellement p =
          PreparationRenouvellement.depuisJson(<String, dynamic>{
        'cycle_ouvert': false,
        'motif': 'CYCLE_EN_COURS',
        'solde_restant': 0,
      });

      expect(p.cycleOuvert, isFalse);
      expect(p.aPayer, isFalse);
      expect(p.motif, 'CYCLE_EN_COURS');
    });

    test('le PREMIER cycle payant est l\'installation', () {
      final PreparationRenouvellement p =
          PreparationRenouvellement.depuisJson(<String, dynamic>{
        'cycle_ouvert': true,
        'motif': 'CYCLE_OUVERT',
        'type_cycle': 'installation',
        'solde_restant': 50000,
        'devise': 'CDF',
      });

      expect(p.estInstallation, isTrue);
      expect(p.libelleCycle, contains('Installation'));
      expect(p.soldeRestant, 50000);
    });

    test('ensuite, c\'est l\'abonnement du mois', () {
      final PreparationRenouvellement p =
          PreparationRenouvellement.depuisJson(<String, dynamic>{
        'cycle_ouvert': true,
        'type_cycle': 'abonnement',
        'solde_restant': 15000,
      });

      expect(p.estInstallation, isFalse);
      expect(p.libelleCycle, 'Abonnement du mois');
    });

    test('sans indication, on suppose le mensuel (jamais l\'installation)', () {
      final PreparationRenouvellement p =
          PreparationRenouvellement.depuisJson(<String, dynamic>{
        'cycle_ouvert': true,
        'solde_restant': 15000,
      });

      expect(p.typeCycle, 'abonnement');
      expect(p.estInstallation, isFalse);
    });

    test('réponse vide : aucune préparation inventée', () {
      expect(PreparationRenouvellement.aucune.aPayer, isFalse);
      expect(PreparationRenouvellement.aucune.soldeRestant, 0);
    });
  });

  group('Type d\'activité de l\'entreprise', () {
    test('lit « distribution » depuis la base', () {
      final Entreprise e = Entreprise.fromMap(<String, dynamic>{
        'id': 'e1',
        'nom': 'Perle Distribution',
        'type_activite': 'distribution',
      });

      expect(e.typeActivite, TypeActivite.distribution);
    });

    test('sans valeur (entreprise historique), le type reste inconnu', () {
      final Entreprise e = Entreprise.fromMap(<String, dynamic>{
        'id': 'e2',
        'nom': 'Boutique historique',
      });

      expect(e.typeActivite, isNull);
    });

    test('une valeur inattendue n\'enferme pas l\'entreprise', () {
      final Entreprise e = Entreprise.fromMap(<String, dynamic>{
        'id': 'e3',
        'nom': 'X',
        'type_activite': 'zzz',
      });

      expect(e.typeActivite, isNull);
    });
  });
}
