// test/pesee_test.dart
//
// 🥩 MODULE 16 (phase C6) — Tests PURS de la vente au poids (boucherie) :
// drapeau « vendable_au_poids » du modèle Article, pas de quantité du
// scanner (0,5 kg), lignes de panier décimales et catalogue des modules.
// Aucun réseau.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/article_scanne.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/ligne_panier.dart';
import 'package:biashara_yangu/models/module_activite.dart';

void main() {
  // =========================================================================
  // 1. LE DRAPEAU SUR L'ARTICLE
  // =========================================================================

  group('Article — vendableAuPoids', () {
    test('fromMap lit vendable_au_poids = true', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 12,
        'nom': 'Viande de bœuf (filet)',
        'prix_vente': 25000.0,
        'quantite': 8.5,
        'unite_mesure': 'kg',
        'vendable_au_poids': true,
      });

      expect(article.vendableAuPoids, isTrue);
      expect(article.uniteMesure, 'kg');
      expect(article.quantite, 8.5);
    });

    test('fromMap : absent ou false → vente à la pièce', () {
      final Article sansChamp = Article.fromMap(<String, dynamic>{
        'id': 13,
        'nom': 'Savon',
      });
      final Article explicitementFaux = Article.fromMap(<String, dynamic>{
        'id': 14,
        'nom': 'Savon',
        'vendable_au_poids': false,
      });

      expect(sansChamp.vendableAuPoids, isFalse);
      expect(explicitementFaux.vendableAuPoids, isFalse);
    });

    test('toMap envoie le drapeau (création / modification)', () {
      const Article article = Article(
        id: 1,
        nom: 'Poulet entier',
        vendableAuPoids: true,
      );

      expect(article.toMap()['vendable_au_poids'], isTrue);

      const Article nonPese = Article(id: 2, nom: 'Savon');
      expect(nonPese.toMap()['vendable_au_poids'], isFalse);
    });

    test('copyWith conserve et modifie le drapeau', () {
      const Article article = Article(
        id: 1,
        nom: 'Viande',
        vendableAuPoids: true,
      );

      expect(article.copyWith(nom: 'Viande hachée').vendableAuPoids, isTrue);
      expect(article.copyWith(vendableAuPoids: false).vendableAuPoids, isFalse);
    });
  });

  // =========================================================================
  // 2. LE SCANNER — PAS DE QUANTITÉ ET UNITÉ
  // =========================================================================

  group('ArticleScanne — vente au poids', () {
    const Article pese = Article(
      id: 7,
      nom: 'Viande de bœuf',
      prixVente: 25000,
      quantite: 12.5,
      uniteMesure: 'kg',
      vendableAuPoids: true,
    );

    const Article aLaPiece = Article(
      id: 8,
      nom: 'Savon',
      prixVente: 1500,
      quantite: 40,
      uniteMesure: 'pièce',
    );

    test('un article pesé est déclaré tel quel, pas de 0,5 kg', () {
      const ArticleScanne scanne = ArticleScanne(article: pese);

      expect(scanne.vendableAuPoids, isTrue);
      expect(scanne.pasQuantite, 0.5);
      expect(scanne.uniteVente, 'kg');
      expect(scanne.uniteVentePlurielle(2), 'kg');
    });

    test('un article à la pièce garde le pas de 1', () {
      const ArticleScanne scanne = ArticleScanne(article: aLaPiece);

      expect(scanne.vendableAuPoids, isFalse);
      expect(scanne.pasQuantite, 1);
    });

    test('un CONDITIONNEMENT reste vendu à la pièce (farde, carton…)', () {
      const ArticleScanne scanne = ArticleScanne(
        article: pese,
        conditionnement: Conditionnement(
          id: 'c-1',
          produitId: 7,
          libelle: 'Caisse de 10 kg',
          quantiteUnitesBase: 10,
          prixVente: 240000,
          qrCodeId: '11111111-1111-1111-1111-111111111111',
        ),
      );

      expect(scanne.vendableAuPoids, isFalse,
          reason: 'un emballage se vend à la pièce');
      expect(scanne.pasQuantite, 1);
    });

    test('le stock pesé accepte les décimales sans arrondi inférieur', () {
      const ArticleScanne scanne = ArticleScanne(article: pese);

      // 12,5 kg en stock → maximum vendable 12,5 (pas 12).
      expect(scanne.quantiteMaxVendable, 12.5);
      expect(scanne.enRupture, isFalse);
    });
  });

  // =========================================================================
  // 3. LA LIGNE DE PANIER DÉCIMALE
  // =========================================================================

  group('LignePanier — poids décimal', () {
    test('0,75 kg × 25 000 = 18 750', () {
      const ArticleScanne scanne = ArticleScanne(
        article: Article(
          id: 7,
          nom: 'Viande de bœuf',
          prixVente: 25000,
          quantite: 12.5,
          uniteMesure: 'kg',
          vendableAuPoids: true,
        ),
      );

      final LignePanier ligne = LignePanier(vendu: scanne, quantite: 0.75);

      expect(ligne.total, 18750);
      expect(ligne.sousTotal, 18750);
      expect(ligne.unitesBase, 0.75, reason: '1 kg vendu = 1 kg de stock');
    });

    test('arrondi métier : 0,333 kg × 25 000 ≈ 8 325', () {
      const ArticleScanne scanne = ArticleScanne(
        article: Article(
          id: 7,
          nom: 'Viande de bœuf',
          prixVente: 25000,
          quantite: 12.5,
          uniteMesure: 'kg',
          vendableAuPoids: true,
        ),
      );

      expect(LignePanier(vendu: scanne, quantite: 0.333).total,
          closeTo(8325, 0.01));
    });

    test('la clé du panier reste le code produit (cumul au scan)', () {
      const ArticleScanne scanne = ArticleScanne(
        article: Article(id: 7, nom: 'Viande', vendableAuPoids: true),
      );

      expect(LignePanier(vendu: scanne).cle, 'PROD:7');
    });
  });

  // =========================================================================
  // 4. CATALOGUE — LE MODULE `pesee` EST LIVRÉ
  // =========================================================================

  group('Catalogue des modules', () {
    test('le module « vente au poids » est disponible (plus « bientôt »)', () {
      final ModuleActivite? module = ModuleActivite.parCode(ModuleCode.pesee);

      expect(module, isNotNull);
      expect(module!.disponible, isTrue);
      expect(module.libelle, 'Vente au poids');
    });

    test('seul le module variantes reste « bientôt »', () {
      expect(
        ModuleActivite.catalogue
            .where((ModuleActivite m) => !m.disponible)
            .map((ModuleActivite m) => m.code),
        <String>[ModuleCode.variantes],
      );
    });
  });
}
