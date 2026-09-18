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

    test('fail-open : profil NON chargé => mêmes cartes qu\'en boutique', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: const <String>{},
        profilCharge: false,
        autorise: autorisationPour(toutesPages),
      );

      expect(cartes.length, 9);
      expect(idsDe(cartes).first, 'produits');
    });

    test('profil vide MAIS chargé => tout reste visible (fail-open)', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: const <String>{},
        profilCharge: true,
        autorise: autorisationPour(toutesPages),
      );

      expect(cartes.length, 9);
    });
  });

  group('CarteAccueil.visibles — hôtel (phase B)', () {
    test('les cartes de commerce disparaissent du tableau de bord', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: profilHotel,
        profilCharge: true,
        autorise: autorisationPour(toutesPages),
      );

      expect(idsDe(cartes), <String>[
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

    test('les modules métier non codés n\'inventent aucune carte', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: profilHotel,
        profilCharge: true,
        autorise: autorisationPour(toutesPages),
      );

      for (final String code in <String>[
        'chambres',
        'reservations',
        'checkin'
      ]) {
        expect(
          cartes.where((CarteAccueil c) => c.module == code),
          isEmpty,
          reason: 'Aucune carte ne doit exister pour $code (phase C2)',
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
      };

      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: ModulesService.modulesBase,
        profilCharge: true,
        autorise: autorisationPour(pagesVendeur),
      );

      expect(idsDe(cartes), <String>['ventes', 'caisse', 'assistant_ia']);
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
