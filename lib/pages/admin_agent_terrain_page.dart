// lib/pages/admin_agent_terrain_page.dart
//
// 🧑‍🌾 MODULE 21 — CRÉATION D'UN COMPTE « AGENT TERRAIN ».
//
// L'agent terrain est le collaborateur de la plateforme qui va sur le
// terrain : il CRÉE l'entreprise du commerçant, VÉRIFIE son dossier,
// l'ACTIVE et VALIDE les paiements reçus — sans être Super Admin.
//
// ⚠️ Le mot de passe est envoyé à la base qui le hache elle-même (bcrypt).
//    Contrairement à une inscription classique, la session de
//    l'administrateur n'est JAMAIS remplacée : il n'est pas déconnecté et le
//    nouvel agent n'est pas connecté à sa place.

import 'dart:math';

import 'package:flutter/material.dart';

import 'package:biashara_yangu/services/admin_plateforme_service.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/permission_service.dart';

class AdminAgentTerrainPage extends StatefulWidget {
  const AdminAgentTerrainPage({super.key});

  @override
  State<AdminAgentTerrainPage> createState() => _AdminAgentTerrainPageState();
}

class _AdminAgentTerrainPageState extends State<AdminAgentTerrainPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nom = TextEditingController();
  final TextEditingController _prenom = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _motDePasse = TextEditingController();
  final TextEditingController _note = TextEditingController();

  bool _motDePasseVisible = false;
  bool _enCours = false;

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _email.dispose();
    _motDePasse.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Mot de passe provisoire lisible : syllabes + chiffres (l'agent devra le
  /// changer, mais il doit pouvoir le dicter au téléphone).
  String _genererMotDePasse() {
    const String lettres = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const String minuscules = 'abcdefghijkmnpqrstuvwxyz';
    const String chiffres = '23456789';
    final Random hasard = Random.secure();
    final StringBuffer tampon = StringBuffer('By-');
    for (int i = 0; i < 4; i++) {
      tampon.write(lettres[hasard.nextInt(lettres.length)]);
    }
    for (int i = 0; i < 4; i++) {
      tampon.write(minuscules[hasard.nextInt(minuscules.length)]);
    }
    for (int i = 0; i < 2; i++) {
      tampon.write(chiffres[hasard.nextInt(chiffres.length)]);
    }
    return tampon.toString();
  }

  Future<void> _creer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _enCours = true);

    try {
      final Map<String, dynamic> resultat =
          await AdminPlateformeService.instance.creerAgentTerrain(
        email: _email.text,
        motDePasse: _motDePasse.text,
        nom: _nom.text,
        prenom: _prenom.text,
        note: _note.text,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Agent terrain créé'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Transmettez ces identifiants à l\'agent. Le mot de passe '
                  'ne pourra plus être relu depuis l\'application.',
                ),
                const SizedBox(height: 12),
                SelectableText('Adresse : ${resultat['email'] ?? _email.text}'),
                const SizedBox(height: 4),
                SelectableText('Mot de passe : ${_motDePasse.text}'),
                const SizedBox(height: 12),
                if (resultat['compte_reutilise'] == true)
                  Text(
                    'Un compte existait déjà avec cette adresse : son mot de '
                    'passe a été mis à jour et son rôle aligné sur celui '
                    'd\'un agent terrain.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AdminPlateformeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Création impossible : $e'),
        backgroundColor: Colors.red.shade700,
      ));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool autorise = PermissionService.instance.estSuperAdmin ||
        PermissionService.instance
            .peut(PageAccess.utilisateurs, ActionAccess.creer);

    if (!autorise) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Seul le Super Admin (ou le gestionnaire des comptes) peut '
              'créer un agent terrain.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvel agent terrain')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.badge_outlined,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'Ce que l\'agent terrain pourra faire',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('• créer une entreprise et son compte ;'),
                    const Text('• vérifier et valider son dossier d\'activation ;'),
                    const Text('• activer le compte et valider les paiements ;'),
                    const Text('• consulter le parc des boutiques.'),
                    const SizedBox(height: 8),
                    Text(
                      'Il n\'a pas accès aux permissions, aux référentiels '
                      'sensibles ni aux devises : ces écrans restent réservés '
                      'au Super Admin.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _prenom,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Prénom',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (String? v) =>
                  (v ?? '').trim().isEmpty ? 'Prénom obligatoire.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nom,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              validator: (String? v) =>
                  (v ?? '').trim().isEmpty ? 'Nom obligatoire.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Adresse e-mail (identifiant de connexion)',
                prefixIcon: Icon(Icons.alternate_email),
                border: OutlineInputBorder(),
              ),
              validator: (String? v) {
                final String email = (v ?? '').trim();
                if (email.isEmpty) return 'Adresse e-mail obligatoire.';
                final RegExp motif = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                return motif.hasMatch(email)
                    ? null
                    : 'Adresse e-mail invalide.';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _motDePasse,
              obscureText: !_motDePasseVisible,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Mot de passe (8 caractères minimum)',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Générer un mot de passe',
                      icon: const Icon(Icons.casino_outlined),
                      onPressed: () => setState(() {
                        _motDePasse.text = _genererMotDePasse();
                        _motDePasseVisible = true;
                      }),
                    ),
                    IconButton(
                      tooltip: _motDePasseVisible
                          ? 'Masquer'
                          : 'Afficher le mot de passe',
                      icon: Icon(_motDePasseVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(
                          () => _motDePasseVisible = !_motDePasseVisible),
                    ),
                  ],
                ),
              ),
              validator: (String? v) {
                final String mdp = v ?? '';
                if (mdp.length < 8) {
                  return 'Au moins 8 caractères.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note interne (optionnel)',
                hintText: 'Ex. : agent affecté à Kinshasa / Limete',
                prefixIcon: Icon(Icons.notes_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _enCours ? null : _creer,
              icon: _enCours
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1),
              label: Text(
                  _enCours ? 'Création en cours…' : 'Créer le compte agent'),
            ),
            const SizedBox(height: 8),
            Text(
              'Le mot de passe est haché par la base de données. Votre propre '
              'session n\'est pas modifiée.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}
