// test/article_test.dart
//
// Tests unitaires du MODULE 5 — Gestion des articles & conditionnements.
//
// Ces tests ne touchent ni au réseau ni à Supabase : ils vérifient les
// modèles (parsing PostgREST), la formule de stock du cahier des charges,
// l'aperçu des conditionnements et le filtrage de la liste des articles.
//
//     flutter test test/article_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/categorie.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/mouvement_article.dart';
import 'package:biashara_yangu/services/article_service.dart';

void main() {
  // =========================================================================
  // 1. PARSING DES ARTICLES (public.produits)
  // =========================================================================

  group('Article.fromMap', () {
    test('convertit une ligne réelle de public.produits', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 121,
        'nom': 'tomate taste',
        'categorie': '',
        'prix_achat': 800,
        'prix_vente': 1000,
        'quantite': 34,
        'unite_mesure': 'unité',
        'photo': null,
        'description': null,
        'owner_id': '9cf448fc-1a8b-461b-ae71-0cd9ab9acf65',
        'created_at': '2026-09-16T15:44:23.436061+00:00',
        'updated_at': '2026-09-16T15:44:23.436061+00:00',
      });

      expect(article.id, 121);
      expect(article.nom, 'tomate taste');
      expect(article.categorie, '');
      expect(article.prixAchat, 800.0);
      expect(article.prixVente, 1000.0);
      expect(article.quantite, 34.0);
      expect(article.uniteMesure, 'unité');
      expect(article.photo, isNull);
      expect(article.ownerId, '9cf448fc-1a8b-461b-ae71-0cd9ab9acf65');
      expect(article.createdAt, isNotNull);
      expect(article.conditionnements, isEmpty);
      expect(article.nombreConditionnements, 0);
    });

    test('tolère les types renvoyés par PostgREST (int pour real, string)', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': '5',
        'nom': 'Riz',
        'prix_vente': '2500.5',
        'quantite': 10,
        'unite_mesure': null,
      });

      expect(article.id, 5);
      expect(article.prixVente, 2500.5);
      expect(article.quantite, 10.0);
      // Valeur de repli quand l'unité est absente.
      expect(article.uniteMesure, 'unité');
      expect(article.categorie, '');
    });

    test('toMap n\'envoie ni id ni owner_id (posés par le service)', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 12,
        'nom': 'Eau',
      });

      final Map<String, dynamic> map = article.toMap();
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('owner_id'), isFalse);
      expect(map['nom'], 'Eau');
      expect(map['quantite'], 0.0);
    });
  });

  // =========================================================================
  // 2. CONDITIONNEMENTS
  // =========================================================================

  group('Conditionnement', () {
    test('fromMap lit la ligne complète (QR code auto-généré)', () {
      final Conditionnement c = Conditionnement.fromMap(<String, dynamic>{
        'id': '3f2a0000-0000-0000-0000-000000000001',
        'produit_id': 121,
        'libelle': 'Farde de 12',
        'quantite_unites_base': 12,
        'prix_vente': 12000,
        'qr_code_id': '9b8c0000-0000-0000-0000-0000000000aa',
        'code_barre_texte': null,
        'created_at': '2026-09-16T16:00:00+00:00',
      });

      expect(c.id, '3f2a0000-0000-0000-0000-000000000001');
      expect(c.produitId, 121);
      expect(c.libelle, 'Farde de 12');
      expect(c.quantiteUnitesBase, 12.0);
      expect(c.prixVente, 12000.0);
      expect(c.qrCodeId, '9b8c0000-0000-0000-0000-0000000000aa');
      expect(c.codeBarreTexte, isNull);
    });

    test('toMap ne renvoie ni id ni qr_code_id (générés par la base)', () {
      final Conditionnement c = Conditionnement.fromMap(<String, dynamic>{
        'id': 'c1',
        'produit_id': 1,
        'libelle': 'Carton de 24',
        'quantite_unites_base': 24,
        'prix_vente': 24000,
        'qr_code_id': 'q1',
      });

      final Map<String, dynamic> map = c.toMap();
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('qr_code_id'), isFalse);
      expect(map['produit_id'], 1);
      expect(map['libelle'], 'Carton de 24');
    });

    test('conversion exemplaires → unités de base', () {
      const Conditionnement c = Conditionnement(
        id: 'c1',
        produitId: 1,
        libelle: 'Farde de 12',
        quantiteUnitesBase: 12,
        prixVente: 12000,
        qrCodeId: 'q1',
      );

      expect(c.versUnitesBase(3), 36.0);
      expect(c.versUnitesBase(0.5), 6.0);
    });

    test('exemplaires entiers contenus dans un stock', () {
      const Conditionnement c = Conditionnement(
        id: 'c1',
        produitId: 1,
        libelle: 'Farde de 12',
        quantiteUnitesBase: 12,
        prixVente: 12000,
        qrCodeId: 'q1',
      );

      expect(c.exemplairesContenusDans(34), 2); // 34 = 2 × 12 + reste 10
      expect(c.exemplairesContenusDans(12), 1);
      expect(c.exemplairesContenusDans(11), 0);
      expect(c.exemplairesContenusDans(0), 0);
    });

    test('aperçu : « 1 Farde de 12 = 12 bouteilles pour 12 000 CDF »', () {
      const Conditionnement farde = Conditionnement(
        id: 'c1',
        produitId: 1,
        libelle: 'Farde de 12',
        quantiteUnitesBase: 12,
        prixVente: 12000,
        qrCodeId: 'q1',
      );
      const Conditionnement carton = Conditionnement(
        id: 'c2',
        produitId: 1,
        libelle: 'Carton de 24',
        quantiteUnitesBase: 24,
        prixVente: 24000,
        qrCodeId: 'q2',
      );

      expect(
        farde.apercu(uniteBase: 'bouteille'),
        '1 Farde de 12 = 12 bouteilles pour 12 000 CDF',
      );
      expect(
        carton.apercu(uniteBase: 'bouteille'),
        '1 Carton de 24 = 24 bouteilles pour 24 000 CDF',
      );
    });

    test('aperçu avec quantité décimale et unité invariable (kg)', () {
      expect(
        Conditionnement.apercuTexte(
          libelle: 'Demi-kilo',
          quantiteUnitesBase: 0.5,
          prixVente: 1500,
          uniteBase: 'kg',
        ),
        '1 Demi-kilo = 0,5 kg pour 1 500 CDF',
      );
    });

    test('pluriel simple des unités', () {
      expect(Conditionnement.pluriel('bouteille', 12), 'bouteilles');
      expect(Conditionnement.pluriel('bouteille', 1), 'bouteille');
      expect(Conditionnement.pluriel('unité', 2), 'unités');
      expect(Conditionnement.pluriel('kg', 5), 'kg');
      expect(Conditionnement.pluriel('m', 5), 'm');
      expect(Conditionnement.pluriel('', 5), '');
    });
  });

  // =========================================================================
  // 3. FORMULE DE STOCK DU CAHIER DES CHARGES
  // =========================================================================

  group('Stock total (unités de base)', () {
    test('stock total = stock base + exemplaires × unités par conditionnement', () {
      expect(
        Article.stockTotal(
          stockBase: 34,
          nombreExemplaires: 10,
          quantiteUnitesBase: 12,
        ),
        154.0,
      );

      expect(
        Article.stockTotal(
          stockBase: 34,
          nombreExemplaires: 0,
          quantiteUnitesBase: 12,
        ),
        34.0,
      );
    });

    test('stockTotalAvecConditionnement reprend le stock actuel', () {
      const Article article = Article(
        id: 1,
        nom: 'Eau Casino',
        quantite: 34,
        uniteMesure: 'bouteille',
      );
      const Conditionnement farde = Conditionnement(
        id: 'c1',
        produitId: 1,
        libelle: 'Farde de 12',
        quantiteUnitesBase: 12,
        prixVente: 12000,
        qrCodeId: 'q1',
      );

      expect(article.stockTotalAvecConditionnement(farde, nombreExemplaires: 3),
          70.0);
    });
  });

  // =========================================================================
  // 4. FILTRAGE DE LA LISTE (recherche nom / code)
  // =========================================================================

  group('ArticleService.filtrer', () {
    const Conditionnement farde = Conditionnement(
      id: 'c1',
      produitId: 1,
      libelle: 'Farde de 12',
      quantiteUnitesBase: 12,
      prixVente: 12000,
      qrCodeId: '9b8c00aa-code-qr-eau',
      codeBarreTexte: '6130000001',
    );

    final List<Article> articles = <Article>[
      const Article(
        id: 1,
        nom: 'Eau Casino',
        categorie: 'Boissons',
        prixVente: 1000,
        quantite: 34,
        uniteMesure: 'bouteille',
        conditionnements: <Conditionnement>[farde],
      ),
      const Article(
        id: 2,
        nom: 'Savon Alpha',
        categorie: '',
        prixVente: 4500,
      ),
    ];

    test('sans filtre, tous les articles sont renvoyés', () {
      expect(ArticleService.filtrer(articles), hasLength(2));
      expect(
        ArticleService.filtrer(articles, recherche: '   '),
        hasLength(2),
      );
    });

    test('recherche par nom (insensible à la casse)', () {
      final List<Article> resultats =
          ArticleService.filtrer(articles, recherche: 'eau');
      expect(resultats, hasLength(1));
      expect(resultats.first.nom, 'Eau Casino');
    });

    test('recherche par code-barre du conditionnement', () {
      final List<Article> resultats =
          ArticleService.filtrer(articles, recherche: '6130000001');
      expect(resultats, hasLength(1));
      expect(resultats.first.id, 1);
    });

    test('recherche par QR code et par libellé du conditionnement', () {
      expect(ArticleService.filtrer(articles, recherche: 'code-qr'), hasLength(1));
      expect(ArticleService.filtrer(articles, recherche: 'farde'), hasLength(1));
    });

    test('filtre par catégorie (normalisation casse / espaces)', () {
      final List<Article> resultats =
          ArticleService.filtrer(articles, categorie: '  boissons ');
      expect(resultats, hasLength(1));
      expect(resultats.first.nom, 'Eau Casino');
    });

    test('recherche et catégorie se combinent', () {
      expect(
        ArticleService.filtrer(articles,
            recherche: 'eau', categorie: 'Boissons'),
        hasLength(1),
      );
      expect(
        ArticleService.filtrer(articles,
            recherche: 'savon', categorie: 'Boissons'),
        isEmpty,
      );
    });

    test('aucun résultat pour une recherche inconnue', () {
      expect(ArticleService.filtrer(articles, recherche: 'zzz'), isEmpty);
    });
  });

  // =========================================================================
  // 5. HISTORIQUE DES MOUVEMENTS
  // =========================================================================

  group('MouvementArticle', () {
    test('entrées et sorties sont signées', () {
      final MouvementArticle entree = MouvementArticle(
        id: 'approvisionnement-1',
        source: SourceMouvement.approvisionnement,
        quantite: 24,
        date: DateTime(2026, 9, 15),
      );
      final MouvementArticle sortie = MouvementArticle(
        id: 'vente-1',
        source: SourceMouvement.vente,
        quantite: -2,
        date: DateTime(2026, 9, 16),
      );

      expect(entree.estEntree, isTrue);
      expect(entree.estSortie, isFalse);
      expect(sortie.estEntree, isFalse);
      expect(sortie.estSortie, isTrue);
    });

    test('tri du plus récent au plus ancien, sans date en dernier', () {
      final List<MouvementArticle> tries = MouvementArticle.recentsDAbord(
        <MouvementArticle>[
          MouvementArticle(
            id: 'a',
            source: SourceMouvement.ajustement,
            quantite: -1,
            date: DateTime(2026, 9, 10),
          ),
          MouvementArticle(
            id: 'sans-date',
            source: SourceMouvement.ajustement,
            quantite: 1,
          ),
          MouvementArticle(
            id: 'b',
            source: SourceMouvement.approvisionnement,
            quantite: 10,
            date: DateTime(2026, 9, 16),
          ),
        ],
      );

      expect(tries.map((MouvementArticle m) => m.id),
          <String>['b', 'a', 'sans-date']);
    });
  });

  // =========================================================================
  // 6. CATÉGORIES
  // =========================================================================

  group('Categorie', () {
    test('fromMap / toMap', () {
      final Categorie categorie =
          Categorie.fromMap(<String, dynamic>{'id': '7', 'nom': 'Boissons'});

      expect(categorie.id, 7);
      expect(categorie.nom, 'Boissons');
      expect(categorie.toMap(), <String, dynamic>{'nom': 'Boissons'});
    });

    test('normalisation pour comparaison', () {
      expect(Categorie.normaliser('  Boissons '), 'boissons');
      expect(
        Categorie.normaliser('Boissons') == Categorie.normaliser(' boissons'),
        isTrue,
      );
    });
  });
}
