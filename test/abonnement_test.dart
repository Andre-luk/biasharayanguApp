// test/abonnement_test.dart
//
// Tests unitaires du MODULE 3 — Moteur d'abonnement.
//
// Ces tests ne touchent ni au réseau ni à Supabase : ils vérifient la logique
// métier pure (statuts, dates, accès), qui reproduit exactement les règles
// appliquées côté base par `20260916000003_module3_abonnement.sql`.
//
//     flutter test test/abonnement_test.dart
//
// Scénarios couverts (ceux du cahier des charges) :
//   1. Nouvelle entreprise → ESSAI_7J → 7 jours passent → EXPIRE
//   2. Avance de 5 000 sur 20 000 → le statut reste ESSAI_7J
//   3. Paiement des 15 000 restants → ACTIF + 30 jours
//   4. Après 30 jours → EXPIRE
//   5. Paiement après expiration → ACTIF + 30 jours

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/paiement_laperle.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';

void main() {
  // Date de référence stable : aucun test ne dépend de l'heure réelle.
  final DateTime t0 = DateTime(2026, 9, 16, 8, 0);
  const double total = 20000;
  const double avance = 5000;

  StatutAbonnement statutEffectif(
    StatutAbonnement statut,
    DateTime expiration,
    double paye,
    double solde,
    DateTime maintenant,
  ) {
    return AbonnementService.calculerStatutEffectif(
      statut: statut,
      dateExpiration: expiration,
      montantDejaPaye: paye,
      soldeRestant: solde,
      maintenant: maintenant,
    );
  }

  // =========================================================================
  // SCÉNARIO 1 — Nouvelle entreprise : essai puis expiration
  // =========================================================================

  group('Scénario 1 — ESSAI_7J → 7 jours → EXPIRE', () {
    final DateTime expirationEssai = t0.add(const Duration(days: 7));

    test("pendant l'essai, le statut reste ESSAI_7J", () {
      expect(
        statutEffectif(
          StatutAbonnement.essai7j,
          expirationEssai,
          0,
          total,
          t0.add(const Duration(days: 3)),
        ),
        StatutAbonnement.essai7j,
      );

      // Une minute avant l'échéance : toujours en essai.
      expect(
        statutEffectif(
          StatutAbonnement.essai7j,
          expirationEssai,
          0,
          total,
          expirationEssai.subtract(const Duration(minutes: 1)),
        ),
        StatutAbonnement.essai7j,
      );
    });

    test('7 jours plus tard, sans paiement : EXPIRE', () {
      expect(
        statutEffectif(
          StatutAbonnement.essai7j,
          expirationEssai,
          0,
          total,
          expirationEssai.add(const Duration(minutes: 1)),
        ),
        StatutAbonnement.expire,
      );
    });
  });

  // =========================================================================
  // SCÉNARIO 2 — Avance partielle pendant l'essai
  // =========================================================================

  group('Scénario 2 — avance de 5 000 sur 20 000', () {
    final DateTime expirationEssai = t0.add(const Duration(days: 7));
    const double soldeApresAvance = total - avance;

    test("le statut reste ESSAI_7J tant que le solde n'est pas réglé", () {
      expect(
        statutEffectif(
          StatutAbonnement.essai7j,
          expirationEssai,
          avance,
          soldeApresAvance,
          t0.add(const Duration(days: 2)),
        ),
        StatutAbonnement.essai7j,
      );
    });

    test(
        "après l'échéance, une avance partielle bascule en "
        'EN_ATTENTE_COMPLEMENT (accès lecture seule)', () {
      expect(
        statutEffectif(
          StatutAbonnement.essai7j,
          expirationEssai,
          avance,
          soldeApresAvance,
          expirationEssai.add(const Duration(days: 1)),
        ),
        StatutAbonnement.enAttenteComplement,
      );
    });
  });

  // =========================================================================
  // SCÉNARIO 3 — Paiement du solde restant : ACTIF + 30 jours
  // =========================================================================

  group('Scénario 3 — paiement des 15 000 restants : ACTIF + 30 jours', () {
    test(
        "l'activation pendant l'essai repart d'aujourd'hui (pas de la fin "
        "d'essai)", () {
      final DateTime paiement = t0.add(const Duration(days: 3));

      final DateTime expiration = AbonnementService.calculerFinCycle(
        statut: StatutAbonnement.essai7j,
        dateExpiration: t0.add(const Duration(days: 7)),
        dureeJours: 30,
        maintenant: paiement,
      );

      expect(expiration, paiement.add(const Duration(days: 30)));
    });

    test('le solde calculé est nul : abonnement soldé', () {
      final Entreprise entreprise = Entreprise.fromMap(<String, dynamic>{
        'id': 'e1',
        'nom': 'Boulangerie Test',
        'statut': 'ACTIF',
        'montant_total_du': total,
        'montant_deja_paye': total,
        'solde_restant': 0,
        'date_activation': t0.toIso8601String(),
        'date_expiration': t0.add(const Duration(days: 30)).toIso8601String(),
      });

      final SoldeAbonnement solde =
          AbonnementService.soldeDepuisEntreprise(entreprise, maintenant: t0);

      expect(solde.total, total);
      expect(solde.paye, total);
      expect(solde.solde, 0);
      expect(solde.estSolde, isTrue);
      expect(solde.tauxPaiement, 1);
      expect(solde.statut, StatutAbonnement.actif);
    });
  });

  // =========================================================================
  // SCÉNARIO 4 — Après 30 jours : EXPIRE
  // =========================================================================

  group('Scénario 4 — après 30 jours : EXPIRE', () {
    test('un abonnement soldé mais échu passe en EXPIRE', () {
      final DateTime expiration = t0.add(const Duration(days: 30));

      expect(
        statutEffectif(
          StatutAbonnement.actif,
          expiration,
          total, // intégralement payé
          0, // plus rien à devoir
          expiration.add(const Duration(minutes: 1)),
        ),
        StatutAbonnement.expire,
      );
    });
  });

  // =========================================================================
  // SCÉNARIO 5 — Paiement après expiration : ACTIF + 30 jours
  // =========================================================================

  group('Scénario 5 — renouvellement', () {
    test('après expiration, le nouveau cycle repart de maintenant', () {
      final DateTime expirationPassee = t0.subtract(const Duration(days: 2));

      final DateTime nouvelle = AbonnementService.calculerFinCycle(
        statut: StatutAbonnement.expire,
        dateExpiration: expirationPassee,
        dureeJours: 30,
        maintenant: t0,
      );

      expect(nouvelle, t0.add(const Duration(days: 30)));
    });

    test(
        "renouvellement anticipé (abonnement encore actif) : les jours payés "
        'sont conservés', () {
      final DateTime expirationFuture = t0.add(const Duration(days: 5));

      final DateTime nouvelle = AbonnementService.calculerFinCycle(
        statut: StatutAbonnement.actif,
        dateExpiration: expirationFuture,
        dureeJours: 30,
        maintenant: t0,
      );

      expect(nouvelle, expirationFuture.add(const Duration(days: 30)));
    });
  });

  // =========================================================================
  // MIDDLEWARE — Décision d'accès (login / démarrage)
  // =========================================================================

  group("Middleware — accès à l'application", () {
    Map<String, dynamic> ligne({
      required String statut,
      DateTime? expiration,
      double paye = 0,
      double solde = total,
    }) {
      return <String, dynamic>{
        'statut': statut,
        'date_expiration': expiration?.toIso8601String(),
        'montant_deja_paye': paye,
        'solde_restant': solde,
      };
    }

    test('aucune entreprise rattachée : accès ouvert (fail-open)', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        const <Map<String, dynamic>>[],
        maintenant: t0,
      );

      expect(etat.accesComplet, isTrue);
      expect(etat.bloque, isFalse);
    });

    test('essai en cours ou abonnement actif : accès complet', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(
            statut: 'ESSAI_7J',
            expiration: t0.add(const Duration(days: 3)),
          ),
        ],
        maintenant: t0,
      );

      expect(etat.accesComplet, isTrue);
    });

    test('abonnement expiré sans paiement : lecture seule, pas de blocage', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(
            statut: 'ESSAI_7J',
            expiration: t0.subtract(const Duration(days: 1)),
          ),
        ],
        maintenant: t0,
      );

      expect(etat.bloque, isFalse);
      expect(etat.lectureSeule, isTrue);
      expect(etat.statut, StatutAbonnement.expire);
      expect(etat.message, isNotNull);
    });

    test(
        'abonnement échu avec paiement partiel : lecture seule, statut '
        'EN_ATTENTE_COMPLEMENT', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(
            statut: 'ACTIF',
            expiration: t0.subtract(const Duration(days: 1)),
            paye: avance,
            solde: total - avance,
          ),
        ],
        maintenant: t0,
      );

      expect(etat.bloque, isFalse);
      expect(etat.lectureSeule, isTrue);
      expect(etat.statut, StatutAbonnement.enAttenteComplement);
    });

    test('entreprise suspendue : accès bloqué (décision administrateur)', () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(statut: 'SUSPENDU'),
        ],
        maintenant: t0,
      );

      expect(etat.bloque, isTrue);
      expect(etat.lectureSeule, isFalse);
      expect(etat.statut, StatutAbonnement.suspendu);
    });

    test("une entreprise valide suffit à ouvrir l'accès complet", () {
      final EtatAccesAbonnement etat = AbonnementService.evaluerAcces(
        <Map<String, dynamic>>[
          ligne(
            statut: 'ESSAI_7J',
            expiration: t0.subtract(const Duration(days: 2)),
          ),
          ligne(
            statut: 'ACTIF',
            expiration: t0.add(const Duration(days: 10)),
          ),
        ],
        maintenant: t0,
      );

      expect(etat.accesComplet, isTrue);
    });
  });

  // =========================================================================
  // MODÈLE — Paiement La Perle
  // =========================================================================

  group('PaiementLaperle', () {
    test('convertit une ligne de la table en modèle', () {
      final PaiementLaperle paiement =
          PaiementLaperle.fromMap(<String, dynamic>{
        'id': 'p1',
        'entreprise_id': 'e1',
        'montant': 5000, // PostgREST peut renvoyer un int
        'type_paiement': 'AVANCE',
        'mode_paiement': 'Espèces',
        'note': 'Acompte de démarrage',
        'total_apres': 5000,
        'solde_apres': 15000,
        'prolongation_jours': 0,
        'created_at': t0.toIso8601String(),
      });

      expect(paiement.montant, 5000);
      expect(paiement.typePaiement, TypePaiement.avance);
      expect(paiement.modePaiement, 'Espèces');
      expect(paiement.note, 'Acompte de démarrage');
      expect(paiement.soldeApres, 15000);
      expect(paiement.aProlonge, isFalse);
    });

    test('un type inconnu ne fait pas échouer le parsing', () {
      final PaiementLaperle paiement =
          PaiementLaperle.fromMap(<String, dynamic>{
        'id': 'p2',
        'montant': 1000,
        'type_paiement': 'TYPE_INCONNU',
      });

      expect(paiement.typePaiement, isNull);
      expect(paiement.montant, 1000);
    });

    test('un paiement prolongé est détecté', () {
      final PaiementLaperle paiement =
          PaiementLaperle.fromMap(<String, dynamic>{
        'id': 'p3',
        'montant': 20000,
        'type_paiement': 'RENOUVELLEMENT',
        'prolongation_jours': 30,
      });

      expect(paiement.aProlonge, isTrue);
      expect(paiement.typePaiement, TypePaiement.renouvellement);
    });
  });
}
