// lib/pages/home_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _lowStockThreshold = 5;

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

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  @override
  void dispose() {
    if (_dashboardChannel != null) {
      Supabase.instance.client.removeChannel(_dashboardChannel!);
    }
    super.dispose();
  }

  Future<void> _initialLoad() async {
    setState(() => _loading = true);
    await _loadUserContext();
    await _loadStats();
    if (mounted) setState(() => _loading = false);
  }

  /// Active l'écoute en temps réel pour mettre à jour l'interface automatiquement
  void _startRealtimeDashboard() {
    if (_effectiveOwnerId == null || _dashboardChannel != null) return;

    _dashboardChannel = Supabase.instance.client
        .channel('dashboard-updates')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'ventes',
      callback: (payload) {
        if (mounted) _loadStats();
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'produits',
      callback: (payload) {
        if (mounted) _loadStats();
      },
    )
        .subscribe();
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
      _displayName = u.nom.isNotEmpty ? u.nom : (u.email ?? 'Utilisateur');
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

  Future<void> _loadStats() async {
    if (_userId == null || _effectiveOwnerId == null) return;
    final db = DBHelper.instance;

    try {
      final String statsTargetId = _userId!;

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
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _navTo(String path) async {
    if (_isCollaborator) {
      final allowed =
          path == '/main/new-sale' || path == '/login' || path == '/setup' || path == '/';
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

    context.go(path);

    if (path.contains('new-sale') ||
        path.contains('stock') ||
        path.contains('add-product') ||
        path.contains('commercial')) {
      await _loadStats();
    }
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations T) {
    final theme = Theme.of(context);

    return AppBar(
      backgroundColor: theme.colorScheme.surface,
      elevation: 0,
      surfaceTintColor: theme.colorScheme.surface,
      centerTitle: false,
      title: Row(
        children: [
          Hero(
            tag: 'app_logo',
            child: Image.asset(
              'assets/Biashara_app_off-.png',
              height: 40,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Biashara Yangu',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

  Widget _buildWelcomeHeader(AppLocalizations T) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          child: CircleAvatar(
            radius: 24,
            backgroundImage: _getAvatarImage(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                T.homeWelcomeMessage(''),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                _displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isCollaborator) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.storefront_rounded,
                        size: 14,
                        color:
                        Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Collaborateur • ${_parentBusinessName.isNotEmpty ? _parentBusinessName.toUpperCase() : 'Boutique'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDailySalesHero(AppLocalizations T, String amountFormatted) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(24);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/banner.jpg',
                fit: BoxFit.cover,
                color: Colors.black.withOpacity(0.3),
                colorBlendMode: BlendMode.darken,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: theme.colorScheme.primary),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withOpacity(0.8),
                      theme.colorScheme.tertiary.withOpacity(0.3),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        T.statDailySales.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Icon(Icons.trending_up, color: Colors.white),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    amountFormatted,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$dailyVentesCount ${T.statSalesCount.toLowerCase()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color baseColor,
    VoidCallback? onTap,
    bool isWarning = false,
  }) {
    final theme = Theme.of(context);
    final bgColor =
    isWarning ? theme.colorScheme.errorContainer : baseColor.withOpacity(0.1);
    final fgColor = isWarning ? theme.colorScheme.onErrorContainer : baseColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: isWarning
                ? Border.all(
              color: theme.colorScheme.error.withOpacity(0.5),
            )
                : null,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceBright,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: fgColor, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: fgColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;
    final dailySalesAmountFormatted =
        '${dailyTotalVentesAmount.toStringAsFixed(0)} ${T.currencyUnit}';

    return Scaffold(
      appBar: _buildAppBar(T),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _initialLoad,
        edgeOffset: 80,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            _buildWelcomeHeader(T),
            const SizedBox(height: 24),
            _buildDailySalesHero(T, dailySalesAmountFormatted),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: () => _navTo('/main/new-sale'),
                icon: const Icon(Icons.point_of_sale_rounded),
                label: Text(
                  T.buttonNewSale,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!_isCollaborator) ...[
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () => _navTo('/main/commercial'),
                  icon: const Icon(Icons.analytics_rounded,
                      color: Colors.indigo),
                  label: const Text(
                    "SUIVI COMMERCIAL",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side:
                    const BorderSide(color: Colors.indigo, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: Colors.indigo.withOpacity(0.05),
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ] else ...[
              const SizedBox(height: 28),
            ],
            if (!_isCollaborator) ...[
              Text(
                T.statisticsTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.15,
                children: [
                  _buildStatCard(
                    title: T.statProductsCount,
                    value: '$produitsCount',
                    icon: Icons.inventory_2_rounded,
                    baseColor: Colors.blueAccent,
                    onTap: () => _navTo('/main/stock'),
                  ),
                  _buildStatCard(
                    title: T.statStockStatus,
                    value: _lowStockCount.toString(),
                    icon: Icons.warning_amber_rounded,
                    baseColor: Colors.orange,
                    isWarning: _lowStockCount > 0,
                    onTap: () => _navTo('/main/stock'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _navTo('/main/add-product'),
                      icon: const Icon(Icons.add_circle_outline),
                      label: Text(T.buttonAddProduct),
                      style: FilledButton.styleFrom(
                        padding:
                        const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _navTo('/settings/manage-users'),
                      icon: const Icon(Icons.group),
                      label: const Text('Collaborateurs'),
                      style: FilledButton.styleFrom(
                        padding:
                        const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }
}