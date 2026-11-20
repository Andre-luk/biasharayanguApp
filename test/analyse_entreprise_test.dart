// test/analyse_entreprise_test.dart
//
// 📊 MIGRATION 175/177 — RAPPORT D'ANALYSE D'UNE ENTREPRISE.
//
// Ces tests ne touchent PAS le réseau : ils vérifient le parsing du JSON
// renvoyé par `rpc_rapport_entreprise_analyse` et la génération du PDF
// (c'est la partie qui produisait « Impossible de produire le rapport pour le
// moment » chez l'utilisateur, quel que soit le métier).

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/analyse_entreprise.dart';
import 'package:biashara_yangu/services/analyse_entreprise_service.dart';

/// Réponse type du serveur (boutique ou pressing : même contrat).
Map<String, dynamic> reponseComplete({int produits = 3}) {
  return <String, dynamic>{
    'ok': true,
    'entreprise_id': '11111111-1111-1111-1111-111111111111',
    'entreprise_nom': 'Pressing La Grâce',
    'debut': '2026-11-14',
    'fin': '2026-11-20',
    'devise': 'CDF',
    'nb_produits': produits,
    'sources': <String, dynamic>{'boutique': 0, 'pressing': 42},
    'totaux': <String, dynamic>{
      'ca': 125000,
      'ventes': 42,
      'articles': 96,
      'panier_moyen': 2976.19,
      'marge': 51000,
    },
    'top_produits': <Map<String, dynamic>>[
      for (int i = 1; i <= produits; i++)
        <String, dynamic>{
          'rang': i,
          'nom': 'Prestation $i',
          'quantite': 10 - i,
          'ca': 50000 - i * 1000,
          'part': 40 - i.toDouble(),
        },
    ],
    'jours': <Map<String, dynamic>>[
      <String, dynamic>{
        'dow': 1,
        'jour': 'Lundi',
        'ca': 30000,
        'ventes': 12,
      },
      <String, dynamic>{
        'dow': 6,
        'jour': 'Samedi',
        'ca': 60000,
        'ventes': 20,
      },
    ],
    'moments': <Map<String, dynamic>>[
      <String, dynamic>{
        'moment': 'Matin (6h–11h)',
        'ca': 20000,
        'ventes': 8,
      },
      <String, dynamic>{
        'moment': 'Après-midi (15h–19h)',
        'ca': 45000,
        'ventes': 15,
      },
    ],
    'meilleur_produit': <String, dynamic>{
      'rang': 1,
      'nom': 'Prestation 1',
      'quantite': 9,
      'ca': 49000,
      'part': 39,
    },
    'meilleur_jour': <String, dynamic>{
      'dow': 6,
      'jour': 'Samedi',
      'ca': 60000,
      'ventes': 20,
    },
    'meilleur_moment': <String, dynamic>{
      'moment': 'Après-midi (15h–19h)',
      'ca': 45000,
      'ventes': 15,
    },
    'conseils': <Map<String, dynamic>>[
      <String, dynamic>{
        'titre': 'Votre meilleur jour : Samedi',
        'detail': 'Samedi réalise 60 000 CDF.',
      },
    ],
    'simulation': <String, dynamic>{
      'produit': 'Prestation 1',
      'ca_actuel': 49000,
      'objectif_pct': 10,
      'ca_supplementaire': 4900,
      'ca_projete': 129900,
      'message': 'Si « Prestation 1 » progresse de 10 %, la boutique gagne '
          'environ 4 900 CDF de plus sur la période.',
    },
  };
}

/// Réponse « aucune vente » (cas d'un pressing qui n'a rien vendu).
Map<String, dynamic> reponseVide() {
  return <String, dynamic>{
    'ok': true,
    'entreprise_id': '11111111-1111-1111-1111-111111111111',
    'entreprise_nom': 'Pressing La Grâce',
    'debut': '2026-11-14',
    'fin': '2026-11-20',
    'devise': 'CDF',
    'totaux': <String, dynamic>{
      'ca': 0,
      'ventes': 0,
      'articles': 0,
      'panier_moyen': 0,
      'marge': 0,
    },
    'top_produits': <dynamic>[],
    'jours': <dynamic>[],
    'moments': <dynamic>[],
    'meilleur_produit': null,
    'meilleur_jour': null,
    'meilleur_moment': null,
    'conseils': <Map<String, dynamic>>[
      <String, dynamic>{
        'titre': 'Aucune vente sur la période',
        'detail': 'Choisissez une autre période.',
      },
    ],
    'simulation': <String, dynamic>{},
  };
}

void main() {
  group('AnalyseEntreprise — lecture du JSON', () {
    test('lit les totaux, les repères et la simulation', () {
      final AnalyseEntreprise analyse =
          AnalyseEntreprise.depuisJson(reponseComplete());

      expect(analyse.entrepriseNom, 'Pressing La Grâce');
      expect(analyse.devise, 'CDF');
      expect(analyse.totaux.ca, 125000);
      expect(analyse.totaux.ventes, 42);
      expect(analyse.totaux.panierMoyen, closeTo(2976.19, 0.01));
      expect(analyse.topProduits, hasLength(3));
      expect(analyse.topProduits.first.nom, 'Prestation 1');
      expect(analyse.meilleurProduit?.nom, 'Prestation 1');
      expect(analyse.meilleurJour?.jour, 'Samedi');
      expect(analyse.meilleurMoment?.moment, 'Après-midi (15h–19h)');
      expect(analyse.conseils, hasLength(1));
      expect(analyse.simulation?.estVide, isFalse);
      expect(analyse.simulation?.caSupplementaire, 4900);
      expect(analyse.estVide, isFalse);
      expect(analyse.nbProduits, 3);
      expect(analyse.sources['pressing'], 42);
      expect(analyse.libelleOrigines, '42 ligne(s) pressing');
    });

    test('tolère une réponse vide (aucune vente sur la période)', () {
      final AnalyseEntreprise analyse =
          AnalyseEntreprise.depuisJson(reponseVide());

      expect(analyse.estVide, isTrue);
      expect(analyse.topProduits, isEmpty);
      expect(analyse.meilleurProduit, isNull);
      expect(analyse.meilleurJour, isNull);
      expect(analyse.meilleurMoment, isNull);
      expect(analyse.simulation?.estVide ?? true, isTrue);
      expect(analyse.conseils.first.titre, 'Aucune vente sur la période');
    });

    test('un `simulation` vide n\'est pas une simulation', () {
      final AnalyseEntreprise analyse =
          AnalyseEntreprise.depuisJson(<String, dynamic>{
        'ok': true,
        'simulation': <String, dynamic>{},
      });
      expect(analyse.simulation?.estVide, isTrue);
    });

    test('nombre de jours : bornes incluses', () {
      final AnalyseEntreprise analyse =
          AnalyseEntreprise.depuisJson(reponseComplete());
      expect(analyse.nombreDeJours, 7);
    });
  });

  group('AnalyseEntrepriseService — périodes', () {
    test('semaine = 7 jours, aujourd\'hui inclus', () {
      final (DateTime debut, DateTime fin) = AnalyseEntrepriseService
          .periodeSemaine(reference: DateTime(2026, 11, 20));
      expect(fin, DateTime(2026, 11, 20));
      expect(debut, DateTime(2026, 11, 14));
      expect(fin.difference(debut).inDays + 1, 7);
      // Le début est MINUIT : un décalage d'une heure fausserait le rapport.
      expect(debut.hour, 0);
    });

    test('mois = 30 jours, aujourd\'hui inclus', () {
      final (DateTime debut, DateTime fin) = AnalyseEntrepriseService
          .periodeMois(reference: DateTime(2026, 11, 20));
      expect(fin, DateTime(2026, 11, 20));
      expect(debut, DateTime(2026, 10, 22));
      expect(debut.hour, 0);
      expect(fin.difference(debut).inDays + 1, 30);
    });

    test('nom de fichier daté', () {
      expect(
        AnalyseEntrepriseService.nomFichier(
          DateTime(2026, 11, 14),
          DateTime(2026, 11, 20),
        ),
        'analyse_20261114_20261120.pdf',
      );
    });
  });

  group('AnalyseEntrepriseService — PDF', () {
    test('produit un PDF sur une analyse complète (tous les produits)', () async {
      final AnalyseEntreprise analyse = AnalyseEntreprise.depuisJson(
        reponseComplete(produits: 12),
      );

      final List<int> octets =
          await AnalyseEntrepriseService.instance.construirePDF(analyse);

      expect(octets.length, greaterThan(1000));
      // Signature d'un fichier PDF.
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });

    test('produit un PDF même sans aucune vente', () async {
      final AnalyseEntreprise analyse =
          AnalyseEntreprise.depuisJson(reponseVide());

      final List<int> octets =
          await AnalyseEntrepriseService.instance.construirePDF(analyse);

      expect(octets.length, greaterThan(500));
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });

    test('un produit sans nom ni quantité ne fait pas échouer le PDF',
        () async {
      final AnalyseEntreprise analyse =
          AnalyseEntreprise.depuisJson(<String, dynamic>{
        'ok': true,
        'totaux': <String, dynamic>{'ca': 1, 'ventes': 1},
        'top_produits': <dynamic>[
          <String, dynamic>{},
          <String, dynamic>{'nom': '', 'ca': null},
        ],
      });

      final List<int> octets =
          await AnalyseEntrepriseService.instance.construirePDF(analyse);
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });
  });
}
