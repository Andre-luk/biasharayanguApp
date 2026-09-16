// test/finance_test.dart
//
// Tests unitaires du MODULE 10 — Finance de l'entreprise.
//
// Ces tests ne touchent ni au réseau ni à Supabase : ils vérifient le parsing
// tolérant des réponses des RPC (jsonb), les calculs purs (restant dû,
// ancienneté, écart de clôture, proportions de rapports), la normalisation
// des numéros de téléphone (relances WhatsApp/SMS/appel) et les messages
// d'erreur serveur.
//
//     flutter test test/finance_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/depense_finance.dart';
import 'package:biashara_yangu/models/dette_client.dart';
import 'package:biashara_yangu/models/finance_stats.dart';
import 'package:biashara_yangu/models/mouvement_caisse.dart';
import 'package:biashara_yangu/models/rapport_finance.dart';
import 'package:biashara_yangu/services/dette_service.dart';
import 'package:biashara_yangu/services/finance_service.dart';

void main() {
  // =========================================================================
  // 1. STATISTIQUES (tableau de bord)
  // =========================================================================

  group('StatsPeriode', () {
    test('parse une réponse RPC avec des nombres int et double mélangés', () {
      final StatsPeriode stats = StatsPeriode.depuisRpc(<String, dynamic>{
        'debut': '2026-09-16',
        'fin': '2026-09-16',
        'chiffre_affaires': 15000, // int majuscule de PostgREST
        'cout_marchandises': 6000.5,
        'marge_brute': 8999.5,
        'depenses': 2000,
        'benefice_net': 6999.5,
        'nb_ventes': 3,
        'nb_depenses': 1,
      });

      expect(stats.chiffreAffaires, 15000);
      expect(stats.coutMarchandises, 6000.5);
      expect(stats.beneficeNet, 6999.5);
      expect(stats.nbVentes, 3);
      expect(stats.nbDepenses, 1);
    });

    test('tauxMarge : 0 quand le chiffre d\'affaires est nul', () {
      expect(StatsPeriode.vide.tauxMarge, 0);
      final StatsPeriode stats = StatsPeriode.depuisRpc(<String, dynamic>{
        'chiffre_affaires': 10000,
        'marge_brute': 2500,
      });
      expect(stats.tauxMarge, closeTo(25, 0.001));
    });
  });

  group('Séries et tableau de bord', () {
    test('listeDepuisRpc tolère une réponse absente', () {
      expect(PointSerieFinance.listeDepuisRpc(null), isEmpty);
      expect(PointSerieFinance.listeDepuisRpc(<dynamic>[]), isEmpty);
    });

    test('parse les séries 7/30 jours et le top articles', () {
      final TableauBordFinance bord = TableauBordFinance.depuisRpc(
        <String, dynamic>{
          'ref': '2026-09-16',
          'jour': <String, dynamic>{'chiffre_affaires': 5000},
          'semaine': <String, dynamic>{'chiffre_affaires': 30000},
          'mois': <String, dynamic>{'chiffre_affaires': 120000},
          'series_7': <dynamic>[
            <String, dynamic>{
              'jour': '2026-09-10',
              'chiffre_affaires': 1000,
              'depenses': 200,
              'benefice_net': 800,
              'nb_ventes': 2,
            },
            <String, dynamic>{'jour': '2026-09-11'},
          ],
          'series_30': <dynamic>[],
          'top_articles': <dynamic>[
            <String, dynamic>{
              'produit_id': 492,
              'nom': 'Bouteille d\'eau',
              'quantite': 36,
              'ca': 12000,
              'marge': 4500,
            },
          ],
        },
      );

      expect(bord.jour.chiffreAffaires, 5000);
      expect(bord.semaine.chiffreAffaires, 30000);
      expect(bord.mois.chiffreAffaires, 120000);
      expect(bord.series7, hasLength(2));
      expect(bord.series7.first.chiffreAffaires, 1000);
      expect(bord.series7.first.beneficeNet, 800);
      expect(bord.series30, isEmpty);
      expect(bord.topArticles.single.nom, 'Bouteille d\'eau');
      expect(bord.topArticles.single.marge, 4500);
    });
  });

  // =========================================================================
  // 2. MOUVEMENTS DE CAISSE
  // =========================================================================

  group('MouvementCaisse', () {
    test('types et sens depuis les codes serveur', () {
      expect(TypeMouvementCaisse.depuisCode('vente'),
          TypeMouvementCaisse.vente);
      expect(TypeMouvementCaisse.depuisCode('vente_ancienne'),
          TypeMouvementCaisse.venteAncienne);
      expect(TypeMouvementCaisse.depuisCode('dette'),
          TypeMouvementCaisse.reglementDette);
      expect(TypeMouvementCaisse.depuisCode('depense'),
          TypeMouvementCaisse.depense);
      expect(TypeMouvementCaisse.depuisCode('inattendu'),
          TypeMouvementCaisse.inconnu);
      expect(SensMouvement.depuisCode('sortie'), SensMouvement.sortie);
      expect(SensMouvement.depuisCode(null), SensMouvement.entree);
    });

    test('parse une ligne de journal (dépense = sortie)', () {
      final MouvementCaisse mouvement =
          MouvementCaisse.depuisRpc(<String, dynamic>{
        'type': 'depense',
        'reference': 'DEP-12',
        'libelle': 'Transport marchandises',
        'sens': 'sortie',
        'mode': 'especes',
        'montant': 15000,
        'date': '2026-09-16T10:30:00+00:00',
      });

      expect(mouvement.type, TypeMouvementCaisse.depense);
      expect(mouvement.reference, 'DEP-12');
      expect(mouvement.estEntree, isFalse);
      expect(mouvement.montant, 15000);
      expect(mouvement.date, isNotNull);
    });

    test('journal : totaux et tolérances', () {
      final ResultatJournalCaisse journal =
          ResultatJournalCaisse.depuisRpc(<String, dynamic>{
        'debut': '2026-09-01',
        'fin': '2026-09-16',
        'sens': null,
        'mode': null,
        'lignes': <dynamic>[
          <String, dynamic>{
            'type': 'vente',
            'libelle': 'VTE-20260916-0001',
            'sens': 'entree',
            'mode': 'especes',
            'montant': 10000,
          },
        ],
        'totaux': <String, dynamic>{
          'entrees': 10000,
          'sorties': 2500,
          'nb': 2,
        },
      });

      expect(journal.lignes, hasLength(1));
      expect(journal.totaux.entrees, 10000);
      expect(journal.totaux.sorties, 2500);
      expect(journal.totaux.solde, 7500);
      expect(journal.totaux.nb, 2);
    });
  });

  group('ResumeCaisse', () {
    test('un vendeur sans droit reçoit solde et décaissements nuls', () {
      final ResumeCaisse resume = ResumeCaisse.depuisRpc(<String, dynamic>{
        'date': '2026-09-16',
        'solde': null,
        'depenses_visibles': false,
        'jour': <String, dynamic>{
          'encaissements_ventes': 12000,
          'encaissements_dettes': 3000,
          'encaissements': 15000,
          'decaissements': null,
          'net': 15000,
          'nb_ventes': 4,
          'nb_paiements_dettes': 1,
          'nb_depenses': 0,
        },
        'par_mode': <String, dynamic>{
          'especes': <String, dynamic>{
            'encaissements': 15000,
            'decaissements': 0,
          },
        },
        'derniere_cloture': null,
      });

      expect(resume.solde, isNull);
      expect(resume.depensesVisibles, isFalse);
      expect(resume.jour.encaissements, 15000);
      expect(resume.jour.decaissements, isNull);
      expect(resume.parMode['especes']!.net, 15000);
      expect(resume.derniereCloture, isNull);
    });

    test('un gérant voit le solde, les décaissements et la dernière clôture',
        () {
      final ResumeCaisse resume = ResumeCaisse.depuisRpc(<String, dynamic>{
        'date': '2026-09-16',
        'solde': 45000,
        'depenses_visibles': true,
        'jour': <String, dynamic>{
          'encaissements': 20000,
          'decaissements': 5000,
          'net': 15000,
        },
        'par_mode': <String, dynamic>{},
        'derniere_cloture': <String, dynamic>{
          'date_cloture': '2026-09-15',
          'solde_theorique': 40000,
          'espece_comptee': 39500,
          'ecart': -500,
          'commentaire': 'Rendu de monnaie',
        },
      });

      expect(resume.solde, 45000);
      expect(resume.depensesVisibles, isTrue);
      expect(resume.jour.decaissements, 5000);
      expect(resume.derniereCloture!.ecart, -500);
      expect(resume.derniereCloture!.commentaire, 'Rendu de monnaie');
    });
  });

  group('Clôture de caisse', () {
    test('parse le résultat de rpc_caisse_cloturer', () {
      final ResultatClotureCaisse resultat =
          ResultatClotureCaisse.depuisRpc(<String, dynamic>{
        'cloture_id': 7,
        'date_cloture': '2026-09-16',
        'fond_initial': 10000,
        'encaissements_total': 52000,
        'decaissements_total': 7000,
        'solde_theorique': 55000,
        'espece_comptee': 54500,
        'ecart': -500,
        'commentaire': 'Clôture du soir',
        'details': <String, dynamic>{'nb_ventes': 12},
        'created_at': '2026-09-16T20:00:00+00:00',
      });

      expect(resultat.clotureId, 7);
      expect(resultat.soldeTheorique, 55000);
      expect(resultat.ecart, -500);
      expect(resultat.details['nb_ventes'], 12);
    });
  });

  // =========================================================================
  // 3. DÉPENSES
  // =========================================================================

  group('DepensesFinance', () {
    test('parse la liste, les totaux et les catégories', () {
      final ResultatListeDepenses liste =
          ResultatListeDepenses.depuisRpc(<String, dynamic>{
        'debut': '2026-09-01',
        'fin': '2026-09-16',
        'categorie': null,
        'lignes': <dynamic>[
          <String, dynamic>{
            'depense_id': 3,
            'motif': 'Transport',
            'montant': 15000,
            'categorie': 'transport',
            'date': '2026-09-16T08:00:00+00:00',
          },
        ],
        'totaux': <String, dynamic>{'nb': 2, 'total': 45000},
        'categories': <dynamic>['transport', 'loyer', ''],
      });

      expect(liste.lignes.single.motif, 'Transport');
      expect(liste.totaux.total, 45000);
      expect(liste.totaux.moyenne, 22500);
      expect(liste.categories, <String>['transport', 'loyer']);
    });
  });

  // =========================================================================
  // 4. DETTES CLIENTS
  // =========================================================================

  group('DetteClient', () {
    test('statut depuis le code serveur', () {
      expect(StatutDette.depuisCode('non_paye'), StatutDette.nonPaye);
      expect(StatutDette.depuisCode('partiel'), StatutDette.partiel);
      expect(StatutDette.depuisCode('paye'), StatutDette.paye);
      expect(StatutDette.depuisCode('ZZZ'), StatutDette.inconnu);
    });

    test('parse une dette (restant, ancienneté, règlements)', () {
      final DetteClient dette = DetteClient.depuisRpc(<String, dynamic>{
        'dette_id': 11,
        'client_id': 42,
        'client': 'Mama Nzuzi',
        'telephone': '+243 812 345 678',
        'vente_uuid': 'a1b2c3d4-0000-0000-0000-000000000000',
        'montant_total': 25000,
        'montant_paye': 10000,
        'restant': 15000,
        'statut': 'partiel',
        'date_creation': '2026-09-01T09:00:00+00:00',
        'date_echeance': '2026-09-10',
        'jours': 15,
        'dernier_paiement': '2026-09-05T10:00:00+00:00',
        'nb_paiements': 1,
      });

      expect(dette.id, 11);
      expect(dette.statut, StatutDette.partiel);
      expect(dette.restant, 15000);
      expect(dette.jours, 15);
      expect(dette.nbPaiements, 1);
      expect(dette.estSoldee, isFalse);
    });

    test('enRetard respecte l\'échéance et l\'état soldé', () {
      DetteClient dette({
        double restant = 1000,
        StatutDette statut = StatutDette.nonPaye,
        DateTime? echeance,
      }) =>
          DetteClient(
            id: 1,
            clientId: 1,
            client: 'Client',
            restant: restant,
            statut: statut,
            dateEcheance: echeance,
          );

      final DateTime reference = DateTime(2026, 9, 16);
      expect(
        dette(echeance: DateTime(2026, 9, 10)).enRetard(reference: reference),
        isTrue,
      );
      expect(
        dette(echeance: DateTime(2026, 9, 20)).enRetard(reference: reference),
        isFalse,
      );
      // Sans échéance : jamais « en retard ».
      expect(dette().enRetard(reference: reference), isFalse);
      expect(
        dette(
          restant: 0,
          statut: StatutDette.paye,
          echeance: DateTime(2026, 9, 1),
        ).enRetard(reference: reference),
        isFalse,
      );
    });

    test('apresPaiement met à jour la dette sans la recharger', () {
      const DetteClient dette = DetteClient(
        id: 11,
        clientId: 42,
        client: 'Mama Nzuzi',
        montantTotal: 25000,
        montantPaye: 10000,
        restant: 15000,
        statut: StatutDette.partiel,
        nbPaiements: 1,
      );

      final DetteClient soldee = dette.apresPaiement(
        montantPaye: 25000,
        restant: 0,
        statut: StatutDette.paye,
        nbPaiements: 2,
      );

      expect(soldee.estSoldee, isTrue);
      expect(soldee.montantPaye, 25000);
      expect(soldee.nbPaiements, 2);
      expect(soldee.client, 'Mama Nzuzi');
    });

    test('parse le résumé et le résultat d\'un paiement', () {
      final ResultatListeDettes liste =
          ResultatListeDettes.depuisRpc(<String, dynamic>{
        'lignes': <dynamic>[],
        'resume': <String, dynamic>{
          'nb': 4,
          'nb_non_paye': 2,
          'nb_partiel': 1,
          'nb_paye': 1,
          'total_dettes': 100000,
          'total_restant': 60000,
        },
      });

      expect(liste.resume.nbNonPaye, 2);
      expect(liste.resume.totalRestant, 60000);

      final ResultatPaiementDette paiement =
          ResultatPaiementDette.depuisRpc(<String, dynamic>{
        'dette_id': 11,
        'client': 'Mama Nzuzi',
        'montant': 15000,
        'mode_paiement': 'mobile_money',
        'date_paiement': '2026-09-16T12:00:00+00:00',
        'montant_paye': 25000,
        'restant': 0,
        'statut': 'paye',
      });

      expect(paiement.statut, StatutDette.paye);
      expect(paiement.restant, 0);
      expect(paiement.modePaiement, 'mobile_money');
    });

    test('parse une relance préparée par le serveur', () {
      final RelanceDette relance = RelanceDette.depuisRpc(<String, dynamic>{
        'dette_id': 11,
        'client': 'Mama Nzuzi',
        'telephone': '+243812345678',
        'canal': 'whatsapp',
        'restant': 15000,
        'jours': 15,
        'message': 'Bonjour Mama Nzuzi, votre dette de 15000 CDF…',
      });

      expect(relance.canal, 'whatsapp');
      expect(relance.jours, 15);
      expect(relance.message, contains('15000 CDF'));
    });
  });

  group('DetteService — liens de relance', () {
    test('numeroInternational : numéros locaux et internationaux', () {
      expect(DetteService.numeroInternational('0812345678'), '243812345678');
      expect(DetteService.numeroInternational('+243 812 345 678'),
          '243812345678');
      expect(DetteService.numeroInternational('00243812345678'),
          '243812345678');
      expect(DetteService.numeroInternational('812 345 678'), '812345678');
      expect(DetteService.numeroInternational('  '), '');
    });

    test('liens WhatsApp, SMS et appel', () {
      final Uri whatsapp = DetteService.lienWhatsApp(
          '0812345678', 'Bonjour, votre dette reste à régler.');
      expect(whatsapp.toString(), startsWith('https://wa.me/243812345678?text='));
      expect(whatsapp.query, contains('Bonjour'));

      final Uri sms = DetteService.lienSms('0812345678', 'Rappel');
      expect(sms.scheme, 'sms');
      expect(sms.path, '243812345678');
      expect(sms.queryParameters['body'], 'Rappel');

      final Uri appel = DetteService.lienAppel('0812345678');
      expect(appel.scheme, 'tel');
      expect(appel.path, '243812345678');
    });
  });

  // =========================================================================
  // 5. RAPPORTS
  // =========================================================================

  group('RapportFinance', () {
    test('groupe « article » : quantité, coût et marge', () {
      final RapportFinance rapport = RapportFinance.depuisRpc(
        GroupeRapportFinance.article,
        <String, dynamic>{
          'debut': '2026-08-18',
          'fin': '2026-09-16',
          'lignes': <dynamic>[
            <String, dynamic>{
              'produit_id': 492,
              'nom': 'Bouteille d\'eau',
              'quantite': 36,
              'ca': 12000,
              'cout': 7500,
              'marge': 4500,
            },
          ],
          'totaux': <String, dynamic>{'chiffre_affaires': 12000},
        },
      );

      final LigneRapportFinance ligne = rapport.lignes.single;
      expect(ligne.cle, '492');
      expect(ligne.libelle, 'Bouteille d\'eau');
      expect(ligne.marge, 4500);
      expect(ligne.part(12000), 1);
      expect(rapport.totalLignes, 12000);
    });

    test('groupe « jour » : bénéfice net et dépenses', () {
      final RapportFinance rapport = RapportFinance.depuisRpc(
        GroupeRapportFinance.jour,
        <String, dynamic>{
          'lignes': <dynamic>[
            <String, dynamic>{
              'jour': '2026-09-16',
              'chiffre_affaires': 5000,
              'cout_marchandises': 2000,
              'depenses': 1000,
              'benefice_net': 2000,
              'nb_ventes': 2,
            },
          ],
          'totaux': <String, dynamic>{},
        },
      );

      final LigneRapportFinance ligne = rapport.lignes.single;
      expect(ligne.libelle, '2026-09-16');
      expect(ligne.montant, 5000);
      expect(ligne.depenses, 1000);
      expect(ligne.beneficeNet, 2000);
    });

    test('groupes vendeur, mode et catégorie de dépense', () {
      final RapportFinance vendeurs = RapportFinance.depuisRpc(
        GroupeRapportFinance.vendeur,
        <String, dynamic>{
          'lignes': <dynamic>[
            <String, dynamic>{
              'seller_id': null,
              'nom': 'Vendeur non attribué',
              'nb_ventes': 5,
              'ca': 30000,
            },
          ],
        },
      );
      expect(vendeurs.lignes.single.cle, 'non-attribue');
      expect(vendeurs.lignes.single.nb, 5);

      final RapportFinance modes = RapportFinance.depuisRpc(
        GroupeRapportFinance.mode,
        <String, dynamic>{
          'lignes': <dynamic>[
            <String, dynamic>{
              'mode': 'mobile_money',
              'nb_ventes': 2,
              'ca': 9000,
            },
          ],
        },
      );
      expect(modes.lignes.single.libelle, 'mobile_money');
      expect(FinanceService.libelleMode(modes.lignes.single.libelle),
          'Mobile Money');

      final RapportFinance categories = RapportFinance.depuisRpc(
        GroupeRapportFinance.categorieDepense,
        <String, dynamic>{
          'lignes': <dynamic>[
            <String, dynamic>{
              'categorie': 'transport',
              'nb': 3,
              'montant': 45000,
            },
          ],
        },
      );
      expect(categories.lignes.single.montant, 45000);
      expect(categories.lignes.single.nb, 3);
    });
  });

  // =========================================================================
  // 6. MESSAGES D'ERREUR ET CONSTANTES
  // =========================================================================

  group('Messages d\'erreur serveur', () {
    test('les codes préfixés sont retirés', () {
      expect(
        FinanceService.messageErreur(
            'MONTANT_INVALIDE|Le montant de la dépense doit être supérieur à zéro.'),
        'Le montant de la dépense doit être supérieur à zéro.',
      );
      expect(
        DetteService.messageErreur('DEJA_SOLDEE|Cette dette est déjà soldée.'),
        'Cette dette est déjà soldée.',
      );
      expect(FinanceService.messageErreur('Message sans code'),
          'Message sans code');
    });
  });

  group('Constantes du module', () {
    test('modes de paiement et catégories', () {
      expect(FinanceService.modesPaiement['especes'], 'Espèces');
      expect(FinanceService.libelleMode('mobile_money'), 'Mobile Money');
      expect(FinanceService.libelleMode('inconnu'), 'inconnu');
      expect(FinanceService.categoriesParDefaut, contains('autre'));
      expect(DetteService.canauxRelance.keys,
          containsAll(<String>['whatsapp', 'sms', 'appel']));
    });
  });
}
