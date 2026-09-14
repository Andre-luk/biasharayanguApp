import 'package:flutter/material.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/db_helper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Délai de 2 secondes avant de vérifier la session et de naviguer
    Timer(const Duration(seconds: 2), () => _checkSession());
  }

  Future<void> _checkSession() async {
    final userId = await SessionManager.getUserId();

    if (!mounted) return; // Sécurité si le widget est démonté

    if (userId != null) {
      // 1. Session existante -> aller directement à la page principale
      context.go('/main');
      return;
    }

    // 2. Pas de session : vérifier s'il y a au moins un utilisateur enregistré (setup terminé)
    final firstUser = await DBHelper.instance.getFirstUtilisateur();
    if (!mounted) return;

    if (firstUser == null) {
      // 2a. Pas d’utilisateur (première utilisation) -> config initiale
      context.go('/setup');
    } else {
      // 2b. Utilisateur existe mais pas de session active -> demander PIN
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Récupération de la taille de l'écran pour un affichage dynamique
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          // 🚀 Centrer verticalement le contenu
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Utilisation du logo Biashara
            Image(
              image: const AssetImage('assets/Biashara app off.png'), // Assurez-vous que le chemin est correct
              // 🚀 Agrandissement de la taille du logo
              height: size.height * 0.3, // Utiliser 30% de la hauteur de l'écran (taille dynamique)
              // OU : height: 250, // Taille fixe et plus grande
            ),
            const SizedBox(height: 24),
            // Rétablissement du titre (optionnel, mais souvent utilisé sur l'écran de splash)
            const Text(
              '',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 40), // Augmentation de l'espace avant l'indicateur
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          ],
        ),
      ),
    );
  }
}