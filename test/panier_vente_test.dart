// test/panier_vente_test.dart
//
// Tests unitaires du MODULE 8 — panier & validation de vente.
//
// Vérifient SANS réseau :
//   • l'API du panier demandée par le module : `ajouter(ligne)`,
//     `modifierQuantite(itemId)`, `supprimer(itemId)`, `total()`,
//     `nombreArticles()` — avec plafonnement au stock ;
//   • les champs de `LignePanier` : itemId, conditionnementId, nom, sousTotal ;
//   • les calculs d'encaissement : rendu, montant suffisant ;
//   • la lecture tolérante des réponses de `rpc_vente_valider` ;
//   • les messages d'erreur serveur (`STOCK_INSUFFISANT|…` → français) ;
//   • la quantité vendue reconstituée depuis l'historique (36 base → 3 fardes).
//
//     flutter test test/panier_vente_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/article_scanne.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/ligne_panier.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Conditionnement farde = Conditionnement(
    id: '3f2a0000-0000-0000-0000-000000000001',
    produitId: 123,
    libelle: 'Farde de 12',
    quantiteUnitesBase: 12,
    prixVente: 12000,
    qrCodeId: '9b8c0000-0000-0000-0000-0000000000aa',
  );

  const Article eau = Article(
    id: 123,
    nom: 'Eau Casino',
    prixVente: 1000,
    quantite: 34,
    uniteMesure: 'bouteille',
  );

  const ArticleScanne bouteille = ArticleScanne(article: eau);
  const ArticleScanne fardeEau =
      ArticleScanne(article: eau, conditionnement: farde);

  // =========================================================================
  // 1. API DU PANIER (MODULE 8)
  // =========================================================================

  group('PanierService — API du Module 8', () {
    final PanierService panier = PanierService.instance;

    setUp(panier.vider);

    test('ajouter(ligne) cumule puis modifierQuantite(itemId) ajuste', () {
      panier.ajouter(LignePanier(vendu: bouteille, quantite: 2));

      expect(panier.nombreLignes, 1);
      expect(panier.quantiteDe('PROD:123'), 2);
      expect(panier.total(), 2000);

      final double finale = panier.modifierQuantite('PROD:123', 5);
      expect(finale, 5);
      expect(panier.total(), 5000);
    });

    test('les champs de LignePanier suivent la spécification', () {
      final LignePanier ligne = LignePanier(vendu: fardeEau, quantite: 3);

      expect(ligne.itemId, 'COND:9b8c0000-0000-0000-0000-0000000000aa');
      expect(ligne.produitId, 123);
      expect(ligne.conditionnementId, farde.id);
      expect(ligne.nom, 'Eau Casino');
      expect(ligne.prixUnitaire, 12000);
      expect(ligne.quantite, 3);
      expect(ligne.sousTotal, 36000);
      expect(ligne.unitesBase, 36); // 3 fardes × 12 bouteilles
    });

    test('nombreArticles() compte les unités vendues', () {
      panier.ajouter(LignePanier(vendu: bouteille, quantite: 2));
      panier.ajouter(LignePanier(vendu: fardeEau, quantite: 1));

      expect(panier.nombreArticles(), 3);
    });

    test('supprimer(itemId) retire la ligne ; vider() efface tout', () {
      panier.ajouter(LignePanier(vendu: bouteille, quantite: 1));
      panier.ajouter(LignePanier(vendu: fardeEau, quantite: 1));

      panier.supprimer('PROD:123');
      expect(panier.nombreLignes, 1);
      expect(panier.total(), 12000);

      panier.vider();
      expect(panier.estVide, isTrue);
      expect(panier.total(), 0);
      expect(panier.nombreArticles(), 0);
    });

    test('les quantités restent plafonnées au stock (vente impossible en trop)',
        () {
      panier.ajouter(LignePanier(vendu: fardeEau, quantite: 4)); // stock = 2
      expect(panier.quantiteDe(fardeEau.code), 2);

      panier.ajouter(LignePanier(vendu: bouteille, quantite: 1));
      panier.modifierQuantite('PROD:123', 500);
      expect(panier.quantiteDe('PROD:123'), 34);
    });
  });

  // =========================================================================
  // 2. ENCAISSEMENT — CALCULS PURS
  // =========================================================================

  group('VenteService — calculs d\'encaissement', () {
    test('le rendu ne devient jamais négatif', () {
      expect(VenteService.calculerRendu(3000, 5000), 2000);
      expect(VenteService.calculerRendu(3000, 3000), 0);
      expect(VenteService.calculerRendu(3000, 1000), 0);
      expect(VenteService.calculerRendu(3000, null), 0);
    });

    test('montantSuffisant laisse passer l\'absence de saisie', () {
      expect(VenteService.montantSuffisant(3000, null), isTrue);
      expect(VenteService.montantSuffisant(3000, 3000), isTrue);
      expect(VenteService.montantSuffisant(3000, 2999), isFalse);
    });

    test('les codes serveur deviennent des messages français', () {
      expect(
        VenteService.messageErreur(
          'STOCK_INSUFFISANT|Stock insuffisant pour Eau Casino : 8 '
          'disponible(s), 12 demandé(s).',
        ),
        'Stock insuffisant pour Eau Casino : 8 disponible(s), 12 demandé(s).',
      );
      // Message sans code : renvoyé tel quel.
      expect(VenteService.messageErreur('Erreur inattendue'),
          'Erreur inattendue');
    });

    test('les libellés de mode de paiement sont prêts pour l\'affichage', () {
      expect(VenteService.libelleMode('especes'), 'Espèces');
      expect(VenteService.libelleMode('mobile_money'), 'Mobile Money');
      expect(VenteService.libelleMode('inconnu'), 'inconnu');
      expect(VenteService.modesPaiement.length, 5);
    });
  });

  // =========================================================================
  // 3. RÉPONSE DE LA TRANSACTION `rpc_vente_valider`
  // =========================================================================

  group('VenteEnregistree — lecture de la réponse serveur', () {
    test('le récapitulatif complet est correctement relu', () {
      final VenteEnregistree vente = VenteEnregistree.fromRpc(<String, dynamic>{
        'numero_vente': 'VTE-20260916-0001',
        'vente_uuid': 'aaaa0000-0000-0000-0000-0000000000bb',
        'total': 36000,
        'mode_paiement': 'especes',
        'montant_recu': 40000,
        'rendu': 4000,
        'date': '2026-09-16T10:30:00+00:00',
        'lignes': <dynamic>[
          <String, dynamic>{
            'produit_id': 123,
            'nom': 'Eau Casino',
            'conditionnement': 'Farde de 12',
            'unite': 'Farde de 12',
            'quantite_vendue': 3,
            'quantite_base': 36,
            'prix_unitaire': 12000,
            'total': 36000,
          },
        ],
      });

      expect(vente.numeroVente, 'VTE-20260916-0001');
      expect(vente.total, 36000);
      expect(vente.modePaiement, 'especes');
      expect(vente.rendu, 4000);
      expect(vente.lignes.single.nom, 'Eau Casino');
      expect(vente.lignes.single.conditionnement, 'Farde de 12');
      expect(vente.lignes.single.quantiteBase, 36);
      expect(vente.lignes.single.prixUnitaire, 12000);
    });

    test('une réponse en chaîne JSON est décodée', () {
      final Map<String, dynamic>? map = reponseRpcEnMap(
        '{"numero_vente":"VTE-20260916-0002","total":1000}',
      );
      expect(map?['numero_vente'], 'VTE-20260916-0002');
    });
  });

  // =========================================================================
  // 4. HISTORIQUE — QUANTITÉS VENDUES RECONSTITUÉES
  // =========================================================================

  group('LigneVenteHistorique — unités vendues', () {
    test('36 unités de base d\'une farde de 12 → 3 fardes', () {
      const LigneVenteHistorique ligne = LigneVenteHistorique(
        id: 1,
        produitId: 123,
        nom: 'Eau Casino',
        uniteBase: 'bouteille',
        conditionnementId: '3f2a0000-0000-0000-0000-000000000001',
        conditionnementLibelle: 'Farde de 12',
        conditionnementUnitesBase: 12,
        quantiteBase: 36,
        total: 36000,
      );

      expect(ligne.quantiteVendue, 3);
      expect(ligne.unite, 'Farde de 12');
    });

    test('une vente à l\'unité garde ses unités de base', () {
      const LigneVenteHistorique ligne = LigneVenteHistorique(
        id: 2,
        produitId: 123,
        nom: 'Eau Casino',
        uniteBase: 'bouteille',
        quantiteBase: 2,
        total: 2000,
      );

      expect(ligne.quantiteVendue, 2);
      expect(ligne.unite, 'bouteille');
    });
  });

  // =========================================================================
  // 🧾 MODULE 27 — LA CAISSE VOIT LES FORMATS AU PANIER
  // =========================================================================
  group('PanierService — lignes par article, formats compris', () {
    final PanierService panier = PanierService.instance;

    setUp(panier.vider);

    test('une farde au panier est bien comptée pour son article', () {
      panier.ajouterArticle(fardeEau, quantite: 2);

      // `quantiteProduit` ne compte QUE la ligne à l'unité : c'est ce qui
      // faisait croire à la caisse que rien n'était ajouté.
      expect(panier.quantiteProduit(123), 0);
      expect(panier.lignesProduit(123), hasLength(1));
      expect(panier.unitesBaseProduit(123), 24);
    });

    test('farde + bouteilles : la carte additionne les unités de base', () {
      panier.ajouterArticle(bouteille, quantite: 3);
      panier.ajouterArticle(fardeEau, quantite: 2);

      expect(panier.lignesProduit(123), hasLength(2));
      expect(panier.unitesBaseProduit(123), 27);
      expect(panier.quantiteProduit(123), 3);
    });

    test('un autre article n\'est pas compté', () {
      panier.ajouterArticle(fardeEau, quantite: 1);

      expect(panier.lignesProduit(999), isEmpty);
      expect(panier.unitesBaseProduit(999), 0);
    });

    test('changer la quantite d\'une farde conserve son format', () {
      panier.ajouterArticle(fardeEau, quantite: 1);
      final LignePanier ligne = panier.lignesProduit(123).first;

      // Stock : 34 bouteilles → 2 fardes complètes seulement.
      panier.definirQuantite(ligne.vendu, 5);

      final LignePanier apres = panier.lignesProduit(123).first;
      expect(apres.cle, ligne.cle);
      expect(apres.quantite, 2);
      expect(apres.conditionnementId, isNotNull);
      expect(panier.unitesBaseProduit(123), 24);
      // Aucune ligne « à l'unité » parasite n'a été créée.
      expect(panier.quantiteProduit(123), 0);
    });

    test('un conditionnement sans QR code a quand même une clé unique', () {
      const Conditionnement sansQr = Conditionnement(
        id: 'cond-sans-qr',
        produitId: 123,
        libelle: 'Carton de 24',
        quantiteUnitesBase: 24,
        prixVente: 24000,
        qrCodeId: '',
      );
      const ArticleScanne carton =
          ArticleScanne(article: eau, conditionnement: sansQr);

      expect(carton.code, 'COND:cond-sans-qr');
      expect(carton.code, isNot(fardeEau.code));

      panier.ajouterArticle(fardeEau, quantite: 1);
      panier.ajouterArticle(carton, quantite: 1);

      // Deux emballages distincts : deux lignes, et non un remplacement.
      expect(panier.lignesProduit(123), hasLength(2));
      expect(panier.unitesBaseProduit(123), 36);
    });
  });
}
