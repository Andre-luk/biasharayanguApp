import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart'; // Utilisé pour context.pop(true)
import 'package:image_picker/image_picker.dart';
// import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase service + modèle + session
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
// 🚀 Import pour la mise à jour locale
import 'package:biashara_yangu/db_helper.dart';
// 🔑 Ajouté pour l'internationalisation (si votre projet l'utilise)
// import 'package:biashara_yangu/l10n/app_localizations.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  final SupabaseService _supabaseService = SupabaseService.instance;
  // 🚀 Accès au Helper DB pour la mise à jour locale
  final DBHelper _dbHelper = DBHelper.instance;

  bool _loading = true;

  // L'ID utilisateur est un String UUID; on le stocke en String?
  String? _userId;
  Utilisateur? _user;

  // Avatar
  File? _avatarFile;
  // 💡 L'avatar URL stockera désormais soit le chemin Cloud existant (si chargé),
  // soit le chemin LOCAL du nouveau fichier.
  String? _avatarUrl;
  bool _isSaving = false;

  final ImagePicker _picker = ImagePicker();
  // ❌ Supprimé car on n'utilise plus Supabase Storage
  // static const String _bucket = 'avatars';

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 🔑 Bonne pratique: Libérer les contrôleurs
  @override
  void dispose() {
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // Helper : convertir n'importe quelle valeur en String? sans lancer d'erreur
  String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    // Tenter de convertir en String, sinon renvoyer null pour la sûreté
    try {
      return v.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final userId = await SessionManager.getUserId();

      _userId = _asString(userId);

      if (_userId != null) {
        // 🚀 Charger depuis la DB locale en priorité (plus rapide)
        final u = await _dbHelper.getUtilisateurById(_userId!);

        // Fallback Supabase si non trouvé localement ou besoin de re-synchroniser
        if (u == null) {
          final uRemote = await _supabaseService.getUtilisateurData(_userId!);
          _user = uRemote;
        } else {
          _user = u;
        }

        if (_user != null) {
          _nomCtrl.text = _user!.nom;
          _emailCtrl.text = _user!.email;
          // 💡 L'avatar pourrait être un chemin Cloud ou un chemin Local enregistré précédemment
          _avatarUrl = _asString(_user!.avatar);
        }
      }
    } catch (e) {
      print('Erreur lors du chargement du profil: $e');
      // 🔑 Afficher une SnackBar pour l'utilisateur
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur de chargement du profil.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _avatarFile = File(pickedFile.path);
        // Mettre à jour _avatarUrl avec le chemin local pour l'affichage immédiat
        _avatarUrl = pickedFile.path;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _user == null || _userId == null) return;

    setState(() => _isSaving = true);

    String? newAvatarPath = _avatarUrl;
    final String currentEmail = _user!.email;
    final String newEmail = _emailCtrl.text.trim();
    final String newNom = _nomCtrl.text.trim();

    // Flag pour savoir si l'email change
    final bool emailChanged = newEmail != currentEmail;

    try {
      // 1) Gestion de l'image (Chemin Local)
      if (_avatarFile != null) {
        newAvatarPath = _avatarFile!.path;
      }

      // 2) Mettre à jour l'Auth Supabase si l'email a changé
      if (emailChanged) {
        try {
          await _supabaseService.client.auth.updateUser(
            UserAttributes(email: newEmail),
          );
        } on AuthException catch (e) {
          // Si updateUser échoue, on affiche l'erreur et on quitte pour ne pas mettre à jour le nom
          throw Exception('Impossible de mettre à jour l\'email Auth: ${e.message}');
        }
      }

      // 3) Mettre à jour la table utilisateurs (métadonnées CLOUD)
      final Map<String, dynamic> updateCloudData = {
        'nom': newNom,
        'email': newEmail,
        // Pas d'update pour 'avatar' ici
      };

      // On n'update que le nom et l'email sur Supabase
      await _supabaseService.client
          .from('utilisateurs')
          .update(updateCloudData)
          .eq('id', _userId!);

      // 🚀 CORRECTION MAJEURE: Mise à jour de l'objet utilisateur local
      final updatedUser = _user!.copyWith(
        nom: newNom,
        email: newEmail,
        avatar: newAvatarPath, // 💡 Stocke le chemin local ou l'ancien chemin
      );

      // 🚀 CORRECTION MAJEURE: Mise à jour dans la base de données locale (SQLite)
      await _dbHelper.updateUtilisateur(updatedUser);

      // Mise à jour de l'état local pour le prochain changement
      _user = updatedUser;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil mis à jour')));

      // 🔑 Utilisation de context.pop(value) pour GoRouter
      context.pop(true);

    } on StorageException catch (e) {
      // ❌ Cette erreur ne devrait plus arriver !
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de stockage (vérifiez la DB): ${e.message}')));
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur d\'authentification: ${e.message}')));
    } catch (e) {
      // 🚀 Gérer l'exception lancée si la mise à jour de l'Auth email a échoué
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de sauvegarde: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // 🔑 Méthode centralisée pour déterminer l'ImageProvider
  ImageProvider _getDisplayImage(ThemeData theme) {
    const defaultAssetPath = 'assets/user.jpg'; // Chemin d'image par défaut

    if (_avatarFile != null) {
      // 1. Nouvelle image sélectionnée
      return FileImage(_avatarFile!);
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      if (_avatarUrl!.startsWith('http')) {
        // 2a. Ancienne URL Cloud
        return NetworkImage(_avatarUrl!);
      } else {
        // 2b. Chemin de fichier local enregistré
        final localFile = File(_avatarUrl!);
        if (localFile.existsSync()) {
          return FileImage(localFile);
        }
      }
    }

    // 3. Fallback: Asset par défaut
    return const AssetImage(defaultAssetPath);
  }

  // MARK: - BUILD (UI Material 3)

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Modifier profil')), body: const Center(child: CircularProgressIndicator()));

    // Déterminer l'ImageProvider
    final ImageProvider displayImage = _getDisplayImage(theme);

    // Vérifier si nous devons afficher l'icône de l'appareil photo dans l'avatar
    final bool showCameraIcon = (_avatarFile == null && (_avatarUrl == null || _avatarUrl!.isEmpty || displayImage is AssetImage));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier profil'),
        // M3: Utilisation de surfaceTintColor pour une meilleure intégration
        surfaceTintColor: theme.colorScheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- AVATAR (M3 Style) ---
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      backgroundImage: displayImage,
                      child: showCameraIcon
                          ? Icon(Icons.person, size: 60, color: theme.colorScheme.onPrimaryContainer)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      // Bouton d'édition sur l'avatar
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: theme.colorScheme.primary,
                          child: Icon(Icons.camera_alt_rounded, size: 18, color: theme.colorScheme.onPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // --- CHAMP NOM (M3 Outlined/Filled) ---
              TextFormField(
                controller: _nomCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  prefixIcon: Icon(Icons.person_outline), // Icône M3
                  border: OutlineInputBorder(), // Style M3 standard
                ),
                validator: (v) => v == null || v.isEmpty ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),

              // --- CHAMP EMAIL (M3 Outlined/Filled) ---
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined), // Icône M3
                  border: OutlineInputBorder(), // Style M3 standard
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || !v.contains('@') ? 'Email invalide' : null,
              ),
              const SizedBox(height: 32),

              // --- BOUTON ENREGISTRER (M3 FilledButton) ---
              FilledButton( // Utilisation du FilledButton M3 pour l'action principale
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50), // Hauteur standard
                  textStyle: theme.textTheme.titleMedium,
                ),
                child: _isSaving
                    ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: theme.colorScheme.onPrimary, // Couleur M3
                    )
                )
                    : const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}