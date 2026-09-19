// test/accueil_modules_test.dart
//
// 🧩 MODULE 16 (phase B) — Tests PURS de la grille d'accueil pilotée par les
// modules : registre des cartes, filtrage (modules × permissions), fail-open,
// ordre d'affichage et valeurs dynamiques. Aucun réseau.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/ui/accueil/cartes_accueil.dart';

/// Matrice de permissions factice : le rôle peut « voir » les pages données.
bool Function(PageAccess, ActionAccess) autorisationPour(
    Set<PageAccess> pages) {
  return (PageAccess page, ActionAccess action) => pages.contains(page);
}

List<String> idsDe(List<CarteAccueil> cartes) =>
    cartes.map((CarteAccueil c) => c.id).toList(growable: false);

void main() {
  final Set<PageAccess> toutesPages = PageAccess.values.toSet();

  // Profil « Hôtel » affiné (phase B) : pas de ventes/produits/stock/qr.
  const Set<String> profilHotel = <String>{
    'caisse',
    'clients',
    'finance',
    'employes',
    'rapports',
    'assistant_ia',
    'chambres',
    'reservations',
    'checkin',
  };

  group('CarteAccueil — registre', () {
    test('identifiants uniques, modules connus, routes définies', () {
      final Set<String> ids = <String>{};

      for (final CarteAccueil carte in CarteAccueil.registre) {
        expect(
          ids.add(carte.id),
          isTrue,
          reason: 'Identifiant dupliqué : ${carte.id}',
        );
        expect(carte.route.startsWith('/'), isTrue,
            reason: 'Route invalide pour ${carte.id}');
        expect(carte.page, isNotNull,
            reason: 'Carte sans permission : ${carte.id}');

        final String? module = carte.module;
        if (module != null) {
          expect(
            ModuleActivite.codeConnu(module),
            isTrue,
            reason: 'Module hors catalogue pour ${carte.id} : $module',
          );
        }
      }
    });

    test('au moins une carte de base sans module (abonnement)', () {
      final Iterable<String> sansModule = CarteAccueil.registre
          .where((CarteAccueil c) => c.module == null)
          .map((CarteAccueil c) => c.id);

      expect(sansModule, contains('abonnement'));
    });
  });

  group('CarteAccueil.visibles — boutique (comportement historique)', () {
    test('propriétaire + profil complet => les 9 cartes, dans l\'ordre', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: ModulesService.modulesBase,
        profilCharge: true,
        autorise: autorisationPour(toutesPages),
      );

      expect(idsDe(cartes), <String>[
        'produits',
        'stock',
        'ventes',
        'clients',
        'caisse',
        'finance',
        'rapports',
        'assistant_ia',
        'abonnement',
      ]);
    });

    test('fail-open : profil NON chargé => toutes les cartes du registre', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: const <String>{},
        profilCharge: false,
        autorise: autorisationPour(toutesPages),
      );

      expect(cartes.length, 18);
      expect(idsDe(cartes).first, 'produits');
      expect(idsDe(cartes), contains('expirations'));
      // 🏨 MODULE 16 C2 — les cartes hôtel sont désormais codées.
      expect(idsDe(cartes), contains('chambres'));
      expect(idsDe(cartes), contains('reservations'));
      expect(idsDe(cartes), contains('checkin'));
      // 🍽️ MODULE 16 C3 — les cartes restaurant sont désormais codées.
      expect(idsDe(cartes), contains('tables'));
      expect(idsDe(cartes), contains('commandes'));
      expect(idsDe(cartes), contains('cuisine'));
      // 🎉 MODULE 16 C4 — les cartes salle des fêtes sont désormais codées.
      expect(idsDe(cartes), contains('salles'));
      expect(idsDe(cartes), contains('evenements'));
    });

    test('profil vide MAIS chargé => tout reste visible (fail-open)', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: const <String>{},
        profilCharge: true,
        autorise: autorisationPour(toutesPages),
      );

      expect(cartes.length, 18);
    });
  });

  group('CarteAccueil.visibles — hôtel (phases B & C2)', () {
    test('les cartes de commerce disparaissent, les cartes hôtel apparaissent',
        () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: profilHotel,
        profilCharge: true,
        autorise: autorisationPour(toutesPages),
      );

      // 🏨 MODULE 16 C2 — chambres, réservations et réception en tête
      // (priorités 12 / 14 / 16), puis les cartes partagées.
      expect(idsDe(cartes), <String>[
        'chambres',
        'reservations',
        'checkin',
        'clients',
        'caisse',
        'finance',
        'rapports',
        'assistant_ia',
        'abonnement',
      ]);
      expect(idsDe(cartes), isNot(contains('produits')));
      expect(idsDe(cartes), isNot(contains('stock')));
      expect(idsDe(cartes), isNot(contains('ventes')));
    });

    test('la grille hôtel est pilotée par les 3 modules métier', () {
      final List<CarteAccueil> sansModules = CarteAccueil.visibles(
        modules: const <String>{'caisse', 'clients'},
        profilCharge: true,
        autorise: autorisationPour(toutesPages),
      );

      for (final String code in <String>[
        'chambres',
        'reservations',
        'checkin',
      ]) {
        expect(
          sansModules.where((CarteAccueil c) => c.module == code),
          isEmpty,
          reason: 'Aucune carte sans le module $code',
        );
      }
    });
  });

  group('CarteAccueil.visibles — restaurant (phase C3)', () {
    const Set<String> profilRestaurant = <String>{
      'caisse',
      'clients',
      'finance',
      'employes',
      'rapports',
      'assistant_ia',
      'tables',
      'commandes',
      'cuisine',
    };

    test('tables, commandes et cuisine en tête de la grille', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: profilRestaurant,
        profilCharge: true,
        autorise: autorisationPour(toutesPages),
      );

      expect(idsDe(cartes), <String>[
        'tables',
        'commandes',
        'cuisine',
        'clients',
        'caisse',
        'finance',
        'rapports',
        'assistant_ia',
        'abonnement',
      ]);
    });

    test('les cartes restaurant disparaissent sans leur module', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: const <String>{'caisse', 'clients'},
        profilCharge: true,
        autorise: autorisationPour(toutesPages),
      );

      for (final String code in <String>['tables', 'commandes', 'cuisine']) {
        expect(
          cartes.where((CarteAccueil c) => c.module == code),
          isEmpty,
          reason: 'Aucune carte sans le module $code',
        );
      }
    });
  });

  group('CarteAccueil.visibles — salle des fêtes (phase C4)', () {
    const Set<String> profilSalleFetes = <String>{
      'caisse',
      'clients',
      'finance',
      'rapports',
      'assistant_ia',
      'salles',
      'evenements',
    };

    test('événements et salles en tête de la grille', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: profilSalleFetes,
        profilCharge: true,
        autorise: autorisationPour(toutesPages),
      );

      expect(idsDe(cartes), <String>[
        'evenements',
        'salles',
        'clients',
        'caisse',
        'finance',
        'rapports',
        'assistant_ia',
        'abonnement',
      ]);
    });

    test('les cartes salle des fêtes disparaissent sans leur module', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: const <String>{'caisse', 'clients'},
        profilCharge: true,
        autorise: autorisationPour(toutesPages),
      );

      for (final String code in <String>['salles', 'evenements']) {
        expect(
          cartes.where((CarteAccueil c) => c.module == code),
          isEmpty,
          reason: 'Aucune carte sans le module $code',
        );
      }
    });
  });

  group('CarteAccueil.visibles — permissions du rôle', () {
    test('vendeur (boutique) : Mes ventes + Solde & clôture + Assistant IA',
        () {
      const Set<PageAccess> pagesVendeur = <PageAccess>{
        PageAccess.ventes,
        PageAccess.caisse,
        PageAccess.scanner,
        PageAccess.panier,
        PageAccess.assistantIa,
        // 🏨 MODULE 16 C2 — réceptionniste d'hôtel.
        PageAccess.chambres,
        PageAccess.reservations,
        PageAccess.reception,
      };

      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: ModulesService.modulesBase,
        profilCharge: true,
        autorise: autorisationPour(pagesVendeur),
      );

      expect(idsDe(cartes), <String>['ventes', 'caisse', 'assistant_ia']);
    });

    test('vendeur + hôtel : cartes hôtel puis caisse et assistant', () {
      const Set<PageAccess> pagesVendeur = <PageAccess>{
        PageAccess.ventes,
        PageAccess.caisse,
        PageAccess.scanner,
        PageAccess.panier,
        PageAccess.assistantIa,
        PageAccess.chambres,
        PageAccess.reservations,
        PageAccess.reception,
      };

      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: profilHotel,
        profilCharge: true,
        autorise: autorisationPour(pagesVendeur),
      );

      expect(
        idsDe(cartes),
        <String>[
          'chambres',
          'reservations',
          'checkin',
          'caisse',
          'assistant_ia'
        ],
      );
    });

    test('vendeur + restaurant : tables, commandes et cuisine puis caisse', () {
      const Set<PageAccess> pagesVendeur = <PageAccess>{
        PageAccess.ventes,
        PageAccess.caisse,
        PageAccess.scanner,
        PageAccess.panier,
        PageAccess.assistantIa,
        PageAccess.chambres,
        PageAccess.reservations,
        PageAccess.reception,
        PageAccess.tables,
        PageAccess.commandes,
        PageAccess.cuisine,
      };

      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: const <String>{
          'caisse',
          'clients',
          'finance',
          'rapports',
          'assistant_ia',
          'tables',
          'commandes',
          'cuisine',
        },
        profilCharge: true,
        autorise: autorisationPour(pagesVendeur),
      );

      expect(
        idsDe(cartes),
        <String>['tables', 'commandes', 'cuisine', 'caisse', 'assistant_ia'],
      );
    });

    test('magasinier : Produits + Stock + Rapports + Assistant IA', () {
      const Set<PageAccess> pagesMagasinier = <PageAccess>{
        PageAccess.stock,
        PageAccess.articles,
        PageAccess.rapports,
        PageAccess.assistantIa,
      };

      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: ModulesService.modulesBase,
        profilCharge: true,
        autorise: autorisationPour(pagesMagasinier),
      );

      expect(idsDe(cartes),
          <String>['produits', 'stock', 'rapports', 'assistant_ia']);
    });

    test('aucune permission => aucune carte (la section disparaît)', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: ModulesService.modulesBase,
        profilCharge: true,
        autorise: autorisationPour(const <PageAccess>{}),
      );

      expect(cartes, isEmpty);
    });
  });

  group('CarteAccueil — valeurs dynamiques', () {
    late AppLocalizations fr;

    setUpAll(() async {
      fr = await AppLocalizations.delegate.load(const Locale('fr'));
    });

    test('les valeurs reflètent les données de l\'accueil', () {
      const DonneesAccueil donnees = DonneesAccueil(
        produitsCount: 12,
        stockAlertes: 3,
        ventesJour: 5,
      );

      CarteAccueil carte(String id) =>
          CarteAccueil.registre.firstWhere((CarteAccueil c) => c.id == id);

      expect(carte('produits').valeur(donnees, fr), '12');
      expect(carte('stock').valeur(donnees, fr), '3');
      expect(carte('ventes').valeur(donnees, fr), '5');
    });

    test('les valeurs hôtel reflètent l\'occupation et la réception du jour',
        () {
      const DonneesAccueil donnees = DonneesAccueil(
        chambresTotal: 12,
        chambresOccupees: 5,
        reservationsActives: 3,
        arriveesJour: 2,
        departsJour: 1,
      );

      CarteAccueil carte(String id) =>
          CarteAccueil.registre.firstWhere((CarteAccueil c) => c.id == id);

      expect(carte('chambres').valeur(donnees, fr), '5/12');
      expect(carte('reservations').valeur(donnees, fr), '3');
      expect(carte('checkin').valeur(donnees, fr), '2/1');

      // La carte « Réception » s'allume quand il y a des mouvements.
      expect(carte('checkin').alerte!(donnees), isTrue);
      expect(carte('checkin').alerte!(const DonneesAccueil()), isFalse);
      expect(carte('chambres').alerte, isNull);
    });

    test('les valeurs restaurant reflètent le service du jour', () {
      const DonneesAccueil donnees = DonneesAccueil(
        tablesTotal: 10,
        tablesOccupees: 4,
        commandesActives: 3,
        cuisineEnAttente: 2,
      );

      CarteAccueil carte(String id) =>
          CarteAccueil.registre.firstWhere((CarteAccueil c) => c.id == id);

      expect(carte('tables').valeur(donnees, fr), '4/10');
      expect(carte('commandes').valeur(donnees, fr), '3');
      expect(carte('cuisine').valeur(donnees, fr), '2');

      // La carte « Cuisine » s'allume dès qu'une commande attend.
      expect(carte('cuisine').alerte!(donnees), isTrue);
      expect(carte('cuisine').alerte!(const DonneesAccueil()), isFalse);
      expect(carte('tables').alerte, isNull);
    });

    test('l\'alerte de stock suit le seuil', () {
      CarteAccueil stock() =>
          CarteAccueil.registre.firstWhere((CarteAccueil c) => c.id == 'stock');

      expect(
        stock().alerte!(const DonneesAccueil(stockAlertes: 2)),
        isTrue,
      );
      expect(
        stock().alerte!(const DonneesAccueil(stockAlertes: 0)),
        isFalse,
      );
      // Les autres cartes n'ont pas d'alerte dynamique.
      expect(
        CarteAccueil.registre
            .firstWhere((CarteAccueil c) => c.id == 'produits')
            .alerte,
        isNull,
      );
    });

    test('le titre « Produits » est localisé (fr)', () {
      final CarteAccueil produits = CarteAccueil.registre
          .firstWhere((CarteAccueil c) => c.id == 'produits');

      expect(produits.titre(fr), 'Produits');
    });
  });
}
