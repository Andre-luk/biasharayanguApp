// lib/pages/distribution_finance_page.dart
//
// 🚚 MODULE 24 — CAISSE, REMISES ET DÉPENSES DE LA DISTRIBUTION.
//
// Règle centrale : l'argent d'une vente reste chez le commercial jusqu'à ce
// que le COMPTABLE confirme l'avoir reçu, puis que le GÉRANT valide. C'est
// seulement à ce moment que la caisse augmente. Une dépense validée diminue
// la caisse ; aucun solde n'est modifié à la main.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/services/distribution_gestion_service.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/distribution_widgets.dart';

class DistributionFinancePage extends StatefulWidget {
  const DistributionFinancePage({super.key, this.ongletInitial = 0});

  final int ongletInitial;

  @override
  State<DistributionFinancePage> createState() =>
      _DistributionFinancePageState();
}

class _DistributionFinancePageState extends State<DistributionFinancePage>
    with SingleTickerProviderStateMixin {
  final DistributionGestionService _service =
      DistributionGestionService.instance;
  late final TabController _tabs =
      TabController(length: 4, vsync: this, initialIndex: widget.ongletInitial);

  RoleDistribution _role = RoleDistribution.aucun;
  ResumeCaisseDistribution _caisse = const ResumeCaisseDistribution();
  List<RemiseArgent> _remises = const <RemiseArgent>[];
  List<DepenseDistribution> _depenses = const <DepenseDistribution>[];

  /// 📈 MODULE 24 §11 — analyse de rentabilité (direction / comptable).
  RentabiliteDistribution? _rentabilite;
  List<ResumeBonusCommercial> _bonusParCommercial =
      const <ResumeBonusCommercial>[];
  bool _chargement = true;
  String? _erreur;

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
      final RoleDistribution role = await _service.role();
      final ResumeCaisseDistribution caisse = await _service.caisse();
      final List<RemiseArgent> remises = await _service.remises();
      final List<DepenseDistribution> depenses = await _service.depenses();

      // 📈 MODULE 24 §11 — rentabilité (best-effort : jamais bloquant).
      RentabiliteDistribution? rentabilite = _rentabilite;
      List<ResumeBonusCommercial> bonusParCommercial =
          _bonusParCommercial;
      final bool peutAnalyser = role == RoleDistribution.proprietaire ||
          role == RoleDistribution.gerant ||
          role == RoleDistribution.comptable;
      if (peutAnalyser) {
        try {
          rentabilite = await _service.rentabilite();
          bonusParCommercial = await _service.resumeBonus();
        } catch (e) {
          debugPrint('DistributionFinancePage rentabilité (ignoré) : $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _role = role;
        _caisse = caisse;
        _remises = remises;
        _depenses = depenses;
        _rentabilite = rentabilite;
        _bonusParCommercial = bonusParCommercial;
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
      debugPrint('DistributionFinancePage : $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger la caisse et les dépenses.';
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

  Future<void> _apport() async {
    final TextEditingController montant = TextEditingController();
    final String? motif = await dialogueTexte(
      context,
      titre: 'Apport en caisse',
      label: 'Origine de l\'apport (ex. fonds de caisse)',
    );
    if (motif == null) {
      montant.dispose();
      return;
    }

    final double? valeur = await showDialog<double>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Montant de l\'apport'),
        content: TextField(
          controller: montant,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
          ],
          decoration: const InputDecoration(labelText: 'Montant'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(double.tryParse(
                montant.text.replaceAll(' ', '').replaceAll(',', '.'))),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    montant.dispose();
    if (valeur == null || valeur <= 0) return;

    try {
      await _service.apportCaisse(montant: valeur, motif: motif);
      _message('Apport enregistré : le solde de caisse est mis à jour.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _receptionnerRemise(RemiseArgent r) async {
    final TextEditingController montant = TextEditingController(
        text: r.montantDeclare.toStringAsFixed(0));

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Réception de la remise ${r.numero}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ligneDistribution('Déclaré par le commercial',
                montantDistribution(r.montantDeclare), gras: true),
            ligneDistribution('Commercial', r.commercial),
            const SizedBox(height: 12),
            TextField(
              controller: montant,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
              ],
              decoration:
                  const InputDecoration(labelText: 'Montant réellement reçu'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Toute différence exigera un motif et ouvrira une anomalie.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmer la réception'),
          ),
        ],
      ),
    );

    if (ok != true) {
      montant.dispose();
      return;
    }

    final double valeur = double.tryParse(
            montant.text.replaceAll(' ', '').replaceAll(',', '.')) ??
        0;
    montant.dispose();

    String? motif;
    if ((valeur - r.montantDeclare).abs() > 0.009) {
      motif = await dialogueTexte(
        context,
        titre: 'Écart de remise',
        label: 'Expliquez la différence entre déclaré et reçu',
      );
      if (motif == null) return;
    }

    try {
      await _service.receptionnerRemise(
        r.id,
        montantRecu: valeur,
        motif: motif,
      );
      _message('Remise réceptionnée : le gérant doit valider l\'entrée en caisse.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _validerRemise(RemiseArgent r) async {
    final bool ok = await confirmerDistribution(
      context,
      titre: 'Validation du gérant',
      message: 'Valider l\'entrée en caisse de '
          '${montantDistribution(r.montantRecu > 0 ? r.montantRecu : r.montantDeclare)} '
          'pour la remise ${r.numero} ?',
      libelleConfirmer: 'Valider et encaisser',
    );
    if (!ok) return;

    try {
      await _service.validerRemise(r.id);
      _message('Remise validée : le montant est entré en caisse.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _nouvelleDepense() async {
    final _SaisieDepense? saisie = await showDialog<_SaisieDepense>(
      context: context,
      builder: (BuildContext _) => const _DialogueDepense(),
    );
    if (saisie == null) return;

    try {
      await _service.creerDepense(
        categorie: saisie.categorie,
        montant: saisie.montant,
        motif: saisie.motif,
        justificatif: saisie.justificatif,
      );
      _message('Dépense enregistrée : elle attend l\'autorisation du gérant.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _traiterDepense(DepenseDistribution d, {required bool accepter}) async {
    String? motif;
    if (!accepter) {
      motif = await dialogueTexte(
        context,
        titre: 'Refus de la dépense',
        label: 'Motif du refus',
      );
      if (motif == null) return;
    }

    try {
      await _service.validerDepense(d.id, accepter: accepter, motif: motif);
      _message(accepter
          ? 'Dépense validée : la caisse a été débitée.'
          : 'Dépense refusée.');
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
        title: const Text('Caisse & dépenses'),
        bottom: TabBar(
          controller: _tabs,
          tabs: <Tab>[
            const Tab(text: 'Caisse'),
            Tab(
                text:
                    'Remises (${_remises.where((RemiseArgent r) => r.attenteComptable || r.attenteGerant).length})'),
            Tab(
                text:
                    'Dépenses (${_depenses.where((DepenseDistribution d) => d.enAttente).length})'),
            // Toujours présent : sinon le TabController (length 4) et le TabBar
            // n'auraient plus le même nombre d'onglets pendant le chargement.
            const Tab(text: 'Rentabilité'),
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
                    _vueCaisse(),
                    _vueRemises(),
                    _vueDepenses(),
                    _vueRentabilite(),
                  ],
                ),
      floatingActionButton: _fab(),
    );
  }

  Widget? _fab() {
    if (_tabs.index == 0 && _role == RoleDistribution.proprietaire) {
      return FloatingActionButton.extended(
        onPressed: _apport,
        icon: const Icon(Icons.add_card_rounded),
        label: const Text('Apport en caisse'),
      );
    }
    if (_tabs.index == 2 &&
        (_role == RoleDistribution.comptable ||
            _role == RoleDistribution.gerant ||
            _role == RoleDistribution.proprietaire)) {
      return FloatingActionButton.extended(
        onPressed: _nouvelleDepense,
        icon: const Icon(Icons.receipt_long_rounded),
        label: const Text('Nouvelle dépense'),
      );
    }
    return null;
  }

  Widget _vueCaisse() {
    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: <Widget>[
              CarteKpiDistribution(
                icone: Icons.play_circle_outline,
                libelle: 'Solde initial',
                valeur: montantDistribution(_caisse.soldeInitial),
              ),
              CarteKpiDistribution(
                icone: Icons.south_west_rounded,
                libelle: 'Recettes confirmées',
                valeur: montantDistribution(_caisse.entrees),
                couleur: Colors.green.shade700,
              ),
              CarteKpiDistribution(
                icone: Icons.north_east_rounded,
                libelle: 'Dépenses validées',
                valeur: montantDistribution(_caisse.sorties),
                couleur: Colors.red.shade700,
              ),
              CarteKpiDistribution(
                icone: Icons.account_balance_wallet_rounded,
                libelle: 'Solde disponible',
                valeur: montantDistribution(_caisse.solde),
                couleur: Colors.blue.shade800,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SectionDistribution(
            titre: 'Mouvements de caisse',
            sousTitre: 'Chaque mouvement a un auteur, une date et un motif.',
            child: SizedBox.shrink(),
          ),
          if (_caisse.mouvements.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucun mouvement de caisse.', textAlign: TextAlign.center),
            )
          else
            for (final MouvementCaisseDistribution m in _caisse.mouvements)
              Card(
                elevation: 0,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.4),
                child: ListTile(
                  leading: Icon(
                    m.entree
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: m.entree
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                  title: Text(m.motif),
                  subtitle: Text(<String>[
                    if (m.categorie.isNotEmpty) m.categorie,
                    if (m.auteur.isNotEmpty) m.auteur,
                    if (m.date != null) _date(m.date!),
                  ].join(' · ')),
                  trailing: Text(
                    '${m.entree ? '+' : '−'}${montantDistribution(m.montant)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: m.entree
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _vueRemises() {
    if (_remises.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune remise déclarée.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _remises.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int i) {
          final RemiseArgent r = _remises[i];
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
                        child: Text('${r.numero} · ${r.commercial}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      PuceDistribution(
                        libelle: r.libelleStatut,
                        couleur: r.statut == 'validee'
                            ? Colors.green.shade700
                            : r.statut == 'litige'
                                ? Colors.red.shade700
                                : Colors.orange.shade800,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ligneDistribution(
                      'Déclaré', montantDistribution(r.montantDeclare)),
                  if (r.montantRecu > 0)
                    ligneDistribution(
                        'Reçu', montantDistribution(r.montantRecu)),
                  if (r.montantValide > 0)
                    ligneDistribution(
                        'Validé en caisse', montantDistribution(r.montantValide),
                        gras: true),
                  if (r.motif.isNotEmpty)
                    Text('Motif : ${r.motif}',
                        style: Theme.of(context).textTheme.bodySmall),
                  if (r.attenteComptable &&
                      (_role == RoleDistribution.comptable ||
                          _role.estDirection)) ...<Widget>[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => _receptionnerRemise(r),
                        child: const Text('Réceptionner l\'argent'),
                      ),
                    ),
                  ],
                  if (r.attenteGerant && _role.estDirection) ...<Widget>[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () => _validerRemise(r),
                        icon: const Icon(Icons.verified_outlined, size: 18),
                        label: const Text('Valider l\'entrée en caisse'),
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

  // ---------------------------------------------------------------------------
  // 📈 MODULE 24 §11 — RENTABILITÉ (marges réelles, bonus par commercial)
  // ---------------------------------------------------------------------------

  Widget _vueRentabilite() {
    final ThemeData theme = Theme.of(context);
    final RentabiliteDistribution? r = _rentabilite;

    // L'analyse est réservée à la direction et au comptable (le serveur le
    // vérifie aussi : `dist_rentabilite` refuse les autres rôles).
    final bool peutAnalyser = _role == RoleDistribution.proprietaire ||
        _role == RoleDistribution.gerant ||
        _role == RoleDistribution.comptable;
    if (!peutAnalyser) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'L\'analyse de rentabilité est réservée à la direction et au '
            'comptable.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (r == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Analyse indisponible pour le moment.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Marge brute du mois',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  montantDistribution(r.margeBrute),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: r.margeBrute >= 0
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 10),
                ligneDistribution('Chiffre d\'affaires',
                    montantDistribution(r.ca)),
                ligneDistribution('Coût des marchandises',
                    montantDistribution(r.coutMarchandises)),
                if (r.margePct != null)
                  ligneDistribution(
                      'Taux de marge', '${r.margePct!.toStringAsFixed(1)} %'),
                ligneDistribution('Bonus & dommages validés',
                    montantDistribution(r.bonusDommages)),
              ],
            ),
          ),
          if (!r.coutComplet) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.info_outline_rounded,
                      color: Colors.orange.shade900, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Coûts incomplets : au moins un intrant n\'a pas de prix '
                      'd\'achat. Renseignez-le pour obtenir des marges fiables.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (r.produits.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            SectionDistribution(
              titre: 'Coût de revient par produit',
              child: Column(
                children: <Widget>[
                  for (final CoutRevientProduit p in r.produits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(p.produit,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          ligneDistribution(
                            'Coût unitaire',
                            p.coutUnitaire == null
                                ? 'à renseigner'
                                : montantDistribution(p.coutUnitaire!),
                          ),
                          ligneDistribution(
                              'Prix de vente', montantDistribution(p.prixVente)),
                          ligneDistribution(
                            'Marge unitaire',
                            p.margeUnitaire == null
                                ? '—'
                                : montantDistribution(p.margeUnitaire!),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SectionDistribution(
            titre: 'Chiffre d\'affaires par commercial',
            child: Column(
              children: <Widget>[
                if (r.parCommercial.isEmpty)
                  const Text('Aucune vente sur la période.')
                else
                  for (final MargeCommercial c in r.parCommercial)
                    ligneDistribution(
                      '${c.commercial.isEmpty ? 'Commercial' : c.commercial} '
                      '(${c.nbVentes})',
                      montantDistribution(c.ca),
                    ),
              ],
            ),
          ),
          if (_bonusParCommercial.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            SectionDistribution(
              titre: 'Bonus et dommages par commercial',
              child: Column(
                children: <Widget>[
                  for (final ResumeBonusCommercial b in _bonusParCommercial)
                    ligneDistribution(
                      '${b.commercial.isEmpty ? 'Commercial' : b.commercial} '
                      '(bonus ${montantDistribution(b.bonusValeur)} · '
                      'dommages ${montantDistribution(b.dommageValeur)})',
                      montantDistribution(b.totalValeur),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _vueDepenses() {
    if (_depenses.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune dépense enregistrée.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _depenses.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int i) {
          final DepenseDistribution d = _depenses[i];
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
                        child: Text('${d.numero} · ${d.motif}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      PuceDistribution(
                        libelle: d.libelleStatut,
                        couleur: d.statut == 'validee'
                            ? Colors.green.shade700
                            : d.statut == 'refusee'
                                ? Colors.red.shade700
                                : Colors.orange.shade800,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ligneDistribution('Catégorie', d.categorie),
                  ligneDistribution('Montant',
                      montantDistribution(d.montant, devise: d.devise),
                      gras: true),
                  if (d.date != null)
                    ligneDistribution('Date', _date(d.date!)),
                  if (d.justificatif.isNotEmpty)
                    ligneDistribution('Justificatif', d.justificatif),
                  if (d.motifRefus.isNotEmpty)
                    Text('Refus : ${d.motifRefus}',
                        style: Theme.of(context).textTheme.bodySmall),
                  if (d.enAttente && _role.estDirection) ...<Widget>[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        children: <Widget>[
                          OutlinedButton(
                            onPressed: () =>
                                _traiterDepense(d, accepter: false),
                            child: const Text('Refuser'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                _traiterDepense(d, accepter: true),
                            child: const Text('Autoriser'),
                          ),
                        ],
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

  static String _date(DateTime date) {
    final DateTime d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

// ---------------------------------------------------------------------------
// DIALOGUE DÉPENSE
// ---------------------------------------------------------------------------

class _SaisieDepense {
  const _SaisieDepense(
      this.categorie, this.montant, this.motif, this.justificatif);

  final String categorie;
  final double montant;
  final String motif;
  final String justificatif;
}

class _DialogueDepense extends StatefulWidget {
  const _DialogueDepense();

  @override
  State<_DialogueDepense> createState() => _DialogueDepenseState();
}

class _DialogueDepenseState extends State<_DialogueDepense> {
  final TextEditingController _montant = TextEditingController();
  final TextEditingController _motif = TextEditingController();
  final TextEditingController _justificatif = TextEditingController();
  String _categorie = 'transport';

  static const List<String> _categories = <String>[
    'transport',
    'carburant',
    'entretien',
    'fournitures',
    'production',
    'autre',
  ];

  @override
  void dispose() {
    _montant.dispose();
    _motif.dispose();
    _justificatif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle dépense'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppDropdownField<String>(
              label: 'Catégorie',
              value: _categorie,
              items: _categories
                  .map((String c) => DropdownMenuItem<String>(
                        value: c,
                        child: Text(c),
                      ))
                  .toList(),
              onChanged: (String? v) =>
                  setState(() => _categorie = v ?? 'transport'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _montant,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
              ],
              decoration: const InputDecoration(labelText: 'Montant'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _motif,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Motif (obligatoire)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _justificatif,
              decoration: const InputDecoration(
                  labelText: 'Référence du justificatif (facultatif)'),
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
            final double? montant = double.tryParse(
                _montant.text.replaceAll(' ', '').replaceAll(',', '.'));
            if (montant == null || montant <= 0 || _motif.text.trim().length < 3) {
              return;
            }
            Navigator.of(context).pop(_SaisieDepense(
              _categorie,
              montant,
              _motif.text.trim(),
              _justificatif.text.trim(),
            ));
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
