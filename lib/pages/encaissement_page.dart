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

import 'package:biashara_yangu/models/ligne_panier.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';
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

  String _mode = 'especes';
  bool _enregistrement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _montantRecuControleur.addListener(_onMontantModifie);
  }

  @override
  void dispose() {
    _montantRecuControleur.dispose();
    _transactionControleur.dispose();
    super.dispose();
  }

  void _onMontantModifie() {
    if (mounted) setState(() => _erreur = null);
  }

  // ---------------------------------------------------------------------------
  // CALCULS
  // ---------------------------------------------------------------------------

  double get _total => _panier.total();

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
      );

      if (!mounted) return;
      // La vente est confirmée : le panier est déjà vidé par le service.
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
                      child: Text(
                        '${_nombreTexte(ligne.quantite)} × ${ligne.nom}'
                        '${ligne.vendu.estConditionnement ? ' (${ligne.vendu.libelleConditionnement})' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMontant(ligne.sousTotal),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text('TOTAL',
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
