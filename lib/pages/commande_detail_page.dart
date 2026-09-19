// lib/pages/commande_detail_page.dart
//
// 🍽️ MODULE 16 (phase C3) — RESTAURANT : DÉTAIL D'UNE COMMANDE.
//
// Saisie des articles depuis le catalogue, envoi en cuisine, service,
// encaissement via la caisse existante et annulation motivée. Le circuit
// cuisine (en préparation / prête) se pilote aussi depuis l'écran Cuisine.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/commande.dart';
import 'package:biashara_yangu/services/restaurant_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/statut_restaurant_chips.dart';

class CommandeDetailPage extends StatefulWidget {
  const CommandeDetailPage({
    super.key,
    required this.commandeId,
    this.commande,
  });

  final String commandeId;

  /// Commande transmise par la liste (rechargée ensuite si absente).
  final Commande? commande;

  @override
  State<CommandeDetailPage> createState() => _CommandeDetailPageState();
}

class _CommandeDetailPageState extends State<CommandeDetailPage> {
  final RestaurantService _service = RestaurantService.instance;

  Commande? _commande;
  List<ProduitRestaurantOption>? _produits;

  bool _chargement = true;
  bool _actionEnCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _commande = widget.commande;
    _charger();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux && _commande == null) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    try {
      final Commande commande = await _service.chargerCommande(widget.commandeId);
      if (!mounted) return;
      setState(() {
        _commande = commande;
        _erreur = null;
        _chargement = false;
      });
    } on RestaurantServiceException catch (e) {
      if (!mounted) return;
      if (silencieux) {
        _message(e.message, erreur: true);
        return;
      }
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e, st) {
      debugPrint('CommandeDetailPage._charger: $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreur = 'Erreur inattendue : $e';
        _chargement = false;
      });
    }
  }

  void _message(String texte, {bool erreur = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red.shade700 : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _ajouterArticle() async {
    final Commande? commande = _commande;
    if (commande == null) return;

    if (_produits == null) {
      try {
        _produits = await _service.listerProduits();
      } on RestaurantServiceException catch (e) {
        if (!mounted) return;
        _message(e.message, erreur: true);
        return;
      }
    }

    final List<ProduitRestaurantOption> produits =
        _produits ?? const <ProduitRestaurantOption>[];
    if (produits.isEmpty) {
      _message('Aucun article au catalogue : créez d\'abord des articles.',
          erreur: true);
      return;
    }

    ProduitRestaurantOption? choisi;
    final TextEditingController quantiteCtrl = TextEditingController(text: '1');

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          title: const Text('Ajouter un article'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppDropdownField<ProduitRestaurantOption>(
                label: 'Article *',
                value: choisi,
                hint: 'Choisir un article',
                prefixIcon: Icons.restaurant_menu_rounded,
                items: produits
                    .map(
                      (ProduitRestaurantOption produit) =>
                          DropdownMenuItem<ProduitRestaurantOption>(
                        value: produit,
                        child: Text(
                          '${produit.nom} '
                          '(${formatMontant(produit.prixVente)} / ${produit.uniteMesure})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (ProduitRestaurantOption? produit) =>
                    setDialogState(() => choisi = produit),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantiteCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Quantité *',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );

    if (confirme != true || choisi == null || !mounted) {
      quantiteCtrl.dispose();
      return;
    }

    final double quantite =
        double.tryParse(quantiteCtrl.text.replaceAll(',', '.')) ?? 0;
    quantiteCtrl.dispose();

    if (quantite <= 0) {
      _message('La quantité doit être supérieure à zéro.', erreur: true);
      return;
    }

    setState(() => _actionEnCours = true);
    try {
      await _service.ajouterLigne(
        commandeId: commande.id,
        produitId: choisi!.id,
        quantite: quantite,
      );
      await _charger(silencieux: true);
      if (mounted) _message('${choisi!.nom} ajouté à la commande.');
    } on RestaurantServiceException catch (e) {
      if (mounted) _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _retirerLigne(LigneCommande ligne) async {
    final Commande? commande = _commande;
    if (commande == null) return;

    try {
      await _service.supprimerLigne(ligne.id);
      await _charger(silencieux: true);
      if (mounted) _message('${ligne.libelle} retiré.');
    } on RestaurantServiceException catch (e) {
      if (mounted) _message(e.message, erreur: true);
    }
  }

  Future<void> _envoyer() async {
    final Commande? commande = _commande;
    if (commande == null) return;

    setState(() => _actionEnCours = true);
    try {
      await _service.envoyer(commande.id);
      await _charger(silencieux: true);
      if (mounted) _message('Commande envoyée en cuisine.');
    } on RestaurantServiceException catch (e) {
      if (mounted) _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _marquerServie() async {
    final Commande? commande = _commande;
    if (commande == null) return;

    setState(() => _actionEnCours = true);
    try {
      await _service.avancer(commande.id, StatutCommande.servie);
      await _charger(silencieux: true);
      if (mounted) _message('Commande marquée servie.');
    } on RestaurantServiceException catch (e) {
      if (mounted) _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _encaisser() async {
    final Commande? commande = _commande;
    if (commande == null) return;

    String mode = 'especes';
    final TextEditingController recuCtrl = TextEditingController();

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          title: Text('Encaisser • ${formatMontant(commande.montantTotal)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppDropdownField<String>(
                label: 'Mode de paiement',
                value: mode,
                items: RestaurantService.modesPaiement.entries
                    .map(
                      (MapEntry<String, String> e) =>
                          DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(e.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (String? valeur) =>
                    setDialogState(() => mode = valeur ?? 'especes'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: recuCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Montant reçu (facultatif)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'La vente est enregistrée dans la caisse (stock, reçu et '
                'journal compris).',
                style: TextStyle(fontSize: 11.5),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Encaisser'),
            ),
          ],
        ),
      ),
    );

    if (confirme != true || !mounted) {
      recuCtrl.dispose();
      return;
    }

    final double? recu = recuCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(recuCtrl.text.replaceAll(',', '.'));
    recuCtrl.dispose();

    setState(() => _actionEnCours = true);
    try {
      final Commande miseAJour =
          await _service.encaisser(commande.id, modePaiement: mode, montantRecu: recu);
      await _charger(silencieux: true);
      if (mounted) {
        _message(
            'Encaissée • vente ${miseAJour.numeroVente ?? ''} enregistrée en caisse.');
      }
    } on RestaurantServiceException catch (e) {
      if (mounted) _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _annuler() async {
    final Commande? commande = _commande;
    if (commande == null) return;

    final TextEditingController motifCtrl = TextEditingController();

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Annuler la commande ?'),
        content: TextField(
          controller: motifCtrl,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Motif (facultatif)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Annuler la commande'),
          ),
        ],
      ),
    );

    if (confirme != true || !mounted) {
      motifCtrl.dispose();
      return;
    }

    final String motif = motifCtrl.text.trim();
    motifCtrl.dispose();

    setState(() => _actionEnCours = true);
    try {
      await _service.annuler(commande.id, motif: motif.isEmpty ? null : motif);
      await _charger(silencieux: true);
      if (mounted) _message('Commande annulée.');
    } on RestaurantServiceException catch (e) {
      if (mounted) _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Commande? commande = _commande;

    return Scaffold(
      appBar: AppBar(
        title: Text(commande?.numero ?? 'Commande'),
      ),
      body: _chargement && commande == null
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null && commande == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreur!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _charger(silencieux: true),
                  child: _contenu(commande!),
                ),
    );
  }

  Widget _contenu(Commande commande) {
    final ThemeData theme = Theme.of(context);
    final bool active = commande.statut.estActive;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Table ${commande.tableNumero.isEmpty ? '—' : commande.tableNumero}'
                        ' • ${commande.nbPersonnes} pers.',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    StatutCommandeChip(statut: commande.statut, compact: true),
                  ],
                ),
                if (commande.clientNom != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text('Client : ${commande.clientNom}',
                      style: theme.textTheme.bodySmall),
                ],
                if (commande.note != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text('Note : ${commande.note}',
                      style: theme.textTheme.bodySmall),
                ],
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text('Total'),
                    Text(
                      formatMontant(commande.montantTotal),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                if (commande.numeroVente != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text('Vente ${commande.numeroVente} enregistrée en caisse.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.primary)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Articles',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (active)
              TextButton.icon(
                onPressed: _actionEnCours ? null : _ajouterArticle,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ajouter'),
              ),
          ],
        ),
        if (commande.lignes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Aucun article : ajoutez les plats et boissons.'),
          )
        else
          ...commande.lignes.map((LigneCommande ligne) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  title: Text('${_quantite(ligne.quantiteVendue)}× ${ligne.libelle}'),
                  subtitle: Text(
                    '${formatMontant(ligne.prixUnitaire)} × '
                    '${_quantite(ligne.quantiteVendue)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(formatMontant(ligne.total)),
                      if (commande.statut == StatutCommande.ouverte)
                        IconButton(
                          tooltip: 'Retirer',
                          onPressed: _actionEnCours
                              ? null
                              : () => _retirerLigne(ligne),
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 20),
                        ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            if (commande.statut == StatutCommande.ouverte)
              FilledButton.icon(
                onPressed: _actionEnCours ? null : _envoyer,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Envoyer en cuisine'),
              ),
            if (commande.statut == StatutCommande.prete)
              FilledButton.icon(
                onPressed: _actionEnCours ? null : _marquerServie,
                icon: const Icon(Icons.room_service_rounded),
                label: const Text('Marquer servie'),
              ),
            if (active)
              FilledButton.tonalIcon(
                onPressed: _actionEnCours ? null : _encaisser,
                icon: const Icon(Icons.payments_rounded),
                label: const Text('Encaisser'),
              ),
            if (active)
              OutlinedButton.icon(
                onPressed: _actionEnCours ? null : _annuler,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Annuler'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _quantite(double valeur) => valeur == valeur.roundToDouble()
      ? valeur.toStringAsFixed(0)
      : valeur.toString();
}
