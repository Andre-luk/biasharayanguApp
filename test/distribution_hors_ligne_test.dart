// test/distribution_hors_ligne_test.dart
//
// 📴 MODULE 24 §12 — file d'attente hors ligne du commercial.
//
// Aucun réseau : l'exécuteur est remplacé par un faux serveur. On vérifie
// la mise en file, la persistance, la synchronisation, les conflits métier
// et le passage en « à vérifier » quand l'envoi est interrompu.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/services/distribution_gestion_service.dart';
import 'package:biashara_yangu/services/distribution_hors_ligne_service.dart';

void main() {
  final DistributionHorsLigne horsLigne = DistributionHorsLigne.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await horsLigne.reinitialiser();
    await horsLigne.initialiser();
    horsLigne.executeur = null;
  });

  test('une vente hors ligne est mise en file avec son total', () async {
    await horsLigne.ajouterVente(
      lignes: <Map<String, dynamic>>[
        <String, dynamic>{
          'produit_id': 'p1',
          'quantite': 3,
          'prix_unitaire': 1500,
        },
      ],
      montantPaye: 4500,
    );

    expect(horsLigne.file.length, 1);
    expect(horsLigne.enAttente.value, 1);
    expect(horsLigne.file.single.type, TypeOperationHorsLigne.vente);
    expect(horsLigne.file.single.donnees['total'], 4500);
    // L'identifiant local est l'idempotence côté serveur.
    expect(horsLigne.file.single.id, isNotEmpty);
  });

  test('la synchronisation envoie et vide la file', () async {
    await horsLigne.ajouterVente(
      lignes: <Map<String, dynamic>>[
        <String, dynamic>{'produit_id': 'p1', 'quantite': 1, 'prix_unitaire': 1000},
      ],
    );
    await horsLigne.ajouterBonus(
      produitId: 'p1',
      nature: NatureBonus.casse,
      quantite: 2,
      motif: 'Chute au déchargement',
    );

    final List<String> envoyes = <String>[];
    horsLigne.executeur = (OperationHorsLigne op) async {
      envoyes.add(op.id);
    };

    final ResultatSynchronisation r = await horsLigne.synchroniser();

    expect(r.envoyees, 2);
    expect(r.restantes, 0);
    expect(r.conflits, 0);
    expect(horsLigne.file, isEmpty);
    expect(envoyes.length, 2);
    // Historique conservé.
    expect((await horsLigne.historique()).first['envoyees'], 2);
  });

  test('un refus métier place l\'opération en conflit et arrête la file',
      () async {
    await horsLigne.ajouterVente(
      lignes: <Map<String, dynamic>>[
        <String, dynamic>{'produit_id': 'p1', 'quantite': 5, 'prix_unitaire': 1000},
      ],
    );
    await horsLigne.ajouterVente(
      lignes: <Map<String, dynamic>>[
        <String, dynamic>{'produit_id': 'p2', 'quantite': 1, 'prix_unitaire': 1000},
      ],
    );

    horsLigne.executeur = (OperationHorsLigne op) async {
      throw const DistributionGestionException(
        'Stock insuffisant : le commercial ne détient que 2 unité(s).',
        code: 'STOCK_COMMERCIAL_INSUFFISANT',
      );
    };

    final ResultatSynchronisation r = await horsLigne.synchroniser();

    expect(r.conflits, 1);
    expect(r.envoyees, 0);
    expect(horsLigne.file.length, 2);
    expect(horsLigne.file.first.statut, StatutHorsLigne.conflit);
    expect(horsLigne.file.first.erreur, contains('Stock insuffisant'));
    // La seconde opération n'a pas été tentée : elle dépend de la première.
    expect(horsLigne.file.last.tentatives, 0);
  });

  test('un envoi interrompu passe en « à vérifier » et n\'est jamais rejoué '
      'automatiquement', () async {
    await horsLigne.ajouterVente(
      lignes: <Map<String, dynamic>>[
        <String, dynamic>{'produit_id': 'p1', 'quantite': 1, 'prix_unitaire': 1000},
      ],
    );

    horsLigne.executeur = (OperationHorsLigne op) async {
      throw Exception('SocketException: réseau coupé');
    };

    final ResultatSynchronisation r1 = await horsLigne.synchroniser();
    expect(r1.reseauIndisponible, isTrue);
    expect(horsLigne.file.single.statut, StatutHorsLigne.aVerifier);
    // Plus rien en attente automatique : l'utilisateur doit contrôler.
    expect(horsLigne.enAttente.value, 0);

    int appels = 0;
    horsLigne.executeur = (OperationHorsLigne op) async {
      appels += 1;
    };
    final ResultatSynchronisation r2 = await horsLigne.synchroniser();
    expect(r2.envoyees, 0);
    expect(appels, 0, reason: 'aucune reprise silencieuse');

    // L'utilisateur relance explicitement après vérification.
    await horsLigne.relancer(horsLigne.file.single.id);
    final ResultatSynchronisation r3 = await horsLigne.synchroniser();
    expect(r3.envoyees, 1);
    expect(appels, 1);
  });

  test('retirer une opération (doublon constaté) la sort de la file', () async {
    await horsLigne.ajouterVente(
      lignes: <Map<String, dynamic>>[
        <String, dynamic>{'produit_id': 'p1', 'quantite': 1, 'prix_unitaire': 1000},
      ],
    );
    final String id = horsLigne.file.single.id;
    await horsLigne.retirer(id);
    expect(horsLigne.file, isEmpty);
    expect(horsLigne.enAttente.value, 0);
  });

  test('le cache local restitue produits, clients et date', () async {
    await horsLigne.mettreEnCache(
      produits: const <ProduitCommercial>[
        ProduitCommercial(
          produitId: 'p1',
          nom: 'Bidon 20L',
          unite: 'bidon',
          quantite: 12,
          prixVente: 1500,
        ),
      ],
      clients: const <ClientDistribution>[
        ClientDistribution(id: 'c1', nom: 'Épicerie Kin'),
      ],
      tarifs: const <TarifBidon>[
        TarifBidon(
          id: 't1',
          produitId: 'p1',
          type: TypeOperationTarif.bidonNeuf,
          prix: 2000,
        ),
      ],
    );

    final List<ProduitCommercial> produits = await horsLigne.produitsEnCache();
    final List<ClientDistribution> clients = await horsLigne.clientsEnCache();

    expect(produits.single.nom, 'Bidon 20L');
    expect(produits.single.quantite, 12);
    expect(clients.single.nom, 'Épicerie Kin');
    expect(await horsLigne.dateCache(), isNotNull);
  });
}
