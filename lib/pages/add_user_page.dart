import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

class AddUserPage extends StatefulWidget {
  const AddUserPage({super.key});

  @override
  State<AddUserPage> createState() => _AddUserPageState();
}

class _AddUserPageState extends State<AddUserPage> {
  final _nomController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSaving = false;
  bool _obscureText = true;

  /// Hash simple SHA256 du mot de passe
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _saveUser() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final nom = _nomController.text.trim();

    if (nom.isEmpty) {
      _showError("Veuillez saisir un nom.");
      return;
    }
    if (password.length < 4) {
      _showError("Le mot de passe doit contenir au moins 4 caractères.");
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Récupère l'ID du patron (session locale)
      final patronId = await SessionManager.getUserId();
      if (patronId == null) throw Exception("Session patron introuvable.");

      // Génère un id local (UUID)
      final id = const Uuid().v4();

      // Hash du mot de passe
      final pwdHash = _hashPassword(password);

      final collaborateur = Utilisateur(
        id: id,
        nom: nom,
        email: email,
        role: 'vendor',
        valide: 1,
        parentId: patronId,
        passwordHash: pwdHash, // Assure-toi que ton modèle Utilisateur a ce champ
      );

      final supabase = Supabase.instance.client;

      // ----------------- SUPABASE UPSERT -----------------
      final upsertMap = collaborateur.toMap();
      upsertMap.removeWhere((k, v) => v == null);

      try {
        // Upsert Supabase avec "id" comme clé unique
        final response = await supabase
            .from('utilisateurs')
            .upsert(upsertMap, onConflict: 'id')
            .select(); // récupère le résultat après l'upsert

        debugPrint('Supabase upsert result: $response');
      } catch (e) {
        debugPrint('Erreur Supabase upsert: $e');
      }

      // ----------------- SAUVEGARDE LOCALE -----------------
      await DBHelper.instance.insertUtilisateur(collaborateur);

      if (mounted) {
        _showSuccess("Collaborateur créé avec succès.");
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showError("Erreur lors de la création : $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red),
  );

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ajouter un collaborateur")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.person_add_alt_1, size: 80, color: Colors.blue),
            const SizedBox(height: 10),
            const Text(
              "Nouveau collaborateur (accès caisse uniquement)",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nomController,
              decoration: InputDecoration(
                labelText: "Nom complet",
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: "Email (optionnel mais recommandé)",
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscureText,
              decoration: InputDecoration(
                labelText: "PIN / Mot de passe",
                helperText: "4+ caractères. Conserver confidentiel.",
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureText ? Icons.visibility_off : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscureText = !_obscureText),
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            _isSaving
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
              onPressed: _saveUser,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Créer le collaborateur",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Le collaborateur pourra vendre depuis son appareil en utilisant l'email (ou l'ID) et le PIN que vous lui donnez.",
              style: TextStyle(fontSize: 13, color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }
}
