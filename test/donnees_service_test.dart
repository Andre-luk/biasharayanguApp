// test/donnees_service_test.dart
//
// 🔔 CORRECTIF 78 — LE TABLEAU DE BORD SE RAFRAÎCHIT TOUT SEUL.
//
// Le constat : après avoir ajouté un article ou encaissé une vente, l'accueil
// gardait les anciens totaux jusqu'à ce qu'on quitte l'application.
//
// La correction repose sur un canal unique : chaque écriture l'annonce, et les
// écrans qui affichent des chiffres s'y abonnent. Ces tests garantissent le
// contrat — une annonce = une notification, jamais zéro, jamais d'exception.
//
//     flutter test test/donnees_service_test.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/services/donnees_service.dart';

void main() {
  final DonneesService service = DonneesService.instance;

  test('chaque annonce incrémente la révision (écoute déclenchée)', () {
    int notifications = 0;
    void ecoute() => notifications++;

    service.revision.addListener(ecoute);
    final int depart = service.revision.value;

    service.signale('vente-caisse');
    service.signale('article-cree');

    service.revision.removeListener(ecoute);

    expect(notifications, 2);
    expect(service.revision.value, depart + 2);
  });

  test('un écran désabonné ne reçoit plus rien', () {
    int notifications = 0;
    void ecoute() => notifications++;

    service.revision.addListener(ecoute);
    service.revision.removeListener(ecoute);

    service.signale('apres-desabonnement');

    expect(notifications, 0);
  });

  test('le dernier motif est conservé pour le diagnostic', () {
    service.signale('article-modifie');
    expect(service.dernierMotif, 'article-modifie');
  });

  test('l’annonce sans motif ne lève jamais', () {
    expect(() => service.signale(), returnsNormally);
  });

  test('le canal est un ValueNotifier : un seul état partagé', () {
    expect(DonneesService.instance, same(service));
    expect(service.revision, isA<ValueNotifier<int>>());
  });
}
