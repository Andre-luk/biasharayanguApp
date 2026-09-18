import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_auth;

import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/audit_service.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/services/sync_service.dart';
import 'package:biashara_yangu/services/subscription_sync_service.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
// 🧾 MODULE 14 — synchronisation du workflow d'activation (restriction /
// réactivation automatiques) après chaque connexion.
import 'package:biashara_yangu/services/activation_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/scanner_service.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/pages/password_recovery_page.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final SupabaseService _supabaseService = SupabaseService.instance;
  final SyncService _syncService = SyncService.instance;
  final DBHelper _dbHelper = DBHelper.instance;

  bool _isLoading = false;
  bool _obscurePassword = true;

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? AppCouleurs.danger
            : AppCouleurs.marine,
      ),
    );
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    // Retiendra le vrai problème RÉSEAU pour un message honnête (ne pas
    // annoncer « identifiants incorrects » quand le serveur est injoignable).
    String? erreurReseau;

    try {
      // 1. CONNEXION SUPABASE
      try {
        final user =
            await _supabaseService.signInUser(email: email, password: password);
        if (user != null && user.id != null) {
          final userId = user.id!;
          await SessionManager.setUserId(userId);

          // 🔐 MODULE 12 — connexion tracée (best-effort : le journal ne doit
          // jamais empêcher une connexion réussie).
          await AuditService.instance.connexion(email: email);

          try {
            await _syncService.syncUserProfile(userId);
            final localUser = await _dbHelper.getUtilisateurById(userId);

            // Extraction sécurisée du ownerId (Patron)
            final String? pId = localUser?.parentId;
            final String ownerId =
                (pId != null && pId.isNotEmpty) ? pId : userId;

            final role = localUser?.role ?? 'vendor';
            await SessionManager.setUserRole(role);

            final db = await _dbHelper.database;
            final subSync = SubscriptionSyncService(db: db);
            await subSync.downloadAndSaveSubscriptions(ownerId);

            // 👇 AJOUT IMPORTANT : Téléchargement de l'historique des données
            try {
              // 1. On télécharge tout l'historique depuis Supabase vers le téléphone (SQLite)
              await _syncService.initialDownload(userId);

              // 2. Par sécurité, s'il y avait des données locales créées hors ligne, on les pousse vers Supabase
              await _syncService.syncAll();
            } catch (syncError) {
              debugPrint(
                  '⚠️ Erreur lors de la synchronisation initiale des données: $syncError');
            }
            // 👆 FIN DE L'AJOUT

            _syncService.startRealtimeSync();
          } catch (e) {
            debugPrint('⚠️ Sync Error: $e');
          }

          if (!mounted) return;
          await _navigateAfterLogin(userId);
          return;
        }
      } on supabase_auth.AuthException catch (e) {
        if (e.message.contains('Invalid login credentials')) {
          // 🔐 MODULE 12 — échec de connexion tracé (session anonyme autorisée
          // uniquement pour cette action).
          await AuditService.instance
              .echecConnexion(email, 'Email ou mot de passe incorrect.');
          _showSnackBar('Email ou mot de passe incorrect.', isError: true);
          setState(() => _isLoading = false);
          return;
        }
      } catch (e) {
        // Réseau / DNS / TLS / base locale indisponible… : on garde le repli
        // local (mode hors ligne), mais on retiendra le vrai problème.
        erreurReseau = e.toString();
        debugPrint('Connexion Supabase impossible : $e');
      }

      // 2. CONNEXION LOCALE (Hors ligne)
      final hash = _hashPassword(password);
      Utilisateur? localUser =
          await _dbHelper.getUtilisateurByEmailAndPassword(email, password);
      if (localUser == null) {
        try {
          localUser =
              await _dbHelper.getUtilisateurByEmailAndPasswordHash(email, hash);
        } catch (_) {}
      }

      if (localUser != null) {
        await SessionManager.setUserId(localUser.id!);
        await SessionManager.setUserRole(
          localUser.role.isNotEmpty ? localUser.role : 'collaborator',
        );
        if (!mounted) return;
        await _navigateAfterLogin(localUser.id!);
        return;
      }

      // 🔐 MODULE 12 — échec tracé aussi pour le repli local (compte inconnu).
      await AuditService.instance.echecConnexion(
        email,
        erreurReseau == null
            ? 'Identifiants incorrects (repli local).'
            : 'Serveur injoignable : $erreurReseau',
      );
      _showSnackBar(
        erreurReseau == null
            ? 'Identifiants incorrects. Vérifiez l\'email et le mot de passe.'
            : 'Serveur injoignable (connexion Internet ?). Réessayez quand le réseau revient.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateAfterLogin(String userId) async {
    // -------------------------------------------------------------------------
    //  🔐 MODULE 4 — RÉSOLUTION DU RÔLE
    // -------------------------------------------------------------------------
    //  Le rôle est relu à trois sources, de la plus fiable à la plus récente :
    //    1. `new_role` du profil local (colonne officielle du Module 4) ;
    //    2. l'ancien rôle texte (`admin`, `vendor`, `collaborator`) ;
    //    3. la base Supabase, consultée juste après : si la synchronisation
    //       locale a échoué, un administrateur de plateforme se retrouverait
    //       sinon enfermé hors de sa propre plateforme.
    //
    //  Les permissions sont ensuite chargées AVANT toute navigation : le
    //  middleware du routeur s'appuie sur elles dès le premier écran.
    RoleUtilisateur role = RoleUtilisateur.fromCode(
      await SessionManager.getUserRole(),
    );

    final Utilisateur? profilLocal = await _dbHelper.getUtilisateurById(userId);
    final RoleUtilisateur roleProfil =
        PermissionService.roleDepuisUtilisateur(profilLocal);
    if (roleProfil != RoleUtilisateur.inconnu) role = roleProfil;

    if (!role.estPlateforme &&
        await SupabaseService.instance.estAdministrateurPlateforme(userId)) {
      role = RoleUtilisateur.superAdmin;
    }

    // Session locale alignée sur le rôle effectif (les prochains démarrages
    // n'auront plus besoin d'interroger la base).
    await SessionManager.setUserRole(role.code);

    // Best-effort : hors ligne, la matrice par défaut du Module 4 s'applique.
    await PermissionService.instance.initialiser(
      role.code,
      forcerRechargement: true,
    );

    // -------------------------------------------------------------------------
    //  EXEMPTION DE L'ADMINISTRATION PLATEFORME
    // -------------------------------------------------------------------------
    //  Les quatre rôles de la plateforme ne sont soumis à AUCUN contrôle
    //  d'accès : ni celui de l'entreprise, ni celui de l'abonnement.
    if (role.estPlateforme) {
      if (!mounted) return;
      context.go('/admin');
      return;
    }

    // 🔒 MODULE 3 — Middleware d'abonnement.
    //
    // 1. Best-effort : la base normalise d'abord les abonnements échus
    //    (EXPIRE / EN_ATTENTE_COMPLEMENT).
    // 2. Le statut de l'entreprise rattachée est ensuite évalué :
    //    - suspendue → accès bloqué (décision de l'administrateur) ;
    //    - échue     → accès en LECTURE SEULE : la consultation reste possible,
    //                  les fonctionnalités commerciales sont bloquées ;
    //    - valide    → accès complet.
    //
    // `verifierAccesUtilisateur` est fail-open : un incident réseau ou une
    // fonction absente laisse l'accès complet.
    await AbonnementService.instance.executerVerificationGlobaleSilencieuse();

    // 🧾 MODULE 14 — synchronise les dossiers d'activation : restriction
    // automatique (solde impayé à l'échéance, données conservées) et
    // réactivation après régularisation. Best-effort.
    await ActivationService.instance.synchroniserSilencieux();

    final EtatAccesAbonnement etatAbonnement =
        await AbonnementService.instance.verifierAccesUtilisateur(userId);

    if (etatAbonnement.bloque) {
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Accès bloqué'),
          content: Text(
            etatAbonnement.message ?? "L'accès à l'application est bloqué.",
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                // 🔐 MODULE 12 — session bloquée : déconnexion tracée.
                await AuditService.instance.deconnexion(
                  email: _emailController.text.trim().toLowerCase(),
                );
                await SupabaseService.instance.signOut();
                await SessionManager.clearSession();
                AbonnementService.instance.reinitialiserAcces();
                // 🔳 MODULE 7 — session terminée : panier et historique vidés.
                PanierService.instance.vider();
                ScannerService.instance.viderHistorique();
              },
              child: const Text('Se déconnecter'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }

    if (!mounted) return;

    // L'état d'abonnement est désormais calculé par le moteur (Module 3) :
    // l'ancien contrôle local SQLite `subscriptions` n'est plus consulté.
    //
    // 🔐 MODULE 4 — la destination dépend des permissions du rôle. Le contrôle
    // d'abonnement reste PRIORITAIRE : un abonnement échu (`lectureSeule`)
    // ramène sur l'accueil consultable plutôt que sur l'écran de vente —
    // uniquement si le rôle a le droit d'ouvrir cet accueil, faute de quoi on
    // provoquerait un aller-retour de redirections inutile.
    final String? accueil = PermissionService.instance.accueilPour(role);

    if (etatAbonnement.lectureSeule &&
        accueil == '/main/new-sale' &&
        PermissionService.instance.peutVoir(PageAccess.dashboard)) {
      context.go('/main');
      return;
    }

    context.go(accueil ?? '/main');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool sombre = theme.brightness == Brightness.dark;
    final Size size = MediaQuery.of(context).size;
    final bool isWide = size.width > 760;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: sombre ? AppDegrades.fondSombre : AppDegrades.fondClair,
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 920 : 440),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: colorScheme.outlineVariant),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppCouleurs.marine.withValues(alpha: 0.10),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isWide) Expanded(child: _buildBanner(colorScheme)),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(isWide ? 40 : 26),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!isWide) ...[
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surface,
                                          borderRadius:
                                              BorderRadius.circular(22),
                                          border: Border.all(
                                            color: colorScheme.outlineVariant,
                                          ),
                                        ),
                                        child: Image.asset(
                                          'assets/Biashara_app_off-.png',
                                          height: 64,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                  ],
                                  Text(
                                    'Connexion',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Accédez à votre espace de gestion.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  _buildTextField(_emailController, 'Email',
                                      Icons.alternate_email_rounded),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    _passwordController,
                                    'Mot de passe',
                                    Icons.lock_outline_rounded,
                                    isPassword: true,
                                  ),
                                  _buildForgotButton(colorScheme),
                                  const SizedBox(height: 18),
                                  _buildLoginButton(colorScheme),
                                  const SizedBox(height: 22),
                                  _buildFooter(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(ColorScheme colorScheme) {
    return Container(
      decoration: const BoxDecoration(gradient: AppDegrades.hero),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -50,
            child: _CercleDeco(
              taille: 180,
              couleur: Colors.white.withValues(alpha: 0.07),
            ),
          ),
          Positioned(
            bottom: -70,
            left: -40,
            child: _CercleDeco(
              taille: 200,
              couleur: AppCouleurs.orange.withValues(alpha: 0.15),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/Biashara_app_off-.png',
                      height: 84,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Biashara Yangu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Gérez votre commerce avec simplicité.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 34),
                const _PointCle(
                  icone: Icons.qr_code_scanner_rounded,
                  texte: 'Scannez et encaissez en quelques secondes',
                ),
                const SizedBox(height: 14),
                const _PointCle(
                  icone: Icons.inventory_2_rounded,
                  texte: 'Stock, caisse et dettes toujours à jour',
                ),
                const SizedBox(height: 14),
                const _PointCle(
                  icone: Icons.insights_rounded,
                  texte: 'Rapports PDF & Excel signés et traçables',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon,
      {bool isPassword = false}) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : false,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(_obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Champ requis' : null,
    );
  }

  Widget _buildForgotButton(ColorScheme colorScheme) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const PasswordRecoveryPage())),
        child: Text('Mot de passe oublié ?',
            style: TextStyle(
                color: colorScheme.primary, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildLoginButton(ColorScheme colorScheme) {
    return FilledButton(
      onPressed: _isLoading ? null : _signIn,
      child: _isLoading
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
          : const Text(
              'SE CONNECTER',
              style: TextStyle(letterSpacing: 0.8),
            ),
    );
  }

  Widget _buildFooter() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text("Pas encore de compte ?"),
        TextButton(
            onPressed: () => context.go('/setup'),
            child: const Text('S\'inscrire',
                style: TextStyle(fontWeight: FontWeight.bold))),
      ],
    );
  }
}

/// Point clé affiché dans la bannière (côté large de l'écran de connexion).
class _PointCle extends StatelessWidget {
  const _PointCle({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icone, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              texte,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Disque translucide décoratif.
class _CercleDeco extends StatelessWidget {
  const _CercleDeco({required this.taille, required this.couleur});

  final double taille;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
    );
  }
}
