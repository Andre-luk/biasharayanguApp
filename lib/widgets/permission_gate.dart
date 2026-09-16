// lib/widgets/permission_gate.dart
//
// MODULE 4 — Masquage des actions non autorisées.
//
// Troisième étage du middleware de permissions :
//
//   1. `app_router.dart`  → refuse la NAVIGATION vers une page interdite ;
//   2. `permission_service` → source unique de vérité (pages + actions) ;
//   3. ce fichier         → masque les BOUTONS et actions interdites dans une
//                           page pourtant autorisée (ex. un magasinier voit le
//                           stock mais n'a pas le bouton « Supprimer »).
//
// Le masquage n'est PAS la sécurité : chaque action sensible est aussi
// contrôlée côté serveur (RLS + triggers, cf. `20260916000006_module4_permissions.sql`).
// Il évite simplement de proposer à l'utilisateur ce qu'il ne peut pas faire.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/permission_service.dart';

/// Affiche [child] uniquement si le rôle connecté possède
/// [action] sur [page].
///
/// ```dart
/// PermissionGate(
///   page: PageAccess.depenses,
///   action: ActionAccess.creer,
///   child: FloatingActionButton(onPressed: _ajouter, child: const Icon(Icons.add)),
/// )
/// ```
class PermissionGate extends StatelessWidget {
  const PermissionGate({
    super.key,
    required this.page,
    required this.action,
    required this.child,
    this.fallback,
  });

  final PageAccess page;
  final ActionAccess action;
  final Widget child;

  /// Widget affiché à la place quand l'action est interdite (`SizedBox.shrink`
  /// par défaut : l'action disparaît purement et simplement).
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    if (PermissionService.instance.peut(page, action)) return child;
    return fallback ?? const SizedBox.shrink();
  }
}

/// Variante paresseuse : le bouton n'est construit que s'il est autorisé.
class PermissionGateBouton extends StatelessWidget {
  const PermissionGateBouton({
    super.key,
    required this.page,
    required this.action,
    required this.builder,
    this.fallback,
  });

  final PageAccess page;
  final ActionAccess action;
  final WidgetBuilder builder;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    if (PermissionService.instance.peut(page, action)) return builder(context);
    return fallback ?? const SizedBox.shrink();
  }
}

/// Message « accès refusé » homogène (utilisé par les pages qui vérifient
/// elles-mêmes une permission à l'exécution, hors navigation go_router).
class AccesRefuse extends StatelessWidget {
  const AccesRefuse({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.lock_outline_rounded, size: 56, color: colorScheme.error),
            const SizedBox(height: 12),
            const Text(
              'Accès refusé',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message ??
                  "Votre rôle ne vous permet pas d'ouvrir cet écran. "
                      "Contactez l'administrateur de votre compte.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau discret signalant que le rôle n'a que la lecture.
class BandeauLectureSeulePermission extends StatelessWidget {
  const BandeauLectureSeulePermission({super.key, required this.page});

  final PageAccess page;

  @override
  Widget build(BuildContext context) {
    final PermissionService permissions = PermissionService.instance;
    final bool lectureSeule = permissions.peutVoir(page) &&
        !permissions.peut(page, ActionAccess.creer) &&
        !permissions.peut(page, ActionAccess.modifier);

    if (!lectureSeule) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.visibility_rounded, size: 18, color: Colors.amber.shade900),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Consultation uniquement : votre rôle ne permet pas de modifier '
              'ces informations.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
