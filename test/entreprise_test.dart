// test/entreprise_test.dart
//
// Tests unitaires du MODULE 1 — Gestion des entreprises.
//
// Ces tests ne touchent ni au réseau ni à Supabase : ils vérifient uniquement
// la logique métier (parsing, calculs, statuts). Ils peuvent donc être lancés
// sans configuration :
//
//     flutter test
//
// Ils couvrent les règles suivantes :
//   - montant total dû = montant de l'abonnement (frais d'ouverture exclus)
//   - solde restant = montant total dû - montant déjà payé
//   - un abonnement échu est affiché comme « Expiré » même si la base ne l'a
//     pas encore mis à jour
//   - les montants numériques arrivent de PostgREST en `int` ou en `String`
//     selon les cas, sans provoquer d'erreur de type

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/models/paiement_abonnement.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/models/utilisateur_entreprise.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

void main() {
  // =========================================================================
  // Affichage des montants
  // =========================================================================

  group('formatMontant', () {
    test('ajoute un séparateur de milliers et la devise', () {
      expect(formatMontant(999.0), '999 CDF');
      expect(formatMontant(1000.0), '1 000 CDF');
      expect(formatMontant(15000.0), '15 000 CDF');
      expect(formatMontant(1500000.0), '1 500 000 CDF');
    });

    test('arrondit les décimales', () {
      expect(formatMontant(14999.6), '15 000 CDF');
      expect(formatMontant(14999.4), '14 999 CDF');
    });

    test('gère zéro et les montants négatifs', () {
      expect(formatMontant(0.0), '0 CDF');
      expect(formatMontant(-2500.0), '-2 500 CDF');
    });

    test('respecte la devise demandée', () {
      expect(formatMontant(500.0, devise: 'USD'), '500 USD');
    });
  });

  group('formatDate', () {
    test('formate en jj/mm/aaaa', () {
      expect(formatDate(DateTime(2026, 9, 16)), '16/09/2026');
      expect(formatDate(DateTime(2026, 1, 5)), '05/01/2026');
    });

    test('renvoie un tiret quand la date est absente', () {
      expect(formatDate(null), '—');
      expect(formatDate(null, valeurAbsente: 'Non planifiée'), 'Non planifiée');
    });
  });

  // =========================================================================
  // Parsing défensif des données PostgREST
  // =========================================================================

  group('json_parsing', () {
    test('parseDouble accepte int, double, String et valeur absente', () {
      expect(parseDouble(5000), 5000.0);
      expect(parseDouble(5000.5), 5000.5);
      expect(parseDouble('5000'), 5000.0);
      expect(parseDouble('5000.25'), 5000.25);
      expect(parseDouble(null), 0.0);
      expect(parseDouble('texte'), 0.0);
      expect(parseDouble(null, fallback: 7), 7.0);
    });

    test('parseInt accepte int, double et String', () {
      expect(parseInt(7), 7);
      expect(parseInt(7.9), 7);
      expect(parseInt('7'), 7);
      expect(parseInt(null), 0);
      expect(parseInt('texte'), 0);
    });

    test('parseStringOrNull convertit une chaîne vide en null', () {
      expect(parseStringOrNull(null), isNull);
      expect(parseStringOrNull(''), isNull);
      expect(parseStringOrNull('   '), isNull);
      expect(parseStringOrNull(' Kinshasa '), 'Kinshasa');
    });

    test('parseMapList ignore les réponses de forme inattendue', () {
      expect(parseMapList(null), isEmpty);
      expect(parseMapList('pas une liste'), isEmpty);
      expect(parseMapList(<dynamic>[]), isEmpty);
      expect(
          parseMapList(<dynamic>[
            <String, dynamic>{'nom': 'Kinshasa'},
          ]).first['nom'],
          'Kinshasa');
    });
  });

  // =========================================================================
  // Statuts d'abonnement
  // =========================================================================

  group('StatutAbonnement', () {
    test('fromCode retrouve les 5 statuts stockés en base', () {
      expect(StatutAbonnement.fromCode('ESSAI_7J'), StatutAbonnement.essai7j);
      expect(StatutAbonnement.fromCode('ACTIF'), StatutAbonnement.actif);
      expect(StatutAbonnement.fromCode('EXPIRE'), StatutAbonnement.expire);
      expect(StatutAbonnement.fromCode('SUSPENDU'), StatutAbonnement.suspendu);
      expect(
        StatutAbonnement.fromCode('EN_ATTENTE_COMPLEMENT'),
        StatutAbonnement.enAttenteComplement,
      );
    });

    test('fromCode renvoie la valeur de repli pour un statut inattendu', () {
      expect(StatutAbonnement.fromCode(null), StatutAbonnement.inconnu);
      expect(
          StatutAbonnement.fromCode('AUTRE_CHOSE'), StatutAbonnement.inconnu);
    });

    test('les codes sont ceux du type PostgreSQL', () {
      expect(StatutAbonnement.essai7j.code, 'ESSAI_7J');
      expect(
          StatutAbonnement.enAttenteComplement.code, 'EN_ATTENTE_COMPLEMENT');
    });

    test('statutsFiltrables exclut la valeur de repli', () {
      expect(StatutAbonnement.statutsFiltrables, hasLength(5));
      expect(
        StatutAbonnement.statutsFiltrables,
        isNot(contains(StatutAbonnement.inconnu)),
      );
    });
  });

  // =========================================================================
  // Lecture d'une entreprise
  // =========================================================================

  group('Entreprise.fromMap', () {
    test('lit les colonnes de public.entreprises', () {
      final Entreprise entreprise = Entreprise.fromMap(<String, dynamic>{
        'id': 'uuid-1',
        'nom': 'Établissement Lukengu',
        'ville_id': 'v1',
        'activite_id': 'a1',
        'groupe_tarifaire_id': 'g1',
        'statut': 'ESSAI_7J',
        'montant_total_du': 25000,
        'montant_deja_paye': 10000,
        'solde_restant': 15000,
      });

      expect(entreprise.id, 'uuid-1');
      expect(entreprise.nom, 'Établissement Lukengu');
      expect(entreprise.villeId, 'v1');
      expect(entreprise.statut, StatutAbonnement.essai7j);
      expect(entreprise.montantTotalDu, 25000.0);
      expect(entreprise.montantDejaPaye, 10000.0);
      expect(entreprise.soldeRestant, 15000.0);
    });

    test('recalcule le solde si la colonne est absente', () {
      final Entreprise entreprise = Entreprise.fromMap(<String, dynamic>{
        'id': 'uuid-1',
        'nom': 'Test',
        'montant_total_du': 5000,
        'montant_deja_paye': 2000,
      });

      expect(entreprise.soldeRestant, 3000.0);
    });

    test('ne renvoie jamais un solde négatif', () {
      final Entreprise entreprise = Entreprise.fromMap(<String, dynamic>{
        'id': 'uuid-1',
        'nom': 'Test',
        'montant_total_du': 1000,
        'montant_deja_paye': 1500,
      });

      expect(entreprise.soldeRestant, 0.0);
      expect(entreprise.estSolde, isTrue);
    });

    test('accepte les montants renvoyés sous forme de texte', () {
      final Entreprise entreprise = Entreprise.fromMap(<String, dynamic>{
        'id': 'uuid-1',
        'nom': 'Test',
        'montant_total_du': '25000',
        'montant_deja_paye': '0',
      });

      expect(entreprise.montantTotalDu, 25000.0);
      expect(entreprise.soldeRestant, 25000.0);
    });

    test('tolère un statut inconnu sans planter', () {
      final Entreprise entreprise = Entreprise.fromMap(<String, dynamic>{
        'id': 'uuid-1',
        'nom': 'Test',
        'statut': 'VALEUR_INCONNUE',
      });

      expect(entreprise.statut, StatutAbonnement.inconnu);
    });

    test('tolère une réponse minimale', () {
      final Entreprise entreprise = Entreprise.fromMap(<String, dynamic>{});

      expect(entreprise.id, '');
      expect(entreprise.nom, '');
      expect(entreprise.montantTotalDu, 0.0);
      expect(entreprise.statut, StatutAbonnement.inconnu);
    });
  });

  // =========================================================================
  // Calcul des jours restants
  // =========================================================================

  group('Entreprise.joursRestants', () {
    Entreprise avecExpiration(DateTime? expiration) => Entreprise(
          id: 'x',
          nom: 'Test',
          dateExpiration: expiration,
        );

    test('renvoie null sans date d\'expiration', () {
      expect(avecExpiration(null).joursRestants, isNull);
    });

    test('compte les jours à la journée, pas en heures', () {
      expect(avecExpiration(DateTime.now()).joursRestants, 0);
      expect(
        avecExpiration(DateTime.now().add(const Duration(days: 5)))
            .joursRestants,
        5,
      );
      expect(
        avecExpiration(DateTime.now().subtract(const Duration(days: 2)))
            .joursRestants,
        -2,
      );
    });

    test('signale un abonnement qui se termine bientôt', () {
      final Entreprise bientot = avecExpiration(
        DateTime.now().add(const Duration(days: 2)),
      );
      final Entreprise plusTard = avecExpiration(
        DateTime.now().add(const Duration(days: 20)),
      );

      expect(bientot.bientotExpire, isTrue);
      expect(plusTard.bientotExpire, isFalse);
    });
  });

  // =========================================================================
  // Statut affiché (expiration non appliquée par la base)
  // =========================================================================

  group('Entreprise.statutEffectif', () {
    Entreprise entreprise({
      required StatutAbonnement statut,
      required DateTime expiration,
    }) =>
        Entreprise(
          id: 'x',
          nom: 'Test',
          statut: statut,
          dateExpiration: expiration,
        );

    test('un essai dépassé est affiché comme expiré', () {
      final Entreprise e = entreprise(
        statut: StatutAbonnement.essai7j,
        expiration: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(e.statutEffectif, StatutAbonnement.expire);
      expect(e.estExpiree, isTrue);
      expect(e.statutDesynchronise, isTrue);
    });

    test('un abonnement actif dépassé est affiché comme expiré', () {
      final Entreprise e = entreprise(
        statut: StatutAbonnement.actif,
        expiration: DateTime.now().subtract(const Duration(days: 3)),
      );

      expect(e.statutEffectif, StatutAbonnement.expire);
      expect(e.statutDesynchronise, isTrue);
    });

    test('un essai en cours reste un essai', () {
      final Entreprise e = entreprise(
        statut: StatutAbonnement.essai7j,
        expiration: DateTime.now().add(const Duration(days: 4)),
      );

      expect(e.statutEffectif, StatutAbonnement.essai7j);
      expect(e.statutDesynchronise, isFalse);
    });

    test('un abonnement suspendu n\'est jamais requalifié en expiré', () {
      final Entreprise e = entreprise(
        statut: StatutAbonnement.suspendu,
        expiration: DateTime.now().subtract(const Duration(days: 10)),
      );

      expect(e.statutEffectif, StatutAbonnement.suspendu);
      expect(e.statutDesynchronise, isFalse);
    });

    test('un statut inconnu n\'est pas requalifié', () {
      final Entreprise e = entreprise(
        statut: StatutAbonnement.inconnu,
        expiration: DateTime.now().subtract(const Duration(days: 10)),
      );

      expect(e.statutEffectif, StatutAbonnement.inconnu);
    });
  });

  // =========================================================================
  // Avancement du paiement
  // =========================================================================

  group('Entreprise.tauxPaiement', () {
    test('calcule la part de l\'abonnement déjà réglée', () {
      const Entreprise e = Entreprise(
        id: 'x',
        nom: 'Test',
        montantTotalDu: 5000,
        montantDejaPaye: 2500,
      );

      expect(e.tauxPaiement, 0.5);
    });

    test('vaut 0 quand le total dû est nul', () {
      const Entreprise e = Entreprise(id: 'x', nom: 'Test');

      expect(e.tauxPaiement, 0);
    });

    test('est borné à 1 en cas de trop-perçu', () {
      const Entreprise e = Entreprise(
        id: 'x',
        nom: 'Test',
        montantTotalDu: 1000,
        montantDejaPaye: 1500,
      );

      expect(e.tauxPaiement, 1);
    });
  });

  // =========================================================================
  // Groupes tarifaires
  // =========================================================================

  group('GroupeTarifaire.fromMap', () {
    test('lit les nombres renvoyés en int comme en String', () {
      final GroupeTarifaire groupe = GroupeTarifaire.fromMap(<String, dynamic>{
        'id': 'g1',
        'activite_id': 'a1',
        'nom': 'Standard',
        'frais_ouverture': 10000,
        'montant_abonnement': '25000',
        'duree_essai_jours': 7,
        'duree_abonnement_jours': '30',
        'prix_par_collaborateur': 2000,
      });

      expect(groupe.activiteId, 'a1');
      expect(groupe.fraisOuverture, 10000.0);
      expect(groupe.montantAbonnement, 25000.0);
      expect(groupe.dureeEssaiJours, 7);
      expect(groupe.dureeAbonnementJours, 30);
      expect(groupe.prixParCollaborateur, 2000.0);
    });

    test('formate les durées avec le bon pluriel', () {
      const GroupeTarifaire un = GroupeTarifaire(
        id: 'g',
        nom: 'A',
        dureeEssaiJours: 1,
        dureeAbonnementJours: 1,
      );
      const GroupeTarifaire plusieurs = GroupeTarifaire(
        id: 'g',
        nom: 'B',
        dureeEssaiJours: 7,
        dureeAbonnementJours: 30,
      );

      expect(un.dureeEssaiLibelle, '1 jour');
      expect(plusieurs.dureeEssaiLibelle, '7 jours');
      expect(plusieurs.dureeAbonnementLibelle, '30 jours');
    });
  });

  // =========================================================================
  // Règle de facturation
  // =========================================================================

  group('EntrepriseService.calculerMontantTotalDu', () {
    test('additionne les frais d\'ouverture et l\'abonnement', () {
      const GroupeTarifaire groupe = GroupeTarifaire(
        id: 'g1',
        nom: 'Standard',
        fraisOuverture: 10000,
        montantAbonnement: 25000,
      );

      expect(
          EntrepriseService.instance.calculerMontantTotalDu(groupe), 35000.0);
    });

    test('vaut zéro quand la grille tarifaire ne définit aucun montant', () {
      const GroupeTarifaire vide = GroupeTarifaire(id: 'g2', nom: 'Vide');

      expect(EntrepriseService.instance.calculerMontantTotalDu(vide), 0.0);
    });
  });

  // =========================================================================
  // Historique des encaissements
  // =========================================================================

  group('PaiementAbonnement.fromMap', () {
    test('lit les colonnes de public.paiements_abonnement', () {
      final PaiementAbonnement paiement =
          PaiementAbonnement.fromMap(<String, dynamic>{
        'id': 'p1',
        'entreprise_id': 'e1',
        'montant': 15000,
        'total_apres': 15000,
        'solde_apres': 0,
        'prolongation_jours': 30,
        'enregistre_par': 'u1',
        'created_at': '2026-09-16T10:00:00Z',
      });

      expect(paiement.entrepriseId, 'e1');
      expect(paiement.montant, 15000.0);
      expect(paiement.soldeApres, 0.0);
      expect(paiement.prolongationJours, 30);
      expect(paiement.aProlonge, isTrue);
      expect(paiement.createdAt, isNotNull);
    });

    test('tolère une réponse minimale', () {
      final PaiementAbonnement paiement =
          PaiementAbonnement.fromMap(const <String, dynamic>{});

      expect(paiement.montant, 0.0);
      expect(paiement.totalApres, isNull);
      expect(paiement.prolongationJours, 0);
      expect(paiement.aProlonge, isFalse);
    });
  });

  // =========================================================================
  // Contrôle d'accès à la connexion
  // =========================================================================

  group('EntrepriseService.evaluerAcces', () {
    final DateTime maintenant = DateTime(2026, 9, 16, 12);

    Map<String, dynamic> ligne(String statut, DateTime? expiration) {
      return <String, dynamic>{
        'entreprise_id': 'e1',
        'nom': 'Test',
        'statut': statut,
        'date_expiration': expiration?.toIso8601String(),
      };
    }

    test("n'exige rien d'un utilisateur sans entreprise rattachée", () {
      expect(
        EntrepriseService.evaluerAcces(const <Map<String, dynamic>>[]),
        isNull,
      );
    });

    test('laisse passer tant qu\'une entreprise est active', () {
      final String? message = EntrepriseService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne('SUSPENDU', maintenant.add(const Duration(days: 10))),
          ligne('ACTIF', maintenant.add(const Duration(days: 20))),
        ],
        maintenant: maintenant,
      );

      expect(message, isNull);
    });

    test('laisse passer un essai en cours', () {
      final String? message = EntrepriseService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne('ESSAI_7J', maintenant.add(const Duration(days: 3))),
        ],
        maintenant: maintenant,
      );

      expect(message, isNull);
    });

    test('bloque quand toutes les entreprises sont suspendues', () {
      final String? message = EntrepriseService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne('SUSPENDU', maintenant.add(const Duration(days: 10))),
        ],
        maintenant: maintenant,
      );

      expect(message, isNotNull);
      expect(message, contains('suspendu'));
    });

    test('bloque quand tous les abonnements ont expiré', () {
      final String? message = EntrepriseService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne('EXPIRE', maintenant.subtract(const Duration(days: 1))),
        ],
        maintenant: maintenant,
      );

      expect(message, isNotNull);
      expect(message, contains('expiré'));
    });

    test('bloque un essai dépassé même si la base affiche encore ESSAI_7J', () {
      final String? message = EntrepriseService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne('ESSAI_7J', maintenant.subtract(const Duration(hours: 2))),
        ],
        maintenant: maintenant,
      );

      expect(message, isNotNull);
    });

    test('mentionne la suspension plutôt que l\'expiration', () {
      final String? message = EntrepriseService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne('EXPIRE', maintenant.subtract(const Duration(days: 5))),
          ligne('SUSPENDU', maintenant.add(const Duration(days: 5))),
        ],
        maintenant: maintenant,
      );

      expect(message, contains('suspendu'));
    });
  });

  // =========================================================================
  // Utilisateurs (rattachement à une entreprise)
  // =========================================================================

  group('UtilisateurEntreprise.fromMap', () {
    test('lit les colonnes utiles de public.utilisateurs', () {
      final UtilisateurEntreprise utilisateur =
          UtilisateurEntreprise.fromMap(<String, dynamic>{
        'id': 'u1',
        'prenom': 'Andre',
        'nom': 'Lukengu',
        'email': 'lukengu@biashara.com',
        'role': 'vendor',
        'parent_id': null,
        'entreprise_id': 'e1',
      });

      expect(utilisateur.nomComplet, 'Andre Lukengu');
      expect(utilisateur.entrepriseId, 'e1');
      expect(utilisateur.roleLibelle, 'Patron / Vendeur');
      expect(utilisateur.estCollaborateur, isFalse);
    });

    test('rattache un collaborateur à son patron', () {
      final UtilisateurEntreprise collaborateur =
          UtilisateurEntreprise.fromMap(<String, dynamic>{
        'id': 'u2',
        'nom': 'Collaborateur',
        'email': 'collaborateur@biashara.com',
        'role': 'collaborator',
        'parent_id': 'u1',
        'entreprise_id': null,
      });

      expect(collaborateur.estCollaborateur, isTrue);
      expect(collaborateur.parentId, 'u1');
      expect(collaborateur.entrepriseId, isNull);
      expect(collaborateur.roleLibelle, 'Collaborateur');
    });

    test("retombe sur l'e-mail quand le nom est vide", () {
      final UtilisateurEntreprise utilisateur =
          UtilisateurEntreprise.fromMap(<String, dynamic>{
        'id': 'u3',
        'nom': '',
        'prenom': '',
        'email': 'josue@biashara.com',
      });

      expect(utilisateur.nomComplet, 'josue@biashara.com');
    });

    test('détecte un administrateur', () {
      final UtilisateurEntreprise admin =
          UtilisateurEntreprise.fromMap(<String, dynamic>{
        'id': 'u4',
        'nom': 'Andre',
        'email': 'andrelukengu67@gmail.com',
        'role': 'admin',
      });

      expect(admin.estAdministrateur, isTrue);
      expect(admin.roleLibelle, 'Administrateur');
    });

    test('tolère une réponse minimale', () {
      final UtilisateurEntreprise utilisateur =
          UtilisateurEntreprise.fromMap(const <String, dynamic>{});

      expect(utilisateur.id, '');
      expect(utilisateur.role, 'vendor');
      expect(utilisateur.parentId, isNull);
      expect(utilisateur.entrepriseId, isNull);
    });
  });
}
