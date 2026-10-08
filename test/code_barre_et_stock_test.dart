// test/code_barre_et_stock_test.dart
//
// 🏷️ CORRECTIF 59 — CODE-BARRES DU PRODUIT & ALERTE DE STOCK.
//
// Vérifient SANS réseau :
//   • le champ `code_barre` du modèle Article (lecture, null quand absent) ;
//   • la règle « UNE SEULE alerte par franchissement du seuil » ;
//   • la rédaction des messages de notification (titre, corps, rupture) ;
//   • le comportement du seuil désactivé (0) : seule la rupture alerte.
//
//     flutter test test/code_barre_et_stock_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/statut_stock.dart';
import 'package:biashara_yangu/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =======================================================================
  // 1. LE CHAMP code_barre DU MODÈLE
  // =======================================================================

  group('Article — code-barres (correctif 59)', () {
    test('fromMap lit `code_barre`', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 7,
        'nom': 'Lait en poudre',
        'code_barre': ' 6001234567890 ',
      });

      //  La base stocke un code sans espaces (le correctif 59 normalise) :
      //  le modèle rend la valeur telle quelle, sans la retoucher.
      expect(article.codeBarre, '6001234567890');
    });

    test('fromMap tolère l\'absence de la colonne', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 8,
        'nom': 'Sucre',
      });

      expect(article.codeBarre, isNull);
    });

    test('copyWith conserve le code-barres quand on ne le change pas', () {
      const Article base = Article(id: 1, nom: 'Riz', codeBarre: '123');
      expect(base.copyWith(prixVente: 500).codeBarre, '123');
    });
  });

  // =======================================================================
  // 2. LE FRANCHISSEMENT DU SEUIL
  // =======================================================================

  group('NotificationService — aFranchiLeSeuil', () {
    test('prévient quand le stock PASSE sous le seuil', () {
      expect(
        NotificationService.aFranchiLeSeuil(avant: 12, apres: 4, seuil: 5),
        isTrue,
      );
    });

    test('prévient en arrivant EXACTEMENT sur le seuil', () {
      expect(
        NotificationService.aFranchiLeSeuil(avant: 9, apres: 5, seuil: 5),
        isTrue,
      );
    });

    test('NE prévient PAS à chaque vente d\'un article déjà en alerte', () {
      //  4 → 3, seuil 5 : le franchissement a déjà eu lieu, on se tait.
      expect(
        NotificationService.aFranchiLeSeuil(avant: 4, apres: 3, seuil: 5),
        isFalse,
      );
      expect(
        NotificationService.aFranchiLeSeuil(avant: 3, apres: 2, seuil: 5),
        isFalse,
      );
    });

    test('NE prévient PAS tant que le stock reste au-dessus', () {
      expect(
        NotificationService.aFranchiLeSeuil(avant: 30, apres: 20, seuil: 5),
        isFalse,
      );
    });

    test('seuil désactivé (0) : seule la RUPTURE alerte', () {
      expect(
        NotificationService.aFranchiLeSeuil(avant: 3, apres: 1, seuil: 0),
        isFalse,
      );
      expect(
        NotificationService.aFranchiLeSeuil(avant: 2, apres: 0, seuil: 0),
        isTrue,
      );
    });

    test('une ENTRÉE de stock (hausse) n\'alerte jamais', () {
      expect(
        NotificationService.aFranchiLeSeuil(avant: 2, apres: 50, seuil: 5),
        isFalse,
      );
    });
  });

  // =======================================================================
  // 3. LES MESSAGES
  // =======================================================================

  group('NotificationService — messages de stock', () {
    test('titre : nom du produit, ou titre neutre s\'il est vide', () {
      expect(NotificationService.titreStock('Riz 5 kg'),
          contains('Riz 5 kg'));
      expect(NotificationService.titreStock('   '), '📦 Stock faible');
    });

    test('corps : quantité, unité et seuil', () {
      final String corps = NotificationService.messageStock(
        quantite: 3,
        seuil: 5,
        unite: 'bouteille',
      );

      expect(corps, contains('3 bouteille'));
      expect(corps, contains('seuil'));
      expect(corps, contains('5'));
    });

    test('corps : annonce la RUPTURE à zéro', () {
      final String corps = NotificationService.messageStock(
        quantite: 0,
        seuil: 5,
        unite: 'pièce',
      );

      expect(corps, contains('RUPTURE'));
    });

    test('nombre lisible : pas de zéro inutile, virgule française', () {
      expect(NotificationService.nombreLisible(12), '12');
      expect(NotificationService.nombreLisible(0.5), '0,50');
    });
  });

  // =======================================================================
  // 4. COHÉRENCE AVEC LE STATUT DE STOCK EXISTANT
  // =======================================================================

  group('Cohérence seuil / statut de stock', () {
    test('un stock au seuil est « Faible », donc l\'alerte est légitime', () {
      expect(
        StatutStock.depuisStock(quantite: 5, seuilAlerte: 5),
        StatutStock.faible,
      );
    });

    test('le franchissement correspond bien au passage en alerte', () {
      expect(
        StatutStock.depuisStock(quantite: 6, seuilAlerte: 5),
        StatutStock.ok,
      );
      expect(
        StatutStock.depuisStock(quantite: 5, seuilAlerte: 5).estAlerte,
        isTrue,
      );
    });
  });
}
