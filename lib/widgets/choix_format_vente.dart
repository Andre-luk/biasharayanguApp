// lib/widgets/choix_format_vente.dart
//
// 🧾 MULTI-FORMATS DE VENTE (pharmacie, boutique, alimentation).
//
// Un même article peut se vendre sous PLUSIEURS formats, chacun à son prix :
//   • à l'unité            → « 1 comprimé », « 1 bouteille » ;
//   • en plaquette/sachet  → « Plaquette de 10 », « Sachet de 6 » ;
//   • en boîte/carton      → « Boîte de 20 », « Carton de 24 ».
//
// Techniquement, ces formats sont les `conditionnements` de l'article
// (Module 5) : chaque emballage porte son propre prix de vente et le nombre
// d'unités de base qu'il contient. Ce sélecteur rend le choix EXPLICITE au
// moment de la vente — plus besoin d'imprimer un QR code par format.
//
// ⚠️ Les prix affichés proviennent de la base (jamais saisis au comptoir).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Résultat du sélecteur : [format] `null` = vente à l'unité de base.
class ChoixFormatVente {
  const ChoixFormatVente(this.format, {this.quantite = 1});

  /// Conditionnement retenu, ou `null` pour l'unité de base.
  final Conditionnement? format;

  /// Quantité demandée (unités vendues de ce format).
  final double quantite;
}

/// Ouvre le sélecteur de format. Retourne `null` si l'utilisateur annule.
Future<ChoixFormatVente?> choisirFormatVente(
  BuildContext context, {
  required Article article,
  required List<Conditionnement> conditionnements,
}) {
  return showDialog<ChoixFormatVente>(
    context: context,
    builder: (BuildContext ctx) => _DialogueFormatVente(
      article: article,
      conditionnements: conditionnements,
    ),
  );
}

class _DialogueFormatVente extends StatefulWidget {
  const _DialogueFormatVente({
    required this.article,
    required this.conditionnements,
  });

  final Article article;
  final List<Conditionnement> conditionnements;

  @override
  State<_DialogueFormatVente> createState() => _DialogueFormatVenteState();
}

class _DialogueFormatVenteState extends State<_DialogueFormatVente> {
  /// `null` = unité de base.
  Conditionnement? _choix;
  late final TextEditingController _quantite;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _quantite = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _quantite.dispose();
    super.dispose();
  }

  double get _prixUnitaire =>
      _choix?.prixVente ?? widget.article.prixVente.toDouble();

  String get _libelleUnite =>
      _choix?.libelle ?? widget.article.uniteMesure;

  double get _pasQuantite {
    // Un format emballé se vend à l'unité entière ; l'unité de base peut se
    // vendre au poids (boucherie) → pas de 0,5.
    if (_choix != null) return 1;
    return widget.article.vendableAuPoids ? 0.5 : 1;
  }

  double get _minimum => _choix != null ? 1 : _pasQuantite;

  double get _sousTotal => _prixUnitaire * (_analyser(_quantite.text) ?? 0);

  static double? _analyser(String texte) {
    final String propre = texte.trim().replaceAll(',', '.');
    if (propre.isEmpty) return null;
    return double.tryParse(propre);
  }

  void _valider() {
    final double? q = _analyser(_quantite.text);
    if (q == null || q < _minimum) {
      setState(() => _erreur = 'Quantité minimale : $_minimum.');
      return;
    }
    Navigator.of(context).pop(ChoixFormatVente(_choix, quantite: q));
  }

  static String _texte(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text('Format de vente — ${widget.article.nom}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Un même article peut avoir un prix à l\'unité et un autre '
                'prix la plaquette, le sachet ou le carton. Choisissez :',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),

              // ------------------------------------------------ unité de base
              _option(
                cs,
                selectionne: _choix == null,
                titre: 'À l\'unité — ${widget.article.uniteMesure}',
                sousTitre: '1 ${widget.article.uniteMesure}',
                prix: widget.article.prixVente.toDouble(),
                onTap: () => setState(() {
                  _choix = null;
                  _quantite.text = '1';
                  _erreur = null;
                }),
              ),

              // ------------------------------------------------ emballages
              for (final Conditionnement c in widget.conditionnements)
                _option(
                  cs,
                  selectionne: _choix?.id == c.id,
                  titre: c.libelle,
                  sousTitre: '${_texte(c.quantiteUnitesBase)} '
                      '${Conditionnement.pluriel(widget.article.uniteMesure, c.quantiteUnitesBase)}',
                  prix: c.prixVente,
                  onTap: () => setState(() {
                    _choix = c;
                    _quantite.text = '1';
                    _erreur = null;
                  }),
                ),

              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () {
                      final double q = _analyser(_quantite.text) ?? _minimum;
                      final double n = q - _pasQuantite;
                      setState(() {
                        _quantite.text = _texte(n < _minimum ? _minimum : n);
                        _erreur = null;
                      });
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Diminuer',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _quantite,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: 'Quantité ($_libelleUnite)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() => _erreur = null),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      final double q = _analyser(_quantite.text) ?? 0;
                      setState(() {
                        _quantite.text = _texte(q + _pasQuantite);
                        _erreur = null;
                      });
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Augmenter',
                  ),
                ],
              ),
              if (_erreur != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(_erreur!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text('Sous-total',
                        style: TextStyle(color: cs.onPrimaryContainer)),
                    Text(
                      formatMontant(_sousTotal),
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
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
        FilledButton.icon(
          onPressed: _valider,
          icon: const Icon(Icons.add_shopping_cart, size: 18),
          label: const Text('Ajouter au panier'),
        ),
      ],
    );
  }

  Widget _option(
    ColorScheme cs, {
    required bool selectionne,
    required String titre,
    required String sousTitre,
    required double prix,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selectionne ? cs.primary : cs.outlineVariant,
              width: selectionne ? 2 : 1,
            ),
            color: selectionne ? cs.primaryContainer.withValues(alpha: 0.35) : null,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selectionne
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selectionne ? cs.primary : cs.outline,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(titre,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(sousTitre,
                        style: TextStyle(fontSize: 11.5, color: cs.outline)),
                  ],
                ),
              ),
              Text(
                formatMontant(prix),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
