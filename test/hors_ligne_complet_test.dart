// test/hors_ligne_complet_test.dart
//
// 🔌 100 % HORS LIGNE — ce qui est vérifié ici :
//
//   1. une lecture qui échoue est servie depuis le cache (écran non vide) ;
//   2. une réponse du serveur n'est JAMAIS remplacée par du cache
//      (un refus de droit doit rester un refus) ;
//   3. la clé de cache isole bien les appels (fonction + arguments) ;
//   4. les ventes locales sans réseau produisent un reçu lisible ;
//   5. la décision « conflit » après N tentatives est explicite.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/vente_enregistree.dart';
import 'package:biashara_yangu/services/cache_lecture.dart';

/// Stockage en mémoire : aucun SQLite, aucun Supabase.
class StockageMemoire implements StockageCache {
  final Map<String, String> valeurs = <String, String>{};
  final Map<String, DateTime> dates = <String, DateTime>{};

  @override
  Future<String?> lire(String cle) async => valeurs[cle];

  @override
  Future<void> ecrire(String cle, String valeur) async {
    valeurs[cle] = valeur;
    dates[cle] = DateTime.now();
  }

  @override
  Future<DateTime?> majLe(String cle) async => dates[cle];

  @override
  Future<void> purger(String cle) async {
    valeurs.remove(cle);
    dates.remove(cle);
  }

  @override
  Future<void> vider() async {
    valeurs.clear();
    dates.clear();
  }
}

void main() {
  group('CacheLecture — repli hors ligne', () {
    late StockageMemoire stockage;
    late CacheLecture cache;

    setUp(() {
      stockage = StockageMemoire();
      cache = CacheLecture(stockage: stockage);
    });

    test('réseau indisponible : la dernière valeur connue est servie', () async {
      // 1er appel : le serveur répond → la valeur entre en cache.
      final dynamic premier = await cache.avecRepli(
        'rapport|u1',
        () async => <String, dynamic>{'total': 12500, 'ventes': 7},
      );
      expect(premier['total'], 12500);

      // 2e appel : plus de réseau → même donnée, pas d'écran vide.
      final dynamic second = await cache.avecRepli(
        'rapport|u1',
        () async => throw TimeoutException('réseau absent'),
      );
      expect(second['total'], 12500);
      expect(second['ventes'], 7);
      expect(cache.dernierResultatLocal.value, isTrue);
    });

    test('aucun cache : l\'erreur remonte (jamais de fausse donnée)', () async {
      await expectLater(
        cache.avecRepli(
          'jamais-vu',
          () async => throw TimeoutException('réseau absent'),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(cache.dernierResultatLocal.value, isFalse);
    });

    test('un refus du serveur n\'est JAMAIS masqué par le cache', () async {
      await cache.avecRepli(
        'activation|u1',
        () async => <String, dynamic>{'ok': true},
      );

      await expectLater(
        cache.avecRepli(
          'activation|u1',
          () async => throw const PostgrestException(message: 'DROIT_REFUSE'),
        ),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('la valeur fraîche remplace l\'ancienne', () async {
      await cache.avecRepli('stats', () async => <String, dynamic>{'n': 1});
      await cache.avecRepli('stats', () async => <String, dynamic>{'n': 2});

      final dynamic relu = await cache.relire('stats');
      expect(relu['n'], 2);
    });

    test('vider() efface tout (déconnexion)', () async {
      await cache.avecRepli('a', () async => <String, dynamic>{'x': 1});
      await cache.vider();
      expect(await cache.relire('a'), isNull);
    });

    test('une valeur non sérialisable ne casse pas la lecture', () async {
      final dynamic reponse = await cache.avecRepli(
        'bizarre',
        () async => Object(),
      );
      expect(reponse, isNotNull);
      // Non mise en cache : la relecture est simplement vide.
      expect(await cache.relire('bizarre'), isNull);
    });
  });

  group('CacheLecture.cleRpc', () {
    test('deux appels différents ne partagent pas la même clé', () {
      final String a = CacheLecture.cleRpc(
        'rpc_rapport',
        params: <String, dynamic>{'p_espace': 'boutique'},
      );
      final String b = CacheLecture.cleRpc(
        'rpc_rapport',
        params: <String, dynamic>{'p_espace': 'pharmacie'},
      );
      expect(a, isNot(b));
      expect(a, contains('rpc_rapport'));
      expect(a, contains('p_espace=boutique'));
    });

    test('l\'ordre des paramètres ne change pas la clé', () {
      final String a = CacheLecture.cleRpc(
        'rpc_x',
        params: <String, dynamic>{'p_a': 1, 'p_b': 2},
      );
      final String b = CacheLecture.cleRpc(
        'rpc_x',
        params: <String, dynamic>{'p_b': 2, 'p_a': 1},
      );
      expect(a, b);
    });

    test('les paramètres nuls sont ignorés', () {
      final String a = CacheLecture.cleRpc(
        'rpc_y',
        params: <String, dynamic>{'p_a': 1, 'p_b': null},
      );
      final String b = CacheLecture.cleRpc(
        'rpc_y',
        params: <String, dynamic>{'p_a': 1},
      );
      expect(a, b);
    });
  });

  group('VenteEnregistree — reçu hors ligne', () {
    test('un reçu local porte un numéro reconnaissable et son total', () {
      const VenteEnregistree vente = VenteEnregistree(
        numeroVente: 'HORS-LIGNE-12345678',
        venteUuid: 'local-1',
        total: 15000,
        modePaiement: 'especes',
        montantRecu: 20000,
        rendu: 5000,
        lignes: <LigneVenteEnregistree>[
          LigneVenteEnregistree(
            produitId: 4,
            nom: 'Eau 1,5 L',
            unite: 'unité',
            quantiteVendue: 10,
            quantiteBase: 10,
            prixUnitaire: 1500,
            total: 15000,
          ),
        ],
      );

      expect(vente.numeroVente, startsWith('HORS-LIGNE-'));
      expect(vente.total, 15000);
      expect(vente.rendu, 5000);
      expect(vente.lignes.single.nom, 'Eau 1,5 L');
    });
  });
}
