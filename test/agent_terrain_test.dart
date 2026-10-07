// test/agent_terrain_test.dart
//
// 🧑‍🌾 MODULE 21 ter — tests purs de la fiche agent terrain.
//
// On teste le PARSING et les libellés (aucun accès réseau) : la sécurité
// réelle est côté serveur (migration 47), ces tests verrouillent le contrat
// des données renvoyées par `rpc_agent_fiche`.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/agent_terrain.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/agent_terrain_service.dart';

void main() {
  group('EntrepriseAgentTerrain', () {
    test('lit les compteurs et l\'étape', () {
      final EntrepriseAgentTerrain e = EntrepriseAgentTerrain.fromMap(
        <String, dynamic>{
          'entreprise_id': 'ent-1',
          'nom': 'Boutique Espoir',
          'statut': 'ESSAI_7J',
          'activation_etape': 'verifie',
          'solde_restant': 15000,
          'montant_total_du': 20000,
          'montant_deja_paye': 5000,
          'responsable': 'Ntumba',
          'nb_publies': 3,
        },
      );

      expect(e.id, 'ent-1');
      expect(e.nom, 'Boutique Espoir');
      expect(e.etape, 'verifie');
      expect(e.enAttente, isTrue);
      expect(e.actif, isFalse);
      expect(e.impaye, isTrue);
      expect(e.soldeRestant, 15000);
      expect(e.nbPublies, 3);
      expect(e.responsable, 'Ntumba');
      expect(e.libelleEtape, 'Vérifié — à activer');
    });

    test('un dossier actif et soldé n\'est ni en attente ni impayé', () {
      final EntrepriseAgentTerrain e = EntrepriseAgentTerrain.fromMap(
        <String, dynamic>{
          'id': 'ent-2',
          'nom': 'Hôtel KM',
          'activation_etape': 'actif',
          'solde_restant': 0,
        },
      );
      expect(e.actif, isTrue);
      expect(e.enAttente, isFalse);
      expect(e.impaye, isFalse);
      expect(e.libelleEtape, 'Actif');
    });

    test('tolère des valeurs absentes (jamais d\'exception)', () {
      final EntrepriseAgentTerrain e =
          EntrepriseAgentTerrain.fromMap(<String, dynamic>{});
      expect(e.id, '');
      expect(e.soldeRestant, 0);
      expect(e.etape, 'actif');
    });
  });

  group('UtilisateurAgentTerrain', () {
    test('parsing complet', () {
      final UtilisateurAgentTerrain u = UtilisateurAgentTerrain.fromMap(
        <String, dynamic>{
          'id': 'u-1',
          'nom': 'Espoir Ntumba',
          'email': 'agent@espoir.com',
          'telephone': '+243970000000',
          'role': 'PROPRIETAIRE',
          'entreprise_id': 'ent-1',
          'entreprise': 'Boutique Espoir',
          'activation_etape': 'actif',
        },
      );
      expect(u.nom, 'Espoir Ntumba');
      expect(u.entreprise, 'Boutique Espoir');
      expect(u.telephone, '+243970000000');
    });
  });

  group('ActionAgentTerrain', () {
    test('parsing du journal', () {
      final ActionAgentTerrain a = ActionAgentTerrain.fromMap(<String, dynamic>{
        'action': 'ACTIVATION_FINANCE',
        'niveau': 'HAUT',
        'details': <String, dynamic>{'montant': 20000},
      });
      expect(a.action, 'ACTIVATION_FINANCE');
      expect(a.niveau, 'HAUT');
      expect(a.details?['montant'], 20000);
    });
  });

  group('FicheAgentTerrain', () {
    test('agrège compteurs, listes et revenus', () {
      final FicheAgentTerrain f = FicheAgentTerrain.fromMap(<String, dynamic>{
        'agent_id': 'agent-1',
        'nom': 'Ntumba',
        'email': 'agent@espoir.com',
        'role': 'AGENT_TERRAIN',
        'nb_utilisateurs': 4,
        'nb_entreprises': 3,
        'nb_boutiques': 3,
        'nb_abonnements_actifs': 2,
        'nb_en_attente': 1,
        'nb_produits': 10,
        'nb_conditionnements': 2,
        'nb_qr_codes': 12,
        'nb_produits_publies': 7,
        'montant_encaisse': 60000,
        'solde_du': 15000,
        'entreprises': <dynamic>[
          <String, dynamic>{'id': 'e1', 'nom': 'A', 'activation_etape': 'actif'},
        ],
        'utilisateurs': <dynamic>[
          <String, dynamic>{'id': 'u1', 'nom': 'Client A', 'email': 'a@x.cd'},
        ],
        'journal': <dynamic>[
          <String, dynamic>{'action': 'ACTIVATION_VERIFIEE'},
        ],
      });

      expect(f.agentId, 'agent-1');
      expect(f.nbUtilisateurs, 4);
      expect(f.nbBoutiques, 3);
      expect(f.nbQrCodes, 12);
      expect(f.nbProduitsPublies, 7);
      expect(f.montantEncaisse, 60000);
      expect(f.soldeDu, 15000);
      expect(f.entreprises.length, 1);
      expect(f.utilisateurs.length, 1);
      expect(f.journal.length, 1);
    });

    test('tolère une réponse vide', () {
      final FicheAgentTerrain f = FicheAgentTerrain.fromMap(<String, dynamic>{});
      expect(f.nbUtilisateurs, 0);
      expect(f.entreprises, isEmpty);
      expect(f.journal, isEmpty);
      expect(f.montantEncaisse, 0);
    });
  });

  group('Rôle AGENT_TERRAIN', () {
    test('le code est résolu par fromCode', () {
      expect(RoleUtilisateur.fromCode('AGENT_TERRAIN'),
          RoleUtilisateur.agentTerrain);
      expect(RoleUtilisateur.agentTerrain.estPlateforme, isTrue);
    });
  });

  group('AgentTerrainService.messageErreur', () {
    test('extrait le texte lisible après le code', () {
      expect(
        AgentTerrainService.messageErreur(
            'DROIT_REFUSE|Ce dossier est déjà suivi par un autre agent.'),
        'Ce dossier est déjà suivi par un autre agent.',
      );
      expect(AgentTerrainService.messageErreur('Sans séparateur'),
          'Sans séparateur');
      expect(AgentTerrainService.messageErreur('CODE|'), 'CODE|');
    });
  });
}
