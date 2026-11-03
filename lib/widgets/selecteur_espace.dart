// lib/widgets/selecteur_espace.dart
//
// MODULE 15 — SÉLECTEUR D'ENTREPRISE (barre supérieure de l'espace boutique).
//
// Affiche l'entreprise ACTIVE et permet d'en changer en un geste. Visible
// dès qu'un compte possède une entreprise (même une seule : le nom affiché
// évite toute confusion de caisse) ; le chevron n'apparaît qu'en pack
// multi-entreprises.
//
// La bascule appelle `rpc_espace_basculer` : côté serveur,
// `mon_proprietaire()` renvoie alors le nouvel espace et TOUTES les données
// (ventes, stock, clients…) suivent automatiquement.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/espace.dart';
import 'package:biashara_yangu/services/espace_service.dart';

/// Icône associée au type d'entreprise.
IconData iconePourTypeEspace(TypeEspace type) {
  switch (type) {
    case TypeEspace.boutique:
      return Icons.storefront_rounded;
    case TypeEspace.distribution:
      return Icons.local_shipping_rounded;
    case TypeEspace.depot:
      return Icons.warehouse_rounded;
    case TypeEspace.hotel:
      return Icons.hotel_rounded;
    case TypeEspace.pharmacie:
      return Icons.local_pharmacy_rounded;
    case TypeEspace.restaurant:
      return Icons.restaurant_rounded;
    case TypeEspace.salleFetes:
      return Icons.celebration_rounded;
    case TypeEspace.boulangerie:
      return Icons.bakery_dining_rounded;
    case TypeEspace.boucherie:
      return Icons.lunch_dining_rounded;
    case TypeEspace.mode:
      return Icons.checkroom_rounded;
    case TypeEspace.salon:
      return Icons.content_cut_rounded;
    case TypeEspace.autre:
      return Icons.business_rounded;
  }
}

/// Bouton compact pour la barre supérieure.
class SelecteurEspace extends StatelessWidget {
  const SelecteurEspace({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<EtatEspaces?>(
      valueListenable: EspaceService.instance.etat,
      builder: (BuildContext context, EtatEspaces? etat, Widget? _) {
        final Espace? actif = etat?.actif;
        if (actif == null) return const SizedBox.shrink();

        final bool multi = etat!.multiEntreprises;

        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: multi
                ? 'Changer d\'entreprise'
                : 'Mes entreprises',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _ouvrirSelection(context, etat),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      iconePourTypeEspace(actif.type),
                      size: 15,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 96),
                      child: Text(
                        actif.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 17,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _ouvrirSelection(BuildContext context, EtatEspaces etat) async {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final String? choix = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.apartment_rounded,
                        size: 20, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Mes entreprises',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (etat.packMulti)
                      Text(
                        '${etat.espaces.length}/${etat.maxEspaces}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...etat.espaces.map(
                (Espace espace) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: espace.estActif
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    child: Icon(
                      iconePourTypeEspace(espace.type),
                      size: 18,
                      color: espace.estActif
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: Text(
                    espace.nom,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(espace.type.libelle),
                  trailing: espace.estActif
                      ? Icon(Icons.check_circle_rounded,
                          color: colorScheme.primary)
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pop(espace.id),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Gérer mes entreprises'),
                subtitle: Text(
                  etat.peutCreer
                      ? '${etat.placesRestantes} place(s) disponible(s) dans votre pack'
                      : 'Détails, pack et création',
                ),
                onTap: () => Navigator.of(context).pop('__gerer__'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!context.mounted || choix == null) return;

    if (choix == '__gerer__') {
      context.push('/main/mes-entreprises');
      return;
    }

    if (choix == etat.actifId) return;

    try {
      await EspaceService.instance.basculer(choix);
      if (!context.mounted) return;

      final Espace? nouveau = EspaceService.instance.actif;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Entreprise « ${nouveau?.nom ?? ''} » activée — les données affichées suivent.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } on EspaceServiceException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}
