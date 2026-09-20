// lib/pages/profile_page.dart
import 'package:biashara_yangu/utils/image_locale.dart';
import 'package:flutter/material.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/pages/profile_edit_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Utilisateur? utilisateur;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    // 1. Lire l'ID de la session (String? - UUID)
    final uidString = await SessionManager.getUserId();
    if (uidString == null) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    // ❌ Suppression de la logique de conversion int.tryParse
    // final uidInt = int.tryParse(uidString);
    // if (uidInt == null) { ... }

    // 🔑 CORRECTION (Ancienne Ligne 31) : Passer l'ID String (UUID) au DBHelper.
    // L'ID utilisateur doit toujours être de type String dans le contexte UUID/Supabase.
    final u = await DBHelper.instance.getUtilisateurById(uidString);

    if (mounted) {
      setState(() {
        utilisateur = u;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final avatarImage =
        (utilisateur?.avatar != null && utilisateur!.avatar!.isNotEmpty)
            ? (imageProviderLocalSiExiste(utilisateur!.avatar!) ??
                const AssetImage('assets/user.jpg'))
            : const AssetImage('assets/user.jpg');

    return Scaffold(
      appBar: AppBar(title: const Text('Profil Utilisateur')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: utilisateur == null
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Aucun profil trouvé.'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/setup'),
              child: const Text('Créer un profil'),
            ),
          ],
        )
            : Column(
          children: [
            CircleAvatar(radius: 50, backgroundImage: avatarImage),
            const SizedBox(height: 16),
            Text(utilisateur!.nom, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(utilisateur!.email, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                // Ouvrir la page d'édition du profil
                final updated = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileEditPage()),
                );
                if (updated == true) {
                  _loadUser(); // rafraîchir après modification
                }
              },
              child: const Text('Modifier Profil'),
            ),
          ],
        ),
      ),
    );
  }
}