import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/db_helper.dart';
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

  @override
  void initState() {
    super.initState();
    _loadUser();
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

  Future<void> _logout() async {
    await SessionManager.clearSession();
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
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final bool isPatron = _currentUser?.parentId == null;
    final bool isAdmin = _currentUser?.role == 'admin';

    return Scaffold(
      appBar: AppBar(title: Text(T.settingsTitle), elevation: 0),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ListTile(
              title: Text(T.profileTitle),
              subtitle: Text(T.profileSubtitle),
              leading: const Icon(Icons.person),
              onTap: () => context.pushNamed('profile-edit'),
            ),
            ListTile(
              title: Text(T.changePasswordTitle),
              subtitle: Text(T.changePasswordSubtitle),
              leading: const Icon(Icons.lock),
              onTap: () => context.pushNamed('password-change'),
            ),
            const Divider(),

            if (isPatron) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Gestion d'équipe",
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                ),
              ),
              ListTile(
                title: const Text("Mes vendeurs"),
                subtitle: const Text("Ajouter ou supprimer des collaborateurs"),
                leading: const Icon(Icons.badge_outlined),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => context.pushNamed('manage-users'),
              ),
              const Divider(),
            ],

            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(T.manageCategories),
              subtitle: Text(T.manageCategoriesSubtitle),
              onTap: () => context.pushNamed('manage-categories'),
            ),
            const Divider(),

            ListTile(
              title: Text(T.themeTitle),
              subtitle: Text(themeManager.themeMode == ThemeMode.light
                  ? T.themeLight : (themeManager.themeMode == ThemeMode.dark ? T.themeDark : T.themeSystem)),
              leading: const Icon(Icons.palette),
              onTap: _showThemeDialog,
            ),

            ListTile(
              title: Text(T.languageTitle),
              subtitle: Text(languageManager.appLocale.languageCode.toUpperCase()),
              leading: const Icon(Icons.language),
              onTap: _showLanguageDialog,
            ),
            const Divider(),

            // ✅ SECTION CORRIGÉE : Utilise maintenant GoRouter
            ListTile(
              title: Text(T.settingsAboutTitle),
              subtitle: Text(T.aboutAppDescription),
              leading: const Icon(Icons.info_outline),
              onTap: () => context.pushNamed('about'),
            ),
            const Divider(),

            if (isAdmin)
              ListTile(
                title: Text(T.manageUsersTitle),
                leading: const Icon(Icons.admin_panel_settings),
                onTap: () {},
              ),

            const SizedBox(height: 20),
            ListTile(
              title: Text(T.logoutButton, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              leading: const Icon(Icons.logout, color: Colors.red),
              onTap: () => _logout(),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}