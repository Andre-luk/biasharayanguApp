// lib/pages/distribution_collaborateurs_page.dart
//
// 🚚 MODULE 24 — COLLABORATEURS DE LA DISTRIBUTION.
//
// Le propriétaire crée lui-même ses comptes, sans développeur ni accès à la
// base : chaque collaborateur a SON mot de passe et SON rôle distribution.
// Le serveur crée le compte Auth réel et refuse tout le reste.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/services/distribution_gestion_service.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/distribution_widgets.dart';

class DistributionCollaborateursPage extends StatefulWidget {
  const DistributionCollaborateursPage({super.key});

  @override
  State<DistributionCollaborateursPage> createState() =>
      _DistributionCollaborateursPageState();
}

class _DistributionCollaborateursPageState
    extends State<DistributionCollaborateursPage> {
  final DistributionGestionService _service =
      DistributionGestionService.instance;

  List<CollaborateurDistribution> _collaborateurs =
      const <CollaborateurDistribution>[];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;
    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    try {
      final List<CollaborateurDistribution> items =
          await _service.collaborateurs();
      if (!mounted) return;
      setState(() {
        _collaborateurs = items;
        _chargement = false;
        _erreur = null;
      });
    } on DistributionGestionException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e, st) {
      debugPrint('DistributionCollaborateursPage : $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger les collaborateurs.';
        _chargement = false;
      });
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _creer() async {
    final _SaisieCollaborateur? saisie =
        await showDialog<_SaisieCollaborateur>(
      context: context,
      builder: (BuildContext _) => const _DialogueCollaborateur(),
    );
    if (saisie == null) return;

    try {
      await _service.creerCollaborateur(
        nom: saisie.nom,
        prenom: saisie.prenom,
        email: saisie.email,
        telephone: saisie.telephone,
        motDePasse: saisie.motDePasse,
        role: saisie.role,
      );
      _message('Collaborateur créé : il peut se connecter avec son e-mail.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _modifier(CollaborateurDistribution c) async {
    final _SaisieCollaborateur? saisie =
        await showDialog<_SaisieCollaborateur>(
      context: context,
      builder: (BuildContext _) => _DialogueCollaborateur(
        collaborateur: c,
      ),
    );
    if (saisie == null) return;

    try {
      if (saisie.nouveau) {
        await _service.creerCollaborateur(
          nom: saisie.nom,
          prenom: saisie.prenom,
          email: saisie.email,
          telephone: saisie.telephone,
          motDePasse: saisie.motDePasse,
          role: saisie.role,
        );
      } else {
        await _service.majCollaborateur(
          id: c.id,
          nom: saisie.nom,
          prenom: saisie.prenom,
          telephone: saisie.telephone,
          role: saisie.role,
          actif: saisie.actif,
          motDePasse:
              saisie.motDePasse.trim().isEmpty ? null : saisie.motDePasse,
        );
      }
      _message('Collaborateur enregistré.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collaborateurs Distribution'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creer,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nouveau collaborateur'),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreur!, textAlign: TextAlign.center),
                  ),
                )
              : _collaborateurs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const Icon(Icons.groups_2_outlined, size: 48),
                            const SizedBox(height: 12),
                            const Text(
                              'Aucun collaborateur. Créez le responsable de '
                              'production, le gestionnaire de stock, le gérant, '
                              'les commerciaux et le comptable.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _creer,
                              icon: const Icon(Icons.person_add_alt_1),
                              label: const Text('Créer un collaborateur'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _charger(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: _collaborateurs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (BuildContext context, int i) {
                          final CollaborateurDistribution c =
                              _collaborateurs[i];
                          return Card(
                            elevation: 0,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(_initiales(c)),
                              ),
                              title: Text(
                                c.nomComplet.isEmpty ? c.email : c.nomComplet,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(<String>[
                                c.role.libelle,
                                if (c.email.isNotEmpty) c.email,
                                if (c.telephone.isNotEmpty) c.telephone,
                              ].join(' · ')),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  PuceDistribution(
                                    libelle: c.actif ? 'Actif' : 'Désactivé',
                                    couleur: c.actif
                                        ? Colors.green.shade700
                                        : Colors.grey.shade600,
                                  ),
                                  IconButton(
                                    tooltip: 'Modifier',
                                    onPressed: () => _modifier(c),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  static String _initiales(CollaborateurDistribution c) {
    final String n = c.nom.trim();
    final String p = c.prenom.trim();
    final String a = n.isEmpty ? '' : n[0];
    final String b = p.isEmpty ? '' : p[0];
    final String r = '$a$b'.toUpperCase();
    return r.isEmpty ? '?' : r;
  }
}

// ---------------------------------------------------------------------------
// DIALOGUE
// ---------------------------------------------------------------------------

class _SaisieCollaborateur {
  const _SaisieCollaborateur({
    required this.nom,
    required this.prenom,
    required this.email,
    required this.telephone,
    required this.motDePasse,
    required this.role,
    required this.actif,
    required this.nouveau,
  });

  final String nom;
  final String prenom;
  final String email;
  final String telephone;
  final String motDePasse;
  final RoleDistribution role;
  final bool actif;
  final bool nouveau;
}

class _DialogueCollaborateur extends StatefulWidget {
  const _DialogueCollaborateur({this.collaborateur});

  final CollaborateurDistribution? collaborateur;

  @override
  State<_DialogueCollaborateur> createState() => _DialogueCollaborateurState();
}

class _DialogueCollaborateurState extends State<_DialogueCollaborateur> {
  late final TextEditingController _nom =
      TextEditingController(text: widget.collaborateur?.nom ?? '');
  late final TextEditingController _prenom =
      TextEditingController(text: widget.collaborateur?.prenom ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.collaborateur?.email ?? '');
  late final TextEditingController _telephone =
      TextEditingController(text: widget.collaborateur?.telephone ?? '');
  final TextEditingController _motDePasse = TextEditingController();
  late RoleDistribution _role = widget.collaborateur?.role ??
      RoleDistribution.production;
  late bool _actif = widget.collaborateur?.actif ?? true;
  bool _obscur = true;

  bool get _nouveau => widget.collaborateur == null;

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _email.dispose();
    _telephone.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<RoleDistribution> roles = <RoleDistribution>[
      RoleDistribution.gerant,
      RoleDistribution.production,
      RoleDistribution.stock,
      RoleDistribution.commercial,
      RoleDistribution.comptable,
    ];

    return AlertDialog(
      title: Text(_nouveau ? 'Nouveau collaborateur' : 'Modifier le collaborateur'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nom,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prenom,
              decoration: const InputDecoration(labelText: 'Prénom'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              enabled: _nouveau,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail (identifiant de connexion)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone'),
            ),
            const SizedBox(height: 10),
            AppDropdownField<RoleDistribution>(
              label: 'Rôle dans la distribution',
              value: _role,
              items: roles
                  .map((RoleDistribution r) => DropdownMenuItem<RoleDistribution>(
                        value: r,
                        child: Text(r.libelle),
                      ))
                  .toList(),
              onChanged: (RoleDistribution? v) =>
                  setState(() => _role = v ?? _role),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _motDePasse,
              obscureText: _obscur,
              decoration: InputDecoration(
                labelText: _nouveau
                    ? 'Mot de passe (8 caractères minimum)'
                    : 'Nouveau mot de passe (facultatif)',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscur = !_obscur),
                  icon: Icon(
                      _obscur ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
            if (!_nouveau) ...<Widget>[
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Compte actif'),
                value: _actif,
                onChanged: (bool v) => setState(() => _actif = v),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (_nom.text.trim().isEmpty) return;
            if (_nouveau && _email.text.trim().isEmpty) return;
            if (_nouveau && _motDePasse.text.trim().length < 8) return;

            Navigator.of(context).pop(_SaisieCollaborateur(
              nom: _nom.text.trim(),
              prenom: _prenom.text.trim(),
              email: _email.text.trim().toLowerCase(),
              telephone: _telephone.text.trim(),
              motDePasse: _motDePasse.text.trim(),
              role: _role,
              actif: _actif,
              nouveau: _nouveau,
            ));
          },
          child: Text(_nouveau ? 'Créer le compte' : 'Enregistrer'),
        ),
      ],
    );
  }
}
