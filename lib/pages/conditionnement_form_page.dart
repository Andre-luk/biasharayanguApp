// lib/pages/conditionnement_form_page.dart
//
// MODULE 5 — ÉCRAN « AJOUTER / MODIFIER UN CONDITIONNEMENT »
//
//   • libellé (« Farde de 12 », « Carton de 24 ») ;
//   • quantité en unités de base (12, 24…) ;
//   • prix de vente de l'emballage (libre : jamais recalculé depuis la
//     quantité — un emballage peut être vendu moins cher que le prix de
//     base × quantité) ;
//   • code-barre texte (optionnel) ;
//   • QR code généré automatiquement par la base à la création ;
//   • prévisualisation : « 1 Farde de 12 = 12 bouteilles pour 12 000 CDF ».

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
// 🪙 MODULE 18 — devise de travail (symbole affiché dans les champs prix).
import 'package:biashara_yangu/services/devise_service.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

class ConditionnementFormPage extends StatefulWidget {
  const ConditionnementFormPage({
    super.key,
    required this.articleId,
    this.conditionnement,
  });

  /// Article auquel appartient (ou appartiendra) le conditionnement.
  final int articleId;

  /// Conditionnement à modifier ; `null` pour une création.
  final Conditionnement? conditionnement;

  @override
  State<ConditionnementFormPage> createState() =>
      _ConditionnementFormPageState();
}

class _ConditionnementFormPageState extends State<ConditionnementFormPage> {
  final ArticleService _service = ArticleService.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _libelleController = TextEditingController();
  final TextEditingController _quantiteController = TextEditingController();
  final TextEditingController _prixController = TextEditingController();
  final TextEditingController _codeBarreController = TextEditingController();

  Article? _article;
  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreurChargement;

  bool get _estModification => widget.conditionnement != null;

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  @override
  void dispose() {
    _libelleController.dispose();
    _quantiteController.dispose();
    _prixController.dispose();
    _codeBarreController.dispose();
    super.dispose();
  }

  Future<void> _initialiser() async {
    Article? article;
    try {
      article = await _service.getArticleById(widget.articleId);
    } on ArticleServiceException catch (e) {
      if (mounted) {
        setState(() {
          _erreurChargement = e.message;
          _chargement = false;
        });
      }
      return;
    }

    if (!mounted) return;

    if (article == null) {
      setState(() {
        _erreurChargement = "Cet article n'existe plus dans la base de données.";
        _chargement = false;
      });
      return;
    }

    final Conditionnement? conditionnement = widget.conditionnement;
    if (conditionnement != null) {
      _libelleController.text = conditionnement.libelle;
      _quantiteController.text = _champNombre(conditionnement.quantiteUnitesBase);
      _prixController.text = _champNombre(conditionnement.prixVente);
      _codeBarreController.text = conditionnement.codeBarreTexte ?? '';
    }

    setState(() {
      _article = article;
      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // SAISIE
  // ---------------------------------------------------------------------------

  String _champNombre(double valeur) {
    if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
    return valeur.toString();
  }

  double _lireNombre(String texte, {double fallback = 0}) {
    final String propre = texte.trim().replaceAll(',', '.');
    if (propre.isEmpty) return fallback;
    return double.tryParse(propre) ?? fallback;
  }

  String? _validerObligatoire(String? valeur, String message) {
    if (valeur == null || valeur.trim().isEmpty) return message;
    return null;
  }

  String? _validerQuantite(String? valeur) {
    final double nombre = _lireNombre(valeur ?? '');
    if (nombre <= 0) {
      return 'La quantité doit être supérieure à zéro.';
    }
    return null;
  }

  String? _validerPrix(String? valeur) {
    final String propre = (valeur ?? '').trim().replaceAll(',', '.');
    if (propre.isEmpty) return 'Le prix de vente est obligatoire.';
    final double? nombre = double.tryParse(propre);
    if (nombre == null || nombre < 0) {
      return 'Le prix de vente est invalide.';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // ENREGISTREMENT
  // ---------------------------------------------------------------------------

  Future<void> _enregistrer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _enregistrement = true);
    FocusScope.of(context).unfocus();

    try {
      final String libelle = _libelleController.text.trim();
      final double quantite = _lireNombre(_quantiteController.text);
      final double prix = _lireNombre(_prixController.text);
      final String codeBarre = _codeBarreController.text.trim();

      if (_estModification) {
        await _service.majConditionnement(
          id: widget.conditionnement!.id,
          libelle: libelle,
          quantiteUnitesBase: quantite,
          prixVente: prix,
          codeBarreTexte: codeBarre,
        );
        if (!mounted) return;
        _afficherMessage('Conditionnement enregistré.');
        context.pop(true);
      } else {
        await _service.ajouterConditionnement(
          produitId: widget.articleId,
          libelle: libelle,
          quantiteUnitesBase: quantite,
          prixVente: prix,
          codeBarreTexte: codeBarre,
        );
        if (!mounted) return;
        _afficherMessage('Conditionnement créé (QR code généré).');
        context.pop(true);
      }
    } on ArticleServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  Future<void> _supprimer() async {
    final Conditionnement conditionnement = widget.conditionnement!;

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Supprimer ce conditionnement ?'),
        content: Text(
          '« ${conditionnement.libelle} » sera retiré du catalogue. '
          "L'article de base n'est pas modifié.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (!mounted || confirme != true) return;

    try {
      await _service.supprimerConditionnement(conditionnement.id);
      if (!mounted) return;
      _afficherMessage('Conditionnement supprimé.');
      context.pop(true);
    } on ArticleServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    }
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

  Widget _carteApercu(String uniteBase) {
    final String libelle = _libelleController.text.trim();
    final double quantite = _lireNombre(_quantiteController.text);
    final double prix = _lireNombre(_prixController.text);

    final String apercu = Conditionnement.apercuTexte(
      libelle: libelle,
      quantiteUnitesBase: quantite,
      prixVente: prix,
      uniteBase: uniteBase,
    );

    String? parUnite;
    if (quantite > 0 && prix > 0) {
      parUnite = 'soit ${formatMontant(prix / quantite)} par $uniteBase';
    }

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.visibility_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    apercu,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  if (parUnite != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      parUnite,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carteQr() {
    final Conditionnement conditionnement = widget.conditionnement!;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'QR code du conditionnement',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            QrImageView(
              data: conditionnement.qrCodeId,
              version: QrVersions.auto,
              size: 150,
            ),
            const SizedBox(height: 8),
            Text(
              'Identifiant : ${conditionnement.qrCodeId}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (conditionnement.createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Créé le ${formatDateHeure(conditionnement.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String titre =
        _estModification ? 'Modifier le conditionnement' : 'Nouveau conditionnement';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          titre,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreurChargement != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreurChargement!, textAlign: TextAlign.center),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_article != null) ...[
                        Text(
                          "Article : ${_article!.nom} (unité de base : ${_article!.uniteMesure})",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ------------------------------------------- libellé
                      TextFormField(
                        controller: _libelleController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Libellé *',
                          hintText: 'Ex. Farde de 12',
                          prefixIcon: const Icon(Icons.sell_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (String? v) => _validerObligatoire(
                            v, 'Le libellé est obligatoire (ex. Farde de 12).'),
                      ),
                      const SizedBox(height: 16),

                      // -------------------------------------- quantité de base
                      TextFormField(
                        controller: _quantiteController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          labelText: "Quantité en unités de base *",
                          hintText: _article == null
                              ? 'Ex. 12'
                              : 'Ex. 12 ${Conditionnement.pluriel(_article!.uniteMesure, 2)}',
                          prefixIcon: const Icon(Icons.numbers),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: _validerQuantite,
                      ),
                      const SizedBox(height: 8),

                      // Règle métier du Module 5 : le prix reste libre.
                      Text(
                        'Modifier la quantité ne change PAS le prix : les deux '
                        'valeurs sont indépendantes (un emballage peut être vendu '
                        'moins cher que le prix de base × quantité).',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),

                      // ---------------------------------------------- prix
                      TextFormField(
                        controller: _prixController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Prix de vente *',
                          suffixText: DeviseService.instance.symbole,
                          prefixIcon: const Icon(Icons.payments_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: _validerPrix,
                      ),
                      const SizedBox(height: 16),

                      // ------------------------------------------ code-barre
                      TextFormField(
                        controller: _codeBarreController,
                        decoration: InputDecoration(
                          labelText: 'Code-barre texte (optionnel)',
                          hintText: 'Code du fabricant',
                          prefixIcon: const Icon(Icons.qr_code),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ------------------------------------- prévisualisation
                      _carteApercu(_article?.uniteMesure ?? 'unité'),
                      const SizedBox(height: 12),

                      if (_estModification) ...[
                        _carteQr(),
                        const SizedBox(height: 12),
                      ] else ...[
                        Card(
                          elevation: 0,
                          color: Colors.grey.shade100,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: const Padding(
                            padding: EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(Icons.qr_code_2_rounded, color: Colors.grey),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Le QR code sera généré automatiquement '
                                    "à l'enregistrement.",
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ------------------------------------- bouton enregistrer
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _enregistrement ? null : _enregistrer,
                          icon: _enregistrement
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_estModification
                              ? 'Enregistrer le conditionnement'
                              : 'Créer le conditionnement'),
                        ),
                      ),

                      if (_estModification) ...[
                        const SizedBox(height: 12),
                        PermissionGate(
                          page: PageAccess.articles,
                          action: ActionAccess.supprimer,
                          child: OutlinedButton.icon(
                            onPressed: _supprimer,
                            icon: Icon(Icons.delete_outline,
                                color: Colors.red.shade700),
                            label: Text(
                              'Supprimer ce conditionnement',
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
