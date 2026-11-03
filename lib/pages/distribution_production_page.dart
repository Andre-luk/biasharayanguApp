// lib/pages/distribution_production_page.dart
//
// 🚚 MODULE 24 — PRODUCTION.
//
// Le producteur DEMANDE ses intrants, le stock AUTORISE et sort les quantités,
// le producteur CONFIRME ce qu'il a réellement reçu, puis déclare sa
// production (consommé / perdu / fabriqué). Les produits finis n'entrent au
// stock central qu'après comptage par le gestionnaire de stock.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/services/distribution_gestion_service.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/distribution_widgets.dart';

class DistributionProductionPage extends StatefulWidget {
  const DistributionProductionPage({super.key, this.ongletInitial = 0});

  final int ongletInitial;

  @override
  State<DistributionProductionPage> createState() =>
      _DistributionProductionPageState();
}

class _DistributionProductionPageState
    extends State<DistributionProductionPage>
    with SingleTickerProviderStateMixin {
  final DistributionGestionService _service =
      DistributionGestionService.instance;
  late final TabController _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.ongletInitial);

  RoleDistribution _role = RoleDistribution.aucun;
  StockDistribution _stock = const StockDistribution();
  List<DemandeIntrant> _demandes = const <DemandeIntrant>[];
  List<ProductionDistribution> _productions = const <ProductionDistribution>[];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _charger();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;
    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    try {
      final RoleDistribution role = await _service.role();
      final StockDistribution stock = await _service.stock();
      final List<DemandeIntrant> demandes =
          await _service.demandesIntrants();
      final List<ProductionDistribution> productions =
          await _service.productions();

      if (!mounted) return;
      setState(() {
        _role = role;
        _stock = stock;
        _demandes = demandes;
        _productions = productions;
        _chargement = false;
        _erreur = null;
      });
    } on DistributionGestionException catch (e) {
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
      debugPrint('DistributionProductionPage : $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger la production.';
        _chargement = false;
      });
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red.shade700 : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DEMANDES D'INTRANTS
  // ---------------------------------------------------------------------------

  Future<void> _nouvelleDemande() async {
    if (_stock.intrants.isEmpty) {
      _message('Aucun intrant au catalogue : demandez au stock de les créer.',
          erreur: true);
      return;
    }

    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Demande d\'intrants',
      sousTitre: 'Le gestionnaire de stock autorisera les quantités.',
      articles: _stock.intrants
          .map((LigneStockDistribution l) => ArticleQuantite(
                id: l.id,
                nom: l.nom,
                unite: l.unite,
                valeurInitiale: 0,
                min: 0,
                description: 'Disponible : ${quantiteDistribution(l.stock)}',
              ))
          .toList(),
      libelleValider: 'Envoyer au stock',
    );
    if (quantites == null) return;

    final List<Map<String, dynamic>> lignes = quantites.entries
        .where((MapEntry<String, double> e) => e.value > 0)
        .map((MapEntry<String, double> e) => <String, dynamic>{
              'intrant_id': e.key,
              'quantite': e.value,
            })
        .toList();
    if (lignes.isEmpty) {
      _message('Indiquez au moins un intrant.', erreur: true);
      return;
    }

    final String? note = await dialogueTexte(
      context,
      titre: 'Note pour le stock',
      label: 'Précisions (facultatif)',
      obligatoire: false,
    );

    try {
      final Map<String, dynamic> r = await _service.creerDemandeIntrants(
        lignes,
        note: (note ?? '').isEmpty ? null : note,
      );
      _message('Demande ${r['numero']} envoyée au stock.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _traiterDemande(DemandeIntrant d) async {
    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Quantités autorisées',
      sousTitre:
          'Modifiez si le stock ne peut pas fournir exactement la demande.',
      articles: d.lignes
          .map((LigneDemandeIntrant l) => ArticleQuantite(
                id: l.intrantId,
                nom: l.nom,
                unite: l.unite,
                valeurInitiale: l.demandee,
                min: 0,
              ))
          .toList(),
      libelleValider: 'Autoriser et sortir',
    );
    if (quantites == null) return;

    try {
      await _service.traiterDemandeIntrants(
        d.id,
        lignes: quantites.entries
            .map((MapEntry<String, double> e) => <String, dynamic>{
                  'intrant_id': e.key,
                  'quantite_autorisee': e.value,
                })
            .toList(),
      );
      _message('Intrants sortis du stock : le producteur doit confirmer.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _refuserDemande(DemandeIntrant d) async {
    final String? motif = await dialogueTexte(
      context,
      titre: 'Refus du stock',
      label: 'Motif du refus',
    );
    if (motif == null) return;

    try {
      await _service.traiterDemandeIntrants(d.id,
          refuser: true, motif: motif);
      _message('Demande refusée.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _receptionnerDemande(DemandeIntrant d) async {
    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Réception réelle des intrants',
      sousTitre: 'Déclarez ce que vous avez physiquement reçu.',
      articles: d.lignes
          .map((LigneDemandeIntrant l) => ArticleQuantite(
                id: l.intrantId,
                nom: l.nom,
                unite: l.unite,
                valeurInitiale: l.sortie,
                min: 0,
                max: l.sortie,
                description:
                    'Sorti du stock : ${quantiteDistribution(l.sortie)}',
              ))
          .toList(),
      libelleValider: 'Confirmer la réception',
    );
    if (quantites == null) return;

    final bool ecart = d.lignes.any((LigneDemandeIntrant l) =>
        (quantites[l.intrantId] ?? l.sortie) < l.sortie - 0.0001);

    String? motif;
    if (ecart) {
      motif = await dialogueTexte(
        context,
        titre: 'Intrants manquants',
        label: 'Expliquez la différence (une anomalie sera ouverte)',
      );
      if (motif == null) return;
    }

    try {
      await _service.receptionnerDemandeIntrants(
        d.id,
        lignes: quantites.entries
            .map((MapEntry<String, double> e) => <String, dynamic>{
                  'intrant_id': e.key,
                  'quantite_recue': e.value,
                })
            .toList(),
        motif: motif,
      );
      _message('Réception confirmée.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // PRODUCTIONS
  // ---------------------------------------------------------------------------

  Future<void> _declarerProduction() async {
    if (_stock.produits.isEmpty) {
      _message('Aucun produit fini au catalogue : le gérant doit en créer.',
          erreur: true);
      return;
    }

    final List<DemandeIntrant> disponibles = _demandes
        .where((DemandeIntrant d) =>
            d.statut == 'recue' || d.statut == 'en_litige')
        .toList();

    final _SaisieProduction? saisie = await showDialog<_SaisieProduction>(
      context: context,
      builder: (BuildContext _) => _DialogueProduction(
        demandes: disponibles,
        intrants: _stock.intrants,
        produits: _stock.produits,
      ),
    );
    if (saisie == null) return;

    try {
      final Map<String, dynamic> r = await _service.enregistrerProduction(
        demandeId: saisie.demandeId,
        intrants: saisie.intrants,
        sorties: saisie.sorties,
        motifPertes: saisie.motifPertes,
      );
      _message('Production ${r['numero']} déclarée : '
          'elle attend le comptage du stock.');
      _tabs.animateTo(1);
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _receptionnerProduction(ProductionDistribution p) async {
    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Réception au stock',
      sousTitre: 'Comptez les produits réellement remis par la production.',
      articles: p.sorties
          .map((LigneProductionSortie s) => ArticleQuantite(
                id: s.produitId,
                nom: s.nom,
                unite: s.unite,
                valeurInitiale: s.remise,
                min: 0,
                max: s.remise,
                description:
                    'Déclaré par la production : ${quantiteDistribution(s.remise)}',
              ))
          .toList(),
      libelleValider: 'Confirmer',
    );
    if (quantites == null) return;

    final bool ecart = p.sorties.any((LigneProductionSortie s) =>
        (quantites[s.produitId] ?? s.remise) < s.remise - 0.0001);

    String? motif;
    if (ecart) {
      motif = await dialogueTexte(
        context,
        titre: 'Produits manquants',
        label: 'Expliquez la différence (une anomalie sera ouverte)',
      );
      if (motif == null) return;
    }

    try {
      await _service.receptionnerProduction(
        p.id,
        lignes: quantites.entries
            .map((MapEntry<String, double> e) => <String, dynamic>{
                  'produit_id': e.key,
                  'quantite_recue': e.value,
                })
            .toList(),
        motif: motif,
      );
      _message('Production réceptionnée.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Production'),
        bottom: TabBar(
          controller: _tabs,
          tabs: <Tab>[
            Tab(
              text:
                  'Demandes (${_demandes.where((DemandeIntrant d) => d.statut == 'attente_stock' || d.statut == 'attente_reception').length})',
            ),
            Tab(
              text:
                  'Productions (${_productions.where((ProductionDistribution p) => p.attenteStock).length})',
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreur!, textAlign: TextAlign.center),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: <Widget>[
                    _listeDemandes(),
                    _listeProductions(),
                  ],
                ),
      floatingActionButton: _role.peutProduire
          ? FloatingActionButton.extended(
              onPressed: _tabs.index == 0 ? _nouvelleDemande : _declarerProduction,
              icon: Icon(_tabs.index == 0
                  ? Icons.assignment_add
                  : Icons.factory_rounded),
              label: Text(
                  _tabs.index == 0 ? 'Demander des intrants' : 'Nouvelle production'),
            )
          : null,
    );
  }

  Widget _listeDemandes() {
    if (_demandes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune demande d\'intrants.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _demandes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int i) {
          final DemandeIntrant d = _demandes[i];
          return Card(
            elevation: 0,
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${d.numero} · ${d.demandeur}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      PuceDistribution(
                        libelle: d.libelleStatut,
                        couleur: _couleurStatut(d.statut),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final LigneDemandeIntrant l in d.lignes)
                    ligneDistribution(
                      l.nom,
                      'demandé ${quantiteDistribution(l.demandee)}'
                          '${l.sortie > 0 ? ' · sorti ${quantiteDistribution(l.sortie)}' : ''}'
                          '${l.recue > 0 ? ' · reçu ${quantiteDistribution(l.recue)}' : ''}',
                    ),
                  if (d.motif.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Motif : ${d.motif}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: <Widget>[
                      if (d.attenteStock && _role.peutGererStock) ...<Widget>[
                        OutlinedButton(
                          onPressed: () => _refuserDemande(d),
                          child: const Text('Refuser'),
                        ),
                        FilledButton(
                          onPressed: () => _traiterDemande(d),
                          child: const Text('Traiter'),
                        ),
                      ],
                      if (d.attenteReception && _role.peutProduire)
                        FilledButton(
                          onPressed: () => _receptionnerDemande(d),
                          child: const Text('Confirmer la réception'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _listeProductions() {
    if (_productions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune production déclarée.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _productions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int i) {
          final ProductionDistribution p = _productions[i];
          return Card(
            elevation: 0,
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${p.numero} · ${p.responsable}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      PuceDistribution(
                        libelle: p.libelleStatut,
                        couleur: _couleurStatut(p.statut),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final LigneProductionSortie s in p.sorties)
                    ligneDistribution(
                      s.nom,
                      'produit ${quantiteDistribution(s.produite)}'
                          '${s.recue > 0 ? ' · reçu au stock ${quantiteDistribution(s.recue)}' : ''}',
                    ),
                  if (p.pertesIntrants > 0)
                    ligneDistribution('Intrants perdus',
                        quantiteDistribution(p.pertesIntrants),
                        couleur: Colors.red.shade700),
                  if (p.motifPertes.isNotEmpty)
                    Text('Motif des pertes : ${p.motifPertes}',
                        style: Theme.of(context).textTheme.bodySmall),
                  if (p.resteIntrants > 0)
                    ligneDistribution('Intrants non utilisés',
                        quantiteDistribution(p.resteIntrants)),
                  if (p.attenteStock && _role.peutGererStock) ...<Widget>[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () => _receptionnerProduction(p),
                        icon: const Icon(Icons.inventory_rounded, size: 18),
                        label: const Text('Réceptionner au stock'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _couleurStatut(String statut) {
    if (statut == 'en_litige' || statut.startsWith('refusee')) {
      return Colors.red.shade700;
    }
    if (statut == 'recue' || statut == 'cloturee') {
      return Colors.green.shade700;
    }
    return Colors.orange.shade800;
  }
}

// ---------------------------------------------------------------------------
// DIALOGUE DE DÉCLARATION DE PRODUCTION
// ---------------------------------------------------------------------------

class _SaisieProduction {
  const _SaisieProduction({
    required this.demandeId,
    required this.intrants,
    required this.sorties,
    this.motifPertes,
  });

  final String? demandeId;
  final List<Map<String, dynamic>> intrants;
  final List<Map<String, dynamic>> sorties;
  final String? motifPertes;
}

class _DialogueProduction extends StatefulWidget {
  const _DialogueProduction({
    required this.demandes,
    required this.intrants,
    required this.produits,
  });

  final List<DemandeIntrant> demandes;
  final List<LigneStockDistribution> intrants;
  final List<LigneStockDistribution> produits;

  @override
  State<_DialogueProduction> createState() => _DialogueProductionState();
}

class _DialogueProductionState extends State<_DialogueProduction> {
  String? _demandeId;
  final Map<String, TextEditingController> _sorties =
      <String, TextEditingController>{};
  final Map<String, TextEditingController> _recues =
      <String, TextEditingController>{};
  final Map<String, TextEditingController> _consommees =
      <String, TextEditingController>{};
  final Map<String, TextEditingController> _perdues =
      <String, TextEditingController>{};
  final TextEditingController _motifPertes = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final LigneStockDistribution p in widget.produits) {
      _sorties[p.id] = TextEditingController(text: '0');
    }
    for (final LigneStockDistribution i in widget.intrants) {
      _recues[i.id] = TextEditingController(text: '0');
      _consommees[i.id] = TextEditingController(text: '0');
      _perdues[i.id] = TextEditingController(text: '0');
    }
    if (widget.demandes.isNotEmpty) {
      _demandeId = widget.demandes.first.id;
      _appliquerDemande(widget.demandes.first);
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      ..._sorties.values,
      ..._recues.values,
      ..._consommees.values,
      ..._perdues.values,
      _motifPertes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _appliquerDemande(DemandeIntrant d) {
    for (final LigneDemandeIntrant l in d.lignes) {
      final double recue = l.recue > 0 ? l.recue : l.sortie;
      _recues[l.intrantId]?.text = _nombre(recue);
      _consommees[l.intrantId]?.text = _nombre(recue);
      _perdues[l.intrantId]?.text = '0';
    }
  }

  static String _nombre(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static double? _lire(TextEditingController c) => double.tryParse(
      c.text.trim().replaceAll(' ', '').replaceAll(',', '.'));

  void _valider() {
    final List<Map<String, dynamic>> sorties = <Map<String, dynamic>>[];
    for (final LigneStockDistribution p in widget.produits) {
      final TextEditingController? champ = _sorties[p.id];
      final double q = champ == null ? 0 : (_lire(champ) ?? 0);
      if (q > 0) {
        sorties.add(<String, dynamic>{'produit_id': p.id, 'quantite': q});
      }
    }
    if (sorties.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Déclarez au moins un produit fabriqué.')));
      return;
    }

    final List<Map<String, dynamic>> intrants = <Map<String, dynamic>>[];
    bool perte = false;
    for (final LigneStockDistribution i in widget.intrants) {
      final TextEditingController? cRecue = _recues[i.id];
      final TextEditingController? cConsommee = _consommees[i.id];
      final TextEditingController? cPerdue = _perdues[i.id];
      final double recue = cRecue == null ? 0 : (_lire(cRecue) ?? 0);
      final double consommee =
          cConsommee == null ? 0 : (_lire(cConsommee) ?? 0);
      final double perdue = cPerdue == null ? 0 : (_lire(cPerdue) ?? 0);

      if (recue <= 0 && consommee <= 0 && perdue <= 0) continue;

      if (consommee + perdue > recue + 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${i.nom} : consommé + perdu dépasse le reçu.')));
        return;
      }
      if (perdue > 0) perte = true;

      intrants.add(<String, dynamic>{
        'intrant_id': i.id,
        'quantite_recue': recue,
        'quantite_consommee': consommee,
        'quantite_perdue': perdue,
      });
    }

    if (intrants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Déclarez les intrants utilisés.')));
      return;
    }

    if (perte && _motifPertes.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Expliquez obligatoirement les pertes.')));
      return;
    }

    Navigator.of(context).pop(_SaisieProduction(
      demandeId: _demandeId,
      intrants: intrants,
      sorties: sorties,
      motifPertes:
          _motifPertes.text.trim().isEmpty ? null : _motifPertes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    DemandeIntrant? selection;
    for (final DemandeIntrant d in widget.demandes) {
      if (d.id == _demandeId) selection = d;
    }

    return AlertDialog(
      title: const Text('Déclarer une production'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.demandes.isNotEmpty) ...<Widget>[
                AppDropdownField<String?>(
                  label: 'Intrants reçus du stock',
                  value: _demandeId,
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sans demande (déduction du stock central)'),
                    ),
                    ...widget.demandes.map((DemandeIntrant d) =>
                        DropdownMenuItem<String?>(
                          value: d.id,
                          child: Text('${d.numero} · ${d.demandeur}'),
                        )),
                  ],
                  onChanged: (String? v) {
                    setState(() {
                      _demandeId = v;
                      if (v != null) {
                        final DemandeIntrant d =
                            widget.demandes.firstWhere((DemandeIntrant x) => x.id == v);
                        _appliquerDemande(d);
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],
              const Text('Intrants (reçu / consommé / perdu)',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final LigneStockDistribution i in widget.intrants)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(i.nom,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _champ(_recues[i.id]!, 'Reçu',
                                enabled: selection == null),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                              child: _champ(_consommees[i.id]!, 'Consommé')),
                          const SizedBox(width: 6),
                          Expanded(child: _champ(_perdues[i.id]!, 'Perdu')),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _motifPertes,
                decoration: const InputDecoration(
                  labelText: 'Motif des pertes (obligatoire s\'il y en a)',
                ),
              ),
              const SizedBox(height: 14),
              const Text('Produits finis fabriqués',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final LigneStockDistribution p in widget.produits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(p.designation,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _sorties[p.id],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9., ]')),
                          ],
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            isDense: true,
                            suffixText: p.unite,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valider,
          child: const Text('Déclarer'),
        ),
      ],
    );
  }

  Widget _champ(TextEditingController c, String label, {bool enabled = true}) {
    return TextField(
      controller: c,
      enabled: enabled,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
      ],
      textAlign: TextAlign.right,
      decoration: InputDecoration(isDense: true, labelText: label),
    );
  }
}
