import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart'; // Ajouté pour une meilleure navigation si nécessaire
import 'package:supabase_flutter/supabase_flutter.dart'; // Import pour la gestion des exceptions
// 🔑 Remplacement de DBHelper par SupabaseService
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/models/client.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart'; // Pour l'internationalisation

class AddClientPage extends StatefulWidget {
  const AddClientPage({super.key});

  @override
  State<AddClientPage> createState() => _AddClientPageState();
}

class _AddClientPageState extends State<AddClientPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _telController = TextEditingController();
  final _emailController = TextEditingController();
  bool _saving = false;

  // 🔑 Instance du service Supabase
  final SupabaseService _supabaseService = SupabaseService.instance;

  @override
  void dispose() {
    _nomController.dispose();
    _telController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final T = AppLocalizations.of(context)!;

    // 🔑 L'ID utilisateur est un String (UUID)
    final ownerId = await SessionManager.getUserId();

    if (ownerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(T.errorUserNotLoggedIn)));
        setState(() => _saving = false);
      }
      return;
    }

    try {
      // 🔑 CRÉATION DU CLIENT (sans ID, car la BDD Supabase l'ajoutera)
      final clientData = {
        'nom': _nomController.text.trim(),
        'telephone': _telController.text.trim(),
        'email': _emailController.text.trim(),
        'owner_id': ownerId, // UUID String
      };

      // 🔑 Utilisation du SupabaseService pour insérer dans la table 'clients'
      // NOTE : Cette méthode suppose que 'insertClient' existe dans SupabaseService
      // ou que vous insérez directement via client.from('clients').insert(...)
      await _supabaseService.client
          .from('clients')
          .insert(clientData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(T.clientAddedSuccess)));
      // Retourne true pour indiquer qu'une action a été effectuée
      Navigator.pop(context, true);

    } on PostgrestException catch (e) {
      if (!mounted) return;
      print('Erreur Supabase lors de l\'ajout du client: ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${T.errorSavingClient}: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      print('Erreur inattendue: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(T.errorSavingClientGeneric)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(T.clientNewTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nomController,
                decoration: InputDecoration(labelText: T.fieldName),
                validator: (v) => v == null || v.trim().isEmpty ? T.validationNameRequired : null,
              ),
              TextFormField(
                controller: _telController,
                decoration: InputDecoration(labelText: T.fieldPhone),
                keyboardType: TextInputType.phone,
              ),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: T.fieldEmail),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v != null && v.isNotEmpty && !v.contains('@')) {
                    return T.validationEmailInvalid;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(T.buttonSaveClient),
              ),
            ],
          ),
        ),
      ),
    );
  }
}