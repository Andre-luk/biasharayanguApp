// test/radar_tournee_test.dart
//
// 🎯 RADAR DE TOURNÉE (phase 6).
//
// Le radar n'est pas un écran décoratif : il doit dire la VÉRITÉ sur des
// données réelles. Ces tests vérifient que le décodage côté application ne
// transforme jamais un silence du serveur en accusation, ni une absence de
// données en recommandation inventée.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/distribution_terrain.dart';

void main() {
  group('NiveauAnomalie', () {
    test('reconnaît les trois niveaux', () {
      expect(NiveauAnomalie.fromCode('normal'), NiveauAnomalie.normal);
      expect(NiveauAnomalie.fromCode('surveiller'), NiveauAnomalie.surveiller);
      expect(NiveauAnomalie.fromCode('alerte'), NiveauAnomalie.alerte);
    });

    test('un code inconnu ou absent ne transforme pas un agent en suspect', () {
      expect(NiveauAnomalie.fromCode(null), NiveauAnomalie.normal);
      expect(NiveauAnomalie.fromCode(''), NiveauAnomalie.normal);
      expect(NiveauAnomalie.fromCode('tres-mauvais'), NiveauAnomalie.normal);
      expect(NiveauAnomalie.fromCode('  ALERTE '), NiveauAnomalie.alerte);
    });
  });

  group('EcartProduit', () {
    test('un écart positif est un manquant', () {
      const EcartProduit e = EcartProduit(
        produitId: 7,
        nom: 'Eau 1,5 L',
        attribuee: 50,
        vendue: 40,
        retournee: 5,
        ecart: 5,
        valeur: 5000,
      );

      expect(e.manquant, isTrue);
      expect(e.excedent, isFalse);
    });

    test('un écart négatif signale une incohérence de saisie', () {
      const EcartProduit e = EcartProduit(produitId: 8, ecart: -2);

      expect(e.manquant, isFalse);
      expect(e.excedent, isTrue);
    });

    test('lit un écart fourni par le serveur', () {
      final EcartProduit e = EcartProduit.depuisJson(<String, dynamic>{
        'produit_id': 12,
        'nom': 'Casier',
        'unite': 'casier',
        'attribuee': 20,
        'vendue': 18,
        'retournee': 1,
        'bonus': 0,
        'casse': 0,
        'ecart': 1,
        'valeur': 3000,
      });

      expect(e.nom, 'Casier');
      expect(e.ecart, 1);
      expect(e.valeur, 3000);
      expect(e.manquant, isTrue);
    });
  });

  group('RadarTournee', () {
    test('décode un radar complet', () {
      final RadarTournee r = RadarTournee.depuisJson(<String, dynamic>{
        'ok': true,
        'zone': 'Kinshasa-Est',
        'tournee': <String, dynamic>{
          'id': 't1',
          'reference': 'TOU-20260101-0001',
        },
        'resume': <String, dynamic>{
          'produits': 3,
          'quantite_confiee': 100,
          'quantite_vendue': 80,
          'quantite_retournee': 10,
          'quantite_bonus': 2,
          'quantite_casse': 3,
          'ecart': 5,
          'valeur_ecart': 12500,
        },
        'ecarts': <dynamic>[
          <String, dynamic>{
            'produit_id': 1,
            'nom': 'Eau 1,5 L',
            'unite': 'bouteille',
            'ecart': 5,
            'valeur': 12500,
          },
        ],
        'recommandations': <dynamic>[
          <String, dynamic>{
            'produit_id': 1,
            'nom': 'Eau 1,5 L',
            'unite': 'bouteille',
            'mediane_vendue': 60,
            'taux_retour': 0.1,
            'nb_tournees': 4,
            'quantite_suggeree': 54,
            'stock_disponible': 40,
            'quantite_retenue': 40,
          },
        ],
        'historique_suffisant': true,
        'consignes_risque': <dynamic>[
          <String, dynamic>{
            'id': 'c1',
            'client_id': 9,
            'client_nom': 'Mama Nicole',
            'libelle': 'Casier 12',
            'restant': 4,
            'jours': 45,
            'valeur': 20000,
          },
        ],
      });

      expect(r.zone, 'Kinshasa-Est');
      expect(r.reference, 'TOU-20260101-0001');
      expect(r.produits, 3);
      expect(r.ecart, 5);
      expect(r.valeurEcart, 12500);
      expect(r.aDesEcarts, isTrue);
      expect(r.ecarts.single.nom, 'Eau 1,5 L');
      expect(r.historiqueSuffisant, isTrue);

      final RecommandationChargement rec = r.recommandations.single;
      expect(rec.nbTournees, 4);
      expect(rec.quantiteRetenue, 40);
      // Le stock est le plafond : on ne conseille jamais l'impossible.
      expect(rec.quantiteRetenue, lessThanOrEqualTo(rec.stockDisponible));

      expect(r.consignesRisque.single.jours, 45);
      expect(r.valeurConsignesRisque, 20000);
    });

    test('un radar sans données ne fabrique ni écart ni recommandation', () {
      final RadarTournee r =
          RadarTournee.depuisJson(<String, dynamic>{'ok': true});

      expect(r.aDesEcarts, isFalse);
      expect(r.ecarts, isEmpty);
      expect(r.recommandations, isEmpty);
      expect(r.consignesRisque, isEmpty);
      expect(r.historiqueSuffisant, isFalse);
      expect(r.ecart, 0);
      expect(r.valeurConsignesRisque, 0);
    });

    test('RadarTournee.vide ne prétend rien savoir', () {
      expect(RadarTournee.vide.aDesEcarts, isFalse);
      expect(RadarTournee.vide.historiqueSuffisant, isFalse);
      expect(RadarTournee.vide.ecart, 0);
    });
  });

  group('RecommandationChargement', () {
    test('le taux de retour est borné pour l\'affichage', () {
      const RecommandationChargement haut = RecommandationChargement(
        produitId: 1,
        tauxRetour: 1.8,
      );
      const RecommandationChargement negatif = RecommandationChargement(
        produitId: 2,
        tauxRetour: -0.5,
      );

      expect(haut.tauxRetourPourcent, 100);
      expect(negatif.tauxRetourPourcent, 0);
    });
  });

  group('RadarAgent', () {
    test('décode le score et ses motifs', () {
      final RadarAgent a = RadarAgent.depuisJson(<String, dynamic>{
        'ok': true,
        'agent_id': 'u1',
        'agent_nom': 'Jean Kabila',
        'jours': 30,
        'score': 47,
        'niveau': 'surveiller',
        'tournees': 6,
        'quantite_confiee': 400,
        'quantite_vendue': 360,
        'ecart': 20,
        'taux_ecart': 0.05,
        'chiffre_affaires': 1200000,
        'credit_ouvert': 60000,
        'taux_credit': 0.05,
        'motifs': <dynamic>[
          <String, dynamic>{
            'code': 'ECART_MARCHANDISE',
            'libelle': 'Marchandise confiée non justifiée',
            'detail': 'Sur 30 jours : 20 unité(s)',
            'valeur': 20,
          },
        ],
      });

      expect(a.agentNom, 'Jean Kabila');
      expect(a.score, 47);
      expect(a.niveau, NiveauAnomalie.surveiller);
      expect(a.niveau.libelle, 'À surveiller');
      expect(a.aQuelqueChoseASignaler, isTrue);
      expect(a.motifs.single.code, 'ECART_MARCHANDISE');
      expect(a.motifs.single.detail, contains('30 jours'));
    });

    test('un agent irréprochable n\'est pas signalé', () {
      final RadarAgent a = RadarAgent.depuisJson(<String, dynamic>{
        'ok': true,
        'score': 0,
        'niveau': 'normal',
        'tournees': 4,
        'quantite_confiee': 200,
        'quantite_vendue': 200,
        'ecart': 0,
        'motifs': <dynamic>[
          <String, dynamic>{
            'code': 'AUCUNE_ANOMALIE',
            'libelle': 'Aucune anomalie détectée',
            'detail': 'Tout ce qui a été confié est vendu, rendu, cassé ou offert.',
            'valeur': 0,
          },
        ],
      });

      expect(a.niveau, NiveauAnomalie.normal);
      expect(a.aQuelqueChoseASignaler, isFalse);
      expect(a.motifs.single.code, 'AUCUNE_ANOMALIE');
    });

    test('un radar vide reste neutre', () {
      expect(RadarAgent.vide.score, 0);
      expect(RadarAgent.vide.niveau, NiveauAnomalie.normal);
      expect(RadarAgent.vide.motifs, isEmpty);
      expect(RadarAgent.vide.aQuelqueChoseASignaler, isFalse);
    });

    test('un score fourni en texte reste un entier', () {
      final RadarAgent a = RadarAgent.depuisJson(<String, dynamic>{
        'score': '63',
        'niveau': 'alerte',
      });

      expect(a.score, 63);
      expect(a.niveau, NiveauAnomalie.alerte);
    });
  });
}
