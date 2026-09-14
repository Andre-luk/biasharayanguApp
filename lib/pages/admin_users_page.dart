// lib/pages/admin_users_page.dart
import 'package:flutter/material.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/pages/setup_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// utilitaires
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/utils/date_utils.dart'; // addMonths

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final SupabaseService _supabaseService = SupabaseService.instance;
  final supabase = Supabase.instance.client;

  List<Utilisateur> users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      users = await _supabaseService.getAllUtilisateurs();
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.message ?? e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de BDD: $msg')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur inconnue: ${e.toString()}')));
      }
    }
    setState(() => _loading = false);
  }

  // 1) Activation / Désactivation compte (valide)
  Future<void> _toggleAccountActivation(Utilisateur u) async {
    final newValidState = (u.valide == 1) ? 0 : 1;
    final action = newValidState == 0 ? 'Désactivé' : 'Activé';

    try {
      // update via Supabase (RLS: admin policy must allow this)
      await _supabaseService.client
          .from('utilisateurs')
          .update({'valide': newValidState})
          .eq('id', u.id?.toString() ?? '');

      // Si je désactive mon propre compte, déco
      final currentUserId = await SessionManager.getUserId();
      if (newValidState == 0 && u.id != null && u.id == currentUserId) {
        await SessionManager.clearSession();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Votre compte a été $action par un administrateur. Déconnexion...')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Compte de ${u.nom} $action.')),
          );
        }
        await _loadUsers();
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.message ?? e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de mise à jour: $msg')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString()}')));
      }
    }
  }

  // 2) Editer utilisateur
  Future<void> _editUser(Utilisateur u) async {
    final res = await Navigator.push<bool?>(
      context,
      MaterialPageRoute<bool?>(
        builder: (_) => SetupPage(editUser: u, adminCreating: true),
      ),
    );
    if (res == true) await _loadUsers();
  }

  Future<void> _createUser() async {
    final res = await Navigator.push<bool?>(
      context,
      MaterialPageRoute<bool?>(
        builder: (_) => const SetupPage(adminCreating: true),
      ),
    );
    if (res == true) await _loadUsers();
  }

  Future<void> _deleteUser(String userId) async {
    try {
      await _supabase_service_deleteUser(userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utilisateur et métadonnées supprimés')),
        );
      }
      await _loadUsers();
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.message ?? e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de BDD lors de la suppression: $msg')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString()}')));
      }
    }
  }

  // wrap real delete call so we keep code cleaner / testable
  Future<void> _supabase_service_deleteUser(String userId) async {
    await _supabase_service_deleteUser_impl(userId);
  }

  Future<void> _supabase_service_deleteUser_impl(String userId) async {
    await _supabaseService.client.from('utilisateurs').delete().eq('id', userId);
  }

  void _confirmDelete(Utilisateur u) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet utilisateur ?'),
        content: Text('Êtes-vous sûr de vouloir supprimer ${u.nom} de façon définitive ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (u.id != null) _deleteUser(u.id!);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // 3) ADMIN: Gérer abonnements
  // ---------------------------

  Future<List<Map<String, dynamic>>> _fetchSubscriptionsForUser(String userId) async {
    try {
      final raw = await supabase
          .from('subscriptions')
          .select()
          .eq('user_id', userId)
          .order('start_date', ascending: false);

      // raw should be a List<dynamic>
      final List<dynamic> data = raw is List ? raw : <dynamic>[];
      return data.map((e) {
        final mapE = e as Map<String, dynamic>;
        return Map<String, dynamic>.from(mapE);
      }).toList();
    } catch (e) {
      debugPrint('Erreur fetch subs: $e');
      return [];
    }
  }

  Future<void> _createSubscriptionForUser(String userId, String plan, int months, String adminId) async {
    final now = DateTime.now();
    final end = addMonths(now, months);
    try {
      final insertedRaw = await supabase.from('subscriptions').insert({
        'user_id': userId,
        'plan': plan,
        'period_months': months,
        'start_date': now.toIso8601String(),
        'end_date': end.toIso8601String(),
        'active': true,
        'activated_by': adminId,
        'activated_at': now.toIso8601String(),
      }).select();

      // insertedRaw can be List<dynamic> with one item
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abonnement créé avec succès.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur création abonnement: ${e.toString()}')));
      }
    }
  }

  Future<void> _updateSubscription(Map<String, dynamic> subUpdate, String subId) async {
    try {
      await supabase.from('subscriptions').update(subUpdate).eq('id', subId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abonnement mis à jour.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur MAJ abonnement: ${e.toString()}')));
      }
    }
  }

  Future<void> _deleteSubscription(String subId) async {
    try {
      await supabase.from('subscriptions').delete().eq('id', subId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abonnement supprimé.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur suppression abonnement: ${e.toString()}')));
      }
    }
  }

  // UI pour gérer un utilisateur (afficher liste d'abonnements + actions)
  void _manageUserSubscriptions(Utilisateur u) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchSubscriptionsForUser(u.id?.toString() ?? ''),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return SizedBox(height: 200, child: const Center(child: CircularProgressIndicator()));
          }
          final subs = snap.data ?? [];

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Wrap(
              children: [
                ListTile(
                  title: Text('Abonnements de ${u.fullName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${subs.length} enregistrements'),
                  trailing: TextButton.icon(
                    onPressed: () async {
                      // Créer un abonnement rapide: modal simple pour plan + mois
                      Navigator.pop(context);
                      await _showCreateSubscriptionDialog(u);
                      setState(() {}); // rafraîchir la liste générale si besoin
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter'),
                  ),
                ),
                const Divider(),
                if (subs.isEmpty)
                  const Padding(padding: EdgeInsets.all(16.0), child: Text('Aucun abonnement trouvé.'))
                else
                  ...subs.map((s) {
                    final id = (s['id']?.toString() ?? '');
                    final plan = (s['plan']?.toString() ?? '');
                    final active = s['active'] == true || s['active'] == 1;
                    final start = (s['start_date']?.toString() ?? '');
                    final end = (s['end_date']?.toString() ?? '');
                    final activatedBy = (s['activated_by']?.toString() ?? '');
                    return ListTile(
                      title: Text('$plan ${active ? "(Actif)" : "(Inactif)"}'),
                      subtitle: Text('Débute: $start\nExpire: $end\nActivé par: $activatedBy'),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (choice) async {
                          if (choice == 'deactivate') {
                            Navigator.pop(context);
                            await _updateSubscription({'active': false}, id);
                          } else if (choice == 'activate') {
                            Navigator.pop(context);
                            await _updateSubscription({'active': true}, id);
                          } else if (choice == 'edit') {
                            Navigator.pop(context);
                            await _showEditSubscriptionDialog(id, s);
                          } else if (choice == 'delete') {
                            Navigator.pop(context);
                            _confirmDeleteSubscription(id);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: active ? 'deactivate' : 'activate', child: Text(active ? 'Désactiver' : 'Activer')),
                          const PopupMenuItem(value: 'edit', child: Text('Éditer')),
                          const PopupMenuItem(value: 'delete', child: Text('Supprimer', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                  }).toList(),
                const SizedBox(height: 12),
                Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  // Dialog création rapide d'abonnement (plan + mois)
  Future<void> _showCreateSubscriptionDialog(Utilisateur u) async {
    final _planCtrl = TextEditingController(text: 'monthly_basic');
    final _monthsCtrl = TextEditingController(text: '1');
    final adminId = (await SessionManager.getUserId()) ?? '';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Créer abonnement pour ${u.fullName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _planCtrl, decoration: const InputDecoration(labelText: 'Plan')),
            TextField(controller: _monthsCtrl, decoration: const InputDecoration(labelText: 'Durée (mois)'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              final plan = _planCtrl.text.trim();
              final months = int.tryParse(_monthsCtrl.text.trim()) ?? 1;
              Navigator.pop(ctx);
              if (u.id != null) await _createSubscriptionForUser(u.id!, plan, months, adminId);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  // Dialog édition d'abonnement (modifie plan / dates / period)
  Future<void> _showEditSubscriptionDialog(String subId, Map<String, dynamic> sub) async {
    final _planCtrl = TextEditingController(text: sub['plan']?.toString() ?? '');
    final _monthsCtrl = TextEditingController(text: (sub['period_months']?.toString() ?? '1'));
    final _startCtrl = TextEditingController(text: sub['start_date']?.toString() ?? '');
    final _endCtrl = TextEditingController(text: sub['end_date']?.toString() ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Éditer abonnement'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _planCtrl, decoration: const InputDecoration(labelText: 'Plan')),
              TextField(controller: _monthsCtrl, decoration: const InputDecoration(labelText: 'Durée (mois)'), keyboardType: TextInputType.number),
              TextField(controller: _startCtrl, decoration: const InputDecoration(labelText: 'Start ISO (optionnel)')),
              TextField(controller: _endCtrl, decoration: const InputDecoration(labelText: 'End ISO (optionnel)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              final plan = _planCtrl.text.trim();
              final months = int.tryParse(_monthsCtrl.text.trim()) ?? (sub['period_months'] ?? 1) as int;
              final Map<String, dynamic> update = {
                'plan': plan,
                'period_months': months,
              };
              if (_startCtrl.text.isNotEmpty) update['start_date'] = _startCtrl.text.trim();
              if (_endCtrl.text.isNotEmpty) update['end_date'] = _endCtrl.text.trim();
              Navigator.pop(ctx);
              await _updateSubscription(update, subId);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSubscription(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet abonnement ?'),
        content: const Text('Cette opération est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteSubscription(id);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // Build UI
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        children: [
          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(onPressed: _createUser, icon: const Icon(Icons.person_add), label: const Text('Ajouter un utilisateur')),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers, tooltip: 'Rafraîchir'),
              ],
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (users.isEmpty
                ? const Center(child: Text("Aucun utilisateur trouvé."))
                : ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final u = users[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: u.valide == 1 ? Colors.blueAccent : Colors.grey,
                    child: Text(u.nom.isNotEmpty ? u.nom[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(u.nom, style: TextStyle(fontWeight: FontWeight.bold, color: u.valide == 0 ? Colors.grey : Colors.black)),
                  subtitle: Text('${u.email ?? ''} • ${u.role ?? ''}\nStatut: ${u.valide == 1 ? 'Activé' : 'Désactivé'}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showAdminActions(context, u),
                  ),
                );
              },
            )),
          ),
        ],
      ),
    );
  }

  // Menu d'actions (attach manage subscriptions)
  void _showAdminActions(BuildContext context, Utilisateur user) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Actions pour ${user.nom}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_note, color: Colors.blue),
                title: const Text('Modifier le profil et le rôle'),
                subtitle: Text('Rôle actuel: ${user.role ?? ''}'),
                onTap: () {
                  Navigator.pop(context);
                  _editUser(user);
                },
              ),
              ListTile(
                leading: Icon(user.valide == 1 ? Icons.block : Icons.check_circle_outline, color: user.valide == 1 ? Colors.red : Colors.green),
                title: Text(user.valide == 1 ? 'Désactiver le compte' : 'Activer le compte'),
                subtitle: Text(user.valide == 1 ? 'L\'utilisateur ne pourra plus se connecter.' : 'L\'utilisateur pourra se connecter.'),
                onTap: () {
                  Navigator.pop(context);
                  _toggleAccountActivation(user);
                },
              ),
              ListTile(
                leading: const Icon(Icons.subscriptions, color: Colors.orange),
                title: const Text('Gérer les abonnements'),
                subtitle: const Text('Voir / créer / modifier les abonnements'),
                onTap: () {
                  Navigator.pop(context);
                  _manageUserSubscriptions(user);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.grey),
                title: const Text('Supprimer le compte', style: TextStyle(color: Colors.grey)),
                subtitle: const Text('Suppression définitive de l\'utilisateur et de ses données.'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(user);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
