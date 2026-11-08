// test/vente_format_sync_test.dart
//
// 🧾 MODULE 28 — LE FORMAT VENDU VA JUSQU'AU SERVEUR.
//
// Une farde de 12 n'est PAS 12 bouteilles du point de vue du PRIX.
// Ces tests vérifient que la ligne de vente locale transporte :
//   • les unités de BASE (12) → ce que le stock consomme ;
//   • les unités VENDUES (1) → ce que le client paie ;
//   • l'identifiant du conditionnement → le prix de la farde, pas de l'unité.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/vente.dart';

Vente _vente({
  double quantite = 12,
  double? quantiteVendue,
  String? conditionnementId,
  double prix = 12000,
}) {
  return Vente(
    produitId: 7,
    quantite: quantite,
    prix: prix,
    modePaiement: 'cash',
    createdAt: DateTime(2026, 11, 8).toIso8601String(),
    quantiteVendue: quantiteVendue,
    conditionnementId: conditionnementId,
  );
}

void main() {
  group('Vente locale — format vendu', () {
    test('une farde conserve son conditionnement et ses deux quantités', () {
      final Vente v = _vente(
        quantite: 12,
        quantiteVendue: 1,
        conditionnementId: 'cond-uuid-1',
      );

      final Map<String, dynamic> map = v.toMap();
      expect(map['quantite'], 12, reason: 'unités de base = stock');
      expect(map['quantite_vendue'], 1, reason: 'unités vendues = prix');
      expect(map['conditionnement_id'], 'cond-uuid-1');
      expect(map['prix'], 12000);
    });

    test('une vente à l\'unité n\'a pas de conditionnement', () {
      final Vente v = _vente(quantite: 3, quantiteVendue: 3);

      final Map<String, dynamic> map = v.toMap();
      expect(map['conditionnement_id'], isNull);
      expect(map['quantite'], 3);
      expect(map['quantite_vendue'], 3);
    });

    test('fromMap relit ce que toMap a écrit', () {
      final Vente origine = _vente(
        quantite: 24,
        quantiteVendue: 2,
        conditionnementId: 'cond-uuid-2',
        prix: 24000,
      );

      final Vente relue = Vente.fromMap(<String, dynamic>{
        ...origine.toMap(),
        'id': 1,
      });

      expect(relue.quantite, 24);
      expect(relue.quantiteVendue, 2);
      expect(relue.conditionnementId, 'cond-uuid-2');
      expect(relue.prix, 24000);
    });

    test('une ancienne ligne (sans colonnes) reste lisible', () {
      final Vente relue = Vente.fromMap(<String, dynamic>{
        'id': 5,
        'produit_id': 7,
        'quantite': 3,
        'prix': 3000,
        'mode_paiement': 'cash',
        'date': '2026-11-08T10:00:00.000',
        'is_synced': 0,
      });

      expect(relue.conditionnementId, isNull);
      expect(relue.quantiteVendue, isNull);
      expect(relue.quantite, 3);
    });

    test('tant que la quantité vendue manque, on retombe sur la base', () {
      final Vente v = _vente(quantite: 12);

      // C'est la règle appliquée par la synchronisation :
      // `v.quantiteVendue ?? v.quantite`.
      expect(v.quantiteVendue ?? v.quantite, 12);
    });
  });
}
