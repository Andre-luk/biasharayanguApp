// test/mise_en_page_adaptative_test.dart
//
// 🖥️ Tests PURS de la mise en page adaptative : marges de centrage et nombre
// de colonnes de la grille d'accueil. Aucun réseau, aucun widget.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/ui/mise_en_page_adaptative.dart';

void main() {
  group('MiseEnPageAdaptative — marge latérale', () {
    test('téléphone : marge minimale de 20', () {
      expect(MiseEnPageAdaptative.margeLaterale(360), 20);
      expect(MiseEnPageAdaptative.margeLaterale(390), 20);
      expect(MiseEnPageAdaptative.margeLaterale(600), 20);
    });

    test('ordinateur : le contenu est centré et borné à 980', () {
      // 1366 × 768 (portable) : 1366 - 2 × 193 = 980.
      expect(MiseEnPageAdaptative.margeLaterale(1366), 193);
      expect(MiseEnPageAdaptative.largeurContenu(1366), 980);

      // 1200 × 800 (fenêtre par défaut) : 1200 - 2 × 110 = 980.
      expect(MiseEnPageAdaptative.margeLaterale(1200), 110);
      expect(MiseEnPageAdaptative.largeurContenu(1200), 980);

      // Très grand écran : le contenu ne s'étire pas, il reste centré.
      expect(MiseEnPageAdaptative.largeurContenu(2560), 980);
    });

    test('valeur de bascule : jusqu\'à 1020 la marge reste minimale', () {
      expect(MiseEnPageAdaptative.margeLaterale(1020), 20);
      expect(MiseEnPageAdaptative.margeLaterale(1021), 20.5);
    });

    test('valeurs absurdes : jamais de marge négative ni de division par zéro', () {
      expect(MiseEnPageAdaptative.margeLaterale(0), 20);
      expect(MiseEnPageAdaptative.margeLaterale(-100), 20);
      expect(MiseEnPageAdaptative.margeLaterale(double.infinity), 20);
      expect(MiseEnPageAdaptative.largeurContenu(0), 0);
    });
  });

  group('MiseEnPageAdaptative — colonnes de la grille', () {
    test('téléphone : 2 colonnes (comportement historique)', () {
      expect(MiseEnPageAdaptative.colonnesGrille(360), 2);
      expect(MiseEnPageAdaptative.colonnesGrille(390), 2);
      expect(MiseEnPageAdaptative.colonnesGrille(600), 2);
      // 700 - 40 = 660 → 660 / 280 = 2 colonnes (2,35 tronqué).
      expect(MiseEnPageAdaptative.colonnesGrille(700), 2);
    });

    test('ordinateur : 3 colonnes au lieu de 2', () {
      // 1200 → contenu 980 → 980 / 280 = 3.
      expect(MiseEnPageAdaptative.colonnesGrille(1200), 3);
      expect(MiseEnPageAdaptative.colonnesGrille(1366), 3);
      expect(MiseEnPageAdaptative.colonnesGrille(2560), 3);
    });

    test('le nombre de colonnes est borné par maxColonnes', () {
      expect(MiseEnPageAdaptative.colonnesGrille(2000, maxColonnes: 2), 2);
      // Le contenu est borné à 980 : 4 colonnes exigent des cartes plus
      // étroites (980 / 240 = 4).
      expect(
        MiseEnPageAdaptative.colonnesGrille(
          2000,
          maxColonnes: 4,
          largeurCarte: 240,
        ),
        4,
      );
    });

    test('les cartes gardent une largeur raisonnable (≥ 280)', () {
      for (final double largeur in <double>[1200, 1366, 1920, 2560]) {
        final int colonnes = MiseEnPageAdaptative.colonnesGrille(largeur);
        final double largeurCarte = MiseEnPageAdaptative.largeurContenu(largeur) /
            colonnes;
        expect(
          largeurCarte,
          greaterThanOrEqualTo(MiseEnPageAdaptative.largeurCarteMin),
          reason: 'Carte trop étroite à $largeur px',
        );
      }
    });
  });
}
