// test/coherence_metiers_test.dart
//
// 🧭 CORRECTIF 180 — « UNE BOUTIQUE N'EST PAS UN PRESSING ».
//
// Scénario vécu : un compte possède une BOUTIQUE et un PRESSING. La boutique
// se comportait comme un pressing (interdiction de vendre, menus Dépôts /
// Atelier / Retraits, collaborateurs avec un métier pressing).
//
// Côté application, la règle est portée par le CONTEXTE PRESSING :
//   • il n'est actif que si l'ESPACE DE TRAVAIL est un pressing ;
//   • un métier pressing « hérité » (role_pressing périmé) ne suffit pas à
//     activer les écrans du pressing.
//
// Ces tests verrouillent ce comportement, sans réseau.
//
//     flutter test test/coherence_metiers_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/permission_service.dart';

void main() {
  final PermissionService permissions = PermissionService.instance;

  setUp(() {
    permissions.reinitialiser();
    permissions.definirRoleCourant(RoleUtilisateur.proprietaire);
  });

  group('Contexte pressing — l\'espace décide', () {
    test('espace boutique : aucun écran métier pressing', () {
      permissions.definirContextePressing(actif: false, roleCode: null);

      expect(permissions.estDansPressing, isFalse);
      expect(permissions.rolePressingCode, isNull);
      expect(permissions.routeAutorisee('/main/pressing/atelier'), isFalse);
      expect(permissions.routeAutorisee('/main/pressing/caisse'), isFalse);
    });

    test('métier pressing périmé sur une boutique : il ne s\'active pas', () {
      // Cas réel : `utilisateurs.role_pressing = 'caisse'` resté en base
      // alors que l'espace de travail est redevenu une boutique.
      permissions.definirContextePressing(actif: false, roleCode: 'caisse');

      expect(permissions.estDansPressing, isFalse,
          reason: 'Le drapeau actif est la seule porte d\'entrée');
      expect(permissions.routeAutorisee('/main/pressing/atelier'), isFalse);
      // La vente boutique redevient possible : nous ne sommes pas au pressing.
      expect(permissions.routeAutorisee('/main/ventes'), isTrue);
    });

    test('espace pressing : les écrans du métier sont ouverts', () {
      permissions.definirContextePressing(actif: true, roleCode: 'atelier');

      expect(permissions.estDansPressing, isTrue);
      expect(permissions.rolePressingCode, 'atelier');
      expect(permissions.routeAutorisee('/main/pressing/atelier'), isTrue);
      // L'atelier ne tient pas la caisse du pressing.
      expect(permissions.routeAutorisee('/main/pressing/caisse'), isFalse);
      // Un pressing ne vend pas d'articles boutique.
      expect(permissions.routeAutorisee('/main/ventes'), isFalse);
    });

    test('propriétaire d\'un pressing : tous les écrans du pressing', () {
      permissions.definirContextePressing(actif: true, roleCode: 'proprietaire');

      expect(permissions.estDansPressing, isTrue);
      expect(permissions.routeAutorisee('/main/pressing/depots'), isTrue);
      expect(permissions.routeAutorisee('/main/pressing/atelier'), isTrue);
      expect(permissions.routeAutorisee('/main/pressing/retraits'), isTrue);
      expect(permissions.routeAutorisee('/main/pressing/equipe'), isTrue);
    });

    test('caisse du pressing : retraits seulement', () {
      permissions.definirContextePressing(actif: true, roleCode: 'caisse');

      expect(permissions.routeAutorisee('/main/pressing/retraits'), isTrue);
      expect(permissions.routeAutorisee('/main/pressing/atelier'), isFalse);
      expect(permissions.routeAutorisee('/main/pressing/depots'), isFalse);
    });

    test('réinitialiser() efface le métier pressing (déconnexion)', () {
      permissions.definirContextePressing(actif: true, roleCode: 'caisse');
      expect(permissions.estDansPressing, isTrue);

      permissions.reinitialiser();

      expect(permissions.estDansPressing, isFalse);
      expect(permissions.rolePressingCode, isNull);
    });
  });

  group('Aucun espace ne déborde sur un autre', () {
    test('un compte plateforme n\'accède jamais à /main', () {
      permissions.definirRoleCourant(RoleUtilisateur.superAdmin);

      expect(PermissionService.espaceAutorise(
          RoleUtilisateur.superAdmin, '/main'), isFalse);
      expect(PermissionService.espaceAutorise(
          RoleUtilisateur.superAdmin, '/admin'), isTrue);
    });

    test('un compte d\'entreprise n\'accède jamais à /admin', () {
      expect(PermissionService.espaceAutorise(
          RoleUtilisateur.proprietaire, '/admin'), isFalse);
      expect(PermissionService.espaceAutorise(
          RoleUtilisateur.proprietaire, '/main'), isTrue);
    });
  });
}
