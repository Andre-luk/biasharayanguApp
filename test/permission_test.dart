// test/permission_test.dart
//
// Tests unitaires du MODULE 4 — Système de permissions.
//
// Ces tests ne touchent ni au réseau ni à Supabase : ils vérifient la matrice
// des droits, la conversion des rôles hérités, la sérialisation des
// personnalisations et le middleware de navigation.
//
//     flutter test test/permission_test.dart
//
// Les résultats attendus reproduisent exactement ceux du script SQL
// `20260916000006_module4_permissions.sql` (section 11.4) : si un test casse
// ici, la matrice Dart et la matrice SQL ne sont plus alignées.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/services/permission_service.dart';

void main() {
  final PermissionService service = PermissionService.instance;

  setUp(() {
    // Chaque test repart de la matrice par défaut, sans surcharge.
    service.reinitialiser();
  });

  // =========================================================================
  // 1. LES HUIT RÔLES
  // =========================================================================

  group('Les huit rôles du cahier des charges', () {
    test('les huit codes sont déclarés et uniques', () {
      expect(RoleUtilisateur.values.length, 9); // 8 rôles + « inconnu »
      expect(RoleUtilisateur.rolesSelectionnables.length, 8);

      final Set<String> codes = RoleUtilisateur.rolesSelectionnables
          .map((RoleUtilisateur r) => r.code)
          .toSet();
      expect(codes.length, 8);
      expect(codes, contains('SUPER_ADMIN'));
      expect(codes, contains('GESTIONNAIRE_COMPTES'));
      expect(codes, contains('FINANCE_LAPERLE'));
      expect(codes, contains('SUPPORT'));
      expect(codes, contains('PROPRIETAIRE'));
      expect(codes, contains('VENDEUR'));
      expect(codes, contains('MAGASINIER'));
      expect(codes, contains('COMPTABLE_ENTREPRISE'));
    });

    test('un utilisateur ne peut avoir qu\'un rôle : la colonne new_role', () {
      final Utilisateur u = Utilisateur(
        id: 'u1',
        nom: 'Test',
        email: 'test@x.cd',
        role: 'vendor',
        newRole: 'MAGASINIER',
      );

      // new_role prime sur l'ancien rôle.
      expect(
        PermissionService.roleDepuisUtilisateur(u),
        RoleUtilisateur.magasinier,
      );
    });

    test('rôle inconnu = aucune permission (échec fermé)', () {
      expect(RoleUtilisateur.fromCode('PIRATE'), RoleUtilisateur.inconnu);
      expect(service.getPagesAccessibles(RoleUtilisateur.inconnu), isEmpty);
      expect(
        service.aAcces(RoleUtilisateur.inconnu, PageAccess.dashboard,
            ActionAccess.voir),
        isFalse,
      );
    });

    test('conversion des rôles hérités de l\'application', () {
      expect(RoleUtilisateur.fromCode('admin'), RoleUtilisateur.superAdmin);
      expect(RoleUtilisateur.fromCode('vendor'), RoleUtilisateur.proprietaire);
      expect(
        RoleUtilisateur.fromCode('collaborator'),
        RoleUtilisateur.vendeur,
      );
      expect(RoleUtilisateur.fromCode(null), RoleUtilisateur.inconnu);
      expect(RoleUtilisateur.fromCode(''), RoleUtilisateur.inconnu);
    });

    test('colonne vide : le comportement historique est conservé', () {
      // Compte autonome (aucun parent) → propriétaire, comme l'ancien défaut
      // `vendor` de l'application.
      expect(
        PermissionService.roleDepuisCodes(role: null),
        RoleUtilisateur.proprietaire,
      );
      // Compte rattaché à un patron → vendeur.
      expect(
        PermissionService.roleDepuisCodes(role: '', parentId: 'patron-1'),
        RoleUtilisateur.vendeur,
      );
    });
  });

  // =========================================================================
  // 2. MATRICE DES PERMISSIONS
  // =========================================================================

  group('SUPER_ADMIN — toutes les pages, toutes les actions', () {
    test('accès total', () {
      for (final PageAccess page in PageAccess.values) {
        for (final ActionAccess action in ActionAccess.values) {
          expect(service.aAcces(RoleUtilisateur.superAdmin, page, action),
              isTrue,
              reason: '${page.code}/${action.code}');
        }
      }
    });
  });

  group('GESTIONNAIRE_COMPTES — comptes et référentiels, jamais la finance', () {
    test('pages autorisées', () {
      final List<PageAccess> pages =
          service.getPagesAccessibles(RoleUtilisateur.gestionnaireComptes);

      for (final PageAccess attendue in <PageAccess>[
        PageAccess.entreprises,
        PageAccess.utilisateurs,
        PageAccess.villes,
        PageAccess.activites,
        PageAccess.groupesTarifaires,
        // 🏢 production des étiquettes QR des boutiques (service plateforme).
        PageAccess.qrCodes,
        PageAccess.abonnements,
        PageAccess.assistance,
        PageAccess.notifications,
      ]) {
        expect(pages, contains(attendue));
      }
    });

    test('actions : voir, créer, modifier — ni supprimer ni valider', () {
      expect(
        service.aAcces(RoleUtilisateur.gestionnaireComptes,
            PageAccess.entreprises, ActionAccess.creer),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.gestionnaireComptes,
            PageAccess.entreprises, ActionAccess.supprimer),
        isFalse,
      );
      expect(
        service.aAcces(RoleUtilisateur.gestionnaireComptes,
            PageAccess.abonnements, ActionAccess.valider),
        isFalse,
      );
    });

    test('INTERDIT : finance et paiements', () {
      expect(
        service.aAcces(RoleUtilisateur.gestionnaireComptes, PageAccess.finance,
            ActionAccess.voir),
        isFalse,
      );
      expect(
        service.aAcces(RoleUtilisateur.gestionnaireComptes,
            PageAccess.paiements, ActionAccess.creer),
        isFalse,
      );
    });
  });

  group('FINANCE_LAPERLE — abonnements, paiements, validation', () {
    test('peut encaisser et valider, mais pas créer d\'entreprise', () {
      expect(
        service.aAcces(RoleUtilisateur.financeLaperle, PageAccess.paiements,
            ActionAccess.creer),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.financeLaperle, PageAccess.paiements,
            ActionAccess.valider),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.financeLaperle, PageAccess.abonnements,
            ActionAccess.voir),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.financeLaperle, PageAccess.entreprises,
            ActionAccess.creer),
        isFalse,
      );
      expect(
        service.aAcces(RoleUtilisateur.financeLaperle, PageAccess.parametres,
            ActionAccess.modifier),
        isFalse,
      );
    });
  });

  group('SUPPORT — lecture, assistance modifiable', () {
    test('modifier uniquement l\'assistance', () {
      expect(
        service.aAcces(RoleUtilisateur.support, PageAccess.assistance,
            ActionAccess.modifier),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.support, PageAccess.entreprises,
            ActionAccess.modifier),
        isFalse,
      );
      expect(
        service.aAcces(RoleUtilisateur.support, PageAccess.utilisateurs,
            ActionAccess.modifier),
        isFalse,
      );
      expect(
        service.aAcces(RoleUtilisateur.support, PageAccess.finance,
            ActionAccess.voir),
        isFalse,
      );
    });
  });

  group('PROPRIETAIRE — tout son espace', () {
    test('les pages de la boutique sont accessibles avec toutes les actions',
        () {
      for (final PageAccess page in <PageAccess>[
        PageAccess.dashboard,
        PageAccess.ventes,
        PageAccess.caisse,
        PageAccess.scanner,
        PageAccess.panier,
        PageAccess.articles,
        PageAccess.stock,
        PageAccess.clients,
        PageAccess.fournisseurs,
        PageAccess.finance,
        PageAccess.depenses,
        PageAccess.collaborateurs,
        PageAccess.rapports,
        PageAccess.abonnements,
        // 🔐 MODULE 12 — le propriétaire consulte le journal de SA boutique
        // (RLS serveur : cloisonné à son entreprise).
        PageAccess.audit,
        // 🤖 MODULE 13 — assistant IA (le patron règle les quotas, attribue
        // des quotas à son équipe et achète des packs).
        PageAccess.assistantIa,
        PageAccess.parametres,
      ]) {
        expect(
          service.aAcces(RoleUtilisateur.proprietaire, page, ActionAccess.voir),
          isTrue,
          reason: page.code,
        );
        expect(
          service.aAcces(
              RoleUtilisateur.proprietaire, page, ActionAccess.modifier),
          isTrue,
          reason: page.code,
        );
      }
    });

    test('aucun accès aux pages réservées à la plateforme', () {
      for (final PageAccess page in <PageAccess>[
        PageAccess.entreprises,
        PageAccess.utilisateurs,
        PageAccess.villes,
        PageAccess.activites,
        PageAccess.groupesTarifaires,
        // 🔐 MODULE 12 — `audit` n'est plus dans cette liste : la page existe
        // aussi côté entreprise, cloisonnée par la RLS. `securite` la
        // remplace comme écran strictement plateforme.
        PageAccess.securite,
        // 🏢 la production des étiquettes QR est réservée à la plateforme.
        PageAccess.qrCodes,
        PageAccess.assistance,
        PageAccess.notifications,
      ]) {
        expect(
          service.aAcces(RoleUtilisateur.proprietaire, page, ActionAccess.voir),
          isFalse,
          reason: page.code,
        );
      }
    });
  });

  group('VENDEUR — vendre, jamais modifier un prix', () {
    test('pages : ventes, caisse, scanner, panier, assistant IA, hôtel, resto',
        () {
      expect(
        service.getPagesAccessibles(RoleUtilisateur.vendeur),
        <PageAccess>[
          PageAccess.ventes,
          PageAccess.caisse,
          PageAccess.scanner,
          PageAccess.panier,
          // 🤖 MODULE 13 — il peut interroger l'assistant, mais les outils
          // sensibles (prix, suppression…) restent refusés CÔTÉ SERVEUR.
          PageAccess.assistantIa,
          // 🏨 MODULE 16 C2 — réceptionniste d'hôtel : chambres en lecture,
          // planning et arrivées/départs (jamais la configuration).
          PageAccess.chambres,
          PageAccess.reservations,
          PageAccess.reception,
          // 🍽️ MODULE 16 C3 — serveur / cuisine : tables en lecture,
          // commandes et écran cuisine (jamais la configuration).
          PageAccess.tables,
          PageAccess.commandes,
          PageAccess.cuisine,
          // 🎉 MODULE 16 C4 — agent d'accueil événementiel : salles en
          // lecture, événements voir + créer.
          PageAccess.salles,
          PageAccess.evenements,
        ],
      );
    });

    test('réceptionniste : planning & séjours, jamais la configuration hôtel',
        () {
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.reservations,
            ActionAccess.creer),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.reception,
            ActionAccess.creer),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.chambres,
            ActionAccess.voir),
        isTrue,
      );
      // ❌ Aucune écriture sur les chambres (création, prix, suppression).
      for (final ActionAccess action in <ActionAccess>[
        ActionAccess.creer,
        ActionAccess.modifier,
        ActionAccess.supprimer,
      ]) {
        expect(
          service.aAcces(RoleUtilisateur.vendeur, PageAccess.chambres, action),
          isFalse,
          reason: 'chambres/${action.code}',
        );
      }

      // 🍽️ MODULE 16 C3 — serveur : commandes + cuisine, sans configurer.
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.commandes,
            ActionAccess.creer),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.cuisine,
            ActionAccess.creer),
        isTrue,
      );
      for (final ActionAccess action in <ActionAccess>[
        ActionAccess.creer,
        ActionAccess.modifier,
        ActionAccess.supprimer,
      ]) {
        expect(
          service.aAcces(RoleUtilisateur.vendeur, PageAccess.tables, action),
          isFalse,
          reason: 'tables/${action.code}',
        );
      }

      // 🎉 MODULE 16 C4 — agent d'accueil événementiel : il prépare les
      // événements mais ne configure ni les salles ni leurs prix.
      expect(
        service.aAcces(
            RoleUtilisateur.vendeur, PageAccess.evenements, ActionAccess.creer),
        isTrue,
      );
      for (final ActionAccess action in <ActionAccess>[
        ActionAccess.creer,
        ActionAccess.modifier,
        ActionAccess.supprimer,
      ]) {
        expect(
          service.aAcces(RoleUtilisateur.vendeur, PageAccess.salles, action),
          isFalse,
          reason: 'salles/${action.code}',
        );
      }
    });

    test('peut vendre', () {
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.caisse,
            ActionAccess.creer),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.ventes,
            ActionAccess.voir),
        isTrue,
      );
    });

    test('NE PEUT JAMAIS modifier un article (donc un prix)', () {
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.articles,
            ActionAccess.modifier),
        isFalse,
      );
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.articles,
            ActionAccess.voir),
        isFalse,
      );
    });

    test('aucune action modifier / supprimer / valider, nulle part', () {
      for (final PageAccess page in PageAccess.values) {
        expect(
          service.aAcces(RoleUtilisateur.vendeur, page, ActionAccess.modifier),
          isFalse,
          reason: page.code,
        );
        expect(
          service.aAcces(RoleUtilisateur.vendeur, page, ActionAccess.supprimer),
          isFalse,
          reason: page.code,
        );
        expect(
          service.aAcces(RoleUtilisateur.vendeur, page, ActionAccess.valider),
          isFalse,
          reason: page.code,
        );
      }
    });

    test('INTERDIT : abonnements et finances globales', () {
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.abonnements,
            ActionAccess.voir),
        isFalse,
      );
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.finance,
            ActionAccess.voir),
        isFalse,
      );
    });
  });

  group('MAGASINIER — mouvements de stock', () {
    test('pages : stock, articles (lecture), rapports, assistant IA', () {
      final List<PageAccess> pages =
          service.getPagesAccessibles(RoleUtilisateur.magasinier);
      expect(pages, contains(PageAccess.stock));
      expect(pages, contains(PageAccess.articles));
      // 🤖 MODULE 13 — l'assistant est utilisable, sans droit de modification.
      expect(pages, contains(PageAccess.assistantIa));
      expect(
        service.aAcces(RoleUtilisateur.magasinier, PageAccess.assistantIa,
            ActionAccess.creer),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.magasinier, PageAccess.assistantIa,
            ActionAccess.modifier),
        isFalse,
      );
    });

    test('peut créer un mouvement mais pas modifier un article', () {
      expect(
        service.aAcces(RoleUtilisateur.magasinier, PageAccess.stock,
            ActionAccess.creer),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.magasinier, PageAccess.stock,
            ActionAccess.modifier),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.magasinier, PageAccess.articles,
            ActionAccess.voir),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.magasinier, PageAccess.articles,
            ActionAccess.modifier),
        isFalse,
      );
      expect(
        service.aAcces(RoleUtilisateur.magasinier, PageAccess.ventes,
            ActionAccess.creer),
        isFalse,
      );
    });
  });

  group('COMPTABLE_ENTREPRISE — dépenses et rapports', () {
    test('consulte les ventes, crée des dépenses, valide', () {
      expect(
        service.aAcces(RoleUtilisateur.comptableEntreprise, PageAccess.ventes,
            ActionAccess.voir),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.comptableEntreprise,
            PageAccess.depenses, ActionAccess.creer),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.comptableEntreprise,
            PageAccess.depenses, ActionAccess.valider),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.comptableEntreprise,
            PageAccess.rapports, ActionAccess.valider),
        isTrue,
      );
      // Il ne vend pas et ne modifie pas le catalogue.
      expect(
        service.aAcces(RoleUtilisateur.comptableEntreprise, PageAccess.caisse,
            ActionAccess.creer),
        isFalse,
      );
      expect(
        service.aAcces(RoleUtilisateur.comptableEntreprise,
            PageAccess.articles, ActionAccess.modifier),
        isFalse,
      );
      // 🤖 MODULE 13 — assistant IA : consultation et questions, jamais de
      // modification.
      expect(
        service.aAcces(RoleUtilisateur.comptableEntreprise,
            PageAccess.assistantIa, ActionAccess.voir),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.comptableEntreprise,
            PageAccess.assistantIa, ActionAccess.creer),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.comptableEntreprise,
            PageAccess.assistantIa, ActionAccess.modifier),
        isFalse,
      );
    });
  });

  // =========================================================================
  // 3. PERSONNALISATION PAR LE SUPER ADMIN (app_settings)
  // =========================================================================

  group('Personnalisation des permissions', () {
    test('une surcharge REMPLACE la matrice par défaut (retrait possible)', () {
      service.appliquerSurcharges(<RoleUtilisateur, RolePermission>{
        RoleUtilisateur.vendeur: RolePermission.uniforme(
          <PageAccess>[PageAccess.ventes],
          <ActionAccess>[ActionAccess.voir],
        ),
      });

      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.ventes,
            ActionAccess.creer),
        isFalse, // retiré par la personnalisation
      );
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.caisse,
            ActionAccess.voir),
        isFalse, // page non listée = page interdite
      );
      expect(service.estPersonnalise(RoleUtilisateur.vendeur), isTrue);
      // Les autres rôles gardent leurs droits par défaut.
      expect(
        service.aAcces(RoleUtilisateur.magasinier, PageAccess.stock,
            ActionAccess.creer),
        isTrue,
      );
    });

    test('lecture du document app_settings (les codes inconnus sont ignorés)',
        () {
      final Map<RoleUtilisateur, RolePermission> surcharges =
          PermissionService.lireSurcharges(<String, dynamic>{
        'roles': <String, dynamic>{
          'VENDEUR': <String, dynamic>{
            'ventes': <String>['voir', 'CREER'],
            'page_qui_n_existe_pas': <String>['voir'],
          },
          'ROLE_FANTOME': <String, dynamic>{
            'ventes': <String>['voir'],
          },
        },
      });

      expect(surcharges.keys, <RoleUtilisateur>[RoleUtilisateur.vendeur]);
      final RolePermission vendeur = surcharges[RoleUtilisateur.vendeur]!;
      expect(vendeur.actionsPour(PageAccess.ventes),
          <ActionAccess>{ActionAccess.voir, ActionAccess.creer});
      expect(vendeur.pages, <PageAccess>[PageAccess.ventes]);
    });

    test('un document illisible ne modifie rien', () {
      expect(PermissionService.lireSurcharges(null), isEmpty);
      expect(PermissionService.lireSurcharges('pas du json'), isEmpty);
      expect(PermissionService.lireSurcharges(<String>['a']), isEmpty);
    });

    test('sérialisation JSON aller-retour', () {
      final RolePermission original = RolePermission.personnalise(
        <PageAccess, Set<ActionAccess>>{
          PageAccess.stock: <ActionAccess>{
            ActionAccess.voir,
            ActionAccess.creer,
            ActionAccess.modifier,
          },
          PageAccess.articles: <ActionAccess>{ActionAccess.voir},
        },
      );

      final RolePermission relu = RolePermission.fromJson(original.toJson());

      expect(relu.pages, original.pages);
      for (final PageAccess page in original.pages) {
        expect(relu.actionsPour(page), original.actionsPour(page));
      }
    });

    test('retirer la dernière action d\'une page rend la page interdite', () {
      RolePermission permissions = RolePermission.uniforme(
        <PageAccess>[PageAccess.ventes],
        <ActionAccess>[ActionAccess.voir],
      );

      permissions = permissions.avec(PageAccess.ventes, ActionAccess.voir, false);

      expect(permissions.pages, isEmpty);
      expect(permissions.estVide, isTrue);
    });

    test('avecPage réactive une page avec « voir »', () {
      RolePermission permissions = RolePermission.uniforme(
        <PageAccess>[PageAccess.ventes],
        <ActionAccess>[ActionAccess.voir],
      );

      permissions = permissions.avecPage(PageAccess.stock, true);
      expect(permissions.actionsPour(PageAccess.stock),
          <ActionAccess>{ActionAccess.voir});

      permissions = permissions.avecPage(PageAccess.stock, false);
      expect(permissions.actionsPour(PageAccess.stock), isEmpty);
    });
  });

  // =========================================================================
  // 4. MENU DYNAMIQUE
  // =========================================================================

  group('Menu dynamique', () {
    test('le menu d\'un vendeur contient ses treize pages (hôtel, resto & fêtes)',
        () {
      final List<EntreeMenu> menu =
          service.menuPour(RoleUtilisateur.vendeur, EspaceApplication.entreprise);

      expect(
        menu.map((EntreeMenu e) => e.page).toList(),
        <PageAccess>[
          PageAccess.ventes,
          PageAccess.caisse,
          PageAccess.scanner,
          PageAccess.panier,
          PageAccess.assistantIa, // 🤖 MODULE 13
          // 🏨 MODULE 16 C2 — réception d'hôtel.
          PageAccess.chambres,
          PageAccess.reservations,
          PageAccess.reception,
          // 🍽️ MODULE 16 C3 — service restaurant.
          PageAccess.tables,
          PageAccess.commandes,
          PageAccess.cuisine,
          // 🎉 MODULE 16 C4 — salle des fêtes.
          PageAccess.salles,
          PageAccess.evenements,
        ],
      );
    });

    test('le menu d\'un gestionnaire de comptes est côté plateforme', () {
      final List<EntreeMenu> menu = service.menuPour(
          RoleUtilisateur.gestionnaireComptes, EspaceApplication.plateforme);

      expect(
        menu.map((EntreeMenu e) => e.page),
        containsAll(<PageAccess>[
          PageAccess.entreprises,
          PageAccess.utilisateurs,
          PageAccess.activites,
        ]),
      );
      expect(menu.map((EntreeMenu e) => e.page), isNot(contains(PageAccess.finance)));
    });

    test('chaque entrée de menu correspond à une page autorisée en lecture', () {
      for (final RoleUtilisateur role in RoleUtilisateur.rolesSelectionnables) {
        for (final EspaceApplication espace in EspaceApplication.values) {
          for (final EntreeMenu entree in service.menuPour(role, espace)) {
            expect(
              service.aAcces(role, entree.page, ActionAccess.voir),
              isTrue,
              reason: '${role.code} / ${entree.page.code}',
            );
          }
        }
      }
    });
  });

  // =========================================================================
  // 5. MIDDLEWARE DE NAVIGATION
  // =========================================================================

  group('Middleware de navigation', () {
    test('un vendeur ne peut pas ouvrir les rapports ni le stock', () {
      expect(service.aAcces(RoleUtilisateur.vendeur, PageAccess.rapports, ActionAccess.voir), isFalse);
      expect(service.aAcces(RoleUtilisateur.vendeur, PageAccess.stock, ActionAccess.voir), isFalse);
    });

    test('les routes sensibles sont associées à la bonne page', () {
      expect(PermissionService.pageRequisePour('/main/new-sale'), PageAccess.caisse);
      expect(PermissionService.pageRequisePour('/main/add-product'), PageAccess.articles);
      expect(PermissionService.pageRequisePour('/admin/entreprises/123'), PageAccess.entreprises);
      expect(PermissionService.pageRequisePour('/admin/abonnements/123'), PageAccess.abonnements);
      expect(PermissionService.pageRequisePour('/admin/abonnements/123/paiement'), PageAccess.paiements);
      expect(PermissionService.pageRequisePour('/settings/manage-users'), PageAccess.collaborateurs);
      expect(PermissionService.pageRequisePour('/login'), isNull);
      // 🤖 MODULE 13 — chat, quotas et configuration IA.
      expect(PermissionService.pageRequisePour('/assistant-ia'), PageAccess.assistantIa);
      expect(PermissionService.pageRequisePour('/achat-quotas'), PageAccess.assistantIa);
      expect(PermissionService.pageRequisePour('/agent-ia-config'), PageAccess.parametres);
    });

    test('routeAutorisee respecte le rôle connecté', () {
      service.definirRoleCourant(RoleUtilisateur.vendeur);
      expect(service.routeAutorisee('/main/new-sale'), isTrue);
      expect(service.routeAutorisee('/admin/entreprises'), isFalse);
      expect(service.routeAutorisee('/settings'), isFalse);
      // 🤖 MODULE 13 — le vendeur a le droit de dialoguer avec l'assistant,
      // mais jamais d'ouvrir la configuration IA (Super Admin).
      expect(service.routeAutorisee('/assistant-ia'), isTrue);
      expect(service.routeAutorisee('/agent-ia-config'), isFalse);

      service.definirRoleCourant(RoleUtilisateur.financeLaperle);
      expect(service.routeAutorisee('/admin/abonnements/42'), isTrue);
      expect(service.routeAutorisee('/admin/abonnements/42/paiement'), isTrue);
      expect(service.routeAutorisee('/admin/permissions'), isFalse); // Super Admin seulement
      expect(service.routeAutorisee('/main/new-sale'), isFalse);

      service.definirRoleCourant(RoleUtilisateur.superAdmin);
      expect(service.routeAutorisee('/admin/permissions'), isTrue);
      expect(service.routeAutorisee('/main/stock'), isTrue);
      // 🤖 MODULE 13 — le Super Admin règle la configuration et valide les
      // demandes de packs (y compris depuis l'espace plateforme).
      expect(service.routeAutorisee('/agent-ia-config'), isTrue);
      expect(service.routeAutorisee('/achat-quotas'), isTrue);
    });

    test('page d\'accueil de repli cohérente pour chaque rôle', () {
      expect(service.accueilPour(RoleUtilisateur.superAdmin), '/admin');
      expect(service.accueilPour(RoleUtilisateur.financeLaperle), '/admin');
      expect(service.accueilPour(RoleUtilisateur.proprietaire), '/main');
      expect(service.accueilPour(RoleUtilisateur.vendeur), '/main/new-sale');
      expect(service.accueilPour(RoleUtilisateur.magasinier), '/main/stock');
      expect(service.accueilPour(RoleUtilisateur.comptableEntreprise), '/main');
      expect(service.accueilPour(RoleUtilisateur.inconnu), isNull);
    });
  });

  // =========================================================================
  // 6. CRITÈRES D'ACCEPTATION DU MODULE 4
  // =========================================================================

  group('Critères d\'acceptation', () {
    test('les 8 rôles ont des droits différents (aucun doublon de matrice)', () {
      final Set<String> signatures = <String>{};
      for (final RoleUtilisateur role in RoleUtilisateur.rolesSelectionnables) {
        signatures.add(service.permissionsDe(role).toJson().toString());
      }
      expect(signatures.length, 8);
    });

    test('la lecture de `dashboard` distingue plateforme et entreprise', () {
      expect(
        service.aAcces(RoleUtilisateur.financeLaperle, PageAccess.dashboard,
            ActionAccess.voir),
        isTrue,
      );
      expect(
        service.aAcces(RoleUtilisateur.vendeur, PageAccess.dashboard,
            ActionAccess.voir),
        isFalse,
      );
    });

    test('seul le SUPER_ADMIN peut modifier les paramètres de la plateforme',
        () {
      final List<RoleUtilisateur> peuventModifierParametres = RoleUtilisateur
          .rolesSelectionnables
          .where((RoleUtilisateur r) =>
              service.aAcces(r, PageAccess.parametres, ActionAccess.modifier))
          .toList();

      expect(peuventModifierParametres, <RoleUtilisateur>[
        RoleUtilisateur.superAdmin,
        RoleUtilisateur.proprietaire,
      ]);
      // Le propriétaire modifie SES paramètres, pas ceux de la plateforme :
      // l'écran des permissions exige en plus le rôle SUPER_ADMIN.
      expect(service.aAcces(RoleUtilisateur.proprietaire, PageAccess.utilisateurs,
          ActionAccess.voir), isFalse);
    });
  });
}
