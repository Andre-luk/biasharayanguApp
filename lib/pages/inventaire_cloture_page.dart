// lib/pages/inventaire_cloture_page.dart
//
// MODULE 9 — INVENTAIRE QUOTIDIEN (ÉCRAN DE CLÔTURE).
//
//   • la liste des articles affiche le stock THÉORIQUE (serveur) ;
//   • le magasinier saisit les quantités PHYSIQUES comptées ;
//   • les écarts sont calculés en direct (physique − théorique) ;
//   • à la clôture, le serveur enregistre chaque comptage dans
//     `public.inventaires_quotidiens` et — si l'option est active — corrige
//     les écarts par des AJUSTEMENTS tracés « Inventaire quotidien du … ».
//
// Un article non saisi n'est PAS envoyé : l'inventaire partiel est permis,
// c'est le serveur qui fige les quantités théoriques sous verrou.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/inventaire_ligne.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/stock_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/code_barre_lecteur.dart';

/// Écran de clôture de l'inventaire quotidien (Module 9).
class InventaireCloturePage extends StatefulWidget {
  const InventaireCloturePage({super.key});

  @override
  State<InventaireCloturePage> createState() => _InventaireCloturePageState();
}

class _InventaireCloturePageState extends State<InventaireCloturePage> {
  final StockService _service = StockService.instance;
  final TextEditingController _rechercheController = TextEditingController();

  // -------------------------------------------------------------------------
  // 🏷️ CORRECTIF 59 — COMPTER EN SCANNANT
  // -------------------------------------------------------------------------

  /// Isole une ligne de comptage en scannant le code-barres du produit.
  ///
  /// L'inventaire se fait article par article : scanner filtre la liste sur
  /// le bon produit (le compteur reste à saisir) et rappelle le stock
  /// théorique, ce qui évite de chercher le libellé dans une longue liste.
  Future<void> _scannerPourCompter() async {
    final String? code = await lireCodeBarre(
      context,
      titre: 'Inventaire — scanner un article',
      aide: 'Visez le code-barres du produit compté.',
    );
    if (code == null || !mounted) return;

    try {
      final Article? article =
          await ArticleService.instance.trouverParCodeBarre(code);
      if (!mounted) return;

      if (article == null) {
        _messageScan('Aucun article ne porte le code « $code ».');
        return;
      }

      setState(() => _rechercheController.text = article.nom);
      _messageScan(
        '${article.nom} — stock théorique : '
        '${formatQuantite(article.quantite)} ${article.uniteMesure}.',
      );
    } catch (e) {
      debugPrint('InventaireCloturePage._scannerPourCompter : $e');
      if (mounted) {
        _messageScan('Recherche impossible : vérifiez votre réseau.');
      }
    }
  }

  void _messageScan(String texte) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texte), duration: const Duration(seconds: 4)),
    );
  }

  List<LigneInventaire> _lignes = <LigneInventaire>[];
  final Map<int, TextEditingController> _controleurs =
      <int, TextEditingController>{};

  bool _chargement = true;
  String? _erreur;
  bool _ajuster = true;
  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    _rechercheController.addListener(_rafraichir);
    _charger();
  }

  @override
  void dispose() {
    _rechercheController.removeListener(_rafraichir);
    _rechercheController.dispose();
    for (final TextEditingController controleur in _controleurs.values) {
      controleur.dispose();
    }
    super.dispose();
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  Future<void> _charger() async {
    if (!mounted) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final List<Article> articles = await _service.getStock();
      if (!mounted) return;

      for (final TextEditingController controleur in _controleurs.values) {
        controleur.dispose();
      }
      _controleurs.clear();
      _lignes = <LigneInventaire>[];

      for (final Article article in articles) {
        final LigneInventaire ligne = LigneInventaire(
          produitId: article.id,
          nom: article.nom,
          unite: article.uniteMesure,
          quantiteTheorique: article.quantite,
        );
        _lignes.add(ligne);
        _controleurs[article.id] = TextEditingController()
          ..addListener(() => _surSaisie(ligne));
      }

      setState(() {
        _chargement = false;
        _erreur = null;
      });
    } on StockServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } on ArticleServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e, st) {
      debugPrint('InventaireCloturePage._charger: $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreur = 'Une erreur inattendue est survenue lors du chargement.';
        _chargement = false;
      });
    }
  }

  void _surSaisie(LigneInventaire ligne) {
    final TextEditingController? controleur = _controleurs[ligne.produitId];
    if (controleur == null) return;

    final String texte = controleur.text.trim().replaceAll(',', '.');
    ligne.quantitePhysique = texte.isEmpty ? null : double.tryParse(texte);
    if (mounted) setState(() {});
  }

  List<LigneInventaire> get _lignesAffichees {
    final String recherche = _rechercheController.text.trim().toLowerCase();
    if (recherche.isEmpty) return _lignes;
    return _lignes
        .where((LigneInventaire ligne) => ligne.nom.toLowerCase().contains(recherche))
        .toList(growable: false);
  }

  ResumeInventaire get _resume => ResumeInventaire.depuisLignes(_lignes);

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  void _toutConforme() {
    for (final LigneInventaire ligne in _lignesAffichees) {
      _controleurs[ligne.produitId]?.text = formatQuantite(ligne.quantiteTheorique);
    }
    // Les listeners mettent à jour `quantitePhysique` et l'affichage.
    setState(() {});
  }

  void _effacerSaisies() {
    for (final TextEditingController controleur in _controleurs.values) {
      controleur.clear();
    }
    setState(() {});
  }

  Future<void> _cloturer() async {
    final ResumeInventaire resume = _resume;

    if (resume.nbComptes == 0) {
      _afficherMessage(
        'Aucun article compté : saisissez au moins une quantité physique.',
        estErreur: true,
      );
      return;
    }

    // Contrôle des saisies : toute valeur non vide doit être un nombre >= 0.
    for (final LigneInventaire ligne in _lignes) {
      if (!ligne.compte) continue;
      if (ligne.quantitePhysique == null || ligne.quantitePhysique! < 0) {
        _afficherMessage(
          'Quantité invalide pour « ${ligne.nom} ».',
          estErreur: true,
        );
        return;
      }
    }

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Clôturer l'inventaire ?",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${resume.nbComptes} article(s) compté(s), '
          '${resume.nbEcarts} écart(s) '
          '(${formatQuantiteSignee(resume.ecartNet)} au total).\n\n'
          '${_ajuster ? 'Les écarts seront corrigés par des ajustements tracés.' : 'Les écarts seront enregistrés SANS correction du stock.'}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );

    if (!mounted || confirme != true) return;

    setState(() => _enregistrement = true);

    try {
      final ResultatInventaire resultat = await _service.cloturerInventaire(
        lignes: _lignes,
        ajuster: _ajuster,
      );

      if (!mounted) return;
      setState(() => _enregistrement = false);
      await _afficherRecapitulatif(resultat);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StockServiceException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _afficherMessage(e.message, estErreur: true);
    } catch (e, st) {
      debugPrint('InventaireCloturePage._cloturer: $e\n$st');
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _afficherMessage('Une erreur inattendue est survenue.', estErreur: true);
    }
  }

  Future<void> _afficherRecapitulatif(ResultatInventaire resultat) async {
    final List<LigneResultatInventaire> ecarts = resultat.lignes
        .where((LigneResultatInventaire l) => l.ecart.abs() > 0.000001)
        .toList(growable: false);

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: <Widget>[
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Inventaire clôturé',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${resultat.nbLignes} article(s) enregistré(s) · '
                '${resultat.nbEcarts} écart(s) · '
                'net ${formatQuantiteSignee(resultat.ecartNet)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                resultat.ajustementsCrees
                    ? 'Les écarts ont été corrigés par des ajustements tracés.'
                    : 'Écarts enregistrés sans correction du stock.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (ecarts.isNotEmpty) ...<Widget>[
                const Divider(height: 20),
                ...ecarts.take(12).map((LigneResultatInventaire l) {
                  final bool positif = l.ecart > 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• ${l.nom} : ${formatQuantite(l.theorique)} → '
                      '${formatQuantite(l.physique)} '
                      '(${formatQuantiteSignee(l.ecart)})',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: positif
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  );
                }),
                if (ecarts.length > 12)
                  Text(
                    '… et ${ecarts.length - 12} autre(s) écart(s).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Terminer'),
          ),
        ],
      ),
    );
  }

  void _afficherMessage(String message, {bool estErreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: estErreur
            ? Colors.red.shade700
            : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _carteIntro() {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Clôture du ${formatDate(DateTime.now())}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Comptez les quantités physiques puis clôturez : chaque comptage est '
            'enregistré et les écarts corrigés par des ajustements tracés.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _ligneArticle(LigneInventaire ligne) {
    final ThemeData theme = Theme.of(context);
    final TextEditingController? controleur = _controleurs[ligne.produitId];
    final double? ecart = ligne.ecart;

    final Color couleurEcart = ecart == null
        ? Colors.grey.shade600
        : ecart.abs() <= 0.000001
            ? Colors.green.shade700
            : (ecart > 0 ? Colors.green.shade700 : Colors.red.shade700);

    final String libelleEcart = ecart == null
        ? 'non compté'
        : ecart.abs() <= 0.000001
            ? 'conforme'
            : formatQuantiteSignee(ecart);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    ligne.nom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Théorique : ${formatQuantite(ligne.quantiteTheorique)} ${ligne.unite}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    libelleEcart,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: couleurEcart,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: TextField(
                controller: controleur,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '0',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barreCloture() {
    final ThemeData theme = Theme.of(context);
    final ResumeInventaire resume = _resume;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      resume.nbComptes == 0
                          ? 'Aucun article compté pour le moment.'
                          : '${resume.nbComptes} compté(s) · '
                              '${resume.nbEcarts} écart(s) · '
                              'net ${formatQuantiteSignee(resume.ecartNet)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${resume.nbComptes}/${_lignes.length}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _ajuster,
                onChanged: (bool valeur) => setState(() => _ajuster = valeur),
                title: const Text(
                  'Corriger les écarts (ajustements)',
                  style: TextStyle(fontSize: 13.5),
                ),
                subtitle: Text(
                  _ajuster
                      ? 'Le stock sera aligné sur les quantités comptées.'
                      : 'Les écarts seront enregistrés sans toucher au stock.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _effacerSaisies,
                      icon: const Icon(Icons.backspace_outlined, size: 18),
                      label: const Text('Effacer'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _toutConforme,
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: const Text('Conforme'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _enregistrement ? null : _cloturer,
                      icon: _enregistrement
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Clôturer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Inventaire quotidien',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          // 🏷️ CORRECTIF 59 — compter l'article en le scannant.
          IconButton(
            onPressed: _scannerPourCompter,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Scanner un article à compter',
          ),
          IconButton(
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                        const SizedBox(height: 12),
                        Text(_erreur!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _charger,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Column(
                        children: <Widget>[
                          _carteIntro(),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _rechercheController,
                            decoration: InputDecoration(
                              hintText: 'Rechercher un article…',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _lignes.isEmpty
                          ? Center(
                              child: Text(
                                "Aucun article à compter : le catalogue est vide.",
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              itemCount: _lignesAffichees.length,
                              itemBuilder: (BuildContext context, int index) =>
                                  _ligneArticle(_lignesAffichees[index]),
                            ),
                    ),
                  ],
                ),
      bottomNavigationBar: _chargement || _erreur != null ? null : _barreCloture(),
    );
  }
}
