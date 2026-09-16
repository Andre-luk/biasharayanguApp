// lib/pages/securite_page.dart
//
// MODULE 12 — ÉCRAN « SÉCURITÉ » (PERSONNEL PLATEFORME).
//
// Vue de surveillance :
//   • derniers événements de session (connexions, déconnexions, échecs) ;
//   • compteurs 24 h / 7 j (réussies, échecs, comptes et IP en échec) ;
//   • alertes calculées côté serveur (tentatives échouées répétées,
//     IP suspectes) — seuils : 3 échecs par email, 5 par IP sur 24 h ;
//   • réinitialisation des permissions personnalisées (SUPER_ADMIN).
//
// Réservé à `est_plateforme() and (audit/voir or securite/voir)` — contrôlé
// par les RPC ET par cet écran.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/audit.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/securite_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Écran de surveillance de la sécurité (plateforme).
class SecuritePage extends StatefulWidget {
  const SecuritePage({super.key});

  @override
  State<SecuritePage> createState() => _SecuritePageState();
}

class _SecuritePageState extends State<SecuritePage> {
  final SecuriteService _service = SecuriteService.instance;

  ResultatConnexions? _connexions;
  ResultatAlertes? _alertes;
  bool _chargement = true;
  bool _resetEnCours = false;
  String? _erreur;

  bool get _autorise =>
      PermissionService.instance.estPlateforme &&
      (PermissionService.instance.peutVoir(PageAccess.audit) ||
          PermissionService.instance.peutVoir(PageAccess.securite));

  bool get _estSuperAdmin => PermissionService.instance.estSuperAdmin;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    if (!mounted) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final List<dynamic> resultats = await Future.wait<dynamic>(<Future<dynamic>>[
        _service.derniereConnexions(limit: 60),
        _service.alertes(),
      ]);

      if (!mounted) return;
      setState(() {
        _connexions = resultats[0] as ResultatConnexions;
        _alertes = resultats[1] as ResultatAlertes;
        _chargement = false;
      });
    } on SecuriteException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e) {
      debugPrint('SecuritePage._charger : $e');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger les données de sécurité.';
        _chargement = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // RÉINITIALISATION DES PERMISSIONS (SUPER ADMIN)
  // ---------------------------------------------------------------------------

  Future<void> _resetPermissions() async {
    RoleUtilisateur? roleChoisi; // null = tous les rôles

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext contexte, StateSetter setEtat) {
            return AlertDialog(
              icon: Icon(Icons.restart_alt_rounded,
                  color: Theme.of(contexte).colorScheme.error),
              title: const Text('Réinitialiser les permissions ?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Les personnalisations enregistrées seront supprimées et '
                    'la matrice par défaut du Module 4 s\'appliquera.\n',
                    style: TextStyle(fontSize: 13),
                  ),
                  DropdownButtonFormField<RoleUtilisateur?>(
                    initialValue: roleChoisi,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Portée',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<RoleUtilisateur?>>[
                      const DropdownMenuItem<RoleUtilisateur?>(
                        value: null,
                        child: Text('TOUS les rôles'),
                      ),
                      ...RoleUtilisateur.rolesSelectionnables.map(
                        (RoleUtilisateur role) =>
                            DropdownMenuItem<RoleUtilisateur?>(
                          value: role,
                          child: Text(role.libelle),
                        ),
                      ),
                    ],
                    onChanged: (RoleUtilisateur? valeur) {
                      setEtat(() => roleChoisi = valeur);
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(contexte).colorScheme.error,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Réinitialiser'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirme != true || !mounted) return;

    setState(() => _resetEnCours = true);
    try {
      final Map<String, dynamic> resultat = await _service.resetPermissions(
        roleCode: roleChoisi?.code,
      );
      if (!mounted) return;
      final String portee = (resultat['role'] ?? 'TOUS').toString();
      _message('Permissions réinitialisées ($portee).');
    } on SecuriteException catch (e) {
      if (!mounted) return;
      _message(e.message, erreur: true);
    } catch (e) {
      debugPrint('SecuritePage._resetPermissions : $e');
      if (!mounted) return;
      _message('Réinitialisation impossible : vérifiez votre réseau.',
          erreur: true);
    } finally {
      if (mounted) setState(() => _resetEnCours = false);
    }
  }

  void _message(String message, {bool erreur = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: erreur ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_autorise) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sécurité')),
        body: const AccesRefuse(
          message: 'Cet écran est réservé au personnel de la plateforme.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sécurité',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur()
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: <Widget>[
                      _sectionTitre('Résumé des sessions', Icons.schedule_rounded),
                      _grilleResume(),
                      const SizedBox(height: 22),
                      _sectionTitre('Alertes', Icons.notification_important_rounded),
                      _blocAlertes(),
                      const SizedBox(height: 22),
                      _sectionTitre(
                          'Dernières connexions', Icons.login_rounded),
                      _blocConnexions(),
                      if (_estSuperAdmin) ...<Widget>[
                        const SizedBox(height: 22),
                        _sectionTitre(
                            'Maintenance', Icons.build_circle_rounded),
                        _blocMaintenance(),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _vueErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(_erreur!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitre(String titre, IconData icone) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Icon(icone, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            titre,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _grilleResume() {
    final ResumeConnexions resume =
        _connexions?.resume ?? ResumeConnexions.vide;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.35,
      children: <Widget>[
        _carteStat('Connexions (24 h)', resume.reussies24h, Colors.green,
            Icons.check_circle_rounded),
        _carteStat('Échecs (24 h)', resume.echecs24h, Colors.red,
            Icons.error_rounded),
        _carteStat('Déconnexions (24 h)', resume.deconnexions24h, Colors.blue,
            Icons.logout_rounded),
        _carteStat('Échecs (7 j)', resume.echecs7j, Colors.orange,
            Icons.timeline_rounded),
        _carteStat('Comptes en échec (24 h)', resume.comptesEchoues24h,
            Colors.deepOrange, Icons.person_off_rounded),
        _carteStat('IP en échec (24 h)', resume.ipsEchouees24h, Colors.purple,
            Icons.location_off_rounded),
      ],
    );
  }

  Widget _carteStat(String libelle, int valeur, Color couleur, IconData icone) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: couleur.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icone, size: 22, color: couleur),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '$valeur',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: couleur,
                    height: 1.05,
                  ),
                ),
                Text(
                  libelle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blocAlertes() {
    final ResultatAlertes alertes = _alertes ?? ResultatAlertes.vide;

    if (alertes.alertes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
        ),
        child: const Row(
          children: <Widget>[
            Icon(Icons.verified_rounded, color: Colors.green),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aucune alerte : aucune tentative suspecte détectée sur les '
                'dernières 24 heures.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: alertes.alertes.map(_carteAlerte).toList(growable: false),
    );
  }

  Widget _carteAlerte(AlerteSecurite alerte) {
    final bool haute = alerte.gravite.toUpperCase() == 'HAUTE';
    final Color couleur = haute ? Colors.red.shade700 : Colors.orange.shade800;
    final bool parIp = alerte.type == 'IP_SUSPECTE';

    final String cible = parIp
        ? 'IP ${alerte.ip ?? '(inconnue)'}'
        : 'Compte ${alerte.email ?? '(inconnu)'}';
    final String complement = parIp
        ? (alerte.emails.isEmpty ? '' : ' · comptes : ${alerte.emails.take(3).join(', ')}')
        : (alerte.ips.isEmpty ? '' : ' · IP : ${alerte.ips.take(3).join(', ')}');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: couleur.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            haute ? Icons.gpp_maybe_rounded : Icons.report_problem_rounded,
            color: couleur,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        alerte.libelle,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: couleur.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        alerte.gravite,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: couleur,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$cible · ${alerte.nombre} tentative(s)'
                  '${alerte.derniere == null ? '' : ' · dernière : ${formatDateHeure(alerte.derniere)}'}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                if (complement.isNotEmpty)
                  Text(
                    complement,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blocConnexions() {
    final List<ConnexionAudit> lignes =
        _connexions?.lignes ?? const <ConnexionAudit>[];

    if (lignes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Aucun événement de session enregistré.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < lignes.length; i++) ...<Widget>[
            _ligneConnexion(lignes[i]),
            if (i < lignes.length - 1)
              Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }

  Widget _ligneConnexion(ConnexionAudit ligne) {
    final (Color couleur, IconData icone, String libelle) = switch (ligne.action) {
      'CONNEXION' => (Colors.green.shade700, Icons.login_rounded, 'Connexion'),
      'DECONNEXION' => (
          Colors.blueGrey.shade600,
          Icons.logout_rounded,
          'Déconnexion'
        ),
      'CONNEXION_ECHEC' => (
          Colors.red.shade700,
          Icons.gpp_bad_rounded,
          'Échec de connexion'
        ),
      _ => (Colors.grey.shade600, Icons.help_outline_rounded, ligne.action),
    };

    return ListTile(
      dense: true,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icone, size: 18, color: couleur),
      ),
      title: Text(
        '${ligne.utilisateur.isEmpty ? (ligne.email ?? '(sans session)') : ligne.utilisateur} · $libelle',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
      subtitle: Text(
        '${formatDateHeure(ligne.createdAt)}'
        '${ligne.ipAddress == null ? '' : ' · IP ${ligne.ipAddress}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: ligne.action == 'CONNEXION_ECHEC'
          ? Icon(Icons.warning_amber_rounded, size: 18, color: couleur)
          : null,
    );
  }

  Widget _blocMaintenance() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Réinitialiser les permissions personnalisées d\'un rôle (ou de '
            'tous les rôles) : les valeurs par défaut du Module 4 reprennent '
            'immédiatement effet. L\'opération est journalisée '
            '(PERMISSIONS_REINITIALISEES).',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetEnCours ? null : _resetPermissions,
              icon: _resetEnCours
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restart_alt_rounded),
              label: const Text('Réinitialiser les permissions'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
