// test/verrouillage_test.dart
//
// 🧾 MODULE 17 — VERROUILLAGE DES COMPTES NON ACTIVÉS.
//
// Vérifie les règles PURES (sans réseau) qui décident :
//   1. de l'état d'accès d'un compte (activation en attente → verrou) ;
//   2. des écrans réservés aux comptes OPÉRATIONNELS (cadenas + middleware
//      de navigation, y compris par lien direct).

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/espace.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/article_service.dart';

void main() {
  // =========================================================================
  //  1. ÉTAT D'ACCÈS — DOUBLE VALIDATION (GESTIONNAIRE → FINANCE)
  // =========================================================================

  group('Module 17 — état d\'accès et activation', () {
    Map<String, dynamic> ligne({
      required String statut,
      String? activationEtape,
      DateTime? expiration,
      double paye = 0,
      double solde = 0,
    }) {
      return <String, dynamic>{
        'statut': statut,
        'activation_etape': activationEtape,
        'date_expiration': expiration?.toIso8601String(),
        'montant_deja_paye': paye,
        'solde_restant': solde,
      };
    }

    final DateTime futur = DateTime.now().add(const Duration(days: 20));

    test('dossier en attente de vérification : verrou (pas encore activé)', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(
            statut: 'EN_ATTENTE_COMPLEMENT',
            activationEtape: 'en_attente_verification',
          ),
        ],
      );

      expect(etat.bloque, isFalse);
      expect(etat.lectureSeule, isTrue);
      expect(etat.enAttenteActivation, isTrue);
      expect(etat.accesComplet, isFalse);
      expect(etat.message, contains('en attente de validation'));
    });

    test('dossier vérifié (attente finance) : toujours verrouillé', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(statut: 'EN_ATTENTE_COMPLEMENT', activationEtape: 'verifie'),
        ],
      );

      expect(etat.enAttenteActivation, isTrue);
      expect(etat.lectureSeule, isTrue);
      expect(etat.accesComplet, isFalse);
    });

    test('dossier rejeté : verrouillé (l\'utilisateur suit son dossier)', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(statut: 'EN_ATTENTE_COMPLEMENT', activationEtape: 'rejete'),
        ],
      );

      expect(etat.enAttenteActivation, isTrue);
      expect(etat.accesComplet, isFalse);
    });

    test(
      'activation_etape prime sur un statut ESSAI : pas d\'opération avant '
      'la validation de la finance',
      () {
        final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
          <Map<String, dynamic>>[
            ligne(
              statut: 'ESSAI_7J',
              activationEtape: 'en_attente_verification',
              expiration: futur,
            ),
          ],
        );

        expect(etat.accesComplet, isFalse);
        expect(etat.enAttenteActivation, isTrue);
      },
    );

    test('compte ACTIVÉ (finance) : accès complet, aucun cadenas', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(
            statut: 'ACTIF',
            activationEtape: 'actif',
            expiration: futur,
            paye: 20000,
          ),
        ],
      );

      expect(etat.accesComplet, isTrue);
      expect(etat.bloque, isFalse);
      expect(etat.lectureSeule, isFalse);
      expect(etat.enAttenteActivation, isFalse);
    });

    test('abonnement expiré : lecture seule (opérations verrouillées)', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(
            statut: 'ACTIF',
            activationEtape: 'actif',
            expiration: DateTime.now().subtract(const Duration(days: 3)),
            paye: 20000,
          ),
        ],
      );

      expect(etat.lectureSeule, isTrue);
      expect(etat.enAttenteActivation, isFalse);
      expect(etat.accesComplet, isFalse);
    });

    test('compte restreint (solde impayé) : lecture seule', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(
            statut: 'EN_ATTENTE_COMPLEMENT',
            activationEtape: 'restreint',
          ),
        ],
      );

      expect(etat.lectureSeule, isTrue);
      expect(etat.enAttenteActivation, isFalse);
      expect(etat.accesComplet, isFalse);
    });

    test('compte suspendu par l\'administrateur : accès bloqué', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(statut: 'SUSPENDU', activationEtape: 'actif'),
        ],
      );

      expect(etat.bloque, isTrue);
      expect(etat.accesComplet, isFalse);
    });

    test('une entreprise opérationnelle ouvre l\'accès aux autres', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(
            statut: 'EN_ATTENTE_COMPLEMENT',
            activationEtape: 'en_attente_verification',
          ),
          ligne(
            statut: 'ACTIF',
            activationEtape: 'actif',
            expiration: futur,
            paye: 20000,
          ),
        ],
      );

      expect(etat.accesComplet, isTrue);
    });

    test('migration absente (pas d\'activation_etape) : comportement Module 3',
        () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(statut: 'EN_ATTENTE_COMPLEMENT'),
        ],
      );

      expect(etat.lectureSeule, isTrue);
      expect(etat.enAttenteActivation, isFalse);
      expect(etat.statut, StatutAbonnement.enAttenteComplement);
    });

    test('aucune entreprise : fail-open (jamais de verrou accidentel)', () {
      final EtatAccesAbonnement etat =
          AbonnementService.evaluerAcces(const <Map<String, dynamic>>[]);

      expect(etat.accesComplet, isTrue);
      expect(etat.enAttenteActivation, isFalse);
    });
  });

  // =========================================================================
  //  2. ÉCRANS RÉSERVÉS AUX COMPTES OPÉRATIONNELS (middleware)
  // =========================================================================

  group('Module 17 — chemins verrouillés', () {
    test('les opérations commerciales sont verrouillées', () {
      const List<String> verrouilles = <String>[
        '/main/new-sale',
        '/scanner',
        '/main/panier',
        '/main/panier/encaissement',
        '/main/add-product',
        '/main/edit-product',
        '/main/articles/new',
        '/main/articles/categories',
        '/main/articles/9f1c/edit',
        '/main/articles/9f1c/conditionnements/new',
        '/main/stock/approvisionnement',
        '/main/stock/ajustement',
        '/main/stock/inventaire',
        '/main/caisse/cloture',
        '/main/depenses/new',
        '/main/dettes/new',
        '/main/clients',
        '/main/inventaires',
        '/settings/manage-users',
        '/settings/manage-categories',
        '/import-produits',
        '/main/hotel/chambres',
        '/main/hotel/reservations',
        '/main/hotel/reception',
        '/main/restaurant/tables',
        '/main/restaurant/commandes',
        '/main/restaurant/cuisine',
        '/main/evenements',
        '/main/evenements/new',
        '/main/evenements/salles',
        '/main/production',
        '/main/production/matieres',
      ];

      for (final String chemin in verrouilles) {
        expect(
          AbonnementService.cheminVerrouille(chemin),
          isTrue,
          reason: '$chemin doit être verrouillé pour un compte non activé',
        );
      }
    });

    test('la consultation reste toujours accessible', () {
      const List<String> libres = <String>[
        '/main',
        '/main/mon-activation',
        '/main/compte-verrouille',
        '/main/mes-entreprises',
        '/main/articles',
        '/main/articles/9f1c',
        '/main/articles/expirations',
        '/main/stock',
        '/main/stock/9f1c',
        '/main/caisse',
        '/main/finance',
        '/main/finance/rapports',
        '/main/rapports',
        '/main/ventes',
        '/main/depenses',
        '/main/dettes',
        '/reports',
        '/settings',
        '/login',
        '/admin',
        '/assistant-ia',
      ];

      for (final String chemin in libres) {
        expect(
          AbonnementService.cheminVerrouille(chemin),
          isFalse,
          reason: '$chemin doit rester consultable (lecture seule)',
        );
      }
    });

    test('un chemin vide ou inconnu n\'est jamais bloqué', () {
      expect(AbonnementService.cheminVerrouille(''), isFalse);
      expect(AbonnementService.cheminVerrouille('/inconnu'), isFalse);
    });
  });

  // =========================================================================
  //  3. CATÉGORIE D'ACTIVITÉ (l'environnement suit le type choisi)
  // =========================================================================

  group('Module 17 — catégories d\'activité', () {
    test('les catégories seedées sont reconnues', () {
      expect(TypeEspace.fromCode('hotel'), TypeEspace.hotel);
      expect(TypeEspace.fromCode('restaurant'), TypeEspace.restaurant);
      expect(TypeEspace.fromCode('pharmacie'), TypeEspace.pharmacie);
      expect(TypeEspace.fromCode('salle_fetes'), TypeEspace.salleFetes);
      expect(TypeEspace.fromCode('boulangerie'), TypeEspace.boulangerie);
      expect(TypeEspace.fromCode('boucherie'), TypeEspace.boucherie);
      expect(TypeEspace.fromCode('mode'), TypeEspace.mode);
      expect(TypeEspace.fromCode('salon_de_coiffure'), TypeEspace.salon);
      expect(TypeEspace.fromCode('boutique'), TypeEspace.boutique);
    });

    test('l\'espace conserve le code brut du type (types Expert inclus)', () {
      final Espace hotel = Espace.fromMap(<String, dynamic>{
        'id': 'esp-1',
        'nom': 'HÔTEL KM',
        'type': 'hotel',
      });
      expect(hotel.type, TypeEspace.hotel);
      expect(hotel.codeType, 'hotel');

      final Espace expert = Espace.fromMap(<String, dynamic>{
        'id': 'esp-2',
        'nom': 'Salon Élégance',
        'type': 'salon_de_coiffure',
      });
      expect(expert.codeType, 'salon_de_coiffure');

      final Espace sansType = Espace.fromMap(<String, dynamic>{
        'id': 'esp-3',
        'nom': 'Sans type',
      });
      expect(sansType.codeType, 'autre');
    });

    test('un type inconnu (créé par l\'Expert) ne casse pas l\'affichage', () {
      expect(TypeEspace.fromCode('garage_auto'), TypeEspace.autre);
      expect(TypeEspace.fromCode(null), TypeEspace.autre);
    });

    test('les libellés affichés sont ceux du métier', () {
      expect(TypeEspace.hotel.libelle, 'Hôtel');
      expect(TypeEspace.salleFetes.libelle, 'Salle des fêtes');
      expect(TypeEspace.mode.libelle, 'Mode & vêtements');
    });
  });

  // =========================================================================
  //  4. MESSAGES SERVEUR (refus du verrou affichés en français)
  // =========================================================================

  group('Module 17 — messages de refus', () {
    test('le code technique est retiré du message affiché', () {
      expect(
        ArticleService.messageErreur(
          'ACTIVATION_REQUISE|Votre compte est en attente de validation.',
        ),
        'Votre compte est en attente de validation.',
      );
      expect(
        ArticleService.messageErreur(
          'ABONNEMENT_EXPIRE|Abonnement échu ou compte restreint.',
        ),
        'Abonnement échu ou compte restreint.',
      );
      expect(
        ArticleService.messageErreur('ABONNEMENT_BLOQUE|Compte suspendu.'),
        'Compte suspendu.',
      );
    });

    test('un message sans code reste inchangé', () {
      expect(ArticleService.messageErreur('Erreur inconnue'),
          'Erreur inconnue');
    });
  });
}
