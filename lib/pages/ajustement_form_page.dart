// lib/pages/ajustement_form_page.dart
//
// MODULE 9 — AJUSTEMENT DE STOCK (INVENTAIRE).
//
// Corrige l'écart entre le stock théorique (serveur) et le stock physique
// compté : le magasinier saisit la QUANTITÉ PHYSIQUE, l'écart est calculé
// (`physique − théorique`) et envoyé au serveur qui insère un mouvement dans
// `public.ajustements` (le trigger applique le delta au stock).
//
// La RAISON est OBLIGATOIRE (exigence du cahier des charges) et vérifiée
// côté serveur comme côté application.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/services/stock_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/statut_stock_chip.dart';

/// Formulaire d'ajustement de stock (Module 9).
class AjustementFormPage extends StatefulWidget {
  const AjustementFormPage({super.key, this.article});

  /// Article présélectionné (venu de la fiche stock) ; `null` pour choisir.
  final Article? article;

  @override
  State<AjustementFormPage> createState() => _AjustementFormPageState();
}

class _AjustementFormPageState extends State<AjustementFormPage> {
  final StockService _service = StockService.instance;

  final TextEditingController _quantiteController = TextEditingController();
  final TextEditingController _raisonController = TextEditingController();

  List<Article> _articles = const <Article>[];
  Article? _article;
  bool _chargementListe = false;
  String? _erreurListe;

  bool _enregistrement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _quantiteController.addListener(_rafraichir);
    _raisonController.addListener(_rafraichir);

    final Article? initial = widget.article;
    if (initial != null) {
      _article = initial;
      _quantiteController.text = formatQuantite(initial.quantite);
    } else {
      _chargerArticles();
    }
  }

  @override
  void dispose() {
    _quantiteController.removeListener(_rafraichir);
    _raisonController.removeListener(_rafraichir);
    _quantiteController.dispose();
    _raisonController.dispose();
    super.dispose();
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  Future<void> _chargerArticles() async {
    setState(() {
      _chargementListe = true;
      _erreurListe = null;
    });

    try {
      final List<Article> articles = await _service.getStock();
      if (!mounted) return;
      setState(() {
        _articles = articles;
        _chargementListe = false;
      });
    } catch (e) {
      debugPrint('AjustementFormPage._chargerArticles: $e');
      if (!mounted) return;
      setState(() {
        _chargementListe = false;
        _erreurListe = 'Impossible de charger la liste des articles.';
      });
    }
  }

  void _selectionnerArticle(Article? article) {
    setState(() {
      _article = article;
      if (article != null) {
        _quantiteController.text = formatQuantite(article.quantite);
      }
    });
  }

  double? get _quantitePhysique =>
      double.tryParse(_quantiteController.text.trim().replaceAll(',', '.'));

  double? get _ecart {
    final Article? article = _article;
    final double? physique = _quantitePhysique;
    if (article == null || physique == null) return null;
    return physique - article.quantite;
  }

  bool get _ecartNul {
    final double? ecart = _ecart;
    return ecart != null && ecart.abs() <= 0.000001;
  }

  Future<void> _enregistrer() async {
    final Article? article = _article;
    final double? physique = _quantitePhysique;
    final String raison = _raisonController.text.trim();

    if (article == null) {
      setState(() => _erreur = 'Choisissez un article à ajuster.');
      return;
    }
    if (physique == null || physique < 0) {
      setState(() => _erreur = 'Saisissez la quantité physique comptée.');
      return;
    }
    if (_ecartNul) {
      setState(() => _erreur =
          "Aucun écart à corriger : la quantité saisie est identique au stock actuel.");
      return;
    }
    if (raison.length < 3) {
      setState(() => _erreur =
          "Indiquez la raison de l'ajustement (3 caractères minimum).");
      return;
    }

    setState(() {
      _enregistrement = true;
      _erreur = null;
    });

    try {
      final ResultatAjustement resultat = await _service.ajuster(
        produitId: article.id,
        quantitePhysique: physique,
        raison: raison,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stock ajusté : ${formatQuantite(resultat.stockAvant)} → '
            '${formatQuantite(resultat.stockApres)} ${article.uniteMesure} '
            '(${formatQuantiteSignee(resultat.delta)}).',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop(true);
    } on StockServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _enregistrement = false;
        _erreur = e.message;
      });
    } catch (e, st) {
      debugPrint('AjustementFormPage._enregistrer: $e\n$st');
      if (!mounted) return;
      setState(() {
        _enregistrement = false;
        _erreur = 'Une erreur inattendue est survenue.';
      });
    }
  }

  Widget _carteArticle() {
    final ThemeData theme = Theme.of(context);
    final Article? article = _article;

    if (widget.article != null && article != null) {
      return Card(
        elevation: 0,
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Icon(Icons.inventory_2_rounded, color: theme.colorScheme.primary),
          title: Text(
            article.nom,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'Stock théorique : ${formatQuantite(article.quantite)} ${article.uniteMesure}',
          ),
          trailing: StatutStockChip(statut: article.statutStock),
        ),
      );
    }

    if (_chargementListe) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_erreurListe != null) {
      return Card(
        elevation: 0,
        color: Colors.red.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Icon(Icons.error_outline, color: Colors.red.shade700),
          title: Text(_erreurListe!),
          trailing: TextButton(
            onPressed: _chargerArticles,
            child: const Text('Réessayer'),
          ),
        ),
      );
    }

    return AppDropdownField<Article>(
      label: 'Article',
      value: _article,
      prefixIcon: Icons.inventory_2_outlined,
      hint: 'Choisir un article…',
      items: _articles
          .map((Article a) => DropdownMenuItem<Article>(
                value: a,
                child: Text(
                  '${a.nom} (${formatQuantite(a.quantite)} ${a.uniteMesure})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(growable: false),
      onChanged: _selectionnerArticle,
    );
  }

  Widget _apercuEcart() {
    final ThemeData theme = Theme.of(context);
    final Article? article = _article;
    final double? ecart = _ecart;

    if (article == null || ecart == null) return const SizedBox.shrink();

    final Color couleur = ecart.abs() <= 0.000001
        ? Colors.grey.shade700
        : (ecart > 0 ? Colors.green.shade700 : Colors.red.shade700);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        ecart.abs() <= 0.000001
            ? 'Aucun écart : la quantité saisie est identique au stock actuel.'
            : 'Écart à corriger : ${formatQuantiteSignee(ecart)} ${article.uniteMesure} '
                '(théorique ${formatQuantite(article.quantite)} → physique ${formatQuantite(_quantitePhysique ?? 0)}).',
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: couleur,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Article? article = _article;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ajuster le stock',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _carteArticle(),
          const SizedBox(height: 14),

          if (article != null) ...<Widget>[
            TextField(
              controller: _quantiteController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantité physique comptée (${article.uniteMesure})',
                prefixIcon: const Icon(Icons.tune_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            _apercuEcart(),
            const SizedBox(height: 12),
            TextField(
              controller: _raisonController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Raison (obligatoire)',
                hintText: 'Ex. : casse, vol, erreur de comptage…',
                prefixIcon: const Icon(Icons.edit_note_rounded),
                helperText: 'Toute correction est historisée dans les ajustements.',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ],

          if (_erreur != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _erreur!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ),
          ],

          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _enregistrement || article == null ? null : _enregistrer,
            icon: _enregistrement
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_enregistrement ? 'Enregistrement…' : "Enregistrer l'ajustement"),
          ),
        ],
      ),
    );
  }
}
