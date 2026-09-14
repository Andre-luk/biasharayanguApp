import 'package:flutter/material.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChangePasswordPage extends StatefulWidget {
  final bool isNewUser; // Si true, c'est pour définir un mot de passe initial
  final String? userEmail; // Email du nouvel utilisateur (pour setup admin)

  const ChangePasswordPage({super.key, this.isNewUser = false, this.userEmail});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final SupabaseService _supabaseService = SupabaseService.instance;
  bool _isLoading = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final oldPassword = _oldPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();

    // Correction: utiliser auth.currentUser pour récupérer l'email de l'utilisateur connecté
    final email = widget.isNewUser
        ? widget.userEmail
        : _supabaseService.auth.currentUser?.email;

    if (email == null || email.isEmpty) {
      _showSnackBar("Impossible de récupérer l'email de l'utilisateur.", isError: true);
      setState(() => _isLoading = false);
      return;
    }

    try {
      if (!widget.isNewUser) {
        // 1. Vérification de l'ancien mot de passe via re-login
        await _supabaseService.auth.signInWithPassword(
          email: email,
          password: oldPassword,
        );
      }

      // 2. Mise à jour du mot de passe
      await _supabaseService.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      _showSnackBar(
        widget.isNewUser
            ? "Mot de passe initial défini avec succès!"
            : "Mot de passe mis à jour avec succès!",
      );

      if (mounted) Navigator.of(context).pop(true);

    } on AuthException catch (e) {
      String errorMessage = "Erreur d'authentification.";

      if (!widget.isNewUser && e.message.contains('Invalid login credentials')) {
        errorMessage = "Ancien mot de passe incorrect.";
      } else if (e.message.contains('Password should be at least')) {
        errorMessage = "Le nouveau mot de passe est trop court.";
      } else {
        errorMessage = "Erreur lors de la mise à jour: ${e.message}";
      }

      _showSnackBar(errorMessage, isError: true);
    } catch (e) {
      _showSnackBar("Erreur inattendue: ${e.toString()}", isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.isNewUser;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? "Définir Mot de Passe Initial" : "Changer le Mot de Passe"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isNew)
                const Text(
                  "Pour des raisons de sécurité, veuillez confirmer votre ancien mot de passe.",
                  style: TextStyle(color: Colors.black54),
                ),
              if (!isNew) const SizedBox(height: 20),

              if (!isNew)
                TextFormField(
                  controller: _oldPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Ancien Mot de Passe",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer votre ancien mot de passe.';
                    }
                    return null;
                  },
                ),
              if (!isNew) const SizedBox(height: 16),

              TextFormField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Nouveau Mot de Passe",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Le mot de passe doit contenir au moins 6 caractères.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Confirmer Nouveau Mot de Passe",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.check_circle_outline),
                ),
                validator: (value) {
                  if (value != _newPasswordController.text) {
                    return 'Les mots de passe ne correspondent pas.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),

              ElevatedButton.icon(
                onPressed: _isLoading ? null : _changePassword,
                icon: _isLoading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.vpn_key),
                label: Text(
                  _isLoading
                      ? "Mise à jour..."
                      : (isNew ? "Définir Mot de Passe Initial" : "Mettre à Jour le Mot de Passe"),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
