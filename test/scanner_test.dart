// test/scanner_test.dart
//
// Tests unitaires du MODULE 7 — scanner vendeur.
//
// Vérifient SANS réseau :
//   • les calculs d'affichage d'un article scanné (prix du conditionnement,
//     unités de base, stock vendable, rupture) ;
//   • le plafonnement des quantités du panier partagé (jamais plus que le
//     stock) et le cumul par code scanné ;
//   • le rejet des QR codes inconnus AVANT tout appel réseau ;
//   • l'historique glissant des 5 derniers scans.
//
//     flutter test test/scanner_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/article_scanne.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/scanner_service.dart';

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
    categorie: 'Boissons',
    prixVente: 1000,
    quantite: 34,
    uniteMesure: 'bouteille',
  );

  const ArticleScanne bouteille = ArticleScanne(article: eau);
  const ArticleScanne fardeEau =
      ArticleScanne(article: eau, conditionnement: farde);

  // =========================================================================
  // 1. L'ARTICLE SCANNÉ (PRIX ET STOCK RELUS EN BASE)
  // =========================================================================

  group('ArticleScanne — prix et stock', () {
    test('une bouteille scanée encode « PROD:123 » et se vend au prix de base',
        () {
      expect(bouteille.code, 'PROD:123');
      expect(bouteille.prixUnitaire, 1000);
      expect(bouteille.uniteVente, 'bouteille');
      expect(bouteille.unitesBaseParVente, 1);
      expect(bouteille.quantiteMaxVendable, 34);
      expect(bouteille.enRupture, isFalse);
      expect(bouteille.resumeStock(), 'Stock : 34 bouteilles');
    });

    test('une farde scanée encode « COND:<uuid> » et se vend au prix de la '
        'farde (pas au prix × quantité forcé)', () {
      expect(fardeEau.code, 'COND:9b8c0000-0000-0000-0000-0000000000aa');
      expect(fardeEau.estConditionnement, isTrue);
      expect(fardeEau.prixUnitaire, 12000);
      expect(fardeEau.uniteVente, 'Farde de 12');
      expect(fardeEau.unitesBaseParVente, 12);
      expect(fardeEau.libelleComplet, 'Eau Casino — Farde de 12');
    });

    test('seuls les emballages COMPLETS sont vendables (34 bouteilles → '
        '2 fardes)', () {
      expect(fardeEau.quantiteMaxVendable, 2);
      expect(fardeEau.unitesBasePour(2), 24);
      expect(fardeEau.sousTotal(2), 24000);
      expect(fardeEau.sousTotalTexte(2), '24 000 CDF');
      expect(fardeEau.resumeStock(), 'Stock : 34 bouteilles — 2 × Farde de 12.');
    });

    test('un emballage incomplet passe en rupture (10 bouteilles < farde '
        'de 12)', () {
      const ArticleScanne presque = ArticleScanne(
        article: Article(id: 7, nom: 'Eau Casino', quantite: 10),
        conditionnement: farde,
      );

      expect(presque.quantiteMaxVendable, 0);
      expect(presque.enRupture, isTrue);
    });

    test('l\'unité de base est pluralisée, le conditionnement jamais', () {
      expect(bouteille.uniteVentePlurielle(2), 'bouteilles');
      expect(bouteille.uniteVentePlurielle(1), 'bouteille');
      expect(fardeEau.uniteVentePlurielle(2), 'Farde de 12');
    });
  });

  // =========================================================================
  // 2. LE PANIER PARTAGÉ (PLAFONNÉ AU STOCK)
  // =========================================================================

  group('PanierService — cumul et plafonnement', () {
    final PanierService panier = PanierService.instance;

    setUp(panier.vider);

    test('ajouter cumule les quantités du même code', () {
      panier.ajouterArticle(bouteille, quantite: 2);
      panier.ajouterArticle(bouteille, quantite: 1);

      expect(panier.nombreLignes, 1);
      expect(panier.quantiteProduit(123), 3);
      expect(panier.total(), 3000);
    });

    test('bouteille et farde du même article restent deux lignes', () {
      panier.ajouterArticle(bouteille, quantite: 1);
      panier.ajouterArticle(fardeEau, quantite: 1);

      expect(panier.nombreLignes, 2);
      expect(panier.total(), 13000);
      expect(panier.quantiteDeArticle(fardeEau), 1);
    });

    test('la quantité est plafonnée au stock vendable', () {
      panier.ajouterArticle(fardeEau, quantite: 5); // 5 fardes demandées…
      expect(panier.quantiteDeArticle(fardeEau), 2); // …2 disponibles

      panier.definirQuantite(bouteille, 100);
      expect(panier.quantiteProduit(123), 34); // stock de bouteilles
    });

    test('retirer puis vider', () {
      panier.ajouterArticle(bouteille, quantite: 1);
      panier.ajouterArticle(fardeEau, quantite: 1);

      panier.retirer('PROD:123');
      expect(panier.nombreLignes, 1);
      expect(panier.estVide, isFalse);

      panier.vider();
      expect(panier.estVide, isTrue);
      expect(panier.total(), 0);
    });
  });

  // =========================================================================
  // 3. RÉSOLUTION DES CODES (REJET HORS LIGNE DES CODES INCONNUS)
  // =========================================================================

  group('ScannerService — codes inconnus', () {
    test('un QR étranger est refusé sans toucher au réseau', () async {
      await expectLater(
        ScannerService.instance.resoudre('https://exemple.com'),
        throwsA(
          isA<ScannerException>().having(
            (ScannerException e) => e.type,
            'type',
            TypeErreurScan.formatInconnu,
          ),
        ),
      );
    });

    test('« PROD:abc » (identifiant non numérique) est refusé', () async {
      await expectLater(
        ScannerService.instance.resoudre('PROD:abc'),
        throwsA(
          isA<ScannerException>().having(
            (ScannerException e) => e.type,
            'type',
            TypeErreurScan.formatInconnu,
          ),
        ),
      );
    });

    test('« COND:pas-un-uuid » est refusé', () async {
      await expectLater(
        ScannerService.instance.resoudre('COND:pas-un-uuid'),
        throwsA(
          isA<ScannerException>().having(
            (ScannerException e) => e.type,
            'type',
            TypeErreurScan.formatInconnu,
          ),
        ),
      );
    });
  });

  // =========================================================================
  // 4. HISTORIQUE DES 5 DERNIERS SCANS
  // =========================================================================

  group('ScannerService — historique', () {
    final ScannerService scanner = ScannerService.instance;

    setUp(scanner.viderHistorique);

    test('les doublons sont fusionnés et le plus récent passe en tête', () {
      scanner.enregistrerScan(bouteille);
      scanner.enregistrerScan(fardeEau);
      scanner.enregistrerScan(bouteille);

      expect(scanner.historique.value.length, 2);
      expect(scanner.historique.value.first.code, 'PROD:123');
      expect(scanner.historique.value.last.code, fardeEau.code);
    });

    test('l\'historique ne dépasse jamais 5 entrées', () {
      for (int id = 1; id <= 7; id++) {
        scanner.enregistrerScan(
          ArticleScanne(
            article: Article(id: id, nom: 'Article $id', quantite: 5),
          ),
        );
      }

      expect(scanner.historique.value.length, 5);
      expect(scanner.historique.value.first.code, 'PROD:7');
      expect(
        scanner.historique.value.map((ArticleScanne e) => e.code).toList(),
        <String>['PROD:7', 'PROD:6', 'PROD:5', 'PROD:4', 'PROD:3'],
      );
    });
  });
}
