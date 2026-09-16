// lib/pages/qr_apercu_page.dart
//
// MODULE 6 — ÉCRAN « APERÇU QR CODE »
//
//   • affiche le QR code d'un article ou d'un conditionnement ;
//   • rappelle les informations de l'article ET le prix ACTUEL de la base
//     (le prix n'est jamais encodé dans le QR) ;
//   • boutons : Télécharger PNG, Télécharger SVG, Partager, Imprimer.

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/etiquette_qr.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/qr_code_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

class QrApercuPage extends StatefulWidget {
  const QrApercuPage({super.key, required this.etiquette});

  /// Étiquette à afficher (article `PROD:…` ou conditionnement `COND:…`).
  final EtiquetteQr etiquette;

  @override
  State<QrApercuPage> createState() => _QrApercuPageState();
}

class _QrApercuPageState extends State<QrApercuPage> {
  final QrCodeService _qr = QrCodeService.instance;

  Article? _article;
  bool _chargementArticle = true;

  double _tailleMm = QrCodeService.tailleParDefautMm;
  bool _avecTexte = true;

  @override
  void initState() {
    super.initState();
    _chargerArticle();
  }

  Future<void> _chargerArticle() async {
    final int? articleId = widget.etiquette.articleId;
    if (articleId == null) {
      setState(() => _chargementArticle = false);
      return;
    }

    try {
      final Article? article = await ArticleService.instance.getArticleById(articleId);
      if (!mounted) return;
      setState(() {
        _article = article;
        _chargementArticle = false;
      });
    } on ArticleServiceException catch (e) {
      debugPrint('QrApercuPage (article ignoré): ${e.message}');
      if (mounted) setState(() => _chargementArticle = false);
    }
  }

  /// Conditionnement correspondant au QR affiché (si l'article est chargé).
  Conditionnement? get _conditionnement {
    if (widget.etiquette.type != TypeQrCode.conditionnement) return null;
    for (final Conditionnement conditionnement
        in _article?.conditionnements ?? const <Conditionnement>[]) {
      if (conditionnement.qrCodeId == widget.etiquette.identifiant) {
        return conditionnement;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
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

  Future<void> _telecharger(QrFormatFichier format) async {
    try {
      final String chemin = await _qr.telechargerQrCode(
        widget.etiquette,
        format: format,
        tailleMm: _tailleMm,
      );
      if (!mounted) return;
      _afficherMessage('Fichier enregistré : $chemin');
    } on QrCodeServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    }
  }

  Future<void> _partager() async {
    try {
      await _qr.partagerEtiquettes(
        <EtiquetteQr>[widget.etiquette],
        avecTexte: _avecTexte,
        nomFichier: '${widget.etiquette.nomFichierBase}.pdf',
      );
    } on QrCodeServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    }
  }

  Future<void> _imprimer() async {
    try {
      await _qr.imprimerEtiquettes(
        <EtiquetteQr>[widget.etiquette],
        avecTexte: _avecTexte,
        nomTravail: widget.etiquette.nomFichierBase,
      );
      if (!mounted) return;
      _afficherMessage('Étiquette envoyée à l\'impression.');
    } on QrCodeServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _carteContenu() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_2_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Contenu encodé (${widget.etiquette.type.libelle})',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              widget.etiquette.code,
              style: const TextStyle(
                  fontFamily: 'monospace', fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Le prix n\'est JAMAIS encodé : il est relu dans la base de '
              'données à chaque scan. Un changement de prix n\'invalide donc '
              'pas cette étiquette.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneInfo(String libelle, String valeur) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(libelle, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 12),
          Text(
            valeur,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _carteInformations() {
    if (_chargementArticle) {
      return const Card(
        elevation: 2,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final Article? article = _article;
    final Conditionnement? conditionnement = _conditionnement;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Informations',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            _ligneInfo('Objet', widget.etiquette.type.libelle),
            _ligneInfo(
              'Article',
              article?.nom ?? widget.etiquette.titre,
            ),
            if (conditionnement != null)
              _ligneInfo(
                'Conditionnement',
                '${conditionnement.libelle} — '
                    '${conditionnement.quantiteUnitesBase.toStringAsFixed(0)} '
                    '${Conditionnement.pluriel(article?.uniteMesure ?? 'unité', conditionnement.quantiteUnitesBase)}',
              ),
            if (article != null) ...[
              const Divider(height: 18),
              Text(
                'Prix ACTUEL (relu dans la base de données)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              _ligneInfo(
                conditionnement != null
                    ? 'Prix du conditionnement'
                    : 'Prix de vente (unité)',
                formatMontant(
                  conditionnement?.prixVente ?? article.prixVente,
                ),
              ),
              if (conditionnement != null)
                _ligneInfo(
                  'Prix de vente (unité)',
                  formatMontant(article.prixVente),
                ),
              _ligneInfo(
                'Stock (unités de base)',
                '${article.quantite.toStringAsFixed(0)} ${article.uniteMesure}',
              ),
            ],
            if (conditionnement?.createdAt != null) ...[
              const Divider(height: 18),
              _ligneInfo(
                'Conditionnement créé le',
                formatDateHeure(conditionnement!.createdAt),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _carteApercuQr() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: QrImageView(
                data: widget.etiquette.code,
                version: QrVersions.auto,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                size: 220,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.etiquette.libelleComplet,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carteOptions() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          children: [
            AppDropdownField<double>(
              label: 'Taille (téléchargement / impression)',
              value: _tailleMm,
              items: QrCodeService.taillesMm
                  .map((double mm) => DropdownMenuItem<double>(
                        value: mm,
                        child: Text('${mm.toStringAsFixed(0)} mm'),
                      ))
                  .toList(),
              onChanged: (double? valeur) =>
                  setState(() => _tailleMm = valeur ?? _tailleMm),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _avecTexte,
              onChanged: (bool valeur) => setState(() => _avecTexte = valeur),
              title: const Text(
                'Texte sous le QR (impression)',
                style: TextStyle(fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final EtiquetteQr etiquette = widget.etiquette;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Aperçu QR Code',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _carteApercuQr(),
          const SizedBox(height: 12),
          _carteContenu(),
          const SizedBox(height: 12),
          _carteInformations(),
          const SizedBox(height: 12),
          _carteOptions(),
          const SizedBox(height: 16),
          PermissionGateBouton(
            page: PageAccess.qrCodes,
            action: ActionAccess.creer,
            builder: (BuildContext context) => Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _telecharger(QrFormatFichier.png),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('PNG'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _telecharger(QrFormatFichier.svg),
                        icon: const Icon(Icons.polyline_outlined),
                        label: const Text('SVG'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _partager,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Partager'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _imprimer,
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Imprimer'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              etiquette.code,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
