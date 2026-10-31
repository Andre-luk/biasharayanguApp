// test/catalogue_parametres_test.dart
//
// ⚙️ LES PARAMÈTRES S'ADAPTENT — et ne cachent jamais trop.
//
// Ce fichier verrouille la règle la plus importante : un réglage ne doit
// disparaître que lorsque l'application SAIT qu'il n'a pas de sens (type
// d'entreprise connu, module absent, rôle sans droit). Type inconnu ou profil
// non chargé → tout reste visible, comme avant.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/l10n/app_localizations_fr.dart';
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/type_activite.dart';
import 'package:biashara_yangu/ui/parametres/catalogue_parametres.dart';

void main() {
  final AppLocalizationsFr T = AppLocalizationsFr();

  /// Rôle « patron » : tous les droits.
  bool toutAutorise(PageAccess page, ActionAccess action) => true;

  /// Rôle « vendeur » : aucune page de configuration.
  bool aucunDroit(PageAccess page, ActionAccess action) => false;

  List<ParametreApp> visibles({
    Set<String> modules = const <String>{},
    bool profilCharge = false,
    TypeActivite? typeActivite,
    bool Function(PageAccess, ActionAccess)? peut,
  }) {
    return CatalogueParametres.visibles(
      modules: modules,
      profilCharge: profilCharge,
      typeActivite: typeActivite,
      peut: peut ?? toutAutorise,
    );
  }

  List<String> ids(List<ParametreApp> entrees) =>
      entrees.map((ParametreApp p) => p.id).toList();

  group('Visibilité par type d\'activité', () {
    test('une distribution voit ses réglages de tournées', () {
      final List<String> vus = ids(visibles(typeActivite: TypeActivite.distribution));

      expect(vus, contains('tournees'));
      expect(vus, contains('recipients'));
    });

    test('une boutique ne voit pas les réglages de distribution', () {
      final List<String> vus = ids(visibles(typeActivite: TypeActivite.boutique));

      expect(vus, isNot(contains('tournees')));
      expect(vus, isNot(contains('recipients')));
    });

    test('sans type renseigné, rien n\'est masqué (fail-open)', () {
      final List<String> vus = ids(visibles());

      expect(vus, contains('tournees'));
      expect(vus, contains('recipients'));
      expect(vus, contains('categories'));
    });
  });

  group('Visibilité par module', () {
    test('profil chargé sans le module produits : catégories masquées', () {
      final List<String> vus = ids(visibles(
        modules: <String>{ModuleCode.ventes},
        profilCharge: true,
      ));

      expect(vus, isNot(contains('categories')));
      expect(vus, contains('profil'));
    });

    test('profil chargé avec le module produits : catégories visibles', () {
      final List<String> vus = ids(visibles(
        modules: <String>{ModuleCode.ventes, ModuleCode.produits},
        profilCharge: true,
      ));

      expect(vus, contains('categories'));
    });

    test('profil non chargé : tout reste visible', () {
      final List<String> vus =
          ids(visibles(modules: const <String>{}, profilCharge: false));

      expect(vus, contains('categories'));
      expect(vus, contains('import-articles'));
    });
  });

  group('Visibilité par rôle', () {
    test('un rôle sans droit ne voit aucun réglage protégé', () {
      final List<String> vus = ids(visibles(peut: aucunDroit));

      expect(vus, isNot(contains('equipe')));
      expect(vus, isNot(contains('factures-abonnement')));
      expect(vus, isNot(contains('journal-audit')));
      // Les réglages sans permission restent accessibles (profil, guide…).
      expect(vus, contains('profil'));
      expect(vus, contains('guide'));
    });

    test('le patron voit les réglages protégés', () {
      final List<String> vus = ids(visibles());

      expect(vus, contains('equipe'));
      expect(vus, contains('factures-abonnement'));
      expect(vus, contains('journal-audit'));
    });
  });

  group('Sections', () {
    test('les sections suivent l\'ordre déclaré', () {
      final Map<String, List<ParametreApp>> sections =
          CatalogueParametres.sections(visibles());
      final List<String> ordre = sections.keys.toList();

      expect(ordre.first, SectionParametres.compte);
      expect(ordre.indexOf(SectionParametres.compte),
          lessThan(ordre.indexOf(SectionParametres.application)));
      expect(ordre.indexOf(SectionParametres.legal),
          greaterThan(ordre.indexOf(SectionParametres.application)));
    });

    test('une section sans réglage visible n\'est pas rendue', () {
      final Map<String, List<ParametreApp>> sections =
          CatalogueParametres.sections(visibles(typeActivite: TypeActivite.boutique));

      expect(sections.containsKey(SectionParametres.distribution), isFalse);
    });
  });

  group('Recherche', () {
    test('trouve un réglage par son titre', () {
      final List<ParametreApp> trouvees = CatalogueParametres.rechercher(
        'devise',
        visibles(),
        T,
      );

      expect(ids(trouvees), contains('devise'));
    });

    test('ignore la casse et les accents', () {
      final List<ParametreApp> trouvees = CatalogueParametres.rechercher(
        'PUBLICITÉS',
        visibles(),
        T,
      );

      expect(ids(trouvees), contains('publicites'));
    });

    test('trouve aussi par le nom de la rubrique', () {
      final List<ParametreApp> trouvees = CatalogueParametres.rechercher(
        'abonnement',
        visibles(),
        T,
      );

      expect(trouvees, isNotEmpty);
      expect(
        trouvees.every((ParametreApp p) =>
            p.section == SectionParametres.abonnement ||
            '${p.titre(T)} ${p.sousTitre(T)}'.toLowerCase().contains('abonnement')),
        isTrue,
      );
    });

    test('une recherche vide ne filtre rien', () {
      final List<ParametreApp> base = visibles();
      expect(CatalogueParametres.rechercher('', base, T).length, base.length);
      expect(CatalogueParametres.rechercher('   ', base, T).length, base.length);
    });

    test('une recherche sans résultat renvoie une liste vide', () {
      expect(
        CatalogueParametres.rechercher('zzzzz', visibles(), T),
        isEmpty,
      );
    });

    test('la recherche ne dépasse jamais les réglages autorisés', () {
      // Un vendeur qui tape « équipe » ne doit rien obtenir.
      final List<ParametreApp> trouvees = CatalogueParametres.rechercher(
        'equipe',
        visibles(peut: aucunDroit),
        T,
      );

      expect(trouvees, isEmpty);
    });
  });

  group('Cohérence du registre', () {
    test('chaque identifiant est unique', () {
      final Set<String> vus = <String>{};
      for (final ParametreApp p in CatalogueParametres.tous) {
        expect(vus.add(p.id), isTrue, reason: 'doublon : ${p.id}');
      }
    });

    test('chaque section utilisée est connue', () {
      for (final ParametreApp p in CatalogueParametres.tous) {
        expect(SectionParametres.ordre, contains(p.section),
            reason: 'section inconnue pour ${p.id}');
      }
    });

    test('chaque réglage a une route', () {
      for (final ParametreApp p in CatalogueParametres.tous) {
        expect(p.route, isNotNull, reason: 'route manquante : ${p.id}');
      }
    });
  });
}
