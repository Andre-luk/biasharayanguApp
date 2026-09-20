// lib/pages/compte_verrouille_page.dart
//
// 🧾 MODULE 17 — PAGE « COMPTE VERROUILLÉ ».
//
// Affichée quand un accès est tenté vers un écran commercial alors que le
// compte n'est pas opérationnel :
//   • dossier d'activation pas encore validé (Gestionnaire → Finance) ;
//   • abonnement échu ou compte restreint (solde impayé) ;
//   • compte suspendu par l'administrateur.
//
// L'utilisateur conserve la CONSULTATION (accueil, rapports, stock…). Cette
// page explique la situation, rappelle la procédure officielle et donne accès
// au dossier d'activation. Elle s'actualise automatiquement : dès que la
// finance active le compte, l'utilisateur est ramené à l'accueil — les
// cadenas disparaissent sans reconnexion.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';

class CompteVerrouillePage extends StatefulWidget {
  const CompteVerrouillePage({super.key});

  @override
  State<CompteVerrouillePage> createState() => _CompteVerrouillePageState();
}

class _CompteVerrouillePageState extends State<CompteVerrouillePage> {
  bool _actualisation = false;

  @override
  void initState() {
    super.initState();
    AbonnementService.instance.acces.addListener(_onAcces);
  }

  @override
  void dispose() {
    AbonnementService.instance.acces.removeListener(_onAcces);
    super.dispose();
  }

  /// Le compte vient d'être activé (où que ce soit dans l'application) :
  /// retour immédiat à l'accueil débloqué.
  void _onAcces() {
    if (!mounted) return;
    if (AbonnementService.instance.acces.value.accesComplet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Votre compte est activé ! Bon travail.'),
          backgroundColor: AppCouleurs.succes,
        ),
      );
      context.go('/main');
      return;
    }
    setState(() {});
  }

  Future<void> _actualiser() async {
    setState(() => _actualisation = true);
    await AbonnementService.instance.rafraichirSilencieux();
    if (!mounted) return;
    setState(() => _actualisation = false);
    // `_onAcces` fait le reste si le compte est devenu opérationnel.
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EtatAccesAbonnement acces = AbonnementService.instance.acces.value;
    final bool activation = acces.enAttenteActivation;

    // Rôles sans tableau de bord (vendeur…) : on n'affiche pas les boutons
    // qui rebondiraient vers des écrans qui leur sont interdits.
    final bool voitTableauDeBord =
        PermissionService.instance.peutVoir(PageAccess.dashboard);

    final Color couleur =
        activation ? Colors.orange.shade800 : theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Compte verrouillé',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Retour',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/main'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  activation
                      ? Icons.lock_clock_rounded
                      : Icons.lock_outline_rounded,
                  size: 56,
                  color: couleur,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              activation
                  ? 'Votre compte est en attente de validation'
                  : 'Fonctionnalités temporairement indisponibles',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              acces.message ??
                  'Votre compte doit être validé avant de pouvoir utiliser '
                      'les fonctionnalités de votre entreprise.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),

            // Procédure officielle d'activation.
            if (activation) _carteProcedure(theme),

            const SizedBox(height: 16),
            _carteDonneesInchangees(theme),

            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _actualisation ? null : _actualiser,
              icon: _actualisation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                _actualisation
                    ? 'Vérification…'
                    : 'J\'ai payé — vérifier mon compte',
              ),
            ),
            const SizedBox(height: 10),
            if (voitTableauDeBord) ...<Widget>[
              OutlinedButton.icon(
                onPressed: () => context.go('/main/mon-activation'),
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('Voir mon dossier d\'activation'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => context.go('/main'),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Retour à l\'accueil (consultation)'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _carteProcedure(ThemeData theme) {
    const List<(IconData, String, String)> etapes =
        <(IconData, String, String)>[
      (
        Icons.app_registration_rounded,
        '1. Création du compte',
        'Vos informations d\'entreprise ont été enregistrées.'
      ),
      (
        Icons.fact_check_outlined,
        '2. Vérification',
        'Notre gestionnaire vérifie votre commerce et votre responsable.'
      ),
      (
        Icons.payments_outlined,
        '3. Paiement',
        'Votre paiement est contrôlé par la finance.'
      ),
      (
        Icons.verified_rounded,
        '4. Activation',
        'Compte opérationnel : ventes, stock, caisse et rapports.'
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.timeline_rounded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Procédure d\'activation',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (IconData icone, String titre, String detail) in etapes)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icone, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          titre,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        Text(
                          detail,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _carteDonneesInchangees(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppCouleurs.marine.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppCouleurs.marine),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Vos données sont intactes et consultables. Dès la validation '
              'de la finance, les cadenas disparaissent automatiquement et '
              'vous pourrez vendre, gérer votre stock et votre caisse.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
