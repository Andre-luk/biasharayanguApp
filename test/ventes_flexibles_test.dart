// test/ventes_flexibles_test.dart
//
// MODULE 25 — flexibilité commerciale de la boutique.
//
// Ces tests couvrent les CALCULS et les GARDE-FOUS de l'application :
//   • vente normale au prix catalogue ;
//   • vente négociée (2 500 → 2 200) ;
//   • négociation refusée quand elle est interdite ;
//   • réduction globale (430 → 400) ;
//   • cadeau commercial (valeur, unités de stock) ;
//   • cumul négociation + réduction + cadeau ;
//   • lecture du reçu renvoyé par le serveur.
//
// Les mêmes règles sont revérifiées côté SQL (`rpc_vente_valider`) : ces tests
// garantissent que l'écran n'affiche pas un montant que le serveur refusera.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/article_scanne.dart';
import 'package:biashara_yangu/models/ligne_panier.dart';
import 'package:biashara_yangu/models/parametres_vente.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart';
import 'package:biashara_yangu/services/panier_service.dart';

/// Paramètres « tout ouvert » pour le propriétaire.
const ParametresVente proprietaire = ParametresVente(
  negociationActivee: true,
  negociationMaxPct: 20,
  reductionActivee: true,
  reductionMaxPct: 20,
  cadeauxActifs: true,
  estProprietaire: true,
  peutNegocier: true,
  peutReduire: true,
  peutOffrir: true,
);

/// Paramètres d'un collaborateur : 10 % de marge de manœuvre.
const ParametresVente vendeurAutorise = ParametresVente(
  negociationActivee: true,
  negociationMaxPct: 10,
  reductionActivee: true,
  reductionMaxPct: 10,
  cadeauxActifs: true,
  peutNegocier: true,
  peutReduire: true,
  peutOffrir: true,
);

/// Paramètres d'une boutique qui n'a rien autorisé.
const ParametresVente interdit = ParametresVente();

LignePanier _ligne({
  required int id,
  required String nom,
  required double prix,
  double quantite = 1,
  double stock = 100,
}) {
  return LignePanier(
    vendu: ArticleScanne(
      article: Article(
        id: id,
        nom: nom,
        prixVente: prix,
        quantite: stock,
      ),
    ),
    quantite: quantite,
  );
}

void main() {
  setUp(() => PanierService.instance.vider());

  group('1-2. Vente normale et vente négociée', () {
    test('une vente au prix catalogue reste inchangée', () {
      PanierService.instance
          .ajouter(_ligne(id: 1, nom: 'Savon', prix: 2500));

      expect(PanierService.instance.total(), 2500);
      expect(PanierService.instance.montantNegociation(), 0);
      expect(PanierService.instance.totalAPayer(), 2500);
      expect(PanierService.instance.nombreLignesNegociees, 0);
    });

    test('2 500 négocié à 2 200 : 300 accordés, 2 200 facturés', () {
      final LignePanier ligne =
          _ligne(id: 1, nom: 'Savon', prix: 2500);
      PanierService.instance.ajouter(ligne);

      PanierService.instance.definirPrixNegocie(ligne.cle, 2200);

      final LignePanier apres = PanierService.instance.ligne(ligne.cle)!;
      expect(apres.prixNegocie, 2200);
      expect(apres.prixUnitaireEffectif, 2200);
      // Le prix catalogue de l'article n'a PAS bougé.
      expect(apres.prixUnitaire, 2500);
      expect(PanierService.instance.total(), 2200);
      expect(PanierService.instance.montantNegociation(), 300);
      expect(PanierService.instance.totalCatalogue(), 2500);
      expect(PanierService.instance.totalAPayer(), 2200);
    });

    test('changer la quantité conserve le prix négocié', () {
      final LignePanier ligne =
          _ligne(id: 1, nom: 'Savon', prix: 2500);
      PanierService.instance.ajouter(ligne);
      PanierService.instance.definirPrixNegocie(ligne.cle, 2200);

      PanierService.instance.modifierQuantite(ligne.cle, 3);

      final LignePanier apres = PanierService.instance.ligne(ligne.cle)!;
      expect(apres.quantite, 3);
      expect(apres.prixNegocie, 2200);
      expect(PanierService.instance.total(), 6600);
      expect(PanierService.instance.montantNegociation(), 900);
    });

    test('un prix supérieur au catalogue est accepté par le panier mais '
        'refusé par la règle', () {
      final LignePanier ligne =
          _ligne(id: 1, nom: 'Savon', prix: 2500);
      PanierService.instance.ajouter(ligne);
      PanierService.instance.definirPrixNegocie(ligne.cle, 3000);

      expect(PanierService.instance.ligne(ligne.cle)!.prixNegocie, isNull);
      expect(
        ReglesVenteFlexible.verifierPrixNegocie(
          prixCatalogue: 2500,
          prixNegocie: 3000,
          parametres: proprietaire,
        ),
        isNotNull,
      );
    });
  });

  group('3. Négociation interdite', () {
    test('boutique sans autorisation : la règle refuse', () {
      expect(
        ReglesVenteFlexible.verifierPrixNegocie(
          prixCatalogue: 2500,
          prixNegocie: 2200,
          parametres: interdit,
        ),
        contains('désactivée'),
      );
      expect(ReglesVenteFlexible.negociationPossible(interdit), isFalse);
    });

    test('collaborateur non autorisé : le serveur dirait non', () {
      const ParametresVente nonAutorise = ParametresVente(
        negociationActivee: true,
        negociationMaxPct: 10,
        peutNegocier: false,
      );
      expect(
        ReglesVenteFlexible.verifierPrixNegocie(
          prixCatalogue: 2500,
          prixNegocie: 2200,
          parametres: nonAutorise,
        ),
        contains('désactivée'),
      );
    });

    test('au-delà de la limite du propriétaire : refusé', () {
      // 10 % de 2 500 = plancher 2 250. 2 200 est en dessous.
      expect(
        ReglesVenteFlexible.verifierPrixNegocie(
          prixCatalogue: 2500,
          prixNegocie: 2200,
          parametres: vendeurAutorise,
        ),
        contains('Prix minimum'),
      );
      // 2 300 reste dans la limite.
      expect(
        ReglesVenteFlexible.verifierPrixNegocie(
          prixCatalogue: 2500,
          prixNegocie: 2300,
          parametres: vendeurAutorise,
        ),
        isNull,
      );
    });

    test('prix plancher absolu prioritaire sur le pourcentage', () {
      const ParametresVente avecPlancher = ParametresVente(
        negociationActivee: true,
        negociationMaxPct: 50,
        negociationPrixMin: 2400,
        peutNegocier: true,
      );
      expect(
        ReglesVenteFlexible.prixPlancher(
          prixCatalogue: 2500,
          parametres: avecPlancher,
        ),
        2400,
      );
    });
  });

  group('4. Réduction sur le panier', () {
    test('430 − 30 = 400', () {
      PanierService.instance
        ..ajouter(_ligne(id: 1, nom: 'A', prix: 230))
        ..ajouter(_ligne(id: 2, nom: 'B', prix: 200));

      expect(PanierService.instance.total(), 430);

      PanierService.instance.definirRemise(30);

      expect(PanierService.instance.montantRemise(), 30);
      expect(PanierService.instance.totalAPayer(), 400);
    });

    test('réduction en pourcentage', () {
      PanierService.instance
        ..ajouter(_ligne(id: 1, nom: 'A', prix: 430));
      PanierService.instance.definirRemise(10, type: TypeReduction.pourcentage);

      expect(PanierService.instance.montantRemise(), 43);
      expect(PanierService.instance.totalAPayer(), 387);
    });

    test('une réduction ne peut jamais dépasser le panier', () {
      expect(
        ReglesVenteFlexible.remiseEnMontant(
          base: 430,
          valeur: 900,
          type: TypeReduction.montant,
        ),
        430,
      );
    });

    test('réduction refusée quand la boutique ne l\'autorise pas', () {
      expect(
        ReglesVenteFlexible.verifierRemise(
          base: 430,
          valeur: 30,
          type: TypeReduction.montant,
          parametres: interdit,
        ),
        contains('désactivées'),
      );
    });

    test('réduction au-delà du plafond du vendeur : refusée', () {
      // 10 % de 430 = 43 maximum.
      expect(
        ReglesVenteFlexible.verifierRemise(
          base: 430,
          valeur: 60,
          type: TypeReduction.montant,
          parametres: vendeurAutorise,
        ),
        contains('Réduction maximale'),
      );
      expect(
        ReglesVenteFlexible.verifierRemise(
          base: 430,
          valeur: 40,
          type: TypeReduction.montant,
          parametres: vendeurAutorise,
        ),
        isNull,
      );
    });

    test('vider le panier efface la réduction', () {
      PanierService.instance
        ..ajouter(_ligne(id: 1, nom: 'A', prix: 430))
        ..definirRemise(30);
      expect(PanierService.instance.totalAPayer(), 400);

      PanierService.instance.vider();

      expect(PanierService.instance.remiseValeur, 0);
      expect(PanierService.instance.totalAPayer(), 0);
    });
  });

  group('5. Cadeau commercial', () {
    test('un cadeau a une valeur et sort les bonnes unités de stock', () {
      PanierService.instance.ajouterCadeau(
        const CadeauPanier(
          produitId: 7,
          nom: 'Bouteille 1,5 L',
          prixCatalogue: 500,
          quantite: 2,
          quantiteBase: 2,
        ),
      );

      expect(PanierService.instance.cadeaux.length, 1);
      expect(PanierService.instance.valeurCadeaux(), 1000);
      expect(PanierService.instance.quantiteCadeaux, 2);
      // Le cadeau ne change pas le total à payer.
      expect(PanierService.instance.totalAPayer(), 0);
    });

    test('deux cadeaux du même produit se cumulent', () {
      const CadeauPanier cadeau = CadeauPanier(
        produitId: 7,
        nom: 'Bouteille',
        prixCatalogue: 500,
        quantite: 1,
        quantiteBase: 1,
      );
      PanierService.instance
        ..ajouterCadeau(cadeau)
        ..ajouterCadeau(cadeau);

      expect(PanierService.instance.cadeaux.length, 1);
      expect(PanierService.instance.quantiteCadeaux, 2);
    });

    test('le payload envoyé au serveur ne contient que le nécessaire', () {
      const CadeauPanier cadeau = CadeauPanier(
        produitId: 7,
        nom: 'Farde',
        prixCatalogue: 6000,
        quantite: 1,
        quantiteBase: 12,
        conditionnementId: 'cond-1',
      );
      final Map<String, dynamic> payload = cadeau.versPayload();

      expect(payload['produit_id'], 7);
      expect(payload['quantite'], 1);
      expect(payload['quantite_base'], 12);
      expect(payload['conditionnement_id'], 'cond-1');
      // Le prix n'est jamais transmis : le serveur relit le catalogue.
      expect(payload.containsKey('prix'), isFalse);
    });
  });

  group('6. Cumul négociation + réduction + cadeau', () {
    test('430 initial, 1 ligne négociée, 30 de réduction, un cadeau', () {
      final LignePanier a = _ligne(id: 1, nom: 'A', prix: 250);
      final LignePanier b = _ligne(id: 2, nom: 'B', prix: 180);
      PanierService.instance
        ..ajouter(a)
        ..ajouter(b);

      expect(PanierService.instance.total(), 430);

      // Négociation : A passe de 250 à 200 (−50).
      PanierService.instance.definirPrixNegocie(a.cle, 200);
      expect(PanierService.instance.total(), 380);

      // Réduction globale de 30.
      PanierService.instance.definirRemise(30);
      expect(PanierService.instance.montantRemise(), 30);

      // Cadeau.
      PanierService.instance.ajouterCadeau(
        const CadeauPanier(
          produitId: 9,
          nom: 'Savon offert',
          prixCatalogue: 500,
          quantite: 1,
          quantiteBase: 1,
        ),
      );

      expect(PanierService.instance.totalCatalogue(), 430);
      expect(PanierService.instance.montantNegociation(), 50);
      expect(PanierService.instance.montantRemise(), 30);
      expect(PanierService.instance.totalAPayer(), 350);
      expect(PanierService.instance.valeurCadeaux(), 500);
    });
  });

  group('7. Facture', () {
    test('le reçu du serveur distingue les trois montants', () {
      final VenteEnregistree vente = VenteEnregistree.fromRpc(
        <String, dynamic>{
          'numero_vente': 'VTE-20261105-0007',
          'vente_uuid': 'uuid-1',
          'total': 350,
          'total_initial': 430,
          'negociation': 50,
          'remise': 30,
          'remise_type': 'montant',
          'valeur_cadeaux': 500,
          'mode_paiement': 'especes',
          'montant_recu': 500,
          'rendu': 150,
          'lignes': <Map<String, dynamic>>[
            <String, dynamic>{
              'produit_id': 1,
              'nom': 'A',
              'unite': 'unité',
              'quantite_vendue': 1,
              'quantite_base': 1,
              'prix_unitaire': 200,
              'total': 200,
            },
          ],
          'cadeaux': <Map<String, dynamic>>[
            <String, dynamic>{
              'produit_id': 9,
              'nom': 'Savon offert',
              'quantite': 1,
              'quantite_base': 1,
              'valeur': 500,
              'cout': 320,
            },
          ],
        },
      );

      expect(vente.total, 350);
      expect(vente.totalInitial, 430);
      expect(vente.montantNegociation, 50);
      expect(vente.remise, 30);
      expect(vente.valeurCadeaux, 500);
      expect(vente.cadeaux.single.nom, 'Savon offert');
      expect(vente.cadeaux.single.cout, 320);
      expect(vente.estFlexible, isTrue);
    });

    test('une vente ordinaire n\'est pas marquée flexible', () {
      final VenteEnregistree vente = VenteEnregistree.fromRpc(
        <String, dynamic>{
          'numero_vente': 'VTE-20261105-0008',
          'vente_uuid': 'uuid-2',
          'total': 2500,
          'mode_paiement': 'especes',
          'lignes': <Map<String, dynamic>>[],
        },
      );
      expect(vente.estFlexible, isFalse);
      expect(vente.totalInitial, 2500);
    });
  });

  group('8. Seuil de validation du responsable', () {
    test('au-delà du seuil, le vendeur ne peut pas conclure', () {
      const ParametresVente avecSeuil = ParametresVente(
        negociationActivee: true,
        negociationMaxPct: 50,
        reductionActivee: true,
        reductionMaxPct: 50,
        validationSeuil: 100,
        peutNegocier: true,
        peutReduire: true,
      );

      expect(
        ReglesVenteFlexible.validationRequise(
          montantAccorde: 80,
          parametres: avecSeuil,
        ),
        isFalse,
      );
      expect(
        ReglesVenteFlexible.validationRequise(
          montantAccorde: 150,
          parametres: avecSeuil,
        ),
        isTrue,
      );
      // Sans seuil configuré, aucune validation n'est exigée.
      expect(
        ReglesVenteFlexible.validationRequise(
          montantAccorde: 10000,
          parametres: interdit,
        ),
        isFalse,
      );
    });
  });

  group('Lecture des réglages', () {
    test('les droits effectifs viennent du serveur', () {
      final ParametresVente p = ParametresVente.fromMap(
        <String, dynamic>{
          'negociation_activee': true,
          'negociation_max_pct': 15,
          'negociation_collaborateurs': <String>['u1'],
          'reduction_activee': false,
          'reduction_max_pct': 5,
          'cadeaux_actifs': true,
          'cadeau_collaborateurs': <String>[],
          'est_proprietaire': false,
          'peut_negocier': true,
          'peut_reduire': false,
          'peut_offrir': true,
        },
      );

      expect(p.negociationMaxPct, 15);
      expect(p.negociationCollaborateurs, <String>['u1']);
      expect(p.peutNegocier, isTrue);
      expect(p.peutReduire, isFalse);
      expect(p.peutOffrir, isTrue);
      expect(p.aQuelqueChose, isTrue);
      expect(interdit.aQuelqueChose, isFalse);
    });
  });
}
