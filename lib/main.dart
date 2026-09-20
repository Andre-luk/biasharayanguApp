import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Config & Utils
import 'config/app_router.dart';
import 'l10n/app_localizations.dart';
import 'models/permission.dart';
import 'ui/theme/app_theme.dart';
import 'utils/language_manager.dart';
import 'utils/theme_manager.dart';
import 'utils/accessibilite_manager.dart';
import 'utils/session_manager.dart';
import 'utils/fenetre_bureau.dart';

// Pages
import 'pages/splash_screen.dart';

// Services
import 'services/supabase_service.dart';
import 'services/sync_service.dart';
import 'services/abonnement_service.dart';
// 🧾 MODULE 14 — synchronisation des dossiers d'activation (restriction /
// réactivation automatiques) au démarrage.
import 'services/activation_service.dart';
// 🔔 NOTIFICATIONS — chaque vente + rapport de fin de journée.
import 'services/notification_service.dart';
// 🧩 MODULE 16 — modules de l'activité (socle multi-activités, phase A).
import 'services/modules_service.dart';
import 'services/permission_service.dart';
import 'db_helper.dart';

import 'dart:async' show unawaited;

late final SupabaseClient supabase;

/// Initialise le backend Supabase (isolé pour être lancé EN PARALLÈLE des
/// autres préparatifs du démarrage).
Future<void> _initialiserSupabase() async {
  try {
    await Supabase.initialize(
      url: 'https://pqzcliibocndiyqbyddr.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBxemNsaWlib2NuZGl5cWJ5ZGRyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA1NjAxMjksImV4cCI6MjA3NjEzNjEyOX0.t5XXsrOk_AFRwm-13LYz23-Q6jyFDXEDGNo6kjRDSlM',
    );
    supabase = Supabase.instance.client;
  } catch (e) {
    debugPrint('Erreur Supabase Init: $e');
  }
}

/// Utilisateur local (SQLite) — `null` si la base locale est indisponible
/// (cas du web : PHASE F) : le démarrage continue sans bloquer.
Future<dynamic> _premierUtilisateurLocal() async {
  try {
    return await DBHelper.instance.getFirstUtilisateur();
  } catch (e) {
    debugPrint('Base locale indisponible (premier utilisateur) : $e');
    return null;
  }
}

/// Utilisateur local par identifiant — `null` si indisponible (web).
Future<dynamic> _utilisateurLocal(String? uid) async {
  if (uid == null) return null;
  try {
    return await DBHelper.instance.getUtilisateurById(uid);
  } catch (e) {
    debugPrint('Base locale indisponible (utilisateur $uid) : $e');
    return null;
  }
}

void main() async {
  // 1. Initialisation des bindings et Splash Screen
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 2. 🚀 Préparatifs EN PARALLÈLE : formats de date (fix crash PDF/Vivo Y93)
  //    et initialisation Supabase — le lancement est ainsi plus rapide.
  await Future.wait<void>([
    initializeDateFormatting('fr_FR', null),
    initializeDateFormatting('en_US', null),
    initializeDateFormatting('sw_KE', null),
    _initialiserSupabase(),
  ]);

  // Lancement du Realtime en arrière-plan
  SupabaseService.instance.initializeRealtime();

  // 🔔 Notifications locales : initialisation + surveillance du rapport de
  // fin de journée (best-effort — jamais bloquant au démarrage).
  try {
    await NotificationService.instance.initialiser();
    NotificationService.instance.demarrerSurveillanceQuotidienne();
  } catch (e) {
    debugPrint('Notifications désactivées : $e');
  }

  // 🧩 MODULE 16 — MULTI-ACTIVITÉS (phase A) : surveille l'entreprise active.
  // Chaque bascule d'espace recharge les modules de la nouvelle activité
  // (best-effort — un échec laisse l'application en mode standard).
  ModulesService.instance.demarrerSurveillance();

  // 💳 MODULE 3 — Vérification globale des abonnements au démarrage.
  // Best-effort : si une session est restaurée, on demande à la base de
  // normaliser les abonnements échus (EXPIRE / EN_ATTENTE_COMPLEMENT).
  // Aucun échec ne doit empêcher le lancement de l'application.
  try {
    if (supabase.auth.currentUser != null) {
      AbonnementService.instance.executerVerificationGlobaleSilencieuse();
      // 🧾 MODULE 14 — restriction automatique (solde impayé à l'échéance)
      // et réactivation après régularisation. Best-effort, jamais bloquant.
      ActivationService.instance.synchroniserSilencieux();
    }
  } catch (e) {
    debugPrint('Vérification globale des abonnements ignorée: $e');
  }

  // 4. Configuration Desktop (Windows / Linux / macOS — no-op sur le web).
  await configurerFenetreBureau();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageManager()),
        ChangeNotifierProvider(create: (_) => ThemeManager()),
        // ♿ Accessibilité — taille du texte de l'application.
        ChangeNotifierProvider(create: (_) => AccessibiliteManager()),
      ],
      child: const BiasharaApp(),
    ),
  );
}

class BiasharaApp extends StatefulWidget {
  const BiasharaApp({super.key});
  @override
  State<BiasharaApp> createState() => _BiasharaAppState();
}

class _BiasharaAppState extends State<BiasharaApp> {
  bool _isInitialized = false;

  /// L'application a terminé son démarrage : l'écran cible est routé.
  bool _pret = false;

  /// Le splash a fini son fondu : il est retiré de l'arbre (libère l'animation).
  bool _splashDisparu = false;

  // Thèmes construits UNE seule fois (performance : pas de reconstruction
  // de `ThemeData` à chaque `build`).
  final ThemeData _themeClair = AppTheme.clair();
  final ThemeData _themeSombre = AppTheme.sombre();

  @override
  void initState() {
    super.initState();
    // Dès le premier frame Flutter, le splash natif laisse la place au splash
    // moderne (animé) : la transition est invisible pour l'utilisateur.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      if (mounted && _pret && !_splashDisparu) {
        setState(() => _splashDisparu = true);
      }
    });
    _handleStartup();
  }

  Future<void> _handleStartup() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      // Récupération des données de session et utilisateur local
      final results = await Future.wait([
        SessionManager.getUserId(),
        SessionManager.getUserRole(),
        _premierUtilisateurLocal(),
      ]);

      final String? savedUserId = results[0] as String?;
      final String? role = results[1] as String?;
      final firstUser = results[2];

      final currentSession = supabase.auth.currentSession;
      String targetRoute = '/login';

      // Logique de routage intelligente
      if (firstUser == null && savedUserId == null && currentSession == null) {
        targetRoute = '/setup';
      } else if (savedUserId != null || currentSession != null) {
        final uid = savedUserId ?? currentSession?.user.id;

        // 🔐 MODULE 4 — rôle effectif + permissions, chargés AVANT le premier
        // écran : le middleware du routeur s'appuie dessus dès la restauration
        // de session (démarrage à froid de l'application).
        RoleUtilisateur roleEffectif =
            PermissionService.roleDepuisCodes(role: role);

        if (roleEffectif.estPlateforme) {
          await PermissionService.instance.initialiser(
            roleEffectif.code,
            forcerRechargement: true,
          );
          targetRoute = '/admin';
        } else {
          final localUser =
              await _utilisateurLocal(uid);
          _checkSubscriptionInBackground(localUser?.parentId ?? uid);

          final RoleUtilisateur roleProfil =
              PermissionService.roleDepuisUtilisateur(localUser);
          if (roleProfil != RoleUtilisateur.inconnu) roleEffectif = roleProfil;

          await PermissionService.instance.initialiser(
            roleEffectif.code,
            forcerRechargement: true,
          );

          // 🧩 MODULE 16 — profil de modules de l'espace actif (activité de
          // l'entreprise). En arrière-plan : l'écran s'ouvre sans attendre le
          // réseau (le mode standard reste actif tant que rien n'est chargé).
          unawaited(ModulesService.instance.chargerSilencieux());

          // 🔒 MODULE 3/17 — état d'accès du compte (activation en attente,
          // abonnement échu, compte restreint ou suspendu). Calculé AVANT le
          // routage : un compte non opérationnel ne doit pas ouvrir un écran
          // commercial après la restauration d'une session. Fail-open : toute
          // erreur laisse l'accès complet (jamais de blocage accidentel).
          final String? identifiant = uid;
          if (identifiant != null) {
            final EtatAccesAbonnement accesCompte =
                await AbonnementService.instance
                    .verifierAccesUtilisateur(identifiant);

            final String? accueilRole =
                PermissionService.instance.accueilPour(roleEffectif);

            targetRoute = accueilRole ?? '/main';

            if (!accesCompte.accesComplet &&
                targetRoute == '/main/new-sale' &&
                PermissionService.instance.peutVoir(PageAccess.dashboard)) {
              targetRoute = '/main';
            }
          } else {
            targetRoute = PermissionService.instance.accueilPour(roleEffectif) ??
                '/main';
          }
        }

        // 🚀 SYNCHRONISATION CRITIQUE (Pour Lukengu et après réinstallation)
        if (uid != null) {
          // ⚡️ Sync du profil (Nom, Rôle) EN ARRIÈRE-PLAN : l'écran d'accueil
          // s'ouvre sans attendre le réseau (le profil local est déjà chargé).
          SyncService.instance
              .syncUserProfile(uid)
              .catchError((e) => debugPrint('Sync Profile Error: $e'));

          // RÉCUPÉRATION DES DONNÉES (Produits/Ventes) depuis Supabase vers SQLite vide
          // On ne met pas 'await' ici pour que l'app s'ouvre sans attendre la fin du téléchargement
          SyncService.instance.initialDownload(uid).then((_) {
            debugPrint('✅ Synchro initiale terminée pour Lukengu');
          }).catchError(
              (e) => debugPrint('❌ Échec du téléchargement initial: $e'));
        }
      }

      _terminerDemarrage(targetRoute);
    } catch (e) {
      debugPrint('Erreur critique startup: $e');
      _terminerDemarrage('/login');
    }
  }

  /// Navigue vers l'écran cible puis révèle l'application derrière le splash
  /// (fondu de 420 ms : voir `build`).
  void _terminerDemarrage(String route) {
    appRouter.go(route);
    if (!mounted) return;
    setState(() => _pret = true);
  }

  Future<void> _checkSubscriptionInBackground(String? ownerId) async {
    if (ownerId == null) return;
    try {
      final db = await DBHelper.instance.database;
      final List<Map<String, dynamic>> subData = await db.query(
        'subscriptions',
        where: 'user_id = ? AND active = 1',
        whereArgs: [ownerId],
        orderBy: 'end_date DESC',
        limit: 1,
      );

      if (subData.isNotEmpty) {
        final endDate = DateTime.parse(subData.first['end_date']);
        if (endDate.isBefore(DateTime.now())) {
          debugPrint('Abonnement expiré pour $ownerId');
        }
      }
    } catch (e) {
      debugPrint('Erreur check sub: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageManager = Provider.of<LanguageManager>(context);
    final themeManager = Provider.of<ThemeManager>(context);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Biashara Yangu',
      themeMode: themeManager.themeMode,
      theme: _themeClair,
      darkTheme: _themeSombre,
      locale: languageManager.appLocale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr'), Locale('en'), Locale('sw')],
      routerConfig: appRouter,
      // ✨ Splash moderne : il recouvre l'application pendant le démarrage
      // (session, base, permissions…) puis disparaît en fondu pour révéler
      // l'écran cible — aucun clignotement, aucune attente inutile.
      builder: (BuildContext context, Widget? child) {
        // ♿ Accessibilité — échelle de texte choisie par l'utilisateur
        // (réglage appliqué à toute l'application, y compris les dialogues).
        final double echelleTexte =
            Provider.of<AccessibiliteManager>(context).echelle;
        final Widget? enfantAccessible = child == null
            ? null
            : MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(echelleTexte),
                ),
                child: child,
              );

        if (_splashDisparu) {
          return enfantAccessible ?? const SizedBox.shrink();
        }

        return Stack(
          children: <Widget>[
            if (enfantAccessible != null) enfantAccessible,
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _pret,
                child: AnimatedOpacity(
                  opacity: _pret ? 0 : 1,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  onEnd: () {
                    if (mounted && _pret && !_splashDisparu) {
                      setState(() => _splashDisparu = true);
                    }
                  },
                  child: const SplashScreen(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
