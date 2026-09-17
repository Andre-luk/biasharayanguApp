// lib/pages/home_page.dart
//
// 🏠 ACCUEIL « PRO »
//
// Refonte moderne de l'écran d'accueil :
//   • carte « hero » en dégradé (marque) qui réunit le bonjour, le profil et
//     les ventes du jour ;
//   • actions rapides (nouvelle vente / scanner / suivi commercial) ;
//   • cartes de statistiques modernes (produits, stock, caisse, finance,
//     rapports) filtrées par les permissions du rôle (Module 4) ;
//   • squelettes de chargement animés (aucun spinner nu) ;
//   • performances : rafraîchissement temps réel « debounce », chargement des
//     statistiques groupé et throttlé, animations isolées dans des
//     RepaintBoundary.
//
// ⚠️ Tout le métier reste identique : contexte utilisateur, permissions,
// abonnement (Module 3), panier/scanner (Module 7) et statistiques locales.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/scanner_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/widgets/banniere_abonnement.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _lowStockThreshold = 5;

  /// Fenêtre minimale entre deux rechargements des statistiques : évite de
  /// marteler SQLite quand le temps réel envoie plusieurs évènements.
  static const Duration _fenetreAntiRebond = Duration(seconds: 3);

  // Variables de statistiques
  double overallTotalVentesAmount = 0.0;
  double dailyTotalVentesAmount = 0.0;
  int overallVentesCount = 0;
  int dailyVentesCount = 0;
  int produitsCount = 0;
  int _lowStockCount = 0;

  // Variables d'état utilisateur
  Utilisateur? utilisateur;
  bool _loading = true;
  String? _userId;

  bool _isCollaborator = false;
  String? _effectiveOwnerId;
  String _displayName = 'Utilisateur';
  String _parentBusinessName = '';

  // Canal pour le temps réel
  RealtimeChannel? _dashboardChannel;
  Timer? _minuteurRealtime;
  DateTime? _dernierChargementStats;

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  @override
  void dispose() {
    _minuteurRealtime?.cancel();
    if (_dashboardChannel != null) {
      Supabase.instance.client.removeChannel(_dashboardChannel!);
    }
    super.dispose();
  }

  Future<void> _initialLoad() async {
    if (mounted) setState(() => _loading = true);
    await _loadUserContext();
    await _loadStats(force: true);
    if (mounted) setState(() => _loading = false);
  }

  /// Active l'écoute en temps réel pour mettre à jour l'interface automatiquement.
  ///
  /// Les évènements sont regroupés (`_fenetreAntiRebond`) : une salve de
  /// modifications ne déclenche qu'un seul recalcul des statistiques.
  void _startRealtimeDashboard() {
    if (_effectiveOwnerId == null || _dashboardChannel != null) return;

    _dashboardChannel = Supabase.instance.client
        .channel('dashboard-updates')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'ventes',
      callback: (payload) => _planifierRechargementStats(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'produits',
      callback: (payload) => _planifierRechargementStats(),
    )
        .subscribe();
  }

  void _planifierRechargementStats() {
    _minuteurRealtime?.cancel();
    _minuteurRealtime = Timer(
      const Duration(milliseconds: 900),
      () => _loadStats(),
    );
  }

  Future<void> _loadUserContext() async {
    final uid = await SessionManager.getUserId();
    if (uid == null) {
      if (mounted) context.go('/login');
      return;
    }

    _userId = uid;
    final db = DBHelper.instance;

    try {
      // 1. Chargement instantané depuis SQLite
      final localUser = await db.getUtilisateurById(uid);
      _updateUserInfo(localUser);
      await _fetchParentNameIfNeeded(localUser, db);

      // 2. Synchronisation en arrière-plan avec Supabase
      SupabaseService.instance.getUtilisateurData(uid).then((remoteUser) async {
        if (remoteUser != null) {
          await db.updateUtilisateur(remoteUser);
          if (mounted) {
            _updateUserInfo(remoteUser);
            await _fetchParentNameIfNeeded(remoteUser, db);
            _startRealtimeDashboard();
          }
        }
      }).catchError((e) {
        debugPrint('HomePage: Erreur de sync utilisateur - $e');
      });
    } catch (e) {
      debugPrint('HomePage: Erreur lors du chargement du contexte: $e');
    }
  }

  void _updateUserInfo(Utilisateur? u) {
    if (u == null) return;
    setState(() {
      utilisateur = u;
      _isCollaborator = u.parentId != null && u.parentId!.isNotEmpty;
      _effectiveOwnerId = _isCollaborator ? u.parentId : u.id;
      _displayName = u.nom.isNotEmpty
          ? u.nom
          : (u.email.isNotEmpty ? u.email : 'Utilisateur');
    });
  }

  /// Récupère le nom du patron, même si SQLite est vide sur le nouveau téléphone
  Future<void> _fetchParentNameIfNeeded(Utilisateur? u, DBHelper db) async {
    if (u != null && u.parentId != null && u.parentId!.isNotEmpty) {
      // On cherche d'abord dans SQLite
      Utilisateur? boss = await db.getUtilisateurById(u.parentId!);

      // S'il n'est pas dans SQLite (ex: téléphone tout neuf du collaborateur),
      // on le télécharge depuis Supabase de force.
      if (boss == null) {
        try {
          final remoteBoss =
              await SupabaseService.instance.getUtilisateurData(u.parentId!);
          if (remoteBoss != null) {
            await db.insertUtilisateur(remoteBoss);
            boss = remoteBoss;
          }
        } catch (e) {
          debugPrint('Erreur récupération du boss via Supabase: $e');
        }
      }

      if (mounted && boss != null) {
        final bossInstance = boss;
        if (bossInstance.nom.isNotEmpty) {
          setState(() => _parentBusinessName = bossInstance.nom);
        }
      }
    }
  }

  Future<void> _loadStats({bool force = false}) async {
    if (_userId == null || _effectiveOwnerId == null) return;

    // Anti-rebond : inutile de relire SQLite plusieurs fois par seconde.
    final DateTime maintenant = DateTime.now();
    if (!force &&
        _dernierChargementStats != null &&
        maintenant.difference(_dernierChargementStats!) < _fenetreAntiRebond) {
      return;
    }
    _dernierChargementStats = maintenant;

    final db = DBHelper.instance;

    try {
      final String statsTargetId = _userId!;

      // Une seule passe parallèle : six requêtes SQLite en même temps.
      final results = await Future.wait([
        db.getTotalVentesAmountForUser(statsTargetId),
        db.getTotalVentesAmountForUserToday(statsTargetId),
        db.getVentesCountForUser(statsTargetId),
        db.getVentesCountForUserToday(statsTargetId),
        db.getProduitsCountForUser(_effectiveOwnerId!),
        db.countLowStockProducts(
          ownerId: _effectiveOwnerId!,
          threshold: _lowStockThreshold,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        overallTotalVentesAmount = (results[0] as num?)?.toDouble() ?? 0.0;
        dailyTotalVentesAmount = (results[1] as num?)?.toDouble() ?? 0.0;
        overallVentesCount = results[2] as int;
        dailyVentesCount = results[3] as int;
        produitsCount = results[4] as int;
        _lowStockCount = results[5] as int;
      });
    } catch (e) {
      debugPrint('HomePage: Erreur lors du chargement des stats: $e');
    }
  }

  Future<void> _logout() async {
    await SessionManager.clearSession();
    AbonnementService.instance.reinitialiserAcces();
    // 🔳 MODULE 7 — la session de vente se termine : le panier partagé et
    // l'historique du scanner ne doivent pas survivre à la déconnexion.
    PanierService.instance.vider();
    ScannerService.instance.viderHistorique();
    if (!mounted) return;
    context.go('/login');
  }

  /// Chemins réservés aux fonctionnalités commerciales : bloqués lorsque
  /// l'abonnement de l'entreprise est échu (lecture seule, Module 3).
  static const List<String> _cheminsCommerciaux = <String>[
    '/main/new-sale',
    '/main/add-product',
    '/main/edit-product',
    // 🗂️ MODULE 5 — créer un article est une écriture commerciale ; la
    // consultation du catalogue reste, elle, toujours possible.
    '/main/articles/new',
    '/main/commercial',
    // 💰 MODULE 10 — seules les ÉCRITURES de la finance sont bloquées en
    // lecture seule : consulter la caisse, les dépenses et les dettes reste
    // possible (la clôture, elle, est une validation).
    '/main/depenses/new',
    '/main/dettes/new',
    '/main/caisse/cloture',
    '/main/clients',
    '/main/inventaires',
    // 🏬 MODULE 9 — les écritures de stock (entrée, ajustement, clôture)
    // sont bloquées en lecture seule ; la consultation du stock reste ouverte.
    '/main/stock/approvisionnement',
    '/main/stock/ajustement',
    '/main/stock/inventaire',
  ];

  Future<void> _navTo(String path) async {
    if (_isCollaborator) {
      // 🔳 MODULE 7 — le vendeur (collaborateur) a le droit d'ouvrir
      // directement le scanner : c'est son outil de travail.
      final allowed = path == '/main/new-sale' ||
          path == '/scanner' ||
          path == '/login' ||
          path == '/setup' ||
          path == '/';
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Accès non autorisé.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // 🔒 MODULE 3 — Abonnement échu : accès en lecture seule.
    // Les fonctionnalités commerciales sont bloquées ; la consultation
    // (tableau de bord, rapports, stock) reste possible.
    if (AbonnementService.instance.lectureSeule &&
        _cheminsCommerciaux.contains(path)) {
      afficherDialogueLectureSeule(context);
      return;
    }

    context.go(path);

    if (path.contains('new-sale') ||
        path.contains('stock') ||
        path.contains('add-product') ||
        path.contains('commercial')) {
      await _loadStats();
    }
  }

  ImageProvider _getAvatarImage() {
    final avatarPath = utilisateur?.avatar;
    if (avatarPath != null && avatarPath.isNotEmpty) {
      if (avatarPath.startsWith('http')) {
        return NetworkImage(avatarPath);
      } else {
        final file = File(avatarPath);
        if (file.existsSync()) {
          return FileImage(file);
        }
      }
    }
    return const AssetImage('assets/utilisateur.jpg');
  }

  // ==========================================================================
  //  BARRE SUPÉRIEURE
  // ==========================================================================

  PreferredSizeWidget _buildAppBar(AppLocalizations T) {
    final ThemeData theme = Theme.of(context);

    return AppBar(
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: AppDegrades.primaire,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/Biashara_app_off-.png',
                height: 26,
                width: 26,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Biashara Yangu',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _isCollaborator && _parentBusinessName.isNotEmpty
                      ? _parentBusinessName.toUpperCase()
                      : 'Espace entreprise',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded),
          tooltip: T.logoutButton,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ==========================================================================
  //  BLOCS DE L'ÉCRAN
  // ==========================================================================

  /// Carte « hero » : profil + ventes du jour sur un dégradé de marque.
  Widget _buildCarteHero(AppLocalizations T) {
    final String montantJour =
        '${dailyTotalVentesAmount.toStringAsFixed(0)} ${T.currencyUnit}';

    return _CarteHero(
      sousTitre: T.homeSummaryGreeting(_displayName),
      isCollaborator: _isCollaborator,
      nomBoutique: _parentBusinessName,
      montantJour: montantJour,
      libelleJour: T.statDailySales.toUpperCase(),
      nbVentesJour: '$dailyVentesCount ${T.statSalesCount.toLowerCase()}',
      avatar: _getAvatarImage(),
    );
  }

  Widget _buildActionsRapides(AppLocalizations T) {
    final PermissionService permissions = PermissionService.instance;

    return Row(
      children: [
        Expanded(
          child: _ActionRapide(
            libelle: T.buttonNewSale,
            icone: Icons.point_of_sale_rounded,
            degrade: AppDegrades.hero,
            couleurTexte: Colors.white,
            onTap: () => _navTo('/main/new-sale'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: permissions.peutVoir(PageAccess.scanner)
              ? _ActionRapide(
                  libelle: 'Scanner',
                  icone: Icons.qr_code_scanner_rounded,
                  degrade: AppDegrades.accent,
                  couleurTexte: Colors.white,
                  onTap: () => _navTo('/scanner'),
                )
              : _ActionRapide(
                  libelle: 'Suivi commercial',
                  icone: Icons.insights_rounded,
                  couleur: Theme.of(context).colorScheme.surface,
                  couleurTexte: Theme.of(context).colorScheme.primary,
                  bordure: Theme.of(context).colorScheme.outlineVariant,
                  onTap: () => _navTo('/main/commercial'),
                ),
        ),
      ],
    );
  }

  Widget _buildSectionStatistiques(AppLocalizations T) {
    final PermissionService permissions = PermissionService.instance;
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: AppDegrades.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                T.statisticsTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.28,
          children: [
            // 🔐 MODULE 4 — chaque carte suit les permissions du rôle : un
            // caissier (vendeur) ne voit ni le catalogue ni le stock (sinon
            // le middleware le renverrait sur son écran de vente).
            if (permissions.peutVoir(PageAccess.articles))
              _CarteStat(
                titre: T.statProductsCount,
                valeur: '$produitsCount',
                icone: Icons.inventory_2_rounded,
                couleur: const Color(0xFF2563EB),
                // 🗂️ MODULE 5 — la carte « Produits » ouvre la liste des
                // articles (catalogue + conditionnements), qui gère aussi la
                // création.
                onTap: () => _navTo('/main/articles'),
              ),
            if (permissions.peutVoir(PageAccess.stock))
              _CarteStat(
                titre: T.statStockStatus,
                valeur: '$_lowStockCount',
                icone: Icons.warning_amber_rounded,
                couleur: const Color(0xFFF59E0B),
                alerte: _lowStockCount > 0,
                onTap: () => _navTo('/main/stock'),
              ),
            // 💰 MODULE 10 — caisse et tableau de bord financier.
            if (permissions.peutVoir(PageAccess.caisse))
              _CarteStat(
                titre: 'Solde & clôture',
                valeur: 'Caisse',
                icone: Icons.account_balance_wallet_rounded,
                couleur: const Color(0xFF0D9488),
                onTap: () => _navTo('/main/caisse'),
              ),
            if (permissions.peutVoir(PageAccess.finance))
              _CarteStat(
                titre: 'CA & bénéfice',
                valeur: 'Finance',
                icone: Icons.insights_rounded,
                couleur: const Color(0xFF7C3AED),
                onTap: () => _navTo('/main/finance'),
              ),
            // 📊 MODULE 11 — rapports & exports (PDF / Excel signés).
            if (permissions.peutVoir(PageAccess.rapports))
              _CarteStat(
                titre: 'Rapports & exports',
                valeur: 'Rapports',
                icone: Icons.bar_chart_rounded,
                couleur: const Color(0xFF8B5E34),
                onTap: () => _navTo('/main/rapports'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionsSecondaires(AppLocalizations T) {
    final PermissionService permissions = PermissionService.instance;

    // 🔐 MODULE 4 — « Ajouter un produit » exige la création d'articles ;
    // « Collaborateurs » est réservé aux rôles qui gèrent l'équipe (patron).
    // Sans ces droits, les boutons disparaissent (fini les clics qui
    // renvoyaient silencieusement vers l'écran de vente).
    final bool peutAjouterProduit =
        permissions.peut(PageAccess.articles, ActionAccess.creer);
    final bool peutGererCollaborateurs =
        permissions.peutVoir(PageAccess.collaborateurs);

    if (!peutAjouterProduit && !peutGererCollaborateurs) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (peutAjouterProduit)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _navTo('/main/add-product'),
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: Text(T.buttonAddProduct),
            ),
          ),
        if (peutAjouterProduit && peutGererCollaborateurs)
          const SizedBox(width: 12),
        if (peutGererCollaborateurs)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _navTo('/settings/manage-users'),
              icon: const Icon(Icons.group_outlined),
              label: const Text('Collaborateurs'),
            ),
          ),
      ],
    );
  }

  /// Squelettes affichés pendant le tout premier chargement : la page paraît
  /// déjà « en place », seule la donnée manque (perception de rapidité).
  Widget _buildChargement() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        SquelettePulse(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 190,
                decoration: BoxDecoration(
                  color: AppCouleurs.marine.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: const [
                  Expanded(child: Squelette(hauteur: 56, rayon: 18)),
                  SizedBox(width: 12),
                  Expanded(child: Squelette(hauteur: 56, rayon: 18)),
                ],
              ),
              const SizedBox(height: 28),
              const Squelette(largeur: 140, hauteur: 18),
              const SizedBox(height: 16),
              Row(
                children: const [
                  Expanded(child: Squelette(hauteur: 120, rayon: 20)),
                  SizedBox(width: 12),
                  Expanded(child: Squelette(hauteur: 120, rayon: 20)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Expanded(child: Squelette(hauteur: 120, rayon: 20)),
                  SizedBox(width: 12),
                  Expanded(child: Squelette(hauteur: 120, rayon: 20)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations T = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: _buildAppBar(T),
      body: RefreshIndicator(
        onRefresh: _initialLoad,
        edgeOffset: 90,
        color: Theme.of(context).colorScheme.primary,
        child: _loading
            ? _buildChargement()
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _Apparition(
                    delai: 0,
                    child: _buildCarteHero(T),
                  ),
                  const SizedBox(height: 20),
                  _Apparition(
                    delai: 1,
                    child: _buildActionsRapides(T),
                  ),
                  if (!_isCollaborator) ...[
                    const SizedBox(height: 28),
                    _Apparition(
                      delai: 2,
                      child: _buildSectionStatistiques(T),
                    ),
                    const SizedBox(height: 28),
                    _Apparition(
                      delai: 3,
                      child: _buildActionsSecondaires(T),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

// ============================================================================
//  COMPOSANTS PRIVÉS DE L'ACCUEIL
// ============================================================================

/// Carte principale en dégradé : bonjour + profil + ventes du jour.
class _CarteHero extends StatelessWidget {
  const _CarteHero({
    required this.sousTitre,
    required this.isCollaborator,
    required this.nomBoutique,
    required this.montantJour,
    required this.libelleJour,
    required this.nbVentesJour,
    required this.avatar,
  });

  final String sousTitre;
  final bool isCollaborator;
  final String nomBoutique;
  final String montantJour;
  final String libelleJour;
  final String nbVentesJour;
  final ImageProvider avatar;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          gradient: AppDegrades.hero,
          borderRadius: BorderRadius.circular(28),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppCouleurs.marine.withValues(alpha: 0.30),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: <Widget>[
              // Cercles décoratifs (aucun coût : pas d'image à décoder).
              Positioned(
                right: -50,
                top: -60,
                child: _CercleDeco(
                  taille: 170,
                  couleur: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              Positioned(
                right: 60,
                bottom: -80,
                child: _CercleDeco(
                  taille: 140,
                  couleur: AppCouleurs.orange.withValues(alpha: 0.14),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 23,
                            backgroundImage: avatar,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                sousTitre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              if (isCollaborator) ...<Widget>[
                                const SizedBox(height: 6),
                                _Pastille(
                                  icone: Icons.storefront_rounded,
                                  texte:
                                      'Collaborateur • ${nomBoutique.isNotEmpty ? nomBoutique.toUpperCase() : 'BOUTIQUE'}',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Divider(
                      color: Colors.white.withValues(alpha: 0.14),
                      height: 1,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      libelleJour,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            montantJour,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.trending_up_rounded,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Pastille(icone: Icons.receipt_long_rounded, texte: nbVentesJour),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pastille translucide (texte blanc sur fond clair).
class _Pastille extends StatelessWidget {
  const _Pastille({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icone, size: 13, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texte,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton d'action rapide (dégradé ou fond plein) avec effet d'appui.
class _ActionRapide extends StatelessWidget {
  const _ActionRapide({
    required this.libelle,
    required this.icone,
    required this.onTap,
    this.degrade,
    this.couleur,
    this.couleurTexte = Colors.white,
    this.bordure,
  });

  final String libelle;
  final IconData icone;
  final VoidCallback onTap;
  final Gradient? degrade;
  final Color? couleur;
  final Color couleurTexte;
  final Color? bordure;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: degrade,
            color: degrade == null ? couleur : null,
            borderRadius: BorderRadius.circular(18),
            border: bordure == null ? null : Border.all(color: bordure!),
            boxShadow: degrade == null
                ? null
                : <BoxShadow>[
                    BoxShadow(
                      color: AppCouleurs.marine.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Row(
              children: <Widget>[
                Icon(icone, color: couleurTexte, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    libelle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: couleurTexte,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: couleurTexte.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte de statistique moderne (icône teintée, valeur, libellé, chevron).
class _CarteStat extends StatelessWidget {
  const _CarteStat({
    required this.titre,
    required this.valeur,
    required this.icone,
    required this.couleur,
    required this.onTap,
    this.alerte = false,
  });

  final String titre;
  final String valeur;
  final IconData icone;
  final Color couleur;
  final VoidCallback onTap;
  final bool alerte;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: alerte
                  ? AppCouleurs.alerte.withValues(alpha: 0.55)
                  : scheme.outlineVariant,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: couleur.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icone, color: couleur, size: 22),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  valeur,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: alerte ? AppCouleurs.alerte : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cercle décoratif translucide utilisé par la carte hero.
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

/// Apparition douce (fondu + léger glissement) des sections au chargement.
///
/// L'animation ne rejoue pas lors des rafraîchissements : elle est jouée une
/// fois, puis le widget se contente de se reconstruire.
class _Apparition extends StatefulWidget {
  const _Apparition({required this.child, this.delai = 0});

  final Widget child;
  final int delai;

  @override
  State<_Apparition> createState() => _ApparitionState();
}

class _ApparitionState extends State<_Apparition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controleur = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  late final Animation<double> _fondu = CurvedAnimation(
    parent: _controleur,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _glissement = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controleur, curve: Curves.easeOutCubic));

  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    if (widget.delai <= 0) {
      _controleur.forward();
    } else {
      _minuteur = Timer(
        Duration(milliseconds: 70 * widget.delai),
        () {
          if (mounted) _controleur.forward();
        },
      );
    }
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fondu,
      child: SlideTransition(position: _glissement, child: widget.child),
    );
  }
}
