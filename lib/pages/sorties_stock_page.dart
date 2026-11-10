// lib/pages/sorties_stock_page.dart
//
// 📦 MODULE 9 — SORTIES DE STOCK SPÉCIALES.
//
// Un article ne quitte pas le stock uniquement parce qu'il a été VENDU :
//
//   • le propriétaire consomme son propre article (« j'ai consommé un sucré ») ;
//   • un article est offert / sert d'échantillon (« goffre ») ;
//   • une bouteille est cassée, un produit est périmé, un article est perdu ;
//   • une marchandise retourne au fournisseur ;
//   • un article sert d'ingrédient à une fabrication interne.
//
// Dans tous ces cas : LE STOCK DIMINUE, LA CAISSE NE BOUGE PAS. Cet écran
// enregistre ces sorties, les justifie (motif obligatoire), les valorise et
// produit un RAPPORT IMPRIMABLE.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/sortie_stock.dart';
import 'package:biashara_yangu/services/etablissement_service.dart';
import 'package:biashara_yangu/services/rapport_sorties_pdf_service.dart';
import 'package:biashara_yangu/services/stock_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Écran des sorties de stock non commerciales.
class SortiesStockPage extends StatefulWidget {
  const SortiesStockPage({super.key, this.article});

  /// Article filtré (venu de la fiche stock) ; `null` = tous les articles.
  final Article? article;

  @override
  State<SortiesStockPage> createState() => _SortiesStockPageState();
}

class _SortiesStockPageState extends State<SortiesStockPage> {
  final StockService _service = StockService.instance;

  late DateTime _debut;
  late DateTime _fin;
  String _libellePeriode = 'Ce mois';

  MotifSortieStock? _motifFiltre;
  ResumeSortiesStock? _resume;
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final DateTime maintenant = DateTime.now();
    _debut = DateTime(maintenant.year, maintenant.month, 1);
    _fin = maintenant;
    _charger();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }
    try {
      final ResumeSortiesStock resume = await _service.sortiesStock(
        debut: _debut,
        fin: _fin,
        produitId: widget.article?.id,
        motif: _motifFiltre,
      );
      if (!mounted) return;
      setState(() {
        _resume = resume;
        _chargement = false;
        _erreur = null;
      });
    } on StockServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = e.message;
      });
    } catch (e) {
      debugPrint('SortiesStockPage._charger : $e');
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = 'Impossible de charger les sorties de stock.';
      });
    }
  }

  void _appliquerPeriode(DateTime debut, DateTime fin, String libelle) {
    setState(() {
      _debut = debut;
      _fin = fin;
      _libellePeriode = libelle;
    });
    _charger();
  }

  Future<void> _choisirPeriode() async {
    final DateTimeRange? choix = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _debut, end: _fin),
      helpText: 'Période du rapport',
      saveText: 'Valider',
    );
    if (choix == null) return;
    _appliquerPeriode(choix.start, choix.end, 'Période choisie');
  }

  /// « Aujourd'hui », « 7 derniers jours », « Ce mois », « Période… ».
  Widget _barrePeriodes() {
    final DateTime maintenant = DateTime.now();
    final List<Widget> choix = <Widget>[
      _puce(
        libelle: "Aujourd'hui",
        actif: _libellePeriode == "Aujourd'hui",
        onTap: () => _appliquerPeriode(
          DateTime(maintenant.year, maintenant.month, maintenant.day),
          maintenant,
          "Aujourd'hui",
        ),
      ),
      _puce(
        libelle: '7 derniers jours',
        actif: _libellePeriode == '7 derniers jours',
        onTap: () => _appliquerPeriode(
          maintenant.subtract(const Duration(days: 6)),
          maintenant,
          '7 derniers jours',
        ),
      ),
      _puce(
        libelle: 'Ce mois',
        actif: _libellePeriode == 'Ce mois',
        onTap: () => _appliquerPeriode(
          DateTime(maintenant.year, maintenant.month, 1),
          maintenant,
          'Ce mois',
        ),
      ),
      _puce(
        libelle: 'Période…',
        actif: _libellePeriode == 'Période choisie',
        onTap: _choisirPeriode,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < choix.length; i++) ...<Widget>[
            choix[i],
            if (i != choix.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _puce({
    required String libelle,
    required bool actif,
    required VoidCallback onTap,
  }) {
    final ThemeData theme = Theme.of(context);
    return ChoiceChip(
      label: Text(libelle),
      selected: actif,
      onSelected: (_) => onTap(),
      selectedColor: theme.colorScheme.primary.withValues(alpha: 0.16),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: actif ? FontWeight.bold : FontWeight.normal,
        color: actif ? theme.colorScheme.primary : null,
      ),
    );
  }

  Future<void> _nouvelleSortie() async {
    final bool? enregistre = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) =>
          _FeuilleNouvelleSortie(article: widget.article),
    );
    if (enregistre == true) {
      await _charger(silencieux: true);
    }
  }

  Future<void> _imprimer() async {
    final ResumeSortiesStock? resume = _resume;
    if (resume == null) return;

    if (resume.estVide) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune sortie sur la période : rien à imprimer.'),
        ),
      );
      return;
    }

    try {
      await EtablissementService.instance.charger();
      final DonneesRapportSorties donnees = DonneesRapportSorties(
        etablissement: EtablissementService.instance.courant,
        resume: resume,
        libellePeriode: _periodeLisible(),
      );
      await RapportSortiesPdfService.instance.imprimer(donnees);
    } catch (e) {
      debugPrint('SortiesStockPage._imprimer : $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Impossible de préparer le rapport sur cet appareil."),
        ),
      );
    }
  }

  String _periodeLisible() {
    final String debut = formatDate(_debut);
    final String fin = formatDate(_fin);
    return debut == fin ? debut : 'Du $debut au $fin';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Article? filtre = widget.article;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sorties de stock',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          PermissionGate(
            page: PageAccess.stock,
            action: ActionAccess.voir,
            child: IconButton(
              onPressed: _chargement ? null : _imprimer,
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Rapport imprimable',
            ),
          ),
          IconButton(
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          _barrePeriodes(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    filtre == null
                        ? 'Tous les articles'
                        : 'Article : ${filtre.nom}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: AppDropdownField<String>(
                    label: 'Motif',
                    value: _motifFiltre?.code,
                    hint: 'Tous les motifs',
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Tous les motifs'),
                      ),
                      ...MotifSortieStock.values.map(
                        (MotifSortieStock m) => DropdownMenuItem<String>(
                          value: m.code,
                          child: Text(
                            m.libelle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (String? code) {
                      setState(() {
                        _motifFiltre =
                            code == null ? null : MotifSortieStock.depuisCode(code);
                      });
                      _charger();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _corps()),
        ],
      ),
      floatingActionButton: PermissionGateBouton(
        page: PageAccess.stock,
        action: ActionAccess.modifier,
        builder: (BuildContext context) => FloatingActionButton.extended(
          onPressed: _nouvelleSortie,
          icon: const Icon(Icons.outbox_rounded),
          label: const Text('Sortie de stock'),
        ),
      ),
    );
  }

  Widget _corps() {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    final String? erreur = _erreur;
    if (erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.error_outline, size: 56, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(erreur, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _charger(),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final ResumeSortiesStock resume = _resume ?? const ResumeSortiesStock(
          lignes: <SortieStock>[],
          nb: 0,
          valeur: 0,
          parMotif: <String, TotalMotifSortie>{},
        );

    return RefreshIndicator(
      onRefresh: () => _charger(silencieux: true),
      color: Theme.of(context).colorScheme.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: <Widget>[
          _carteTotaux(resume),
          const SizedBox(height: 12),
          if (resume.estVide)
            _vueVide()
          else ...<Widget>[
            if (resume.parMotif.isNotEmpty) ...<Widget>[
              _carteParMotif(resume),
              const SizedBox(height: 12),
            ],
            ...resume.lignes.map(_tuileSortie),
          ],
        ],
      ),
    );
  }

  Widget _carteTotaux(ResumeSortiesStock resume) {
    final ThemeData theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.primary.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Icon(Icons.outbox_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${resume.nb} sortie(s) — ${_periodeLisible()}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Valeur sortie : ${formatMontant(resume.valeur)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Aucun encaissement : ces articles ne sont pas vendus.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carteParMotif(ResumeSortiesStock resume) {
    final ThemeData theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Détail par motif',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            ...resume.motifsTries.map(
              (MapEntry<String, TotalMotifSortie> e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Icon(e.value.icone, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.value.libelle,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      '${e.value.nb} · ${formatMontant(e.value.valeur)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tuileSortie(SortieStock sortie) {
    final ThemeData theme = Theme.of(context);
    final String? note = sortie.note;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(sortie.iconeMotif, size: 18, color: theme.colorScheme.primary),
        ),
        title: Text(
          sortie.produit,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          <String>[
            '− ${formatQuantite(sortie.quantite)} ${sortie.unite}',
            sortie.libelleMotif,
            if (note != null && note.trim().isNotEmpty) note.trim(),
            formatDateHeure(sortie.date),
          ].join(' · '),
          style: theme.textTheme.labelSmall,
        ),
        trailing: Text(
          formatMontant(sortie.valeurTotale),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _vueVide() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
      child: Column(
        children: <Widget>[
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Aucune sortie de stock sur cette période.\n'
            'Utilisez « Sortie de stock » pour une consommation, un article '
            'offert, une casse ou une perte.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FEUILLE — NOUVELLE SORTIE DE STOCK
// =============================================================================

class _FeuilleNouvelleSortie extends StatefulWidget {
  const _FeuilleNouvelleSortie({this.article});

  final Article? article;

  @override
  State<_FeuilleNouvelleSortie> createState() => _FeuilleNouvelleSortieState();
}

class _FeuilleNouvelleSortieState extends State<_FeuilleNouvelleSortie> {
  final StockService _service = StockService.instance;
  final TextEditingController _quantiteCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  List<Article> _articles = const <Article>[];
  Article? _article;
  MotifSortieStock _motif = MotifSortieStock.consommationProprietaire;

  bool _chargement = false;
  bool _enregistrement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _quantiteCtrl.addListener(_rafraichir);
    if (_article == null) {
      _chargerArticles();
    }
  }

  @override
  void dispose() {
    _quantiteCtrl.removeListener(_rafraichir);
    _quantiteCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  Future<void> _chargerArticles() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final List<Article> articles = await _service.getStock();
      if (!mounted) return;
      setState(() {
        _articles = articles;
        _chargement = false;
      });
    } catch (e) {
      debugPrint('_FeuilleNouvelleSortie._chargerArticles : $e');
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = 'Impossible de charger la liste des articles.';
      });
    }
  }

  double? get _quantite =>
      double.tryParse(_quantiteCtrl.text.trim().replaceAll(',', '.'));

  double? get _stockApres {
    final Article? article = _article;
    final double? quantite = _quantite;
    if (article == null || quantite == null) return null;
    return article.quantite - quantite;
  }

  Future<void> _enregistrer() async {
    final Article? article = _article;
    final double? quantite = _quantite;

    if (article == null) {
      setState(() => _erreur = 'Choisissez l\'article qui sort du stock.');
      return;
    }
    if (quantite == null || quantite <= 0) {
      setState(() => _erreur = 'Saisissez la quantité sortie (supérieure à zéro).');
      return;
    }
    if (quantite > article.quantite + 0.000001) {
      setState(() => _erreur =
          'Stock insuffisant : il ne reste que ${formatQuantite(article.quantite)} ${article.uniteMesure}.');
      return;
    }
    if (_motif == MotifSortieStock.autre && _noteCtrl.text.trim().length < 3) {
      setState(() => _erreur = 'Précisez le motif (3 caractères minimum).');
      return;
    }

    setState(() {
      _enregistrement = true;
      _erreur = null;
    });

    try {
      final ResultatSortieStock resultat = await _service.enregistrerSortie(
        produitId: article.id,
        quantite: quantite,
        motif: _motif,
        note: _noteCtrl.text,
      );

      if (!mounted) return;
      // Le messenger est pris AVANT la fermeture de la feuille : après le
      // `pop`, ce contexte n'existe plus.
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      final Color couleur = Theme.of(context).colorScheme.primary;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Sortie enregistrée : ${formatQuantite(resultat.quantite)} '
            '${resultat.unite} de « ${resultat.nom} » — stock '
            '${formatQuantite(resultat.stockApres)}. Caisse inchangée.',
          ),
          backgroundColor: couleur,
          duration: const Duration(seconds: 4),
        ),
      );
    } on StockServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _enregistrement = false;
        _erreur = e.message;
      });
    } catch (e, st) {
      debugPrint('_FeuilleNouvelleSortie._enregistrer : $e\n$st');
      if (!mounted) return;
      setState(() {
        _enregistrement = false;
        _erreur = 'Une erreur inattendue est survenue.';
      });
    }
  }

  Widget _choixArticle() {
    if (widget.article != null) {
      final Article article = widget.article!;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.inventory_2_rounded),
        title: Text(
          article.nom,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Stock actuel : ${formatQuantite(article.quantite)} ${article.uniteMesure}',
        ),
      );
    }

    if (_chargement) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return AppDropdownField<Article>(
      label: 'Article qui sort du stock',
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
      onChanged: (Article? a) => setState(() => _article = a),
    );
  }

  Widget _apercu() {
    final ThemeData theme = Theme.of(context);
    final Article? article = _article;
    final double? apres = _stockApres;
    if (article == null || apres == null) return const SizedBox.shrink();

    final bool insuffisant = apres < -0.000001;
    final Color couleur =
        insuffisant ? Colors.red.shade700 : Colors.green.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            insuffisant
                ? 'Stock insuffisant : la sortie dépasse le stock disponible.'
                : 'Stock après sortie : ${formatQuantite(apres)} ${article.uniteMesure}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: couleur,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Aucun argent n'entrera en caisse : une sortie n'est pas une vente.",
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Article? article = _article;
    final double? quantite = _quantite;
    final double? valeurEstimee =
        (article == null || quantite == null) ? null : article.prixAchat * quantite;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Sortie de stock',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Consommation, article offert, perte, casse, retour fournisseur…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            _choixArticle(),
            if (article != null) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                controller: _quantiteCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantité sortie (${article.uniteMesure})',
                  prefixIcon: const Icon(Icons.remove_circle_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              AppDropdownField<MotifSortieStock>(
                label: 'Motif (obligatoire)',
                value: _motif,
                prefixIcon: Icons.report_problem_outlined,
                items: MotifSortieStock.values
                    .map((MotifSortieStock m) => DropdownMenuItem<MotifSortieStock>(
                          value: m,
                          child: Row(
                            children: <Widget>[
                              Icon(m.icone, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  m.libelle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(growable: false),
                onChanged: (MotifSortieStock? m) {
                  if (m != null) setState(() => _motif = m);
                },
              ),
              const SizedBox(height: 6),
              Text(
                _motif.explication,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: _motif == MotifSortieStock.autre
                      ? 'Précision (obligatoire)'
                      : 'Précision (facultative)',
                  hintText: 'Ex. : sucré pris par le patron, 2 bouteilles cassées…',
                  prefixIcon: const Icon(Icons.edit_note_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              _apercu(),
              if (valeurEstimee != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Valeur estimée de la sortie : ${formatMontant(valeurEstimee)}',
                    style: Theme.of(context).textTheme.labelSmall,
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _enregistrement || article == null ? null : _enregistrer,
                icon: _enregistrement
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _enregistrement ? 'Enregistrement…' : 'Enregistrer la sortie',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
