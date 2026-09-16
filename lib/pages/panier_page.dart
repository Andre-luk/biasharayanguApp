// lib/pages/panier_page.dart
//
// MODULE 8 — L'ÉCRAN PANIER DU VENDEUR.
//
// Il affiche le panier partagé (`PanierService`, rempli par le scanner du
// Module 7 et par la caisse) et permet de :
//
//   • modifier la quantité d'une ligne (boutons − / + ou saisie au clavier) ;
//   • supprimer une ligne ;
//   • ajouter un article (retour au scanner plein écran) ;
//   • encaisser (écran « Encaissement ») ;
//   • vider le panier (avec confirmation).
//
// Le vendeur ne modifie AUCUN prix : il ne peut que jouer sur les quantités.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/ligne_panier.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/banniere_abonnement.dart';

/// Écran « Panier » — liste des lignes, total et encaissement.
class PanierPage extends StatefulWidget {
  const PanierPage({super.key});

  @override
  State<PanierPage> createState() => _PanierPageState();
}

class _PanierPageState extends State<PanierPage> {
  final PanierService _panier = PanierService.instance;
  final TextEditingController _quantiteControleur = TextEditingController();

  @override
  void initState() {
    super.initState();
    _panier.revision.addListener(_onPanierModifie);
  }

  @override
  void dispose() {
    _panier.revision.removeListener(_onPanierModifie);
    _quantiteControleur.dispose();
    super.dispose();
  }

  void _onPanierModifie() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  /// Retour au scanner plein écran (Module 7).
  Future<void> _ajouterArticle() => context.push('/scanner');

  /// Ouvre l'écran d'encaissement (refusé si l'abonnement est échu).
  Future<void> _encaisser() async {
    if (AbonnementService.instance.lectureSeule) {
      afficherDialogueLectureSeule(context);
      return;
    }
    await context.push('/main/panier/encaissement');
  }

  /// Vide le panier après confirmation.
  Future<void> _vider() async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogue) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Vider le panier ?'),
        content: const Text(
          'Toutes les lignes seront retirées. La vente en cours sera perdue.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogue, false),
            child: const Text('Non'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(dialogue, true),
            child: const Text('Vider'),
          ),
        ],
      ),
    );

    if (confirme == true) {
      _panier.vider();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Panier vidé.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Saisie directe de la quantité d'une ligne.
  Future<void> _modifierQuantite(LignePanier ligne) async {
    final double maximum = ligne.vendu.quantiteMaxVendable;
    _quantiteControleur.text = _texteQuantite(ligne.quantite);

    final double? nouvelle = await showDialog<double>(
      context: context,
      builder: (BuildContext dialogue) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(ligne.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              ligne.vendu.estConditionnement
                  ? '${ligne.vendu.libelleConditionnement} — '
                      '${formatMontant(ligne.prixUnitaire)} l\'unité'
                  : '${formatMontant(ligne.prixUnitaire)} / ${ligne.vendu.uniteVente}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Text(
              'Maximum vendable : ${_texteQuantite(maximum)} '
              '${ligne.vendu.uniteVentePlurielle(maximum)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _quantiteControleur,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantité (${ligne.vendu.uniteVente})',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogue),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final double? valeur = double.tryParse(
                _quantiteControleur.text.trim().replaceAll(',', '.'),
              );
              if (valeur == null || valeur <= 0) {
                Navigator.pop(dialogue);
                _afficherErreur('Quantité invalide.');
                return;
              }
              if (maximum > 0 && valeur > maximum) {
                Navigator.pop(dialogue);
                _afficherErreur(
                  'Stock insuffisant : maximum ${_texteQuantite(maximum)} '
                  '${ligne.vendu.uniteVentePlurielle(maximum)}.',
                );
                return;
              }
              Navigator.pop(dialogue, valeur);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );

    if (nouvelle != null) {
      _panier.modifierQuantite(ligne.itemId, nouvelle);
    }
  }

  void _afficherErreur(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panier'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Mes ventes du jour',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => context.push('/main/ventes'),
          ),
        ],
      ),
      body: _panier.estVide ? _buildVide() : _buildContenu(),
    );
  }

  Widget _buildVide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.shopping_cart_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Votre panier est vide',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Scannez les articles vendus : ils s\'ajouteront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            if (PermissionService.instance.peutVoir(PageAccess.scanner))
              FilledButton.icon(
                onPressed: _ajouterArticle,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text(
                  'SCANNER UN ARTICLE',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenu() {
    final List<LignePanier> lignes = _panier.lignes;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: lignes.length,
            itemBuilder: (BuildContext context, int index) =>
                _buildLigne(lignes[index]),
          ),
        ),
        _buildPied(),
      ],
    );
  }

  Widget _buildLigne(LignePanier ligne) {
    final ThemeData theme = Theme.of(context);
    final double maximum = ligne.vendu.quantiteMaxVendable;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
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
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ligne.vendu.estConditionnement
                        ? '${ligne.vendu.libelleConditionnement} · '
                            '${formatMontant(ligne.prixUnitaire)} l\'unité'
                        : '${formatMontant(ligne.prixUnitaire)} / '
                            '${ligne.vendu.uniteVente}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _boutonPas(
              icone: Icons.remove_rounded,
              actif: ligne.quantite > 1,
              onTap: () =>
                  _panier.modifierQuantite(ligne.itemId, ligne.quantite - 1),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _modifierQuantite(ligne),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  _texteQuantite(ligne.quantite),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            _boutonPas(
              icone: Icons.add_rounded,
              actif: ligne.quantite < maximum,
              onTap: () =>
                  _panier.modifierQuantite(ligne.itemId, ligne.quantite + 1),
            ),
            SizedBox(
              width: 86,
              child: Text(
                formatMontant(ligne.sousTotal),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Retirer du panier',
              icon: Icon(Icons.delete_outline_rounded,
                  color: Colors.red.shade400),
              onPressed: () => _panier.supprimer(ligne.itemId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boutonPas({
    required IconData icone,
    required bool actif,
    required VoidCallback onTap,
  }) {
    return Material(
      color: actif
          ? Theme.of(context).colorScheme.surface
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: actif ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            icone,
            size: 19,
            color: actif
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildPied() {
    final ThemeData theme = Theme.of(context);
    final double total = _panier.total();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (PermissionService.instance.peutVoir(PageAccess.scanner))
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _ajouterArticle,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  label: const Text(
                    'AJOUTER UN ARTICLE',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '${_panier.nombreArticles()} article(s)',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      'TOTAL',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      formatMontant(total),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _vider,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                    label: const Text('Vider'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _encaisser,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      icon: const Icon(Icons.point_of_sale_rounded),
                      label: const Text(
                        'ENCAISSER',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// « 12 » pour une quantité entière, « 1,5 » sinon.
String _texteQuantite(double valeur) {
  if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
  return valeur
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}
