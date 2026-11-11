// lib/pages/clients_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/client.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final DBHelper _db = DBHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Client> _allClients = [];
  List<Client> _filteredClients = [];
  bool _loading = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    _currentUserId = await SessionManager.getUserId();
    if (_currentUserId == null) {
      if (mounted) context.go('/login');
      return;
    }
    // 🧩 MODULE 15 — les clients sont ceux de la boutique affichée.
    _currentUserId =
        await _db.ownerDonneesDe(_currentUserId!) ?? _currentUserId;
    await _reloadClients();
  }

  Future<void> _reloadClients() async {
    try {
      final data = await _db.getClients(ownerId: _currentUserId);
      if (mounted) {
        setState(() {
          _allClients = data;
          _filteredClients = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur de chargement: $e")),
        );
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredClients = _allClients.where((c) {
        return c.nom.toLowerCase().contains(query) ||
            (c.telephone?.contains(query) ?? false) ||
            (c.email?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  // --- FORMULAIRE (AJOUT / MODIFICATION) ---

  void _showClientForm({Client? client}) {
    final isEditing = client != null;
    final nomController = TextEditingController(text: client?.nom);
    final phoneController = TextEditingController(text: client?.telephone);
    final emailController = TextEditingController(text: client?.email);
    final adresseController = TextEditingController(text: client?.adresse);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20, right: 20, top: 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEditing ? "Modifier le client" : "Nouveau Client",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nomController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: "Nom complet *",
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: "Téléphone",
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: "Email (Facultatif)",
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: adresseController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: "Adresse / Détails",
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  final nom = nomController.text.trim();
                  if (nom.isEmpty) return;

                  // Transformation des champs vides en null pour la propreté SQL
                  final newClient = Client(
                    id: client?.id,
                    ownerId: _currentUserId!,
                    nom: nom,
                    telephone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                    email: emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                    adresse: adresseController.text.trim().isEmpty ? null : adresseController.text.trim(),
                    isSynced: 0,
                    supabaseId: client?.supabaseId,
                  );

                  if (isEditing) {
                    await _db.updateClient(newClient);
                  } else {
                    await _db.insertClient(newClient);
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    _reloadClients();
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(isEditing ? "Mettre à jour" : "Enregistrer"),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mes Clients", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: _reloadClients,
            icon: const Icon(Icons.refresh),
            tooltip: "Actualiser",
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showClientForm(),
        icon: const Icon(Icons.person_add),
        label: const Text("Nouveau"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Rechercher par nom, numéro ou email...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredClients.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
              onRefresh: _reloadClients,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: _filteredClients.length,
                itemBuilder: (context, index) {
                  final c = _filteredClients[index];
                  return _buildClientTile(c, theme);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientTile(Client c, ThemeData theme) {
    final Color avatarColor = Colors.primaries[c.nom.length % Colors.primaries.length];

    // Construction du sous-titre dynamique
    String subtitle = c.telephone ?? "";
    if (c.email != null) {
      subtitle += (subtitle.isEmpty ? "" : " • ") + c.email!;
    }
    if (subtitle.isEmpty) subtitle = "Aucune coordonnée";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: ListTile(
        onTap: () => _showClientForm(client: c),
        leading: CircleAvatar(
          backgroundColor: avatarColor.withOpacity(0.15),
          child: Text(
            c.nom.isNotEmpty ? c.nom[0].toUpperCase() : "?",
            style: TextStyle(color: avatarColor, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(c.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              c.isSynced == 1 ? Icons.cloud_done : Icons.cloud_upload,
              size: 16,
              color: c.isSynced == 1 ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? "Votre liste de clients est vide"
                  : "Aucun résultat pour cette recherche",
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}