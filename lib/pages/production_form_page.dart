// lib/pages/production_form_page.dart
//
// 🥖 MODULE 16 (phase C5) — BOULANGERIE : NOUVELLE PRODUCTION.
//
// On choisit le PRODUIT FINI (catalogue) et la quantité prévue ; les
// matières consommées et la clôture se gèrent ensuite dans le dossier.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/production.dart';
import 'package:biashara_yangu/services/production_service.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class ProductionFormPage extends StatefulWidget {
  const ProductionFormPage({super.key});

  @override
  State<ProductionFormPage> createState() => _ProductionFormPageState();
}

class _ProductionFormPageState extends State<ProductionFormPage> {
  final ProductionService _service = ProductionService.instance;
  final TextEditingController _quantiteCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  List<ProduitFiniOption> _produits = const <ProduitFiniOption>[];
  ProduitFiniOption? _produit;

  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _quantiteCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    if (!mounted) return;

    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final List<ProduitFiniOption> produits = await _service.listerProduits();
      if (!mounted) return;
      setState(() {
        _produits = produits;
        _produit = produits.isEmpty ? null : produits.first;
        _chargement = false;
      });
    } on ProductionServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e, st) {
      debugPrint('ProductionFormPage._charger: $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreur = 'Une erreur inattendue est survenue lors du chargement.';
        _chargement = false;
      });
    }
  }

  void _afficherErreur(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  static double _parse(String texte) {
    return double.tryParse(texte.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
  }

  Future<void> _enregistrer() async {
    if (_produit == null) {
      _afficherErreur('Choisissez le produit à fabriquer.');
      return;
    }

    final double quantite = _parse(_quantiteCtrl.text);
    if (quantite <= 0) {
      _afficherErreur('La quantité prévue doit être supérieure à zéro.');
      return;
    }

    final String note = _noteCtrl.text.trim();

    setState(() => _enregistrement = true);
    try {
      final Production production = await _service.creerProduction(
        produitId: _produit!.id,
        quantitePrevue: quantite,
        note: note.isEmpty ? null : note,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Production ${production.numero ?? ''} ouverte — '
              'ajoutez les matières consommées.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      // Retour à la liste ; l'utilisateur ouvre le dossier pour continuer.
      Navigator.of(context).pop(true);
    } on ProductionServiceException catch (e) {
      if (mounted) _afficherErreur(e.message);
    } catch (e) {
      if (mounted) _afficherErreur('Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle production')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur()
              : _produits.isEmpty
                  ? _vueSansProduit()
                  : _formulaire(theme),
    );
  }

  Widget _vueErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 48),
            const SizedBox(height: 12),
            Text(_erreur!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vueSansProduit() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Aucun article au catalogue.\n'
          'Créez d\'abord le produit fini (pain, croissant…) dans la '
          'rubrique Articles.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _formulaire(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        AppDropdownField<ProduitFiniOption>(
          label: 'Produit à fabriquer',
          value: _produit,
          prefixIcon: Icons.bakery_dining_rounded,
          items: _produits
              .map(
                (ProduitFiniOption produit) =>
                    DropdownMenuItem<ProduitFiniOption>(
                  value: produit,
                  child: Text(produit.nom, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(growable: false),
          onChanged: (ProduitFiniOption? produit) {
            if (produit != null) setState(() => _produit = produit);
          },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _quantiteCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Quantité prévue',
            hintText: '100',
            prefixIcon: Icon(Icons.numbers_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _noteCtrl,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Note (facultatif)',
            hintText: 'Fournée du matin, commande spéciale…',
            prefixIcon: Icon(Icons.notes_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
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
                : const Icon(Icons.play_arrow_rounded),
            label: const Text('Ouvrir la production'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'À la clôture, le produit fini entre automatiquement en stock et '
          'le coût de revient unitaire est calculé (matières ÷ quantité '
          'produite).',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
