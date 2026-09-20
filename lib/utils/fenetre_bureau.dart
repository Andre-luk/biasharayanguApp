// lib/utils/fenetre_bureau.dart
//
// 🌐 PHASE F (web) — CONFIGURATION DE LA FENÊTRE BUREAU.
//
// Délègue à `window_manager` sur les plateformes de bureau (Windows,
// Linux, macOS) et ne fait RIEN sur les autres plateformes (web, mobile) :
// l'application est ainsi compilable pour le web sans `dart:io`.

export 'fenetre_bureau_stub.dart'
    if (dart.library.io) 'fenetre_bureau_native.dart';
