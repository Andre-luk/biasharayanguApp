// test/peremption_test.dart
//
// 🧮 CORRECTIF 72 — TESTS DU DÉLAI D'ALERTE DE PÉREMPTION PAR BOUTIQUE.
//
// Tout ce qui est testé ici est PUR : aucun réseau, aucune base. C'est la
// règle qui décide QUAND un produit est annoncé « expire bientôt » — donc
// quand le commerçant reçoit une alerte.
//
// ⚠️ LE POINT LE PLUS IMPORTANT EST LE PREMIER GROUPE : le MÊME produit doit
// changer de statut quand le délai de la boutique change. Si ce n'était pas
// le cas, le réglage serait purement décoratif — et pire, la liste des
// articles et l'écran Expirations se contrediraient sous les yeux de
// l'utilisateur.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/statut_expiration.dart';
import 'package:biashara_yangu/services/peremption_service.dart';

/// Article minimal, avec ou sans date de péremption.
Article _article({DateTime? expiration, String? lot}) => Article(
      id: 1,
      nom: 'Paracétamol',
      dateExpiration: expiration,
      lotNumero: lot,
    );

/// Une date à [jours] d'aujourd'hui (négatif = déjà passée).
///
/// ⚠️ `DateTime(y, m, j + n)` et NON `.add(Duration(days: n))` : passer par une
/// Duration fait traverser les changements d'heure par l'addition, et l'on
/// retombe alors sur J-1 ou J+1 — ce qui fausse le test du seuil, qui porte
/// précisément sur le jour exact. Laisser Dart normaliser le quantième règle
/// aussi les fins de mois.
DateTime _dans(int jours) {
  final DateTime aujourdhui = DateTime.now();
  return DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + jours);
}

void main() {
  group('StatutExpiration — le délai change réellement le statut', () {
    test('un produit à 45 jours est « proche » avec un délai de 60, pas avec 30', () {
      //  LE test du correctif : le réglage doit avoir un effet visible.
      final DateTime dans45jours = _dans(45);

      expect(
        StatutExpiration.depuis(dans45jours, joursProches: 60),
        StatutExpiration.proche,
        reason: 'la boutique a demandé à être prévenue 60 jours avant',
      );

      expect(
        StatutExpiration.depuis(dans45jours, joursProches: 30),
        StatutExpiration.valide,
        reason: 'avec l\'ancien délai figé de 30 jours, rien ne remontait',
      );
    });

    test('un délai court resserre l\'alerte', () {
      final DateTime dans10jours = _dans(10);
      expect(StatutExpiration.depuis(dans10jours, joursProches: 15),
          StatutExpiration.proche);
      expect(StatutExpiration.depuis(dans10jours, joursProches: 7),
          StatutExpiration.valide);
    });

    test('« expiré » NE DÉPEND PAS du délai : seule l\'anticipation se règle', () {
      //  Un produit périmé hier doit rester périmé quel que soit le réglage —
      //  c'est cette date-là qui bloque la vente en caisse.
      final DateTime hier = _dans(-1);
      for (final int delai in <int>[1, 7, 30, 90, 365]) {
        expect(
          StatutExpiration.depuis(hier, joursProches: delai),
          StatutExpiration.expire,
          reason: 'délai $delai',
        );
      }
    });

    test('le seuil est INCLUSIF : à exactement N jours, on est prévenu', () {
      expect(StatutExpiration.depuis(_dans(30), joursProches: 30),
          StatutExpiration.proche);
      expect(StatutExpiration.depuis(_dans(31), joursProches: 30),
          StatutExpiration.valide);
    });

    test('un produit qui expire aujourd\'hui n\'est PAS expiré', () {
      //  Il reste vendable ce jour-là : la caisse ne le bloque qu'à partir du
      //  lendemain (`date_expiration < current_date`).
      expect(StatutExpiration.depuis(_dans(0), joursProches: 30),
          StatutExpiration.proche);
    });

    test('sans date, aucun statut — donc aucune alerte', () {
      expect(StatutExpiration.depuis(null, joursProches: 90), isNull);
    });
  });

  group('Article — le statut suit le délai de la boutique', () {
    test('statutExpirationSelon applique le délai reçu', () {
      final Article a = _article(expiration: _dans(45));

      expect(a.statutExpirationSelon(60), StatutExpiration.proche);
      expect(a.statutExpirationSelon(30), StatutExpiration.valide);
    });

    test('le getter sans délai garde le comportement d\'avant (30 jours)', () {
      //  ⚠️ Ce getter est utilisé là où le réglage n'est pas disponible : il
      //  DOIT rester sur 30 jours, sinon une boutique qui n'a rien réglé
      //  verrait ses alertes changer toutes seules.
      final Article a = _article(expiration: _dans(20));
      expect(a.statutExpiration, StatutExpiration.proche);
      expect(a.statutExpiration, a.statutExpirationSelon(30));
    });

    test('estUrgentSelon : vrai pour expiré et proche, faux pour valide', () {
      expect(_article(expiration: _dans(-2)).estUrgentSelon(30), isTrue);
      expect(_article(expiration: _dans(10)).estUrgentSelon(30), isTrue);
      expect(_article(expiration: _dans(200)).estUrgentSelon(30), isFalse);
    });

    test('sans date : jamais urgent, quel que soit le délai', () {
      final Article a = _article();
      expect(a.estUrgentSelon(365), isFalse);
      expect(a.aDateExpiration, isFalse);
    });

    test('aDateExpiration distingue « pas de date » de « date lointaine »', () {
      expect(_article(expiration: _dans(3000)).aDateExpiration, isTrue);
      expect(_article().aDateExpiration, isFalse);
    });
  });

  group('Le libellé des jours restants', () {
    test('compte à rebours lisible', () {
      expect(StatutExpiration.libelleJours(-3), 'Expiré depuis 3 j');
      expect(StatutExpiration.libelleJours(0), "Expire aujourd'hui");
      expect(StatutExpiration.libelleJours(1), 'Expire demain');
      expect(StatutExpiration.libelleJours(12), 'Dans 12 j');
    });

    test('sans date, on affiche un tiret plutôt qu\'un chiffre inventé', () {
      expect(StatutExpiration.libelleJours(null), '—');
    });
  });

  group('PeremptionService — bornes et messages', () {
    test('le délai par défaut est celui qui avait cours avant (30 jours)', () {
      //  ⚠️ Le changer silencieusement déplacerait toutes les alertes des
      //  boutiques qui n'ont rien réglé.
      expect(PeremptionService.delaiParDefaut, 30);
    });

    test('les bornes correspondent à la contrainte de la base', () {
      expect(PeremptionService.delaiMinimum, 1);
      expect(PeremptionService.delaiMaximum, 365);
    });

    test('un délai hors bornes est refusé AVANT d\'appeler le serveur', () {
      //  Le serveur refuserait aussi (DELAI_INVALIDE), mais un aller-retour
      //  réseau pour une erreur connue d'avance est du temps perdu pour le
      //  commerçant — et un message plus flou.
      expect(
        () => PeremptionService.instance.definirDelai(0),
        throwsA(isA<PeremptionException>()),
      );
      expect(
        () => PeremptionService.instance.definirDelai(366),
        throwsA(isA<PeremptionException>()),
      );
    });

    test('messageErreur extrait le texte français du message serveur', () {
      expect(
        PeremptionService.messageErreur('DELAI_INVALIDE|Le delai doit etre compris entre 1 et 365 jours.'),
        'Le delai doit etre compris entre 1 et 365 jours.',
      );
    });

    test('une base non migrée est annoncée clairement, pas comme une panne', () {
      //  Tant que la migration 72 n'est pas exécutée, l'écran doit pouvoir le
      //  DIRE — et surtout, l'application continue avec 30 jours.
      expect(
        PeremptionService.typeDepuisMessage('PGRST202', 'PGRST202'),
        TypeErreurPeremption.nonDeploye,
      );
      expect(
        PeremptionService.messageErreur('PGRST202', 'PGRST202'),
        contains('mise à jour de la base'),
      );
    });

    test('chaque code serveur est classé dans la bonne nature', () {
      expect(PeremptionService.typeDepuisMessage('SESSION_ABSENTE|x'),
          TypeErreurPeremption.session);
      expect(PeremptionService.typeDepuisMessage('DROIT_REFUSE|x'),
          TypeErreurPeremption.droits);
      expect(PeremptionService.typeDepuisMessage('DELAI_INVALIDE|x'),
          TypeErreurPeremption.validation);
      expect(PeremptionService.typeDepuisMessage('ENTREPRISE_INTROUVABLE|x'),
          TypeErreurPeremption.validation);
      expect(PeremptionService.typeDepuisMessage('BIDON|x'),
          TypeErreurPeremption.inconnu);
    });

    test('sans lecture réussie, le service expose le délai par défaut', () {
      //  Un écran affiché avant que la lecture ait abouti ne doit pas montrer
      //  « 0 jour » ni une valeur vide.
      final PeremptionService service = PeremptionService.instance;
      expect(service.delaiJours,
          inInclusiveRange(PeremptionService.delaiMinimum,
              PeremptionService.delaiMaximum));
    });
  });

  group('Tri par urgence', () {
    test('les expirés d\'abord, puis les plus proches, puis les sans-date', () {
      final List<Article> tries = StatutExpiration.trierParUrgence(<Article>[
        Article(id: 1, nom: 'Zinc', dateExpiration: _dans(200)),
        Article(id: 2, nom: 'Sans date'),
        Article(id: 3, nom: 'Quinine', dateExpiration: _dans(-5)),
        Article(id: 4, nom: 'Ibuprofène', dateExpiration: _dans(10)),
      ]);

      expect(tries.map((Article a) => a.nom).toList(), <String>[
        'Quinine', // expiré
        'Ibuprofène', // le plus proche
        'Zinc', // valide mais daté
        'Sans date', // toujours en dernier
      ]);
    });
  });
}
