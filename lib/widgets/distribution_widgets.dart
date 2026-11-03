// lib/widgets/distribution_widgets.dart
//
// 🚚 MODULE 24 — WIDGETS PARTAGÉS DU MODULE DISTRIBUTION.
//
// Volontairement sobres : ils s'appuient sur le thème global (cartes 20,
// boutons 52/16) et ne redéfinissent aucune AppBar ni aucun champ.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/utils/format_utils.dart';

/// Grand chiffre du tableau de bord.
class CarteKpiDistribution extends StatelessWidget {
  const CarteKpiDistribution({
    super.key,
    required this.icone,
    required this.libelle,
    required this.valeur,
    this.sousTitre,
    this.couleur,
    this.onTap,
  });

  final IconData icone;
  final String libelle;
  final String valeur;
  final String? sousTitre;
  final Color? couleur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color teinte = couleur ?? theme.colorScheme.primary;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: teinte.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icone, size: 20, color: teinte),
                  ),
                  const Spacer(),
                  if (sousTitre != null)
                    Flexible(
                      child: Text(
                        sousTitre!,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                valeur,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: teinte,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                libelle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petite étiquette de statut.
class PuceDistribution extends StatelessWidget {
  const PuceDistribution({
    super.key,
    required this.libelle,
    this.couleur,
    this.icone,
  });

  final String libelle;
  final Color? couleur;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color teinte = couleur ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: teinte.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icone != null) ...<Widget>[
            Icon(icone, size: 13, color: teinte),
            const SizedBox(width: 4),
          ],
          Text(
            libelle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: teinte,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloc titré du tableau de bord.
class SectionDistribution extends StatelessWidget {
  const SectionDistribution({
    super.key,
    required this.titre,
    this.sousTitre,
    required this.child,
    this.action,
  });

  final String titre;
  final String? sousTitre;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      titre,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (sousTitre != null)
                      Text(
                        sousTitre!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Tuile d'accès à un sous-espace.
class TuileDistribution extends StatelessWidget {
  const TuileDistribution({
    super.key,
    required this.icone,
    required this.libelle,
    this.badge,
    required this.onTap,
    this.couleur,
    this.verrouillee = false,
  });

  final IconData icone;
  final String libelle;
  final int? badge;
  final VoidCallback onTap;
  final Color? couleur;
  final bool verrouillee;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color teinte = couleur ?? theme.colorScheme.primary;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: verrouillee ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Icon(
                    verrouillee ? Icons.lock_outline_rounded : icone,
                    size: 26,
                    color: verrouillee
                        ? theme.colorScheme.outline
                        : teinte,
                  ),
                  if ((badge ?? 0) > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${badge!}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                libelle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Description d'un champ quantité demandé à l'utilisateur.
class ArticleQuantite {
  ArticleQuantite({
    required this.id,
    required this.nom,
    this.unite = '',
    this.valeurInitiale = 0,
    this.min = 0,
    this.max,
    this.actif = true,
    this.description,
  });

  final String id;
  final String nom;
  final String unite;
  final double valeurInitiale;
  final double min;
  final double? max;
  final bool actif;
  final String? description;
}

/// Demande une quantité par article et renvoie `id → quantité`.
Future<Map<String, double>?> dialogueQuantites(
  BuildContext context, {
  required String titre,
  required List<ArticleQuantite> articles,
  String libelleValider = 'Valider',
  String? sousTitre,
}) {
  return showDialog<Map<String, double>>(
    context: context,
    builder: (BuildContext ctx) => _DialogueQuantites(
      titre: titre,
      sousTitre: sousTitre,
      articles: articles,
      libelleValider: libelleValider,
    ),
  );
}

class _DialogueQuantites extends StatefulWidget {
  const _DialogueQuantites({
    required this.titre,
    required this.articles,
    required this.libelleValider,
    this.sousTitre,
  });

  final String titre;
  final String? sousTitre;
  final List<ArticleQuantite> articles;
  final String libelleValider;

  @override
  State<_DialogueQuantites> createState() => _DialogueQuantitesState();
}

class _DialogueQuantitesState extends State<_DialogueQuantites> {
  late final Map<String, TextEditingController> _champs;

  @override
  void initState() {
    super.initState();
    _champs = <String, TextEditingController>{
      for (final ArticleQuantite a in widget.articles)
        a.id: TextEditingController(
          text: _texteNombre(a.valeurInitiale),
        ),
    };
  }

  @override
  void dispose() {
    for (final TextEditingController c in _champs.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _texteNombre(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  static double? _lire(String texte) {
    final String t = texte.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  void _valider() {
    final Map<String, double> valeurs = <String, double>{};
    for (final ArticleQuantite a in widget.articles) {
      if (!a.actif) continue;
      final double? v = _lire(_champs[a.id]!.text);
      if (v == null || v < a.min - 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quantité invalide pour « ${a.nom} ».')),
        );
        return;
      }
      if (a.max != null && v > a.max! + 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('« ${a.nom} » ne peut pas dépasser '
                '${_texteNombre(a.max!)} ${a.unite}.'),
          ),
        );
        return;
      }
      valeurs[a.id] = v;
    }
    Navigator.of(context).pop(valeurs);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.sousTitre != null) ...<Widget>[
                Text(widget.sousTitre!),
                const SizedBox(height: 12),
              ],
              for (final ArticleQuantite a in widget.articles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              a.nom,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            if (a.description != null)
                              Text(
                                a.description!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _champs[a.id],
                          enabled: a.actif,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9., ]')),
                          ],
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            isDense: true,
                            suffixText: a.unite,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valider,
          child: Text(widget.libelleValider),
        ),
      ],
    );
  }
}

/// Demande un texte libre (motif, décision, note).
Future<String?> dialogueTexte(
  BuildContext context, {
  required String titre,
  String label = 'Motif',
  String? initial,
  bool obligatoire = true,
  int lignes = 2,
}) {
  final TextEditingController controller =
      TextEditingController(text: initial ?? '');

  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) {
      String? erreur;
      return StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          return AlertDialog(
            title: Text(titre),
            content: TextField(
              controller: controller,
              autofocus: true,
              minLines: lignes,
              maxLines: lignes + 3,
              decoration: InputDecoration(
                labelText: label,
                errorText: erreur,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () {
                  final String v = controller.text.trim();
                  if (obligatoire && v.isEmpty) {
                    setState(() => erreur = 'Ce champ est obligatoire.');
                    return;
                  }
                  Navigator.of(ctx).pop(v);
                },
                child: const Text('Confirmer'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Confirmation simple.
Future<bool> confirmerDistribution(
  BuildContext context, {
  required String titre,
  required String message,
  String libelleConfirmer = 'Confirmer',
  bool danger = false,
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(titre),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(libelleConfirmer),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Ligne « libellé — valeur » compacte.
Widget ligneDistribution(String libelle, String valeur,
    {bool gras = false, Color? couleur}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            libelle,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          valeur,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            fontWeight: gras ? FontWeight.w800 : FontWeight.w600,
            color: couleur,
          ),
        ),
      ],
    ),
  );
}

/// Formate une quantité sans zéros inutiles.
String quantiteDistribution(double valeur, {String unite = ''}) {
  final String nombre = formatQuantite(valeur);
  return unite.isEmpty ? nombre : '$nombre $unite';
}

/// Formate un montant dans la devise de l'entreprise.
String montantDistribution(double valeur, {String? devise}) {
  final String? unite = devise == null
      ? null
      : (devise.toUpperCase() == 'USD' ? r'$' : devise);
  return formatMontant(valeur, devise: unite);
}
