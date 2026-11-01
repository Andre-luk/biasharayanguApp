// test/paiement_abonnement_coherence_test.dart
//
// 🔴 INCOHÉRENCE SIGNALÉE PAR LE PATRON (31/10/2026)
//
//   « Je sélectionne une entreprise pour enregistrer un abonnement :
//     statut EXPIRE, montant total dû 15 000, paiement 15 000 —
//     le message : le montant dépasse le solde restant. »
//
// CAUSE : l'écran proposait le montant du cycle PRÉCÉDENT, alors que le moteur
// ouvre un NOUVEAU cycle au prix mensuel actuel dès que l'abonnement est échu.
// Payer 15 000 quand le nouveau cycle vaut 10 000 est refusé — à juste titre.
//
// La règle vit désormais dans `AbonnementService.montantAEncaisser` : ces
// tests la figent.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';

SoldeAbonnement _solde({
  required double total,
  required double paye,
  required StatutAbonnement statut,
}) {
  return SoldeAbonnement(
    total: total,
    paye: paye,
    solde: total - paye > 0 ? total - paye : 0,
    joursRestants: 0,
    statut: statut,
  );
}

void main() {
  group('AbonnementService.montantAEncaisser', () {
    test('abonnement ÉCHU et soldé : propose le prix du NOUVEAU cycle', () {
      // Le cas exact du rapport : 15 000 affiché était le cycle précédent.
      final SoldeAbonnement solde = _solde(
        total: 15000,
        paye: 15000,
        statut: StatutAbonnement.expire,
      );

      expect(
        AbonnementService.montantAEncaisser(solde: solde, prixCycle: 10000),
        10000,
      );
      expect(AbonnementService.ouvreNouveauCycle(solde), isTrue);
    });

    test('abonnement ÉCHU avec un arriéré : le nouveau cycle prime aussi', () {
      // 5 000 restent impayés sur l'ancien cycle (15 000), mais le moteur
      // rouvre un cycle à 10 000 : encaisser 5 000 laisserait le compte bloqué.
      final SoldeAbonnement solde = _solde(
        total: 15000,
        paye: 10000,
        statut: StatutAbonnement.expire,
      );

      expect(
        AbonnementService.montantAEncaisser(solde: solde, prixCycle: 10000),
        10000,
      );
    });

    test('abonnement en cours : propose le solde restant', () {
      final SoldeAbonnement solde = _solde(
        total: 30000,
        paye: 22000,
        statut: StatutAbonnement.actif,
      );

      expect(
        AbonnementService.montantAEncaisser(solde: solde, prixCycle: 30000),
        8000,
      );
      expect(AbonnementService.ouvreNouveauCycle(solde), isFalse);
    });

    test('cycle soldé mais abonnement encore actif : nouveau cycle', () {
      final SoldeAbonnement solde = _solde(
        total: 30000,
        paye: 30000,
        statut: StatutAbonnement.actif,
      );

      expect(
        AbonnementService.montantAEncaisser(solde: solde, prixCycle: 30000),
        30000,
      );
      expect(AbonnementService.ouvreNouveauCycle(solde), isTrue);
    });

    test('prix du cycle inconnu (0) : repli sur le montant connu', () {
      final SoldeAbonnement solde = _solde(
        total: 15000,
        paye: 15000,
        statut: StatutAbonnement.expire,
      );

      expect(
        AbonnementService.montantAEncaisser(solde: solde, prixCycle: 0),
        15000,
      );
    });

    test('barème distribution : 20 000 le mois, jamais l\'installation', () {
      final SoldeAbonnement solde = _solde(
        total: 50000,
        paye: 50000,
        statut: StatutAbonnement.expire,
      );

      expect(
        AbonnementService.montantAEncaisser(solde: solde, prixCycle: 20000),
        20000,
      );
    });
  });
}
