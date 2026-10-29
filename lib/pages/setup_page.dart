// lib/pages/setup_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_auth;

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/espace.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/mode_application_service.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/sync_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class SetupPage extends StatefulWidget {
  final bool adminCreating;
  final Utilisateur? editUser;
  const SetupPage({super.key, this.adminCreating = false, this.editUser});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeBoutiqueCtrl = TextEditingController(); // AJOUT : Contrôleur pour le code d'invitation
  final _boutiqueCtrl = TextEditingController(); // 🏪 Nom de la boutique (entreprise)
  final _telephoneCtrl = TextEditingController(); // 📞 Correctif 21 : téléphone du responsable

  String _role = 'vendor';
  bool _saving = false;
  bool _obscurePassword = true;

  /// ⚡ MODULE 23 — MODE D'UTILISATION CHOISI À L'INSCRIPTION.
  ///
  /// « Rapide » (défaut) : entreprise créée et essai de 7 jours ACTIVÉ
  /// immédiatement (pas de double validation), écran d'accueil épuré.
  /// « Complet » : parcours historique (vérification gestionnaire → finance).
  ModeApplication _mode = ModeApplication.rapide;

  /// Rôles proposables à la création d'un compte, selon celui qui crée.
  ///
  /// 🔐 Les valeurs envoyées restent les codes **hérités** (`role`), car c'est
  /// ce que le déclencheur de la base traduit en rôle du Module 4. Or
  /// `role_herite('admin')` vaut **SUPER_ADMIN** : proposer « Administrateur »
  /// revenait donc à créer un Super Administrateur de la plateforme — y
  /// compris depuis un compte d'agent. L'option est désormais réservée au
  /// Super Administrateur, et disparaît pour tous les autres.
  List<({String code, String libelle})> get _rolesProposables {
    final RoleUtilisateur acteur = PermissionService.instance.roleCourant;
    return <({String code, String libelle})>[
      (code: 'vendor', libelle: 'Vendeur'),
      (code: 'collaborator', libelle: 'Collaborateur'),
      if (acteur == RoleUtilisateur.superAdmin)
        (code: 'admin', libelle: 'Administrateur (plateforme)'),
    ];
  }

  /// 🧩 MODULE 17 — catégorie d'activité choisie à la création du compte
  /// (Hôtel, Restaurant, Pharmacie…). Elle détermine l'environnement du
  /// client (modules, tableaux de bord, fonctionnalités).
  String _categorieActivite = 'boutique';
  List<({String code, String libelle})> _categories = const [];
  bool _chargementCategories = true;

  /// Un code boutique est saisi → le compte rejoint une entreprise : la
  /// catégorie est celle du patron, le sélecteur disparaît.
  bool _aCodeBoutique = false;

  @override
  void initState() {
    super.initState();
    if (widget.editUser != null) {
      _nomCtrl.text = widget.editUser!.nom;
      _emailCtrl.text = widget.editUser!.email;
      _role = widget.editUser!.role;
    }
    if (!widget.adminCreating) {
      _chargerCategories();
      _codeBoutiqueCtrl.addListener(_onCodeBoutiqueChange);
    }
  }

  void _onCodeBoutiqueChange() {
    final bool aCode = _codeBoutiqueCtrl.text.trim().isNotEmpty;
    if (aCode == _aCodeBoutique) return;
    setState(() => _aCodeBoutique = aCode);
  }

  /// 🧩 MODULE 17 — catégories d'activité proposées à l'inscription.
  ///
  /// Source : `rpc_types_espaces_publics()` (référentiel administré par la
  /// plateforme). Repli hors ligne : les types standards du module 15.
  Future<void> _chargerCategories() async {
    final Set<String> vus = <String>{};
    final List<({String code, String libelle})> liste =
        <({String code, String libelle})>[];

    try {
      final dynamic reponse = await SupabaseService.instance.client
          .rpc('rpc_types_espaces_publics');

      if (reponse is List) {
        for (final dynamic element in reponse) {
          if (element is! Map) continue;
          final String code = (element['type'] ?? '').toString().trim();
          final String libelle =
              (element['libelle'] ?? '').toString().trim();
          if (code.isEmpty || libelle.isEmpty || !vus.add(code)) continue;
          liste.add((code: code, libelle: libelle));
        }
      }
    } catch (e) {
      debugPrint('setup_page: catégories indisponibles ($e) — repli local');
    }

    if (liste.isEmpty) {
      for (final TypeEspace type in TypeEspace.values) {
        if (type == TypeEspace.autre) continue;
        liste.add((code: type.code, libelle: type.libelle));
      }
    }

    if (!mounted) return;
    setState(() {
      _categories = liste;
      _chargementCategories = false;
      if (!liste.any((({String code, String libelle}) c) =>
          c.code == _categorieActivite)) {
        _categorieActivite = liste.isEmpty ? 'boutique' : liste.first.code;
      }
    });
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeBoutiqueCtrl.removeListener(_onCodeBoutiqueChange);
    _codeBoutiqueCtrl.dispose(); // AJOUT : Libération du contrôleur
    _boutiqueCtrl.dispose(); // 🏪 Libération du contrôleur
    _telephoneCtrl.dispose(); // 📞 Libération du contrôleur
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppCouleurs.danger : AppCouleurs.succes,
      ),
    );
  }

  /// Attendre que le profil distant existe (trigger côté DB)
  Future<bool> _waitForRemoteProfile(String userId, {int maxAttempts = 6, int delayMs = 400}) async {
    final client = SupabaseService.instance.client;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final data = await client.from('utilisateurs').select().eq('id', userId).maybeSingle();
        if (data != null) return true;
      } catch (e) {
        // ignore and retry
      }
      await Future.delayed(Duration(milliseconds: delayMs));
    }
    return false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final nom = _nomCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text.trim();
    final codeSaisi = _codeBoutiqueCtrl.text.trim(); // AJOUT
    final nomBoutique = _boutiqueCtrl.text.trim(); // 🏪 nom de l'entreprise
    final telephone = _telephoneCtrl.text.trim(); // 📞 contact du responsable

    try {
      if (widget.editUser != null) {
        final u = Utilisateur(
          id: widget.editUser!.id,
          nom: nom,
          email: email,
          role: widget.editUser!.role,
          valide: widget.editUser!.valide,
          parentId: widget.editUser!.parentId,
        );
        await DBHelper.instance.updateUtilisateur(u);
        if (mounted) {
          _showSnackBar('Profil mis à jour');
          context.pop(true);
        }
        return;
      }

      // LOGIQUE DE PARENTÉ ET RÔLE
      String? parentId;
      // ⚠️ Inscription autonome (sans code) : on envoie directement le code
      // du Module 4 « PROPRIETAIRE ». L'ancien « vendor » est traduit en
      // « VENDEUR » par le trigger de la base (alors que l'application le
      // réserve au patron) — d'où le mauvais rôle des anciens comptes.
      String roleFinal = widget.adminCreating ? _role : 'PROPRIETAIRE';

      if (widget.adminCreating) {
        // Le patron crée lui-même le collaborateur
        parentId = await SessionManager.getUserId();
      } else if (codeSaisi.isNotEmpty) {
        // Le collaborateur s'inscrit lui-même avec un code boutique
        parentId = codeSaisi;
        roleFinal = 'collaborator';
      }

      // 1) Créer le user via Supabase Auth
      final user = await SupabaseService.instance.signUpUser(
        email: email,
        password: password,
        nom: nom,
        role: roleFinal,
        parentId: parentId,
      );

      // 2) Ne PAS forcer une insertion serveur locale ici (le trigger DB doit créer la ligne).
      //    On attend que le trigger ait fini, puis on synchronise localement.

      final remoteProfileExists = await _waitForRemoteProfile(user.id!);
      if (remoteProfileExists) {
        // upsert local depuis le cloud
        try {
          await SyncService.instance.syncUserProfile(user.id!);
        } catch (e) {
          debugPrint('Erreur syncUserProfile après signup: $e');
        }
      } else {
        final minimal = Utilisateur(
          id: user.id,
          nom: nom,
          email: email,
          role: user.role ?? roleFinal,
          valide: 1,
          parentId: parentId,
        );
        try {
          await DBHelper.instance.insertUtilisateur(minimal);
          debugPrint('Profil distant non trouvé : insert local minimal effectué.');
        } catch (e) {
          debugPrint('Impossible d\'insérer localement le profil minimal: $e');
        }
      }

      if (!mounted) return;

      if (!widget.adminCreating) {
        // Inscription classique : on sauvegarde la session et on démarre la sync complète
        await SessionManager.setUserId(user.id!);
        await SessionManager.setUserRole(user.role ?? roleFinal);
        try {
          await SyncService.instance.ensureLocalUserAndStart(user.id!);
        } catch (e) {
          debugPrint('Erreur démarrage sync après signup: $e');
        }

        // 🏪 Créer l'ENTREPRISE de la boutique (c'est elle qui porte
        // l'abonnement) et la rattacher au compte.
        //
        // ⚡ MODE SIMPLE : `rpc_entreprise_creer_simple` active un ESSAI de
        // 7 jours immédiatement — le commerçant peut vendre dès la première
        // seconde, sans attendre la vérification gestionnaire → finance.
        // MODE COMPLET : parcours historique (double validation).
        if (parentId == null) {
          // Le mode choisi s'applique à CET appareil dans tous les cas.
          await ModeApplicationService.instance.definir(_mode);
          try {
            await SupabaseService.instance.client.rpc(
              _mode == ModeApplication.rapide
                  ? 'rpc_entreprise_creer_simple'
                  : 'rpc_entreprise_creer',
              params: <String, dynamic>{
                if (nomBoutique.isNotEmpty) 'p_nom': nomBoutique,
                if (telephone.isNotEmpty) 'p_telephone': telephone,
                // 🧩 MODULE 17 — la CATÉGORIE choisie détermine
                // l'environnement du client (Hôtel → chambres…).
                'p_type': _mode == ModeApplication.rapide
                    ? 'boutique'
                    : _categorieActivite,
              },
            );
            // L'état d'accès (essai actif) est relu en arrière-plan :
            // l'inscription ne doit jamais attendre le réseau.
            unawaited(AbonnementService.instance.rafraichirSilencieux());
          } catch (e) {
            // Migration 81 pas encore exécutée : on retombe sur la création
            // standard pour que l'inscription ne reste jamais sans entreprise.
            final String texte = e.toString();
            final bool fonctionAbsente = texte.contains('PGRST202') ||
                texte.contains('Could not find the function');
            if (_mode == ModeApplication.rapide && fonctionAbsente) {
              try {
                await SupabaseService.instance.client.rpc(
                  'rpc_entreprise_creer',
                  params: <String, dynamic>{
                    if (nomBoutique.isNotEmpty) 'p_nom': nomBoutique,
                    if (telephone.isNotEmpty) 'p_telephone': telephone,
                    'p_type': 'boutique',
                  },
                );
                unawaited(
                    AbonnementService.instance.rafraichirSilencieux());
              } catch (e2) {
                debugPrint('Création de l\'entreprise (repli) ignorée : $e2');
              }
            } else {
              debugPrint('Création de l\'entreprise ignorée : $e');
            }
          }
        }

        if (!mounted) return;
        context.go('/main');
      } else {
        // Administrateur : collaborateur créé
        _showSnackBar("Utilisateur créé avec succès");
        context.pop(true);
      }
    } on supabase_auth.AuthException catch (e) {
      if (e.message.contains('already registered') || e.code == 'user_already_exists') {
        _showSnackBar('Cet email est déjà utilisé.', isError: true);
      } else {
        _showSnackBar(e.message, isError: true);
      }
    } catch (e) {
      _showSnackBar('Erreur : $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editUser != null;
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEdit ? 'Modifier profil' : (widget.adminCreating ? 'Nouvel utilisateur' : ''),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 520 : 420),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppCouleurs.marine.withValues(alpha: 0.08),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  )
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isEdit && !widget.adminCreating) ...[
                      Center(child: Image.asset('assets/Biashara_app_off-.png', height: 80)),
                      const SizedBox(height: 16),
                      const Text(
                        'Créer un compte',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Commencez à gérer votre commerce dès maintenant',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      const SizedBox(height: 32),
                    ],

                    _buildFieldTitle("Nom complet"),
                    TextFormField(
                      controller: _nomCtrl,
                      decoration: _buildInputDecoration(Icons.person_outline, "Votre nom"),
                      validator: (v) => v!.isEmpty ? 'Nom requis' : null,
                    ),
                    const SizedBox(height: 20),

                    _buildFieldTitle("Email"),
                    TextFormField(
                      controller: _emailCtrl,
                      enabled: !isEdit,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _buildInputDecoration(
                          Icons.email_outlined,
                          "exemple@mail.com",
                          isGreyed: isEdit
                      ),
                      validator: (v) => !v!.contains('@') ? 'Email invalide' : null,
                    ),
                    const SizedBox(height: 20),

                    if (!isEdit) ...[
                      _buildFieldTitle("Mot de passe"),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        decoration: _buildInputDecoration(
                          Icons.lock_outline_rounded,
                          "6 caractères minimum",
                          suffix: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) => v!.length < 6 ? 'Min 6 caractères' : null,
                      ),
                      const SizedBox(height: 20), // AJOUT : Espacement

                      // ⚡ MODULE 23 — MODE DE DÉMARRAGE.
                      // Rapide : essai actif immédiatement, accueil épuré.
                      // Complet : vérification par l'équipe plateforme.
                      if (!widget.adminCreating && !_aCodeBoutique) ...[
                        _buildFieldTitle('Mode de démarrage'),
                        SegmentedButton<ModeApplication>(
                          segments: const <ButtonSegment<ModeApplication>>[
                            ButtonSegment<ModeApplication>(
                              value: ModeApplication.rapide,
                              icon: Icon(Icons.bolt_rounded, size: 18),
                              label: Text('Rapide'),
                            ),
                            ButtonSegment<ModeApplication>(
                              value: ModeApplication.complet,
                              icon: Icon(Icons.dashboard_customize_outlined,
                                  size: 18),
                              label: Text('Complet'),
                            ),
                          ],
                          selected: <ModeApplication>{_mode},
                          onSelectionChanged: (Set<ModeApplication> choix) {
                            setState(() => _mode = choix.first);
                          },
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0, left: 4.0),
                          child: Text(
                            "Rapide : nom + prix → vous vendez tout de suite "
                            "(essai de 7 jours actif). Complet : catalogue, "
                            "stock et finance, avec vérification du compte.",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],

                      // 🧩 MODULE 17 — CATÉGORIE D'ACTIVITÉ : l'environnement
                      // du client (modules, tableaux de bord) suit ce choix.
                      if (!widget.adminCreating &&
                          !_aCodeBoutique &&
                          _mode == ModeApplication.complet &&
                          (_chargementCategories || _categories.isNotEmpty)) ...[
                        const SizedBox(height: 20),
                        _buildFieldTitle("Catégorie d'activité"),
                        if (_chargementCategories)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: LinearProgressIndicator(minHeight: 3),
                          )
                        else
                          AppDropdownField<String>(
                            label: "Type d'activité",
                            value: _categorieActivite,
                            prefixIcon: Icons.category_outlined,
                            items: <DropdownMenuItem<String>>[
                              for (final ({String code, String libelle}) c
                                  in _categories)
                                DropdownMenuItem<String>(
                                  value: c.code,
                                  child: Text(c.libelle),
                                ),
                            ],
                            onChanged: (String? v) {
                              if (v == null) return;
                              setState(() => _categorieActivite = v);
                            },
                          ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0, left: 4.0),
                          child: Text(
                            "Choisissez votre métier : Hôtel, Restaurant, Pharmacie, Boutique… L'application s'adapte automatiquement.",
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],

                      // 🏪 Nom de la boutique (entreprise) — pour le patron.
                      if (!widget.adminCreating) ...[
                        const SizedBox(height: 20),
                        _buildFieldTitle("Nom de votre entreprise (Optionnel)"),
                        TextFormField(
                          controller: _boutiqueCtrl,
                          decoration: _buildInputDecoration(
                            Icons.storefront_outlined,
                            "ex : Étoile",
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0, left: 4.0),
                          child: Text(
                            "C'est le nom de votre entreprise (essai de 7 jours). Laissez vide pour « votre catégorie + votre nom ».",
                            style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                          ),
                        ),

                        // 📞 Correctif 21 — Téléphone du responsable : visible
                        // dans l'administration pour la vérification du compte.
                        const SizedBox(height: 20),
                        _buildFieldTitle("Téléphone (Optionnel)"),
                        TextFormField(
                          controller: _telephoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: _buildInputDecoration(
                            Icons.phone_outlined,
                            "ex : +243 81 23 45 67",
                          ),
                          validator: (v) {
                            final String valeur = (v ?? '').trim();
                            if (valeur.isEmpty) return null;
                            return valeur.length < 8
                                ? 'Numéro trop court'
                                : null;
                          },
                        ),
                      ],

                      // AJOUT : Champ Code Boutique pour les nouveaux utilisateurs
                      if (!widget.adminCreating) ...[
                        _buildFieldTitle("Code Boutique (Optionnel)"),
                        TextFormField(
                          controller: _codeBoutiqueCtrl,
                          decoration: _buildInputDecoration(
                            Icons.vpn_key_outlined,
                            "Collez le code de votre patron",
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0, left: 4.0),
                          child: Text(
                            "Laissez vide si vous êtes le propriétaire.",
                            style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ],

                    if (widget.adminCreating) ...[
                      const SizedBox(height: 20),
                      _buildFieldTitle("Rôle de l'utilisateur"),
                      DropdownButtonFormField<String>(
                        value: _role,
                        decoration: _buildInputDecoration(Icons.badge_outlined, ""),
                        items: <DropdownMenuItem<String>>[
                          for (final ({String code, String libelle}) r
                              in _rolesProposables)
                            DropdownMenuItem(
                                value: r.code, child: Text(r.libelle)),
                          // Le rôle actuel du compte modifié peut être hors de
                          // la liste (compte « Administrateur » modifié par un
                          // non Super Administrateur) : on l'affiche sans le
                          // rendre sélectionnable.
                          if (!_rolesProposables.any(
                              (({String code, String libelle}) r) =>
                                  r.code == _role))
                            DropdownMenuItem(
                              value: _role,
                              enabled: false,
                              child: Text('$_role — non attribuable'),
                            ),
                        ],
                        onChanged: (v) => setState(() => _role = v!),
                      ),
                    ],

                    const SizedBox(height: 36),

                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: ModernLoader(
                                taille: 22,
                                epaisseur: 2.6,
                                couleur: Colors.white,
                                couleurSecondaire: Colors.white70,
                              ),
                            )
                          : Text(
                              isEdit
                                  ? 'METTRE À JOUR'
                                  : (widget.adminCreating
                                      ? 'AJOUTER'
                                      : 'S\'INSCRIRE'),
                              style: const TextStyle(letterSpacing: 1.0),
                            ),
                    ),

                    if (!isEdit && !widget.adminCreating)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text("Déjà un compte ? ", style: TextStyle(color: Colors.grey)),
                            TextButton(
                              onPressed: () => context.go('/login'),
                              child: const Text("Se connecter", style: TextStyle(fontWeight: FontWeight.bold)),
                            )
                          ],
                        ),
                      )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(IconData icon, String hint, {Widget? suffix, bool isGreyed = false}) {
    // Le style (fond, coins, état désactivé, focus) vient du thème global :
    // ici, seuls le libellé, l'icône et la teinte « lecture seule » changent.
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 22),
      suffixIcon: suffix,
      fillColor: isGreyed
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : null,
    );
  }
}