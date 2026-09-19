// test/variantes_test.dart
//
// 👕 MODULE 16 (phase C8) — Tests PURS des variantes (mode) : lecture /
// écriture du jsonb `attributs`, résumé lisible, recherche par variante
// et catalogue des modules. Aucun réseau.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/services/article_service.dart';

void main() {
  // =========================================================================
  // 1. LECTURE DU JSONB
  // =========================================================================

  group('Article — attributs (variantes)', () {
    test('fromMap lit l\'objet jsonb taille / couleur / marque', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 12,
        'nom': 'Chemise',
        'prix_vente': 45000.0,
        'attributs': <String, dynamic>{
          'taille': 'M',
          'couleur': 'Bleu',
          'marque': 'Casino',
        },
      });

      expect(article.aVariantes, isTrue);
      expect(article.taille, 'M');
      expect(article.couleur, 'Bleu');
      expect(article.marque, 'Casino');
    });

    test('attributs absent ou vide → aucune variante', () {
      final Article sansChamp = Article.fromMap(<String, dynamic>{
        'id': 13,
        'nom': 'Savon',
      });
      final Article objetVide = Article.fromMap(<String, dynamic>{
        'id': 14,
        'nom': 'Savon',
        'attributs': <String, dynamic>{},
      });

      expect(sansChamp.aVariantes, isFalse);
      expect(sansChamp.attributs, isEmpty);
      expect(objetVide.aVariantes, isFalse);
    });

    test('valeurs vidées du formulaire : clés écartées', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 15,
        'nom': 'Pantalon',
        'attributs': <String, dynamic>{
          'taille': '42',
          'couleur': '',
          'marque': '   ',
        },
      });

      expect(article.attributs, <String, String>{'taille': '42'});
      expect(article.taille, '42');
      expect(article.couleur, isNull);
    });

    test('valeurs numériques converties en texte (« 42 »)', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 16,
        'nom': 'Chaussures',
        'attributs': <String, dynamic>{'taille': 42},
      });

      expect(article.taille, '42');
    });

    test('type inattendu (liste) : ignoré sans planter', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 17,
        'nom': 'Chemise',
        'attributs': <dynamic>['taille', 'M'],
      });

      expect(article.aVariantes, isFalse);
    });

    test('toMap envoie les attributs (création / modification)', () {
      const Article article = Article(
        id: 1,
        nom: 'Chemise',
        attributs: <String, String>{'taille': 'M', 'couleur': 'Bleu'},
      );

      expect(article.toMap()['attributs'],
          <String, String>{'taille': 'M', 'couleur': 'Bleu'});
    });

    test('copyWith conserve et modifie les attributs', () {
      const Article article = Article(
        id: 1,
        nom: 'Chemise',
        attributs: <String, String>{'couleur': 'Bleu'},
      );

      expect(article.copyWith(nom: 'Chemise MC').couleur, 'Bleu');
      expect(
        article.copyWith(attributs: <String, String>{'couleur': 'Rouge'})
            .couleur,
        'Rouge',
      );
    });

    test('resumeVariantes : ordre taille → couleur → marque → autres', () {
      const Article article = Article(
        id: 1,
        nom: 'Chemise',
        attributs: <String, String>{
          'marque': 'Casino',
          'couleur': 'Bleu',
          'taille': 'M',
          'matiere': 'Coton',
        },
      );

      expect(article.resumeVariantes, 'M · Bleu · Casino · Coton');
    });

    test('resumeVariantes vide quand aucune variante', () {
      const Article article = Article(id: 1, nom: 'Savon');
      expect(article.resumeVariantes, '');
    });
  });

  // =========================================================================
  // 2. RECHERCHE PAR VARIANTE
  // =========================================================================

  group('ArticleService.filtrer — variantes', () {
    final List<Article> articles = <Article>[
      const Article(
        id: 1,
        nom: 'Chemise',
        categorie: 'Habillement',
        attributs: <String, String>{'taille': 'XXL', 'couleur': 'Fuchsia'},
      ),
      const Article(
        id: 2,
        nom: 'Pantalon',
        categorie: 'Habillement',
        attributs: <String, String>{'taille': '42', 'couleur': 'Noir'},
      ),
      const Article(id: 3, nom: 'Savon', categorie: 'Hygiène'),
    ];

    test('recherche par taille', () {
      final List<Article> resultats =
          ArticleService.filtrer(articles, recherche: 'xxl');
      expect(resultats, hasLength(1));
      expect(resultats.first.id, 1);
    });

    test('recherche par couleur', () {
      final List<Article> resultats =
          ArticleService.filtrer(articles, recherche: 'noir');
      expect(resultats, hasLength(1));
      expect(resultats.first.id, 2);
    });

    test('recherche par taille numérique', () {
      final List<Article> resultats =
          ArticleService.filtrer(articles, recherche: '42');
      expect(resultats, hasLength(1));
      expect(resultats.first.id, 2);
    });

    test('aucune correspondance de variante : liste vide', () {
      expect(ArticleService.filtrer(articles, recherche: 'vert'), isEmpty);
    });

    test('le filtre catégorie reste prioritaire sur les variantes', () {
      final List<Article> resultats = ArticleService.filtrer(
        articles,
        recherche: 'xxl',
        categorie: 'Hygiène',
      );
      expect(resultats, isEmpty);
    });
  });

  // =========================================================================
  // 3. CATALOGUE — LE MODULE `variantes` EST LIVRÉ
  // =========================================================================

  group('Catalogue des modules', () {
    test('le module variantes est disponible (plus « bientôt »)', () {
      final ModuleActivite? module =
          ModuleActivite.parCode(ModuleCode.variantes);

      expect(module, isNotNull);
      expect(module!.disponible, isTrue);
      expect(module.libelle, 'Variantes (taille / couleur)');
    });

    test('TOUS les modules du catalogue sont désormais livrés', () {
      expect(
        ModuleActivite.catalogue
            .where((ModuleActivite m) => !m.disponible),
        isEmpty,
      );
    });
  });
}
