// test/fiche_entreprise_test.dart
//
// CORRECTIF 73 — tests de la FICHE UNIQUE d'une entreprise.
//
// Aucun réseau, aucune base : on vérifie uniquement la LECTURE de la réponse
// de `rpc_entreprise_fiche` et la robustesse du modèle (une réponse
// inattendue ne doit jamais faire planter un écran).
//
//     flutter test test/fiche_entreprise_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/fiche_entreprise.dart';

/// Réponse réaliste de `rpc_admin_entreprise_creer`.
Map<String, dynamic> _creation() => <String, dynamic>{
      'ok': true,
      'entreprise_id': 'e3da4d44-0000-0000-0000-000000000001',
      'nom': 'Boutique Jambo',
      'type': 'boutique',
      'proprietaire_id': '9d1c2b3a-0000-0000-0000-000000000002',
      'proprietaire_email': 'patron@example.cd',
      'prix_installation': 30000,
      'prix_abonnement_mensuel': 5000,
      'essai_jours': 7,
      'activation_etape': 'en_attente_verification',
      'compte_reutilise': false,
    };

/// Réponse réaliste de `rpc_entreprise_fiche`.
Map<String, dynamic> _fiche() => <String, dynamic>{
      'ok': true,
      'entreprise': <String, dynamic>{
        'id': 'e3da4d44-0000-0000-0000-000000000001',
        'nom': 'Boutique Jambo',
        'statut': 'ESSAI_7J',
        'montant_total_du': 30000,
        'montant_deja_paye': 10000,
        'solde_restant': 20000,
        'prix_installation': 30000,
        'prix_abonnement_mensuel': 5000,
        'activation_etape': 'verifie',
        'date_activation': null,
        'date_expiration': '2026-10-20T00:00:00Z',
        'proprietaire_id': '9d1c2b3a-0000-0000-0000-000000000002',
        'cree_par': '11111111-0000-0000-0000-000000000009',
      },
      'proprietaire': <String, dynamic>{
        'id': '9d1c2b3a-0000-0000-0000-000000000002',
        'nom': 'Kabila',
        'prenom': 'Jean',
        'email': 'patron@example.cd',
        'telephone': '+243974084668',
        'role': 'PROPRIETAIRE',
      },
      'cree_par': <String, dynamic>{
        'id': '11111111-0000-0000-0000-000000000009',
        'nom': 'Agent',
        'email': 'agent@biasharayangu.cd',
        'role': 'AGENT_TERRAIN',
      },
      'grille': <String, dynamic>{
        'id': '22222222-0000-0000-0000-000000000003',
        'nom': 'Standard',
        'frais_ouverture': 25000,
        'montant_abonnement': 5000,
        'duree_essai_jours': 7,
        'duree_abonnement_jours': 30,
        'prix_par_collaborateur': 0,
        'max_espaces': 1,
      },
      'prix': <String, dynamic>{
        'installation': 30000,
        'mensuel': 5000,
        'total_du': 30000,
        'deja_paye': 10000,
        'solde': 20000,
        'paiements_cumules': 10000,
        'prochain_montant': 30000,
      },
      'suivi': <String, dynamic>{
        'statut': 'ESSAI_7J',
        'activation_etape': 'verifie',
        'jours_restants': 7,
        'date_activation': null,
        'date_expiration': '2026-10-20T00:00:00Z',
        'verifie_par': '11111111-0000-0000-0000-000000000009',
        'verifie_le': '2026-10-13T08:00:00Z',
        'valide_par_finance': null,
        'valide_le_finance': null,
      },
      'droits': <String, dynamic>{
        'peut_gerer_prix': true,
        'peut_verifier': true,
        'peut_valider': false,
        'peut_creer': true,
      },
      'historique': <dynamic>[
        <String, dynamic>{
          'etape': 'soumission',
          'montant': null,
          'mode_paiement': null,
          'reference': null,
          'note': 'Création par la plateforme',
          'acteur_role': 'AGENT_TERRAIN',
          'created_at': '2026-10-13T07:00:00Z',
        },
        <String, dynamic>{
          'etape': 'paiment_finance_inconnu',
          'montant': 10000,
          'mode_paiement': 'Espèces',
          'reference': 'TRX-1',
          'note': null,
          'acteur_role': 'FINANCE_LAPERLE',
          'created_at': '2026-10-13T08:30:00Z',
        },
      ],
      'paiements': <dynamic>[
        <String, dynamic>{
          'id': '33333333-0000-0000-0000-000000000004',
          'montant': 10000,
          'type_paiement': 'AVANCE',
          'mode_paiement': 'Espèces',
          'note': 'Avance de lancement',
          'total_apres': 30000,
          'solde_apres': 20000,
          'prolongation_jours': 0,
          'created_at': '2026-10-13T08:30:00Z',
        },
      ],
    };

void main() {
  group('ResultatCreationEntreprise', () {
    test('lit la réponse complète du serveur', () {
      final ResultatCreationEntreprise r =
          ResultatCreationEntreprise.depuisJson(_creation());

      expect(r.entrepriseId, 'e3da4d44-0000-0000-0000-000000000001');
      expect(r.nom, 'Boutique Jambo');
      expect(r.type, 'boutique');
      expect(r.proprietaireId, '9d1c2b3a-0000-0000-0000-000000000002');
      expect(r.proprietaireEmail, 'patron@example.cd');
      expect(r.prixInstallation, 30000);
      expect(r.prixMensuel, 5000);
      expect(r.essaiJours, 7);
      expect(r.compteReutilise, isFalse);
    });

    test('signale un compte réutilisé et un essai absent (repli 7 jours)', () {
      final ResultatCreationEntreprise r = ResultatCreationEntreprise.depuisJson(
        <String, dynamic>{
          'entreprise_id': 'x',
          'proprietaire_id': 'y',
          'compte_reutilise': true,
        },
      );

      expect(r.compteReutilise, isTrue);
      expect(r.essaiJours, 7);
      expect(r.prixMensuel, isNull);
      expect(r.type, 'boutique');
    });
  });

  group('FicheEntreprise — lecture', () {
    test('construit toutes les sections', () {
      final FicheEntreprise? fiche = FicheEntreprise.depuisJson(_fiche());

      expect(fiche, isNotNull);
      expect(fiche!.entreprise.nom, 'Boutique Jambo');
      expect(fiche.proprietaire!.nomComplet, 'Jean Kabila');
      expect(fiche.proprietaire!.email, 'patron@example.cd');
      expect(fiche.createur!.nomComplet, 'Agent');
      expect(fiche.createur!.role, 'AGENT_TERRAIN');
      expect(fiche.grille!.nom, 'Standard');
      expect(fiche.grille!.dureeEssaiJours, 7);
      expect(fiche.prix.installation, 30000);
      expect(fiche.prix.mensuel, 5000);
      expect(fiche.prix.dejaPaye, 10000);
      expect(fiche.prix.solde, 20000);
      expect(fiche.suivi.activationEtape, 'verifie');
      expect(fiche.suivi.joursRestants, 7);
      expect(fiche.droits.peutGererPrix, isTrue);
      expect(fiche.droits.peutValider, isFalse);
      expect(fiche.historique, hasLength(2));
      expect(fiche.historique.first.libelle, 'Dossier soumis');
      expect(fiche.paiements, hasLength(1));
      expect(fiche.paiements.first.libelleType, 'Avance');
      expect(fiche.paiements.first.montant, 10000);
      expect(fiche.paiements.first.soldeApres, 20000);
    });

    test('accepte aussi une réponse sérialisée en chaîne JSON', () {
      final FicheEntreprise? fiche =
          FicheEntreprise.depuisJson(jsonEncode(_fiche()));

      expect(fiche, isNotNull);
      expect(fiche!.entreprise.nom, 'Boutique Jambo');
      expect(fiche.paiements, hasLength(1));
    });

    test('répond null (jamais d\'exception) sur une forme inattendue', () {
      expect(FicheEntreprise.depuisJson(null), isNull);
      expect(FicheEntreprise.depuisJson('pas du json'), isNull);
      expect(FicheEntreprise.depuisJson(<String, dynamic>{'ok': true}), isNull);
      expect(
        FicheEntreprise.depuisJson(<String, dynamic>{'entreprise': 'texte'}),
        isNull,
      );
    });

    test('tolère des sections absentes et un historique vide', () {
      final FicheEntreprise? fiche = FicheEntreprise.depuisJson(
        <String, dynamic>{
          'entreprise': <String, dynamic>{'id': 'e1', 'nom': 'Sans patron'},
        },
      );

      expect(fiche, isNotNull);
      expect(fiche!.proprietaire, isNull);
      expect(fiche.createur, isNull);
      expect(fiche.grille, isNull);
      expect(fiche.historique, isEmpty);
      expect(fiche.paiements, isEmpty);
      expect(fiche.prix.totalDu, 0);
      expect(fiche.droits.peutCreer, isFalse);
      expect(fiche.suivi.joursRestants, isNull);
    });

    test('ignore un propriétaire sans identifiant', () {
      final FicheEntreprise? fiche = FicheEntreprise.depuisJson(
        <String, dynamic>{
          'entreprise': <String, dynamic>{'id': 'e1', 'nom': 'X'},
          'proprietaire': <String, dynamic>{'nom': 'orphelin'},
        },
      );

      expect(fiche!.proprietaire, isNull);
    });
  });

  group('PrixFiche', () {
    test('progression bornée entre 0 et 1', () {
      const PrixFiche partiel =
          PrixFiche(totalDu: 30000, dejaPaye: 10000, solde: 20000);
      expect(partiel.progression, closeTo(0.3333, 0.001));
      expect(partiel.estSolde, isFalse);

      const PrixFiche solde = PrixFiche(totalDu: 30000, dejaPaye: 30000);
      expect(solde.progression, 1);
      expect(solde.estSolde, isTrue);

      const PrixFiche trop =
          PrixFiche(totalDu: 1000, dejaPaye: 5000, solde: 0);
      expect(trop.progression, 1);

      const PrixFiche vide = PrixFiche();
      expect(vide.progression, 0);
      expect(vide.estSolde, isFalse);
    });
  });

  group('SuiviFiche', () {
    test('libellés d\'étape', () {
      expect(
        const SuiviFiche(activationEtape: 'en_attente_verification').libelleEtape,
        'En attente de vérification',
      );
      expect(const SuiviFiche(activationEtape: 'verifie').libelleEtape,
          'Vérifié — en attente de la finance');
      expect(const SuiviFiche(activationEtape: 'actif').libelleEtape, 'Actif');
      expect(const SuiviFiche(activationEtape: 'restreint').libelleEtape,
          'Restreint (paiement incomplet)');
      expect(const SuiviFiche(activationEtape: 'rejete').libelleEtape, 'Rejeté');
      expect(const SuiviFiche().libelleEtape, '—');
    });

    test('libellés de statut d\'abonnement', () {
      expect(const SuiviFiche(statut: 'ESSAI_7J').libelleStatut, 'Essai');
      expect(const SuiviFiche(statut: 'ACTIF').libelleStatut, 'Actif');
      expect(const SuiviFiche(statut: 'EXPIRE').libelleStatut, 'Expiré');
      expect(const SuiviFiche(statut: 'SUSPENDU').libelleStatut, 'Suspendu');
      expect(const SuiviFiche(statut: 'EN_ATTENTE_COMPLEMENT').libelleStatut,
          'Attente de complément');
      expect(const SuiviFiche().libelleStatut, '—');
    });

    test('« en attente » couvre les trois étapes non opérationnelles', () {
      expect(const SuiviFiche(activationEtape: 'en_attente_verification').enAttente,
          isTrue);
      expect(const SuiviFiche(activationEtape: 'verifie').enAttente, isTrue);
      expect(const SuiviFiche(activationEtape: 'rejete').enAttente, isTrue);
      expect(const SuiviFiche(activationEtape: 'actif').enAttente, isFalse);
      expect(const SuiviFiche(activationEtape: 'restreint').enAttente, isFalse);
    });

    test('phrase d\'échéance', () {
      expect(const SuiviFiche(joursRestants: 7).libelleEcheance,
          '7 jour(s) restant(s)');
      expect(const SuiviFiche(joursRestants: 0).libelleEcheance,
          'Expire aujourd\'hui');
      expect(const SuiviFiche(joursRestants: -3).libelleEcheance,
          'Échu depuis 3 jour(s)');
      expect(const SuiviFiche().libelleEcheance,
          'Aucune échéance enregistrée');
    });
  });

  group('Étapes et paiements', () {
    test('libellés des étapes du dossier', () {
      expect(const EtapeFiche(etape: 'soumission').libelle, 'Dossier soumis');
      expect(const EtapeFiche(etape: 'verification').libelle, 'Vérifié');
      expect(const EtapeFiche(etape: 'rejet_verification').libelle,
          'Rejeté (vérification)');
      expect(const EtapeFiche(etape: 'paiement_finance').libelle,
          'Paiement validé (finance)');
      expect(const EtapeFiche(etape: 'rejet_finance').libelle,
          'Paiement rejeté (finance)');
      expect(const EtapeFiche(etape: 'restriction').libelle, 'Compte restreint');
      expect(const EtapeFiche(etape: 'inconnue').libelle, 'inconnue');
    });

    test('libellés des types de paiement', () {
      expect(const PaiementFiche(id: '1', typePaiement: 'AVANCE').libelleType,
          'Avance');
      expect(const PaiementFiche(id: '2', typePaiement: 'SOLDE').libelleType,
          'Solde');
      expect(
        const PaiementFiche(id: '3', typePaiement: 'RENOUVELLEMENT')
            .libelleType,
        'Renouvellement',
      );
      expect(const PaiementFiche(id: '4').libelleType, 'Paiement');
    });
  });
}
