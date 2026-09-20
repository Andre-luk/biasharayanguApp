// lib/widgets/banniere_abonnement.dart
//
// MODULE 3 — Affichage du mode « lecture seule ».
//
// Quand l'abonnement de l'entreprise est échu (EXPIRE ou
// EN_ATTENTE_COMPLEMENT), l'utilisateur conserve un accès en lecture seule :
// la consultation reste possible, les fonctionnalités commerciales sont
// bloquées. Ces widgets affichent l'information et expliquent le blocage.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';

/// Bannière persistante affichée en haut de l'application lorsque
/// l'abonnement de l'entreprise est échu.
///
/// Se met à jour automatiquement : elle écoute [AbonnementService.acces],
/// alimenté par le middleware à la connexion.
class BanniereAbonnement extends StatelessWidget {
  const BanniereAbonnement({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EtatAccesAbonnement>(
      valueListenable: AbonnementService.instance.acces,
      builder: (BuildContext context, EtatAccesAbonnement etat, Widget? child) {
        if (!etat.lectureSeule) return const SizedBox.shrink();

        // 🧾 MODULE 17 — trois situations : complément attendu (orange),
        // dossier pas encore activé (indigo) et abonnement échu (rouge).
        final bool attente =
            etat.statut == StatutAbonnement.enAttenteComplement;
        final Color couleur = etat.enAttenteActivation
            ? Colors.indigo.shade600
            : (attente ? Colors.orange.shade800 : Colors.red.shade700);

        return Material(
          color: couleur.withValues(alpha: 0.10),
          child: SafeArea(
            bottom: false,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: couleur.withValues(alpha: 0.25)),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: couleur.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_clock_rounded,
                      size: 16,
                      color: couleur,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      etat.message ??
                          'Abonnement échu : accès en lecture seule. '
                              'Contactez votre administrateur.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: couleur,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: couleur.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      etat.enAttenteActivation
                          ? 'En attente'
                          : 'Lecture seule',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: couleur,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Affiche le dialogue expliquant que l'action est bloquée car le compte
/// n'est pas opérationnel (activation en attente, abonnement échu ou compte
/// restreint).
///
/// Fonction volontairement synchrone : le dialogue s'affiche pendant que
/// l'appelant interrompt son action, sans introduire de rupture asynchrone.
void afficherDialogueLectureSeule(BuildContext context) {
  final EtatAccesAbonnement etat = AbonnementService.instance.acces.value;

  final bool activation = etat.enAttenteActivation;

  showDialog<void>(
    context: context,
    builder: (BuildContext ctx) {
      final bool voitTableau =
          PermissionService.instance.peutVoir(PageAccess.dashboard);

      return AlertDialog(
        title: Text(
          activation
              ? 'Compte en attente de validation'
              : 'Action indisponible',
        ),
        content: Text(
          activation
              ? '${etat.message ?? "Votre compte est en attente de validation."}\n\n'
                  'Les cadenas disparaîtront automatiquement dès la validation '
                  'de votre paiement par notre équipe.'
              : '${etat.message ?? "L'abonnement de votre entreprise est échu."}\n\n'
                  'Cette action est réservée aux comptes opérationnels. Vos '
                  'données sont intactes : elles redeviendront modifiables dès '
                  'la régularisation.',
        ),
        actions: <Widget>[
          if (activation && voitTableau)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/main/mon-activation');
              },
              child: const Text('Mon dossier'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Compris'),
          ),
        ],
      );
    },
  );
}
