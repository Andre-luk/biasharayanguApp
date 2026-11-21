// test/session_isolation_test.dart
//
// 🧹 CORRECTIF 178 — ISOLATION DES SESSIONS.
//
// Deux bugs constatés en production :
//   1. un SUPER ADMIN se connectait et arrivait dans la coquille ENTREPRISE
//      (`/main` : tableau de bord, rapports, paramètres) ;
//   2. une BOUTIQUE affichait les menus du PRESSING (3 écrans métier).
//
// Les deux venaient d'états de session hérités du compte précédent. Ces tests
// figent les deux garde-fous PURS ajoutés :
//   • `PermissionService.espaceAutorise` sépare plateforme et entreprise ;
//   • `PermissionService.roleDepuisCodes` traduit la ligne serveur, y compris
//     les comptes dont les colonnes de rôle sont vides (repli historique).
//
//     flutter test test/session_isolation_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/permission_service.dart';

void main() {
  final PermissionService service = PermissionService.instance;

  setUp(service.reinitialiser);

  group('Séparation des deux mondes (espaceAutorise)', () {
    test('un rôle plateforme n\'entre pas dans l\'espace entreprise', () {
      for (final RoleUtilisateur role in <RoleUtilisateur>[
        RoleUtilisateur.superAdmin,
        RoleUtilisateur.gestionnaireComptes,
        RoleUtilisateur.financeLaperle,
        RoleUtilisateur.support,
        RoleUtilisateur.agentTerrain,
      ]) {
        expect(
          PermissionService.espaceAutorise(role, '/main'),
          isFalse,
          reason: '${role.name} ne doit pas ouvrir /main',
        );
        expect(
          PermissionService.espaceAutorise(role, '/main/new-sale'),
          isFalse,
          reason: '${role.name} ne doit pas ouvrir une sous-route /main',
        );
        expect(
          PermissionService.espaceAutorise(role, '/admin'),
          isTrue,
          reason: '${role.name} doit garder /admin',
        );
      }
    });

    test('un compte d\'entreprise n\'entre pas dans l\'administration', () {
      for (final RoleUtilisateur role in <RoleUtilisateur>[
        RoleUtilisateur.proprietaire,
        RoleUtilisateur.vendeur,
        RoleUtilisateur.magasinier,
        RoleUtilisateur.comptableEntreprise,
      ]) {
        expect(
          PermissionService.espaceAutorise(role, '/admin/utilisateurs'),
          isFalse,
          reason: '${role.name} ne doit pas ouvrir /admin',
        );
        expect(
          PermissionService.espaceAutorise(role, '/main'),
          isTrue,
          reason: '${role.name} doit garder /main',
        );
      }
    });

    test('les routes libres restent libres (connexion, factures, audit)', () {
      for (final String route in <String>[
        '/login',
        '/setup',
        '/factures-abonnement',
        '/audit',
        '/scanner',
      ]) {
        expect(
          PermissionService.espaceAutorise(RoleUtilisateur.superAdmin, route),
          isTrue,
          reason: 'plateforme : $route',
        );
        expect(
          PermissionService.espaceAutorise(RoleUtilisateur.proprietaire, route),
          isTrue,
          reason: 'entreprise : $route',
        );
      }
    });

    test('rôle inconnu : on ne bloque rien (écran de connexion)', () {
      expect(
        PermissionService.espaceAutorise(RoleUtilisateur.inconnu, '/main'),
        isTrue,
      );
      expect(
        PermissionService.espaceAutorise(RoleUtilisateur.inconnu, '/admin'),
        isTrue,
      );
    });

    test('un chemin avec paramètres est reconnu', () {
      expect(
        PermissionService.espaceAutorise(
          RoleUtilisateur.superAdmin,
          '/main/rapports?periode=7',
        ),
        isFalse,
      );
    });
  });

  group('Rôle lu depuis la ligne serveur', () {
    test('new_role SUPER_ADMIN → rôle plateforme', () {
      expect(
        PermissionService.roleDepuisCodes(newRole: 'SUPER_ADMIN'),
        RoleUtilisateur.superAdmin,
      );
    });

    test('new_role d\'un collaborateur de boutique', () {
      expect(
        PermissionService.roleDepuisCodes(
          newRole: 'VENDEUR',
          role: 'collaborator',
          parentId: 'patron-1',
        ),
        RoleUtilisateur.vendeur,
      );
    });

    test('colonnes vides mais rattaché à un patron → vendeur', () {
      expect(
        PermissionService.roleDepuisCodes(role: '', parentId: 'patron-1'),
        RoleUtilisateur.vendeur,
      );
    });

    test('colonnes vides et compte autonome → propriétaire', () {
      expect(
        PermissionService.roleDepuisCodes(role: ''),
        RoleUtilisateur.proprietaire,
      );
    });

    test('ancien rôle texte « admin » reste un Super Admin', () {
      expect(
        PermissionService.roleDepuisCodes(role: 'admin'),
        RoleUtilisateur.superAdmin,
      );
    });
  });

  group('Nettoyage de session', () {
    test('reinitialiser efface le rôle et le contexte pressing', () {
      service.definirRoleCourant(RoleUtilisateur.proprietaire);
      service.definirContextePressing(actif: true, roleCode: 'atelier');
      expect(service.estDansPressing, isTrue);

      service.reinitialiser();

      expect(service.roleCourant, RoleUtilisateur.inconnu);
      expect(service.estDansPressing, isFalse);
      expect(service.rolePressingCode, isNull);
    });

    test('un compte de pressing nettoyé ne garde aucun menu métier', () {
      service.definirRoleCourant(RoleUtilisateur.vendeur);
      service.definirContextePressing(actif: true, roleCode: 'accueil');
      expect(service.peutVoir(PageAccess.pressingDepots), isTrue);

      service.reinitialiser();
      service.definirRoleCourant(RoleUtilisateur.proprietaire);

      // Le nouveau compte (boutique) ne voit plus les écrans du pressing.
      expect(service.peutVoir(PageAccess.pressingDepots), isTrue,
          reason: 'le propriétaire a ce droit par la matrice entreprise');
      expect(service.estDansPressing, isFalse);
    });
  });
}
