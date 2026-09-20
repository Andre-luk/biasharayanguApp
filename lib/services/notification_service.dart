// lib/services/notification_service.dart
//
// 🔔 NOTIFICATIONS LOCALES — « chaque vente » + « rapport de fin de journée ».
//
//   • notifierVente() : affichée après CHAQUE vente confirmée par le serveur
//     (appelée par VenteService — best-effort, jamais bloquante) ;
//   • rapport de fin de journée : un résumé (nombre de ventes, chiffre
//     d'affaires, articles vendus) est envoyé à l'heure choisie (19 h 00 par
//     défaut) tant que l'application est ouverte (surveillance chaque minute)
//     + rattrapage immédiat à l'ouverture si l'heure est passée et que le
//     rapport du jour n'a pas encore été envoyé.
//
//  Préférences par appareil : activables/désactivables dans Paramètres →
//  Notifications. Plateformes prises en charge : Android, iOS, Linux.
//  (Windows : silencieusement ignoré pour l'instant.)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/services/espace_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

/// Résumé des ventes d'une journée (rapport de fin de journée).
class ResumeVentesJour {
  const ResumeVentesJour({
    required this.ca,
    required this.nbVentes,
    required this.nbArticles,
  });

  /// Chiffre d'affaires de la journée (CDF).
  final double ca;

  /// Nombre de ventes (un panier = une vente).
  final int nbVentes;

  /// Unités de base vendues (articles).
  final int nbArticles;

  bool get estVide => nbVentes <= 0;
}

/// Service des notifications locales (singleton).
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const int _idRapport = 424242;
  static const String _canalVentes = 'biashara_ventes';
  static const String _canalRapport = 'biashara_rapport';
  static const String _prefVentes = 'notifications_ventes_actives';
  static const String _prefRapport = 'notifications_rapport_actif';
  static const String _prefHeure = 'notifications_rapport_heure';
  static const String _prefDernierJour = 'notifications_rapport_dernier_jour';

  /// Heure par défaut du rapport : 19 h 00 (minutes depuis minuit).
  static const int heureRapportParDefaut = 19 * 60;

  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialise = false;
  bool _supporte = false;
  Timer? _surveillance;

  SharedPreferences? _prefs;
  bool _ventesActives = true;
  bool _rapportActif = true;
  int _heureRapportMinutes = heureRapportParDefaut;

  // ── Lectures (synchrones après [initialiser]) ────────────────────────────

  bool get ventesActives => _ventesActives;
  bool get rapportActif => _rapportActif;
  int get heureRapportMinutes => _heureRapportMinutes;
  bool get supporte => _supporte;

  /// « 19:00 » à partir de minutes depuis minuit.
  static String libelleHeure(int minutes) {
    final int h = (minutes ~/ 60) % 24;
    final int m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Clé de jour « AAAA-MM-JJ » (anti-doublon du rapport quotidien).
  static String cleJour(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Titre de la notification de vente.
  static String titreVente(String numero) {
    final String ref = numero.trim();
    return ref.isEmpty ? '💰 Vente enregistrée' : '💰 Vente $ref';
  }

  /// Corps de la notification de vente :
  /// « VTE-…-0007 • 11 500 CDF (2 articles) • especes ».
  static String messageVente({
    required String numero,
    required double total,
    required int nbArticles,
    String? modePaiement,
  }) {
    final String articles = '$nbArticles article${nbArticles > 1 ? 's' : ''}';
    final String mode = (modePaiement ?? '').trim();
    final String ref =
        numero.trim().isEmpty ? 'Vente encaissée' : numero.trim();
    return '$ref • ${formatMontant(total)} ($articles)'
        '${mode.isEmpty ? '' : ' • $mode'}';
  }

  /// Titre du rapport quotidien : « 📊 Rapport du jour — 18/09/2026 ».
  static String titreRapport(DateTime jour) {
    return '📊 Rapport du jour — '
        '${jour.day.toString().padLeft(2, '0')}/'
        '${jour.month.toString().padLeft(2, '0')}/${jour.year}';
  }

  /// Corps du rapport quotidien.
  ///
  /// 🧩 MODULE 16 C1 — [produitsExpires] / [produitsProches] ajoutent la
  /// ligne « 💊 Expirations » (pharmacie) quand des dates existent.
  static String messageRapport(
    ResumeVentesJour resume,
    DateTime jour, {
    int? produitsExpires,
    int? produitsProches,
  }) {
    final StringBuffer tampon = StringBuffer();

    if (resume.estVide) {
      tampon.write('Aucune vente enregistrée aujourd\'hui.');
    } else {
      final String articles = resume.nbArticles > 1 ? 'articles' : 'article';
      tampon.write('Ventes : ${resume.nbVentes} • '
          'Chiffre d\'affaires : ${formatMontant(resume.ca)} • '
          '$articles vendus : ${resume.nbArticles}');
    }

    final int expires = produitsExpires ?? 0;
    final int proches = produitsProches ?? 0;
    if (expires > 0 || proches > 0) {
      final List<String> parts = <String>[
        if (expires > 0) '$expires expiré${expires > 1 ? 's' : ''}',
        if (proches > 0) '$proches bientôt (≤ 30 j)',
      ];
      tampon.write('\n💊 Expirations : ${parts.join(' • ')}');
    }

    return tampon.toString();
  }

  /// Le rapport du jour doit-il être envoyé maintenant ?
  /// Oui si l'heure est atteinte ET qu'aucun rapport n'a été envoyé aujourd'hui.
  static bool doitEnvoyerRapport({
    required DateTime maintenant,
    required int heureMinutes,
    required String? dernierEnvoi,
  }) {
    final int actuel = maintenant.hour * 60 + maintenant.minute;
    if (actuel < heureMinutes) return false;
    return dernierEnvoi != cleJour(maintenant);
  }

  // ── Initialisation ───────────────────────────────────────────────────────

  /// Initialise le greffon et recharge les préférences. Idempotent,
  /// best-effort : un échec laisse simplement le service inactif.
  Future<void> initialiser() async {
    if (_initialise) return;
    _initialise = true;

    try {
      _prefs = await SharedPreferences.getInstance();
      _ventesActives = _prefs!.getBool(_prefVentes) ?? true;
      _rapportActif = _prefs!.getBool(_prefRapport) ?? true;
      _heureRapportMinutes =
          _prefs!.getInt(_prefHeure) ?? heureRapportParDefaut;
    } catch (e) {
      debugPrint('NotificationService (préférences) : $e');
    }

    _supporte = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (!_supporte) {
      debugPrint(
          'NotificationService : plateforme sans notifications locales.');
      return;
    }

    try {
      final FlutterLocalNotificationsPlugin plugin =
          FlutterLocalNotificationsPlugin();
      const InitializationSettings settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        linux: LinuxInitializationSettings(defaultActionName: 'Ouvrir'),
      );
      await plugin.initialize(settings: settings);
      _plugin = plugin;
    } catch (e) {
      debugPrint('NotificationService (init) : $e');
      _supporte = false;
    }
  }

  /// Demande la permission de notifier (Android 13+ / iOS).
  Future<void> demanderPermissions() async {
    if (!_supporte) return;
    try {
      await _plugin
          ?.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          ?.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('NotificationService (permission) : $e');
    }
  }

  // ── Préférences ──────────────────────────────────────────────────────────

  Future<void> definirVentesActives(bool actif) async {
    _ventesActives = actif;
    if (actif) await demanderPermissions();
    try {
      await _prefs?.setBool(_prefVentes, actif);
    } catch (_) {}
  }

  Future<void> definirRapportActif(bool actif) async {
    _rapportActif = actif;
    if (actif) await demanderPermissions();
    try {
      await _prefs?.setBool(_prefRapport, actif);
    } catch (_) {}
  }

  Future<void> definirHeureRapport(int minutes) async {
    _heureRapportMinutes = minutes.clamp(0, 1439);
    try {
      await _prefs?.setInt(_prefHeure, _heureRapportMinutes);
    } catch (_) {}
  }

  // ── Affichage ────────────────────────────────────────────────────────────

  NotificationDetails _details(
      String canalId, String canalNom, String description) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        canalId,
        canalNom,
        channelDescription: description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
      linux: const LinuxNotificationDetails(),
    );
  }

  /// 🔔 Notification « chaque vente » (après confirmation serveur).
  Future<void> notifierVente({
    required String numero,
    required double total,
    required int nbArticles,
    String? modePaiement,
  }) async {
    if (!_supporte || !_ventesActives) return;
    try {
      await _plugin?.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title: titreVente(numero),
        body: messageVente(
          numero: numero,
          total: total,
          nbArticles: nbArticles,
          modePaiement: modePaiement,
        ),
        notificationDetails:
            _details(_canalVentes, 'Ventes', 'Alerte à chaque vente encaissée'),
      );
    } catch (e) {
      debugPrint('NotificationService (vente) : $e');
    }
  }

  /// 📊 Vérifie l'heure et envoie le rapport du jour si nécessaire.
  ///
  /// [forcer] : ignoré les horaires (bouton « tester maintenant ») mais pas
  /// l'anti-doublon du jour.
  Future<void> verifierEtEnvoyerRapportDuJour({bool forcer = false}) async {
    if (!_supporte) return;
    if (!forcer && !_rapportActif) return;

    final DateTime maintenant = DateTime.now();
    final String? dernier = _prefs?.getString(_prefDernierJour);
    if (!forcer &&
        !doitEnvoyerRapport(
          maintenant: maintenant,
          heureMinutes: _heureRapportMinutes,
          dernierEnvoi: dernier,
        )) {
      return;
    }

    final ResumeVentesJour? resume = await resumeDuJour();
    if (resume == null) return; // réseau indisponible → nouvel essai ensuite

    // 🧩 MODULE 16 C1 — pharmacie : compteurs d'expiration (best-effort ;
    // (0, 0) en cas d'échec — le rapport du soir reste envoyé).
    final (int expires, int proches) = await compterExpirations();

    try {
      await _plugin?.show(
        id: _idRapport,
        title: titreRapport(maintenant),
        body: messageRapport(resume, maintenant,
            produitsExpires: expires, produitsProches: proches),
        notificationDetails: _details(_canalRapport,
            'Rapport de fin de journée', 'Résumé des ventes du jour'),
      );
      await _prefs?.setString(_prefDernierJour, cleJour(maintenant));
    } catch (e) {
      debugPrint('NotificationService (rapport) : $e');
    }
  }

  /// Ventes du jour de la boutique active. `null` si indisponible (hors ligne
  /// ou pas d'utilisateur) — le rapport sera retenté plus tard.
  Future<ResumeVentesJour?> resumeDuJour() async {
    try {
      final String? proprietaire = await _proprietaireActif();
      if (proprietaire == null || proprietaire.isEmpty) return null;

      final DateTime maintenant = DateTime.now();
      final DateTime debutLocal =
          DateTime(maintenant.year, maintenant.month, maintenant.day);
      final DateTime finLocale = debutLocal.add(const Duration(days: 1));

      final dynamic reponse = await SupabaseService.instance.client
          .from('ventes')
          .select('prix, quantite, vente_uuid, id')
          .eq('owner_id', proprietaire)
          .gte('date', debutLocal.toUtc().toIso8601String())
          .lt('date', finLocale.toUtc().toIso8601String());

      final List<dynamic> lignes =
          (reponse as List<dynamic>?) ?? const <dynamic>[];
      double ca = 0;
      int quantite = 0;
      final Set<String> ventes = <String>{};

      for (final dynamic brut in lignes) {
        final Map<String, dynamic> ligne =
            Map<String, dynamic>.from(brut as Map<dynamic, dynamic>);
        ca += parseDouble(ligne['prix']);
        quantite += parseDouble(ligne['quantite']).round();
        final String? uuid = parseStringOrNull(ligne['vente_uuid']);
        ventes
            .add((uuid != null && uuid.isNotEmpty) ? uuid : 'L${ligne['id']}');
      }

      return ResumeVentesJour(
        ca: ca,
        nbVentes: ventes.length,
        nbArticles: quantite,
      );
    } catch (e) {
      debugPrint('NotificationService (résumé du jour) : $e');
      return null;
    }
  }

  /// 🧩 MODULE 16 C1 — compteurs d'expiration des articles (déjà expirés,
  /// bientôt périmés ≤ 30 j). Best-effort : (0, 0) en cas d'échec.
  Future<(int, int)> compterExpirations() async {
    try {
      final String? proprietaire = await _proprietaireActif();
      if (proprietaire == null || proprietaire.isEmpty) return (0, 0);

      final dynamic reponse = await SupabaseService.instance.client
          .from('produits')
          .select('date_expiration')
          .eq('owner_id', proprietaire)
          .not('date_expiration', 'is', null);

      final List<dynamic> lignes =
          (reponse as List<dynamic>?) ?? const <dynamic>[];
      final DateTime maintenant = DateTime.now();
      final DateTime reference =
          DateTime(maintenant.year, maintenant.month, maintenant.day);

      int expires = 0;
      int proches = 0;
      for (final dynamic brut in lignes) {
        final Map<String, dynamic> ligne =
            Map<String, dynamic>.from(brut as Map<dynamic, dynamic>);
        final DateTime? date = parseDateTimeOrNull(ligne['date_expiration']);
        if (date == null) continue;

        final DateTime jour = DateTime(date.year, date.month, date.day);
        if (jour.isBefore(reference)) {
          expires++;
        } else if (jour.difference(reference).inDays <= 30) {
          proches++;
        }
      }
      return (expires, proches);
    } catch (e) {
      debugPrint('NotificationService (expirations) : $e');
      return (0, 0);
    }
  }

  /// Espace (entreprise) actif, repli sur le patron historique.
  Future<String?> _proprietaireActif() async {
    try {
      final String? espace = EspaceService.instance.etat.value?.actifId;
      if (espace != null && espace.isNotEmpty) return espace;
    } catch (_) {}

    final String? uid = await SessionManager.getUserId();
    if (uid == null || uid.isEmpty) return null;

    try {
      final dynamic utilisateur =
          await DBHelper.instance.getUtilisateurById(uid);
      final String? parent = utilisateur?.parentId as String?;
      if (parent != null && parent.isNotEmpty) return parent;
    } catch (_) {}
    return uid;
  }

  /// 🕐 Surveillance (application ouverte) : vérifie chaque minute si le
  /// rapport du jour doit partir. Démarre aussi un rattrapage immédiat.
  void demarrerSurveillanceQuotidienne() {
    if (!_supporte) return;
    _surveillance ??= Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(verifierEtEnvoyerRapportDuJour());
    });
    unawaited(verifierEtEnvoyerRapportDuJour());
  }

  void arreterSurveillance() {
    _surveillance?.cancel();
    _surveillance = null;
  }
}
