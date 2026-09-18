import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/audit_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/scanner_service.dart';
import 'package:biashara_yangu/services/notification_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/language_manager.dart';
import 'package:biashara_yangu/utils/theme_manager.dart';
import 'package:biashara_yangu/models/utilisateur.dart';

// ---------------------
// PAGE À PROPOS
// ---------------------
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(T.settingsAboutTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              T.settingsAboutTitle,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              T.aboutAppDescription,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              T.aboutAppPolicy,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              T.aboutAppContact,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------
// PAGE PARAMÈTRES
// ---------------------
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Utilisateur? _currentUser;
  bool _loading = true;

  // 🔔 NOTIFICATIONS — préférences de l'appareil (ventes + rapport du jour).
  bool _notifVentes = true;
  bool _notifRapport = true;
  int _notifHeureMinutes = NotificationService.heureRapportParDefaut;

  @override
  void initState() {
    super.initState();
    _loadUser();
    // Le service est initialisé au démarrage de l'application ; les valeurs
    // par défaut couvrent le cas où il serait indisponible.
    _notifVentes = NotificationService.instance.ventesActives;
    _notifRapport = NotificationService.instance.rapportActif;
    _notifHeureMinutes = NotificationService.instance.heureRapportMinutes;
  }

  Future<void> _loadUser() async {
    final userIdString = await SessionManager.getUserId();
    if (userIdString == null) {
      if (mounted) context.go('/login');
      return;
    }

    final user = await DBHelper.instance.getUtilisateurById(userIdString);

    if (mounted) {
      setState(() {
        _currentUser = user;
        _loading = false;
      });
    }
  }

  Future<void> _choisirHeureRapport() async {
    final TimeOfDay? choix = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (_notifHeureMinutes ~/ 60) % 24,
        minute: _notifHeureMinutes % 60,
      ),
      helpText: 'Heure du rapport de fin de journée',
    );
    if (choix == null) return;
    final int minutes = choix.hour * 60 + choix.minute;
    await NotificationService.instance.definirHeureRapport(minutes);
    if (!mounted) return;
    setState(() => _notifHeureMinutes = minutes);
  }

  Future<void> _logout() async {
    // 🔐 MODULE 12 — déconnexion tracée (best-effort, AVANT de fermer la session).
    await AuditService.instance.deconnexion();
    await SessionManager.clearSession();
    // 🔳 MODULE 7 — fin de la session de vente : on vide le panier partagé
    // et l'historique du scanner.
    PanierService.instance.vider();
    ScannerService.instance.viderHistorique();
    if (!mounted) return;
    context.go('/login');
  }

  void _showLanguageDialog() {
    final languageManager = Provider.of<LanguageManager>(context, listen: false);
    final currentCode = languageManager.appLocale.languageCode;
    final T = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) {
        String selected = currentCode;
        return StatefulBuilder(
          builder: (contextDialog, setStateDialog) {
            return AlertDialog(
              title: Text(T.languageTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'fr',
                    groupValue: selected,
                    title: const Text('Français'),
                    onChanged: (v) => setStateDialog(() => selected = v ?? 'fr'),
                  ),
                  RadioListTile<String>(
                    value: 'en',
                    groupValue: selected,
                    title: const Text('English'),
                    onChanged: (v) => setStateDialog(() => selected = v ?? 'en'),
                  ),
                  RadioListTile<String>(
                    value: 'sw',
                    groupValue: selected,
                    title: const Text('Kiswahili'),
                    onChanged: (v) => setStateDialog(() => selected = v ?? 'sw'),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(T.cancelButton)),
                TextButton(
                  onPressed: () async {
                    await languageManager.changeLanguage(Locale(selected));
                    if (mounted) Navigator.pop(ctx);
                  },
                  child: Text(T.okButton),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showThemeDialog() {
    final themeManager = Provider.of<ThemeManager>(context, listen: false);
    final current = themeManager.themeMode;
    final T = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) {
        ThemeMode selected = current;
        return StatefulBuilder(
          builder: (contextDialog, setStateDialog) {
            return AlertDialog(
              title: Text(T.themeTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    groupValue: selected,
                    title: Text(T.themeSystem),
                    onChanged: (v) => setStateDialog(() => selected = v ?? ThemeMode.system),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    groupValue: selected,
                    title: Text(T.themeLight),
                    onChanged: (v) => setStateDialog(() => selected = v ?? ThemeMode.light),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    groupValue: selected,
                    title: Text(T.themeDark),
                    onChanged: (v) => setStateDialog(() => selected = v ?? ThemeMode.dark),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(T.cancelButton)),
                TextButton(
                  onPressed: () async {
                    await themeManager.setThemeMode(selected);
                    if (mounted) Navigator.pop(ctx);
                  },
                  child: Text(T.okButton),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;
    final themeManager = Provider.of<ThemeManager>(context);
    final languageManager = Provider.of<LanguageManager>(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(T.settingsTitle)),
        body: const Center(
          child: ModernLoader(
            taille: 46,
            legende: 'Chargement des paramètres…',
          ),
        ),
      );
    }

    final bool isPatron = _currentUser?.parentId == null;

    // 🔐 MODULE 4 — les entrées « équipe » et « administration » dépendent des
    // permissions du rôle : un vendeur ou un magasinier ne les voit plus.
    final PermissionService permissions = PermissionService.instance;
    final bool peutGererEquipe =
        isPatron && permissions.peutVoir(PageAccess.collaborateurs);
    final bool isAdmin = permissions.peutModifier(PageAccess.parametres);

    return Scaffold(
      appBar: AppBar(title: Text(T.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: <Widget>[
          // — Carte de profil (identité + rôle effectif) —
          _EnteteProfil(utilisateur: _currentUser),
          const SizedBox(height: 22),

          _SectionParametres(
            titre: 'Compte',
            tuiles: <Widget>[
              _TuileParametre(
                icone: Icons.person_rounded,
                titre: T.profileTitle,
                sousTitre: T.profileSubtitle,
                onTap: () => context.pushNamed('profile-edit'),
              ),
              _TuileParametre(
                icone: Icons.lock_rounded,
                titre: T.changePasswordTitle,
                sousTitre: T.changePasswordSubtitle,
                onTap: () => context.pushNamed('password-change'),
              ),
            ],
          ),

          if (peutGererEquipe)
            _SectionParametres(
              titre: "Gestion d'équipe",
              tuiles: <Widget>[
                _TuileParametre(
                  icone: Icons.badge_rounded,
                  titre: 'Mes vendeurs',
                  sousTitre: 'Ajouter ou supprimer des collaborateurs',
                  onTap: () => context.pushNamed('manage-users'),
                ),
              ],
            ),

          // 🏢 MODULE 15 — pack multi-entreprises : liste, création et
          // bascule d'entreprise active (boutique, hôtel, pharmacie…).
          if (permissions.peutVoir(PageAccess.dashboard))
            _SectionParametres(
              titre: 'Mes entreprises',
              tuiles: <Widget>[
                _TuileParametre(
                  icone: Icons.apartment_rounded,
                  titre: 'Mes entreprises',
                  sousTitre:
                      'Boutique, hôtel, pharmacie… : créer, basculer, suivre le pack',
                  onTap: () => context.pushNamed('mes-entreprises'),
                ),
              ],
            ),

          _SectionParametres(
            titre: 'Application',
            tuiles: <Widget>[
              _TuileParametre(
                icone: Icons.palette_rounded,
                titre: T.themeTitle,
                sousTitre: themeManager.themeMode == ThemeMode.light
                    ? T.themeLight
                    : (themeManager.themeMode == ThemeMode.dark
                        ? T.themeDark
                        : T.themeSystem),
                onTap: _showThemeDialog,
              ),
              _TuileParametre(
                icone: Icons.language_rounded,
                titre: T.languageTitle,
                sousTitre:
                    languageManager.appLocale.languageCode.toUpperCase(),
                onTap: _showLanguageDialog,
              ),
              _TuileParametre(
                icone: Icons.category_rounded,
                titre: T.manageCategories,
                sousTitre: T.manageCategoriesSubtitle,
                onTap: () => context.pushNamed('manage-categories'),
              ),
              // 🤖 MODULE 13 — assistant IA & quotas (selon permissions du rôle).
              if (permissions.peutVoir(PageAccess.assistantIa))
                _TuileParametre(
                  icone: Icons.smart_toy_rounded,
                  titre: 'Assistant IA',
                  sousTitre:
                      'Posez vos questions, l\'assistant agit selon vos droits',
                  onTap: () => context.pushNamed('assistant-ia'),
                ),
              if (permissions.peutVoir(PageAccess.assistantIa))
                _TuileParametre(
                  icone: Icons.shopping_cart_checkout_rounded,
                  titre: 'Quotas IA',
                  sousTitre:
                      'Packs, paiements suivis et attributions (patron)',
                  onTap: () => context.pushNamed('achat-quotas'),
                ),
              _TuileParametre(
                icone: Icons.accessibility_new_rounded,
                titre: 'Accessibilité',
                sousTitre: 'Taille du texte et confort de lecture',
                onTap: () => context.pushNamed('accessibilite'),
              ),
              _TuileParametre(
                icone: Icons.menu_book_rounded,
                titre: 'Guide d\'utilisation',
                sousTitre: 'Apprendre à utiliser Biashara Yangu pas à pas',
                onTap: () => context.pushNamed('guide-utilisation'),
              ),
              _TuileParametre(
                icone: Icons.privacy_tip_outlined,
                titre: 'Politique & conditions',
                sousTitre: 'Confidentialité et conditions d\'utilisation',
                onTap: () => context.pushNamed('politique-confidentialite'),
              ),
              _TuileParametre(
                icone: Icons.info_outline_rounded,
                titre: T.settingsAboutTitle,
                sousTitre: T.aboutAppDescription,
                onTap: () => context.pushNamed('about'),
              ),
            ],
          ),

          // 🔔 NOTIFICATIONS LOCALES — chaque vente + rapport de fin de journée.
          _SectionParametres(
            titre: 'Notifications',
            tuiles: <Widget>[
              SwitchListTile(
                secondary: const Icon(Icons.point_of_sale_rounded),
                title: const Text('Notifier chaque vente'),
                subtitle: const Text(
                    'Alerte à chaque vente encaissée sur cet appareil'),
                value: _notifVentes,
                onChanged: (bool actif) async {
                  await NotificationService.instance
                      .definirVentesActives(actif);
                  if (mounted) setState(() => _notifVentes = actif);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.insights_rounded),
                title: const Text('Rapport de fin de journée'),
                subtitle: Text(
                    'Résumé des ventes du jour à ${NotificationService.libelleHeure(_notifHeureMinutes)}'),
                value: _notifRapport,
                onChanged: (bool actif) async {
                  await NotificationService.instance
                      .definirRapportActif(actif);
                  if (mounted) setState(() => _notifRapport = actif);
                },
              ),
              if (_notifRapport)
                ListTile(
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('Heure du rapport'),
                  subtitle: Text(
                      'Tous les jours à ${NotificationService.libelleHeure(_notifHeureMinutes)}'),
                  onTap: _choisirHeureRapport,
                ),
              ListTile(
                leading: const Icon(Icons.notifications_active_rounded),
                title: const Text('Tester le rapport maintenant'),
                subtitle: const Text('Envoie immédiatement le résumé du jour'),
                onTap: () => NotificationService.instance
                    .verifierEtEnvoyerRapportDuJour(forcer: true),
              ),
            ],
          ),

          if (isAdmin)
            _SectionParametres(
              titre: 'Administration',
              tuiles: <Widget>[
                _TuileParametre(
                  icone: Icons.admin_panel_settings_rounded,
                  titre: T.manageUsersTitle,
                  onTap: () {},
                ),
              ],
            ),

          // 🔐 MODULE 12 — traçabilité & données (selon permissions :
          // journal d'audit pour le propriétaire, import d'articles pour
          // les rôles autorisés à créer des articles).
          if (permissions.peutVoir(PageAccess.audit) ||
              permissions.peut(PageAccess.articles, ActionAccess.creer))
            _SectionParametres(
              titre: 'Traçabilité & données',
              tuiles: <Widget>[
                if (permissions.peutVoir(PageAccess.audit))
                  _TuileParametre(
                    icone: Icons.history_edu_rounded,
                    titre: 'Journal d\'audit',
                    sousTitre:
                        'Qui a fait quoi, quand — filtres, détail et export PDF signé',
                    onTap: () => context.pushNamed('journal-audit'),
                  ),
                if (permissions.peut(PageAccess.articles, ActionAccess.creer))
                  _TuileParametre(
                    icone: Icons.upload_file_rounded,
                    titre: 'Importer des articles',
                    sousTitre:
                        'Coller un contenu CSV ou choisir un fichier — tracé (IMPORT_PRODUITS)',
                    onTap: () => context.pushNamed('import-produits'),
                  ),
              ],
            ),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            label: Text(T.logoutButton),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppCouleurs.danger,
              side: BorderSide(
                color: AppCouleurs.danger.withValues(alpha: 0.45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte d'identité affichée en tête des paramètres.
class _EnteteProfil extends StatelessWidget {
  const _EnteteProfil({required this.utilisateur});

  final Utilisateur? utilisateur;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final RoleUtilisateur role =
        PermissionService.roleDepuisUtilisateur(utilisateur);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppDegrades.hero,
        borderRadius: BorderRadius.circular(24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppCouleurs.marine.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
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
            child: const CircleAvatar(
              radius: 26,
              backgroundImage: AssetImage('assets/utilisateur.jpg'),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  utilisateur?.fullName ?? 'Utilisateur',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  utilisateur?.email ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    role.libelle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Groupe de réglages : titre + carte contenant les tuiles.
class _SectionParametres extends StatelessWidget {
  const _SectionParametres({required this.titre, required this.tuiles});

  final String titre;
  final List<Widget> tuiles;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final List<Widget> contenu = <Widget>[];
    for (int i = 0; i < tuiles.length; i++) {
      contenu.add(tuiles[i]);
      if (i < tuiles.length - 1) {
        contenu.add(Divider(height: 1, color: scheme.outlineVariant));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: AppDegrades.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  titre,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(children: contenu),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tuile de réglage : icône teintée, titre, sous-titre, chevron.
class _TuileParametre extends StatelessWidget {
  const _TuileParametre({
    required this.icone,
    required this.titre,
    required this.onTap,
    this.sousTitre,
  });

  final IconData icone;
  final String titre;
  final String? sousTitre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icone, size: 20, color: scheme.primary),
      ),
      title: Text(
        titre,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
      ),
      subtitle: sousTitre == null
          ? null
          : Text(
              sousTitre!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
      ),
    );
  }
}