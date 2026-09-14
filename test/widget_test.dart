// This is a basic Flutter widget test.
// ... (commentaires inchangés)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/main.dart';
// Note: Le test utilise le widget racine BiasharaApp à la place de l'ancien MyApp.

void main() {
  testWidgets('Application initialization smoke test', (WidgetTester tester) async {
    // 🔑 CORRECTION : Utilise BiasharaApp, qui est le nouveau point d'entrée.
    // NOTE : Tester BiasharaApp nécessite de simuler le LanguageManager et ThemeManager,
    // mais pour un test minimal de 'smoke test', nous utilisons un conteneur simple.

    // Pour simplifier le test sans simuler tous les providers (LanguageManager, ThemeManager, GoRouter),
    // nous allons tester directement la classe principale si elle était simple, ou sa page principale
    // si l'initialisation des providers est trop complexe pour un simple 'smoke test'.

    // Étant donné que BiasharaApp dépend de MultiProvider et GoRouter, le test ci-dessous peut encore échouer.
    // Une solution plus robuste est de ne tester que les widgets unitaires ou d'utiliser un widget mock.

    // Pour le moment, tentons de tester le widget racine :
    await tester.pumpWidget(const BiasharaApp()); // ⬅️ Utilise BiasharaApp

    // Puisque BiasharaApp redirige vers SplashScreen ou Login, nous ne pouvons pas tester le "Counter" classique.
    // Testons un élément que BiasharaApp doit afficher (ex: un MaterialApp/MaterialApp.router est présent).
    expect(find.byType(MaterialApp), findsOneWidget);

    // Vous devriez ajouter des tests spécifiques pour les composants que vous voulez vérifier
    // (ex: vérifier que le SplashScreen s'affiche, ou que la barre de navigation est présente après login).

    // L'ancien test de compteur est maintenant obsolète.

    // Anciens expects (commentés ou supprimés car le compteur n'existe plus):
    // expect(find.text('0'), findsOneWidget);
    // await tester.tap(find.byIcon(Icons.add));
    // await tester.pump();
    // expect(find.text('1'), findsOneWidget);
  });
}