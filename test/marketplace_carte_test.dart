// test/marketplace_carte_test.dart
//
// 🎨 CORRECTIF 76 — LE CADRE DES CARTES DE LA VITRINE PUBLIQUE.
//
// La carte produit a été refondue en « vitrine d'application » (Play Store /
// Shopify) : cadre arrondi, voile dégradé, pastille de prix, ligne boutique
// avec vignette ronde, pastille de disponibilité.
//
// Ces tests protègent le POINT FRAGILE d'une telle refonte : la mise en page.
// Une carte de grille a une hauteur IMPOSÉE — si le contenu grandit (nom sur
// deux lignes, prix long, échelle de texte augmentée par le téléphone), le
// contenu déborde et Flutter lève une exception de rendu. On vérifie donc que
// la carte tient dans la vignette étroite d'un téléphone, y compris avec un
// texte agrandi.
//
//     flutter test test/marketplace_carte_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/boutique_publique.dart';
import 'package:biashara_yangu/models/produit_public.dart';
import 'package:biashara_yangu/widgets/carte_boutique_publique.dart';
import 'package:biashara_yangu/widgets/carte_produit_public.dart';

const ResumeBoutique _boutique = ResumeBoutique(
  espaceId: 'espace-1',
  nom: 'Alimentation Le Bon Prix',
  type: 'boutique',
  quartier: 'Katuba',
  ville: 'Lubumbashi',
  adresse: '12, avenue de la Paix',
  telephone: '+243970000000',
  localisationVerifiee: true,
  nbProduits: 3,
);

const ProduitPublic _produit = ProduitPublic(
  publicationId: 'pub-1',
  produitId: 1,
  nom: 'Riz parfumé 25 kg — sac complet, qualité supérieure',
  boutique: _boutique,
  prix: 125000,
  unite: 'sac',
  categorie: 'Alimentation',
  disponible: true,
  attributs: <String, String>{'taille': 'XL', 'couleur': 'Bleu'},
  distanceKm: 2.4,
);

Widget _habillage({required Widget enfant, double echelle = 1.0}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(echelle)),
        child: Center(child: enfant),
      ),
    ),
  );
}

void main() {
  group('CarteProduitPublic — tenue dans le cadre', () {
    testWidgets('tient dans une vignette de grille (téléphone)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _habillage(
          enfant: const SizedBox(
            width: 172,
            height: 262,
            child: CarteProduitPublic(produit: _produit, compacte: true),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Riz parfumé'), findsOneWidget);
      expect(find.text('Disponible'), findsOneWidget);
    });

    testWidgets('tient dans une carte pleine largeur (liste)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _habillage(
          enfant: const SizedBox(
            width: 360,
            child: CarteProduitPublic(produit: _produit),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Alimentation Le Bon Prix'), findsOneWidget);
    });

    testWidgets('tient avec un texte agrandi (accessibilité)', (
      WidgetTester tester,
    ) async {
      // La grille utilise `MiseEnPageAdaptative.proportionCarte` : la hauteur
      // de vignette suit l'échelle de texte. On reproduit exactement cette
      // hauteur (262 × 1,4) pour vérifier qu'aucune carte ne déborde.
      await tester.pumpWidget(
        _habillage(
          echelle: 1.4,
          enfant: const SizedBox(
            width: 172,
            height: 367,
            child: CarteProduitPublic(produit: _produit, compacte: true),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('produit indisponible : pastille rouge, pas de cadre cassé', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _habillage(
          enfant: const SizedBox(
            width: 172,
            height: 262,
            child: CarteProduitPublic(
              produit: ProduitPublic(
                publicationId: 'pub-2',
                produitId: 2,
                nom: 'Huile de palme',
                boutique: _boutique,
                prix: 8500,
                unite: 'litre',
                disponible: false,
              ),
              compacte: true,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Indisponible'), findsOneWidget);
    });
  });

  group('CarteBoutiquePublique — bandeau vitrine', () {
    testWidgets('affiche le nom, la distance et la position confirmée', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _habillage(
          enfant: const SizedBox(
            width: 360,
            child: CarteBoutiquePublique(boutique: _boutique),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Alimentation Le Bon Prix'), findsOneWidget);
      expect(find.textContaining('Katuba'), findsOneWidget);
      expect(find.text('Position confirmée'), findsOneWidget);
      expect(find.textContaining('3 articles'), findsOneWidget);
    });

    testWidgets('sans produit : pas de ligne articles', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _habillage(
          enfant: const SizedBox(
            width: 280,
            child: CarteBoutiquePublique(
              boutique: _boutique,
              jamaisSansProduit: true,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('articles'), findsNothing);
    });
  });
}
