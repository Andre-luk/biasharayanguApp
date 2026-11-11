// lib/pages/manage_users_page.dart
//
//  MON ÉQUIPE — le propriétaire CRÉE lui-même les comptes de ses
//  collaborateurs, avec leur rôle, rattachés à SON entreprise.
//
//  ⚠️ Plus de « code boutique » ni de code d'invitation : le patron saisit
//  nom, prénom, e-mail, téléphone, mot de passe et rôle → le serveur crée le
//  compte Auth et le rattache à l'entreprise (migration 0140). Même principe
//  que la Distribution et le Pressing, mais valable pour TOUS les modules.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/collaborateur_entreprise.dart';
import 'package:biashara_yangu/models/espace.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/equipe_service.dart';
import 'package:biashara_yangu/services/espace_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

class ManageUsersPage extends StatefulWidget {
  const ManageUsersPage({super.key});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
  List<CollaborateurEntreprise> _collaborateurs =
      const <CollaborateurEntreprise>[];
  bool _loading = true;
  String? _erreur;

  /// 🧩 MODULE 15 — boutiques du compte (sélecteur de la fiche collaborateur).
  List<Espace> _espaces = const <Espace>[];

  @override
  void initState() {
    super.initState();
    _chargerEspaces();
    _loadCollaborateurs();
  }

  /// Les boutiques servent seulement à AFFECTER un collaborateur : si la
  /// liste ne charge pas, l'écran reste utilisable (boutique par défaut).
  Future<void> _chargerEspaces() async {
    try {
      final EtatEspaces etat = await EspaceService.instance.charger();
      if (!mounted) return;
      setState(() => _espaces = etat.espaces);
    } catch (e) {
      debugPrint('ManageUsersPage: boutiques indisponibles ($e)');
    }
  }

  /// Source de vérité = le serveur (le propriétaire et ses collaborateurs).
  /// Une erreur est AFFICHÉE : un silence donnerait l'impression d'une équipe
  /// vide alors qu'un droit ou le réseau a échoué.
  Future<void> _loadCollaborateurs() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _erreur = null;
    });

    try {
      final List<CollaborateurEntreprise> liste =
          await EquipeService.instance.collaborateurs();
      if (!mounted) return;
      setState(() {
        _collaborateurs = liste;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _erreur =
            e is EquipeException ? e.message : 'Chargement impossible : $e';
      });
    }
  }

  void _snack(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? AppCouleurs.danger : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  CRÉATION D'UN COMPTE (sans code d'invitation)
  // ---------------------------------------------------------------------------
  Future<void> _nouveauCollaborateur() async {
    final _FormulaireCollaborateur? saisie =
        await showDialog<_FormulaireCollaborateur>(
      context: context,
      builder: (BuildContext ctx) => _DialogueCollaborateur(
        espaces: _espaces,
        espaceInitial: EspaceService.instance.actif?.id,
      ),
    );
    if (saisie == null) return;

    try {
      await EquipeService.instance.creer(
        nom: saisie.nom,
        prenom: saisie.prenom,
        email: saisie.email,
        telephone: saisie.telephone,
        motDePasse: saisie.motDePasse,
        role: saisie.role,
        espaceId: saisie.espaceId,
      );
      _snack(
        'Compte de ${saisie.nom} créé : il peut se connecter dès maintenant.',
      );
      await _loadCollaborateurs();
    } catch (e) {
      _snack(
        e is EquipeException ? e.message : 'Création impossible : $e',
        erreur: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  //  MODIFICATION (rôle, état, mot de passe)
  // ---------------------------------------------------------------------------
  Future<void> _modifier(CollaborateurEntreprise c) async {
    final _FormulaireCollaborateur? saisie =
        await showDialog<_FormulaireCollaborateur>(
      context: context,
      builder: (BuildContext ctx) => _DialogueCollaborateur(
        existant: c,
        espaces: _espaces,
        espaceInitial: c.espaceId,
      ),
    );
    if (saisie == null) return;

    try {
      await EquipeService.instance.maj(
        id: c.id,
        nom: saisie.nom,
        prenom: saisie.prenom,
        telephone: saisie.telephone,
        role: saisie.role,
        actif: saisie.actif,
        motDePasse: saisie.motDePasse,
        espaceId: saisie.espaceId,
      );
      _snack('${c.nomComplet} mis à jour.');
      await _loadCollaborateurs();
    } catch (e) {
      _snack(
        e is EquipeException ? e.message : 'Modification impossible : $e',
        erreur: true,
      );
    }
  }

  Future<void> _deleteUser(CollaborateurEntreprise user) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Supprimer ${user.nomComplet} ?'),
        content: const Text(
          'Ce collaborateur perdra l\'accès à l\'entreprise immédiatement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await SupabaseService.instance.client.rpc(
        'delete_collaborateur',
        params: <String, dynamic>{'target_user_id': user.id},
      );
      _snack('${user.nomComplet} supprimé de votre entreprise.');
      await _loadCollaborateurs();
    } catch (e) {
      _snack('Suppression impossible : $e', erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Équipe'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: _loadCollaborateurs,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Stats collaborateurs',
            onPressed: () async {
              final String? patronId = await SessionManager.getUserId();
              if (patronId != null && mounted) {
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
            : _erreur != null
                ? _buildErreur()
                : _collaborateurs.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        itemCount: _collaborateurs.length,
                        itemBuilder: (BuildContext context, int index) =>
                            _buildUserCard(_collaborateurs[index], theme),
                      ),
      ),
      // 🔐 Créer un compte = permission « créer » sur les collaborateurs.
      floatingActionButton: PermissionGate(
        page: PageAccess.collaborateurs,
        action: ActionAccess.creer,
        child: FloatingActionButton.extended(
          onPressed: _nouveauCollaborateur,
          label: const Text('Nouveau collaborateur'),
          icon: const Icon(Icons.person_add_alt_1),
        ),
      ),
    );
  }

  Widget _buildErreur() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 64,
              color: AppCouleurs.danger,
            ),
            const SizedBox(height: 16),
            const Text(
              'Impossible de charger votre équipe',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_erreur!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadCollaborateurs,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              "Vous travaillez seul pour l'instant",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Créez le compte d'un collaborateur : il se connectera avec "
              "l'e-mail et le mot de passe que vous choisissez, sans code "
              "d'invitation.",
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(CollaborateurEntreprise user, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: user.actif
              ? theme.colorScheme.primaryContainer
              : Colors.grey.shade300,
          child: Text(
            user.initiales,
            style: TextStyle(
              color: user.actif
                  ? theme.colorScheme.onPrimaryContainer
                  : Colors.grey.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          user.nomComplet,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _etiquette(user.libelleRoleCourt, AppCouleurs.info),
                // 🧩 MODULE 15 — la boutique où il travaille (si plusieurs).
                if (user.espaceNom.trim().isNotEmpty)
                  _etiquette(user.espaceNom, AppCouleurs.succes),
                if (!user.actif) _etiquette('Désactivé', AppCouleurs.danger),
                if (user.telephone.isNotEmpty)
                  _etiquette(user.telephone, Colors.grey.shade600),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Actions',
          onSelected: (String action) {
            if (action == 'modifier') _modifier(user);
            if (action == 'supprimer') _deleteUser(user);
          },
          itemBuilder: (BuildContext ctx) => const [
            PopupMenuItem<String>(
              value: 'modifier',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_outlined),
                title: Text('Modifier / rôle'),
              ),
            ),
            PopupMenuItem<String>(
              value: 'supprimer',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.person_remove_outlined,
                  color: Colors.redAccent,
                ),
                title: Text(
                  'Supprimer',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _etiquette(String texte, Color couleur) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: couleur.withValues(alpha: 0.4)),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontSize: 11,
          color: couleur,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// =============================================================================
//  FORMULAIRE — création et modification d'un collaborateur
// =============================================================================

class _FormulaireCollaborateur {
  final String nom;
  final String prenom;
  final String email;
  final String telephone;
  final String motDePasse;
  final String role;
  final bool actif;

  /// 🧩 MODULE 15 — boutique d'affectation (`null` = boutique par défaut).
  final String? espaceId;

  const _FormulaireCollaborateur({
    required this.nom,
    required this.prenom,
    required this.email,
    required this.telephone,
    required this.motDePasse,
    required this.role,
    this.actif = true,
    this.espaceId,
  });
}

class _DialogueCollaborateur extends StatefulWidget {
  final CollaborateurEntreprise? existant;

  /// Boutiques du compte : le sélecteur n'apparaît qu'à partir de deux.
  final List<Espace> espaces;

  /// Boutique proposée par défaut.
  final String? espaceInitial;

  const _DialogueCollaborateur({
    this.existant,
    this.espaces = const <Espace>[],
    this.espaceInitial,
  });

  @override
  State<_DialogueCollaborateur> createState() => _DialogueCollaborateurState();
}

class _DialogueCollaborateurState extends State<_DialogueCollaborateur> {
  final GlobalKey<FormState> _cle = GlobalKey<FormState>();
  late final TextEditingController _nom;
  late final TextEditingController _prenom;
  late final TextEditingController _email;
  late final TextEditingController _telephone;
  final TextEditingController _motDePasse = TextEditingController();

  late String _role;
  late bool _actif;
  String? _espaceId;
  bool _voirMotDePasse = false;

  bool get _edition => widget.existant != null;
  bool get _choixBoutique => widget.espaces.length > 1;

  @override
  void initState() {
    super.initState();
    final CollaborateurEntreprise? c = widget.existant;
    _nom = TextEditingController(text: c?.nom ?? '');
    _prenom = TextEditingController(text: c?.prenom ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _telephone = TextEditingController(text: c?.telephone ?? '');
    _actif = c?.actif ?? true;
    _espaceId = c != null ? c.espaceId : widget.espaceInitial;
    final String role = c?.role ?? 'VENDEUR';
    _role = kRolesCollaborateur.any(
      (({String code, String libelle}) r) => r.code == role,
    )
        ? role
        : 'VENDEUR';
  }

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _email.dispose();
    _telephone.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  void _valider() {
    if (!_cle.currentState!.validate()) return;
    Navigator.pop(
      context,
      _FormulaireCollaborateur(
        nom: _nom.text.trim(),
        prenom: _prenom.text.trim(),
        email: _email.text.trim().toLowerCase(),
        telephone: _telephone.text.trim(),
        motDePasse: _motDePasse.text.trim(),
        role: _role,
        actif: _actif,
        espaceId: _espaceId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _edition ? 'Modifier le collaborateur' : 'Nouveau collaborateur',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _cle,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _prenom,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Prénom',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nom,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nom *',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (String? v) => (v == null || v.trim().isEmpty)
                      ? 'Indiquez le nom du collaborateur'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_edition,
                  decoration: const InputDecoration(
                    labelText: 'E-mail (identifiant de connexion) *',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (String? v) {
                    final String t = (v ?? '').trim();
                    if (t.isEmpty || !t.contains('@') || !t.contains('.')) {
                      return 'Adresse e-mail invalide';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telephone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Rôle *',
                    prefixIcon: Icon(Icons.verified_user_outlined),
                  ),
                  items: kRolesCollaborateur
                      .map(
                        (({String code, String libelle}) r) =>
                            DropdownMenuItem<String>(
                          value: r.code,
                          child: Text(r.libelle),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (String? v) {
                    if (v != null) setState(() => _role = v);
                  },
                ),
                // 🧩 MODULE 15 — À QUELLE BOUTIQUE ? Le choix n'apparaît
                //    qu'à partir de deux boutiques : sans multi-boutiques, il
                //    n'y aurait qu'une option et donc aucun choix à faire.
                if (_choixBoutique) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _espaceId,
                    decoration: const InputDecoration(
                      labelText: 'Boutique',
                      prefixIcon: Icon(Icons.storefront_outlined),
                      helperText:
                          'Le collaborateur ne verra que les données de cette boutique.',
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Boutique principale'),
                      ),
                      ...widget.espaces.map(
                        (Espace e) => DropdownMenuItem<String?>(
                          value: e.id,
                          child: Text(e.nom),
                        ),
                      ),
                    ],
                    onChanged: (String? v) => setState(() => _espaceId = v),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _motDePasse,
                  obscureText: !_voirMotDePasse,
                  decoration: InputDecoration(
                    labelText: _edition
                        ? 'Nouveau mot de passe (facultatif)'
                        : 'Mot de passe *',
                    prefixIcon: const Icon(Icons.lock_outline),
                    helperText: 'Au moins 8 caractères',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _voirMotDePasse
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _voirMotDePasse = !_voirMotDePasse),
                    ),
                  ),
                  validator: (String? v) {
                    final String t = (v ?? '').trim();
                    if (_edition && t.isEmpty) return null;
                    if (t.length < 8) {
                      return 'Le mot de passe doit comporter au moins 8 caractères';
                    }
                    return null;
                  },
                ),
                if (_edition) ...[
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _actif,
                    title: const Text('Compte actif'),
                    subtitle: const Text(
                      'Désactivé : le collaborateur ne peut plus se connecter.',
                    ),
                    onChanged: (bool v) => setState(() => _actif = v),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valider,
          child: Text(_edition ? 'Enregistrer' : 'Créer le compte'),
        ),
      ],
    );
  }
}
