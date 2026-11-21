// test/pressing_permissions_test.dart
//
// 🧺 MODULE 35 — PRESSING & BLANCHISSERIE : droits d'accès aux trois écrans.
//
// Ces tests figent le correctif « le pressing n'apparaît pas » : les pages
// `pressing_depots`, `pressing_atelier` et `pressing_retraits` étaient
// déclarées (enum, routes, cartes d'accueil) mais ABSENTES de la matrice des
// droits par défaut. Résultat : `CarteAccueil.visibles` les filtrait pour
// TOUS les rôles, y compris le propriétaire d'un pressing, et l'application
// rebondissait de `/main/pressing/depots` vers `/main`.
//
//     flutter test test/pressing_permissions_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/ui/accueil/cartes_accueil.dart';

void main() {
  final PermissionService service = PermissionService.instance;

  setUp(() {
    service.reinitialiser();
  });

  // Modules d'un compte pressing, tels que `rpc_mes_modules()` les renvoie.
  const Set<String> modulesPressing = <String>{
    'assistant_ia',
    'caisse',
    'clients',
    'employes',
    'finance',
    'press_atelier',
    'press_depots',
    'press_retraits',
    'produits',
    'qr',
    'rapports',
    'stock',
    'ventes',
  };

  // Modules d'une boutique de marchandises (aucun `press_*`).
  const Set<String> modulesBoutique = <String>{
    'articles',
    'caisse',
    'clients',
    'ventes',
  };

  Set<String> idsDe(List<CarteAccueil> cartes) =>
      cartes.map((CarteAccueil c) => c.id).toSet();

  group('Matrice par défaut — pages du pressing', () {
    test('le propriétaire (patron du pressing) a les trois pages, tout faire',
        () {
      service.definirRoleCourant(RoleUtilisateur.proprietaire);

      for (final PageAccess page in const <PageAccess>[
        PageAccess.pressingDepots,
        PageAccess.pressingAtelier,
        PageAccess.pressingRetraits,
      ]) {
        for (final ActionAccess action in ActionAccess.values) {
          expect(
            service.peut(page, action),
            isTrue,
            reason: 'PROPRIETAIRE devrait pouvoir ${action.name} ${page.name}',
          );
        }
      }
    });

    test('le vendeur (accueil / caisse) dépose, remet et encaisse', () {
      service.definirRoleCourant(RoleUtilisateur.vendeur);

      expect(service.peut(PageAccess.pressingDepots, ActionAccess.voir), isTrue);
      expect(
          service.peut(PageAccess.pressingDepots, ActionAccess.creer), isTrue);
      expect(
        service.peut(PageAccess.pressingDepots, ActionAccess.modifier),
        isTrue,
        reason: 'annuler une commande est un acte d\'accueil (matrice SQL)',
      );
      expect(
          service.peut(PageAccess.pressingRetraits, ActionAccess.creer), isTrue);
      expect(
          service.peut(PageAccess.pressingRetraits, ActionAccess.valider),
          isTrue);

      // L'atelier n'est pas son écran.
      expect(service.peut(PageAccess.pressingAtelier, ActionAccess.voir), isFalse);
      // Ni la suppression, ni la configuration des tarifs.
      expect(
        service.peut(PageAccess.pressingDepots, ActionAccess.supprimer),
        isFalse,
      );
    });

    test('le magasinier (atelier) fait avancer les vêtements, sans encaisser',
        () {
      service.definirRoleCourant(RoleUtilisateur.magasinier);

      expect(
        service.peut(PageAccess.pressingAtelier, ActionAccess.voir),
        isTrue,
      );
      expect(
        service.peut(PageAccess.pressingAtelier, ActionAccess.modifier),
        isTrue,
      );
      // Il n'a AUCUNE permission sur les dépôts et les retraits : la caisse et
      // la remise ne sont pas son travail (matrice serveur).
      expect(service.peut(PageAccess.pressingDepots, ActionAccess.voir), isFalse);
      expect(
          service.peut(PageAccess.pressingRetraits, ActionAccess.voir), isFalse);
    });

    test('le comptable lit les dépôts sans rien écrire', () {
      service.definirRoleCourant(RoleUtilisateur.comptableEntreprise);

      expect(service.peut(PageAccess.pressingDepots, ActionAccess.voir), isTrue);
      expect(
          service.peut(PageAccess.pressingDepots, ActionAccess.creer), isFalse);
      expect(
          service.peut(PageAccess.pressingDepots, ActionAccess.modifier),
          isFalse);
      // Ni l'atelier ni la remise : ce ne sont pas ses pages.
      expect(service.peut(PageAccess.pressingAtelier, ActionAccess.voir), isFalse);
      expect(
          service.peut(PageAccess.pressingRetraits, ActionAccess.voir), isFalse);
    });

    test('un rôle qui n\'a rien à faire dans un pressing n\'y entre pas', () {
      service.definirRoleCourant(RoleUtilisateur.support);

      expect(service.peut(PageAccess.pressingDepots, ActionAccess.voir), isFalse);
      expect(service.peut(PageAccess.pressingAtelier, ActionAccess.voir), isFalse);
      expect(
          service.peut(PageAccess.pressingRetraits, ActionAccess.voir), isFalse);
    });
  });

  group('Navigation — les routes du pressing sont ouvertes', () {
    test('le propriétaire atteint les cinq écrans', () {
      service.definirRoleCourant(RoleUtilisateur.proprietaire);

      for (final String route in const <String>[
        '/main/pressing/depots',
        '/main/pressing/atelier',
        '/main/pressing/retraits',
        '/main/pressing/equipe',
        '/main/pressing/reglages',
        '/main/pressing/caisse',
      ]) {
        expect(service.routeAutorisee(route), isTrue, reason: route);
      }
    });

    test('l\'agent d\'atelier ouvre l\'atelier mais ne remet pas un vêtement',
        () {
      service.definirRoleCourant(RoleUtilisateur.magasinier);

      expect(service.routeAutorisee('/main/pressing/atelier'), isTrue);
      // La route des retraits lui est fermée (page non accordée).
      expect(service.routeAutorisee('/main/pressing/retraits'), isFalse);
      expect(
        service.peut(PageAccess.pressingRetraits, ActionAccess.creer),
        isFalse,
      );
    });
  });

  group('Contexte métier pressing — aucun écran de vente boutique', () {
    test('aucun métier pressing n\'ouvre la vente, scanner, pesée ou caisse boutique', () {
      const List<String> metiers = <String>[
        'proprietaire',
        'responsable',
        'accueil',
        'atelier',
        'caisse',
      ];
      const List<PageAccess> pagesBoutique = <PageAccess>[
        PageAccess.ventes,
        PageAccess.scanner,
        PageAccess.panier,
        PageAccess.caisse,
        PageAccess.stock,
        PageAccess.articles,
      ];

      for (final String metier in metiers) {
        service.definirRoleCourant(
          metier == 'atelier'
              ? RoleUtilisateur.magasinier
              : metier == 'responsable' || metier == 'proprietaire'
                  ? RoleUtilisateur.proprietaire
                  : RoleUtilisateur.vendeur,
        );
        service.definirContextePressing(actif: true, roleCode: metier);

        for (final PageAccess page in pagesBoutique) {
          expect(
            service.peut(page, ActionAccess.voir),
            isFalse,
            reason: '$metier ne doit pas voir ${page.name}',
          );
        }
        expect(service.routeAutorisee('/main/new-sale'), isFalse);
        expect(service.routeAutorisee('/scanner'), isFalse);
        expect(service.routeAutorisee('/main/pesee'), isFalse);
        expect(service.routeAutorisee('/main/caisse'), isFalse);
      }
    });

    test('accueil peut déposer/retirer, jamais vente, scanner ou pesée', () {
      service.definirRoleCourant(RoleUtilisateur.vendeur);
      service.definirContextePressing(actif: true, roleCode: 'accueil');

      expect(service.peut(PageAccess.pressingDepots, ActionAccess.creer), isTrue);
      expect(service.peut(PageAccess.pressingRetraits, ActionAccess.creer), isTrue);
      expect(service.peut(PageAccess.ventes, ActionAccess.voir), isFalse);
      expect(service.peut(PageAccess.scanner, ActionAccess.voir), isFalse);
      expect(service.peut(PageAccess.panier, ActionAccess.voir), isFalse);
      expect(service.routeAutorisee('/main/new-sale'), isFalse);
      expect(service.routeAutorisee('/scanner'), isFalse);
      expect(service.routeAutorisee('/main/pesee'), isFalse);
      expect(service.routeAutorisee('/main/ventes'), isFalse);
      expect(service.routeAutorisee('/main/caisse'), isFalse);
    });

    test('atelier ne voit que son atelier, pas la caisse ni le stock boutique',
        () {
      service.definirRoleCourant(RoleUtilisateur.magasinier);
      service.definirContextePressing(actif: true, roleCode: 'atelier');

      expect(service.peut(PageAccess.pressingAtelier, ActionAccess.voir), isTrue);
      expect(service.peut(PageAccess.pressingDepots, ActionAccess.voir), isFalse);
      expect(service.peut(PageAccess.pressingRetraits, ActionAccess.voir), isFalse);
      expect(service.peut(PageAccess.stock, ActionAccess.voir), isFalse);
      expect(service.peut(PageAccess.articles, ActionAccess.voir), isFalse);
      expect(service.peut(PageAccess.scanner, ActionAccess.voir), isFalse);
    });

    test('caisse pressing accède à sa caisse et aux retraits seulement', () {
      service.definirRoleCourant(RoleUtilisateur.vendeur);
      service.definirContextePressing(actif: true, roleCode: 'caisse');

      expect(service.peut(PageAccess.caisse, ActionAccess.creer), isFalse);
      expect(service.routeAutorisee('/main/pressing/caisse'), isTrue);
      expect(service.peut(PageAccess.pressingRetraits, ActionAccess.creer), isTrue);
      expect(service.peut(PageAccess.pressingDepots, ActionAccess.voir), isFalse);
        expect(service.peut(PageAccess.caisse, ActionAccess.voir), isFalse,
          reason: 'la caisse boutique est masquée, seule la route pressing existe');
      expect(service.routeAutorisee('/main/caisse'), isFalse);
          expect(service.routeAutorisee('/main/pesee'), isFalse);
      expect(service.peut(PageAccess.ventes, ActionAccess.voir), isFalse);
    });

    test('responsable garde ses écrans pressing mais jamais les ventes boutique',
        () {
      service.definirRoleCourant(RoleUtilisateur.proprietaire);
      service.definirContextePressing(actif: true, roleCode: 'responsable');

      expect(service.peut(PageAccess.pressingDepots, ActionAccess.voir), isTrue);
      expect(service.peut(PageAccess.pressingAtelier, ActionAccess.voir), isTrue);
      expect(service.peut(PageAccess.pressingRetraits, ActionAccess.voir), isTrue);
      expect(service.peut(PageAccess.ventes, ActionAccess.voir), isFalse);
      expect(service.routeAutorisee('/scanner'), isFalse);
    });

    test('hors pressing, un vendeur garde les droits habituels', () {
      service.definirRoleCourant(RoleUtilisateur.vendeur);
      service.definirContextePressing(actif: false);

      expect(service.peut(PageAccess.ventes, ActionAccess.creer), isTrue);
      expect(service.peut(PageAccess.scanner, ActionAccess.voir), isTrue);
    });
  });

  test('un profil pressing obsolète ne réaffiche pas les cartes boutique', () {
    service.definirRoleCourant(RoleUtilisateur.vendeur);
    service.definirContextePressing(actif: true, roleCode: 'accueil');

    final Set<String> ids = idsDe(CarteAccueil.visibles(
      modules: modulesPressing,
      profilCharge: true,
      autorise: service.peut,
    ));

    expect(ids, contains('pressing'));
    expect(ids, isNot(contains('ventes')));
    expect(ids, isNot(contains('caisse')));
    expect(ids, isNot(contains('stock')));
  });

  group('Carte d\'accueil « Pressing »', () {
    test('elle s\'affiche pour un profil pressing et le rôle propriétaire', () {
      service.definirRoleCourant(RoleUtilisateur.proprietaire);

      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: modulesPressing,
        profilCharge: true,
        autorise: service.peut,
      );

      expect(idsDe(cartes), contains('pressing'));
      final CarteAccueil carte =
          cartes.firstWhere((CarteAccueil c) => c.id == 'pressing');
      expect(carte.route, '/main/pressing/depots');
    });

    test('elle reste absente d\'une boutique qui n\'a pas les modules', () {
      service.definirRoleCourant(RoleUtilisateur.proprietaire);

      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: modulesBoutique,
        profilCharge: true,
        autorise: service.peut,
      );

      expect(idsDe(cartes), isNot(contains('pressing')));
    });

    test('profil non chargé : aucune carte MÉTIER n\'est affichée', () {
      service.definirRoleCourant(RoleUtilisateur.proprietaire);

      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: const <String>{},
        profilCharge: false,
        autorise: service.peut,
      );

      // 🧹 CORRECTIF 178 — une carte spécialisée (pressing, hôtel…) attend la
      // réponse du serveur : sinon la boutique du compte précédent affichait
      // les trois menus du pressing.
      expect(idsDe(cartes), isNot(contains('pressing')));

      // Une fois le profil chargé, elle revient.
      expect(
        idsDe(CarteAccueil.visibles(
          modules: modulesPressing,
          profilCharge: true,
          autorise: service.peut,
        )),
        contains('pressing'),
      );
    });

    test('un agent d\'atelier voit la carte malgré l\'absence de « dépôts »',
        () {
      // Le magasinier n'a que `pressingAtelier` : c'est la règle « au moins
      // une page » de la carte qui lui garde son point d'entrée vers le hub.
      service.definirRoleCourant(RoleUtilisateur.magasinier);
      expect(
        service.peut(PageAccess.pressingDepots, ActionAccess.voir),
        isFalse,
      );
      expect(
        idsDe(CarteAccueil.visibles(
          modules: modulesPressing,
          profilCharge: true,
          autorise: service.peut,
        )),
        contains('pressing'),
      );

      // En revanche un rôle sans la moindre permission ne la voit pas.
      service.definirRoleCourant(RoleUtilisateur.inconnu);
      expect(
        idsDe(CarteAccueil.visibles(
          modules: modulesPressing,
          profilCharge: true,
          autorise: service.peut,
        )),
        isNot(contains('pressing')),
      );
    });
  });
}
