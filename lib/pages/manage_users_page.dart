// lib/pages/manage_users_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

class ManageUsersPage extends StatefulWidget {
  const ManageUsersPage({super.key});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
  List<Utilisateur> _collaborateurs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCollaborateurs();
  }

  Future<void> _loadCollaborateurs() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final patronId = await SessionManager.getUserId();
      if (patronId == null) return;

      final localList = await DBHelper.instance.getCollaborateurs(patronId);
      if (mounted) {
        setState(() {
          _collaborateurs = localList;
          _loading = false;
        });
      }

      try {
        final cloudList = await SupabaseService.instance.getCollaborateursByPatron(patronId);
        if (cloudList.isNotEmpty) {
          for (var user in cloudList) {
            try {
              // Optionnel : mettre à jour DB locale (si tu as upsert)
              // await DBHelper.instance.insertOrUpdateUtilisateur(user);
            } catch (e) {
              debugPrint("Erreur de mise à jour locale de l'utilisateur: $e");
            }
          }

          if (mounted) {
            setState(() {
              _collaborateurs = cloudList;
            });
          }
        }
      } catch (e) {
        debugPrint("Mode hors-ligne : impossible de rafraîchir depuis le Cloud ($e)");
      }
    } catch (e) {
      debugPrint("Erreur globale chargement collaborateurs: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteUser(Utilisateur user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Supprimer ${user.nom} ?"),
        content: const Text("Ce vendeur perdra l'accès à la boutique immédiatement."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // 🔥 CORRECTION ICI : On utilise le RPC (la fonction Admin sur Supabase)
        // au lieu de SupabaseService.instance.deleteUtilisateur(user.id!);
        await SupabaseService.instance.client.rpc('delete_collaborateur', params: {
          'target_user_id': user.id,
        });

        // Si on arrive ici, le Cloud a bien supprimé l'utilisateur
        await DBHelper.instance.deleteUtilisateurById(user.id!);
        await _loadCollaborateurs();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${user.nom} supprimé de votre boutique")),
          );
        }
      } catch (e) {
        debugPrint("Erreur suppression cloud: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            // J'ai ajouté l'affichage de l'erreur (e) pour vous aider à débugger
            // si vous n'avez pas encore créé la fonction SQL sur Supabase
            SnackBar(content: Text("Erreur de suppression : $e")),
          );
        }
      }
    }
  }

  void _showInviteCodeDialog(String patronId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Inviter un vendeur"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Demandez à votre collaborateur de télécharger l'application et de créer son compte."),
            const SizedBox(height: 12),
            const Text("Il devra entrer ce Code Boutique :", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                patronId,
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: patronId));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Code copié !")),
              );
            },
            child: const Text("Copier"),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mon Équipe"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: "Stats Collaborateurs",
            onPressed: () async {
              final patronId = await SessionManager.getUserId();
              if (patronId != null) {
                context.goNamed('collaborateurs-stats', extra: patronId);
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCollaborateurs,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _collaborateurs.isEmpty
            ? _buildEmptyState()
            : ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: _collaborateurs.length,
          itemBuilder: (context, index) {
            final user = _collaborateurs[index];
            return _buildUserCard(user, theme);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final patronId = await SessionManager.getUserId();
          if (patronId != null && mounted) {
            _showInviteCodeDialog(patronId);
          }
        },
        label: const Text("Inviter Vendeur"),
        icon: const Icon(Icons.share),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              "Vous travaillez seul pour l'instant",
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text("Invitez des vendeurs pour déléguer la caisse."),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(Utilisateur user, ThemeData theme) {
    final initials = user.nom.isNotEmpty ? user.nom[0].toUpperCase() : "?";

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(initials,
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
        ),
        title: Text(user.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(user.email),
        trailing: IconButton(
          icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
          onPressed: () => _deleteUser(user),
        ),
      ),
    );
  }
}