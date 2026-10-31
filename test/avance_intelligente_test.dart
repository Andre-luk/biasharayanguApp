// test/avance_intelligente_test.dart
//
// PHASE 11 — L'AVANCE INTELLIGENTE.
//
// La question du client : « je verse 5 000 maintenant, ça me donne quoi ? »
// La règle : prix d'une journée = prix du mois / 30.
//   30 000 / mois → 1 000 / jour → 5 000 = 5 jours.
//
// Ce calcul tourne EN LOCAL (aucun réseau) : il doit donc être juste même
// quand l'application est hors ligne.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/etat_installation.dart';

void main() {
  group('SimulationAvance.calculer', () {
    test('5 000 sur un mois à 30 000 donnent 5 jours', () {
      final SimulationAvance sim = SimulationAvance.calculer(
        montant: 5000,
        resteAPayer: 30000,
        prixCycle: 30000,
        maintenant: DateTime(2026, 1, 1),
      );

      expect(sim.prixJour, 1000);
      expect(sim.joursObtenus, 5);
      expect(sim.cycleComplet, isFalse);
      expect(sim.dateFinEstimee, DateTime(2026, 1, 6));
      expect(sim.libelle, contains('5 jour(s)'));
    });

    test('payer la totalité solde le mois entier (30 jours)', () {
      final SimulationAvance sim = SimulationAvance.calculer(
        montant: 30000,
        resteAPayer: 30000,
        prixCycle: 30000,
        maintenant: DateTime(2026, 1, 1),
      );

      expect(sim.cycleComplet, isTrue);
      expect(sim.joursObtenus, 30);
      expect(sim.dateFinEstimee, DateTime(2026, 1, 31));
      expect(sim.libelle, contains('Mois complet'));
    });

    test('le prix du jour se lit sur le prix du cycle, pas sur le reste', () {
      // 10 000 déjà versés sur 30 000 : il reste 20 000 à payer, mais une
      // avance de 5 000 vaut toujours 5 jours (1 000 / jour).
      final SimulationAvance sim = SimulationAvance.calculer(
        montant: 5000,
        resteAPayer: 20000,
        prixCycle: 30000,
      );

      expect(sim.prixJour, 1000);
      expect(sim.joursObtenus, 5);
      expect(sim.resteAPayer, 20000);
    });

    test('un montant inférieur à une journée est signalé, jamais bloquant', () {
      final SimulationAvance sim = SimulationAvance.calculer(
        montant: 500,
        resteAPayer: 30000,
        prixCycle: 30000,
      );

      expect(sim.joursObtenus, 0);
      expect(sim.insuffisant, isTrue);
      expect(sim.libelle, contains('inférieur'));
    });

    test('aucun montant saisi : on invite à saisir, sans planter', () {
      final SimulationAvance sim = SimulationAvance.calculer(
        montant: 0,
        resteAPayer: 10000,
        prixCycle: 10000,
      );

      expect(sim.exploitable, isFalse);
      expect(sim.libelle, contains('Saisissez un montant'));
    });

    test('prix du cycle inconnu (0) : repli sur le reste à payer', () {
      final SimulationAvance sim = SimulationAvance.calculer(
        montant: 2000,
        resteAPayer: 10000,
        prixCycle: 0,
      );

      expect(sim.prixJour, closeTo(333.33, 0.01));
      expect(sim.joursObtenus, 6);
    });

    test('le barème distribution (50 000 / 20 000) suit la même règle', () {
      final SimulationAvance sim = SimulationAvance.calculer(
        montant: 5000,
        resteAPayer: 20000,
        prixCycle: 20000,
      );

      expect(sim.prixJour, closeTo(666.67, 0.01));
      expect(sim.joursObtenus, 7);
    });

    test('les jours ne dépassent jamais 30', () {
      final SimulationAvance sim = SimulationAvance.calculer(
        montant: 100000,
        resteAPayer: 100000,
        prixCycle: 100000,
      );

      expect(sim.joursObtenus, 30);
    });
  });

  group('SimulationAvance.depuisJson', () {
    test('lit la réponse de rpc_abonnement_simulation_avance', () {
      final SimulationAvance sim = SimulationAvance.depuisJson(
        <String, dynamic>{
          'montant_saisi': 5000,
          'reste_a_payer': 30000,
          'prix_cycle': 30000,
          'prix_jour': 1000,
          'jours_obtenus': 5,
          'cycle_complet': false,
          'devise': 'CDF',
          'date_fin_estimee': '2026-02-06T10:00:00+00:00',
        },
      );

      expect(sim.joursObtenus, 5);
      expect(sim.prixJour, 1000);
      expect(sim.devise, 'CDF');
      expect(sim.dateFinEstimee, isNotNull);
      expect(sim.exploitable, isTrue);
    });

    test('tolère une réponse incomplète sans lever', () {
      final SimulationAvance sim =
          SimulationAvance.depuisJson(<String, dynamic>{});

      expect(sim.joursObtenus, 0);
      expect(sim.montantSaisi, 0);
      expect(sim.exploitable, isFalse);
    });
  });
}
