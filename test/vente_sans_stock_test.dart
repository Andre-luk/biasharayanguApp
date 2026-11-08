// test/vente_sans_stock_test.dart
//
// ♾️ MODULE 31 — VENDRE UN ARTICLE QUI NE SE COMPTE PAS.
//
// Certains produits ne peuvent pas être comptés : eau au robinet, service,
// article fabriqué à la demande, vente au poids approximatif. Ils doivent
// pouvoir être vendus même avec un stock à zéro, sans plafond dans le panier,
// et sans jamais bloquer la caisse.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/article_scanne.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/produit.dart';
import 'package:biashara_yangu/services/panier_service.dart';

const Article _eauRobinet = Article(
  id: 900,
  nom: 'Eau au robinet (20 L)',
  prixVente: 500,
  quantite: 0, // rien à compter
  uniteMesure: 'bidon',
  stockIllimite: true,
);

const Article _savon = Article(
  id: 901,
  nom: 'Savon',
  prixVente: 1200,
  quantite: 4,
  uniteMesure: 'pièce',
);

const ArticleScanne _eauScannee = ArticleScanne(article: _eauRobinet);
const ArticleScanne _savonScanne = ArticleScanne(article: _savon);

void main() {
  final PanierService panier = PanierService.instance;

  setUp(panier.vider);

  group('Article sans suivi de stock', () {
    test('un produit non comptable se vend même avec un stock nul', () {
      expect(_eauScannee.sansSuiviDeStock, isTrue);
      expect(_eauScannee.enRupture, isFalse);

      final double ajoutee = panier.ajouterArticle(_eauScannee, quantite: 1);
      expect(ajoutee, 1);
      expect(panier.lignes, hasLength(1));
    });

    test('la quantité n\'est jamais plafonnée', () {
      // 500 unités alors que le stock vaut 0 : c'est permis.
      final double ajoutee = panier.ajouterArticle(_eauScannee, quantite: 500);
      expect(ajoutee, 500);
      expect(panier.quantiteTotale, 500);
    });

    test('un article normal reste plafonné au stock', () {
      // 4 en stock : on ne peut pas en mettre 10.
      final double ajoutee = panier.ajouterArticle(_savonScanne, quantite: 10);
      expect(ajoutee, 4);
      expect(_savonScanne.enRupture, isFalse);
    });

    test('un article en rupture réelle est bien détecté', () {
      const Article vide = Article(
        id: 902,
        nom: 'Rupture',
        prixVente: 100,
        quantite: 0,
        uniteMesure: 'pièce',
      );
      expect(const ArticleScanne(article: vide).enRupture, isTrue);
    });

    test('un format (farde) d\'un article non comptable reste vendable', () {
      const Conditionnement farde = Conditionnement(
        id: 'c-1',
        produitId: 900,
        libelle: 'Pack de 12',
        quantiteUnitesBase: 12,
        prixVente: 5500,
        qrCodeId: 'qr-1',
      );
      const ArticleScanne pack =
          ArticleScanne(article: _eauRobinet, conditionnement: farde);

      expect(pack.quantiteMaxVendable, greaterThan(1000));
      expect(panier.ajouterArticle(pack, quantite: 3), 3);
    });
  });

  group('Produit local — stock non suivi', () {
    test('le drapeau survit à toMap / fromMap', () {
      final Produit p = Produit(
        nom: 'Eau au robinet',
        categorie: 'Boissons',
        prixAchat: 0,
        prixVente: 500,
        quantite: 0,
        uniteMesure: 'bidon',
        stockIllimite: true,
      );

      expect(p.toMap()['stock_illimite'], 1);

      final Produit relu = Produit.fromMap(<String, dynamic>{
        ...p.toMap(),
        'id': 3,
      });
      expect(relu.stockIllimite, isTrue);
    });

    test('un produit ordinaire reste suivi', () {
      final Produit p = Produit(
        nom: 'Savon',
        categorie: 'Hygiène',
        prixAchat: 800,
        prixVente: 1200,
        quantite: 4,
        uniteMesure: 'pièce',
      );

      expect(p.toMap()['stock_illimite'], 0);
      expect(Produit.fromMap(p.toMap()).stockIllimite, isFalse);
    });

    test('copyWith conserve le drapeau', () {
      final Produit p = Produit(
        nom: 'Service',
        categorie: '',
        prixAchat: 0,
        prixVente: 2000,
        quantite: 0,
        uniteMesure: 'service',
        stockIllimite: true,
      );

      expect(p.copyWith(nom: 'Service de lavage').stockIllimite, isTrue);
    });
  });
}
