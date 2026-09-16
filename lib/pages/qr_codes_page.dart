// lib/pages/qr_codes_page.dart
//
// MODULE 6 — ÉCRAN « GESTION QR CODES »
//
//   • liste des articles et de leurs conditionnements avec cases à cocher ;
//   • options : taille (mm), texte sous le QR, format de téléchargement ;
//   • boutons « Générer QR Codes », « Télécharger tout », « Imprimer tout » ;
//   • génération en masse par lots de 10 avec barre de progression.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/etiquette_qr.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/qr_code_service.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

class QrCodesPage extends StatefulWidget {
  const QrCodesPage({super.key});

  @override
  State<QrCodesPage> createState() => _QrCodesPageState();
}

class _QrCodesPageState extends State<QrCodesPage> {
  final ArticleService _articles = ArticleService.instance;
  final QrCodeService _qr = QrCodeService.instance;

  List<Article> _listeArticles = const <Article>[];
  bool _chargement = true;
  String? _erreur;

  /// Codes (`PROD:…` / `COND:…`) des étiquettes cochées.
  final Set<String> _selection = <String>{};

  // Options (étape 5 du cahier des charges).
  double _tailleMm = QrCodeService.tailleParDefautMm;
  QrFormatFichier _format = QrFormatFichier.png;
  bool _avecTexte = true;

  RealtimeChannel? _canalTempsReel;
  Timer? _antiRebondTempsReel;

  @override
  void initState() {
    super.initState();
    _demarrerEcouteTempsReel();
    _charger();
  }

  @override
  void dispose() {
    _antiRebondTempsReel?.cancel();
    final RealtimeChannel? canal = _canalTempsReel;
    if (canal != null) {
      unawaited(_articles.arreterEcoute(canal));
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // DONNÉES
  // ---------------------------------------------------------------------------

  void _demarrerEcouteTempsReel() {
    try {
      _canalTempsReel = _articles.ecouterChangements(_planifierRechargement);
    } catch (e) {
      debugPrint('QrCodesPage : temps réel indisponible ($e)');
    }
  }

  void _planifierRechargement() {
    _antiRebondTempsReel?.cancel();
    _antiRebondTempsReel = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _charger(silencieux: true);
    });
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    List<Article> articles = const <Article>[];
    String? messageErreur;

    try {
      articles = await _articles.getArticles();
    } on ArticleServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('QrCodesPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des articles.';
    }

    if (!mounted) return;

    if (messageErreur != null) {
      if (silencieux) {
        _afficherMessage(messageErreur, estErreur: true);
        return;
      }
      setState(() {
        _erreur = messageErreur;
        _chargement = false;
      });
      return;
    }

    setState(() {
      _listeArticles = articles;
      _erreur = null;
      _chargement = false;

      // La sélection ne doit garder que des étiquettes encore existantes.
      final Set<String> disponibles = _toutesLesEtiquettes
          .map((EtiquetteQr etiquette) => etiquette.code)
          .toSet();
      _selection.removeWhere((String code) => !disponibles.contains(code));
    });
  }

  List<EtiquetteQr> get _toutesLesEtiquettes =>
      QrCodeService.etiquettesPourArticles(_listeArticles);

  List<EtiquetteQr> get _etiquettesSelectionnees => _toutesLesEtiquettes
      .where((EtiquetteQr etiquette) => _selection.contains(etiquette.code))
      .toList(growable: false);

  void _basculer(EtiquetteQr etiquette) {
    setState(() {
      if (!_selection.remove(etiquette.code)) {
        _selection.add(etiquette.code);
      }
    });
  }

  void _toutSelectionner() {
    setState(() {
      _selection
        ..clear()
        ..addAll(_toutesLesEtiquettes.map((EtiquetteQr e) => e.code));
    });
  }

  void _toutDeselectionner() {
    setState(() => _selection.clear());
  }

  // ---------------------------------------------------------------------------
  // ACTIONS (Générer / Télécharger / Imprimer)
  // ---------------------------------------------------------------------------

  /// Exécute [tache] derrière une boîte de dialogue de progression.
  Future<T?> _avecProgression<T>(
    String titre,
    Future<T> Function(void Function(double fraction) onProgression) tache,
  ) async {
    final ValueNotifier<double> progression = ValueNotifier<double>(0);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            ValueListenableBuilder<double>(
              valueListenable: progression,
              builder: (_, double valeur, __) => LinearProgressIndicator(
                value: valeur <= 0 ? null : valeur.clamp(0, 1),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      return await tache((double fraction) {
        progression.value = fraction;
      });
    } on QrCodeServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
      return null;
    } catch (e, st) {
      debugPrint('QrCodesPage._avecProgression: $e\n$st');
      _afficherMessage('Une erreur inattendue est survenue.', estErreur: true);
      return null;
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progression.dispose();
    }
  }

  Future<void> _generer() async {
    final List<EtiquetteQr> etiquettes = _etiquettesSelectionnees;
    if (etiquettes.isEmpty) {
      _afficherMessage('Cochez au moins un article ou un conditionnement.');
      return;
    }

    final bool? ok = await _avecProgression<bool>(
      'Génération de ${etiquettes.length} QR codes (lots de 10)…',
      (void Function(double) onProgression) async {
        await _qr.preparerEtiquettes(
          etiquettes,
          tailleMm: _tailleMm,
          onProgression: (int faits, int total) =>
              onProgression(total == 0 ? 0 : faits / total),
        );
        return true;
      },
    );

    if (!mounted || ok != true) return;
    _afficherMessage(
      '${etiquettes.length} QR codes générés (${_tailleMm.toStringAsFixed(0)} mm, '
      '${QrCodeService.dpi} DPI) — prêts à télécharger ou imprimer.',
    );
  }

  Future<void> _telecharger() async {
    final List<EtiquetteQr> etiquettes = _etiquettesSelectionnees;
    if (etiquettes.isEmpty) {
      _afficherMessage('Cochez au moins un article ou un conditionnement.');
      return;
    }

    List<String>? chemins = await _avecProgression<List<String>>(
      'Téléchargement de ${etiquettes.length} QR codes '
      '(${_format.libelle})…',
      (void Function(double) onProgression) => _qr.telechargerQrCodes(
        etiquettes,
        format: _format,
        tailleMm: _tailleMm,
        onProgression: (int faits, int total) =>
            onProgression(total == 0 ? 0 : faits / total),
      ),
    );

    if (!mounted || chemins == null || chemins.isEmpty) return;

    final String dossier =
        chemins.first.substring(0, chemins.first.lastIndexOf('/'));
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Téléchargement terminé'),
        content: SelectableText(
          '${chemins.length} fichier(s) enregistrés dans :\n\n$dossier',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _imprimer() async {
    final List<EtiquetteQr> etiquettes = _etiquettesSelectionnees;
    if (etiquettes.isEmpty) {
      _afficherMessage('Cochez au moins un article ou un conditionnement.');
      return;
    }

    final bool? ok = await _avecProgression<bool>(
      'Préparation de la planche PDF '
      '(${etiquettes.length} étiquettes)…',
      (void Function(double) onProgression) async {
        onProgression(0.3);
        await _qr.imprimerEtiquettes(
          etiquettes,
          avecTexte: _avecTexte,
          nomTravail: 'Etiquettes_QR',
        );
        onProgression(1);
        return true;
      },
    );

    if (!mounted || ok != true) return;
    _afficherMessage('Planche PDF envoyée à l\'impression.');
  }

  void _ouvrirApercu(EtiquetteQr etiquette) {
    context.push<bool>('/main/qr-codes/apercu', extra: etiquette);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

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

  Widget _ligneEtiquette({
    required EtiquetteQr etiquette,
    required String titre,
    String? sousTitre,
    bool dense = false,
  }) {
    return CheckboxListTile(
      value: _selection.contains(etiquette.code),
      onChanged: (_) => _basculer(etiquette),
      controlAffinity: ListTileControlAffinity.leading,
      dense: dense,
      title: Text(
        titre,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: dense ? FontWeight.normal : FontWeight.w600,
          fontSize: dense ? 13.5 : null,
        ),
      ),
      subtitle: Text(
        sousTitre ?? etiquette.code,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5),
      ),
      secondary: IconButton(
        icon: const Icon(Icons.qr_code_2_rounded),
        tooltip: 'Aperçu / télécharger / imprimer',
        onPressed: () => _ouvrirApercu(etiquette),
      ),
    );
  }

  Widget _carteArticle(Article article) {
    final List<EtiquetteQr> etiquettes =
        QrCodeService.etiquettesPourArticles(<Article>[article]);
    final EtiquetteQr etiquetteArticle = etiquettes.first;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _ligneEtiquette(
            etiquette: etiquetteArticle,
            titre: article.nom,
            sousTitre: article.conditionnements.isEmpty
                ? 'Article · ${etiquetteArticle.code}'
                : 'Article · ${etiquetteArticle.code} · '
                    '${article.nombreConditionnements} conditionnement(s)',
          ),
          ...etiquettes.skip(1).map(
                (EtiquetteQr etiquette) => Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _ligneEtiquette(
                    etiquette: etiquette,
                    titre: etiquette.sousTitre ?? 'Conditionnement',
                    sousTitre: etiquette.code,
                    dense: true,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _carteOptions() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 18,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Options',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AppDropdownField<double>(
                    label: 'Taille du QR',
                    value: _tailleMm,
                    items: QrCodeService.taillesMm
                        .map((double mm) => DropdownMenuItem<double>(
                              value: mm,
                              child: Text('${mm.toStringAsFixed(0)} mm'),
                            ))
                        .toList(),
                    onChanged: (double? valeur) => setState(
                        () => _tailleMm = valeur ?? _tailleMm),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDropdownField<QrFormatFichier>(
                    label: 'Format fichier',
                    value: _format,
                    items: QrFormatFichier.values
                        .map((QrFormatFichier format) =>
                            DropdownMenuItem<QrFormatFichier>(
                              value: format,
                              child: Text(format.libelle),
                            ))
                        .toList(),
                    onChanged: (QrFormatFichier? valeur) => setState(
                        () => _format = valeur ?? _format),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _avecTexte,
              onChanged: (bool valeur) => setState(() => _avecTexte = valeur),
              title: const Text(
                'Texte sous le QR (nom, article, code)',
                style: TextStyle(fontSize: 13.5),
              ),
            ),
            Text(
              'Les QR codes sont encodés en ${QrCodeService.dpi} DPI. '
              'Ils ne contiennent JAMAIS le prix : celui-ci est relu dans la '
              'base à chaque scan.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _barreActions() {
    final int nombre = _selection.length;
    final ThemeData theme = Theme.of(context);

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nombre == 0
                    ? 'Aucune étiquette sélectionnée'
                    : '$nombre étiquette(s) sélectionnée(s)',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              PermissionGateBouton(
                page: PageAccess.qrCodes,
                action: ActionAccess.creer,
                builder: (BuildContext context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: nombre == 0 ? null : _generer,
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: const Text('Générer QR Codes'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: nombre == 0 ? null : _telecharger,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Télécharger tout'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: nombre == 0 ? null : _imprimer,
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Imprimer tout'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
          'Gestion QR Codes',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'Sélection',
            onSelected: (String valeur) {
              if (valeur == 'tout') {
                _toutSelectionner();
              } else {
                _toutDeselectionner();
              }
            },
            itemBuilder: (BuildContext ctx) => const [
              PopupMenuItem<String>(
                value: 'tout',
                child: Text('Tout sélectionner'),
              ),
              PopupMenuItem<String>(
                value: 'rien',
                child: Text('Tout désélectionner'),
              ),
            ],
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
                      children: [
                        Icon(Icons.error_outline,
                            size: 56, color: Colors.red.shade400),
                        const SizedBox(height: 12),
                        Text(_erreur!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => _charger(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _charger(silencieux: true),
                  color: Theme.of(context).colorScheme.primary,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      _carteOptions(),
                      const SizedBox(height: 12),
                      if (_listeArticles.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Column(
                            children: [
                              const Icon(Icons.qr_code_2_rounded,
                                  size: 72, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                'Aucun article à équiper.\n'
                                "Créez d'abord des articles dans l'écran Articles.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 15, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )
                      else
                        ..._listeArticles.map(_carteArticle),
                    ],
                  ),
                ),
      bottomNavigationBar: _barreActions(),
    );
  }
}
