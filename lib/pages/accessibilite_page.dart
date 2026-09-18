// lib/pages/accessibilite_page.dart
//
// ♿ ACCESSIBILITÉ — déclaration et réglages de confort de lecture.
//
//   • taille du texte de l'application (90 % → 130 %) ;
//   • thème clair / sombre (renvoi vers les Paramètres) ;
//   • engagements d'accessibilité de Biashara Yangu.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/accessibilite_manager.dart';

class AccessibilitePage extends StatelessWidget {
  const AccessibilitePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AccessibiliteManager accessibilite =
        Provider.of<AccessibiliteManager>(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Accessibilité',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          _carte(
            context,
            titre: 'Taille du texte',
            icone: Icons.format_size_rounded,
            enfants: <Widget>[
              Text(
                'Choisissez la taille qui vous convient : elle s\'applique '
                'immédiatement à toute l\'application.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AccessibiliteManager.echelles
                    .map((double echelle) => ChoiceChip(
                          label: Text('${(echelle * 100).round()} %'),
                          selected: accessibilite.echelle == echelle,
                          onSelected: (_) =>
                              accessibilite.setEchelle(echelle),
                        ))
                    .toList(growable: false),
              ),
              const SizedBox(height: 10),
              Text(
                'Aperçu : « Biashara Yangu — gérez votre commerce '
                'en toute simplicité. »',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _carte(
            context,
            titre: 'Thème clair / sombre',
            icone: Icons.contrast_rounded,
            enfants: <Widget>[
              Text(
                'Le thème se règle dans « Paramètres → Application → Thème ». '
                'Le mode sombre réduit la fatigue visuelle et économise la '
                'batterie sur les écrans OLED.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _carte(
            context,
            titre: 'Nos engagements',
            icone: Icons.volunteer_activism_rounded,
            enfants: const <Widget>[
              _Puce(
                'Les boutons et zones tactiles respectent une taille minimale '
                'confortable (44 px).',
              ),
              _Puce(
                'Les textes utilisent des contrastes renforcés (fond clair '
                'ou sombre, jamais gris sur gris).',
              ),
              _Puce(
                'La taille du texte s\'adapte aussi au réglage '
                'd\'accessibilité de votre téléphone.',
              ),
              _Puce(
                'Les messages d\'erreur sont rédigés en français simple, '
                'sans jargon technique.',
              ),
              _Puce(
                'Aucune information essentielle ne dépend uniquement de la '
                'couleur (icônes + textes systématiques).',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _carte(
            context,
            titre: 'Un obstacle ? Dites-le-nous',
            icone: Icons.support_agent_rounded,
            enfants: <Widget>[
              Text(
                'Si un écran vous paraît difficile à utiliser (lecture, '
                'couleurs, boutons trop petits), signalez-le à l\'équipe '
                'Biashara Yangu (support@biasharayangu.cd). Les retours sont '
                'étudiés à chaque mise à jour.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _carte(
    BuildContext context, {
    required String titre,
    required IconData icone,
    required List<Widget> enfants,
  }) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icone, size: 20, color: AppCouleurs.marine),
              const SizedBox(width: 8),
              Text(
                titre,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...enfants,
        ],
      ),
    );
  }
}

class _Puce extends StatelessWidget {
  const _Puce(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle_rounded,
                size: 16, color: AppCouleurs.succes),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texte,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
