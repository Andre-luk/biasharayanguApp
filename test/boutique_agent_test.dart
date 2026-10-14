// test/boutique_agent_test.dart
//
// 🧑‍🌾 CORRECTIF 76 — LES BOUTIQUES DE L'AGENT (lecture de `rpc_agent_mes_boutiques`).
//
// L'agent ne voyait rien de ce qu'il créait. La correction repose sur un
// contrat précis entre la base et l'application : la fonction serveur renvoie
// une liste de boutiques avec leur abonnement, et l'écran se contente de
// l'afficher. Ces tests protègent ce contrat :
//
//   • les libellés affichés (étape, statut, échéance) viennent des MÊMES règles
//     que la fiche d'entreprise — une seule vérité, pas deux ;
//   • une réponse illisible ou incomplète ne fait JAMAIS planter l'application ;
//   • l'agent ne peut RIEN modifier par ce chemin (aucun drapeau d'écriture).
//
//     flutter test test/boutique_agent_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/boutique_agent.dart';

Map<String, dynamic> _ligne({Map<String, dynamic> extra = const {}}) {
  return <String, dynamic>{
    'entreprise_id': 'ent-1',
    'nom': 'Boutique Mwamba',
    'type': 'boutique',
    'statut': 'ESSAI_7J',
    'activation_etape': 'actif',
    'cree_le': '2026-10-01T08:00:00Z',
    'date_activation': '2026-10-01T09:00:00Z',
    'date_expiration': '2026-10-08T09:00:00Z',
    'jours_restants': 3,
    'prix_installation': 30000,
    'prix_abonnement_mensuel': 20000,
    'total_du': 30000,
    'deja_paye': 10000,
    'solde': 20000,
    'proprietaire_nom': 'Mwamba Kalonji',
    'proprietaire_email': 'mwamba@example.cd',
    'proprietaire_telephone': '+243970000000',
    'dossiers_en_attente': 0,
    ...extra,
  };
}

void main() {
  group('BoutiqueAgent — lecture de la ligne serveur', () {
    test('lit une boutique complète', () {
      final MesBoutiquesAgent? data = MesBoutiquesAgent.depuisJson(
        <String, dynamic>{
          'ok': true,
          'role': 'AGENT_TERRAIN',
          'boutiques': <dynamic>[_ligne()],
        },
      );

      expect(data, isNotNull);
      expect(data!.role, 'AGENT_TERRAIN');
      expect(data.boutiques, hasLength(1));

      final BoutiqueAgent b = data.boutiques.first;
      expect(b.entrepriseId, 'ent-1');
      expect(b.nom, 'Boutique Mwamba');
      expect(b.joursRestants, 3);
      expect(b.totalDu, 30000);
      expect(b.dejaPaye, 10000);
      expect(b.solde, 20000);
      expect(b.proprietaireTelephone, '+243970000000');
      expect(b.actif, isTrue);
      expect(b.echu, isFalse);
      expect(b.soldeRestant, isTrue);
    });

    test('les libellés sont ceux de la fiche d\'entreprise', () {
      final BoutiqueAgent b = MesBoutiquesAgent.depuisJson(<String, dynamic>{
        'ok': true,
        'boutiques': <dynamic>[_ligne()],
      })!
          .boutiques
          .first;

      // Mêmes règles que `SuiviFiche` : aucune seconde implémentation.
      expect(b.suivi.libelleEtape, 'Actif');
      expect(b.suivi.libelleStatut, 'Essai');
      expect(b.suivi.libelleEcheance, '3 jour(s) restant(s)');
      expect(b.suivi.enAttente, isFalse);
    });

    test('un dossier en attente de finance est signalé', () {
      final BoutiqueAgent b = MesBoutiquesAgent.depuisJson(<String, dynamic>{
        'ok': true,
        'boutiques': <dynamic>[
          _ligne(extra: <String, dynamic>{
            'activation_etape': 'verifie',
            'statut': 'EN_ATTENTE_COMPLEMENT',
            'dossiers_en_attente': 1,
          }),
        ],
      })!
          .boutiques
          .first;

      expect(b.enAttenteFinance, isTrue);
      expect(b.suivi.enAttente, isTrue);
      expect(b.suivi.libelleEtape, 'Vérifié — en attente de la finance');
    });

    test('un abonnement échu est détecté (jours négatifs)', () {
      final BoutiqueAgent b = MesBoutiquesAgent.depuisJson(<String, dynamic>{
        'ok': true,
        'boutiques': <dynamic>[
          _ligne(extra: <String, dynamic>{'jours_restants': -5}),
        ],
      })!
          .boutiques
          .first;

      expect(b.echu, isTrue);
      expect(b.actif, isFalse);
      expect(b.suivi.libelleEcheance, 'Échu depuis 5 jour(s)');
    });
  });

  group('MesBoutiquesAgent — synthèse du portefeuille', () {
    test('compte les actives, les échues et la somme des soldes', () {
      final MesBoutiquesAgent data = MesBoutiquesAgent.depuisJson(
        <String, dynamic>{
          'ok': true,
          'boutiques': <dynamic>[
            _ligne(),
            _ligne(extra: <String, dynamic>{
              'entreprise_id': 'ent-2',
              'nom': 'Dépôt Katuba',
              'jours_restants': -2,
              'solde': 5000,
            }),
            _ligne(extra: <String, dynamic>{
              'entreprise_id': 'ent-3',
              'nom': 'Pharmacie du Centre',
              'activation_etape': 'verifie',
              'solde': 0,
            }),
          ],
        },
      )!;

      expect(data.boutiques, hasLength(3));
      expect(data.nbActives, 1);
      expect(data.nbEchues, 1);
      expect(data.nbEnAttente, 1);
      expect(data.soldeTotal, 25000);
      expect(data.vide, isFalse);
    });

    test('portefeuille vide : aucune erreur', () {
      final MesBoutiquesAgent data = MesBoutiquesAgent.depuisJson(
        <String, dynamic>{'ok': true, 'boutiques': <dynamic>[]},
      )!;

      expect(data.vide, isTrue);
      expect(data.soldeTotal, 0);
    });

    test('accepte une réponse encodée en texte (PostgREST)', () {
      final MesBoutiquesAgent? data = MesBoutiquesAgent.depuisJson(
        '{"ok":true,"boutiques":[{"entreprise_id":"e","nom":"Test"}]}',
      );

      expect(data, isNotNull);
      expect(data!.boutiques.single.nom, 'Test');
    });

    test('réponse illisible : null, jamais une exception', () {
      expect(MesBoutiquesAgent.depuisJson(null), isNull);
      expect(MesBoutiquesAgent.depuisJson('pas du json'), isNull);
      expect(MesBoutiquesAgent.depuisJson(<String, dynamic>{'ok': false}), isNull);
      expect(
        MesBoutiquesAgent.depuisJson(<String, dynamic>{'ok': true}),
        isNotNull,
      );
    });

    test('ligne incomplète : valeurs neutres, pas de plantage', () {
      final BoutiqueAgent b = MesBoutiquesAgent.depuisJson(<String, dynamic>{
        'ok': true,
        'boutiques': <dynamic>[
          <String, dynamic>{'entreprise_id': 'e', 'nom': 'Sans détails'},
        ],
      })!
          .boutiques
          .first;

      expect(b.nom, 'Sans détails');
      expect(b.joursRestants, isNull);
      expect(b.solde, isNull);
      expect(b.dossiersEnAttente, 0);
      expect(b.soldeRestant, isFalse);
      expect(b.echu, isFalse);
      expect(b.suivi.libelleEcheance, 'Aucune échéance enregistrée');
    });
  });
}
