// test/restaurant_test.dart
//
// 🍽️ MODULE 16 (phase C3) — Tests PURS du module restaurant : tables,
// commandes, lignes, tableau de bord et messages d'erreur. Aucun réseau.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/commande.dart';
import 'package:biashara_yangu/models/restaurant_tableau_bord.dart';
import 'package:biashara_yangu/models/table_salle.dart';
import 'package:biashara_yangu/services/restaurant_service.dart';

void main() {
  // =========================================================================
  // 1. TABLES
  // =========================================================================

  group('TableStatut', () {
    test('fromCode accepte les codes serveur et retombe sur libre', () {
      expect(TableStatut.fromCode('libre'), TableStatut.libre);
      expect(TableStatut.fromCode('occupee'), TableStatut.occupee);
      expect(TableStatut.fromCode('reservee'), TableStatut.reservee);
      expect(TableStatut.fromCode(' OCCUPEE '), TableStatut.occupee);
      expect(TableStatut.fromCode(null), TableStatut.libre);
      expect(TableStatut.fromCode('inconnu'), TableStatut.libre);
    });
  });

  group('TableSalle', () {
    test('fromMap, designation et disponibilité', () {
      final TableSalle table = TableSalle.fromMap(<String, dynamic>{
        'id': 'table-1',
        'numero': '5',
        'zone': 'Terrasse',
        'places': 4,
        'statut': 'reservee',
        'actif': true,
      });

      expect(table.numero, '5');
      expect(table.zone, 'Terrasse');
      expect(table.places, 4);
      expect(table.statut, TableStatut.reservee);
      expect(table.designation, 'Table 5 — Terrasse');
      expect(table.disponible, isTrue); // réservée mais pas occupée
    });

    test('une table occupée ou inactive n\'est pas disponible', () {
      const TableSalle table = TableSalle(id: 't', numero: '7');
      expect(table.designation, 'Table 7');
      expect(table.disponible, isTrue);
      expect(table.copyWith(statut: TableStatut.occupee).disponible, isFalse);
      expect(table.copyWith(actif: false).disponible, isFalse);
    });
  });

  // =========================================================================
  // 2. COMMANDES
  // =========================================================================

  group('StatutCommande', () {
    test('fromCode + libellés', () {
      expect(StatutCommande.fromCode('ouverte'), StatutCommande.ouverte);
      expect(StatutCommande.fromCode('envoyee'), StatutCommande.envoyee);
      expect(StatutCommande.fromCode('en_preparation'),
          StatutCommande.enPreparation);
      expect(StatutCommande.fromCode('prete'), StatutCommande.prete);
      expect(StatutCommande.fromCode('servie'), StatutCommande.servie);
      expect(StatutCommande.fromCode('encaissee'), StatutCommande.encaissee);
      expect(StatutCommande.fromCode('annulee'), StatutCommande.annulee);
      expect(StatutCommande.fromCode(null), StatutCommande.ouverte);

      expect(StatutCommande.ouverte.libelle, 'En saisie');
    });

    test('estActive / enCuisine', () {
      expect(StatutCommande.ouverte.estActive, isTrue);
      expect(StatutCommande.servie.estActive, isTrue);
      expect(StatutCommande.encaissee.estActive, isFalse);
      expect(StatutCommande.annulee.estActive, isFalse);

      expect(StatutCommande.envoyee.enCuisine, isTrue);
      expect(StatutCommande.enPreparation.enCuisine, isTrue);
      expect(StatutCommande.prete.enCuisine, isTrue);
      expect(StatutCommande.ouverte.enCuisine, isFalse);
      expect(StatutCommande.servie.enCuisine, isFalse);
    });
  });

  group('LigneCommande', () {
    test('fromMap', () {
      final LigneCommande ligne = LigneCommande.fromMap(<String, dynamic>{
        'id': 'ligne-1',
        'produit_id': 7,
        'libelle': 'Poulet braisé',
        'quantite': 2,
        'quantite_vendue': 2,
        'prix_unitaire': 12000,
        'total': 24000,
      });

      expect(ligne.id, 'ligne-1');
      expect(ligne.produitId, 7);
      expect(ligne.libelle, 'Poulet braisé');
      expect(ligne.quantite, 2);
      expect(ligne.quantiteVendue, 2);
      expect(ligne.prixUnitaire, 12000);
      expect(ligne.total, 24000);
    });
  });

  group('Commande', () {
    Map<String, dynamic> ligne([String statut = 'envoyee']) {
      return <String, dynamic>{
        'id': 'cmd-1',
        'table_id': 'table-1',
        'tables_salle': <String, dynamic>{'numero': '5', 'zone': 'Salle'},
        'numero': 'CMD-20260919-0001',
        'client_nom': 'M. Ilunga',
        'nb_personnes': 3,
        'statut': statut,
        'montant_total': 35500,
        'lignes_commande': <dynamic>[
          <String, dynamic>{
            'id': 'l1',
            'produit_id': 7,
            'libelle': 'Poulet braisé',
            'quantite': 2,
            'quantite_vendue': 2,
            'prix_unitaire': 12000,
            'total': 24000,
          },
          <String, dynamic>{
            'id': 'l2',
            'produit_id': 9,
            'libelle': 'Coca 33cl',
            'quantite': 1,
            'quantite_vendue': 1,
            'prix_unitaire': 1000,
            'total': 1000,
          },
        ],
      };
    }

    test('fromMap avec jointures table et lignes', () {
      final Commande commande = Commande.fromMap(ligne());

      expect(commande.id, 'cmd-1');
      expect(commande.tableNumero, '5');
      expect(commande.numero, 'CMD-20260919-0001');
      expect(commande.clientNom, 'M. Ilunga');
      expect(commande.nbPersonnes, 3);
      expect(commande.statut, StatutCommande.envoyee);
      expect(commande.montantTotal, 35500);
      expect(commande.nbArticles, 2);
      expect(commande.resume, '2× Poulet braisé, 1× Coca 33cl');
      expect(commande.statut.estActive, isTrue);
    });

    test('resume vide sans lignes', () {
      final Map<String, dynamic> map = ligne()..['lignes_commande'] = <dynamic>[];
      expect(Commande.fromMap(map).resume, 'Aucun article');
    });

    test('copyWith', () {
      final Commande commande = Commande.fromMap(ligne('ouverte'));
      final Commande encaissee = commande.copyWith(
        statut: StatutCommande.encaissee,
        numeroVente: 'VTE-20260919-0002',
      );

      expect(encaissee.statut, StatutCommande.encaissee);
      expect(encaissee.numeroVente, 'VTE-20260919-0002');
      expect(encaissee.statut.estActive, isFalse);
    });
  });

  // =========================================================================
  // 3. TABLEAU DE BORD
  // =========================================================================

  group('RestaurantTableauBord', () {
    test('fromMap + cuisineCount', () {
      final RestaurantTableauBord bord =
          RestaurantTableauBord.fromMap(<String, dynamic>{
        'ok': true,
        'tables': <String, dynamic>{
          'total': 10,
          'libres': 4,
          'occupees': 5,
          'reservees': 1,
        },
        'commandes_actives': 6,
        'a_envoyer': 2,
        'en_cuisine': 3,
        'pretes': 1,
        'servies': 2,
        'montant_actif': 125000,
      });

      expect(bord.tablesTotal, 10);
      expect(bord.tablesLibres, 4);
      expect(bord.tablesOccupees, 5);
      expect(bord.tablesReservees, 1);
      expect(bord.commandesActives, 6);
      expect(bord.aEnvoyer, 2);
      expect(bord.enCuisine, 3);
      expect(bord.pretes, 1);
      expect(bord.servies, 2);
      expect(bord.montantActif, 125000);
      expect(bord.cuisineCount, 4); // en préparation + prêtes
    });

    test('fromMap tolère une réponse vide', () {
      final RestaurantTableauBord bord =
          RestaurantTableauBord.fromMap(const <String, dynamic>{});
      expect(bord.tablesTotal, 0);
      expect(bord.cuisineCount, 0);
    });
  });

  // =========================================================================
  // 4. ERREURS SERVEUR & OPTIONS
  // =========================================================================

  group('RestaurantService — messages d\'erreur', () {
    test('messageErreur extrait le texte après « CODE| »', () {
      expect(
        RestaurantService.messageErreur(
            'TABLE_OCCUPEE|La table 5 a déjà une commande en cours.'),
        'La table 5 a déjà une commande en cours.',
      );
      expect(RestaurantService.messageErreur('DUREE_INVALIDE'),
          'DUREE_INVALIDE');
    });

    test('typeDepuisMessage classe droits / validation / inconnu', () {
      expect(RestaurantService.typeDepuisMessage('DROIT_REFUSE|…'),
          TypeErreurRestaurant.droits);
      expect(RestaurantService.typeDepuisMessage('COMMANDE_VIDE|…'),
          TypeErreurRestaurant.validation);
      expect(RestaurantService.typeDepuisMessage('STOCK_INSUFFISANT|…'),
          TypeErreurRestaurant.validation);
      expect(RestaurantService.typeDepuisMessage('BOOM|…'),
          TypeErreurRestaurant.inconnu);
    });
  });

  group('ProduitRestaurantOption', () {
    test('depuisRpc', () {
      final ProduitRestaurantOption produit =
          ProduitRestaurantOption.depuisRpc(<String, dynamic>{
        'id': 7,
        'nom': 'Poulet braisé',
        'prix_vente': 12000,
        'quantite': 20,
        'unite_mesure': 'plat',
      });

      expect(produit.id, 7);
      expect(produit.nom, 'Poulet braisé');
      expect(produit.prixVente, 12000);
      expect(produit.quantite, 20);
      expect(produit.uniteMesure, 'plat');
    });
  });
}
