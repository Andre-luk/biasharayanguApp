// test/lots_medicament_test.dart
//
// MODULE 36 — LOTS DE MÉDICAMENTS : logique PURE.
//
// Aucun réseau, aucune base : on vérifie ce que l'application affiche à
// partir d'une réponse serveur, et les règles de lecture qui protègent la
// caisse (un lot périmé n'est jamais « vendable », FEFO = plus proche
// d'abord).

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/lot_medicament.dart';
import 'package:biashara_yangu/services/cache_lecture.dart';
import 'package:biashara_yangu/services/pharmacie_lots_service.dart';
import 'package:biashara_yangu/services/scope_donnees.dart';

DateTime _jour(int decalage) {
  final DateTime maintenant = DateTime.now();
  return DateTime(maintenant.year, maintenant.month, maintenant.day)
      .add(Duration(days: decalage));
}

String _date(DateTime d) {
  final String m = d.month.toString().padLeft(2, '0');
  final String j = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$j';
}

Map<String, dynamic> _lot({
  String id = 'lot-1',
  String numero = 'LOT-A',
  int jours = 200,
  double restante = 10,
  double recue = 10,
  String statut = 'valide',
  bool vendable = true,
  bool retire = false,
  double? prix = 500,
}) {
  return <String, dynamic>{
    'id': id,
    'produit_id': 42,
    'numero_lot': numero,
    'date_peremption': _date(_jour(jours)),
    'quantite_recue': recue,
    'quantite_restante': restante,
    'prix_achat_unitaire': prix,
    'statut': statut,
    'vendable': vendable,
    'retire_le': retire ? _date(_jour(-1)) : null,
    'jours_restants': jours,
  };
}

void main() {
  group('StatutLot', () {
    test('lit les codes serveur', () {
      expect(StatutLot.fromCode('perime'), StatutLot.perime);
      expect(StatutLot.fromCode('PROCHE'), StatutLot.proche);
      expect(StatutLot.fromCode(' retire '), StatutLot.retire);
      expect(StatutLot.fromCode(null), StatutLot.inconnu);
      expect(StatutLot.fromCode('???'), StatutLot.inconnu);
    });

    test('seul un lot valide ou proche est vendable', () {
      expect(StatutLot.valide.vendable, isTrue);
      expect(StatutLot.proche.vendable, isTrue);
      expect(StatutLot.perime.vendable, isFalse);
      expect(StatutLot.retire.vendable, isFalse);
      expect(StatutLot.perime.bloquant, isTrue);
    });
  });

  group('LotMedicament — lecture', () {
    test('lit un lot complet renvoyé par le serveur', () {
      final LotMedicament lot =
          LotMedicament.fromMap(_lot(restante: 7, recue: 12, prix: 1000));

      expect(lot.produitId, 42);
      expect(lot.numeroLot, 'LOT-A');
      expect(lot.quantiteRestante, 7);
      expect(lot.quantiteRecue, 12);
      expect(lot.quantiteSortie, 5);
      expect(lot.valeurAchat, 7000);
      expect(lot.statut, StatutLot.valide);
      expect(lot.vendable, isTrue);
    });

    test('quantiteSortie ne devient jamais négative', () {
      final LotMedicament lot =
          LotMedicament.fromMap(_lot(restante: 15, recue: 10));
      expect(lot.quantiteSortie, 0);
    });

    test('sans statut serveur, la règle locale s’applique', () {
      final Map<String, dynamic> map = _lot(jours: -2)
        ..remove('statut')
        ..remove('vendable');
      final LotMedicament lot = LotMedicament.fromMap(map);
      expect(lot.statut, StatutLot.perime);

      final Map<String, dynamic> procheMap = _lot(jours: 10)
        ..remove('statut')
        ..remove('vendable');
      expect(LotMedicament.fromMap(procheMap).statut, StatutLot.proche);

      final Map<String, dynamic> valideMap = _lot(jours: 120)
        ..remove('statut')
        ..remove('vendable');
      expect(LotMedicament.fromMap(valideMap).statut, StatutLot.valide);
    });

    test('un lot retiré reste « retiré » même si la date est future', () {
      final LotMedicament lot = LotMedicament.fromMap(
        _lot(jours: 300, statut: 'retire', vendable: false, retire: true),
      );
      expect(lot.statut, StatutLot.retire);
      expect(lot.vendable, isFalse);
      expect(lot.retireLe, isNotNull);
    });
  });

  group('DossierLots', () {
    Map<String, dynamic> rpc() => <String, dynamic>{
          'ok': true,
          'produit_id': 42,
          'produit': 'Paracétamol 500mg',
          'stock': 26,
          'total_lots_restants': 26,
          'total_vendable': 18,
          // Le serveur renvoie déjà l'ordre FEFO.
          'lots': <Map<String, dynamic>>[
            _lot(id: 'a', numero: 'LOT-A', jours: 40, restante: 10),
            _lot(id: 'b', numero: 'LOT-B', jours: 300, restante: 8),
            _lot(
              id: 'c',
              numero: 'LOT-C',
              jours: -5,
              restante: 8,
              statut: 'perime',
              vendable: false,
            ),
          ],
        };

    test('conserve l’ordre FEFO et expose le prochain lot à servir', () {
      final DossierLots dossier =
          DossierLots.fromRpc(rpc()..['stock'] = 26);

      expect(dossier.produit, 'Paracétamol 500mg');
      expect(dossier.lots.length, 3);
      expect(dossier.prochainLot?.numeroLot, 'LOT-A');
      expect(dossier.lotsVendables.map((LotMedicament l) => l.numeroLot),
          <String>['LOT-A', 'LOT-B']);
    });

    test('les lots périmés immobilisent du stock mais ne sont pas vendables', () {
      final DossierLots dossier = DossierLots.fromRpc(rpc());

      expect(dossier.lotsPerimes.length, 1);
      expect(dossier.lotsPerimes.first.numeroLot, 'LOT-C');
      expect(dossier.stockVendable, 18);
      expect(dossier.stockLots, 26);
    });

    test('valeur d’achat : seuls les lots non retirés comptent', () {
      final DossierLots dossier = DossierLots.fromRpc(rpc());
      // 10 × 500 + 8 × 500 + 8 × 500
      expect(dossier.valeurTotale, 13000);
    });

    test('écart fiche / lots calculé sans arrondi brutal', () {
      final DossierLots dossier = DossierLots.fromRpc(rpc());
      expect(dossier.ecart, 0);
      expect(dossier.ecart.abs() > 0.0005, isFalse);
    });

    test('aucun lot => pas de prochain lot, dossier vide', () {
      final DossierLots dossier = DossierLots.fromRpc(<String, dynamic>{
        'produit_id': 7,
        'produit': 'Article sans lot',
        'stock': 3,
        'total_lots_restants': 0,
        'total_vendable': 0,
        'lots': <dynamic>[],
      });

      expect(dossier.aLots, isFalse);
      expect(dossier.prochainLot, isNull);
      expect(dossier.stockVendable, 0);
    });
  });

  group('Résultats RPC', () {
    test('réception', () {
      final ResultatReceptionLot r =
          ResultatReceptionLot.depuisRpc(<String, dynamic>{
        'lot_id': 'abc',
        'stock': 120,
        'quantite_recue': 20,
        'date_expiration': _date(_jour(300)),
      });

      expect(r.lotId, 'abc');
      expect(r.stockApres, 120);
      expect(r.quantiteRecue, 20);
      expect(r.dateExpiration, isNotNull);
    });

    test('retrait', () {
      final ResultatRetraitLot r = ResultatRetraitLot.depuisRpc(
        <String, dynamic>{'quantite_retiree': 12, 'stock': 8},
      );
      expect(r.quantiteRetiree, 12);
      expect(r.stockApres, 8);
    });
  });

  group('Erreurs métier', () {
    test('messageErreur retire le code', () {
      expect(
        PharmacieLotsService.messageErreur(
            'LOT_DOUBLON|Ce numéro de lot existe déjà.'),
        'Ce numéro de lot existe déjà.',
      );
      expect(PharmacieLotsService.messageErreur('texte simple'), 'texte simple');
    });

    test('typeDepuisMessage classe les refus', () {
      expect(
        PharmacieLotsService.typeDepuisMessage('DROIT_REFUSE|non'),
        TypeErreurLots.droits,
      );
      expect(
        PharmacieLotsService.typeDepuisMessage('SESSION_ABSENTE|non'),
        TypeErreurLots.session,
      );
      expect(
        PharmacieLotsService.typeDepuisMessage('PEREMPTION_PASSEE|non'),
        TypeErreurLots.validation,
      );
      expect(
        PharmacieLotsService.typeDepuisMessage('LOT_INTROUVABLE|non'),
        TypeErreurLots.stock,
      );
      expect(
        PharmacieLotsService.typeDepuisMessage('AUTRE|non'),
        TypeErreurLots.inconnu,
      );
    });
  });

  group('CacheLecture — isolation entre entreprises', () {
    setUp(ScopeDonnees.reinitialiser);
    tearDown(ScopeDonnees.reinitialiser);

    test('la clé change quand l’entreprise active change', () {
      ScopeDonnees.definirEspaceActif('11111111-1111-1111-1111-111111111111');
      final String cleA = CacheLecture.cleRpc('rpc_finance_tableau_bord');

      ScopeDonnees.definirEspaceActif('22222222-2222-2222-2222-222222222222');
      final String cleB = CacheLecture.cleRpc('rpc_finance_tableau_bord');

      expect(cleA, isNot(equals(cleB)),
          reason: 'Hors ligne, la pharmacie ne doit jamais relire le cache de '
              'la boutique.');
      expect(cleA, contains('espace=11111111'));
      expect(cleB, contains('espace=22222222'));
    });

    test('le propriétaire effectif (serveur) prime sur l’espace choisi', () {
      ScopeDonnees.definirEspaceActif('espace-pharmacie');
      ScopeDonnees.definirProprietaireEffectif('patron-uuid');

      final String cle = CacheLecture.cleRpc('rpc_stock');
      expect(cle, contains('espace=patron-uuid'));
      expect(cle, isNot(contains('espace-pharmacie')));
    });
  });
}
