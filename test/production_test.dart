// test/production_test.dart
//
// 🥖 MODULE 16 (phase C5) — Tests PURS de la boulangerie : matières
// premières (alertes), productions (quantités, pertes, surplus, coût),
// consommations, tableau de bord et messages d'erreur. Aucun réseau.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/matiere_premiere.dart';
import 'package:biashara_yangu/models/production.dart';
import 'package:biashara_yangu/models/production_tableau_bord.dart';
import 'package:biashara_yangu/services/production_service.dart';

void main() {
  // =========================================================================
  // 1. MATIÈRES PREMIÈRES
  // =========================================================================

  group('MatierePremiere', () {
    test('fromMap lit la ligne complète', () {
      final MatierePremiere matiere = MatierePremiere.fromMap(<String, dynamic>{
        'id': 'm-1',
        'nom': 'Farine T55',
        'unite': 'kg',
        'stock': 32.5,
        'seuil_alerte': 20,
        'prix_unitaire': 1500.0,
        'actif': true,
      });

      expect(matiere.id, 'm-1');
      expect(matiere.nom, 'Farine T55');
      expect(matiere.unite, 'kg');
      expect(matiere.stock, 32.5);
      expect(matiere.seuilAlerte, 20);
      expect(matiere.prixUnitaire, 1500);
      expect(matiere.designation, 'Farine T55 (kg)');
    });

    test('enAlerte : stock ≤ seuil', () {
      const MatierePremiere sousSeuil = MatierePremiere(
        id: 'x',
        nom: 'Levure',
        stock: 3,
        seuilAlerte: 5,
      );
      const MatierePremiere pile = MatierePremiere(
        id: 'y',
        nom: 'Levure',
        stock: 5,
        seuilAlerte: 5,
      );
      const MatierePremiere ok = MatierePremiere(
        id: 'z',
        nom: 'Levure',
        stock: 8,
        seuilAlerte: 5,
      );

      expect(sousSeuil.enAlerte, isTrue);
      expect(pile.enAlerte, isTrue, reason: 'le seuil lui-même est une alerte');
      expect(ok.enAlerte, isFalse);
    });

    test('fromMap tolère les champs absents', () {
      final MatierePremiere matiere =
          MatierePremiere.fromMap(<String, dynamic>{'id': 'x'});

      expect(matiere.nom, 'Matière');
      expect(matiere.unite, 'kg');
      expect(matiere.stock, 0);
      expect(matiere.actif, isTrue);
    });
  });

  // =========================================================================
  // 2. STATUTS & MODÈLE PRODUCTION
  // =========================================================================

  group('StatutProduction', () {
    test('codes serveur reconnus + repli', () {
      expect(StatutProduction.fromCode('en_cours'), StatutProduction.enCours);
      expect(StatutProduction.fromCode('terminee'), StatutProduction.terminee);
      expect(StatutProduction.fromCode('annulee'), StatutProduction.annulee);
      expect(StatutProduction.fromCode(null), StatutProduction.enCours);
      expect(StatutProduction.fromCode('BIDON'), StatutProduction.enCours);
    });

    test('estEnCours / estClose / libellés', () {
      expect(StatutProduction.enCours.estEnCours, isTrue);
      expect(StatutProduction.enCours.estClose, isFalse);
      expect(StatutProduction.terminee.estClose, isTrue);
      expect(StatutProduction.annulee.estClose, isTrue);
      expect(StatutProduction.terminee.libelle, 'Terminée');
    });
  });

  group('Production', () {
    Map<String, dynamic> ligne({Map<String, dynamic>? extra}) {
      return <String, dynamic>{
        'id': 'prod-1',
        'produit_id': 42,
        'numero': 'PROD-20261012-0001',
        'quantite_prevue': 100,
        'quantite_reelle': 96,
        'pertes': 4,
        'cout_matieres': 48000.0,
        'cout_unitaire': 500.0,
        'statut': 'terminee',
        'note': 'Fournée du matin',
        'produits': <String, dynamic>{'nom': 'Pain baguette'},
        'consommations_production': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'c-1',
            'matiere_id': 'm-1',
            'quantite': 30,
            'cout_unitaire': 1500.0,
            'total': 45000.0,
            'matieres_premieres': <String, dynamic>{
              'nom': 'Farine T55',
              'unite': 'kg',
            },
          },
          <String, dynamic>{
            'id': 'c-2',
            'matiere_id': 'm-2',
            'quantite': 1.5,
            'cout_unitaire': 2000.0,
            'total': 3000.0,
            'matieres_premieres': <String, dynamic>{
              'nom': 'Levure',
              'unite': 'kg',
            },
          },
        ],
        ...?extra,
      };
    }

    test('fromMap avec jointure produit + matières', () {
      final Production production = Production.fromMap(ligne());

      expect(production.id, 'prod-1');
      expect(production.produitId, 42);
      expect(production.produitNom, 'Pain baguette');
      expect(production.numero, 'PROD-20261012-0001');
      expect(production.quantitePrevue, 100);
      expect(production.quantiteReelle, 96);
      expect(production.pertes, 4);
      expect(production.coutMatieres, 48000);
      expect(production.coutUnitaire, 500);
      expect(production.statut, StatutProduction.terminee);
      expect(production.consommations, hasLength(2));
      expect(production.consommations.first.libelle, 'Farine T55');
      expect(production.consommations.first.unite, 'kg');
      expect(production.consommations.first.total, 45000);
    });

    test('pertes affichées vs surplus', () {
      final Production pertes = Production.fromMap(ligne());
      expect(pertes.pertesAffichees, 4);
      expect(pertes.surplus, 0);

      final Production surplus =
          Production.fromMap(ligne(extra: <String, dynamic>{'pertes': -3}));
      expect(surplus.pertesAffichees, 0);
      expect(surplus.surplus, 3);
    });

    test('fromMap sans jointure garde des valeurs sûres', () {
      final Production production = Production.fromMap(<String, dynamic>{
        'id': 'x',
        'produit_id': 1,
        'quantite_prevue': 10,
      });

      expect(production.produitNom, '');
      expect(production.statut, StatutProduction.enCours);
      expect(production.consommations, isEmpty);
    });

    test('copyWith ne change que les champs demandés', () {
      final Production production = Production.fromMap(ligne());
      final Production maj = production.copyWith(
        statut: StatutProduction.annulee,
        coutMatieres: 0,
      );

      expect(maj.statut, StatutProduction.annulee);
      expect(maj.coutMatieres, 0);
      expect(maj.produitNom, production.produitNom);
      expect(maj.quantiteReelle, production.quantiteReelle);
    });

    test('nombre() formate sans zéros inutiles', () {
      expect(Production.nombre(10), '10');
      expect(Production.nombre(10.5), '10.5');
      expect(Production.nombre(10.250), '10.25');
      expect(Production.nombre(0.100), '0.1');
    });
  });

  group('ConsommationProduction', () {
    test('fromMap lit la jointure matière', () {
      final ConsommationProduction ligne =
          ConsommationProduction.fromMap(<String, dynamic>{
        'id': 'c-9',
        'matiere_id': 'm-9',
        'quantite': 2.5,
        'cout_unitaire': 1200.0,
        'total': 3000.0,
        'matieres_premieres': <String, dynamic>{
          'nom': 'Sucre',
          'unite': 'kg',
        },
      });

      expect(ligne.id, 'c-9');
      expect(ligne.matiereId, 'm-9');
      expect(ligne.libelle, 'Sucre');
      expect(ligne.unite, 'kg');
      expect(ligne.quantite, 2.5);
      expect(ligne.total, 3000);
    });
  });

  // =========================================================================
  // 3. TABLEAU DE BORD
  // =========================================================================

  group('TableauBordProduction', () {
    test('fromMap lit les compteurs et les dernières productions', () {
      final TableauBordProduction bord =
          TableauBordProduction.fromMap(<String, dynamic>{
        'ok': true,
        'matieres': 6,
        'matieres_alerte': 2,
        'productions_jour': 3,
        'quantite_jour': 288.5,
        'pertes_jour': 11.5,
        'cout_jour': 144000.0,
        'dernieres': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'prod-1',
            'numero': 'PROD-20261012-0001',
            'produit': 'Pain baguette',
            'statut': 'terminee',
            'quantite_prevue': 100,
            'quantite_reelle': 96,
            'pertes': 4,
            'cout_matieres': 48000.0,
            'cout_unitaire': 500.0,
            'date': '12/10/2026 06:30',
          },
        ],
      });

      expect(bord.matieres, 6);
      expect(bord.matieresAlerte, 2);
      expect(bord.productionsJour, 3);
      expect(bord.quantiteJour, 288.5);
      expect(bord.pertesJour, 11.5);
      expect(bord.coutJour, 144000);
      expect(bord.dernieres, hasLength(1));
      expect(bord.dernieres.first.produit, 'Pain baguette');
      expect(bord.dernieres.first.date, '12/10/2026 06:30');
    });

    test('fromMap vide : tout à zéro', () {
      final TableauBordProduction bord =
          TableauBordProduction.fromMap(const <String, dynamic>{});

      expect(bord.matieres, 0);
      expect(bord.matieresAlerte, 0);
      expect(bord.productionsJour, 0);
      expect(bord.dernieres, isEmpty);
    });
  });

  // =========================================================================
  // 4. MESSAGES D'ERREUR SERVEUR (« CODE|texte »)
  // =========================================================================

  group('ProductionService — messages d\'erreur', () {
    test('messageErreur extrait le texte après « CODE| »', () {
      expect(
        ProductionService.messageErreur(
            'STOCK_MATIERE_INSUFFISANT|Stock insuffisant pour « Farine ».'),
        'Stock insuffisant pour « Farine ».',
      );
      expect(ProductionService.messageErreur('Erreur simple'), 'Erreur simple');
    });

    test('typeDepuisMessage classe droits / validation / inconnu', () {
      expect(
        ProductionService.typeDepuisMessage('DROIT_REFUSE|Refusé.'),
        TypeErreurProduction.droits,
      );
      expect(
        ProductionService.typeDepuisMessage('NOM_EXISTE|Doublon.'),
        TypeErreurProduction.validation,
      );
      expect(
        ProductionService.typeDepuisMessage(
            'STOCK_MATIERE_INSUFFISANT|Pas assez.'),
        TypeErreurProduction.validation,
      );
      expect(
        ProductionService.typeDepuisMessage('PRODUCTION_INTROUVABLE|Absente.'),
        TypeErreurProduction.validation,
      );
      expect(
        ProductionService.typeDepuisMessage('OBSCUR|Quelque chose.'),
        TypeErreurProduction.inconnu,
      );
    });
  });
}
