// test/admin_plateforme_test.dart
//
// 🛡️ MODULE 20 — tests de l'administration plateforme (audit final).
//
// Ces tests sont PURS : aucun accès réseau, aucun binding Flutter requis
// (comme le reste de la suite du projet). Ils couvrent les règles de décision
// qui doivent rester stables, parce qu'elles protègent des données de gestion.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/admin_plateforme.dart';
import 'package:biashara_yangu/services/admin_plateforme_service.dart';
import 'package:biashara_yangu/ui/mise_en_page_adaptative.dart';

void main() {
  // ==========================================================================
  //  1. PARC DES BOUTIQUES
  // ==========================================================================
  group('EspaceAdmin', () {
    Map<String, dynamic> complet({Map<String, dynamic> extra = const {}}) =>
        <String, dynamic>{
          'espace_id': 'esp-1',
          'nom': 'Épicerie Bonne Espérance',
          'type': 'boutique',
          'actif': true,
          'visible_publiquement': true,
          'statut_localisation': 'verifiee',
          'ville': 'Lubumbashi',
          'quartier': 'Katuba',
          'entreprises_id': 'ent-1',
          'entreprise': 'Ets MUKENDI',
          'entreprise_statut': 'ACTIF',
          'activation_etape': 'actif',
          'nb_produits': 24,
          'nb_produits_publies': 18,
          'latitude': -11.66,
          'longitude': 27.47,
          ...extra,
        };

    test('fromMap lit toutes les informations du parc', () {
      final EspaceAdmin espace = EspaceAdmin.fromMap(complet());

      expect(espace.espaceId, 'esp-1');
      expect(espace.nom, 'Épicerie Bonne Espérance');
      expect(espace.entreprise, 'Ets MUKENDI');
      expect(espace.ville, 'Lubumbashi');
      expect(espace.nbProduits, 24);
      expect(espace.nbProduitsPublies, 18);
      expect(espace.geolocalisee, isTrue);
      expect(espace.localisationVerifiee, isTrue);
    });

    test('visibleEffectivement exige : active + publiée + géolocalisée',
        () {
      expect(EspaceAdmin.fromMap(complet()).visibleEffectivement, isTrue);

      expect(
        EspaceAdmin.fromMap(complet(extra: <String, dynamic>{'actif': false}))
            .visibleEffectivement,
        isFalse,
      );
      expect(
        EspaceAdmin.fromMap(complet(
                extra: <String, dynamic>{'visible_publiquement': false}))
            .visibleEffectivement,
        isFalse,
      );
      expect(
        EspaceAdmin.fromMap(complet(extra: <String, dynamic>{
          'latitude': null,
          'longitude': null,
        })).visibleEffectivement,
        isFalse,
      );
    });

    test('une entreprise suspendue ou un dossier rejeté rend la boutique '
        'invisible, malgré l\'opt-in', () {
      expect(
        EspaceAdmin.fromMap(complet(
                extra: <String, dynamic>{'entreprise_statut': 'SUSPENDU'}))
            .visibleEffectivement,
        isFalse,
      );
      expect(
        EspaceAdmin.fromMap(
                complet(extra: <String, dynamic>{'activation_etape': 'rejete'}))
            .visibleEffectivement,
        isFalse,
      );
      // « restreint » (compte en règle, abonnement à régulariser) reste visible :
      // la vue serveur `v_biashara_boutiques` accepte 'actif' et 'restreint'.
      expect(
        EspaceAdmin.fromMap(complet(
                extra: <String, dynamic>{'activation_etape': 'restreint'}))
            .visibleEffectivement,
        isTrue,
      );
    });

    test('raisonInvisibilite explique la cause en clair', () {
      expect(
        EspaceAdmin.fromMap(complet()).raisonInvisibilite,
        'Visible dans le catalogue public',
      );
      expect(
        EspaceAdmin.fromMap(complet(extra: <String, dynamic>{'actif': false}))
            .raisonInvisibilite,
        'Boutique désactivée par la plateforme',
      );
      expect(
        EspaceAdmin.fromMap(complet(
                extra: <String, dynamic>{'visible_publiquement': false}))
            .raisonInvisibilite,
        contains('n\'a pas publié'),
      );
      expect(
        EspaceAdmin.fromMap(complet(extra: <String, dynamic>{
          'latitude': null,
          'longitude': null,
        })).raisonInvisibilite,
        'Position non renseignée',
      );
    });

    test('localisationCourte et typeLisible sont prêts à afficher', () {
      expect(EspaceAdmin.fromMap(complet()).localisationCourte,
          'Katuba · Lubumbashi');
      expect(EspaceAdmin.fromMap(complet()).typeLisible, 'Boutique');

      final EspaceAdmin sans = EspaceAdmin.fromMap(<String, dynamic>{
        'espace_id': 'x',
        'nom': 'Test',
      });
      expect(sans.localisationCourte, 'Localisation non renseignée');
      expect(sans.typeLisible, 'Boutique');
      expect(sans.actif, isTrue, reason: 'actif par défaut');
      expect(sans.visiblePubliquement, isFalse, reason: 'opt-in par défaut');
    });
  });

  group('ResumeParcEspaces', () {
    test('calcule les espaces inactifs', () {
      final ResumeParcEspaces resume = ResumeParcEspaces.fromMap(
          <String, dynamic>{'espaces': 12, 'actifs': 9, 'visibles': 5});

      expect(resume.espaces, 12);
      expect(resume.actifs, 9);
      expect(resume.visibles, 5);
      expect(resume.inactifs, 3);
    });

    test('tolère une réponse vide (module non déployé)', () {
      expect(ResumeParcEspaces.fromMap(null).espaces, 0);
      expect(ResumeParcEspaces.vide.inactifs, 0);
    });
  });

  // ==========================================================================
  //  2. MODÉRATION DU CATALOGUE
  // ==========================================================================
  group('PublicationAdmin', () {
    test('fromMap et distinction retrait plateforme / retrait commerçant', () {
      final PublicationAdmin parPlateforme = PublicationAdmin.fromMap(
        <String, dynamic>{
          'publication_id': 'pub-1',
          'produit_id': 42,
          'nom': 'Riz parfumé 25 kg',
          'prix': 145000,
          'unite': 'sac',
          'publie': false,
          'boutique': 'Épicerie Katuba',
          'moderation_note': 'Prix trompeur',
          'moderation_le': '2026-09-20T10:00:00.000Z',
        },
      );

      expect(parPlateforme.publie, isFalse);
      expect(parPlateforme.retireParPlateforme, isTrue);
      expect(parPlateforme.dejaModere, isTrue);
      expect(parPlateforme.moderationNote, 'Prix trompeur');
      expect(parPlateforme.boutique, 'Épicerie Katuba');

      // Retiré par le commerçant lui-même : jamais modéré par la plateforme.
      final PublicationAdmin parCommercant = PublicationAdmin.fromMap(
        <String, dynamic>{
          'publication_id': 'pub-2',
          'produit_id': 43,
          'nom': 'Sucre',
          'publie': false,
        },
      );
      expect(parCommercant.retireParPlateforme, isFalse);
      expect(parCommercant.dejaModere, isFalse);
    });
  });

  group('ResumePublications', () {
    test('lit les compteurs du catalogue', () {
      final ResumePublications resume =
          ResumePublications.fromMap(<String, dynamic>{
        'publications': 30,
        'publiees': 28,
        'retirees': 2,
      });
      expect(resume.publications, 30);
      expect(resume.publiees, 28);
      expect(resume.retirees, 2);
    });
  });

  // ==========================================================================
  //  3. RETRAIT D'UN COMPTE
  // ==========================================================================
  group('StrategieSuppression', () {
    test('depuisCode est insensible à la casse et à la casse vide', () {
      expect(StrategieSuppression.depuisCode('desactivation'),
          StrategieSuppression.desactivation);
      expect(StrategieSuppression.depuisCode(' ANONYMISATION '),
          StrategieSuppression.anonymisation);
      expect(StrategieSuppression.depuisCode('suppression'),
          StrategieSuppression.suppression);
      expect(StrategieSuppression.depuisCode(''), isNull);
      expect(StrategieSuppression.depuisCode(null), isNull);
      expect(StrategieSuppression.depuisCode('inconnu'), isNull);
    });

    test('les codes envoyés au serveur sont figés', () {
      expect(StrategieSuppression.desactivation.code, 'desactivation');
      expect(StrategieSuppression.anonymisation.code, 'anonymisation');
      expect(StrategieSuppression.suppression.code, 'suppression');
    });
  });

  group('DependancesUtilisateur', () {
    test('sansImpact est vrai uniquement pour un compte totalement isolé', () {
      final DependancesUtilisateur seul =
          DependancesUtilisateur.fromMap(<String, dynamic>{
        'utilisateur_id': 'u-1',
        'est_patron': false,
        'nb_espaces': 0,
        'nb_collaborateurs': 0,
        'total_donnees': 0,
        'detail': <String, dynamic>{},
        'suppression_possible': true,
        'recommandation': 'suppression',
      });

      expect(seul.sansImpact, isTrue);
      expect(seul.suppressionPossible, isTrue);
      expect(seul.recommandation, StrategieSuppression.suppression);
      expect(seul.detailTrie, isEmpty);
    });

    test('un patron avec dépendances recommande l\'anonymisation', () {
      final DependancesUtilisateur patron =
          DependancesUtilisateur.fromMap(<String, dynamic>{
        'utilisateur_id': 'u-2',
        'est_patron': true,
        'nb_espaces': 2,
        'nb_collaborateurs': 3,
        'total_donnees': 4210,
        'detail': <String, dynamic>{
          'ventes': 4000,
          'produits': 200,
          'dettes': 10,
        },
        'suppression_possible': false,
        'recommandation': 'anonymisation',
      });

      expect(patron.sansImpact, isFalse);
      expect(patron.suppressionPossible, isFalse);
      expect(patron.recommandation, StrategieSuppression.anonymisation);
      expect(patron.totalDonnees, 4210);
      expect(patron.nbEspaces, 2);
      // Le détail est trié par volume décroissant : l'administrateur voit
      // d'abord ce qui pèse le plus.
      expect(patron.detailTrie.first.key, 'ventes');
      expect(patron.detailTrie.first.value, 4000);
      expect(patron.detailTrie.last.key, 'dettes');
    });

    test('tolère un détail absent et des valeurs textuelles', () {
      final DependancesUtilisateur d =
          DependancesUtilisateur.fromMap(<String, dynamic>{
        'utilisateur_id': 'u-3',
        'detail': <String, dynamic>{'ventes': '12', 'clients': 3},
      });

      expect(d.totalDonnees, 0);
      expect(d.detail['ventes'], 12);
      expect(d.detail['clients'], 3);
      expect(d.recommandation, isNull);
    });
  });

  // ==========================================================================
  //  4. MESSAGES D'ERREUR ET PROPORTIONS DE GRILLE
  // ==========================================================================
  group('AdminPlateformeService.messageErreur', () {
    test('extrait le texte français après le code serveur', () {
      expect(
        AdminPlateformeService.messageErreur(
            'ACCES_REFUSE|Cette action est réservée à l\'équipe plateforme.'),
        'Cette action est réservée à l\'équipe plateforme.',
      );
    });

    test('laisse intact un message sans code', () {
      expect(AdminPlateformeService.messageErreur('Erreur réseau'),
          'Erreur réseau');
      expect(AdminPlateformeService.messageErreur('CODE|'), 'CODE|');
    });
  });

  group('MiseEnPageAdaptative.proportionCartePour', () {
    test('ne modifie rien tant que le texte n\'est pas agrandi', () {
      expect(MiseEnPageAdaptative.proportionCartePour(1.28, 1.0), 1.28);
      expect(MiseEnPageAdaptative.proportionCartePour(1.28, 0.9), 1.28);
    });

    test('rend la carte plus haute quand le texte grandit', () {
      expect(MiseEnPageAdaptative.proportionCartePour(1.28, 1.3),
          closeTo(0.9846, 0.001));
      expect(MiseEnPageAdaptative.proportionCartePour(2.35, 1.3),
          closeTo(1.8077, 0.001));
    });

    test('respecte un minimum pour ne pas obtenir de cartes interminables',
        () {
      expect(MiseEnPageAdaptative.proportionCartePour(0.72, 3.0), 0.45);
      expect(
        MiseEnPageAdaptative.proportionCartePour(0.72, 3.0, minimum: 0.5),
        0.5,
      );
    });

    test('tolère des entrées incohérentes', () {
      expect(MiseEnPageAdaptative.proportionCartePour(0, 1.3), 0);
      expect(MiseEnPageAdaptative.proportionCartePour(1.28, 0), 1.28);
    });
  });
}
