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
import 'ui/widgets/ecran_erreur_biashara.dart';
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
import 'services/espace_service.dart';
import 'services/type_activite_service.dart';
// ⚡ MODULE 23 — mode rapide / complet.
import 'services/mode_application_service.dart';
// 🪙 MODULE 18 — devises de travail (CDF/USD) et taux de conversion.
import 'services/devise_service.dart';
import 'services/permission_service.dart';
import 'services/reseau_service.dart';
import 'db_helper.dart';

import 'dart:async' show TimeoutException, unawaited;
import 'dart:ui' show PlatformDispatcher;

// `kIsWeb` : la lecture de l'URL n'a de sens que dans un navigateur.
import 'package:flutter/foundation.dart' show kIsWeb;

late final SupabaseClient supabase;

/// Chemin demandé par l'adresse du navigateur (+ À LIRE AVANT `runApp`).
///
/// ⚠️ Le routeur réécrit l'URL d'adresse en `/login` dès son initialisation :
/// il faut donc mémoriser le fragment AVANT de lancer l'application, sinon le
/// lien profond est perdu et tout le monde finit sur la même page.
String? _cheminAuDemarrage;

/// Lit le fragment de l'URL (web seulement). `null` = rien d'explicite.
String? _lireCheminUrl() {
  if (!kIsWeb) return null;
  try {
    final String fragment = Uri.base.fragment.trim();
    if (fragment.isEmpty) return null;
    final String chemin = fragment.startsWith('/') ? fragment : '/$fragment';
    if (chemin == '/') return null;
    return chemin;
  } catch (_) {
    return null;
  }
}

/// Exécute [action] en la bornant dans le temps.
///
/// Pourquoi : au démarrage, une étape réseau lente (rafraîchissement de
/// session, service de notifications, lecture du mode) retenait l'écran de
/// démarrage parfois plusieurs dizaines de secondes — l'application semblait
/// « plantée ». Ici, un dépassement est simplement journalisé : on continue
/// avec ce que l'on a, et la session se rétablit ensuite en arrière-plan.
Future<void> _avecDelai(
  Future<void> action,
  Duration limite,
  String etape,
) async {
  try {
    await action.timeout(limite);
  } on TimeoutException {
    debugPrint('⏱️ Démarrage : « $etape » a dépassé ${limite.inSeconds}s — '
        'on continue sans attendre.');
  } catch (e) {
    debugPrint('Démarrage : « $etape » ignorée ($e)');
  }
}

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
  // 0. 🔗 URL demandée : mémorisée AVANT toute initialisation (voir la note
  //    sur `_cheminAuDemarrage`), pour respecter les liens profonds du web.
  _cheminAuDemarrage = _lireCheminUrl();

  // 1. Initialisation des bindings et Splash Screen
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 🖼️ CACHE D'IMAGES — réglé une fois pour toute l'application.
  // Un catalogue riche défile vite : sans plafond explicite, Flutter vide son
  // cache très tôt et retélécharge les vignettes en revenant en arrière. Ces
  // valeurs gardent en mémoire l'équivalent de plusieurs écrans de photos,
  // sans risque pour un téléphone modeste.
  PaintingBinding.instance.imageCache
    ..maximumSize = 220
    ..maximumSizeBytes = 64 << 20; // 64 Mo

  // 🛡️ FILET DE SÉCURITÉ GLOBAL (audit final de professionnalisation).
  // Sans lui, une exception non capturée remplaçait l'écran par le panneau
  // rouge « Unhandled Exception » — illisible et donnant l'image d'une
  // application cassée. On affiche désormais un message compréhensible et on
  // journalise la cause pour le diagnostic.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🛡️ Erreur d\'interface interceptée : ${details.exception}');
  };
  ErrorWidget.builder =
      (FlutterErrorDetails details) => const EcranErreurBiashara();
  // Les erreurs asynchrones (hors arbre de widgets : appels réseau lancés en
  // arrière-plan) ne doivent plus faire planter l'application en production.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('🛡️ Erreur asynchrone non capturée : $error');
    return true;
  };

  // 2. 🚀 Préparatifs EN PARALLÈLE : formats de date (fix crash PDF/Vivo Y93)
  //    et initialisation Supabase — le lancement est ainsi plus rapide.
  //
  //    ⏱️ CHAQUE étape réseau est BORNÉE : sur une connexion lente (ou une
  //    session à rafraîchir), le splash restait affiché parfois très
  //    longtemps. Un dépassement laisse simplement l'application démarrer
  //    sans session (elle se reconnecte ensuite) au lieu de bloquer.
  await Future.wait<void>([
    initializeDateFormatting('fr_FR', null),
    initializeDateFormatting('en_US', null),
    initializeDateFormatting('sw_KE', null),
    _avecDelai(_initialiserSupabase(), const Duration(seconds: 6),
        'initialisation Supabase'),
  ]);

  // Lancement du Realtime en arrière-plan
  SupabaseService.instance.initializeRealtime();

  // 🔔 Notifications locales : initialisation + surveillance du rapport de
  // fin de journée (best-effort — jamais bloquant au démarrage).
  try {
    await _avecDelai(Future<void>(() async {
      await NotificationService.instance.initialiser();
      NotificationService.instance.demarrerSurveillanceQuotidienne();
    }), const Duration(seconds: 3), 'notifications');
  } catch (e) {
    debugPrint('Notifications désactivées : $e');
  }

  // 🧩 MODULE 16 — MULTI-ACTIVITÉS (phase A) : surveille l'entreprise active.
  // Chaque bascule d'espace recharge les modules de la nouvelle activité
  // (best-effort — un échec laisse l'application en mode standard).
  ModulesService.instance.demarrerSurveillance();
  // ⚙️ REFONTE ABONNEMENTS & DISTRIBUTION — type d'activité de l'entreprise
  // (boutique / distribution). Fail-open : tant qu'il n'est pas connu, tous
  // les écrans restent visibles.
  TypeActiviteService.instance.demarrerSurveillance();

  // ⚡ MODULE 23 — MODE RAPIDE / COMPLET : lu avant le premier rendu pour que
  // l'accueil s'affiche directement dans le bon mode.
  try {
    await _avecDelai(ModeApplicationService.instance.charger(),
        const Duration(seconds: 3), 'mode d\'application');
  } catch (e) {
    debugPrint('Mode d\'application (ignoré) : $e');
  }

  // 🪙 MODULE 18 — DEVISE : la devise appartient à l'entreprise ; chaque
  // bascule d'espace la recharge (et met à jour l'affichage global des
  // montants). Best-effort : en cas d'échec, l'application reste en CDF.
  DeviseService.instance.demarrerSurveillance();

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

      // Trace de démarrage : elle indique au support SI une session a été
      // restaurée et si une base locale existe déjà sur l'appareil. C'est
      // exactement ce qui détermine la porte d'entrée (marketplace ou espace
      // de travail), donc la première question posée lors d'un diagnostic.
      debugPrint(
        'Démarrage — session restaurée : ${savedUserId != null || supabase.auth.currentSession != null}'
        ' | utilisateur local : ${firstUser != null}'
        ' | rôle enregistré : ${role ?? "aucun"}',
      );

      final currentSession = supabase.auth.currentSession;
      String targetRoute = '/login';

      // 🔗 LIEN PROFOND (WEB) — un visiteur qui ouvre
      // `…/#/login`, `…/#/setup` ou la fiche d'une boutique ne doit pas être
      // téléporté sur le catalogue : c'est ce qui faisait croire que « la
      // page de connexion ne s'affiche pas ». On ne lit l'URL que sur le web
      // et uniquement si elle contient un chemin explicite (le lancement
      // normal, lui, part de `/login` par défaut).
      final String? cheminDemande = _cheminAuDemarrage;

      // Logique de routage intelligente
      //
      // 🛍️ MODULE 19 — « LE MARKETPLACE EST LA PORTE D'ENTRÉE »
      // La condition est volontairement fondée sur l'ÉTAT DE CONNEXION, et
      // non sur l'existence d'un compte local :
      //   • aucune session restaurée (non connecté, y compris après une
      //     déconnexion, ou premier lancement) → catalogue public /biashara ;
      //   • session restaurée → espace de travail habituel (tableau de bord).
      // Ainsi, un visiteur n'est jamais accueilli par un formulaire de
      // connexion : il découvre le catalogue, et la connexion n'est demandée
      // que pour une action privée (publier, gérer sa boutique, son compte).
      final bool sessionRestauree =
          savedUserId != null || currentSession != null;

      if (!sessionRestauree) {
        // Le lien profond explicite gagne sur la page d'accueil par défaut.
        targetRoute = cheminDemande ?? '/biashara';
      } else {
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
          final localUser = await _utilisateurLocal(uid);
          _checkSubscriptionInBackground(localUser?.parentId ?? uid);

          final RoleUtilisateur roleProfil =
              PermissionService.roleDepuisUtilisateur(localUser);
          if (roleProfil != RoleUtilisateur.inconnu) roleEffectif = roleProfil;

          await PermissionService.instance.initialiser(
            roleEffectif.code,
            forcerRechargement: true,
          );

          // 🧩 MODULE 15 — CONTEXTE D'ENTREPRISE APRÈS RESTAURATION DE SESSION.
          //
          // ⚠️ SANS CET APPEL, un simple rechargement de la page (web) ou un
          // redémarrage de l'application affichait les données de la MAUVAISE
          // entreprise : « Changer d'entreprise » disparaissait du bandeau et
          // la liste des articles montrait la boutique alors que la pharmacie
          // était active. La liste n'était chargée qu'après une CONNEXION
          // (`login_page`), jamais après la restauration d'une session.
          //
          // `initialiserContexte` publie d'abord le dernier état connu (cache
          // local, aucun réseau) puis confirme avec le serveur : l'entreprise
          // active est donc correcte même si le réseau est lent ou absent.
          await EspaceService.instance.initialiserContexte();

          // 🧩 MODULE 16 — profil de modules de l'espace actif (activité de
          // l'entreprise). En arrière-plan : l'écran s'ouvre sans attendre le
          // réseau (le mode standard reste actif tant que rien n'est chargé).
          unawaited(ModulesService.instance.chargerSilencieux());
          // ⚙️ REFONTE ABONNEMENTS & DISTRIBUTION — type d'activité de
          // l'entreprise : détermine les écrans de distribution.
          unawaited(TypeActiviteService.instance.charger());

          // 🪙 MODULE 18 — devise de travail de l'entreprise (CDF/USD) :
          // appliquée à l'affichage de TOUS les montants de l'application.
          unawaited(DeviseService.instance.chargerSilencieux());

          // 🔒 MODULE 3/17 — état d'accès du compte (activation en attente,
          // abonnement échu, compte restreint ou suspendu). Calculé AVANT le
          // routage : un compte non opérationnel ne doit pas ouvrir un écran
          // commercial après la restauration d'une session. Fail-open : toute
          // erreur laisse l'accès complet (jamais de blocage accidentel).
          final String? identifiant = uid;
          if (identifiant != null) {
            final EtatAccesAbonnement accesCompte = await AbonnementService
                .instance
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
            targetRoute =
                PermissionService.instance.accueilPour(roleEffectif) ?? '/main';
          }
        }

        // 🚀 SYNCHRONISATION CRITIQUE (Pour Lukengu et après réinstallation)
        if (uid != null) {
          // 📡 SURVEILLANCE DU RÉSEAU — dès qu'une connexion revient, la file
          // locale (ventes, produits, clients…) est poussée toute seule.
          ReseauService.instance.demarrerSurveillance();

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
      supportedLocales: const [
        // ⚠️ AUDIT FINAL — vérité de l'interface : seuls les libellés français
        // sont réellement traduits (26 clés ARB pour 3 langues). Annoncer le
        // français, l'anglais et le swahili tout en affichant la quasi-totalité
        // de l'interface en français était une promesse trompeuse. Le
        // sélecteur de langue explique désormais que les autres langues sont
        // en préparation, et une locale déjà enregistrée sur un appareil est
        // ramenée au français par Flutter (aucun plantage).
        Locale('fr'),
      ],
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
