// test/univers_distribution_test.dart
//
// 🚚 MODULE 24 — SÉPARATION DES UNIVERS (boutique ↔ distribution).
//
// Vérifie les règles PURES : ce qu'un compte de distribution voit à
// l'accueil, et ce qui s'efface devant le module 24 (les tournées).
// Aucun accès réseau.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/type_activite.dart';
import 'package:biashara_yangu/services/contexte_distribution.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/ui/accueil/cartes_accueil.dart';

List<String> _idsDe(List<CarteAccueil> cartes) =>
    cartes.map((CarteAccueil c) => c.id).toList(growable: false);

/// Profil de modules d'une entreprise de distribution « complète ».
const Set<String> _modulesDistribution = <String>{
  ModuleCode.distribution,
  ModuleCode.ventes,
  ModuleCode.produits,
  ModuleCode.stock,
  ModuleCode.caisse,
  ModuleCode.rapports,
  ModuleCode.assistantIa,
};

bool Function(PageAccess, ActionAccess) _toutAutorise() =>
    (PageAccess _, ActionAccess __) => true;

void main() {
  group('ContexteDistribution — règles pures', () {
    test('un membre (rôle distribution) est toujours « univers distribution »',
        () {
      expect(
        ContexteDistribution.universDistributionPour(
          membre: true,
          entrepriseDistribution: false,
          moduleComplet: false,
        ),
        isTrue,
      );
    });

    test('le patron d\'une entreprise de distribution n\'y entre que si le '
        'module 24 est actif', () {
      expect(
        ContexteDistribution.universDistributionPour(
          membre: false,
          entrepriseDistribution: true,
          moduleComplet: true,
        ),
        isTrue,
      );
      expect(
        ContexteDistribution.universDistributionPour(
          membre: false,
          entrepriseDistribution: true,
          moduleComplet: false,
        ),
        isFalse,
      );
    });

    test('une boutique classique reste en univers boutique', () {
      expect(
        ContexteDistribution.universDistributionPour(
          membre: false,
          entrepriseDistribution: false,
          moduleComplet: true,
        ),
        isFalse,
      );
    });

    test('les tournées ne s\'effacent que devant un module 24 complet', () {
      expect(
        ContexteDistribution.masquerTourneesPour(
          membre: true,
          entrepriseDistribution: true,
          moduleComplet: true,
        ),
        isTrue,
      );
      // Distribution sans module 24 : elle garde ses tournées (module 23).
      expect(
        ContexteDistribution.masquerTourneesPour(
          membre: true,
          entrepriseDistribution: true,
          moduleComplet: false,
        ),
        isFalse,
      );
      // Boutique : rien à voir avec la distribution.
      expect(
        ContexteDistribution.masquerTourneesPour(
          membre: false,
          entrepriseDistribution: false,
          moduleComplet: false,
        ),
        isFalse,
      );
    });
  });

  group('CarteAccueil.visibles — univers distribution', () {
    test('les cartes de la BOUTIQUE disparaissent', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: _modulesDistribution,
        profilCharge: true,
        autorise: _toutAutorise(),
        typeActivite: TypeActivite.distribution,
        universDistribution: true,
        masquerTournees: true,
      );
      final List<String> ids = _idsDe(cartes);

      expect(ids, contains('distribution-pro'));
      // Stock, ventes, caisse, articles, rapports : c'est la boutique.
      expect(ids, isNot(contains('stock')));
      expect(ids, isNot(contains('ventes')));
      expect(ids, isNot(contains('caisse')));
      expect(ids, isNot(contains('produits')));
      expect(ids, isNot(contains('rapports')));
      // Les tournées du module 23 sont remplacées par le module 24.
      expect(ids, isNot(contains('tournees')));
      expect(ids, isNot(contains('ma-tournee')));
      expect(ids, isNot(contains('consignes')));
      expect(ids, isNot(contains('recipients')));
      // Les cartes communes restent (aide, abonnement).
      expect(ids, contains('assistant_ia'));
      expect(ids, contains('abonnement'));
    });

    test('sans les nouveaux drapeaux, rien ne change (boutique historique)',
        () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: _modulesDistribution,
        profilCharge: true,
        autorise: _toutAutorise(),
        typeActivite: TypeActivite.distribution,
      );
      final List<String> ids = _idsDe(cartes);

      expect(ids, contains('stock'));
      expect(ids, contains('ventes'));
      expect(ids, contains('tournees'));
      expect(ids, contains('distribution-pro'));
    });

    test('une distribution sans module 24 garde ses tournées', () {
      final List<CarteAccueil> cartes = CarteAccueil.visibles(
        modules: _modulesDistribution,
        profilCharge: true,
        autorise: _toutAutorise(),
        typeActivite: TypeActivite.distribution,
        universDistribution: false,
        masquerTournees: false,
      );
      final List<String> ids = _idsDe(cartes);

      expect(ids, contains('tournees'));
      expect(ids, contains('ma-tournee'));
    });
  });
}
