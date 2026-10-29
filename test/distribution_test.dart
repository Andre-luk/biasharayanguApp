// test/distribution_test.dart
//
// 🚚 MODULE 23 — Tests PURS de la distribution terrain :
//   • états et parsing des tournées / lignes / consignes / bonus ;
//   • messages d'erreur serveur traduits en français ;
//   • mode rapide (mode d'application + stock illimité de l'article).
//
// Aucun réseau : tous les objets sont construits à partir de JSON simulés.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/distribution_terrain.dart';
import 'package:biashara_yangu/models/statut_stock.dart';
import 'package:biashara_yangu/services/distribution_service.dart';
import 'package:biashara_yangu/services/mode_application_service.dart';
import 'package:biashara_yangu/services/tableau_bord_stats_service.dart';

void main() {
  // =========================================================================
  // 1. ÉTATS ET PARSING
  // =========================================================================

  group('TourneeStatut', () {
    test('fromCode reconnaît les quatre états', () {
      expect(TourneeStatut.fromCode('preparee'), TourneeStatut.preparee);
      expect(TourneeStatut.fromCode('en_cours'), TourneeStatut.enCours);
      expect(TourneeStatut.fromCode('cloturee'), TourneeStatut.cloturee);
      expect(TourneeStatut.fromCode('annulee'), TourneeStatut.annulee);
    });

    test('un code inconnu retombe sur « préparée » (jamais null)', () {
      expect(TourneeStatut.fromCode('bizarre'), TourneeStatut.preparee);
      expect(TourneeStatut.fromCode(null), TourneeStatut.preparee);
    });

    test('seules « préparée » et « en cours » sont actives', () {
      expect(TourneeStatut.preparee.estActive, isTrue);
      expect(TourneeStatut.enCours.estActive, isTrue);
      expect(TourneeStatut.cloturee.estActive, isFalse);
      expect(TourneeStatut.annulee.estActive, isFalse);
    });
  });

  group('TourneeDistribution.depuisJson', () {
    test('parse un rapport complet, nombres en texte compris', () {
      final TourneeDistribution t = TourneeDistribution.depuisJson(
        <String, dynamic>{
          'id': 't-1',
          'reference': 'TOU-20261029-0001',
          'date_tournee': '2026-10-29',
          'agent_id': 'a-1',
          'agent_nom': 'Jean Livreur',
          'zone': 'Katuba',
          'statut': 'en_cours',
          'nb_articles': '3',
          'quantite_attribuee': '120',
          'quantite_vendue': '90',
          'quantite_retournee': '20',
          'ecart': '10',
          'chiffre_affaires': '45000',
          'consignes_ouvertes': '4',
          'consignes_total': '6',
          'bonus_total': '3000',
        },
      );

      expect(t.reference, 'TOU-20261029-0001');
      expect(t.agentNom, 'Jean Livreur');
      expect(t.zone, 'Katuba');
      expect(t.statut, TourneeStatut.enCours);
      expect(t.nbArticles, 3);
      expect(t.quantiteAttribuee, 120);
      expect(t.quantiteVendue, 90);
      expect(t.ecart, 10);
      expect(t.chiffreAffaires, 45000);
      expect(t.consignesOuvertes, 4);
      expect(t.bonusTotal, 3000);
      expect(t.tauxVente, closeTo(0.75, 0.0001));
    });

    test('tauxVente ne divise jamais par zéro', () {
      final TourneeDistribution t = TourneeDistribution.depuisJson(
        <String, dynamic>{'id': 'x', 'reference': 'r'},
      );
      expect(t.tauxVente, 0);
    });
  });

  group('LigneTournee', () {
    test('calcule le restant affiché et l\'épuisement', () {
      final LigneTournee l = LigneTournee.depuisJson(<String, dynamic>{
        'produit_id': 7,
        'nom': 'Eau 1,5 L',
        'unite': 'bouteille',
        'attribuee': 48,
        'vendue': 36,
        'retournee': 0,
        'restante': 12,
        'prix_vente': 500,
      });

      expect(l.produitId, 7);
      expect(l.restante, 12);
      expect(l.epuisee, isFalse);
    });

    test('une ligne sans restant est épuisée', () {
      const LigneTournee l = LigneTournee(produitId: 1, nom: 'X', restante: 0);
      expect(l.epuisee, isTrue);
    });
  });

  group('MaTournee.depuisJson', () {
    test('renvoie null quand le serveur dit ok:false', () {
      expect(
        MaTournee.depuisJson(<String, dynamic>{
          'ok': false,
          'motif': 'AUCUNE_TOURNEE',
        }),
        isNull,
      );
    });

    test('parse la tournée, ses lignes, consignes et bonus', () {
      final MaTournee? t = MaTournee.depuisJson(<String, dynamic>{
        'ok': true,
        'tournee': <String, dynamic>{
          'id': 't-9',
          'reference': 'TOU-20261029-0009',
          'date_tournee': '2026-10-29',
          'zone': 'Ruashi',
          'statut': 'en_cours',
        },
        'lignes': <dynamic>[
          <String, dynamic>{
            'produit_id': 1,
            'nom': 'Eau 0,5 L',
            'attribuee': 24,
            'vendue': 4,
            'restante': 20,
            'prix_vente': 300,
          },
        ],
        'consignes': <dynamic>[
          <String, dynamic>{
            'id': 'c-1',
            'client_nom': 'Kiosque Mama',
            'quantite': 5,
            'recuperee': 2,
            'statut': 'partielle',
          },
        ],
        'bonus': <dynamic>[
          <String, dynamic>{
            'id': 'b-1',
            'client_nom': 'Kiosque Mama',
            'nature': 'remise',
            'montant': 500,
          },
        ],
      });

      expect(t, isNotNull);
      expect(t!.reference, 'TOU-20261029-0009');
      expect(t.demarree, isTrue);
      expect(t.lignes, hasLength(1));
      expect(t.produitsRestants, 1);
      expect(t.quantiteRestante, 20);
      expect(t.consignes.single.restante, 3);
      expect(t.consignes.single.ouverte, isTrue);
      expect(t.bonus.single.libelleNature, 'Remise');
    });
  });

  group('ConsigneRecipient', () {
    test('restante ne descend jamais sous zéro', () {
      final ConsigneRecipient c = ConsigneRecipient.depuisJson(
        <String, dynamic>{
          'id': 'c',
          'quantite': 3,
          'recuperee': 5,
          'statut': 'recuperee',
        },
      );
      expect(c.restante, 0);
      expect(c.ouverte, isFalse);
      expect(c.libelleStatut, 'Récupérée');
    });

    test('une consigne perdue n\'est plus ouverte', () {
      final ConsigneRecipient c = ConsigneRecipient.depuisJson(
        <String, dynamic>{
          'id': 'c',
          'quantite': 3,
          'recuperee': 0,
          'statut': 'perdue',
        },
      );
      expect(c.ouverte, isFalse);
      expect(c.libelleStatut, 'Perdue');
    });
  });

  group('RapportDistribution', () {
    test('parse les lignes et les totaux', () {
      final RapportDistribution r = RapportDistribution.depuisJson(
        <String, dynamic>{
          'ok': true,
          'lignes': <dynamic>[
            <String, dynamic>{
              'id': 't1',
              'reference': 'TOU-1',
              'agent_nom': 'Agent A',
              'statut': 'cloturee',
              'chiffre_affaires': 1000,
            },
            <String, dynamic>{
              'id': 't2',
              'reference': 'TOU-2',
              'agent_nom': 'Agent B',
              'statut': 'en_cours',
              'chiffre_affaires': 2500,
            },
          ],
          'totaux': <String, dynamic>{
            'tournees': 2,
            'chiffre_affaires': '3500',
            'quantite_vendue': '40',
            'ecart': '2',
            'consignes_ouvertes': '3',
            'bonus': '500',
          },
        },
      );

      expect(r.tournees, hasLength(2));
      expect(r.totaux.tournees, 2);
      expect(r.totaux.chiffreAffaires, 3500);
      expect(r.totaux.ecart, 2);
      expect(r.totaux.consignesOuvertes, 3);
    });

    test('un JSON vide produit un rapport vide (pas d\'exception)', () {
      final RapportDistribution r =
          RapportDistribution.depuisJson(<String, dynamic>{});
      expect(r.tournees, isEmpty);
      expect(r.totaux.chiffreAffaires, 0);
    });
  });

  group('CompteursDistribution', () {
    test('parse les compteurs de la carte d\'accueil', () {
      final CompteursDistribution c = CompteursDistribution.depuisJson(
        <String, dynamic>{
          'tournees_actives': 2,
          'agents_actifs': 2,
          'consignes_ouvertes': 7,
          'bonus_mois': '12000',
        },
      );
      expect(c.tourneesActives, 2);
      expect(c.agentsActifs, 2);
      expect(c.consignesOuvertes, 7);
      expect(c.bonusMois, 12000);
    });
  });

  group('StatsAccueil', () {
    test('ventes_total : même source serveur que les montants', () {
      final StatsAccueil s = StatsAccueil.depuisJson(<String, dynamic>{
        'produits': 5,
        'stock_alertes': 1,
        'ventes_jour': 3,
        'ventes_total': 128,
        'ca_jour': '45000',
        'ca_total': '980000',
      });

      expect(s.produits, 5);
      expect(s.stockAlertes, 1);
      expect(s.ventesJour, 3);
      expect(s.ventesTotal, 128);
      expect(s.caJour, 45000);
      expect(s.caTotal, 980000);
    });

    test('un JSON vide donne des zéros (jamais une exception)', () {
      final StatsAccueil s = StatsAccueil.depuisJson(<String, dynamic>{});
      expect(s.ventesTotal, 0);
      expect(s.caTotal, 0);
    });
  });

  // =========================================================================
  // 2. MESSAGES D'ERREUR
  // =========================================================================

  group('DistributionService.messageErreur', () {
    test('traduit les codes métier connus', () {
      expect(
        DistributionService.messageErreur('AUCUNE_TOURNEE|qqch'),
        contains('Aucune tournée en cours'),
      );
      expect(
        DistributionService.messageErreur('ATTRIBUTION_EPUISEE|reste 0'),
        contains('plus assez'),
      );
      expect(
        DistributionService.messageErreur('DROIT_REFUSE|non'),
        contains('Votre rôle'),
      );
    });

    test('conserve un message français déjà rédigé', () {
      expect(
        DistributionService.messageErreur('Retour supérieur au restant'),
        'Retour supérieur au restant',
      );
    });

    test('message vide → repli générique', () {
      expect(
        DistributionService.messageErreur(''),
        contains('réessayez'),
      );
      expect(
        DistributionService.messageErreur(null),
        contains('réessayez'),
      );
    });
  });

  // =========================================================================
  // 3. MODE RAPIDE
  // =========================================================================

  group('ModeApplication', () {
    test('par défaut et code inconnu → mode complet', () {
      expect(ModeApplication.fromCode(null), ModeApplication.complet);
      expect(ModeApplication.fromCode('inconnu'), ModeApplication.complet);
    });

    test('reconnaît le mode rapide', () {
      expect(ModeApplication.fromCode('rapide'), ModeApplication.rapide);
      expect(ModeApplication.fromCode(' RAPIDE '), ModeApplication.rapide);
    });
  });

  group('Article — stock illimité (mode rapide)', () {
    test('fromMap lit stock_illimite', () {
      final Article a = Article.fromMap(<String, dynamic>{
        'id': 1,
        'nom': 'Eau',
        'quantite': 1000000,
        'stock_illimite': true,
      });
      expect(a.stockIllimite, isTrue);
      expect(a.statutStock, StatutStock.ok);
      expect(a.stockAffiche, '∞');
    });

    test('toMap n\'envoie la clé que si elle est vraie', () {
      const Article normal = Article(id: 1, nom: 'Savon');
      const Article rapide =
          Article(id: 2, nom: 'Eau', stockIllimite: true);

      expect(normal.toMap().containsKey('stock_illimite'), isFalse);
      expect(rapide.toMap()['stock_illimite'], isTrue);
    });

    test('un article à stock illimité n\'est jamais en alerte', () {
      const Article a = Article(
        id: 3,
        nom: 'Eau',
        quantite: 0,
        seuilAlerte: 10,
        stockIllimite: true,
      );
      expect(a.statutStock, StatutStock.ok);
    });
  });

  group('ResultatCloture', () {
    test('conserve la tournée et les lignes du rapport', () {
      const TourneeDistribution t = TourneeDistribution(
        id: 't',
        reference: 'TOU-1',
        dateTournee: null,
        statut: TourneeStatut.cloturee,
        ecart: 2,
      );
      const ResultatCloture r = ResultatCloture(
        tournee: t,
        lignes: <LigneTournee>[
          LigneTournee(produitId: 1, nom: 'Eau', restante: 2),
        ],
      );

      expect(r.tournee.statut, TourneeStatut.cloturee);
      expect(r.lignes.single.restante, 2);
    });
  });
}
