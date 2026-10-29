// lib/pages/pesee_rapide_page.dart
//
// ⚖️ MODULE 23 — PESÉE RAPIDE (BOUCHERIE, PRIMEUR, POISSONNERIE…).
//
// Une boutique qui vend au poids travaille devant sa balance :
//
//   1. le vendeur choisit (ou scanne) le produit pesé ;
//   2. il vérifie le PRIX AU KILO affiché (défini sur l'article) ;
//   3. il saisit le POIDS que la balance affiche ;
//   4. il encaisse immédiatement — ou met la ligne au panier.
//
// Le produit reste sélectionné après la vente : le client suivant est pesé
// et encaissé en quelques secondes. Aucun écran intermédiaire.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/article_scanne.dart';
import 'package:biashara_yangu/models/pesee.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class PeseeRapidePage extends StatefulWidget {
  const PeseeRapidePage({super.key});

  @override
  State<PeseeRapidePage> createState() => _PeseeRapidePageState();
}

class _PeseeRapidePageState extends State<PeseeRapidePage> {
  final TextEditingController _recherche = TextEditingController();
  final TextEditingController _poids = TextEditingController(text: '1');

  List<Article> _produits = const <Article>[];
  Article? _choisi;
  bool _chargement = true;
  bool _enCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _recherche.addListener(() => setState(() {}));
    _poids.addListener(() => setState(() {}));
    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    _poids.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final List<Article> articles = await ArticleService.instance.getArticles();
      if (!mounted) return;
      setState(() {
        _produits = articles
            .where((Article a) => a.vendableAuPoids)
            .toList(growable: false);
        _chargement = false;
      });
    } catch (e) {
      debugPrint('PeseeRapidePage._charger : $e');
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = 'Impossible de charger les produits pesés.';
      });
    }
  }

  List<Article> get _filtres {
    final String q = _recherche.text.trim().toLowerCase();
    if (q.isEmpty) return _produits;
    return _produits
        .where((Article a) => a.nom.toLowerCase().contains(q))
        .toList(growable: false);
  }

  double? get _poidsSaisi => PeseeCalculs.analyser(_poids.text);

  double get _total {
    final Article? a = _choisi;
    final double? p = _poidsSaisi;
    if (a == null || p == null) return 0;
    return PeseeCalculs.total(poids: p, prixUnitaire: a.prixVente);
  }

  void _choisir(Article article) {
    setState(() {
      _choisi = article;
      _erreur = null;
      _poids.text = '1';
    });
  }

  /// Ouvre la fiche de l'article pour définir / corriger le PRIX AU KILO,
  /// puis relit le produit (le prix affiché doit être le vrai).
  Future<void> _definirPrix() async {
    final Article? courant = _choisi;
    if (courant == null) return;

    await context.push('/main/articles/${courant.id}/edit', extra: courant);
    await _charger();
    if (!mounted) return;

    Article? relu;
    for (final Article a in _produits) {
      if (a.id == courant.id) {
        relu = a;
        break;
      }
    }
    setState(() => _choisi = relu);
  }

  void _ajuster(double delta) {
    final double actuel = _poidsSaisi ?? 1;
    final double valeur = (actuel + delta).clamp(0.001, 999.999);
    _poids.text = PeseeCalculs.texte(valeur);
  }

  Future<void> _vendre({required bool direct}) async {
    final Article? a = _choisi;
    final double? poids = _poidsSaisi;

    if (a == null) return;
    if (poids == null) {
      setState(() => _erreur = 'Saisissez le poids affiché par la balance.');
      return;
    }
    if (a.prixVente <= 0) {
      setState(() => _erreur =
          'Définissez d\'abord le PRIX AU KILO de « ${a.nom} ».');
      return;
    }

    if (!direct) {
      // Passage par le panier : on crée une ligne d'article pesé.
      PanierService.instance.ajouterArticle(
        ArticleScanne(article: a),
        quantite: poids,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${formatQuantite(poids)} kg de « ${a.nom} » au panier.',
          ),
        ),
      );
      _poids.text = '1';
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final VenteEnregistree vente = await VenteService.instance.venteRapide(
        produitId: a.id,
        quantite: poids,
      );
      if (!mounted) return;
      setState(() => _enCours = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${formatQuantite(poids)} kg • ${formatMontant(vente.total)} — '
            '${vente.numeroVente}',
          ),
        ),
      );
      // Prêt pour le client suivant : le produit reste choisi.
      _poids.text = '1';
    } on VenteServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = e.message;
      });
    } catch (e) {
      debugPrint('PeseeRapidePage._vendre : $e');
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = 'Vente non confirmée : réessayez.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesée rapide'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Scanner un produit',
            onPressed: () async {
              await context.push('/scanner');
              await _charger();
            },
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: ModernLoader(legende: 'Chargement…'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: <Widget>[
                Text(
                  'Saisissez le poids affiché par la balance, puis encaissez. '
                  'Le prix au kilo vient du produit : il n\'est jamais saisi '
                  'au hasard.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                if (_erreur != null) ...<Widget>[
                  _Bandeau(message: _erreur!, erreur: true),
                  const SizedBox(height: 10),
                ],
                if (_choisi == null) ...<Widget>[
                  TextField(
                    controller: _recherche,
                    decoration: const InputDecoration(
                      hintText: 'Rechercher un produit pesé…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_filtres.isEmpty)
                    _Bandeau(
                      message: 'Aucun produit vendu au poids. Ouvrez '
                          '« Articles » et cochez « Vendu au poids (kg) » sur '
                          'le produit, avec son prix au kilo.',
                    )
                  else
                    ..._filtres.map(
                      (Article a) => _CarteProduit(
                        article: a,
                        onTap: () => _choisir(a),
                      ),
                    ),
                ] else
                  _PanneauPesee(
                    article: _choisi!,
                    poidsController: _poids,
                    total: _total,
                    enCours: _enCours,
                    onChanger: () => setState(() => _choisi = null),
                    onMoins: () => _ajuster(-0.1),
                    onPlus: () => _ajuster(0.1),
                    onPlusDemi: () => _ajuster(0.5),
                    onDefinirPrix: _definirPrix,
                    onEncaisser: () => _vendre(direct: true),
                    onPanier: () => _vendre(direct: false),
                  ),
              ],
            ),
    );
  }
}

class _CarteProduit extends StatelessWidget {
  const _CarteProduit({required this.article, required this.onTap});

  final Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool sansPrix = article.prixVente <= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(child: Icon(Icons.scale_rounded)),
        title: Text(article.nom, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          sansPrix
              ? 'Prix au kilo manquant — à définir'
              : '${formatMontant(article.prixVente)} / ${article.uniteMesure} '
                  '• stock ${formatQuantite(article.quantite)}',
          style: sansPrix
              ? TextStyle(
                  color: theme.colorScheme.error, fontWeight: FontWeight.w600)
              : null,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _PanneauPesee extends StatelessWidget {
  const _PanneauPesee({
    required this.article,
    required this.poidsController,
    required this.total,
    required this.enCours,
    required this.onChanger,
    required this.onMoins,
    required this.onPlus,
    required this.onPlusDemi,
    required this.onDefinirPrix,
    required this.onEncaisser,
    required this.onPanier,
  });

  final Article article;
  final TextEditingController poidsController;
  final double total;
  final bool enCours;
  final VoidCallback onChanger;
  final VoidCallback onMoins;
  final VoidCallback onPlus;
  final VoidCallback onPlusDemi;
  final VoidCallback onDefinirPrix;
  final VoidCallback onEncaisser;
  final VoidCallback onPanier;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool sansPrix = article.prixVente <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        article.nom,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: onChanger,
                      child: const Text('Changer'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  sansPrix
                      ? 'Aucun prix au kilo défini.'
                      : 'Prix : ${formatMontant(article.prixVente)} / '
                          '${article.uniteMesure}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: sansPrix
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: sansPrix ? FontWeight.w700 : null,
                  ),
                ),
                if (sansPrix) ...<Widget>[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: onDefinirPrix,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Définir le prix au kilo'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                const Text(
                  'POIDS AFFICHÉ PAR LA BALANCE (kg)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: poidsController,
                  enabled: !enCours && !sansPrix,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                  decoration: const InputDecoration(
                    suffixText: 'kg',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: enCours || sansPrix ? null : onMoins,
                        child: const Text('− 0,1'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: enCours || sansPrix ? null : onPlus,
                        child: const Text('+ 0,1'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: enCours || sansPrix ? null : onPlusDemi,
                        child: const Text('+ 0,5'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        'TOTAL',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        formatMontant(total),
                        style: theme.textTheme.headlineSmall?.copyWith(
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
        const SizedBox(height: 14),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: enCours || sansPrix ? null : onEncaisser,
            icon: enCours
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.point_of_sale_rounded),
            label: Text(
              enCours ? 'Encaissement…' : 'ENCAISSER MAINTENANT',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: enCours || sansPrix ? null : onPanier,
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('Ajouter au panier'),
          ),
        ),
      ],
    );
  }
}

class _Bandeau extends StatelessWidget {
  const _Bandeau({required this.message, this.erreur = false});

  final String message;
  final bool erreur;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fond = erreur
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.tertiaryContainer;
    final Color texte = erreur
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(erreur ? Icons.error_outline : Icons.info_outline,
              size: 18, color: texte),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: texte)),
          ),
        ],
      ),
    );
  }
}
