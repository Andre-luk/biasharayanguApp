// test/widget_test.dart
//
// Smoke tests des widgets réutilisables de l'application.
//
// REMARQUE : l'ancienne version de ce fichier instanciait directement
// `BiasharaApp`, ce qui échouait systématiquement — le widget racine exige les
// providers `LanguageManager` / `ThemeManager` ainsi qu'un client Supabase
// initialisé. Les tests ci-dessous vérifient des widgets autonomes, sans
// dépendance réseau, et passent donc avec un simple `flutter test`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/statut_abonnement_chip.dart';

void main() {
  group('StatutAbonnementChip', () {
    testWidgets('affiche le libellé du statut', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatutAbonnementChip(statut: StatutAbonnement.suspendu),
          ),
        ),
      );

      expect(find.text('Suspendu'), findsOneWidget);
    });

    testWidgets('sait afficher les cinq statuts de la base',
        (WidgetTester tester) async {
      for (final StatutAbonnement statut
          in StatutAbonnement.statutsFiltrables) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: StatutAbonnementChip(statut: statut)),
          ),
        );

        expect(find.text(statut.libelle), findsOneWidget);
      }
    });
  });

  group('AppDropdownField', () {
    testWidgets('affiche le libellé et l\'indication',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDropdownField<String>(
              label: 'Ville',
              value: null,
              hint: 'Choisir une ville',
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'k1', child: Text('Kinshasa')),
              ],
              onChanged: (String? valeur) {},
            ),
          ),
        ),
      );

      expect(find.text('Ville'), findsOneWidget);
      expect(find.text('Choisir une ville'), findsOneWidget);
    });

    testWidgets('remonte la sélection via onChanged',
        (WidgetTester tester) async {
      String? selection;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDropdownField<String>(
              label: 'Ville',
              value: null,
              hint: 'Choisir une ville',
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'k1', child: Text('Kinshasa')),
                DropdownMenuItem<String>(
                    value: 'l1', child: Text('Lubumbashi')),
              ],
              onChanged: (String? valeur) => selection = valeur,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lubumbashi').last);
      await tester.pumpAndSettle();

      expect(selection, 'l1');
    });

    testWidgets('affiche le message d\'erreur fourni',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDropdownField<String>(
              label: 'Ville',
              value: null,
              errorText: 'Veuillez sélectionner une ville.',
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'k1', child: Text('Kinshasa')),
              ],
              onChanged: (String? valeur) {},
            ),
          ),
        ),
      );

      expect(find.text('Veuillez sélectionner une ville.'), findsOneWidget);
    });

    testWidgets('ne déclenche rien quand il est désactivé',
        (WidgetTester tester) async {
      bool appele = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDropdownField<String>(
              label: 'Groupe tarifaire',
              value: null,
              hint: 'Sélectionnez d\'abord une activité',
              enabled: false,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'g1', child: Text('Standard')),
              ],
              onChanged: (String? valeur) => appele = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      expect(appele, isFalse);
    });
  });
}
