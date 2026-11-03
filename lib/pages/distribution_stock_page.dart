// lib/pages/distribution_stock_page.dart
//
// 🚚 MODULE 24 — STOCK DE LA DISTRIBUTION.
//
// Deux mondes volontairement séparés : les INTRANTS (matières premières) et
// les PRODUITS FINIS. Un troisième onglet suit les réceptions d'intrants :
// le gestionnaire de stock enregistre, le gérant confirme, alors seulement
// les quantités entrent en stock.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/services/distribution_gestion_service.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/distribution_widgets.dart';

class DistributionStockPage extends StatefulWidget {
  const DistributionStockPage({super.key, this.ongletInitial = 0});

  final int ongletInitial;

  @override
  State<DistributionStockPage> createState() => _DistributionStockPageState();
}

class _DistributionStockPageState extends State<DistributionStockPage>
    with SingleTickerProviderStateMixin {
  final DistributionGestionService _service =
      DistributionGestionService.instance;
  late final TabController _tabs =
      TabController(length: 3, vsync: this, initialIndex: widget.ongletInitial);

  StockDistribution _stock = const StockDistribution();
  List<ReceptionIntrants> _receptions = const <ReceptionIntrants>[];
  bool _chargement = true;
  String? _erreur;

  RoleDistribution get _role => _stock.role;

  @override
  void initState() {
    super.initState();
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
      final StockDistribution stock = await _service.stock();
      final List<ReceptionIntrants> receptions = await _service.receptions();
      if (!mounted) return;
      setState(() {
        _stock = stock;
        _receptions = receptions;
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
      debugPrint('DistributionStockPage : $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger le stock Distribution.';
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
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _nouvelIntrant() async {
    final _SaisieIntrant? saisie = await showDialog<_SaisieIntrant>(
      context: context,
      builder: (BuildContext _) => const _DialogueIntrant(),
    );
    if (saisie == null) return;
    try {
      await _service.enregistrerIntrant(
        nom: saisie.nom,
        unite: saisie.unite,
        seuil: saisie.seuil,
        prix: saisie.prix,
      );
      _message('Intrant ajouté.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _nouveauProduit() async {
    final _SaisieProduit? saisie = await showDialog<_SaisieProduit>(
      context: context,
      builder: (BuildContext _) => const _DialogueProduit(),
    );
    if (saisie == null) return;
    try {
      await _service.enregistrerProduit(
        nom: saisie.nom,
        format: saisie.format,
        unite: saisie.unite,
        prixVente: saisie.prixVente,
        prixAchat: saisie.prixAchat,
      );
      _message('Produit fini ajouté.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _ajuster(LigneStockDistribution ligne) async {
    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Stock physique constaté',
      sousTitre: 'Saisissez la quantité réellement comptée. '
          'Un mouvement de régularisation sera enregistré.',
      articles: <ArticleQuantite>[
        ArticleQuantite(
          id: ligne.id,
          nom: ligne.designation,
          unite: ligne.unite,
          valeurInitiale: ligne.stock,
          min: 0,
        ),
      ],
      libelleValider: 'Continuer',
    );
    if (quantites == null) return;
    final double? valeur = quantites[ligne.id];
    if (valeur == null) return;

    final String? motif = await dialogueTexte(
      context,
      titre: 'Motif de la correction',
      label: 'Expliquez l\'écart (inventaire, casse, erreur…)',
    );
    if (motif == null) return;

    try {
      await _service.ajusterStock(
        intrantId: ligne.estIntrant ? ligne.id : null,
        produitId: ligne.estIntrant ? null : ligne.id,
        nouvelleQuantite: valeur,
        motif: motif,
      );
      _message('Stock corrigé et mouvement enregistré.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  /// 🏷️ MODULE 24 §9 — grille multi-tarifs d'un produit fini.
  ///
  /// Modifier un tarif ne change AUCUNE vente passée : les prix des lignes de
  /// vente sont figés à l'enregistrement.
  Future<void> _gererTarifs(LigneStockDistribution ligne) async {
    List<TarifBidon> existants = const <TarifBidon>[];
    try {
      existants = await _service.tarifs(produitId: ligne.id);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
      return;
    }
    if (!mounted) return;

    final Map<TypeOperationTarif, double>? saisie =
        await showDialog<Map<TypeOperationTarif, double>>(
      context: context,
      builder: (BuildContext _) => _DialogueTarifs(
        produit: ligne.designation,
        existants: existants,
      ),
    );
    if (saisie == null) return;

    try {
      for (final MapEntry<TypeOperationTarif, double> e in saisie.entries) {
        await _service.enregistrerTarif(
          produitId: ligne.id,
          type: e.key,
          prix: e.value,
        );
      }
      _message('Grille tarifaire enregistrée.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _mouvements(LigneStockDistribution ligne) async {
    try {
      final List<Map<String, dynamic>> mouvements = await _service.mouvements(
        intrantId: ligne.estIntrant ? ligne.id : null,
        produitId: ligne.estIntrant ? null : ligne.id,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (BuildContext ctx) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: mouvements.isEmpty
                ? const Center(child: Text('Aucun mouvement enregistré.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: mouvements.length,
                    separatorBuilder: (_, __) => const Divider(height: 20),
                    itemBuilder: (BuildContext _, int i) {
                      final Map<String, dynamic> m = mouvements[i];
                      final double q = (m['quantite'] as num?)?.toDouble() ?? 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          q >= 0
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          color: q >= 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                        title: Text(_libelleNature('${m['nature']}')),
                        subtitle: Text(
                          <String>[
                            if ('${m['motif'] ?? ''}'.isNotEmpty)
                              '${m['motif']}',
                            if ('${m['date'] ?? ''}'.isNotEmpty)
                              _dateCourte(
                                  DateTime.tryParse('${m['date']}')),
                          ].join(' · '),
                        ),
                        trailing: Text(
                          '${q >= 0 ? '+' : ''}${quantiteDistribution(q)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: q >= 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      );
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  static String _libelleNature(String nature) => switch (nature) {
        'intrant_entree' => 'Entrée d\'intrants',
        'intrant_sortie_production' => 'Sortie vers production',
        'intrant_retour_production' => 'Retour d\'intrants non utilisés',
        'production_entree' => 'Entrée de production',
        'production_perte' => 'Perte de production',
        'transfert_commercial' => 'Attribution commerciale',
        'retour_commercial' => 'Retour commercial',
        'vente_commercial' => 'Vente commerciale',
        'regularisation_intrant' => 'Régularisation d\'intrant',
        'regularisation_produit' => 'Régularisation de produit',
        _ => nature,
      };

  Future<void> _enregistrerReception() async {
    if (_stock.intrants.isEmpty) {
      _message('Créez d\'abord les intrants dans le catalogue.', erreur: true);
      return;
    }

    final String? fournisseur = await dialogueTexte(
      context,
      titre: 'Nouvelle réception d\'intrants',
      label: 'Fournisseur (facultatif)',
      obligatoire: false,
    );
    if (fournisseur == null) return;

    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Quantités physiquement reçues',
      sousTitre: 'Ces quantités sont votre première confirmation. '
          'Le gérant devra ensuite valider la réception.',
      articles: _stock.intrants
          .map((LigneStockDistribution l) => ArticleQuantite(
                id: l.id,
                nom: l.nom,
                unite: l.unite,
                valeurInitiale: 0,
                min: 0,
              ))
          .toList(),
      libelleValider: 'Enregistrer',
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
      _message('Indiquez au moins une quantité reçue.', erreur: true);
      return;
    }

    try {
      final Map<String, dynamic> resultat = await _service.enregistrerReception(
        lignes: lignes,
        fournisseur: fournisseur.isEmpty ? null : fournisseur,
      );
      _message('Réception ${resultat['numero']} enregistrée : '
          'elle attend la confirmation du gérant.');
      _tabs.animateTo(2);
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _confirmerReception(ReceptionIntrants reception) async {
    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Confirmation du gérant',
      sousTitre: 'Comptez à nouveau si nécessaire. '
          'Tout écart doit être expliqué.',
      articles: reception.lignes
          .map((LigneReceptionIntrant l) => ArticleQuantite(
                id: l.intrantId,
                nom: l.nom,
                unite: l.unite,
                valeurInitiale: l.quantiteComptee,
                min: 0,
              ))
          .toList(),
      libelleValider: 'Confirmer',
    );
    if (quantites == null) return;

    final bool ecart = reception.lignes.any((LigneReceptionIntrant l) =>
        (quantites[l.intrantId] ?? l.quantiteComptee) != l.quantiteAnnoncee);

    String? motif;
    if (ecart) {
      motif = await dialogueTexte(
        context,
        titre: 'Écart constaté',
        label: 'Expliquez la différence entre annoncé et compté',
      );
      if (motif == null) return;
    }

    try {
      await _service.confirmerReception(
        reception.id,
        lignes: quantites.entries
            .map((MapEntry<String, double> e) => <String, dynamic>{
                  'intrant_id': e.key,
                  'quantite_comptee': e.value,
                })
            .toList(),
        motif: motif,
      );
      _message('Réception validée : les quantités sont entrées en stock.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  /// Refus motivé d'une réception : aucun stock n'est touché.
  Future<void> _refuserReception(ReceptionIntrants reception) async {
    final String? motif = await dialogueTexte(
      context,
      titre: 'Refuser la réception',
      label: 'Motif du refus (obligatoire)',
    );
    if (motif == null) return;
    if (motif.trim().length < 3) {
      _message('Indiquez un motif de refus (3 caractères minimum).',
          erreur: true);
      return;
    }

    try {
      await _service.refuserReception(reception.id, motif);
      _message('Réception refusée : aucun stock n\'a été modifié.');
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
        title: const Text('Stock Distribution'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Tab>[
            Tab(text: 'Intrants'),
            Tab(text: 'Produits finis'),
            Tab(text: 'Réceptions'),
          ],
        ),
        actions: <Widget>[
          if (_role.peutGererStock)
            PopupMenuButton<String>(
              tooltip: 'Ajouter',
              onSelected: (String valeur) {
                if (valeur == 'intrant') _nouvelIntrant();
                if (valeur == 'produit' && _role.estDirection) _nouveauProduit();
              },
              itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'intrant',
                  child: Text('Nouvel intrant'),
                ),
                if (_role.estDirection)
                  const PopupMenuItem<String>(
                    value: 'produit',
                    child: Text('Nouveau produit fini'),
                  ),
              ],
            ),
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
                    _listeStock(_stock.intrants, intrants: true),
                    _listeStock(_stock.produits, intrants: false),
                    _listeReceptions(),
                  ],
                ),
      floatingActionButton: _role.peutGererStock
          ? FloatingActionButton.extended(
              onPressed: _enregistrerReception,
              icon: const Icon(Icons.move_to_inbox_rounded),
              label: const Text('Réception d\'intrants'),
            )
          : null,
    );
  }

  Widget _listeStock(List<LigneStockDistribution> lignes, {required bool intrants}) {
    if (lignes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            intrants
                ? 'Aucun intrant enregistré. Ajoutez PET, caps et bouteilles vides.'
                : 'Aucun produit fini enregistré. Ajoutez fardes, bouteilles et bidons.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: lignes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int i) {
          final LigneStockDistribution l = lignes[i];
          return Card(
            elevation: 0,
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                l.designation,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (l.rupture)
                              PuceDistribution(
                                libelle: 'Rupture',
                                couleur: Colors.red.shade700,
                              )
                            else if (l.alerte)
                              PuceDistribution(
                                libelle: 'Seuil',
                                couleur: Colors.orange.shade800,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${quantiteDistribution(l.stock, unite: l.unite)} disponible(s)',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: l.alerte
                                ? Colors.red.shade700
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        Text(
                          'Seuil ${quantiteDistribution(l.seuil)} · '
                          '${montantDistribution(l.prix)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (String valeur) {
                      if (valeur == 'ajuster') _ajuster(l);
                      if (valeur == 'mouvements') _mouvements(l);
                      if (valeur == 'tarifs') _gererTarifs(l);
                    },
                    itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'mouvements',
                        child: Text('Historique des mouvements'),
                      ),
                      // 🏷️ MODULE 24 §9 — grille multi-tarifs des bidons.
                      if (!intrants && _role.estDirection)
                        const PopupMenuItem<String>(
                          value: 'tarifs',
                          child: Text('Grille tarifaire (bidons)'),
                        ),
                      if (_role.peutGererStock)
                        const PopupMenuItem<String>(
                          value: 'ajuster',
                          child: Text('Corriger le stock'),
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

  Widget _listeReceptions() {
    if (_receptions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune réception d\'intrants enregistrée.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _receptions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int i) {
          final ReceptionIntrants r = _receptions[i];
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
                          r.numero,
                          style:
                              const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      PuceDistribution(
                        libelle: r.libelleStatut,
                        couleur: r.validee
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                      ),
                    ],
                  ),
                  if (r.fournisseur.isNotEmpty)
                    Text('Fournisseur : ${r.fournisseur}'),
                  const SizedBox(height: 6),
                  for (final LigneReceptionIntrant l in r.lignes)
                    ligneDistribution(
                      l.nom,
                      '${quantiteDistribution(l.quantiteComptee, unite: l.unite)}'
                          '${l.ecart.abs() > 0.0001 ? ' (annoncé ${quantiteDistribution(l.quantiteAnnoncee)})' : ''}',
                    ),
                  if (r.enAttente && _role.estDirection) ...<Widget>[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () => _refuserReception(r),
                          icon: const Icon(Icons.block_rounded, size: 18),
                          label: const Text('Refuser'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _confirmerReception(r),
                          icon: const Icon(Icons.verified_outlined, size: 18),
                          label: const Text('Confirmer'),
                        ),
                      ],
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
}

// ---------------------------------------------------------------------------
// DIALOGUES DE CRÉATION
// ---------------------------------------------------------------------------

class _SaisieIntrant {
  const _SaisieIntrant(this.nom, this.unite, this.seuil, this.prix);
  final String nom;
  final String unite;
  final double seuil;
  final double prix;
}

class _DialogueIntrant extends StatefulWidget {
  const _DialogueIntrant();

  @override
  State<_DialogueIntrant> createState() => _DialogueIntrantState();
}

class _DialogueIntrantState extends State<_DialogueIntrant> {
  final TextEditingController _nom = TextEditingController();
  final TextEditingController _unite = TextEditingController(text: 'unité');
  final TextEditingController _seuil = TextEditingController(text: '0');
  final TextEditingController _prix = TextEditingController(text: '0');

  @override
  void dispose() {
    _nom.dispose();
    _unite.dispose();
    _seuil.dispose();
    _prix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvel intrant'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nom,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom (PET, Caps, Bouteilles vides…)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _unite,
              decoration: const InputDecoration(labelText: 'Unité'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _seuil,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Seuil d\'alerte'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prix,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Prix unitaire (facultatif)'),
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
            final String nom = _nom.text.trim();
            if (nom.isEmpty) return;
            Navigator.of(context).pop(_SaisieIntrant(
              nom,
              _unite.text.trim().isEmpty ? 'unité' : _unite.text.trim(),
              double.tryParse(_seuil.text.replaceAll(',', '.')) ?? 0,
              double.tryParse(_prix.text.replaceAll(',', '.')) ?? 0,
            ));
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

class _SaisieProduit {
  const _SaisieProduit(
      this.nom, this.format, this.unite, this.prixVente, this.prixAchat);
  final String nom;
  final String format;
  final String unite;
  final double prixVente;
  final double prixAchat;
}

class _DialogueProduit extends StatefulWidget {
  const _DialogueProduit();

  @override
  State<_DialogueProduit> createState() => _DialogueProduitState();
}

class _DialogueProduitState extends State<_DialogueProduit> {
  final TextEditingController _nom = TextEditingController();
  final TextEditingController _unite = TextEditingController(text: 'unité');
  final TextEditingController _prixVente = TextEditingController(text: '0');
  final TextEditingController _prixAchat = TextEditingController(text: '0');
  String _format = 'farde';

  @override
  void dispose() {
    _nom.dispose();
    _unite.dispose();
    _prixVente.dispose();
    _prixAchat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau produit fini'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nom,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom (Farde 12×50cl, Bidon 20L…)',
              ),
            ),
            const SizedBox(height: 10),
            AppDropdownField<String>(
              label: 'Format',
              value: _format,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                    value: 'farde', child: Text('Farde')),
                DropdownMenuItem<String>(
                    value: 'bouteille', child: Text('Bouteille')),
                DropdownMenuItem<String>(
                    value: 'bidon', child: Text('Bidon')),
                DropdownMenuItem<String>(
                    value: 'autre', child: Text('Autre')),
              ],
              onChanged: (String? v) =>
                  setState(() => _format = v ?? 'farde'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _unite,
              decoration: const InputDecoration(labelText: 'Unité'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prixVente,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
              ],
              decoration: const InputDecoration(labelText: 'Prix de vente'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prixAchat,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
              ],
              decoration: const InputDecoration(labelText: 'Prix d\'achat'),
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
            final String nom = _nom.text.trim();
            if (nom.isEmpty) return;
            Navigator.of(context).pop(_SaisieProduit(
              nom,
              _format,
              _unite.text.trim().isEmpty ? 'unité' : _unite.text.trim(),
              double.tryParse(_prixVente.text.replaceAll(',', '.')) ?? 0,
              double.tryParse(_prixAchat.text.replaceAll(',', '.')) ?? 0,
            ));
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

String _dateCourte(DateTime? date) {
  if (date == null) return '';
  final DateTime d = date.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// 🏷️ DIALOGUE « GRILLE TARIFAIRE » (module 24 §9)
// ---------------------------------------------------------------------------

class _DialogueTarifs extends StatefulWidget {
  const _DialogueTarifs({required this.produit, required this.existants});

  final String produit;
  final List<TarifBidon> existants;

  @override
  State<_DialogueTarifs> createState() => _DialogueTarifsState();
}

class _DialogueTarifsState extends State<_DialogueTarifs> {
  final Map<TypeOperationTarif, TextEditingController> _prix =
      <TypeOperationTarif, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final TypeOperationTarif type in TypeOperationTarif.values) {
      double valeur = 0;
      for (final TarifBidon t in widget.existants) {
        if (t.type == type) valeur = t.prix;
      }
      _prix[type] = TextEditingController(
        text: valeur > 0 ? valeur.toStringAsFixed(0) : '',
      );
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _prix.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _lire(TypeOperationTarif type) {
    final String texte = _prix[type]!.text.replaceAll(' ', '');
    return double.tryParse(texte.replaceAll(',', '.')) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Tarifs — ${widget.produit}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final TypeOperationTarif type in TypeOperationTarif.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _prix[type],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: type.libelle,
                      hintText: 'Laisser vide ou 0 = non proposé',
                    ),
                  ),
                ),
              Text(
                'Les ventes déjà enregistrées gardent leurs prix : seule la '
                'grille change.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          onPressed: () {
            final Map<TypeOperationTarif, double> valeurs =
                <TypeOperationTarif, double>{};
            for (final TypeOperationTarif type in TypeOperationTarif.values) {
              final double v = _lire(type);
              if (v > 0) valeurs[type] = v;
            }
            if (valeurs.isEmpty) {
              Navigator.of(context).pop();
              return;
            }
            Navigator.of(context).pop(valeurs);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
