// lib/utils/fichiers_locaux.dart
//
// 🌐 PHASE F (web) — ENREGISTREMENT DE FICHIERS (PDF, Excel, QR, audit).
//
//   • natif : écrit dans les « Téléchargements » (repli : documents de
//     l'application) et renvoie le chemin du fichier ;
//   • web   : déclenche le téléchargement du navigateur et renvoie `null`
//     (aucun chemin : le fichier va dans les téléchargements du navigateur).

export 'fichiers_locaux_stub.dart'
    if (dart.library.io) 'fichiers_locaux_native.dart';
