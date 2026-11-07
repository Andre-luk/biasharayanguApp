// test/finance_abonnements_test.dart
//
// MODULE 27 — tableau de bord Finance / Super Admin : lecture des réponses
// serveur (facturé / encaissé / dû), dossier par entreprise et traçabilité
// Mobile Money. Aucun chiffre n'est recalculé côté application : ces tests
// vérifient que l'écran affiche EXACTEMENT ce que le serveur renvoie.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/services/finance_abonnements_service.dart';

void main() {
  group('ResumeFinance', () {
    test('lit les totaux facturé / encaissé / dû', () {
      final ResumeFinance r = ResumeFinance.fromMap(<String, dynamic>{
        'debut': '2026-10-01',
        'fin': '2026-10-31',
        'entreprises_total': 12,
        'abonnements_actifs': 8,
        'abonnements_expires': 2,
        'abonnements_en_attente': 1,
        'abonnements_partiels': 1,
        'montant_facture': 480000,
        'montant_encaisse_cumule': 360000,
        'solde_a_recouvrer': 120000,
        'supplements_collaborateurs': 25000,
        'paiements_periode': 9,
        'encaisse_periode': 180000,
      });

      expect(r.entreprisesTotal, 12);
      expect(r.abonnementsActifs, 8);
      expect(r.abonnementsExpires, 2);
      expect(r.montantFacture, 480000);
      expect(r.montantEncaisseCumule, 360000);
      expect(r.soldeARecouvrer, 120000);
      expect(r.supplementsCollaborateurs, 25000);
      expect(r.paiementsPeriode, 9);
      expect(r.encaissePeriode, 180000);
      expect(r.estVide, isFalse);
    });

    test('taux de recouvrement : 75 % pour 360 000 sur 480 000', () {
      const ResumeFinance r = ResumeFinance(
        montantFacture: 480000,
        montantEncaisseCumule: 360000,
      );
      expect(r.tauxRecouvrement, closeTo(75, 0.001));
    });

    test('taux de recouvrement borné et sans division par zéro', () {
      const ResumeFinance vide = ResumeFinance();
      expect(vide.tauxRecouvrement, 0);

      const ResumeFinance trop = ResumeFinance(
        montantFacture: 1000,
        montantEncaisseCumule: 1500,
      );
      expect(trop.tauxRecouvrement, 100);
    });

    test('répartition par moyen de paiement et courbe par jour', () {
      final ResumeFinance r = ResumeFinance.fromMap(<String, dynamic>{
        'encaisse_periode': 150000,
        'encaisse_especes': 50000,
        'encaisse_mobile_money': 90000,
        'encaisse_carte': 10000,
        'encaisse_autres': 0,
        'par_jour': <dynamic>[
          <String, dynamic>{'jour': '2026-10-01', 'montant': 50000, 'nb': 2},
          <String, dynamic>{'jour': '2026-10-02', 'montant': 100000, 'nb': 3},
        ],
      });

      expect(r.encaisseMobileMoney, 90000);
      expect(r.encaisseCarte, 10000);
      expect(r.encaisseAutres, 0);
      expect(r.parJour, hasLength(2));
      expect(r.parJour.first.montant, 50000);
      expect(r.parJour.first.nombre, 2);
      expect(r.parJour.first.jour, isNotNull);
    });

    test('tolérance : réponse vide ou nulle', () {
      expect(ResumeFinance.fromMap(<String, dynamic>{}).estVide, isTrue);
      expect(ResumeFinance.fromMap(<String, dynamic>{}).parJour, isEmpty);
      expect(ResumeFinance.vide.montantFacture, 0);
    });
  });

  group('LigneFinanceEntreprise', () {
    test('lit la situation complète d\'une boutique', () {
      final LigneFinanceEntreprise l =
          LigneFinanceEntreprise.fromMap(<String, dynamic>{
        'entreprise_id': 'e-1',
        'nom': 'Boutique Kivu',
        'statut': 'ACTIF',
        'devise': 'CDF',
        'echeance': '2026-11-30T23:59:59Z',
        'jours_restants': 18,
        'montant_facture': 30000,
        'montant_encaisse': 10000,
        'solde_du': 20000,
        'supplement_collaborateurs': 5000,
        'collaborateurs': 2,
        'dernier_paiement': '2026-10-31T10:00:00Z',
        'total_paiements': 3,
        'serdipay_en_attente': 1,
      });

      expect(l.nom, 'Boutique Kivu');
      expect(l.statut, 'ACTIF');
      expect(l.joursRestants, 18);
      expect(l.montantFacture, 30000);
      expect(l.montantEncaisse, 10000);
      expect(l.soldeDu, 20000);
      expect(l.collaborateurs, 2);
      expect(l.totalPaiements, 3);
      expect(l.serdipayEnAttente, 1);
      expect(l.echeance, isNotNull);
      expect(l.dernierPaiement, isNotNull);
      expect(l.enRetard, isTrue);
      expect(l.tauxPaiement, closeTo(33.33, 0.01));
    });

    test('une boutique soldée n\'est pas en retard', () {
      const LigneFinanceEntreprise l = LigneFinanceEntreprise(
        entrepriseId: 'e-2',
        montantFacture: 30000,
        montantEncaisse: 30000,
      );
      expect(l.enRetard, isFalse);
      expect(l.tauxPaiement, 100);
    });

    test('données manquantes : aucun plantage', () {
      final LigneFinanceEntreprise l =
          LigneFinanceEntreprise.fromMap(<String, dynamic>{});
      expect(l.nom, '—');
      expect(l.devise, 'CDF');
      expect(l.joursRestants, isNull);
      expect(l.soldeDu, 0);
      expect(l.enRetard, isFalse);
    });
  });

  group('TransactionSerdipay', () {
    test('lit une transaction payée', () {
      final TransactionSerdipay t =
          TransactionSerdipay.fromMap(<String, dynamic>{
        'id': 's-1',
        'entreprise': 'Boutique Kivu',
        'reference': 'SD-2026-0001',
        'reference_fournisseur': 'MP-99887',
        'montant': 30000,
        'devise': 'CDF',
        'operateur': 'M-Pesa',
        'telephone': '243990000000',
        'nom_payeur': 'Jean Kabila',
        'statut': 'paye',
        'date': '2026-10-31T10:00:00Z',
        'confirme_le': '2026-10-31T10:00:12Z',
        'frais': 500,
        'montant_net': 29500,
        'rapproche': true,
        'rapproche_le': '2026-11-01T09:00:00Z',
      });

      expect(t.estPayee, isTrue);
      expect(t.estEnAttente, isFalse);
      expect(t.libelleStatut, 'Payée');
      expect(t.montant, 30000);
      expect(t.nomPayeur, 'Jean Kabila');
      expect(t.frais, 500);
      expect(t.montantNet, 29500);
      expect(t.rapproche, isTrue);
      expect(t.rapprocheLe, isNotNull);
    });

    test('statuts traduits en français', () {
      TransactionSerdipay avec(String statut) =>
          TransactionSerdipay(id: 'x', statut: statut);

      expect(avec('en_attente').libelleStatut, 'En attente');
      expect(avec('echoue').libelleStatut, 'Échouée');
      expect(avec('annule').libelleStatut, 'Annulée');
      expect(avec('expire').libelleStatut, 'Expirée');
      expect(avec('inconnu').libelleStatut, 'inconnu');
    });

    test('une transaction échouée conserve son motif', () {
      final TransactionSerdipay t =
          TransactionSerdipay.fromMap(<String, dynamic>{
        'id': 's-2',
        'statut': 'echoue',
        'motif_echec': 'Solde insuffisant',
        'montant': 30000,
      });

      expect(t.estEchouee, isTrue);
      expect(t.motifEchec, 'Solde insuffisant');
      expect(t.rapproche, isFalse);
      expect(t.frais, isNull);
      expect(t.montantNet, isNull);
    });

    test('`rapproche` tolère texte et entier', () {
      expect(
        TransactionSerdipay.fromMap(<String, dynamic>{'rapproche': 'true'})
            .rapproche,
        isTrue,
      );
      expect(
        TransactionSerdipay.fromMap(<String, dynamic>{'rapproche': 1})
            .rapproche,
        isTrue,
      );
      expect(
        TransactionSerdipay.fromMap(<String, dynamic>{'rapproche': 0})
            .rapproche,
        isFalse,
      );
    });
  });

  group('FinanceAbonnementsException', () {
    test('toString renvoie le message lisible', () {
      const FinanceAbonnementsException e =
          FinanceAbonnementsException('Droit refusé.');
      expect(e.toString(), 'Droit refusé.');
    });
  });
}
