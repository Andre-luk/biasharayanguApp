// lib/pages/permissions_role_page.dart
//
// MODULE 4 — ÉCRAN « MODIFIER LES PERMISSIONS D'UN RÔLE »
//
// Réservé au SUPER_ADMIN (contrôle applicatif ci-dessous + contrôle serveur :
// la RPC `rpc_permissions_set` refuse toute autre rôle).
//
// Fonctionnement :
//   • un sélecteur de rôle ;
//   • pour chaque page : un interrupteur (page accessible ou non) et, si elle
//     est accessible, les actions autorisées (voir / créer / modifier /
//     supprimer / valider) sous forme de pastilles ;
//   • bouton « Enregistrer » → `app_settings.permissions_roles` ;
//   • bouton « Rétablir les droits par défaut » → suppression de la
//     personnalisation (retour à la matrice du Module 4).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/icones_pages.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

class PermissionsRolePage extends StatefulWidget {
  const PermissionsRolePage({super.key, this.roleInitial});

  /// Rôle présélectionné (facultatif).
  final RoleUtilisateur? roleInitial;

  @override
  State<PermissionsRolePage> createState() => _PermissionsRolePageState();
}

class _PermissionsRolePageState extends State<PermissionsRolePage> {
  final PermissionService _permissions = PermissionService.instance;

  RoleUtilisateur _role = RoleUtilisateur.vendeur;

  /// Permissions en cours d'édition (avant enregistrement), par rôle.
  final Map<RoleUtilisateur, RolePermission> _edits =
      <RoleUtilisateur, RolePermission>{};

  bool _chargement = false;
  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    _role = widget.roleInitial ?? RoleUtilisateur.vendeur;
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    await _permissions.rechargerSurcharges();
    if (!mounted) return;
    setState(() {
      _edits.clear();
      _chargement = false;
    });
  }

  /// Permissions affichées pour le rôle sélectionné (édition en priorité).
  RolePermission get _permissionsAffichees =>
      _edits[_role] ?? _permissions.permissionsDe(_role);

  void _majPermissions(RolePermission nouvelles) {
    setState(() => _edits[_role] = nouvelles);
  }

  bool get _modifie => _edits.containsKey(_role);

  void _afficherSnack(String message, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor:
          erreur ? Colors.red.shade700 : Theme.of(context).colorScheme.primary,
    ));
  }

  Future<void> _enregistrer() async {
    if (!_modifie) {
      _afficherSnack('Aucune modification à enregistrer.');
      return;
    }

    setState(() => _enregistrement = true);
    try {
      await _permissions.enregistrerPermissions(_role, _permissionsAffichees);
      if (!mounted) return;
      setState(() {
        _edits.remove(_role);
        _enregistrement = false;
      });
      _afficherSnack('Permissions enregistrées pour ${_role.libelle}.');
    } on PermissionServiceException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _afficherSnack(e.message, erreur: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _afficherSnack('Enregistrement impossible : $e', erreur: true);
    }
  }

  Future<void> _retablir() async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Rétablir les droits par défaut ?'),
        content: Text(
          'Le rôle « ${_role.libelle} » reprendra exactement les permissions du '
          'Module 4. Les personnalisations enregistrées seront perdues.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Rétablir'),
          ),
        ],
      ),
    );

    if (confirme != true) return;

    setState(() => _enregistrement = true);
    try {
      await _permissions.reinitialiserRole(_role);
      if (!mounted) return;
      setState(() {
        _edits.remove(_role);
        _enregistrement = false;
      });
      _afficherSnack('Droits par défaut rétablis pour ${_role.libelle}.');
    } on PermissionServiceException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _afficherSnack(e.message, erreur: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _afficherSnack('Réinitialisation impossible : $e', erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    // Double barrière : le rôle doit être SUPER_ADMIN (l'accès à la page est
    // déjà filtré par le middleware de navigation).
    if (!_permissions.estSuperAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Permissions des rôles',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
        ),
        body: const AccesRefuse(
          message: 'Seul le Super Administrateur peut modifier les permissions '
              'des rôles.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Permissions des rôles',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Recharger depuis la base',
            onPressed: _chargement ? null : _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _construireCorps(colorScheme),
      bottomNavigationBar: _construireBarreActions(colorScheme),
    );
  }

  Widget _construireCorps(ColorScheme colorScheme) {
    final RolePermission permissions = _permissionsAffichees;
    final List<PageAccess> pages = PageAccess.values;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // ------------------------------------------------ sélecteur de rôle
        AppDropdownField<RoleUtilisateur>(
          label: 'Rôle à configurer',
          value: _role,
          prefixIcon: Icons.badge_rounded,
          items: RoleUtilisateur.values
              .where((RoleUtilisateur r) => r != RoleUtilisateur.inconnu)
              .map((RoleUtilisateur r) => DropdownMenuItem<RoleUtilisateur>(
                    value: r,
                    child: Text('${r.libelle}  •  ${r.code}'),
                  ))
              .toList(),
          onChanged: (RoleUtilisateur? r) {
            if (r != null) setState(() => _role = r);
          },
        ),
        const SizedBox(height: 12),

        // ------------------------------------------------------- état du rôle
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      _role.estPlateforme
                          ? Icons.business_center_rounded
                          : Icons.storefront_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _role.estPlateforme
                            ? 'Espace plateforme La Perle'
                            : 'Espace entreprise (boutique)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_permissions.estPersonnalise(_role))
                      Chip(
                        label: const Text('Personnalisé',
                            style: TextStyle(fontSize: 11)),
                        backgroundColor: Colors.amber.shade100,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${permissions.pages.length} page(s) autorisée(s), '
                  '${pages.length} page(s) disponible(s).',
                  style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Astuce : décochez une page pour la retirer du menu du rôle. '
                  'Un rôle à qui il ne reste aucune page n\'a plus accès à rien.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // --------------------------------------------------------- les pages
        ...pages.map((PageAccess page) => _cartePage(page, permissions)),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _cartePage(PageAccess page, RolePermission permissions) {
    final bool active = permissions.actionsPour(page).isNotEmpty;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(iconePourPage(page), size: 20, color: Colors.grey[700]),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        page.libelle,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${page.code}  •  ${libelleEspace(page)}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: active,
                  onChanged: (bool valeur) => _majPermissions(
                    permissions.avecPage(page, valeur),
                  ),
                ),
              ],
            ),
            if (active) ...<Widget>[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: -6,
                children: ActionAccess.values.map((ActionAccess action) {
                  final bool autorisee = permissions.aAcces(page, action);
                  return FilterChip(
                    label: Text(action.libelle, style: const TextStyle(fontSize: 12)),
                    selected: autorisee,
                    visualDensity: VisualDensity.compact,
                    onSelected: (bool selection) => _majPermissions(
                      permissions.avec(page, action, selection),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _construireBarreActions(ColorScheme colorScheme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _enregistrement ? null : _retablir,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Droits par défaut'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: (_enregistrement || !_modifie) ? null : _enregistrer,
                icon: _enregistrement
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('Enregistrer'),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
