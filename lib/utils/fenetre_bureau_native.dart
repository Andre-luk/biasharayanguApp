// lib/utils/fenetre_bureau_native.dart
//
// 🖥️ Configuration de fenêtre pour Windows / macOS (taille, centrage).
//
// ⚠️ LINUX VOLONTAIREMENT EXCLU — diagnostic du 2026-09-20 (core dump) :
// le greffon `window_manager` 0.2.5 plante (SIGSEGV dans gtk_widget_show →
// libwindow_manager_plugin.so) sur les GTK récents au moment d'afficher la
// fenêtre. La fenêtre Linux est donc configurée NATIVEMENT dans
// `linux/runner/my_application.cc` (taille 1200×800, minimum 900×600,
// titre « Biashara Yangu »), et l'icône vient du raccourci .desktop.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Prépare et affiche la fenêtre de bureau.
/// • Windows / macOS : window_manager (taille, centrage, focus) ;
/// • Linux : no-op (configuration native — voir en-tête) ;
/// • mobile / web : no-op.
Future<void> configurerFenetreBureau() async {
  if (!Platform.isWindows && !Platform.isMacOS) return;

  await windowManager.ensureInitialized();
  const WindowOptions windowOptions = WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(900, 600),
    center: true,
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
