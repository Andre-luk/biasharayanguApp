// lib/pages/pressing/pressing_equipe_page.dart
//
// 🧺 MODULE 35 — L'ÉQUIPE DU PRESSING.
//
// Le patron crée lui-même ses comptes, sans développeur : chaque collaborateur
// a son e-mail, SON mot de passe et SON métier dans le pressing (accueil,
// atelier, caisse ou responsable).
//
// ⚠️ Le métier n'est pas un simple libellé : il est vérifié par le serveur.
//    Un agent d'atelier ne peut pas changer un tarif ; un caissier ne peut pas
//    faire avancer un vêtement. Le patron (et le responsable) peuvent tout.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/pressing_equipe.dart';
import 'package:biashara_yangu/services/pressing_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class PressingEquipePage extends StatefulWidget {
  const PressingEquipePage({super.key});

  @override
  State<PressingEquipePage> createState() => _PressingEquipePageState();
}

class _PressingEquipePageState extends State<PressingEquipePage> {
  final PressingService _service = PressingService.instance;

  EquipePressing _equipe = const EquipePressing();
  bool _chargement = true;
  String? _erreur;

  /// Le patron n'a pas de métier : `null` = tous les droits.
  bool get _peutGerer =>
      _equipe.roleCourant == null ||
      _equipe.roleCourant == RolePressing.responsable;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }
    try {
      final EquipePressing equipe = await _service.equipe();
      if (!mounted) return;
      setState(() {
        _equipe = equipe;
        _chargement = false;
        _erreur = null;
      });
    } on PressingException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? AppCouleurs.danger : null,
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
      await _charger(silencieux: true);
      _message('Compte créé : ${saisie.email} peut se connecter.');
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _modifier(CollaborateurPressing c) async {
    final _SaisieCollaborateur? saisie =
        await showDialog<_SaisieCollaborateur>(
      context: context,
      builder: (BuildContext _) => _DialogueCollaborateur(collaborateur: c),
    );
    if (saisie == null) return;

    try {
      await _service.majCollaborateur(
        id: c.id,
        nom: saisie.nom,
        prenom: saisie.prenom,
        telephone: saisie.telephone,
        role: saisie.role,
        actif: saisie.actif,
        motDePasse: saisie.motDePasse,
      );
      await _charger(silencieux: true);
      _message('Collaborateur mis à jour.');
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _basculer(CollaborateurPressing c) async {
    final RolePressing role = c.role ?? RolePressing.accueil;
    try {
      await _service.majCollaborateur(
        id: c.id,
        nom: c.nom,
        prenom: c.prenom,
        telephone: c.telephone,
        role: role,
        actif: !c.actif,
      );
      await _charger(silencieux: true);
      _message(c.actif
          ? '${c.nomComplet} ne peut plus se connecter.'
          : '${c.nomComplet} peut de nouveau se connecter.');
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Équipe du pressing'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _peutGerer
          ? FloatingActionButton.extended(
              onPressed: _creer,
              icon: const Icon(Icons.person_add_alt_rounded),
              label: const Text('Nouveau collaborateur'),
            )
          : null,
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur(_erreur!)
              : RefreshIndicator(
                  onRefresh: () => _charger(silencieux: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: <Widget>[
                      _encart(),
                      if (_equipe.estVide) _vide(),
                      ..._equipe.collaborateurs.map(_tuile),
                    ],
                  ),
                ),
    );
  }

  Widget _encart() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppCouleurs.marine.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.groups_rounded, size: 18, color: AppCouleurs.marine),
              const SizedBox(width: 8),
              const Text(
                'Chaque métier a ses droits',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...RolePressing.tous.map(
            (RolePressing r) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 118,
                    child: Text(
                      r.libelle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.explication,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vide() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: <Widget>[
          Icon(Icons.group_outlined, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            'Aucun collaborateur pour l\'instant.\n'
            'Créez un compte pour votre agent d\'accueil, d\'atelier ou de caisse.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _tuile(CollaborateurPressing c) {
    final RolePressing? role = c.role;
    final Color couleur = c.actif ? AppCouleurs.succes : Colors.grey;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppCouleurs.marine.withValues(alpha: 0.12),
          child: Text(
            c.initiales,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppCouleurs.marine,
            ),
          ),
        ),
        title: Text(
          c.nomComplet.isEmpty ? c.email : c.nomComplet,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          <String>[
            if ((c.email).trim().isNotEmpty) c.email.trim(),
            if ((c.telephone).trim().isNotEmpty) c.telephone.trim(),
            if (role != null) role.libelle else 'Métier non défini',
            if (!c.actif) 'compte désactivé',
          ].join(' · '),
          style: const TextStyle(fontSize: 11.5),
          maxLines: 2,
        ),
        isThreeLine: true,
        trailing: _peutGerer
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Modifier',
                    onPressed: () => _modifier(c),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  Switch(
                    value: c.actif,
                    activeThumbColor: couleur,
                    onChanged: (_) => _basculer(c),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _vueErreur(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 56, color: AppCouleurs.danger),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _charger(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
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
  });

  final String nom;
  final String prenom;
  final String email;
  final String telephone;
  final String motDePasse;
  final RolePressing role;
  final bool actif;
}

class _DialogueCollaborateur extends StatefulWidget {
  const _DialogueCollaborateur({this.collaborateur});

  final CollaborateurPressing? collaborateur;

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

  late RolePressing _role =
      widget.collaborateur?.role ?? RolePressing.accueil;
  late bool _actif = widget.collaborateur?.actif ?? true;
  bool _obscur = true;
  String? _erreur;

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

  void _valider() {
    if (_nom.text.trim().isEmpty) {
      setState(() => _erreur = 'Indiquez le nom du collaborateur.');
      return;
    }
    if (_nouveau &&
        (!_email.text.contains('@') || !_email.text.contains('.'))) {
      setState(() => _erreur = 'Indiquez une adresse e-mail valide.');
      return;
    }
    if (_nouveau && _motDePasse.text.trim().length < 8) {
      setState(() =>
          _erreur = 'Le mot de passe doit comporter au moins 8 caractères.');
      return;
    }

    Navigator.of(context).pop(
      _SaisieCollaborateur(
        nom: _nom.text.trim(),
        prenom: _prenom.text.trim(),
        email: _email.text.trim().toLowerCase(),
        telephone: _telephone.text.trim(),
        motDePasse: _motDePasse.text.trim(),
        role: _role,
        actif: _actif,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_nouveau ? 'Nouveau collaborateur' : 'Modifier le collaborateur'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nom,
              autofocus: _nouveau,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prenom,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Prénom',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              enabled: _nouveau,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail (identifiant de connexion)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            AppDropdownField<RolePressing>(
              label: 'Métier dans le pressing',
              value: _role,
              prefixIcon: Icons.badge_outlined,
              items: RolePressing.tous
                  .map((RolePressing r) => DropdownMenuItem<RolePressing>(
                        value: r,
                        child: Text(r.libelle),
                      ))
                  .toList(growable: false),
              onChanged: (RolePressing? v) {
                if (v != null) setState(() => _role = v);
              },
            ),
            const SizedBox(height: 6),
            Text(
              _role.explication,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _motDePasse,
              obscureText: _obscur,
              decoration: InputDecoration(
                labelText: _nouveau
                    ? 'Mot de passe (8 caractères minimum)'
                    : 'Nouveau mot de passe (facultatif)',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscur = !_obscur),
                  icon: Icon(
                    _obscur ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            if (!_nouveau) ...<Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Compte actif'),
                subtitle: const Text('Désactivé : le collaborateur ne peut plus se connecter.'),
                value: _actif,
                onChanged: (bool v) => setState(() => _actif = v),
              ),
            ],
            if (_erreur != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _erreur!,
                style: TextStyle(color: AppCouleurs.danger, fontSize: 12.5),
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
          onPressed: _valider,
          child: Text(_nouveau ? 'Créer le compte' : 'Enregistrer'),
        ),
      ],
    );
  }
}
