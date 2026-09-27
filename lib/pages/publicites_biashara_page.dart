// lib/pages/publicites_biashara_page.dart
//
// 🛒 MODULE 19 — « PUBLICITÉS BIASHARA ».
//
// Espace PRÉPARATOIRE, professionnel et honnête :
//   • le commerçant compose ses campagnes (produit, boutique, promotion,
//     offre spéciale), choisit un ciblage et les SOUMET ;
//   • la plateforme les ACTIVE (modération) — mode `modePlateforme` ;
//   • une annonce porte TOUJOURS la mention « PUBLICITÉ » et n'est jamais
//     mélangée aux résultats organiques : c'est une règle du module, pas une
//     option d'affichage.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/pages/publicite_biashara_form_page.dart';
import 'package:biashara_yangu/services/publicite_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class PublicitesBiasharaPage extends StatefulWidget {
  const PublicitesBiasharaPage({super.key, this.modePlateforme = false});

  /// `true` = écran de MODÉRATION (personnel de la plateforme) : on voit toutes
  /// les campagnes soumises et on peut les activer ou les refuser.
  final bool modePlateforme;

  @override
  State<PublicitesBiasharaPage> createState() => _PublicitesBiasharaPageState();
}

class _PublicitesBiasharaPageState extends State<PublicitesBiasharaPage> {
  final PubliciteService _publicites = PubliciteService.instance;

  List<PubliciteBiashara> _liste = const <PubliciteBiashara>[];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final List<PubliciteBiashara> liste = widget.modePlateforme
          ? await _publicites.moderation(statut: 'soumise')
          : await _publicites.lister();

      if (!mounted) return;
      setState(() {
        _liste = liste;
        _chargement = false;
      });
    } on PubliciteException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  Future<void> _changerStatut(
    PubliciteBiashara publicite,
    StatutPublicite statut, {
    String? note,
  }) async {
    try {
      await _publicites.changerStatut(id: publicite.id, statut: statut, note: note);
      _message('Statut mis à jour : ${statut.libelle}.');
      await _charger();
    } on PubliciteException catch (e) {
      _message(e.message);
    }
  }

  Future<void> _nouvelle() async {
    final bool? modifie = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext ctx) => const PubliciteBiasharaFormPage(),
      ),
    );
    if (modifie == true) await _charger();
  }

  Future<void> _modifier(PubliciteBiashara publicite) async {
    final bool? modifie = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext ctx) =>
            PubliciteBiasharaFormPage(publicite: publicite),
      ),
    );
    if (modifie == true) await _charger();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.modePlateforme
            ? 'Modération des publicités'
            : 'Mes publicités Biashara'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Recharger',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: widget.modePlateforme
          ? null
          : FloatingActionButton.extended(
              onPressed: _nouvelle,
              icon: const Icon(Icons.campaign_rounded),
              label: const Text('Nouvelle campagne'),
            ),
      body: _chargement
          ? const Center(child: ModernLoader(taille: 46))
          : (_erreur != null ? _etatErreur(theme) : _contenu(theme)),
    );
  }

  Widget _etatErreur(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.campaign_outlined,
                size: 44, color: AppCouleurs.alerte),
            const SizedBox(height: 12),
            Text(
              _erreur ?? 'Publicités indisponibles.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenu(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppCouleurs.orange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.info_outline_rounded,
                    color: AppCouleurs.orangeFonce),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.modePlateforme
                        ? 'Seules les campagnes que vous ACTIVEZ sont diffusées. '
                            'Une annonce porte toujours la mention « PUBLICITÉ » '
                            'et n\'est jamais mélangée aux résultats organiques.'
                        : 'Une campagne soumise est vérifiée par Biashara avant '
                            'diffusion. Elle apparaît dans un emplacement dédié, '
                            'toujours marquée « PUBLICITÉ », jamais au milieu '
                            'des résultats organiques.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_liste.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: <Widget>[
                  const Icon(Icons.campaign_rounded,
                      size: 44, color: AppCouleurs.orange),
                  const SizedBox(height: 10),
                  Text(
                    widget.modePlateforme
                        ? 'Aucune campagne en attente de validation.'
                        : 'Aucune campagne pour le moment.\n'
                            'Préparez une annonce pour faire connaître un '
                            'produit ou une promotion.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          else
            for (final PubliciteBiashara publicite in _liste)
              _carte(theme, publicite),
        ],
      ),
    );
  }

  Widget _carte(ThemeData theme, PubliciteBiashara publicite) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_iconeType(publicite.typeContenu),
                    color: AppCouleurs.marine),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    publicite.titre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                _puceStatut(theme, publicite.statut),
              ],
            ),
            if (publicite.message != null &&
                publicite.message!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(publicite.message!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Text(
              'Ciblage : ${publicite.ciblageLisible}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (publicite.boutiqueNom != null)
              Text(
                'Boutique : ${publicite.boutiqueNom}'
                '${publicite.ville == null ? '' : ' · ${publicite.ville}'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (publicite.prixPromo != null)
              Text(
                'Prix promotionnel : ${formatMontant(publicite.prixPromo!)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppCouleurs.orangeFonce,
                  fontWeight: FontWeight.w800,
                ),
              ),
            if (publicite.noteModeration != null &&
                publicite.noteModeration!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Note de Biashara : ${publicite.noteModeration}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppCouleurs.alerte,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              children: <Widget>[
                _compteur(theme, 'Affichages', publicite.impressions),
                _compteur(theme, 'Clics', publicite.clics),
                _compteur(theme, 'Conversions', publicite.conversions),
                if (publicite.tauxClic != null)
                  _compteur(theme, 'Taux de clic %', publicite.tauxClic!),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _actions(theme, publicite),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(ThemeData theme, PubliciteBiashara publicite) {
    // MODÉRATION (plateforme).
    if (widget.modePlateforme) {
      return <Widget>[
        FilledButton.icon(
          onPressed: () =>
              _changerStatut(publicite, StatutPublicite.active),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Activer'),
        ),
        OutlinedButton.icon(
          onPressed: () => _changerStatut(
            publicite,
            StatutPublicite.refusee,
            note: 'Refusée par la plateforme',
          ),
          icon: const Icon(Icons.block_rounded, size: 18),
          label: const Text('Refuser'),
        ),
      ];
    }

    final List<Widget> actions = <Widget>[];

    if (publicite.statut.modifiable) {
      actions.add(OutlinedButton.icon(
        onPressed: () => _modifier(publicite),
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text('Modifier'),
      ));
    }

    switch (publicite.statut) {
      case StatutPublicite.brouillon:
      case StatutPublicite.refusee:
        actions.add(FilledButton.icon(
          onPressed: () => _changerStatut(publicite, StatutPublicite.soumise),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Soumettre'),
        ));
        break;
      case StatutPublicite.soumise:
        actions.add(OutlinedButton.icon(
          onPressed: () => _changerStatut(publicite, StatutPublicite.pause),
          icon: const Icon(Icons.pause_rounded, size: 18),
          label: const Text('Annuler la demande'),
        ));
        break;
      case StatutPublicite.active:
        actions.add(OutlinedButton.icon(
          onPressed: () => _changerStatut(publicite, StatutPublicite.pause),
          icon: const Icon(Icons.pause_rounded, size: 18),
          label: const Text('Mettre en pause'),
        ));
        break;
      case StatutPublicite.pause:
        actions.add(FilledButton.icon(
          onPressed: () => _changerStatut(publicite, StatutPublicite.soumise),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Reprendre'),
        ));
        break;
      case StatutPublicite.terminee:
        break;
    }

    if (publicite.statut != StatutPublicite.terminee) {
      actions.add(TextButton.icon(
        onPressed: () => _changerStatut(publicite, StatutPublicite.terminee),
        icon: const Icon(Icons.stop_rounded, size: 18),
        label: const Text('Terminer'),
      ));
    }

    return actions;
  }

  Widget _compteur(ThemeData theme, String libelle, int valeur) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$valeur',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          libelle,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _puceStatut(ThemeData theme, StatutPublicite statut) {
    final Color couleur = switch (statut) {
      StatutPublicite.active => AppCouleurs.succes,
      StatutPublicite.soumise => AppCouleurs.info,
      StatutPublicite.refusee => AppCouleurs.danger,
      StatutPublicite.pause => AppCouleurs.alerte,
      StatutPublicite.terminee => theme.colorScheme.onSurfaceVariant,
      StatutPublicite.brouillon => AppCouleurs.marine,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statut.libelle,
        style: theme.textTheme.labelSmall?.copyWith(
          color: couleur,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  IconData _iconeType(TypeContenuPublicite type) {
    switch (type) {
      case TypeContenuPublicite.produit:
        return Icons.inventory_2_rounded;
      case TypeContenuPublicite.boutique:
        return Icons.storefront_rounded;
      case TypeContenuPublicite.promotion:
        return Icons.local_offer_rounded;
      case TypeContenuPublicite.offre:
        return Icons.redeem_rounded;
    }
  }
}
