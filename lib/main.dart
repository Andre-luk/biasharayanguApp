import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

// Config & Utils
import 'config/app_router.dart';
import 'l10n/app_localizations.dart';
import 'utils/language_manager.dart';
import 'utils/theme_manager.dart';
import 'utils/session_manager.dart';

// Services
import 'services/supabase_service.dart';
import 'services/sync_service.dart';
import 'db_helper.dart';

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

late final SupabaseClient supabase;

void main() async {
  // 1. Initialisation des bindings et Splash Screen
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 2. Initialisation des formats de date (Fix crash PDF/Vivo Y93)
  await Future.wait([
    initializeDateFormatting('fr_FR', null),
    initializeDateFormatting('en_US', null),
    initializeDateFormatting('sw_KE', null),
  ]);

  // 3. Initialisation Supabase
  try {
    await Supabase.initialize(
      url: 'https://pqzcliibocndiyqbyddr.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBxemNsaWlib2NuZGl5cWJ5ZGRyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA1NjAxMjksImV4cCI6MjA3NjEzNjEyOX0.t5XXsrOk_AFRwm-13LYz23-Q6jyFDXEDGNo6kjRDSlM',
    );
    supabase = Supabase.instance.client;
  } catch (e) {
    debugPrint('Erreur Supabase Init: $e');
  }

  // Lancement du Realtime en arrière-plan
  SupabaseService.instance.initializeRealtime();

  // 4. Configuration Desktop
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    final windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(900, 600),
      center: true,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageManager()),
        ChangeNotifierProvider(create: (_) => ThemeManager()),
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

  @override
  void initState() {
    super.initState();
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
        DBHelper.instance.getFirstUtilisateur(),
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

        if (role == 'admin') {
          targetRoute = '/admin';
        } else {
          final localUser = uid != null ? await DBHelper.instance.getUtilisateurById(uid) : null;
          _checkSubscriptionInBackground(localUser?.parentId ?? uid);
          targetRoute = (localUser?.parentId != null) ? '/main/new-sale' : '/main';
        }

        // 🚀 SYNCHRONISATION CRITIQUE (Pour Lukengu et après réinstallation)
        if (uid != null) {
          // Sync du profil (Nom, Rôle)
          await SyncService.instance.syncUserProfile(uid).catchError((e) => debugPrint('Sync Profile Error: $e'));

          // RÉCUPÉRATION DES DONNÉES (Produits/Ventes) depuis Supabase vers SQLite vide
          // On ne met pas 'await' ici pour que l'app s'ouvre sans attendre la fin du téléchargement
          SyncService.instance.initialDownload(uid).then((_) {
            debugPrint('✅ Synchro initiale terminée pour Lukengu');
          }).catchError((e) => debugPrint('❌ Échec du téléchargement initial: $e'));
        }
      }

      FlutterNativeSplash.remove();
      appRouter.go(targetRoute);

    } catch (e) {
      debugPrint('Erreur critique startup: $e');
      FlutterNativeSplash.remove();
      appRouter.go('/login');
    }
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      locale: languageManager.appLocale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr'), Locale('en'), Locale('sw')],
      routerConfig: appRouter,
    );
  }
}