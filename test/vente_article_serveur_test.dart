// test/vente_article_serveur_test.dart
//
// 🔴 CORRECTIF 77 — « Article n° 83 introuvable : il a peut-être été supprimé. »
//
// La vente échouait depuis la caisse parce que le panier envoyait
// l'identifiant **local** de SQLite (1, 2, 3… 83) au lieu du numéro de
// l'article dans la base (503, 504…). Le serveur, lui, avait raison : il ne
// trouvait pas d'article portant ce numéro.
//
// Ces tests verrouillent la règle : TOUT ce qui part vers le serveur utilise
// `Produit.idServeur`, jamais `Produit.id`.
//
//     flutter test test/vente_article_serveur_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article_scanne.dart';
import 'package:biashara_yangu/models/produit.dart';
import 'package:biashara_yangu/services/vente_service.dart';

Produit _produit({String? supabaseId, int? id = 83}) {
  return Produit(
    id: id,
    nom: 'Eau Dasani',
    categorie: 'Eau',
    prixAchat: 300,
    prixVente: 500,
    quantite: 150,
    uniteMesure: 'bouteille',
    ownerId: 'boutique-1',
    supabaseId: supabaseId,
  );
}

void main() {
  group('Produit.idServeur — le seul numéro qui parle au serveur', () {
    test('lit le numéro de la base depuis supabase_id', () {
      expect(_produit(supabaseId: '503').idServeur, 503);
      expect(_produit(supabaseId: '503').synchronise, isTrue);
    });

    test('article jamais envoyé : aucun numéro serveur', () {
      expect(_produit(supabaseId: null).idServeur, isNull);
      expect(_produit(supabaseId: null).synchronise, isFalse);
      expect(_produit(supabaseId: '').idServeur, isNull);
      expect(_produit(supabaseId: 'abc').idServeur, isNull);
    });

    test('tolère les espaces autour du numéro', () {
      expect(_produit(supabaseId: '  574 ').idServeur, 574);
    });
  });

  group('ArticleScanne.depuisProduit — le panier parle au serveur', () {
    test('envoie le numéro de la base, PAS le numéro local', () {
      final ArticleScanne ligne = ArticleScanne.depuisProduit(
        _produit(id: 83, supabaseId: '503'),
      );

      expect(ligne.produitId, 503);
      expect(ligne.code, 'PROD:503');
      expect(ligne.idServeurEnAttente, isFalse);
    });

    test('conserve le numéro LOCAL pour le stock du téléphone', () {
      // 🔴 CORRECTIF 78 — les deux numéros voyagent ensemble : le serveur
      // comprend 503, la copie SQLite connaît 83. Sans le second,
      // « Enregistrer vente » répondait « Produit ID 503 introuvable ».
      final ArticleScanne ligne = ArticleScanne.depuisProduit(
        _produit(id: 83, supabaseId: '503'),
      );

      expect(ligne.produitId, 503);
      expect(ligne.produitIdLocal, 83);
    });

    test('article pas encore synchronisé : signalé, jamais envoyé en aveugle',
        () {
      final ArticleScanne ligne = ArticleScanne.depuisProduit(
        _produit(id: 83, supabaseId: null),
      );

      expect(ligne.idServeurEnAttente, isTrue);
      expect(ligne.produitId, 83); // repli : la caisse refusera et l'expliquera
    });

    test('conditionnement conservé (vente à la farde)', () {
      final ArticleScanne ligne = ArticleScanne.depuisProduit(
        _produit(supabaseId: '507'),
      );
      expect(ligne.estConditionnement, isFalse);
      expect(ligne.nom, 'Eau Dasani');
    });
  });

  group('VenteService.messageErreur — dire quoi faire', () {
    test('article introuvable : le message porte la solution', () {
      final String message = VenteService.messageErreur(
        'PRODUIT_INTROUVABLE|Article n° 83 introuvable : il a peut-être été '
        'supprimé.',
      );

      expect(message, contains('Article n° 83 introuvable'));
      expect(message, contains('Nouvel article'));
      expect(message, contains('restaurer'));
    });

    test('les autres erreurs restent inchangées', () {
      expect(
        VenteService.messageErreur(
          'STOCK_INSUFFISANT|Stock insuffisant pour Eau Dasani : 150 '
          'disponible(s), 999999 demandé(s).',
        ),
        'Stock insuffisant pour Eau Dasani : 150 disponible(s), 999999 '
        'demandé(s).',
      );
      expect(VenteService.messageErreur('Erreur simple'), 'Erreur simple');
      expect(VenteService.messageErreur(''), '');
      expect(VenteService.messageErreur('CODE|'), 'CODE|');
    });
  });
}
