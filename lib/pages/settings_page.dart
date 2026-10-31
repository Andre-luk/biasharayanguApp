import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/audit_service.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/services/type_activite_service.dart';
import 'package:biashara_yangu/ui/parametres/catalogue_parametres.dart';
import 'package:biashara_yangu/services/mode_application_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/peremption_service.dart';
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
  /// 🔎 Recherche dans les réglages (accents et casse ignorés).
  final TextEditingController _rechercheController = TextEditingController();
  String _filtre = '';
  Utilisateur? _currentUser;
  bool _loading = true;

  // 🔔 NOTIFICATIONS — préférences de l'appareil (ventes + rapport du jour).
  bool _notifVentes = true;
  bool _notifRapport = true;
  int _notifHeureMinutes = NotificationService.heureRapportParDefaut;

  // ⚡ MODULE 23 — MODE RAPIDE (nom + prix → vendre).
  bool _modeRapide = false;

  /// 🧮 CORRECTIF 72 — délai d'alerte de péremption de la boutique.
  ///
  /// `null` tant qu'il n'a pas été lu : la tuile affiche alors un libellé
  /// neutre plutôt qu'un chiffre inventé — on n'annonce pas un délai qu'on
  /// n'a pas vérifié.
  int? _delaiPeremption;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _chargerDelaiPeremption();
    // Le service est initialisé au démarrage de l'application ; les valeurs
    // par défaut couvrent le cas où il serait indisponible.
    _notifVentes = NotificationService.instance.ventesActives;
    _notifRapport = NotificationService.instance.rapportActif;
    _notifHeureMinutes = NotificationService.instance.heureRapportMinutes;
    // ⚡ MODULE 23 — le mode enregistré sur cet appareil.
    ModeApplicationService.instance.charger().then((_) {
      if (mounted) {
        setState(() {
          _modeRapide = ModeApplicationService.instance.rapide;
        });
      }
    });
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  Future<void> _chargerDelaiPeremption() async {
    final int delai = await PeremptionService.instance.charger();
    if (!mounted) return;
    setState(() => _delaiPeremption = delai);
  }

  /// 🧮 CORRECTIF 72 — régler le délai d'alerte de péremption.
  ///
  /// On propose les valeurs courantes (7, 15, 30, 60, 90 jours) ET la saisie
  /// libre : une pharmacie qui veut 45 jours ne doit pas être coincée entre
  /// deux boutons.
  Future<void> _reglerDelaiPeremption() async {
    final int actuel = _delaiPeremption ?? PeremptionService.delaiParDefaut;
    final TextEditingController saisie =
        TextEditingController(text: actuel.toString());

    final int? nouveau = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Alerte de péremption'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'À partir de combien de jours avant la date de péremption '
              'voulez-vous être prévenu ?',
            ),
            const SizedBox(height: 8),
            const Text(
              'Un produit devient « expire bientôt » dans cette fenêtre. '
              'Il est signalé dans votre liste d\'articles, sur l\'écran '
              'Expirations, et rappelé par le rapport de fin de journée.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final int choix in <int>[7, 15, 30, 60, 90])
                  ChoiceChip(
                    label: Text('$choix j'),
                    selected: actuel == choix,
                    onSelected: (_) => Navigator.of(context).pop(choix),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: saisie,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Ou un nombre de jours précis (1 à 365)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final int? valeur = int.tryParse(saisie.text.trim());
              Navigator.of(context).pop(valeur);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    saisie.dispose();
    if (nouveau == null || !mounted) return;

    try {
      final int retenu = await PeremptionService.instance.definirDelai(nouveau);
      if (!mounted) return;
      setState(() => _delaiPeremption = retenu);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alertes de péremption réglées à $retenu jours.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } on PeremptionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Réglage impossible : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
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
    final languageManager =
        Provider.of<LanguageManager>(context, listen: false);
    final T = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) {
        // ⚠️ AUDIT FINAL — vérité de l'interface : seuls les libellés français
        // sont réellement traduits. Proposer l'anglais et le swahili laissait
        // 99 % de l'application en français : les deux options restent
        // visibles (l'utilisateur sait que ces langues arrivent) mais sont
        // désactivées, et toute locale héritée est ramenée au français.
        String selected = 'fr';
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
                    onChanged: (v) =>
                        setStateDialog(() => selected = v ?? 'fr'),
                  ),
                  const RadioListTile<String>(
                    value: 'en',
                    groupValue: 'fr',
                    enabled: false,
                    title: Text('English'),
                    subtitle: Text('Traduction en préparation'),
                    onChanged: null,
                  ),
                  const RadioListTile<String>(
                    value: 'sw',
                    groupValue: 'fr',
                    enabled: false,
                    title: Text('Kiswahili'),
                    subtitle: Text('Traduction en préparation'),
                    onChanged: null,
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(T.cancelButton)),
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
                    onChanged: (v) =>
                        setStateDialog(() => selected = v ?? ThemeMode.system),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    groupValue: selected,
                    title: Text(T.themeLight),
                    onChanged: (v) =>
                        setStateDialog(() => selected = v ?? ThemeMode.light),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    groupValue: selected,
                    title: Text(T.themeDark),
                    onChanged: (v) =>
                        setStateDialog(() => selected = v ?? ThemeMode.dark),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(T.cancelButton)),
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

    // 🔐 MODULE 4 — les entrées « équipe » et « administration » dépendent des
    // permissions du rôle : un vendeur ou un magasinier ne les voit plus.
    final PermissionService permissions = PermissionService.instance;
    final bool isAdmin = permissions.peutModifier(PageAccess.parametres);

    // 🧩 MODULE 16 — les entrées d'écran suivent AUSSI l'activité : un hôtel
    // ne voit ni « Catégories » d'articles, ni « Importer des articles », ni
    // l'assistant IA si son profil ne les contient pas (masquage uniquement).
    final ModulesService modules = ModulesService.instance;

    // 🧮 CORRECTIF 72 — le délai d'alerte de péremption ne concerne que les
    // activités qui suivent les dates (pharmacie, alimentaire…). L'afficher
    // ailleurs serait un réglage sans effet, donc un piège.
    final bool peremptionDisponible =
        modules.moduleActif(ModuleCode.lotsExpiration);

    return Scaffold(
      appBar: AppBar(title: Text(T.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: <Widget>[
          // — Carte de profil (identité + rôle effectif) —
          _EnteteProfil(utilisateur: _currentUser),
          const SizedBox(height: 22),

          // 🔎 RECHERCHE — le patron tape « devise », « tournée », « audit »…
          // et trouve le réglage sans connaître la rubrique.
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: TextField(
              controller: _rechercheController,
              onChanged: (String v) => setState(() => _filtre = v),
              decoration: InputDecoration(
                hintText: 'Rechercher un réglage…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _filtre.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _rechercheController.clear();
                          setState(() => _filtre = '');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // ⚙️ RÉGLAGES ADAPTÉS — sections construites à partir du catalogue
          // (`CatalogueParametres`) : chaque réglage n'apparaît que s'il a un
          // sens pour le TYPE d'entreprise, les MODULES actifs et le RÔLE.
          ..._sectionsParametres(T),

          // 🎨 APPARENCE — réglages propres à CET APPAREIL (thème, langue,
          // confort de lecture) : ils ne dépendent ni du type d'activité ni des
          // modules, et restent donc toujours proposés.
          _SectionParametres(
            titre: 'Apparence',
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
                sousTitre: languageManager.appLocale.languageCode.toUpperCase(),
                onTap: _showLanguageDialog,
              ),
              _TuileParametre(
                icone: Icons.accessibility_new_rounded,
                titre: 'Accessibilité',
                sousTitre: 'Taille du texte et confort de lecture',
                onTap: () => context.pushNamed('accessibilite'),
              ),
              // 🧮 délai d'alerte de péremption, réglé PAR la boutique.
              if (peremptionDisponible)
                _TuileParametre(
                  icone: Icons.event_busy_rounded,
                  titre: 'Alerte de péremption',
                  sousTitre: _delaiPeremption == null
                      ? 'Être prévenu avant la date de péremption'
                      : 'Prévenu $_delaiPeremption jours avant la date',
                  onTap: _reglerDelaiPeremption,
                ),
            ],
          ),

          // ⚡ MODULE 23 — MODE RAPIDE : nom + prix → vendre. Les écrans
          // avancés sont masqués (jamais bloqués) tant que le mode est actif.
          _SectionParametres(
            titre: 'Mode d\'utilisation',
            tuiles: <Widget>[
              SwitchListTile(
                secondary: const Icon(Icons.bolt_rounded),
                title: const Text('Mode rapide'),
                subtitle: const Text(
                    'Ajouter un produit avec un nom et un prix, puis vendre. '
                    'Les écrans avancés sont masqués.'),
                value: _modeRapide,
                onChanged: (bool actif) async {
                  await ModeApplicationService.instance.definir(
                    actif ? ModeApplication.rapide : ModeApplication.complet,
                  );
                  if (mounted) setState(() => _modeRapide = actif);
                },
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
                  await NotificationService.instance.definirRapportActif(actif);
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

extension _SectionsCatalogue on _SettingsPageState {
  /// Réglages visibles pour cette entreprise et ce rôle, filtrés par la
  /// recherche, puis regroupés en sections.
  ///
  /// Fail-open : modules non chargés ou type inconnu → tout reste visible.
  List<Widget> _sectionsParametres(AppLocalizations T) {
    final PermissionService permissions = PermissionService.instance;

    final List<ParametreApp> visibles = CatalogueParametres.visibles(
      modules: ModulesService.instance.modules.value,
      profilCharge: ModulesService.instance.charge,
      typeActivite: TypeActiviteService.instance.type.value,
      peut: permissions.peut,
    );

    final List<ParametreApp> filtres =
        CatalogueParametres.rechercher(_filtre, visibles, T);

    if (filtres.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: <Widget>[
              Icon(Icons.search_off_rounded,
                  size: 40, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 8),
              Text(
                'Aucun réglage ne correspond à « $_filtre ».',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ];
    }

    final Map<String, List<ParametreApp>> sections =
        CatalogueParametres.sections(filtres);

    return <Widget>[
      for (final MapEntry<String, List<ParametreApp>> entree
          in sections.entries) ...<Widget>[
        _SectionParametres(
          titre: entree.key,
          tuiles: <Widget>[
            for (final ParametreApp p in entree.value)
              _TuileParametre(
                icone: p.icone,
                titre: p.titre(T),
                sousTitre: p.sousTitre(T),
                onTap: () {
                  if (p.route != null) context.pushNamed(p.route!);
                },
              ),
          ],
        ),
        const SizedBox(height: 22),
      ],
    ];
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
