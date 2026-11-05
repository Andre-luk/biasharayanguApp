// lib/pages/vente_confirmation_page.dart
//
// MODULE 8 — ÉCRAN DE CONFIRMATION APRÈS ENCAISSEMENT.
//
// Affiché après la validation de la vente (le panier est déjà vidé) :
//   • numéro de vente unique (VTE-YYYYMMDD-XXXX) ;
//   • total, mode de paiement, montant reçu / rendu ;
//   • liste des articles vendus ;
//   • impression du reçu (ticket 58 mm) ;
//   • démarrage d'une nouvelle vente (retour au panier, vide).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/invoice_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

/// Écran « Vente enregistrée » — reçu et démarrage d'une nouvelle vente.
class VenteConfirmationPage extends StatefulWidget {
  const VenteConfirmationPage({super.key, required this.vente});

  final VenteEnregistree vente;

  @override
  State<VenteConfirmationPage> createState() => _VenteConfirmationPageState();
}

class _VenteConfirmationPageState extends State<VenteConfirmationPage> {
  String _nomBoutique = 'Biashara Yangu';

  /// 🚚 MODULE 23 — stock restant APRÈS la vente, relu dans la base.
  /// Clé = produit, valeur = quantité restante (`null` = inconnu).
  final Map<int, double> _stockRestant = <int, double>{};
  final Set<int> _stockIllimite = <int>{};

  @override
  void initState() {
    super.initState();
    _chargerNomBoutique();
    _chargerStockRestant();
  }

  /// 🔎 TRADABILITÉ (exigence du module 23) : après chaque vente, le vendeur
  /// voit le nombre d'unités RESTANTES de chaque produit vendu.
  Future<void> _chargerStockRestant() async {
    for (final LigneVenteEnregistree ligne in widget.vente.lignes) {
      try {
        final Article? article =
            await ArticleService.instance.getArticleById(ligne.produitId);
        if (!mounted || article == null) continue;
        setState(() {
          _stockRestant[ligne.produitId] = article.quantite;
          if (article.stockIllimite) _stockIllimite.add(ligne.produitId);
        });
      } catch (e) {
        debugPrint('VenteConfirmationPage stock restant (ignoré) : $e');
      }
    }
  }

  /// Nom affiché sur le ticket : celui du patron de la boutique.
  Future<void> _chargerNomBoutique() async {
    try {
      final String? userId = await SessionManager.getUserId();
      if (userId == null || userId.isEmpty) return;

      final String owner =
          await DBHelper.instance.resolveEffectiveOwnerId(userId) ?? userId;
      final utilisateur = await DBHelper.instance.getUtilisateurById(owner);
      if (!mounted || utilisateur == null || utilisateur.nom.isEmpty) return;
      setState(() => _nomBoutique = utilisateur.nom);
    } catch (e) {
      debugPrint('VenteConfirmationPage : nom de boutique ignoré ($e)');
    }
  }

  Future<void> _imprimer() async {
    final AppLocalizations T = AppLocalizations.of(context)!;
    final VenteEnregistree vente = widget.vente;

    try {
      final InvoiceService facture = InvoiceService(
        T: T,
        userName: _nomBoutique,
        paymentMode: VenteService.libelleMode(vente.modePaiement),
        totalAmount: vente.total,
        items: vente.lignes
            .map(
              (LigneVenteEnregistree ligne) => InvoiceItem(
                name: ligne.conditionnement == null
                    ? ligne.nom
                    : '${ligne.nom} — ${ligne.conditionnement}',
                quantity: ligne.quantiteVendue,
                unit: ligne.unite,
                pricePerUnit: ligne.prixUnitaire,
                total: ligne.total,
              ),
            )
            .toList(growable: false),
        saleDate: vente.date ?? DateTime.now(),
        invoiceId: _numeroTicket(),
        // 🛒 MODULE 25 — la facture explique le prix payé.
        totalInitial: vente.totalInitial,
        negociation: vente.montantNegociation,
        remise: vente.remise,
        remiseLibelle: vente.remiseType == 'pourcentage' ? '%' : null,
        cadeaux: vente.cadeaux
            .map((CadeauVente c) =>
                '${_nombreTexte(c.quantite)} × ${c.nom}')
            .toList(growable: false),
      );

      await facture.generateAndPrintInvoice(isTicket: true);
    } catch (e) {
      debugPrint('VenteConfirmationPage : impression impossible ($e)');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impression impossible sur cet appareil.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// « VTE-20260916-0001 » → 1 (numéro de ticket affiché par InvoiceService).
  int _numeroTicket() {
    final List<String> morceaux = widget.vente.numeroVente.split('-');
    return int.tryParse(morceaux.isEmpty ? '' : morceaux.last) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final VenteEnregistree vente = widget.vente;

    return Scaffold(
      appBar: AppBar(title: const Text('Vente enregistrée')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _buildCarteSucces(theme, vente),
          const SizedBox(height: 16),
          _buildCartePaiement(theme, vente),
          const SizedBox(height: 20),
          Text(
            'Articles vendus',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...vente.lignes.map((LigneVenteEnregistree ligne) =>
              _buildLigne(theme, ligne)),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _imprimer,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.print_rounded),
              label: const Text(
                'IMPRIMER LE REÇU',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/main/panier'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text(
                'NOUVELLE VENTE',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarteSucces(ThemeData theme, VenteEnregistree vente) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: <Widget>[
          const Icon(Icons.check_circle_rounded,
              color: Colors.green, size: 56),
          const SizedBox(height: 10),
          Text(
            'Vente enregistrée avec succès',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              vente.numeroVente.isEmpty
                  ? 'Sans numéro'
                  : vente.numeroVente,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatDateHeure(vente.date ?? DateTime.now()),
            style: TextStyle(
              fontSize: 12.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartePaiement(ThemeData theme, VenteEnregistree vente) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            // 🛒 MODULE 25 — ce qui a été accordé, ligne par ligne.
            if (vente.montantNegociation > 0)
              _ligneInfo(theme, 'Prix catalogue',
                  formatMontant(vente.totalInitial)),
            if (vente.montantNegociation > 0)
              _ligneInfo(theme, 'Négociation accordée',
                  '- ${formatMontant(vente.montantNegociation)}'),
            if (vente.remise > 0)
              _ligneInfo(
                  theme,
                  vente.remiseType == 'pourcentage'
                      ? 'Réduction accordée (%)'
                      : 'Réduction accordée',
                  '- ${formatMontant(vente.remise)}'),
            if (vente.cadeaux.isNotEmpty)
              _ligneInfo(
                  theme,
                  'Cadeaux offerts',
                  '${vente.cadeaux.length} produit(s) — '
                      '${formatMontant(vente.valeurCadeaux)}'),
            if (vente.estFlexible) const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text('TOTAL',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  formatMontant(vente.total),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            _ligneInfo(theme, 'Mode de paiement',
                VenteService.libelleMode(vente.modePaiement)),
            if (vente.montantRecu != null)
              _ligneInfo(theme, 'Montant reçu', formatMontant(vente.montantRecu!)),
            if (vente.rendu != null && vente.rendu! > 0)
              _ligneInfo(theme, 'Rendu', formatMontant(vente.rendu!),
                  valeurEnVert: true),
            // 🎁 Les cadeaux sont rappelés nommément sur le reçu.
            if (vente.cadeaux.isNotEmpty) ...<Widget>[
              const Divider(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Produits offerts',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              ...vente.cadeaux.map(
                (CadeauVente cadeau) => _ligneInfo(
                  theme,
                  '${_nombreTexte(cadeau.quantite)} × ${cadeau.nom}',
                  'OFFERT',
                  valeurEnVert: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ligneInfo(ThemeData theme, String libelle, String valeur,
      {bool valeurEnVert = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            libelle,
            style: TextStyle(
              fontSize: 13.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            valeur,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: valeurEnVert ? Colors.green.shade700 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLigne(ThemeData theme, LigneVenteEnregistree ligne) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${_nombreTexte(ligne.quantiteVendue)} ${ligne.unite} '
                  '× ${formatMontant(ligne.prixUnitaire)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // 🚚 MODULE 23 — traçabilité : stock restant après la vente.
                if (_stockRestant.containsKey(ligne.produitId))
                  Text(
                    _stockIllimite.contains(ligne.produitId)
                        ? 'Stock restant : ∞ (non suivi)'
                        : 'Stock restant : '
                            '${_nombreTexte(_stockRestant[ligne.produitId]!)} '
                            '${ligne.unite}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            formatMontant(ligne.total),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
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
