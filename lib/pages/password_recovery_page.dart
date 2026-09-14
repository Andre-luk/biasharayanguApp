import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:go_router/go_router.dart';
import 'package:biashara_yangu/db_helper.dart';

class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage({super.key});

  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _adminKeyController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  Future<void> _handleRecovery() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final email = _emailController.text.trim().toLowerCase();
    final adminKey = _adminKeyController.text.trim();
    final hashedPass = _hashPassword(_newPasswordController.text.trim());

    // 💡 TEST : Clé fixe pour vos tests.
    // Plus tard, vous pourrez la charger depuis les paramètres de la boutique
    bool success = false;
    if (adminKey == "BIASHARA2026") {
      int result = await DBHelper.instance.updateUserPasswordOffline(email, hashedPass);
      success = result > 0;
    }

    setState(() => _isLoading = false);

    if (success) {
      if (!mounted) return;
      _showSuccessDialog();
    } else {
      _showError("Clé de sécurité incorrecte ou utilisateur introuvable.");
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Succès"),
        content: const Text("Le mot de passe a été réinitialisé avec succès."),
        actions: [
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text("RETOUR AU LOGIN"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Récupération de compte")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey, // Pas de 'const' ici car formKey est dynamique
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.shield_outlined, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                "Réinitialisation locale",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),

              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: "Email fictif",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => v!.isEmpty ? "Champ requis" : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _adminKeyController,
                decoration: const InputDecoration(
                  labelText: "Clé Admin (Test: BIASHARA2026)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
                validator: (v) => v!.isEmpty ? "Champ requis" : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: "Nouveau mot de passe",
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) => v!.length < 4 ? "Trop court" : null,
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isLoading ? null : _handleRecovery,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text("VALIDER LE CHANGEMENT"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}