// lib/utils/fenetre_bureau_native.dart
//
// 🖥️ Fenêtre de bureau — CONFIGURATION NATIVE (plus de greffon Dart).
//
// ⚠️ Historique (2026-09-20) : le greffon `window_manager` a été RETIRÉ du
// projet. Sur Linux il plantait au démarrage (SIGSEGV dans
// `libwindow_manager_plugin.so` → `gtk_widget_show`) : son gestionnaire du
// signal GTK « show » s'attache à la fenêtre dès l'enregistrement du plugin,
// même sans aucun appel Dart — impossible à contourner côté code.
//
// La fenêtre est donc configurée NATIVEMENT :
//   • Linux   : `linux/runner/my_application.cc` (1200×800, min 900×600,
//               titre « Biashara Yangu ») ;
//   • Windows : `windows/runner/main.cpp` (1200×800,
//               titre « Biashara Yangu ») ;
//   • icône   : raccourci .desktop (Linux) / .ico du .exe (Windows).

/// No-op : la configuration de fenêtre est faite nativement (voir en-tête).
Future<void> configurerFenetreBureau() async {}
