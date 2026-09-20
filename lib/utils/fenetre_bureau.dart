// lib/utils/fenetre_bureau.dart
//
// 🌐 PHASE F (web) — CONFIGURATION DE LA FENÊTRE BUREAU.
//
// La fenêtre est configurée NATIVEMENT (linux/runner, windows/runner) : le
// greffon `window_manager` a été retiré après le crash Linux du 20/09/2026
// (SIGSEGV GTK — voir fenetre_bureau_native.dart). Les deux branches sont
// désormais des no-op ; la structure conditionnelle est conservée pour la
// compilation web sans `dart:io`.

export 'fenetre_bureau_stub.dart'
    if (dart.library.io) 'fenetre_bureau_native.dart';
