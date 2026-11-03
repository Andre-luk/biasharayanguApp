// test/distribution_gestion_test.dart
//
// 🚚 MODULE 24 — tests des objets PURS du module Distribution.
//
// Aucun accès réseau : on vérifie le parsing tolérant des réponses `dist_*`,
// les statuts lisibles, les drapeaux de rôle et les messages d'erreur.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/services/distribution_gestion_service.dart';

void main() {
  group('RoleDistribution', () {
    test('reconnaît les six rôles et retombe sur « aucun »', () {
      expect(RoleDistribution.depuisCode('proprietaire'),
          RoleDistribution.proprietaire);
      expect(RoleDistribution.depuisCode('GERANT'), RoleDistribution.gerant);
      expect(RoleDistribution.depuisCode(' production '),
          RoleDistribution.production);
      expect(RoleDistribution.depuisCode('stock'), RoleDistribution.stock);
      expect(RoleDistribution.depuisCode('commercial'),
          RoleDistribution.commercial);
      expect(RoleDistribution.depuisCode('comptable'),
          RoleDistribution.comptable);
      expect(RoleDistribution.depuisCode('inconnu'), RoleDistribution.aucun);
      expect(RoleDistribution.depuisCode(null), RoleDistribution.aucun);
    });

    test('les drapeaux de responsabilité sont cohérents', () {
      expect(RoleDistribution.gerant.estDirection, isTrue);
      expect(RoleDistribution.proprietaire.estDirection, isTrue);
      expect(RoleDistribution.commercial.estDirection, isFalse);

      expect(RoleDistribution.proprietaire.peutGererCollaborateurs, isTrue);
      expect(RoleDistribution.gerant.peutGererCollaborateurs, isFalse);

      expect(RoleDistribution.production.peutProduire, isTrue);
      expect(RoleDistribution.stock.peutProduire, isFalse);
      expect(RoleDistribution.gerant.peutProduire, isTrue);

      expect(RoleDistribution.stock.peutGererStock, isTrue);
      expect(RoleDistribution.production.peutGererStock, isFalse);
      expect(RoleDistribution.proprietaire.peutGererStock, isTrue);

      expect(RoleDistribution.commercial.peutVendre, isTrue);
      expect(RoleDistribution.gerant.peutVendre, isFalse);

      expect(RoleDistribution.comptable.peutValiderArgent, isTrue);
      expect(RoleDistribution.commercial.peutValiderArgent, isFalse);
      expect(RoleDistribution.gerant.peutValiderArgent, isTrue);
    });
  });

  group('TableauBordDistribution', () {
    test('lit les compteurs imbriqués et les opérations en attente', () {
      final TableauBordDistribution bord = TableauBordDistribution.depuisJson(
        <String, dynamic>{
          'role': 'gerant',
          'devise': 'USD',
          'intrants': <String, dynamic>{
            'total': 15000,
            'pet': 5000,
            'caps': 5000,
            'bouteilles_vides': 5000,
          },
          'produits': <String, dynamic>{
            'total': 450,
            'fardes': 100,
            'bouteilles': 300,
            'bidons': 50,
          },
          'attribues_commerciaux': 30,
          'demandes_intrants_attente_stock': 2,
          'demandes_intrants_attente_production': 1,
          'productions_attente_stock': 3,
          'receptions_attente_gerant': 1,
          'demandes_commerciales_en_cours': 4,
          'retours_attente_stock': 1,
          'remises_attente_comptable': 2,
          'remises_attente_gerant': 1,
          'depenses_attente': 3,
          'ventes_total': 250000,
          'collecte_commerciaux': 120000,
          'montant_recu_comptable': 80000,
          'collecte_non_remise': 40000,
          'caisse_solde': 500000,
          'depenses_mois': 50000,
          'anomalies_ouvertes': 2,
          'tournees_en_cours': 3,
          'operations': <dynamic>[
            <String, dynamic>{
              'type': 'remise_comptable',
              'id': 'abc',
              'numero': 'REM-1',
              'libelle': 'Remise à recevoir',
              'role': 'comptable',
              'date': '2026-11-03T09:00:00Z',
            },
          ],
        },
      );

      expect(bord.role, RoleDistribution.gerant);
      expect(bord.devise, 'USD');
      expect(bord.intrantsTotal, 15000);
      expect(bord.pet, 5000);
      expect(bord.caps, 5000);
      expect(bord.bouteillesVides, 5000);
      expect(bord.produitsTotal, 450);
      expect(bord.fardes, 100);
      expect(bord.bidons, 50);
      expect(bord.attribuesCommerciaux, 30);
      expect(bord.collecteNonRemise, 40000);
      expect(bord.caisseSolde, 500000);
      expect(bord.operations, hasLength(1));
      expect(bord.operations.first.role, RoleDistribution.comptable);
      expect(bord.operations.first.icone, '💵');
      expect(bord.operations.first.date, isNotNull);

      // 2 + 1 + 3 + 1 + 4 + 1 + 2 + 1 + 3 + 2 = 20
      expect(bord.totalEnAttente, 20);
      expect(bord.resultatBrut, 200000);
    });

    test('tolère un JSON vide (aucune exception)', () {
      final TableauBordDistribution bord =
          TableauBordDistribution.depuisJson(<String, dynamic>{});
      expect(bord.role, RoleDistribution.aucun);
      expect(bord.devise, 'CDF');
      expect(bord.totalEnAttente, 0);
      expect(bord.operations, isEmpty);
    });
  });

  group('Stock', () {
    test('sépare intrants et produits finis et signale les seuils', () {
      final StockDistribution stock = StockDistribution.depuisJson(
        <String, dynamic>{
          'role': 'stock',
          'intrants': <dynamic>[
            <String, dynamic>{
              'id': 'i1',
              'nom': 'PET',
              'unite': 'pc',
              'stock': 100,
              'seuil': 200,
              'prix': 50,
            },
            <String, dynamic>{
              'id': 'i2',
              'nom': 'Caps',
              'unite': 'pc',
              'stock': 500,
              'seuil': 100,
            },
          ],
          'produits': <dynamic>[
            <String, dynamic>{
              'id': 'p1',
              'nom': 'Farde 12×50cl',
              'format': 'farde',
              'unite': 'farde',
              'stock': 0,
              'prix_vente': 8000,
              'prix_achat': 5000,
            },
          ],
        },
      );

      expect(stock.role, RoleDistribution.stock);
      expect(stock.intrants, hasLength(2));
      expect(stock.produits, hasLength(1));
      expect(stock.intrants.first.estIntrant, isTrue);
      expect(stock.intrants.first.alerte, isTrue);
      expect(stock.intrants[1].alerte, isFalse);
      expect(stock.produits.first.rupture, isTrue);
      expect(stock.produits.first.designation, 'Farde 12×50cl · farde');
      expect(stock.produits.first.prix, 8000);
      expect(stock.totalIntrants, 600);
      expect(stock.alertes, 2);
    });
  });

  group('Réceptions', () {
    test('calcule l\'écart entre annoncé et compté', () {
      final ReceptionIntrants r = ReceptionIntrants.depuisJson(
        <String, dynamic>{
          'id': 'r1',
          'numero': 'REC-20261103-0001',
          'fournisseur': 'PET Congo',
          'statut': 'attente_gerant',
          'lignes': <dynamic>[
            <String, dynamic>{
              'intrant_id': 'i1',
              'nom': 'PET',
              'unite': 'pc',
              'quantite_annoncee': 5000,
              'quantite_comptee': 4900,
            },
          ],
        },
      );

      expect(r.enAttente, isTrue);
      expect(r.libelleStatut, 'Attente du gérant');
      expect(r.lignes.first.ecart, -100);
    });
  });

  group('Demandes d\'intrants', () {
    test('statuts et quantités du cycle demande → sortie → réception', () {
      final DemandeIntrant d = DemandeIntrant.depuisJson(
        <String, dynamic>{
          'id': 'd1',
          'numero': 'DIN-1',
          'statut': 'attente_reception',
          'demandeur': 'Jean Production',
          'lignes': <dynamic>[
            <String, dynamic>{
              'intrant_id': 'i1',
              'nom': 'PET',
              'unite': 'pc',
              'quantite_demandee': 2000,
              'quantite_autorisee': 2000,
              'quantite_sortie': 2000,
              'quantite_recue': 0,
            },
          ],
        },
      );

      expect(d.attenteReception, isTrue);
      expect(d.attenteStock, isFalse);
      expect(d.libelleStatut, 'Attente du producteur');
      expect(d.lignes.first.sortie, 2000);
      expect(d.lignes.first.ecart, 2000);
    });
  });

  group('Production', () {
    test('totalise produit / remis / reçu / pertes / reste', () {
      final ProductionDistribution p = ProductionDistribution.depuisJson(
        <String, dynamic>{
          'id': 'p1',
          'numero': 'PRD-1',
          'statut': 'en_litige',
          'motif_pertes': 'Bouteilles défectueuses',
          'intrants': <dynamic>[
            <String, dynamic>{
              'intrant_id': 'i1',
              'nom': 'PET',
              'quantite_recue': 2000,
              'quantite_consommee': 1900,
              'quantite_perdue': 50,
              'quantite_restante': 50,
            },
          ],
          'sorties': <dynamic>[
            <String, dynamic>{
              'produit_id': 'f1',
              'nom': 'Farde',
              'quantite_produite': 100,
              'quantite_remise': 100,
              'quantite_recue': 95,
            },
          ],
        },
      );

      expect(p.enLitige, isTrue);
      expect(p.quantiteProduite, 100);
      expect(p.quantiteRemise, 100);
      expect(p.quantiteRecue, 95);
      expect(p.pertesIntrants, 50);
      expect(p.resteIntrants, 50);
      expect(p.sorties.first.ecart, 5);
      expect(p.motifPertes, 'Bouteilles défectueuses');
    });
  });

  group('Commercial', () {
    test('demande commerciale : statuts lisibles', () {
      final DemandeCommercial d = DemandeCommercial.depuisJson(
        <String, dynamic>{
          'id': 'c1',
          'numero': 'DCO-1',
          'statut': 'attente_commercial',
          'commercial': 'Alice',
          'lignes': <dynamic>[
            <String, dynamic>{
              'produit_id': 'f1',
              'nom': 'Farde',
              'quantite_demandee': 30,
              'quantite_confirmee': 30,
              'quantite_sortie': 30,
              'quantite_recue': null,
            },
          ],
        },
      );

      expect(d.attenteCommercial, isTrue);
      expect(d.libelleStatut, 'Attente commercial');
      expect(d.lignes.first.sortie, 30);
      expect(d.lignes.first.recue, 0);
    });

    test('client : localisation lisible sans champ vide', () {
      const ClientDistribution c = ClientDistribution(
        id: 'cl1',
        nom: 'Épicerie Lumumba',
        telephone: '+243 970 000 000',
        adresse: 'Avenue Kasa-Vubu 12',
        zone: 'Lubumbashi',
      );
      expect(c.localisation, 'Avenue Kasa-Vubu 12 · Lubumbashi');
    });

    test('vente : crédit et facture', () {
      final VenteDistribution v = VenteDistribution.depuisJson(
        <String, dynamic>{
          'id': 'v1',
          'numero': 'FAC-1',
          'commercial': 'Alice',
          'client': 'Épicerie',
          'total': 104000,
          'montant_paye': 80000,
          'credit': 24000,
          'mode_paiement': 'especes',
          'lignes': <dynamic>[
            <String, dynamic>{
              'nom': 'Fardes',
              'quantite': 10,
              'prix_unitaire': 8000,
              'total': 80000,
            },
          ],
        },
      );
      expect(v.aCredit, isTrue);
      expect(v.credit, 24000);
      expect(v.lignes.first.total, 80000);

      final FactureDistribution f = FactureDistribution.depuisJson(
        <String, dynamic>{
          'entreprise': 'ETS BUSINESS',
          'numero': 'FAC-1',
          'client': 'Épicerie',
          'total': 104000,
          'montant_paye': 80000,
          'credit': 24000,
          'lignes': <dynamic>[
            <String, dynamic>{
              'nom': 'Fardes',
              'quantite': 10,
              'prix_unitaire': 8000,
              'total': 80000,
            },
            <String, dynamic>{
              'nom': 'Gros bidons',
              'quantite': 2,
              'prix_unitaire': 12000,
              'total': 24000,
            },
          ],
        },
      );
      expect(f.entreprise, 'ETS BUSINESS');
      expect(f.lignes, hasLength(2));
      expect(f.credit, 24000);
    });
  });

  group('Retours, remises et collaborateurs', () {
    test('retour : écart déclaré / compté', () {
      final RetourCommercial r = RetourCommercial.depuisJson(
        <String, dynamic>{
          'id': 'rt1',
          'numero': 'RET-1',
          'statut': 'en_litige',
          'lignes': <dynamic>[
            <String, dynamic>{
              'produit_id': 'f1',
              'nom': 'Farde',
              'quantite_declaree': 10,
              'quantite_recue': 8,
            },
          ],
        },
      );
      expect(r.enAttente, isFalse);
      expect(r.libelleStatut, 'En litige');
      expect(r.lignes.first.ecart, 2);
    });

    test('remise : étapes comptable puis gérant', () {
      const RemiseArgent declaree = RemiseArgent(
        id: 'r1',
        statut: 'declaree',
        montantDeclare: 50000,
      );
      const RemiseArgent recue = RemiseArgent(
        id: 'r2',
        statut: 'recue',
        montantDeclare: 50000,
        montantRecu: 48000,
      );
      const RemiseArgent validee = RemiseArgent(
        id: 'r3',
        statut: 'validee',
        montantDeclare: 50000,
        montantRecu: 50000,
        montantValide: 50000,
      );

      expect(declaree.attenteComptable, isTrue);
      expect(declaree.attenteGerant, isFalse);
      expect(recue.attenteComptable, isFalse);
      expect(recue.attenteGerant, isTrue);
      expect(recue.libelleStatut, 'Reçue (attente gérant)');
      expect(validee.libelleStatut, 'Validée');
    });

    test('collaborateur : nom complet et rôle', () {
      final CollaborateurDistribution c = CollaborateurDistribution.depuisJson(
        <String, dynamic>{
          'id': 'u1',
          'nom': 'Kabila',
          'prenom': 'Alice',
          'email': 'alice@exemple.cd',
          'role_distribution': 'commercial',
          'actif': true,
        },
      );
      expect(c.nomComplet, 'Kabila Alice');
      expect(c.role, RoleDistribution.commercial);
      expect(c.actif, isTrue);
    });
  });

  group('Messages d\'erreur', () {
    test('traduit les codes métier en français', () {
      expect(DistributionGestionService.messageErreur('DROIT_REFUSE|'),
          contains('rôle'));
      expect(
          DistributionGestionService.messageErreur('STOCK_INSUFFISANT|'),
          contains('Stock insuffisant'));
      expect(
          DistributionGestionService.messageErreur('MOTIF_REQUIS|'),
          contains('motif'));
      expect(
          DistributionGestionService.messageErreur('DOUBLON_CLIENT|'),
          contains('existe déjà'));
      expect(
          DistributionGestionService.messageErreur('PGRST202|'),
          contains('migration'));
    });

    test('un message déjà rédigé est conservé', () {
      expect(
        DistributionGestionService.messageErreur('La caisse est vide.'),
        'La caisse est vide.',
      );
      expect(
        DistributionGestionService.messageErreur(null),
        contains('Opération impossible'),
      );
    });
  });

  group('Journal de traçabilité', () {
    test('lit une entrée et traduit son action', () {
      final EntreeJournalDistribution e =
          EntreeJournalDistribution.depuisJson(<String, dynamic>{
        'id': 42,
        'action': 'RECEPTION_INTRANTS_REFUSEE',
        'entite': 'dist_receptions',
        'entite_id': 'abc',
        'auteur': 'Kabila Alice',
        'role': 'gerant',
        'details': <String, dynamic>{'numero': 'REC-20260101-0001'},
        'created_at': '2026-01-01T10:00:00Z',
      });

      expect(e.id, 42);
      expect(e.libelle, contains('refusée'));
      expect(e.auteur, 'Kabila Alice');
      expect(e.date, isNotNull);
      expect(e.resume, contains('REC-20260101-0001'));
    });

    test('un code d\'action inconnu reste lisible et un JSON vide ne casse pas',
        () {
      final EntreeJournalDistribution e =
          EntreeJournalDistribution.depuisJson(<String, dynamic>{
        'action': 'ACTION_FUTURE',
        'details': null,
      });

      expect(e.libelle, 'ACTION_FUTURE');
      expect(e.resume, isEmpty);
      expect(e.id, 0);
      expect(e.date, isNull);
    });

    test('le refus d\'une réception exige un motif explicite', () async {
      expect(
        () => DistributionGestionService.instance
            .refuserReception('reception-1', '  '),
        throwsA(isA<DistributionGestionException>()),
      );
    });
  });

  group('Tarifs, bonus et marges (§9-§11)', () {
    test('lis un tarif et retombe sur « prix normal »', () {
      final TarifBidon t = TarifBidon.depuisJson(<String, dynamic>{
        'id': 't1',
        'produit_id': 'p1',
        'produit': 'Bidon 20L',
        'type_operation': 'eau_avec_echange',
        'prix': 1500,
        'actif': true,
      });
      expect(t.type, TypeOperationTarif.eauAvecEchange);
      expect(t.prix, 1500);
      expect(t.libelleAffiche, contains('échange'));
      expect(TypeOperationTarif.depuisCode('inconnu'),
          TypeOperationTarif.standard);
    });

    test('une déclaration de bonus est lisible et son statut traduit', () {
      final BonusDommage b = BonusDommage.depuisJson(<String, dynamic>{
        'id': 'b1',
        'commercial_id': 'c1',
        'commercial': 'Kabila Alice',
        'nom_produit': 'Farde',
        'nature': 'casse',
        'quantite': 2,
        'valeur': 4000,
        'motif': 'Chute au déchargement',
        'statut': 'valide',
      });
      expect(b.nature, NatureBonus.casse);
      expect(b.nature.estBonus, isFalse);
      expect(b.valide, isTrue);
      expect(b.libelleStatut, 'Validé');
      expect(b.valeur, 4000);
    });

    test('un coût incomplet laisse la marge vide (jamais inventée)', () {
      final CoutRevientProduit c = CoutRevientProduit.depuisJson(
        <String, dynamic>{
          'produit_id': 'p1',
          'produit': 'Bidon',
          'quantite': 100,
          'cout_total': 0,
          'cout_unitaire': null,
          'prix_vente': 1500,
          'marge_unitaire': null,
          'marge_pct': null,
          'cout_complet': false,
        },
      );
      expect(c.coutComplet, isFalse);
      expect(c.coutUnitaire, isNull);
      expect(c.margeUnitaire, isNull);
    });

    test('rentabilité : CA, coût, marge et commerciaux', () {
      final RentabiliteDistribution r = RentabiliteDistribution.depuisJson(
        <String, dynamic>{
          'ca': 100000,
          'cout_marchandises': 60000,
          'marge_brute': 40000,
          'marge_pct': 40.0,
          'bonus_dommages': 5000,
          'cout_complet': true,
          'par_commercial': <Map<String, dynamic>>[
            <String, dynamic>{'commercial_id': 'c1', 'ca': 100000, 'nb_ventes': 8},
          ],
          'produits': <Map<String, dynamic>>[],
        },
      );
      expect(r.margeBrute, 40000);
      expect(r.margePct, 40.0);
      expect(r.coutComplet, isTrue);
      expect(r.parCommercial.single.ca, 100000);
      expect(r.bonusDommages, 5000);
    });
  });
}
