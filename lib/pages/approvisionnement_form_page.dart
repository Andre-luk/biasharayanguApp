// lib/pages/approvisionnement_form_page.dart
//
// MODULE 9 — ENTRÉE DE STOCK (APPROVISIONNEMENT).
//
// Le magasinier saisit l'entrée dans l'unité qui l'arrange :
//
//   • en UNITÉ DE BASE (bouteille, pièce…) : 20 → +20 unités ;
//   • en CONDITIONNEMENT (farde, carton…) : 10 fardes de 12 → +120 unités.
//
// La conversion est faite ICI, avant l'appel : `public.approvisionnements.
// quantite_ajoutee` stocke toujours des UNITÉS DE BASE, et le trigger serveur
// ajoute la quantité au stock (jamais de décrément direct côté application).
//
// Le prix d'achat est saisi « par unité choisie » puis converti en prix par
// unité de base pour le stockage (`prix_achat_unitaire`).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/stock_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/code_barre_lecteur.dart';

/// Une unité proposée à la saisie (unité de base, ou conditionnement).
class _OptionUnite {
  const _OptionUnite({required this.libelle, required this.facteur});

  final String libelle;

  /// Nombre d'unités de base dans 1 unité saisie (1 pour l'unité de base).
  final double facteur;

  bool get estBase => facteur <= 1;
}

/// Formulaire d'entrée de stock (Module 9).
class ApprovisionnementFormPage extends StatefulWidget {
  const ApprovisionnementFormPage({super.key, this.article});

  /// Article présélectionné (venu de la fiche stock) ; `null` pour choisir
  /// l'article dans la liste.
  final Article? article;

  @override
  State<ApprovisionnementFormPage> createState() =>
      _ApprovisionnementFormPageState();
}

class _ApprovisionnementFormPageState extends State<ApprovisionnementFormPage> {
  final StockService _service = StockService.instance;

  final TextEditingController _quantiteController = TextEditingController();
  final TextEditingController _prixController = TextEditingController();
  final TextEditingController _fournisseurController = TextEditingController();

  List<Article> _articles = const <Article>[];
  Article? _article;
  bool _chargementListe = false;
  String? _erreurListe;

  List<_OptionUnite> _unites = const <_OptionUnite>[];
  int _indexUnite = 0;

  DateTime _date = DateTime.now();
  bool _enregistrement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _quantiteController.addListener(_rafraichir);
    _prixController.addListener(_rafraichir);

    final Article? initial = widget.article;
    if (initial != null) {
      _article = initial;
      _construireUnites(initial);
    } else {
      _chargerArticles();
    }
  }

  @override
  void dispose() {
    _quantiteController.removeListener(_rafraichir);
    _prixController.removeListener(_rafraichir);
    _quantiteController.dispose();
    _prixController.dispose();
    _fournisseurController.dispose();
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
      debugPrint('ApprovisionnementFormPage._chargerArticles: $e');
      if (!mounted) return;
      setState(() {
        _chargementListe = false;
        _erreurListe = 'Impossible de charger la liste des articles.';
      });
    }
  }

  void _construireUnites(Article article) {
    _unites = <_OptionUnite>[
      _OptionUnite(libelle: article.uniteMesure, facteur: 1),
      for (final Conditionnement c in article.conditionnements)
        if (c.quantiteUnitesBase > 1)
          _OptionUnite(libelle: c.libelle, facteur: c.quantiteUnitesBase),
    ];
    _indexUnite = 0;
  }

  /// 🏷️ CORRECTIF 59 — choisit l'article en scannant son code-barres.
  ///
  /// À la réception d'une livraison, on scanne le carton au lieu de chercher
  /// le libellé dans une longue liste.
  Future<void> _scannerArticle() async {
    final String? code = await lireCodeBarre(
      context,
      titre: 'Article à approvisionner',
      aide: 'Visez le code-barres du produit reçu.',
    );
    if (code == null || !mounted) return;

    try {
      final Article? article =
          await ArticleService.instance.trouverParCodeBarre(code);
      if (!mounted) return;

      if (article == null) {
        _messageScan('Aucun article ne porte le code « $code ».\n'
            'Créez-le d\'abord dans la liste des articles.');
        return;
      }

      //  Le menu déroulant n'accepte comme valeur qu'un article présent dans
      //  sa liste : on ajoute celui du scan s'il n'y figure pas encore.
      if (!_articles.any((Article a) => a.id == article.id)) {
        setState(() => _articles = <Article>[..._articles, article]);
      }
      _selectionnerArticle(article);
    } catch (e) {
      debugPrint('ApprovisionnementFormPage._scannerArticle : $e');
      if (mounted) {
        _messageScan('Recherche impossible : vérifiez votre réseau.');
      }
    }
  }

  void _messageScan(String texte) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texte), duration: const Duration(seconds: 3)),
    );
  }

  void _selectionnerArticle(Article? article) {
    setState(() {
      _article = article;
      if (article != null) _construireUnites(article);
    });
  }

  // ---------------------------------------------------------------------------
  // CALCULS DE SAISIE
  // ---------------------------------------------------------------------------

  _OptionUnite? get _unite =>
      (_indexUnite >= 0 && _indexUnite < _unites.length) ? _unites[_indexUnite] : null;

  double? get _quantiteSaisie =>
      double.tryParse(_quantiteController.text.trim().replaceAll(',', '.'));

  double? get _prixSaisi {
    final String texte = _prixController.text.trim().replaceAll(',', '.');
    if (texte.isEmpty) return null;
    return double.tryParse(texte);
  }

  /// Quantité convertie en unités de base (10 fardes de 12 → 120).
  double? get _quantiteUnitesBase {
    final double? quantite = _quantiteSaisie;
    final _OptionUnite? unite = _unite;
    if (quantite == null || quantite <= 0 || unite == null) return null;
    return quantite * unite.facteur;
  }

  /// Prix d'achat converti « par unité de base ».
  double? get _prixAchatUnitaire {
    final double? prix = _prixSaisi;
    final _OptionUnite? unite = _unite;
    if (prix == null || prix < 0 || unite == null) return null;
    return prix / unite.facteur;
  }

  // ---------------------------------------------------------------------------
  // ENREGISTREMENT
  // ---------------------------------------------------------------------------

  Future<void> _enregistrer() async {
    final Article? article = _article;
    final double? quantiteBase = _quantiteUnitesBase;
    final double? prixBase = _prixAchatUnitaire;

    if (article == null) {
      setState(() => _erreur = 'Choisissez un article à approvisionner.');
      return;
    }
    if (quantiteBase == null) {
      setState(() => _erreur = 'Saisissez une quantité supérieure à zéro.');
      return;
    }
    // 💰 MODULE 34 — LE PRIX D'ACHAT EST FACULTATIF.
    //  Un commerçant qui rentre une marchandise reçue en cadeau, un retour
    //  client ou un stock initial ne connaît pas toujours le prix. Vider le
    //  champ enregistre 0 au lieu de bloquer l'entrée de stock.
    final double prixEffectif = prixBase ?? 0;

    setState(() {
      _enregistrement = true;
      _erreur = null;
    });

    try {
      final ResultatApprovisionnement resultat = await _service.approvisionner(
        produitId: article.id,
        quantiteUnitesBase: quantiteBase,
        prixAchatUnitaire: prixEffectif,
        fournisseur: _fournisseurController.text,
        dateApprovisionnement: _date,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Entrée enregistrée : ${formatQuantite(resultat.stockAvant)} → '
            '${formatQuantite(resultat.stockApres)} ${article.uniteMesure}.',
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
      debugPrint('ApprovisionnementFormPage._enregistrer: $e\n$st');
      if (!mounted) return;
      setState(() {
        _enregistrement = false;
        _erreur = 'Une erreur inattendue est survenue.';
      });
    }
  }

  Future<void> _choisirDate() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: "Date d'approvisionnement",
    );
    if (date == null || !mounted) return;
    setState(() => _date = date);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

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
            'Stock actuel : ${formatQuantite(article.quantite)} ${article.uniteMesure}',
          ),
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

    return Column(
      children: <Widget>[
        AppDropdownField<Article>(
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
        ),
        const SizedBox(height: 10),
        // 🏷️ CORRECTIF 59 — le produit reçu est scanné, pas cherché.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _scannerArticle,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scanner le code-barres de l\'article'),
          ),
        ),
      ],
    );
  }

  Widget _apercuConversion() {
    final ThemeData theme = Theme.of(context);
    final Article? article = _article;
    final _OptionUnite? unite = _unite;
    final double? quantite = _quantiteSaisie;
    final double? quantiteBase = _quantiteUnitesBase;

    if (article == null || unite == null) return const SizedBox.shrink();

    final StringBuffer lignes = StringBuffer();

    if (quantite != null && quantite > 0) {
      if (!unite.estBase) {
        lignes.writeln(
          '${formatQuantite(quantite)} × ${unite.libelle} '
          '= ${formatQuantite(quantiteBase ?? 0)} ${article.uniteMesure}',
        );
      }
      final double nouveauStock = article.quantite + (quantiteBase ?? 0);
      lignes.write(
        'Stock après entrée : ${formatQuantite(nouveauStock)} ${article.uniteMesure}',
      );
    } else if (!unite.estBase) {
      lignes.write('1 ${unite.libelle} = ${formatQuantite(unite.facteur)} ${article.uniteMesure}');
    }

    if (lignes.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        lignes.toString(),
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Article? article = _article;
    final _OptionUnite? unite = _unite;
    final double? prixBase = _prixAchatUnitaire;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Entrée de stock',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _carteArticle(),
          const SizedBox(height: 14),

          if (article != null && unite != null) ...<Widget>[
            AppDropdownField<int>(
              label: 'Unité de saisie',
              value: _indexUnite,
              prefixIcon: Icons.straighten_rounded,
              items: List<DropdownMenuItem<int>>.generate(
                _unites.length,
                (int i) => DropdownMenuItem<int>(
                  value: i,
                  child: Text(_unites[i].libelle),
                ),
              ),
              onChanged: (int? valeur) {
                if (valeur != null) setState(() => _indexUnite = valeur);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantiteController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantité (${unite.libelle})',
                prefixIcon: const Icon(Icons.add_box_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            _apercuConversion(),
            const SizedBox(height: 12),
            TextField(
              controller: _prixController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                // 💰 MODULE 34 — facultatif : laissez vide si vous ne
                //  connaissez pas le prix d'achat (cadeau, retour, stock
                //  initial). 0 est alors enregistré.
                labelText: "Prix d'achat (par ${unite.libelle}) — facultatif",
                prefixIcon: const Icon(Icons.payments_outlined),
                helperText: (prixBase != null && !unite.estBase)
                    ? '= ${formatMontant(prixBase)} par ${article.uniteMesure}'
                    : 'Laissez vide si le prix est inconnu',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fournisseurController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Fournisseur (facultatif)',
                prefixIcon: const Icon(Icons.local_shipping_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _choisirDate,
              icon: const Icon(Icons.event_outlined),
              label: Text("Date : ${formatDate(_date)}"),
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
                : const Icon(Icons.save_outlined),
            label: Text(_enregistrement ? 'Enregistrement…' : "Enregistrer l'entrée"),
          ),
        ],
      ),
    );
  }
}
