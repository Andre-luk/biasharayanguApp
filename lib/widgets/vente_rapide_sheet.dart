// lib/widgets/vente_rapide_sheet.dart
//
// ⚡ MODULE 23 — VENTE RAPIDE (MODE SIMPLE).
//
// Un commerçant pressé ouvre cette feuille depuis l'accueil :
//   • la liste vient de SUPABASE (vérité partagée entre tous les téléphones) ;
//   • « Nouveau produit » ne demande qu'un NOM et un PRIX ;
//   • un appui sur un produit vend 1 unité (quantité modifiable).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Ouvre la feuille de vente rapide.
Future<void> ouvrirVenteRapide(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => const _VenteRapideSheet(),
  );
}

class _VenteRapideSheet extends StatefulWidget {
  const _VenteRapideSheet();

  @override
  State<_VenteRapideSheet> createState() => _VenteRapideSheetState();
}

class _VenteRapideSheetState extends State<_VenteRapideSheet> {
  final TextEditingController _recherche = TextEditingController();

  List<Article> _articles = const <Article>[];
  bool _chargement = true;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _recherche.addListener(() => setState(() {}));
    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final List<Article> articles = await ArticleService.instance.getArticles();
      if (!mounted) return;
      setState(() {
        _articles = articles;
        _chargement = false;
      });
    } catch (e) {
      debugPrint('VenteRapide._charger : $e');
      if (!mounted) return;
      setState(() => _chargement = false);
      _message('Impossible de charger les produits.', erreur: true);
    }
  }

  List<Article> get _filtres {
    final String q = _recherche.text.trim().toLowerCase();
    if (q.isEmpty) return _articles;
    return _articles
        .where((Article a) => a.nom.toLowerCase().contains(q))
        .toList(growable: false);
  }

  Future<void> _nouveauProduit() async {
    final TextEditingController nom = TextEditingController();
    final TextEditingController prix = TextEditingController();
    final GlobalKey<FormState> cle = GlobalKey<FormState>();

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Nouveau produit'),
        content: Form(
          key: cle,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: nom,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nom du produit',
                  hintText: 'Ex. Eau 1,5 L',
                ),
                validator: (String? v) =>
                    (v ?? '').trim().isEmpty ? 'Indiquez un nom.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: prix,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Prix de vente',
                  suffixText: 'par unité',
                ),
                validator: (String? v) {
                  final double? p =
                      double.tryParse((v ?? '').replaceAll(',', '.'));
                  return (p == null || p <= 0) ? 'Prix invalide.' : null;
                },
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (cle.currentState?.validate() == true) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    final String nomValeur = nom.text.trim();
    final double? prixValeur =
        double.tryParse(prix.text.replaceAll(',', '.'));
    nom.dispose();
    prix.dispose();

    if (valide != true || prixValeur == null) return;

    setState(() => _enCours = true);
    try {
      await ArticleService.instance.creerArticleRapide(
        nom: nomValeur,
        prixVente: prixValeur,
      );
      await _charger();
      if (!mounted) return;
      _message('« $nomValeur » est prêt : touchez-le pour vendre.');
    } on ArticleServiceException catch (e) {
      _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _vendre(Article article) async {
    final TextEditingController q = TextEditingController(text: '1');

    final double? quantite = await showDialog<double>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(article.nom),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${formatMontant(article.prixVente)} l\'unité — '
              '${article.stockIllimite ? 'stock non suivi' : 'stock ${formatQuantite(article.quantite)}'}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: q,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'Quantité',
                suffixText: article.uniteMesure,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              double.tryParse(q.text.replaceAll(',', '.')),
            ),
            child: const Text('Encaisser'),
          ),
        ],
      ),
    );

    q.dispose();
    if (quantite == null || quantite <= 0) return;

    setState(() => _enCours = true);
    try {
      final VenteEnregistree vente =
          await VenteService.instance.venteRapide(
        produitId: article.id,
        quantite: quantite,
      );
      await _charger();
      if (!mounted) return;
      _message('Vente ${vente.numeroVente} : ${formatMontant(vente.total)}');
    } on VenteServiceException catch (e) {
      _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? const Color(0xFFB91C1C) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double hauteur = MediaQuery.of(context).size.height * 0.82;

    return SizedBox(
      height: hauteur,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: <Widget>[
                const Icon(Icons.bolt_rounded),
                const SizedBox(width: 8),
                Text('Vente rapide', style: theme.textTheme.titleLarge),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _enCours ? null : _nouveauProduit,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Nouveau'),
                ),
              ],
            ),
          ),
          if (_enCours) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _recherche,
              decoration: const InputDecoration(
                hintText: 'Rechercher un produit…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _chargement
                ? const Center(child: ModernLoader(legende: 'Chargement…'))
                : _filtres.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Aucun produit. Touchez « Nouveau » : un nom et '
                            'un prix suffisent.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: _filtres.length,
                        separatorBuilder: (BuildContext c, int i) =>
                            const Divider(height: 1),
                        itemBuilder: (BuildContext c, int i) {
                          final Article a = _filtres[i];
                          return ListTile(
                            title: Text(a.nom, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              <String>[
                                formatMontant(a.prixVente),
                                if (a.stockIllimite)
                                  '∞'
                                else
                                  'stock ${formatQuantite(a.quantite)}',
                                if (a.categorie.isNotEmpty) a.categorie,
                              ].join(' • '),
                            ),
                            trailing: FilledButton.tonal(
                              onPressed: _enCours ? null : () => _vendre(a),
                              child: const Text('Vendre'),
                            ),
                            onTap: _enCours ? null : () => _vendre(a),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
