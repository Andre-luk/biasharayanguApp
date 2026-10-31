// test/installation_forfaits_test.dart
//
// PHASE 2 — « L'installation ne se paie qu'une fois » et « on ne propose pas
// un forfait de distribution à une boutique ».
//
// Ces deux règles sont testées ici sans base de données : elles reposent sur
// des fonctions pures, donc elles restent vraies quel que soit l'écran qui
// les utilise.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/etat_installation.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/models/type_activite.dart';

void main() {
  group('ProchainCycle', () {
    test('reconnaît « abonnement » et « installation »', () {
      expect(ProchainCycle.fromCode('abonnement'), ProchainCycle.abonnement);
      expect(
          ProchainCycle.fromCode('installation'), ProchainCycle.installation);
    });

    test('valeur inconnue ou absente : on demande l\'installation', () {
      // Choix prudent : mieux vaut demander l'installation une fois de trop
      // que d'offrir un cycle gratuit… mais le serveur, lui, tranche sur les
      // faits. Ici on ne fait que décoder.
      expect(ProchainCycle.fromCode(null), ProchainCycle.installation);
      expect(ProchainCycle.fromCode(''), ProchainCycle.installation);
      expect(ProchainCycle.fromCode('mensuel'), ProchainCycle.installation);
    });
  });

  group('EtatInstallation', () {
    test('lit un état « installation déjà réglée »', () {
      final EtatInstallation e = EtatInstallation.depuisJson(<String, dynamic>{
        'entreprise_id': 'e1',
        'devise': 'CDF',
        'prix_installation': 50000,
        'prix_mensuel': 15000,
        'montant_total_du': 15000,
        'montant_deja_paye': 15000,
        'solde_restant': 0,
        'statut': 'ACTIF',
        'installation_deja_reglee': true,
        'installation_reglee_montant': 50000,
        'cycles_soldes': 3,
        'prochain_cycle': 'abonnement',
        'prochain_montant': 15000,
      });

      expect(e.installationDejaReglee, isTrue);
      expect(e.cyclesSoldes, 3);
      expect(e.prochainCycle, ProchainCycle.abonnement);
      expect(e.prochainMontant, 15000);
      expect(e.complementAttendu, isFalse);
      expect(e.libelleInstallation, contains('ne sera pas refacturée'));
    });

    test('lit un état « installation à régler »', () {
      final EtatInstallation e = EtatInstallation.depuisJson(<String, dynamic>{
        'entreprise_id': 'e2',
        'prix_installation': 50000,
        'prochain_cycle': 'installation',
        'prochain_montant': 50000,
        'statut': 'ESSAI',
      });

      expect(e.installationDejaReglee, isFalse);
      expect(e.prochainCycle, ProchainCycle.installation);
      expect(e.prochainMontant, 50000);
      expect(e.libelleInstallation, contains('une seule fois'));
    });

    test('un complément attendu est signalé', () {
      const EtatInstallation e = EtatInstallation(soldeRestant: 5000);

      expect(e.complementAttendu, isTrue);
    });

    test('un état vide ne prétend rien', () {
      expect(EtatInstallation.inconnu.installationDejaReglee, isFalse);
      expect(EtatInstallation.inconnu.prochainMontant, 0);
      expect(EtatInstallation.inconnu.devise, 'CDF');
      expect(EtatInstallation.inconnu.complementAttendu, isFalse);
    });

    test('le libellé du prochain encaissement est lisible', () {
      const EtatInstallation e = EtatInstallation(
        prochainCycle: ProchainCycle.abonnement,
        prochainMontant: 15000,
      );

      expect(e.libelleProchainEncaissement, 'Abonnement mensuel — 15000 CDF');
    });

    test('un montant nul reste lisible', () {
      const EtatInstallation e = EtatInstallation(
        prochainCycle: ProchainCycle.installation,
        prochainMontant: 0,
      );

      expect(e.libelleProchainEncaissement, 'Installation — 0 CDF');
    });
  });

  group('Forfaits par type d\'activité', () {
    test('un forfait de distribution n\'est pas proposé à une boutique', () {
      final GroupeTarifaire distribution = GroupeTarifaire.fromMap(
        <String, dynamic>{
          'id': 'g1',
          'nom': 'Distribution Pro',
          'type_activite': 'distribution',
        },
      );

      expect(distribution.typeActivite, TypeActivite.distribution);
      expect(distribution.proposableA(TypeActivite.boutique), isFalse);
      expect(distribution.proposableA(TypeActivite.distribution), isTrue);
    });

    test('un forfait commun (type NULL) est proposé à tout le monde', () {
      final GroupeTarifaire commun = GroupeTarifaire.fromMap(
        <String, dynamic>{'id': 'g2', 'nom': 'Standard'},
      );

      expect(commun.typeActivite, isNull);
      expect(commun.proposableA(TypeActivite.boutique), isTrue);
      expect(commun.proposableA(TypeActivite.distribution), isTrue);
    });

    test('une entreprise sans type connu voit tous les forfaits', () {
      final GroupeTarifaire distribution = GroupeTarifaire.fromMap(
        <String, dynamic>{
          'id': 'g3',
          'nom': 'Distribution Pro',
          'type_activite': 'distribution',
        },
      );
      final GroupeTarifaire boutique = GroupeTarifaire.fromMap(
        <String, dynamic>{
          'id': 'g4',
          'nom': 'Boutique',
          'type_activite': 'boutique',
        },
      );

      // Fail-open : ne jamais bloquer une souscription sur une valeur absente.
      expect(distribution.proposableA(null), isTrue);
      expect(boutique.proposableA(null), isTrue);
    });

    test('un type inconnu en base est toléré comme commun', () {
      final GroupeTarifaire bizarre = GroupeTarifaire.fromMap(
        <String, dynamic>{'id': 'g5', 'nom': 'Étrange', 'type_activite': 'zzz'},
      );

      expect(bizarre.typeActivite, isNull);
      expect(bizarre.proposableA(TypeActivite.boutique), isTrue);
    });
  });
}
