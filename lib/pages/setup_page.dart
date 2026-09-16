// lib/pages/setup_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_auth;

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/sync_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

class SetupPage extends StatefulWidget {
  final bool adminCreating;
  final Utilisateur? editUser;
  const SetupPage({super.key, this.adminCreating = false, this.editUser});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeBoutiqueCtrl = TextEditingController(); // AJOUT : Contrôleur pour le code d'invitation

  String _role = 'vendor';
  bool _saving = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.editUser != null) {
      _nomCtrl.text = widget.editUser!.nom;
      _emailCtrl.text = widget.editUser!.email;
      _role = widget.editUser!.role;
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeBoutiqueCtrl.dispose(); // AJOUT : Libération du contrôleur
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppCouleurs.danger : AppCouleurs.succes,
      ),
    );
  }

  /// Attendre que le profil distant existe (trigger côté DB)
  Future<bool> _waitForRemoteProfile(String userId, {int maxAttempts = 6, int delayMs = 400}) async {
    final client = SupabaseService.instance.client;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final data = await client.from('utilisateurs').select().eq('id', userId).maybeSingle();
        if (data != null) return true;
      } catch (e) {
        // ignore and retry
      }
      await Future.delayed(Duration(milliseconds: delayMs));
    }
    return false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final nom = _nomCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text.trim();
    final codeSaisi = _codeBoutiqueCtrl.text.trim(); // AJOUT

    try {
      if (widget.editUser != null) {
        final u = Utilisateur(
          id: widget.editUser!.id,
          nom: nom,
          email: email,
          role: widget.editUser!.role,
          valide: widget.editUser!.valide,
          parentId: widget.editUser!.parentId,
        );
        await DBHelper.instance.updateUtilisateur(u);
        if (mounted) {
          _showSnackBar('Profil mis à jour');
          context.pop(true);
        }
        return;
      }

      // LOGIQUE DE PARENTÉ ET RÔLE
      String? parentId;
      String roleFinal = widget.adminCreating ? _role : 'vendor';

      if (widget.adminCreating) {
        // Le patron crée lui-même le collaborateur
        parentId = await SessionManager.getUserId();
      } else if (codeSaisi.isNotEmpty) {
        // Le collaborateur s'inscrit lui-même avec un code boutique
        parentId = codeSaisi;
        roleFinal = 'collaborator';
      }

      // 1) Créer le user via Supabase Auth
      final user = await SupabaseService.instance.signUpUser(
        email: email,
        password: password,
        nom: nom,
        role: roleFinal,
        parentId: parentId,
      );

      // 2) Ne PAS forcer une insertion serveur locale ici (le trigger DB doit créer la ligne).
      //    On attend que le trigger ait fini, puis on synchronise localement.

      final remoteProfileExists = await _waitForRemoteProfile(user.id!);
      if (remoteProfileExists) {
        // upsert local depuis le cloud
        try {
          await SyncService.instance.syncUserProfile(user.id!);
        } catch (e) {
          debugPrint('Erreur syncUserProfile après signup: $e');
        }
      } else {
        final minimal = Utilisateur(
          id: user.id,
          nom: nom,
          email: email,
          role: user.role ?? roleFinal,
          valide: 1,
          parentId: parentId,
        );
        try {
          await DBHelper.instance.insertUtilisateur(minimal);
          debugPrint('Profil distant non trouvé : insert local minimal effectué.');
        } catch (e) {
          debugPrint('Impossible d\'insérer localement le profil minimal: $e');
        }
      }

      if (!mounted) return;

      if (!widget.adminCreating) {
        // Inscription classique : on sauvegarde la session et on démarre la sync complète
        await SessionManager.setUserId(user.id!);
        await SessionManager.setUserRole(user.role ?? roleFinal);
        try {
          await SyncService.instance.ensureLocalUserAndStart(user.id!);
        } catch (e) {
          debugPrint('Erreur démarrage sync après signup: $e');
        }
        context.go('/main');
      } else {
        // Administrateur : collaborateur créé
        _showSnackBar("Utilisateur créé avec succès");
        context.pop(true);
      }
    } on supabase_auth.AuthException catch (e) {
      if (e.message.contains('already registered') || e.code == 'user_already_exists') {
        _showSnackBar('Cet email est déjà utilisé.', isError: true);
      } else {
        _showSnackBar(e.message, isError: true);
      }
    } catch (e) {
      _showSnackBar('Erreur : $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editUser != null;
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEdit ? 'Modifier profil' : (widget.adminCreating ? 'Nouvel utilisateur' : ''),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 520 : 420),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppCouleurs.marine.withValues(alpha: 0.08),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  )
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isEdit && !widget.adminCreating) ...[
                      Center(child: Image.asset('assets/Biashara_app_off-.png', height: 80)),
                      const SizedBox(height: 16),
                      const Text(
                        'Créer un compte',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Commencez à gérer votre commerce dès maintenant',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      const SizedBox(height: 32),
                    ],

                    _buildFieldTitle("Nom complet"),
                    TextFormField(
                      controller: _nomCtrl,
                      decoration: _buildInputDecoration(Icons.person_outline, "Votre nom"),
                      validator: (v) => v!.isEmpty ? 'Nom requis' : null,
                    ),
                    const SizedBox(height: 20),

                    _buildFieldTitle("Email"),
                    TextFormField(
                      controller: _emailCtrl,
                      enabled: !isEdit,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _buildInputDecoration(
                          Icons.email_outlined,
                          "exemple@mail.com",
                          isGreyed: isEdit
                      ),
                      validator: (v) => !v!.contains('@') ? 'Email invalide' : null,
                    ),
                    const SizedBox(height: 20),

                    if (!isEdit) ...[
                      _buildFieldTitle("Mot de passe"),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        decoration: _buildInputDecoration(
                          Icons.lock_outline_rounded,
                          "6 caractères minimum",
                          suffix: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) => v!.length < 6 ? 'Min 6 caractères' : null,
                      ),
                      const SizedBox(height: 20), // AJOUT : Espacement

                      // AJOUT : Champ Code Boutique pour les nouveaux utilisateurs
                      if (!widget.adminCreating) ...[
                        _buildFieldTitle("Code Boutique (Optionnel)"),
                        TextFormField(
                          controller: _codeBoutiqueCtrl,
                          decoration: _buildInputDecoration(
                            Icons.vpn_key_outlined,
                            "Collez le code de votre patron",
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0, left: 4.0),
                          child: Text(
                            "Laissez vide si vous êtes le propriétaire.",
                            style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ],

                    if (widget.adminCreating) ...[
                      const SizedBox(height: 20),
                      _buildFieldTitle("Rôle de l'utilisateur"),
                      DropdownButtonFormField<String>(
                        value: _role,
                        decoration: _buildInputDecoration(Icons.badge_outlined, ""),
                        items: const [
                          DropdownMenuItem(value: 'vendor', child: Text("Vendeur")),
                          DropdownMenuItem(value: 'collaborator', child: Text("Collaborateur")),
                          DropdownMenuItem(value: 'admin', child: Text("Administrateur")),
                        ],
                        onChanged: (v) => setState(() => _role = v!),
                      ),
                    ],

                    const SizedBox(height: 36),

                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: ModernLoader(
                                taille: 22,
                                epaisseur: 2.6,
                                couleur: Colors.white,
                                couleurSecondaire: Colors.white70,
                              ),
                            )
                          : Text(
                              isEdit
                                  ? 'METTRE À JOUR'
                                  : (widget.adminCreating
                                      ? 'AJOUTER'
                                      : 'S\'INSCRIRE'),
                              style: const TextStyle(letterSpacing: 1.0),
                            ),
                    ),

                    if (!isEdit && !widget.adminCreating)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text("Déjà un compte ? ", style: TextStyle(color: Colors.grey)),
                            TextButton(
                              onPressed: () => context.go('/login'),
                              child: const Text("Se connecter", style: TextStyle(fontWeight: FontWeight.bold)),
                            )
                          ],
                        ),
                      )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(IconData icon, String hint, {Widget? suffix, bool isGreyed = false}) {
    // Le style (fond, coins, état désactivé, focus) vient du thème global :
    // ici, seuls le libellé, l'icône et la teinte « lecture seule » changent.
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 22),
      suffixIcon: suffix,
      fillColor: isGreyed
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : null,
    );
  }
}