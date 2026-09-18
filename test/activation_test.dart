// test/activation_test.dart
//
// Tests unitaires du MODULE 14 — Workflow d'activation à double validation.
//
// Ces tests ne touchent ni au réseau ni à Supabase : ils vérifient les
// modèles (parsing du JSON des RPC), les règles d'affichage et l'isolation
// des responsabilités dans la matrice de permissions :
//
//   GESTIONNAIRE DES COMPTES → vérifie (verification_comptes)
//   FINANCE                  → valide et active (activations_finance)
//
//     flutter test test/activation_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/activation.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/services/permission_service.dart';

void main() {
  final PermissionService service = PermissionService.instance;

  setUp(() {
    // Chaque test repart de la matrice par défaut, sans surcharge.
    service.reinitialiser();
  });

  // =========================================================================
  // 1. MODÈLE — ÉTAPES DU WORKFLOW
  // =========================================================================

  group('EtapeActivation', () {
    test('conversion des codes SQL', () {
      expect(EtapeActivation.fromCode('en_attente_verification'),
          EtapeActivation.enAttenteVerification);
      expect(EtapeActivation.fromCode('verifie'), EtapeActivation.verifie);
      expect(EtapeActivation.fromCode('actif'), EtapeActivation.actif);
      expect(EtapeActivation.fromCode('restreint'), EtapeActivation.restreint);
      expect(EtapeActivation.fromCode('rejete'), EtapeActivation.rejete);
      expect(EtapeActivation.fromCode('aucune'), EtapeActivation.aucune);
    });

    test('code inconnu ou absent → aucune (échec fermé)', () {
      expect(EtapeActivation.fromCode(null), EtapeActivation.aucune);
      expect(EtapeActivation.fromCode(''), EtapeActivation.aucune);
      expect(EtapeActivation.fromCode('PIRATE'), EtapeActivation.aucune);
    });

    test('séparation des responsabilités entre les étapes', () {
      // Seul « en attente de vérification » attend le gestionnaire.
      expect(EtapeActivation.enAttenteVerification.attendGestionnaire, isTrue);
      expect(EtapeActivation.verifie.attendGestionnaire, isFalse);

      // « vérifié » et « restreint » (régularisation) attendent la finance.
      expect(EtapeActivation.verifie.attendFinance, isTrue);
      expect(EtapeActivation.restreint.attendFinance, isTrue);
      expect(EtapeActivation.enAttenteVerification.attendFinance, isFalse);
      expect(EtapeActivation.actif.attendFinance, isFalse);
    });
  });

  // =========================================================================
  // 2. MODÈLE — TABLEAU DE BORD CLIENT (rpc_activation_etat)
  // =========================================================================

  group('EtatActivation — tableau de bord client', () {
    test('réponse « aucune » : pas de dossier', () {
      final EtatActivation etat =
          EtatActivation.fromMap(<String, dynamic>{'etape': 'aucune'});

      expect(etat.aUnDossier, isFalse);
      expect(etat.etape, EtapeActivation.aucune);
      expect(etat.historique, isEmpty);
    });

    test('dossier complet avec historique (paiement partiel)', () {
      final EtatActivation etat = EtatActivation.fromMap(<String, dynamic>{
        'entreprise_id': 'ent-1',
        'nom': 'Boutique Étoile',
        'etape': 'actif',
        'statut': 'ESSAI_7J',
        'type_paiement': 'partiel',
        'montant_total_du': 20000,
        'montant_deja_paye': 5000,
        'solde_restant': 15000,
        'date_activation': '2026-09-16T08:00:00Z',
        'date_expiration': '2026-09-23T08:00:00Z',
        'jours_restants': 7,
        'verifie_le': '2026-09-16T09:00:00Z',
        'valide_le_finance': '2026-09-16T10:00:00Z',
        'historique': <Map<String, dynamic>>[
          <String, dynamic>{
            'etape': 'paiement_finance',
            'role': 'FINANCE_LAPERLE',
            'montant': 5000,
            'mode_paiement': 'Mobile Money',
            'reference': 'MOMO-001',
            'note': 'Première avance',
            'le': '2026-09-16T10:00:00Z',
          },
          <String, dynamic>{
            'etape': 'verification',
            'role': 'GESTIONNAIRE_COMPTES',
            'le': '2026-09-16T09:00:00Z',
          },
          <String, dynamic>{
            'etape': 'soumission',
            'le': '2026-09-16T08:00:00Z',
          },
        ],
      });

      expect(etat.aUnDossier, isTrue);
      expect(etat.nom, 'Boutique Étoile');
      expect(etat.etape, EtapeActivation.actif);
      expect(etat.statut, StatutAbonnement.essai7j);
      expect(etat.typePaiement, TypePaiementActivation.partiel);
      expect(etat.montantTotalDu, 20000);
      expect(etat.montantDejaPaye, 5000);
      expect(etat.soldeRestant, 15000);
      expect(etat.joursRestants, 7);
      expect(etat.verifieLe, isNotNull);
      expect(etat.valideLeFinance, isNotNull);

      // CAS 1 du cahier des charges : partiel → solde non réglé.
      expect(etat.estSolde, isFalse);
      expect(etat.tauxPaiement, closeTo(0.25, 0.0001));

      expect(etat.historique.length, 3);
      expect(etat.historique.first.estPaiement, isTrue);
      expect(etat.historique.first.montant, 5000);
      expect(etat.historique.first.modePaiement, 'Mobile Money');
      expect(etat.historique.first.reference, 'MOMO-001');
      expect(etat.historique.first.estRejet, isFalse);
    });

    test('dossier soldé (paiement total)', () {
      final EtatActivation etat = EtatActivation.fromMap(<String, dynamic>{
        'etape': 'actif',
        'statut': 'ACTIF',
        'type_paiement': 'total',
        'montant_total_du': 20000,
        'montant_deja_paye': 20000,
        'solde_restant': 0,
        'jours_restants': 30,
      });

      // CAS 2 : total → 30 jours immédiats, solde nul.
      expect(etat.estSolde, isTrue);
      expect(etat.tauxPaiement, 1);
      expect(etat.typePaiement, TypePaiementActivation.total);
      expect(etat.messageEtape, contains('actif'));
    });

    test('dossier restreint : les données restent consultables', () {
      final EtatActivation etat = EtatActivation.fromMap(<String, dynamic>{
        'etape': 'restreint',
        'statut': 'EN_ATTENTE_COMPLEMENT',
        'type_paiement': 'partiel',
        'montant_total_du': 20000,
        'montant_deja_paye': 5000,
        'solde_restant': 15000,
        'jours_restants': 0,
      });

      expect(etat.etape, EtapeActivation.restreint);
      expect(etat.estSolde, isFalse);
      expect(etat.messageEtape, contains('restreint'));
      expect(etat.messageEtape, contains('conservées'));
    });

    test('taux de paiement borné (jamais > 1)', () {
      final EtatActivation etat = EtatActivation.fromMap(<String, dynamic>{
        'etape': 'actif',
        'montant_total_du': 20000,
        'montant_deja_paye': 25000,
        'solde_restant': 0,
      });

      expect(etat.tauxPaiement, 1);
    });

    test('total dû nul → progression nulle (pas de division par zéro)', () {
      final EtatActivation etat = EtatActivation.fromMap(<String, dynamic>{
        'etape': 'en_attente_verification',
      });

      expect(etat.tauxPaiement, 0);
      expect(etat.messageEtape, contains('gestionnaire des comptes'));
    });
  });

  // =========================================================================
  // 3. MODÈLE — LISTE ADMIN (rpc_activation_lister)
  // =========================================================================

  group('DossierActivation — écrans admin', () {
    test('parsing complet', () {
      final DossierActivation dossier =
          DossierActivation.fromMap(<String, dynamic>{
        'id': 'ent-9',
        'nom': 'Pharmacie Centrale',
        'etape': 'en_attente_verification',
        'statut': 'EN_ATTENTE_COMPLEMENT',
        'ville': 'Kinshasa',
        'activite': 'Pharmacie',
        'montant_total_du': 35000,
        'montant_deja_paye': 0,
        'solde_restant': 35000,
        'created_at': '2026-09-16T08:00:00Z',
        'responsable': 'Mme Kanku',
        'contact': 'kanku@exemple.cd',
        'telephone': '+243810000000',
        'dernier_motif': 'Documents incomplets',
      });

      expect(dossier.id, 'ent-9');
      expect(dossier.nom, 'Pharmacie Centrale');
      expect(dossier.etape, EtapeActivation.enAttenteVerification);
      expect(dossier.statut, StatutAbonnement.enAttenteComplement);
      expect(dossier.ville, 'Kinshasa');
      expect(dossier.activite, 'Pharmacie');
      expect(dossier.soldeRestant, 35000);
      expect(dossier.estSolde, isFalse);
      expect(dossier.responsable, 'Mme Kanku');
      expect(dossier.contact, 'kanku@exemple.cd');
      expect(dossier.telephone, '+243810000000');
      expect(dossier.dernierMotif, 'Documents incomplets');
      expect(dossier.createdAt, isNotNull);
    });

    test('champs absents tolérés (jamais d\'exception de parsing)', () {
      final DossierActivation dossier =
          DossierActivation.fromMap(<String, dynamic>{
        'id': 'ent-10',
        'nom': 'Hôtel Royal',
      });

      expect(dossier.etape, EtapeActivation.aucune);
      expect(dossier.statut, isNull);
      expect(dossier.montantTotalDu, 0);
      expect(dossier.ville, isNull);
      expect(dossier.dernierMotif, isNull);
    });
  });

  // =========================================================================
  // 4. MODÈLE — HISTORIQUE
  // =========================================================================

  group('EntreeActivation', () {
    test('conversion des étapes d\'historique', () {
      expect(EtapeHistoriqueActivation.fromCode('soumission'),
          EtapeHistoriqueActivation.soumission);
      expect(EtapeHistoriqueActivation.fromCode('verification'),
          EtapeHistoriqueActivation.verification);
      expect(EtapeHistoriqueActivation.fromCode('rejet_verification'),
          EtapeHistoriqueActivation.rejetVerification);
      expect(EtapeHistoriqueActivation.fromCode('paiement_finance'),
          EtapeHistoriqueActivation.paiementFinance);
      expect(EtapeHistoriqueActivation.fromCode('rejet_finance'),
          EtapeHistoriqueActivation.rejetFinance);
      expect(EtapeHistoriqueActivation.fromCode('restriction'),
          EtapeHistoriqueActivation.restriction);
      expect(EtapeHistoriqueActivation.fromCode('inconnu'), isNull);
    });

    test('rejets identifiables (gestionnaire et finance)', () {
      final EntreeActivation rejetGestionnaire =
          EntreeActivation.fromMap(<String, dynamic>{
        'etape': 'rejet_verification',
        'role': 'GESTIONNAIRE_COMPTES',
        'note': 'Nom d\'entreprise manquant',
      });
      final EntreeActivation rejetFinance =
          EntreeActivation.fromMap(<String, dynamic>{
        'etape': 'rejet_finance',
        'role': 'FINANCE_LAPERLE',
        'note': 'Paiement introuvable',
      });

      expect(rejetGestionnaire.estRejet, isTrue);
      expect(rejetGestionnaire.estPaiement, isFalse);
      expect(rejetFinance.estRejet, isTrue);
    });
  });

  // =========================================================================
  // 5. PERMISSIONS — SÉPARATION DES RESPONSABILITÉS
  // =========================================================================

  group('Permissions — isolation gestionnaire / finance', () {
    test('GESTIONNAIRE_COMPTES : vérifie les comptes, jamais la finance', () {
      expect(
        service.aAcces(RoleUtilisateur.gestionnaireComptes,
            PageAccess.verificationComptes, ActionAccess.voir),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.gestionnaireComptes,
            PageAccess.verificationComptes, ActionAccess.valider),
        isTrue,
      );

      // 🔒 Il ne peut ni valider les paiements ni activer un compte :
      // l'écran Finance lui est interdit (double revérification serveur).
      expect(
        service.aAcces(RoleUtilisateur.gestionnaireComptes,
            PageAccess.activationsFinance, ActionAccess.voir),
        isFalse,
      );
      expect(
        service.aAcces(RoleUtilisateur.gestionnaireComptes,
            PageAccess.activationsFinance, ActionAccess.valider),
        isFalse,
      );
    });

    test('FINANCE_LAPERLE : valide le paiement et active, mais ne vérifie pas',
        () {
      expect(
        service.aAcces(RoleUtilisateur.financeLaperle,
            PageAccess.activationsFinance, ActionAccess.voir),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.financeLaperle,
            PageAccess.activationsFinance, ActionAccess.valider),
        isTrue,
      );

      // 🔒 La finance ne fait pas la première vérification : la séparation
      // des responsabilités est stricte dans les deux sens.
      expect(
        service.aAcces(RoleUtilisateur.financeLaperle,
            PageAccess.verificationComptes, ActionAccess.voir),
        isFalse,
      );
    });

    test('SUPER_ADMIN voit les deux écrans (dépannage)', () {
      expect(
        service.aAcces(RoleUtilisateur.superAdmin,
            PageAccess.verificationComptes, ActionAccess.valider),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.superAdmin,
            PageAccess.activationsFinance, ActionAccess.valider),
        isTrue,
      );
    });

    test('SUPPORT : en lecture seule, sans droit d\'action', () {
      expect(
        service.aAcces(RoleUtilisateur.support, PageAccess.activationsFinance,
            ActionAccess.voir),
        isFalse,
      );
      expect(
        service.aAcces(RoleUtilisateur.support,
            PageAccess.verificationComptes, ActionAccess.valider),
        isFalse,
      );
    });

    test('les rôles d\'entreprise n\'accèdent pas aux écrans plateforme', () {
      for (final RoleUtilisateur role in <RoleUtilisateur>[
        RoleUtilisateur.proprietaire,
        RoleUtilisateur.vendeur,
        RoleUtilisateur.magasinier,
        RoleUtilisateur.comptableEntreprise,
      ]) {
        expect(
          service.aAcces(role, PageAccess.verificationComptes,
              ActionAccess.voir),
          isFalse,
          reason: role.code,
        );
        expect(
          service.aAcces(role, PageAccess.activationsFinance, ActionAccess.voir),
          isFalse,
          reason: role.code,
        );
      }
    });
  });

  // =========================================================================
  // 6. MIDDLEWARE DE NAVIGATION
  // =========================================================================

  group('Middleware de navigation — routes du Module 14', () {
    test('les écrans admin exigent leur page respective', () {
      expect(
        PermissionService.pageRequisePour('/admin/verification-comptes'),
        PageAccess.verificationComptes,
      );
      expect(
        PermissionService.pageRequisePour('/admin/activations-finance'),
        PageAccess.activationsFinance,
      );
    });

    test('le tableau de bord client est protégé par le dashboard', () {
      expect(
        PermissionService.pageRequisePour('/main/mon-activation'),
        PageAccess.dashboard,
      );
    });
  });
}
