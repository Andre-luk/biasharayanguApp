// lib/pages/encaissement_page.dart
//
// MODULE 8 — L'ÉCRAN D'ENCAISSEMENT.
//
// Récapitulatif du panier + choix du mode de paiement :
//   • Espèces      → champ « Montant reçu » et calcul automatique du rendu ;
//   • Mobile Money → numéro de transaction (optionnel) ;
//   • Carte / Virement / Autre.
//
// « VALIDER LA VENTE » appelle la transaction serveur `rpc_vente_valider`
// (Module 8 SQL) : tout ou rien. Le panier n'est vidé que lorsque le serveur
// a confirmé — et l'écran de confirmation affiche alors le numéro de vente.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/ligne_panier.dart';
import 'package:biashara_yangu/models/parametres_vente.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';
import 'package:biashara_yangu/services/ventes_commerciales_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Écran « Encaissement » — mode de paiement puis validation de la vente.
class EncaissementPage extends StatefulWidget {
  const EncaissementPage({super.key});

  @override
  State<EncaissementPage> createState() => _EncaissementPageState();
}

class _EncaissementPageState extends State<EncaissementPage> {
  final PanierService _panier = PanierService.instance;
  final TextEditingController _montantRecuControleur = TextEditingController();
  final TextEditingController _transactionControleur = TextEditingController();
  final TextEditingController _remiseControleur = TextEditingController();

  String _mode = 'especes';
  bool _enregistrement = false;
  String? _erreur;

  // 🛒 MODULE 25 — flexibilité commerciale.
  ParametresVente _parametres = ParametresVente.aucun;
  TypeReduction _typeRemise = TypeReduction.montant;
  bool _chargementReglages = true;

  /// Clé d'idempotence : la même vente rejouée ne crée jamais deux ventes.
  String _referenceLocale =
      'app-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _montantRecuControleur.addListener(_onMontantModifie);
    _remiseControleur.addListener(_onRemiseModifiee);
    _chargerReglages();
  }

  @override
  void dispose() {
    _montantRecuControleur.dispose();
    _transactionControleur.dispose();
    _remiseControleur.dispose();
    super.dispose();
  }

  void _onMontantModifie() {
    if (mounted) setState(() => _erreur = null);
  }

  // ---------------------------------------------------------------------------
  // RÉGLAGES DE LA BOUTIQUE
  // ---------------------------------------------------------------------------

  Future<void> _chargerReglages() async {
    final ParametresVente p =
        await VentesCommercialesService.instance.charger(forcer: true);
    if (!mounted) return;
    setState(() {
      _parametres = p;
      _chargementReglages = false;
    });
  }

  /// Applique la réduction saisie au panier, dans la limite autorisée.
  void _onRemiseModifiee() {
    final double? valeur = _remiseSaisie;
    if (valeur == null || valeur <= 0) {
      _panier.effacerRemise();
      if (mounted) setState(() => _erreur = null);
      return;
    }

    final String? refus = ReglesVenteFlexible.verifierRemise(
      base: _panier.total(),
      valeur: valeur,
      type: _typeRemise,
      parametres: _parametres,
    );
    if (refus != null) {
      _panier.effacerRemise();
      if (mounted) setState(() => _erreur = refus);
      return;
    }

    _panier.definirRemise(valeur, type: _typeRemise);
    if (mounted) setState(() => _erreur = null);
  }

  // ---------------------------------------------------------------------------
  // CALCULS
  // ---------------------------------------------------------------------------

  /// Total AVANT réduction du panier (après négociations de lignes).
  double get _brut => _panier.total();

  /// Montant réellement demandé au client.
  double get _total => _panier.totalAPayer();

  /// Montant accordé par négociation sur les lignes.
  double get _negociation => _panier.montantNegociation();

  /// Réduction accordée sur l'ensemble du panier.
  double get _reduction => _panier.montantRemise();

  /// Montant saisi dans la case réduction.
  double? get _remiseSaisie {
    final String texte =
        _remiseControleur.text.trim().replaceAll(',', '.');
    if (texte.isEmpty) return null;
    return double.tryParse(texte);
  }

  /// Montant saisi (null tant que le champ est vide).
  double? get _montantRecu {
    final String texte = _montantRecuControleur.text.trim().replaceAll(',', '.');
    if (texte.isEmpty) return null;
    return double.tryParse(texte);
  }

  /// Rendu calculé en direct (espèces).
  double get _rendu => VenteService.calculerRendu(_total, _montantRecu);

  bool get _montantInsuffisant =>
      _mode == 'especes' && !VenteService.montantSuffisant(_total, _montantRecu);

  bool get _peutValider =>
      !_enregistrement && !_panier.estVide && !_montantInsuffisant;

  // ---------------------------------------------------------------------------
  // VALIDATION
  // ---------------------------------------------------------------------------

  Future<void> _valider() async {
    FocusScope.of(context).unfocus();

    // 🛡️ Contrôle local du seuil de validation du responsable : le serveur le
    // revérifie de toute façon, mais autant l'expliquer avant l'envoi.
    if (_parametres.validationSeuil != null &&
        !_parametres.estProprietaire &&
        ReglesVenteFlexible.validationRequise(
          montantAccorde: _negociation + _reduction,
          parametres: _parametres,
        )) {
      setState(() => _erreur =
          'Remise totale de ${formatMontant(_negociation + _reduction)} : '
          'au-delà de ${formatMontant(_parametres.validationSeuil!)} le '
          'responsable doit valider la vente.');
      return;
    }

    setState(() {
      _enregistrement = true;
      _erreur = null;
    });

    try {
      final VenteEnregistree vente = await VenteService.instance.validerVente(
        modePaiement: _mode,
        montantRecu: _mode == 'especes' ? _montantRecu : null,
        numeroTransaction:
            _mode == 'mobile_money' ? _transactionControleur.text : null,
        // 🛒 MODULE 25 — réduction globale et cadeaux.
        remise: _panier.remiseValeur,
        remiseType: _panier.remiseType.code,
        cadeaux: _panier.cadeaux,
        referenceLocale: _referenceLocale,
      );

      if (!mounted) return;
      // La vente est confirmée : le panier est déjà vidé par le service.
      _referenceLocale = 'app-${DateTime.now().microsecondsSinceEpoch}';
      _remiseControleur.clear();
      context.pushReplacement('/confirmation-vente', extra: vente);
    } on VenteServiceException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Encaissement')),
      body: _panier.estVide && !_enregistrement
          ? _buildPanierVide()
          : Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      _buildRecap(),
                      // 🛒 MODULE 25 — négociation, réduction, cadeaux.
                      if (!_chargementReglages && _parametres.aQuelqueChose) ...[
                        const SizedBox(height: 16),
                        _buildFlexibilite(),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        'Mode de paiement',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _buildModes(),
                      if (_mode == 'especes') ...<Widget>[
                        const SizedBox(height: 18),
                        _buildChampMontantRecu(),
                        const SizedBox(height: 12),
                        _buildRendu(),
                      ],
                      if (_mode == 'mobile_money') ...<Widget>[
                        const SizedBox(height: 18),
                        TextField(
                          controller: _transactionControleur,
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            labelText: 'Numéro de transaction (optionnel)',
                            prefixIcon:
                                const Icon(Icons.confirmation_number_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                          ),
                        ),
                      ],
                      if (_erreur != null) ...<Widget>[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.error_outline_rounded,
                                  color: Colors.red.shade700, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _erreur!,
                                  style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _buildPied(),
              ],
            ),
    );
  }

  Widget _buildPanierVide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.remove_shopping_cart_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 14),
            const Text(
              'Le panier est vide : rien à encaisser.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => context.pop(),
              child: const Text('Retour au panier'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecap() {
    final List<LignePanier> lignes = _panier.lignes;
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.receipt_long_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Récapitulatif',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${_panier.nombreArticles()} article(s)',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            ...lignes.map(
              (LignePanier ligne) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${_nombreTexte(ligne.quantite)} × ${ligne.nom}'
                            '${ligne.vendu.estConditionnement ? ' (${ligne.vendu.libelleConditionnement})' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                          if (ligne.estNegociee)
                            Text(
                              'Prix négocié ${formatMontant(ligne.prixUnitaireEffectif)} '
                              '(catalogue ${formatMontant(ligne.prixUnitaire)})',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_parametres.peutNegocier && !_panier.estVide)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Négocier le prix',
                        icon: const Icon(Icons.price_change_outlined, size: 19),
                        onPressed: () => _negocierLigne(ligne),
                      ),
                    Text(
                      formatMontant(ligne.total),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 🎁 Les cadeaux, clairement séparés des articles vendus.
            if (_panier.cadeaux.isNotEmpty) ...<Widget>[
              const Divider(height: 16),
              Row(
                children: <Widget>[
                  Icon(Icons.card_giftcard_rounded,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Cadeaux offerts',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ..._panier.cadeaux.map(
                (CadeauPanier cadeau) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${_nombreTexte(cadeau.quantite)} × ${cadeau.nom}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      Text(
                        'OFFERT',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Retirer le cadeau',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _panier.retirerCadeau(cadeau.cle);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const Divider(height: 14),
            if (_negociation > 0) ...<Widget>[
              _ligneTotal(theme, 'Prix catalogue',
                  formatMontant(_panier.totalCatalogue()),
                  muted: true),
              _ligneTotal(theme, 'Négociation accordée',
                  '- ${formatMontant(_negociation)}',
                  alerte: true),
            ],
            if (_reduction > 0) ...<Widget>[
              _ligneTotal(theme, 'Sous-total avant réduction',
                  formatMontant(_brut),
                  muted: true),
              _ligneTotal(theme, 'Réduction sur le panier',
                  '- ${formatMontant(_reduction)}',
                  alerte: true),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text('TOTAL À PAYER',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  formatMontant(_total),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Une ligne « libellé / montant » du récapitulatif.
  Widget _ligneTotal(
    ThemeData theme,
    String libelle,
    String montant, {
    bool muted = false,
    bool alerte = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            libelle,
            style: TextStyle(
              fontSize: 12.5,
              color: muted
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
          Text(
            montant,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: alerte ? Colors.orange.shade800 : null,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🛒 MODULE 25 — NÉGOCIATION, RÉDUCTION, CADEAUX
  // ---------------------------------------------------------------------------

  Widget _buildFlexibilite() {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.tune_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Flexibilité commerciale',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 18),

            // 🔻 Réduction globale
            if (_parametres.peutReduire) ...<Widget>[
              SegmentedButton<TypeReduction>(
                segments: const <ButtonSegment<TypeReduction>>[
                  ButtonSegment<TypeReduction>(
                    value: TypeReduction.montant,
                    label: Text('Montant'),
                    icon: Icon(Icons.payments_outlined, size: 16),
                  ),
                  ButtonSegment<TypeReduction>(
                    value: TypeReduction.pourcentage,
                    label: Text('%'),
                    icon: Icon(Icons.percent_rounded, size: 16),
                  ),
                ],
                selected: <TypeReduction>{_typeRemise},
                onSelectionChanged: (Set<TypeReduction> choix) {
                  setState(() => _typeRemise = choix.first);
                  _onRemiseModifiee();
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _remiseControleur,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _typeRemise == TypeReduction.pourcentage
                      ? 'Réduction sur le panier (%)'
                      : 'Réduction sur le panier (CDF)',
                  prefixIcon: const Icon(Icons.local_offer_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  helperText: _plafondRemiseTexte(),
                ),
              ),
              const SizedBox(height: 6),
            ],

            // 🎁 Cadeaux
            if (_parametres.peutOffrir)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _choisirCadeau,
                  icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                  label: const Text('Offrir un produit'),
                ),
              ),

            if (!_parametres.peutReduire && !_parametres.peutOffrir)
              Text(
                'La négociation se fait sur chaque ligne (icône à droite).',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Rappel du plafond autorisé par le propriétaire.
  String? _plafondRemiseTexte() {
    if (_parametres.estProprietaire) return null;
    final double plafond = ReglesVenteFlexible.remisePlafond(
      base: _brut,
      parametres: _parametres,
    );
    if (plafond <= 0) return null;
    return 'Maximum autorisé : ${formatMontant(plafond)}'
        '${_parametres.reductionMaxPct > 0 ? ' (${_parametres.reductionMaxPct.toStringAsFixed(0)} %)' : ''}';
  }

  /// Dialogue de négociation d'une ligne.
  Future<void> _negocierLigne(LignePanier ligne) async {
    final TextEditingController controleur = TextEditingController(
      text: ligne.prixUnitaireEffectif.toStringAsFixed(0),
    );

    final double? prix = await showDialog<double>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Négocier — ${ligne.nom}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Prix catalogue : ${formatMontant(ligne.prixUnitaire)}'),
              const SizedBox(height: 12),
              TextField(
                controller: controleur,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Prix accepté (par unité)',
                  helperText: _parametres.estProprietaire
                      ? null
                      : 'Minimum : '
                          '${formatMontant(ReglesVenteFlexible.prixPlancher(prixCatalogue: ligne.prixUnitaire, parametres: _parametres))}',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final double? valeur = double.tryParse(
                    controleur.text.trim().replaceAll(',', '.'));
                Navigator.of(context).pop(valeur);
              },
              child: const Text('Appliquer'),
            ),
          ],
        );
      },
    );

    controleur.dispose();
    if (prix == null || !mounted) return;

    final String? refus = ReglesVenteFlexible.verifierPrixNegocie(
      prixCatalogue: ligne.prixUnitaire,
      prixNegocie: prix,
      parametres: _parametres,
    );
    if (refus != null) {
      setState(() => _erreur = refus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(refus),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _panier.definirPrixNegocie(ligne.cle, prix);
    // Le plafond de réduction dépend du nouveau total : on réapplique.
    _onRemiseModifiee();
    setState(() {});
  }

  /// Dialogue de choix d'un cadeau (produit + quantité).
  Future<void> _choisirCadeau() async {
    List<Article> articles;
    try {
      articles = await ArticleService.instance.getArticles();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Produits indisponibles : $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;

    final List<Article> disponibles = articles
        .where((Article a) => a.quantite > 0)
        .toList(growable: false);

    if (disponibles.isEmpty) {
      setState(() => _erreur = 'Aucun produit en stock : impossible d\'offrir '
          'un cadeau pour le moment.');
      return;
    }

    final CadeauPanier? cadeau = await showDialog<CadeauPanier>(
      context: context,
      builder: (BuildContext context) =>
          _DialogueCadeau(articles: disponibles),
    );

    if (cadeau == null || !mounted) return;
    _panier.ajouterCadeau(cadeau);
    setState(() => _erreur = null);
  }

  Widget _buildModes() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: VenteService.modesPaiement.entries.map(
        (MapEntry<String, String> entree) {
          final bool selectionne = _mode == entree.key;
          return ChoiceChip(
            label: Text(entree.value),
            selected: selectionne,
            onSelected: (_) => setState(() {
              _mode = entree.key;
              _erreur = null;
            }),
          );
        },
      ).toList(),
    );
  }

  Widget _buildChampMontantRecu() {
    return TextField(
      controller: _montantRecuControleur,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Montant reçu (CDF)',
        prefixIcon: const Icon(Icons.payments_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        errorText: _montantInsuffisant
            ? 'Montant insuffisant : ${formatMontant(_total)} attendu.'
            : null,
      ),
    );
  }

  Widget _buildRendu() {
    final double? recu = _montantRecu;
    final ThemeData theme = Theme.of(context);
    final bool insuffisant = _montantInsuffisant;

    final Color fond = insuffisant
        ? Colors.red.withValues(alpha: 0.08)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.55);
    final Color teinte = insuffisant
        ? Colors.red.shade700
        : theme.colorScheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.local_atm_rounded, color: teinte, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              recu == null
                  ? 'Rendu : saisissez le montant remis par le client.'
                  : (insuffisant
                      ? 'Il manque ${formatMontant(_total - recu)}.'
                      : 'Rendu à remettre'),
              style: TextStyle(color: teinte, fontWeight: FontWeight.w600),
            ),
          ),
          if (recu != null && !insuffisant)
            Text(
              formatMontant(_rendu),
              style: TextStyle(
                color: teinte,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPied() {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _peutValider ? _valider : null,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _enregistrement
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_rounded),
            label: Text(
              _enregistrement ? 'Enregistrement…' : 'VALIDER LA VENTE',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// « 12 » pour une quantité entière, « 1,5 » sinon.
String _nombreTexte(double valeur) {
  if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
  return valeur
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}

/// 🎁 Choix d'un produit offert : article, conditionnement éventuel, quantité.
class _DialogueCadeau extends StatefulWidget {
  const _DialogueCadeau({required this.articles});

  final List<Article> articles;

  @override
  State<_DialogueCadeau> createState() => _DialogueCadeauState();
}

class _DialogueCadeauState extends State<_DialogueCadeau> {
  int? _articleId;
  String? _conditionnementId;
  double _quantite = 1;
  String? _erreur;

  Article? get _article {
    if (_articleId == null) return null;
    for (final Article a in widget.articles) {
      if (a.id == _articleId) return a;
    }
    return null;
  }

  /// Prix et unités de base de ce qui est offert.
  ({double prix, double unitesBase, String? libelle}) get _choix {
    final Article? article = _article;
    if (article == null) {
      return (prix: 0, unitesBase: 1, libelle: null);
    }
    if (_conditionnementId != null) {
      for (final Conditionnement c in article.conditionnements) {
        if (c.id == _conditionnementId) {
          return (
            prix: c.prixVente,
            unitesBase: c.quantiteUnitesBase,
            libelle: c.libelle,
          );
        }
      }
    }
    return (prix: article.prixVente, unitesBase: 1, libelle: null);
  }

  @override
  Widget build(BuildContext context) {
    final Article? article = _article;

    return AlertDialog(
      title: const Text('Offrir un produit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DropdownButtonFormField<int>(
              initialValue: _articleId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Produit',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: widget.articles
                  .map((Article a) => DropdownMenuItem<int>(
                        value: a.id,
                        child: Text(
                          '${a.nom} (stock ${_nombreTexte(a.quantite)})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(growable: false),
              onChanged: (int? valeur) => setState(() {
                _articleId = valeur;
                _conditionnementId = null;
                _erreur = null;
              }),
            ),
            if (article != null && article.conditionnements.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _conditionnementId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Conditionnement',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Unité de base'),
                  ),
                  ...article.conditionnements.map(
                    (Conditionnement c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(
                        '${c.libelle} (${_nombreTexte(c.quantiteUnitesBase)} unités)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (String? valeur) => setState(() {
                  _conditionnementId = valeur;
                  _erreur = null;
                }),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              initialValue: '1',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantité offerte',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (String texte) {
                final double? valeur =
                    double.tryParse(texte.trim().replaceAll(',', '.'));
                setState(() => _quantite = valeur ?? 0);
              },
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 10),
              Text(
                _erreur!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Le cadeau sort du stock et n\'est pas facturé au client.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final Article? choisi = article;
            if (choisi == null) {
              setState(() => _erreur = 'Choisissez le produit à offrir.');
              return;
            }
            if (_quantite <= 0) {
              setState(() => _erreur = 'Indiquez une quantité supérieure à 0.');
              return;
            }

            final ({double prix, double unitesBase, String? libelle}) choix =
                _choix;
            final double baseNecessaire = choix.unitesBase * _quantite;
            if (baseNecessaire > choisi.quantite + 0.0001) {
              setState(() => _erreur =
                  'Stock insuffisant : ${_nombreTexte(choisi.quantite)} '
                  'disponible(s).');
              return;
            }

            Navigator.of(context).pop(
              CadeauPanier(
                produitId: choisi.id,
                nom: choix.libelle == null
                    ? choisi.nom
                    : '${choisi.nom} — ${choix.libelle}',
                prixCatalogue: choix.prix,
                quantite: _quantite,
                quantiteBase: baseNecessaire,
                conditionnementId: _conditionnementId,
                unite: choix.libelle ?? choisi.uniteMesure,
                stockDisponible: choisi.quantite,
              ),
            );
          },
          child: const Text('Offrir'),
        ),
      ],
    );
  }
}
