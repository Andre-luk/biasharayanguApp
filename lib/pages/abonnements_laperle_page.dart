// lib/pages/abonnements_laperle_page.dart
//
// MODULE 4 — ONGLET « ABONNEMENTS » DE L'ESPACE PLATEFORME.
//
// Sans cet écran, un comptable FINANCE_LAPERLE ne pourrait pas atteindre les
// fiches d'abonnement du Module 3 : il n'a pas le droit d'ouvrir la liste des
// entreprises (page `entreprises`), mais il doit pouvoir encaisser.
//
// L'écran est volontairement en lecture : le paiement se fait sur la fiche
// d'abonnement (Module 3), protégée par `paiements / creer`.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/widgets/statut_abonnement_chip.dart';

class AbonnementsLaperlePage extends StatefulWidget {
  const AbonnementsLaperlePage({super.key});

  @override
  State<AbonnementsLaperlePage> createState() => _AbonnementsLaperlePageState();
}

class _AbonnementsLaperlePageState extends State<AbonnementsLaperlePage> {
  final TextEditingController _recherche = TextEditingController();

  List<Entreprise> _entreprises = const <Entreprise>[];
  StatutAbonnement? _filtre;
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final List<Entreprise> entreprises =
          await EntrepriseService.instance.getEntreprises();
      if (!mounted) return;
      setState(() {
        _entreprises = entreprises;
        _chargement = false;
      });
    } on EntrepriseServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger les abonnements : $e';
        _chargement = false;
      });
    }
  }

  List<Entreprise> get _visibles {
    final String recherche = _recherche.text.trim().toLowerCase();

    return _entreprises.where((Entreprise e) {
      if (_filtre != null && e.statut != _filtre) return false;
      if (recherche.isEmpty) return true;
      return e.nom.toLowerCase().contains(recherche);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
              const SizedBox(height: 12),
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
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

    final List<Entreprise> visibles = _visibles;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _recherche,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Rechercher une entreprise…',
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: <Widget>[
              FilterChip(
                label: const Text('Toutes'),
                selected: _filtre == null,
                onSelected: (_) => setState(() => _filtre = null),
              ),
              const SizedBox(width: 8),
              ...StatutAbonnement.statutsFiltrables.map(
                (StatutAbonnement statut) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(statut.libelle),
                    selected: _filtre == statut,
                    onSelected: (_) => setState(
                      () => _filtre = _filtre == statut ? null : statut,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _charger,
            child: visibles.isEmpty
                ? ListView(
                    children: const <Widget>[
                      SizedBox(height: 80),
                      Center(child: Text('Aucun abonnement à afficher.')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visibles.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Entreprise entreprise = visibles[index];
                      return _carteEntreprise(context, entreprise);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _carteEntreprise(BuildContext context, Entreprise entreprise) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final int? jours = entreprise.joursRestants;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => GoRouter.of(context)
            .push('/admin/abonnements/${entreprise.id}', extra: entreprise),
        title: Text(
          entreprise.nom,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StatutAbonnementChip(statut: entreprise.statut, compact: true),
              const SizedBox(height: 6),
              Text(
                'Payé : ${entreprise.montantDejaPaye.toStringAsFixed(0)} / '
                '${entreprise.montantTotalDu.toStringAsFixed(0)} CDF'
                '   •   Solde : ${entreprise.soldeRestant.toStringAsFixed(0)} CDF',
                style: const TextStyle(fontSize: 12),
              ),
              if (jours != null)
                Text(
                  jours >= 0
                      ? 'Expire dans $jours jour(s)'
                      : 'Expiré depuis ${-jours} jour(s)',
                  style: TextStyle(
                    fontSize: 12,
                    color: jours >= 0 ? Colors.grey[700] : Colors.red.shade700,
                  ),
                ),
            ],
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.primary),
      ),
    );
  }
}
