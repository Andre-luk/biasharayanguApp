// lib/utils/fenetre_bureau_native.dart
//
// 🖥️ Configuration de fenêtre pour Windows / Linux / macOS
// (taille, centrage, icône) — code natif uniquement (`dart:io` + paquet
// `window_manager`).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Prépare et affiche la fenêtre de bureau (no-op sur mobile).
Future<void> configurerFenetreBureau() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

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

    // 🖼️ Icône de la fenêtre — Linux : le logo est chargé depuis le paquet
    // (Windows utilise directement l'icône .ico du .exe).
    if (Platform.isLinux) {
      try {
        final String icone =
            '${Directory(Platform.resolvedExecutable).parent.path}'
            '/data/flutter_assets/assets/Biashara_app_off-.png';
        if (File(icone).existsSync()) {
          await windowManager.setIcon(icone);
        }
      } catch (e) {
        debugPrint('Icône de fenêtre ignorée : $e');
      }
    }
  });
}
