// test/stock_test.dart
//
// Tests unitaires du MODULE 9 — Gestion du stock (conversions multi-unités).
//
// Ces tests ne touchent ni au réseau ni à Supabase : ils vérifient les
// calculs purs (statuts d'alerte, conversions, décompositions, écarts
// d'inventaire), le parsing des modèles et les messages d'erreur serveur.
//
//     flutter test test/stock_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/inventaire_ligne.dart';
import 'package:biashara_yangu/models/statut_stock.dart';
import 'package:biashara_yangu/models/stock_article.dart';
import 'package:biashara_yangu/services/stock_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

Conditionnement _fardeDe12({int produitId = 492}) => Conditionnement(
      id: 'a1111111-1111-1111-1111-111111111111',
      produitId: produitId,
      libelle: 'Farde de 12',
      quantiteUnitesBase: 12,
      prixVente: 12000,
      qrCodeId: 'b2222222-2222-2222-2222-222222222222',
    );

Conditionnement _cartonDe24({int produitId = 492}) => Conditionnement(
      id: 'c3333333-3333-3333-3333-333333333333',
      produitId: produitId,
      libelle: 'Carton de 24',
      quantiteUnitesBase: 24,
      prixVente: 22000,
      qrCodeId: 'd4444444-4444-4444-4444-444444444444',
    );

Article _article({
  int id = 492,
  String nom = 'Bouteille d\'eau',
  double quantite = 1004,
  double seuilAlerte = 50,
  List<Conditionnement> conditionnements = const <Conditionnement>[],
}) =>
    Article(
      id: id,
      nom: nom,
      quantite: quantite,
      seuilAlerte: seuilAlerte,
      uniteMesure: 'bouteille',
      conditionnements: conditionnements,
    );

void main() {
  // =========================================================================
  // 1. STATUTS D'ALERTE (OK / Faible / Rupture)
  // =========================================================================

  group('StatutStock.depuisStock', () {
    test('stock nul ou négatif → Rupture', () {
      expect(
        StatutStock.depuisStock(quantite: 0, seuilAlerte: 5),
        StatutStock.rupture,
      );
      expect(
        StatutStock.depuisStock(quantite: -3, seuilAlerte: 5),
        StatutStock.rupture,
      );
    });

    test('stock égal au seuil → Faible (le seuil déclenche l\'alerte)', () {
      expect(
        StatutStock.depuisStock(quantite: 5, seuilAlerte: 5),
        StatutStock.faible,
      );
      expect(
        StatutStock.depuisStock(quantite: 3, seuilAlerte: 5),
        StatutStock.faible,
      );
    });

    test('stock au-dessus du seuil → OK', () {
      expect(
        StatutStock.depuisStock(quantite: 6, seuilAlerte: 5),
        StatutStock.ok,
      );
    });

    test('seuil à 0 : seules les ruptures sont signalées', () {
      expect(
        StatutStock.depuisStock(quantite: 1, seuilAlerte: 0),
        StatutStock.ok,
      );
      expect(
        StatutStock.depuisStock(quantite: 0, seuilAlerte: 0),
        StatutStock.rupture,
      );
    });

    test('tolérance sur les arrondis `real` de la base', () {
      expect(
        StatutStock.depuisStock(quantite: 0.0000001, seuilAlerte: 5),
        StatutStock.rupture,
      );
    });

    test('priorité : rupture < faible < OK', () {
      expect(StatutStock.rupture.priorite, lessThan(StatutStock.faible.priorite));
      expect(StatutStock.faible.priorite, lessThan(StatutStock.ok.priorite));
      expect(StatutStock.rupture.estAlerte, isTrue);
      expect(StatutStock.ok.estAlerte, isFalse);
    });
  });

  // =========================================================================
  // 2. SEUIL D'ALERTE DANS LE MODÈLE ARTICLE
  // =========================================================================

  group('Article.seuilAlerte', () {
    test('parsing de seuil_alerte renvoyé par Supabase', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 492,
        'nom': 'Bouteille',
        'quantite': 1004,
        'seuil_alerte': 50,
      });

      expect(article.seuilAlerte, 50.0);
      expect(article.statutStock, StatutStock.ok);
    });

    test('seuil par défaut (5) quand la colonne est absente', () {
      final Article article = Article.fromMap(<String, dynamic>{
        'id': 1,
        'nom': 'Sucre',
        'quantite': 3,
      });

      expect(article.seuilAlerte, 5.0);
      expect(article.statutStock, StatutStock.faible);
    });

    test('copyWith peut changer le seuil sans toucher au stock', () {
      final Article article = _article(seuilAlerte: 50);
      final Article modifie = article.copyWith(seuilAlerte: 100);

      expect(modifie.seuilAlerte, 100.0);
      expect(modifie.quantite, article.quantite);
    });

    test('toMap n\'envoie PAS le seuil (écrit par la RPC du Module 9)', () {
      final Map<String, dynamic> map = _article().toMap();
      expect(map.containsKey('seuil_alerte'), isFalse);
    });
  });

  // =========================================================================
  // 3. CONVERSIONS MULTI-UNITÉS
  // =========================================================================

  group('StockCalculs — conversions', () {
    test('10 fardes de 12 → 120 bouteilles (unités de base)', () {
      expect(
        StockCalculs.versUnitesBase(quantiteSaisie: 10, quantiteUnitesBase: 12),
        120.0,
      );
    });

    test('saisie en unité de base : facteur 1', () {
      expect(
        StockCalculs.versUnitesBase(quantiteSaisie: 7, quantiteUnitesBase: 1),
        7.0,
      );
    });

    test('prix d\'achat : 1 200 CDF la farde de 12 → 100 CDF la bouteille', () {
      expect(
        StockCalculs.prixParUniteBase(prixSaisi: 1200, quantiteUnitesBase: 12),
        100.0,
      );
      expect(
        StockCalculs.prixParUniteBase(prixSaisi: 100, quantiteUnitesBase: 1),
        100.0,
      );
    });
  });

  // =========================================================================
  // 4. DÉCOMPOSITION EN CONDITIONNEMENTS
  // =========================================================================

  group('StockCalculs — décomposition', () {
    test('1004 bouteilles avec farde de 12 → 83 fardes + 8 bouteilles', () {
      final DecompositionStock d = StockCalculs.decomposer(
        quantite: 1004,
        conditionnement: _fardeDe12(),
      );

      expect(d.exemplaires, 83);
      expect(d.reste, 8.0);
      expect(d.estExact, isFalse);
      // 83 × 12 = 996, plus les 8 bouteilles directes = 1004.
      expect(d.quantiteRegroupee, 996.0);
      expect(d.quantiteRegroupee + d.reste, 1004.0);
    });

    test('1 020 bouteilles → 85 fardes exactement', () {
      final DecompositionStock d = StockCalculs.decomposer(
        quantite: 1020,
        conditionnement: _fardeDe12(),
      );

      expect(d.exemplaires, 85);
      expect(d.estExact, isTrue);
      expect(d.quantiteRegroupee, 1020.0);
    });

    test('stock nul → 0 exemplaire', () {
      final DecompositionStock d = StockCalculs.decomposer(
        quantite: 0,
        conditionnement: _fardeDe12(),
      );

      expect(d.exemplaires, 0);
      expect(d.reste, 0.0);
    });

    test('exemple du cahier des charges : 984 + 20 = 1004', () {
      // 82 fardes × 12 = 984 bouteilles + 20 bouteilles « directes ».
      final double stock = StockCalculs.versUnitesBase(
            quantiteSaisie: 82,
            quantiteUnitesBase: 12,
          ) +
          20;
      expect(stock, 1004.0);
    });

    test('décompositions multiples (farde de 12 et carton de 24)', () {
      final Article article = _article(
        quantite: 1004,
        conditionnements: <Conditionnement>[_fardeDe12(), _cartonDe24()],
      );

      final List<DecompositionStock> decompositions =
          StockCalculs.decompositions(article);

      expect(decompositions, hasLength(2));
      expect(decompositions[0].exemplaires, 83); // 1004 ÷ 12
      expect(decompositions[1].exemplaires, 41); // 1004 ÷ 24 = 41, reste 20
      expect(decompositions[1].reste, 20.0);
    });

    test('decompositionPrincipale : null sans conditionnement', () {
      expect(StockCalculs.decompositionPrincipale(_article()), isNull);
      expect(
        StockCalculs.decompositionPrincipale(_article(
          conditionnements: <Conditionnement>[_fardeDe12()],
        )),
        isNotNull,
      );
    });
  });

  // =========================================================================
  // 5. TABLEAU DE BORD MAGASINIER
  // =========================================================================

  group('StockCalculs — alertes et tri', () {
    final List<Article> articles = <Article>[
      _article(id: 1, nom: 'Zèbre', quantite: 0, seuilAlerte: 5),
      _article(id: 2, nom: 'Avion', quantite: 4, seuilAlerte: 5),
      _article(id: 3, nom: 'Mais', quantite: 100, seuilAlerte: 5),
      _article(id: 4, nom: 'Béton', quantite: 2, seuilAlerte: 10),
    ];

    test('comptage par statut', () {
      expect(StockCalculs.compter(articles, StatutStock.rupture), 1);
      expect(StockCalculs.compter(articles, StatutStock.faible), 2);
      expect(StockCalculs.compter(articles, StatutStock.ok), 1);
    });

    test('articles en alerte : ruptures puis faibles, triés par nom', () {
      final List<Article> alertes = StockCalculs.enAlerte(articles);

      expect(alertes, hasLength(3));
      expect(alertes[0].nom, 'Zèbre'); // rupture
      expect(alertes[1].nom, 'Avion'); // faible
      expect(alertes[2].nom, 'Béton'); // faible
    });

    test('tri par urgence : rupture, faible, puis OK', () {
      final List<Article> tries = StockCalculs.trierParUrgence(articles);

      expect(tries.map((Article a) => a.nom).toList(),
          <String>['Zèbre', 'Avion', 'Béton', 'Mais']);
    });

    test('valeur du stock au prix d\'achat', () {
      final List<Article> liste = <Article>[
        Article(id: 1, nom: 'A', quantite: 10, prixAchat: 100),
        Article(id: 2, nom: 'B', quantite: 5, prixAchat: 200),
      ];

      expect(StockCalculs.valeurAchat(liste), 2000.0);
    });

    test('statut d\'un article (raccourci)', () {
      expect(StockCalculs.statut(articles[0]), StatutStock.rupture);
      expect(StockCalculs.statut(articles[1]), StatutStock.faible);
      expect(StockCalculs.statut(articles[2]), StatutStock.ok);
    });
  });

  // =========================================================================
  // 6. INVENTAIRE QUOTIDIEN
  // =========================================================================

  group('LigneInventaire', () {
    test('non compté : aucune quantité, écart inconnu', () {
      final LigneInventaire ligne = LigneInventaire(
        produitId: 1,
        nom: 'Bouteille',
        unite: 'bouteille',
        quantiteTheorique: 100,
      );

      expect(ligne.compte, isFalse);
      expect(ligne.ecart, isNull);
      expect(ligne.estConforme, isFalse);
      expect(ligne.estEnEcart, isFalse);
    });

    test('écart négatif (manquant) et positif (excédent)', () {
      final LigneInventaire manquant = LigneInventaire(
        produitId: 1,
        nom: 'Bouteille',
        unite: 'bouteille',
        quantiteTheorique: 100,
        quantitePhysique: 92,
      );
      final LigneInventaire excedent = LigneInventaire(
        produitId: 2,
        nom: 'Sucre',
        unite: 'pièce',
        quantiteTheorique: 50,
        quantitePhysique: 53,
      );

      expect(manquant.ecart, -8.0);
      expect(manquant.estEnEcart, isTrue);
      expect(excedent.ecart, 3.0);
      expect(excedent.estConforme, isFalse);
    });

    test('comptage conforme', () {
      final LigneInventaire ligne = LigneInventaire(
        produitId: 1,
        nom: 'Bouteille',
        unite: 'bouteille',
        quantiteTheorique: 100,
        quantitePhysique: 100,
      );

      expect(ligne.ecart, 0.0);
      expect(ligne.estConforme, isTrue);
      expect(ligne.estEnEcart, isFalse);
    });

    test('versJson : corps envoyé à rpc_inventaire_cloturer', () {
      final LigneInventaire ligne = LigneInventaire(
        produitId: 42,
        nom: 'Riz',
        unite: 'kg',
        quantiteTheorique: 10,
        quantitePhysique: 9.5,
      );

      expect(ligne.versJson(), <String, dynamic>{
        'produit_id': 42,
        'quantite_physique': 9.5,
      });
    });
  });

  group('ResumeInventaire', () {
    test('ignore les lignes non comptées', () {
      final ResumeInventaire resume = ResumeInventaire.depuisLignes(<LigneInventaire>[
        LigneInventaire(
          produitId: 1,
          nom: 'A',
          unite: 'u',
          quantiteTheorique: 10,
        ),
        LigneInventaire(
          produitId: 2,
          nom: 'B',
          unite: 'u',
          quantiteTheorique: 10,
          quantitePhysique: 12,
        ),
      ]);

      expect(resume.nbComptes, 1);
      expect(resume.nbEcarts, 1);
      expect(resume.ecartNet, 2.0);
      expect(resume.ecartAbsolu, 2.0);
    });

    test('écarts signés : net compensé, amplitude absolue', () {
      final ResumeInventaire resume = ResumeInventaire.depuisLignes(<LigneInventaire>[
        LigneInventaire(
          produitId: 1,
          nom: 'A',
          unite: 'u',
          quantiteTheorique: 100,
          quantitePhysique: 92, // -8
        ),
        LigneInventaire(
          produitId: 2,
          nom: 'B',
          unite: 'u',
          quantiteTheorique: 50,
          quantitePhysique: 55, // +5
        ),
        LigneInventaire(
          produitId: 3,
          nom: 'C',
          unite: 'u',
          quantiteTheorique: 10,
          quantitePhysique: 10, // conforme
        ),
      ]);

      expect(resume.nbComptes, 3);
      expect(resume.nbEcarts, 2);
      expect(resume.ecartNet, -3.0);
      expect(resume.ecartAbsolu, 13.0);
      expect(resume.aDesEcarts, isTrue);
    });

    test('aucune ligne comptée → résumé vide', () {
      final ResumeInventaire resume = ResumeInventaire.depuisLignes(const <LigneInventaire>[]);
      expect(resume.nbComptes, 0);
      expect(resume.aDesEcarts, isFalse);
      expect(ResumeInventaire.vide.nbComptes, 0);
    });
  });

  // =========================================================================
  // 7. PARSING DES RÉPONSES RPC
  // =========================================================================

  group('Résultats des RPC', () {
    test('ResultatApprovisionnement.depuisRpc', () {
      final ResultatApprovisionnement resultat =
          ResultatApprovisionnement.depuisRpc(<String, dynamic>{
        'produit_id': 492,
        'nom': 'Bouteille d\'eau',
        'quantite_ajoutee': 120,
        'prix_achat_unitaire': 100,
        'fournisseur': 'Éts Kabila',
        'stock_avant': 884,
        'stock_apres': 1004,
        'date': '2026-09-16T18:44:00+00:00',
      });

      expect(resultat.produitId, 492);
      expect(resultat.quantiteAjoutee, 120.0);
      expect(resultat.prixAchatUnitaire, 100.0);
      expect(resultat.fournisseur, 'Éts Kabila');
      expect(resultat.stockAvant, 884.0);
      expect(resultat.stockApres, 1004.0);
      expect(resultat.date, isNotNull);
    });

    test('ResultatAjustement.depuisRpc (delta négatif)', () {
      final ResultatAjustement resultat =
          ResultatAjustement.depuisRpc(<String, dynamic>{
        'produit_id': 7,
        'nom': 'Sucre',
        'delta': -8,
        'raison': 'Casse pendant manutention',
        'stock_avant': '100',
        'stock_apres': '92',
      });

      expect(resultat.delta, -8.0);
      expect(resultat.raison, 'Casse pendant manutention');
      expect(resultat.stockAvant, 100.0);
      expect(resultat.stockApres, 92.0);
    });

    test('ResultatInventaire.depuisRpc (lignes + totaux)', () {
      final ResultatInventaire resultat =
          ResultatInventaire.depuisRpc(<String, dynamic>{
        'date_cloture': '2026-09-16',
        'nb_lignes': 2,
        'nb_ecarts': 1,
        'ecart_net': -8,
        'ajustements_crees': true,
        'lignes': <dynamic>[
          <String, dynamic>{
            'produit_id': 1,
            'nom': 'Bouteille',
            'unite': 'bouteille',
            'theorique': 100,
            'physique': 92,
            'ecart': -8,
            'ajuste': true,
          },
          <String, dynamic>{
            'produit_id': 2,
            'nom': 'Sucre',
            'unite': 'pièce',
            'theorique': 50,
            'physique': 50,
            'ecart': 0,
            'ajuste': false,
          },
        ],
      });

      expect(resultat.nbLignes, 2);
      expect(resultat.nbEcarts, 1);
      expect(resultat.ecartNet, -8.0);
      expect(resultat.ajustementsCrees, isTrue);
      expect(resultat.lignes, hasLength(2));
      expect(resultat.lignes[0].ecart, -8.0);
      expect(resultat.lignes[0].ajuste, isTrue);
      expect(resultat.lignes[1].ajuste, isFalse);
    });
  });

  // =========================================================================
  // 8. MESSAGES D'ERREUR ET FORMATAGE
  // =========================================================================

  group('StockService.messageErreur', () {
    test('retire le code serveur et garde le texte français', () {
      expect(
        StockService.messageErreur(
            'RAISON_OBLIGATOIRE|Indiquez la raison de l\'ajustement.'),
        'Indiquez la raison de l\'ajustement.',
      );
      expect(
        StockService.messageErreur(
            'AUCUN_ECART|Aucun écart à corriger : la quantité saisie est identique.'),
        'Aucun écart à corriger : la quantité saisie est identique.',
      );
    });

    test('message sans préfixe conservé tel quel', () {
      expect(
        StockService.messageErreur('Connexion impossible.'),
        'Connexion impossible.',
      );
      expect(StockService.messageErreur('CODE|'), 'CODE|');
    });
  });

  group('Formatage des quantités', () {
    test('formatQuantite : entier sans décimale, sinon 2 décimales', () {
      expect(formatQuantite(85), '85');
      expect(formatQuantite(1004.0), '1004');
      expect(formatQuantite(10.5), '10.5');
      expect(formatQuantite(0), '0');
    });

    test('formatQuantiteSignee : signe + pour les excédents', () {
      expect(formatQuantiteSignee(8), '+8');
      expect(formatQuantiteSignee(-3), '-3');
      expect(formatQuantiteSignee(0), '0');
    });
  });

  // ---------------------------------------------------------------------------
  // 🔔 CORRECTIF 71 — ALERTE DE STOCK APRÈS UN INVENTAIRE
  //
  // Avant ce correctif, seule une VENTE pouvait déclencher l'alerte de stock.
  // Un inventaire qui découvre une marchandise perdue, volée ou cassée ne
  // disait rien : le stock ne pouvait baisser sous le seuil QUE si le manquant
  // avait été vendu. Autrement dit, le cas le plus grave était le seul cas
  // muet.
  //
  // La règle ci-dessous n'est pas un détail d'implémentation : c'est elle qui
  // décide QUELS articles méritent une alerte. Trop large, elle noie le
  // commerçant sous de fausses alertes ; trop étroite, elle laisse passer
  // exactement ce qu'elle devait rattraper.
  // ---------------------------------------------------------------------------

  group('StockService — baissesDeStockApresInventaire', () {
    LigneResultatInventaire ligne({
      int produitId = 1,
      double theorique = 20,
      double physique = 3,
      bool ajuste = true,
    }) {
      return LigneResultatInventaire(
        produitId: produitId,
        nom: 'Article $produitId',
        unite: 'pièce',
        theorique: theorique,
        physique: physique,
        ecart: physique - theorique,
        ajuste: ajuste,
      );
    }

    test('retient une baisse réellement corrigée', () {
      final List<({int produitId, double avant, double apres})> baisses =
          StockService.baissesDeStockApresInventaire(<LigneResultatInventaire>[
        ligne(produitId: 7, theorique: 20, physique: 3),
      ]);

      expect(baisses.length, 1);
      expect(baisses.first.produitId, 7);
      expect(baisses.first.avant, 20);
      expect(baisses.first.apres, 3);
    });

    test('ignore un écart NON corrigé', () {
      //  Clôture en lecture seule : le stock n'a pas bougé. Signaler une
      //  disparition qui n'a pas eu lieu serait un faux positif — et une
      //  fausse alerte apprend au commerçant à ignorer les alertes.
      expect(
        StockService.baissesDeStockApresInventaire(<LigneResultatInventaire>[
          ligne(ajuste: false),
        ]),
        isEmpty,
      );
    });

    test('ignore un écart NUL (le stock n\'a pas bougé)', () {
      expect(
        StockService.baissesDeStockApresInventaire(<LigneResultatInventaire>[
          ligne(theorique: 20, physique: 20),
        ]),
        isEmpty,
      );
    });

    test('ignore un EXCÉDENT : une hausse ne franchit pas un seuil vers le bas', () {
      //  Un excédent est une bonne nouvelle ; l'examiner ne coûterait qu'une
      //  lecture réseau inutile.
      expect(
        StockService.baissesDeStockApresInventaire(<LigneResultatInventaire>[
          ligne(theorique: 20, physique: 44),
        ]),
        isEmpty,
      );
    });

    test('ignore une chute à ZÉRO non corrigée, mais la retient si corrigée', () {
      //  Une chute à zéro est le cas extrême : disparition totale.
      expect(
        StockService.baissesDeStockApresInventaire(<LigneResultatInventaire>[
          ligne(theorique: 5, physique: 0, ajuste: false),
        ]),
        isEmpty,
      );
      expect(
        StockService.baissesDeStockApresInventaire(<LigneResultatInventaire>[
          ligne(theorique: 5, physique: 0),
        ]).length,
        1,
      );
    });

    test('trie le bon grain de l\'ivraie au milieu d\'un inventaire réel', () {
      //  Un inventaire d'une journée : trois écarts, dont UNE seule
      //  disparition réelle. C'est ce mélange qui rend la règle nécessaire.
      final List<({int produitId, double avant, double apres})> baisses =
          StockService.baissesDeStockApresInventaire(<LigneResultatInventaire>[
        ligne(produitId: 1, theorique: 30, physique: 30), // conforme
        ligne(produitId: 2, theorique: 12, physique: 20), // excédent
        ligne(produitId: 3, theorique: 9, physique: 2, ajuste: false), // non corrigé
        ligne(produitId: 4, theorique: 15, physique: 1), // disparition corrigée
      ]);

      expect(baisses.length, 1);
      expect(baisses.first.produitId, 4);
      expect(baisses.first.avant, 15);
      expect(baisses.first.apres, 1);
    });

    test('une liste vide reste vide', () {
      expect(
        StockService.baissesDeStockApresInventaire(
            const <LigneResultatInventaire>[]),
        isEmpty,
      );
    });
  });
}
