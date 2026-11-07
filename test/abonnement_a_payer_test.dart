// test/abonnement_a_payer_test.dart
//
// CORRECTIF 112 — « DÉTECTER QUELQU'UN QUI N'A PAS ENCORE PAYÉ ».
//
// Exigence du propriétaire : même un compte en ESSAI de 7 jours doit voir un
// bouton de paiement. Ces tests verrouillent la règle unique [aPayer] et le
// libellé associé, pour qu'aucun écran ne puisse plus afficher « rien à payer »
// à un client qui n'a jamais payé.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/activation.dart';
import 'package:biashara_yangu/models/etat_installation.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';

EtatActivation _etat({
  StatutAbonnement? statut,
  double total = 30000,
  double paye = 0,
  double solde = 0,
  int jours = 7,
  bool dossier = true,
}) {
  final DateTime maintenant = DateTime.now();
  return EtatActivation(
    entrepriseId: dossier ? 'ent-1' : null,
    nom: 'Boutique Test',
    etape: dossier ? EtapeActivation.actif : EtapeActivation.aucune,
    statut: statut,
    montantTotalDu: total,
    montantDejaPaye: paye,
    soldeRestant: solde,
    dateActivation: dossier ? maintenant.subtract(const Duration(days: 1)) : null,
    dateExpiration: dossier ? maintenant.add(Duration(days: jours)) : null,
    joursRestants: dossier ? jours : null,
  );
}

void main() {
  group('Essai de 7 jours jamais payé', () {
    final EtatActivation essai =
        _etat(statut: StatutAbonnement.essai7j, paye: 0, solde: 0, jours: 7);

    test('est reconnu comme jamais payé', () {
      expect(essai.jamaisPaye, isTrue);
      expect(essai.enEssai, isTrue);
      expect(essai.abonnementEchu, isFalse);
    });

    test('propose un paiement malgré un solde nul', () {
      expect(essai.aPayer, isTrue);
      expect(essai.libellePaiement, 'Payer mon abonnement');
      expect(essai.explicationPaiement, contains('essai'));
      expect(essai.explicationPaiement, contains('7 jours'));
    });
  });

  group('Essai partiellement payé', () {
    final EtatActivation partiel = _etat(
      statut: StatutAbonnement.essai7j,
      paye: 10000,
      solde: 20000,
    );

    test('le solde prend la priorité', () {
      expect(partiel.jamaisPaye, isFalse);
      expect(partiel.aPayer, isTrue);
      expect(partiel.libellePaiement, 'Payer le solde de mon abonnement');
    });
  });

  group('Abonnement échu', () {
    final EtatActivation echu = _etat(
      statut: StatutAbonnement.expire,
      paye: 30000,
      solde: 0,
      jours: -2,
    );

    test('demande un renouvellement', () {
      expect(echu.abonnementEchu, isTrue);
      expect(echu.estSolde, isTrue);
      expect(echu.doitRenouveler, isTrue);
      expect(echu.aPayer, isTrue);
      expect(echu.libellePaiement, 'Renouveler mon abonnement');
    });

    test('un solde impayé reste prioritaire sur le renouvellement', () {
      final EtatActivation echuAvecSolde =
          _etat(statut: StatutAbonnement.expire, paye: 0, solde: 30000);
      expect(echuAvecSolde.doitRenouveler, isFalse);
      expect(echuAvecSolde.aPayer, isTrue);
      expect(
        echuAvecSolde.libellePaiement,
        'Payer le solde de mon abonnement',
      );
    });
  });

  group('Compte à jour', () {
    final EtatActivation aJour = _etat(
      statut: StatutAbonnement.actif,
      paye: 30000,
      solde: 0,
      jours: 20,
    );

    test('n\'est pas une alerte mais reste payable par anticipation', () {
      expect(aJour.jamaisPaye, isFalse);
      expect(aJour.enEssai, isFalse);
      expect(aJour.aPayer, isFalse);
      expect(aJour.peutPayerAnticipe, isTrue);
      expect(aJour.libellePaiement, 'Payer mon prochain mois');
      expect(aJour.explicationPaiement, contains('anticipation'));
    });
  });

  group('Aucun dossier', () {
    test('ne propose aucun paiement', () {
      final EtatActivation vide =
          _etat(statut: null, dossier: false, jours: 0);
      expect(vide.aUnDossier, isFalse);
      expect(vide.aPayer, isFalse);
    });
  });

  group('AvanceCycle — ouverture d\'un cycle anticipé', () {
    test('lit la réponse du serveur', () {
      final AvanceCycle avance = AvanceCycle.depuisJson(<String, dynamic>{
        'ok': true,
        'ouvert': true,
        'motif': 'CYCLE_ANTICIPE',
        'montant': 32500,
        'base': 30000,
        'supplement_collaborateurs': 2500,
        'jours_restants': 5,
        'devise': 'CDF',
      });

      expect(avance.ouvert, isTrue);
      expect(avance.anticipe, isTrue);
      expect(avance.aPayer, isTrue);
      expect(avance.montant, 32500);
      expect(avance.base + avance.supplementCollaborateurs, avance.montant);
      expect(avance.joursRestants, 5);
    });

    test('un solde déjà dû ne rouvre rien', () {
      final AvanceCycle deja = AvanceCycle.depuisJson(<String, dynamic>{
        'ouvert': false,
        'motif': 'DEJA_DU',
        'montant': 12000,
      });

      expect(deja.ouvert, isFalse);
      expect(deja.anticipe, isFalse);
      expect(deja.aPayer, isTrue);
    });

    test('réponse vide → rien à payer', () {
      expect(AvanceCycle.aucune.aPayer, isFalse);
      expect(AvanceCycle.depuisJson(<String, dynamic>{}).aPayer, isFalse);
    });
  });
}
