import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_auth;

import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/services/sync_service.dart';
import 'package:biashara_yangu/services/subscription_sync_service.dart';
import 'package:biashara_yangu/services/subscription_service.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/pages/password_recovery_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final SupabaseService _supabaseService = SupabaseService.instance;
  final SyncService _syncService = SyncService.instance;
  final DBHelper _dbHelper = DBHelper.instance;

  bool _isLoading = false;
  bool _obscurePassword = true;

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.blueGrey[800],
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    try {
      // 1. CONNEXION SUPABASE
      try {
        final user =
            await _supabaseService.signInUser(email: email, password: password);
        if (user != null && user.id != null) {
          final userId = user.id!;
          await SessionManager.setUserId(userId);

          try {
            await _syncService.syncUserProfile(userId);
            final localUser = await _dbHelper.getUtilisateurById(userId);

            // Extraction sécurisée du ownerId (Patron)
            final String? pId = localUser?.parentId;
            final String ownerId =
                (pId != null && pId.isNotEmpty) ? pId : userId;

            final role = localUser?.role ?? 'vendor';
            await SessionManager.setUserRole(role);

            final db = await _dbHelper.database;
            final subSync = SubscriptionSyncService(db: db);
            await subSync.downloadAndSaveSubscriptions(ownerId);

            // 👇 AJOUT IMPORTANT : Téléchargement de l'historique des données
            try {
              // 1. On télécharge tout l'historique depuis Supabase vers le téléphone (SQLite)
              await _syncService.initialDownload(userId);

              // 2. Par sécurité, s'il y avait des données locales créées hors ligne, on les pousse vers Supabase
              await _syncService.syncAll();
            } catch (syncError) {
              debugPrint(
                  '⚠️ Erreur lors de la synchronisation initiale des données: $syncError');
            }
            // 👆 FIN DE L'AJOUT

            _syncService.startRealtimeSync();
          } catch (e) {
            debugPrint('⚠️ Sync Error: $e');
          }

          if (!mounted) return;
          await _navigateAfterLogin(userId);
          return;
        }
      } on supabase_auth.AuthException catch (e) {
        if (e.message.contains('Invalid login credentials')) {
          _showSnackBar('Email ou mot de passe incorrect.', isError: true);
          setState(() => _isLoading = false);
          return;
        }
      }

      // 2. CONNEXION LOCALE (Hors ligne)
      final hash = _hashPassword(password);
      Utilisateur? localUser =
          await _dbHelper.getUtilisateurByEmailAndPassword(email, password);
      if (localUser == null) {
        try {
          localUser =
              await _dbHelper.getUtilisateurByEmailAndPasswordHash(email, hash);
        } catch (_) {}
      }

      if (localUser != null) {
        await SessionManager.setUserId(localUser.id!);
        await SessionManager.setUserRole(localUser.role ?? 'collaborator');
        if (!mounted) return;
        await _navigateAfterLogin(localUser.id!);
        return;
      }

      _showSnackBar("Identifiants incorrects.", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateAfterLogin(String userId) async {
    final db = await _dbHelper.database;
    final role = await SessionManager.getUserRole() ?? 'vendor';

    if (role == 'admin') {
      context.go('/admin');
      return;
    }

    // 🏢 Contrôle d'accès lié à l'entreprise rattachée.
    //
    // `verifierAccesUtilisateur` est fail-open : si la fonction SQL n'est pas
    // installée, si le réseau échoue ou si l'utilisateur n'est rattaché à
    // aucune entreprise, l'accès reste ouvert.
    final String? blocageEntreprise =
        await EntrepriseService.instance.verifierAccesUtilisateur(userId);

    if (blocageEntreprise != null) {
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Accès bloqué'),
          content: Text(blocageEntreprise),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await SupabaseService.instance.signOut();
                await SessionManager.clearSession();
              },
              child: const Text('Se déconnecter'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }

    final hasActiveSubscription = await isUserSubscribed(db, userId);

    if (hasActiveSubscription) {
      context.go('/subscription-expired');
    } else {
      if (role == 'vendor') {
        context.go('/main');
      } else {
        context.go('/main/new-sale');
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 900 : 450),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 25,
                      offset: const Offset(0, 12))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Row(
                  children: [
                    if (isWide) _buildBanner(colorScheme),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(isWide ? 40 : 25),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!isWide) ...[
                                Center(
                                    child: Image.asset(
                                        'assets/Biashara_app_off-.png',
                                        height: 70)),
                                const SizedBox(height: 20),
                              ],
                              const Text('Connexion',
                                  style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 35),
                              _buildTextField(_emailController, 'Email',
                                  Icons.alternate_email_rounded),
                              const SizedBox(height: 16),
                              _buildTextField(_passwordController,
                                  'Mot de passe', Icons.lock_outline_rounded,
                                  isPassword: true),
                              _buildForgotButton(colorScheme),
                              const SizedBox(height: 20),
                              _buildLoginButton(colorScheme),
                              const SizedBox(height: 24),
                              _buildFooter(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(ColorScheme colorScheme) {
    return Expanded(
      child: Container(
        height: 600,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.primary.withBlue(200)]),
        ),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset('assets/Biashara_app_off-.png', height: 100),
              const SizedBox(height: 30),
              const Text('Biashara Yangu',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Text('Gérez votre commerce avec simplicité.',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8), fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon,
      {bool isPassword = false}) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : false,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(_obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Champ requis' : null,
    );
  }

  Widget _buildForgotButton(ColorScheme colorScheme) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const PasswordRecoveryPage())),
        child: Text('Mot de passe oublié ?',
            style: TextStyle(
                color: colorScheme.primary, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildLoginButton(ColorScheme colorScheme) {
    return ElevatedButton(
      onPressed: _isLoading ? null : _signIn,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : const Text('SE CONNECTER',
              style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildFooter() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text("Pas encore de compte ?"),
        TextButton(
            onPressed: () => context.go('/setup'),
            child: const Text('S\'inscrire',
                style: TextStyle(fontWeight: FontWeight.bold))),
      ],
    );
  }
}
