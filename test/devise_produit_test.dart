// test/devise_produit_test.dart
//
// 💵 MODULE 29 — LA DEVISE DE CHAQUE ARTICLE.
//
// Une boutique peut vendre un article en dollars et l'autre en francs.
// Ces tests verrouillent les règles :
//   • un article sans devise suit la devise de l'entreprise ;
//   • le prix saisi n'est JAMAIS modifié en base ;
//   • la conversion utilise le taux du jour ;
//   • les francs sont arrondis à l'unité, les dollars à 2 décimales.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/devise.dart';
import 'package:biashara_yangu/services/devise_service.dart';
import 'package:biashara_yangu/utils/devise_produit.dart';

void main() {
  // Taux de test : 1 USD = 2 800 CDF, entreprise tenue en CDF.
  void configurer({
    Devise entreprise = Devise.cdf,
    double taux = 2800,
  }) {
    DeviseService.instance.etat.value = EtatDevise(
      devise: entreprise,
      tauxUsdCdf: taux,
    );
  }

  setUp(() => configurer());

  group('deviseArticle', () {
    test('un article sans devise suit celle de l\'entreprise', () {
      configurer();
      expect(deviseArticle(null), Devise.cdf);
      expect(deviseArticle(''), Devise.cdf);
      expect(deviseArticle('   '), Devise.cdf);
    });

    test('la devise de l\'article est respectée', () {
      configurer();
      expect(deviseArticle('USD'), Devise.usd);
      expect(deviseArticle('usd'), Devise.usd, reason: 'casse ignorée');
      expect(deviseArticle('CDF'), Devise.cdf);
    });

    test('une devise inconnue retombe sur le franc congolais', () {
      configurer();
      expect(deviseArticle('EUR'), Devise.cdf);
    });

    test('entreprise en USD : un article sans devise suit les dollars', () {
      configurer(entreprise: Devise.usd);
      expect(deviseArticle(null), Devise.usd);
      configurer(); // retour à l'état standard pour les tests suivants
    });
  });

  group('deviseDifferente', () {
    test('vrai seulement quand l\'article est dans une autre devise', () {
      configurer();
      expect(deviseDifferente(null), isFalse);
      expect(deviseDifferente('CDF'), isFalse);
      expect(deviseDifferente('USD'), isTrue);
    });
  });

  group('versDeviseEntreprise', () {
    test('un prix déjà dans la devise de l\'entreprise est inchangé', () {
      configurer();
      expect(versDeviseEntreprise(15000, 'CDF'), 15000);
      expect(versDeviseEntreprise(15000, null), 15000);
    });

    test('un prix en dollars est converti au taux du jour', () {
      configurer();
      expect(versDeviseEntreprise(10, 'USD'), 28000);
      expect(versDeviseEntreprise(2.5, 'USD'), 7000);
    });

    test('les francs n\'ont pas de centimes : arrondi à l\'unité', () {
      configurer(taux: 2833);
      // 1,5 × 2833 = 4249,5 → 4250 (jamais « 4 249,5 CDF »).
      expect(versDeviseEntreprise(1.5, 'USD'), 4250);
    });

    test('entreprise en USD : un prix en francs est divisé par le taux', () {
      configurer(entreprise: Devise.usd, taux: 2800);
      expect(versDeviseEntreprise(28000, 'CDF'), 10);
      configurer();
    });

    test('un autre taux change bien le résultat', () {
      configurer(taux: 3000);
      expect(versDeviseEntreprise(10, 'USD'), 30000);
      configurer();
    });
  });

  group('prixArticle', () {
    test('devise de l\'article avec équivalence entre parenthèses', () {
      configurer();
      final String texte = prixArticle(10, 'USD');
      expect(texte, contains('10'));
      expect(texte, contains('\$'));
      expect(texte, contains('28 000'));
    });

    test('sans équivalence sur demande', () {
      configurer();
      expect(prixArticle(10, 'USD', avecEquivalence: false), '10,00 \$');
    });

    test('prix en francs : aucun doublon', () {
      configurer();
      final String texte = prixArticle(1500, 'CDF');
      expect(texte, '1 500 CDF');
      expect(texte, isNot(contains('≈')));
    });

    test('article sans devise : prix simple dans la devise de l\'entreprise', () {
      configurer();
      expect(prixArticle(1500, null), '1 500 CDF');
    });
  });

  group('tauxDuJour', () {
    test('suit la configuration de l\'entreprise', () {
      configurer(taux: 2900);
      expect(tauxDuJour, 2900);
      configurer();
      expect(tauxDuJour, 2800);
    });
  });
}
