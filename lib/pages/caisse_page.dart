// lib/pages/caisse_page.dart
//
// MODULE 10 — ÉCRAN « CAISSE ».
//
//   • solde global de la caisse (tout l'historique) ;
//   • encaissements / décaissements du jour, détail par mode de paiement ;
//   • historique filtrable (période, sens, mode) ;
//   • bouton « Décaissement » (dépense) si le rôle peut créer une dépense ;
//   • bouton « Clôture de caisse » (si le rôle peut modifier/valider).
//
// ⚠️ La caisse est CALCULÉE par le serveur (`rpc_caisse_resume` /
//    `rpc_caisse_journal`) : ventes encaissées + règlements de dettes −
//    dépenses. Un vendeur sans droit `depenses/voir` ne voit ni le solde ni
//    les décaissements (le serveur renvoie alors `null`).
//
// ⚠️ Un décaissement ne touche JAMAIS le solde en direct : il crée une
//    dépense (`rpc_depense_creer` → `depenses`), que le serveur déduit du
//    solde au rechargement.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/mouvement_caisse.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/finance_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/ecoute_contexte_entreprise.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/decaissement_caisse_dialogue.dart';

class CaissePage extends StatefulWidget {
  const CaissePage({super.key});

  @override
  State<CaissePage> createState() => _CaissePageState();
}

class _CaissePageState extends State<CaissePage>
    with EcouteContexteEntreprise<CaissePage> {
  final FinanceService _finance = FinanceService.instance;

  bool _chargement = true;
  String? _erreur;
  ResumeCaisse? _resume;
  ResultatJournalCaisse? _journal;

  // Filtres de l'historique.
  String _periode = 'jour';
  String? _sens;
  String? _mode;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  /// 🧩 MULTI-ENTREPRISES — la caisse est calculée par le serveur pour
  /// l'entreprise active : on la relit intégralement après une bascule.
  @override
  void onChangementEntreprise(String? espaceId) {
    if (!mounted) return;
    setState(() {
      _resume = null;
      _journal = null;
    });
    _charger();
  }

  DateTime _debutPeriode() {
    final DateTime maintenant = DateTime.now();
    final DateTime aujourdHui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);
    switch (_periode) {
      case 'semaine':
        return aujourdHui.subtract(const Duration(days: 6));
      case 'mois':
        return aujourdHui.subtract(const Duration(days: 29));
      default:
        return aujourdHui;
    }
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = _resume == null;
      _erreur = null;
    });

    try {
      final List<Object> resultats = await Future.wait(<Future<Object>>[
        _finance.resumeCaisse(),
        _finance.journalCaisse(
          debut: _debutPeriode(),
          fin: DateTime.now(),
          sens: _sens,
          mode: _mode,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _resume = resultats[0] as ResumeCaisse;
        _journal = resultats[1] as ResultatJournalCaisse;
      });
    } on FinanceServiceException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'Impossible de charger la caisse : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  bool get _peutCloturer =>
      PermissionService.instance.peut(PageAccess.caisse, ActionAccess.modifier) ||
      PermissionService.instance.peut(PageAccess.caisse, ActionAccess.valider);

  /// Créer une dépense (= sortie de caisse) est un droit distinct de la
  /// clôture : un comptable peut ainsi décaisser sans clôturer.
  bool get _peutDecaisser =>
      PermissionService.instance.peut(PageAccess.depenses, ActionAccess.creer);

  Future<void> _ouvrirCloture() async {
    final bool? cloture = await context.push<bool>('/main/caisse/cloture');
    if (cloture == true) _charger();
  }

  Future<void> _ouvrirDecaissement() async {
    final bool enregistre = await afficherDecaissementCaisse(
      context,
      soldeActuel: _resume?.solde,
    );
    if (!enregistre) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Décaissement enregistré : le solde a été mis à jour.'),
      ),
    );
    await _charger();
  }

  /// 🔁 CORRECTIF 133 — ouvrir l'écran des dettes clients pour encaisser un
  /// règlement. Le montant réglé entre dans la caisse (`paiements_dette`).
  Future<void> _ouvrirDettes() async {
    await context.push('/main/dettes');
    if (!mounted) return;
    await _charger();
  }

  // ---------------------------------------------------------------------------
  // RENDU
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Caisse',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: <Widget>[
          if (_peutDecaisser)
            IconButton(
              tooltip: 'Décaissement',
              onPressed: _chargement ? null : _ouvrirDecaissement,
              icon: const Icon(Icons.south_east_rounded),
            ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _boutonsFlottants(),
      body: _construireCorps(),
    );
  }

  /// Un seul emplacement flottant, mais deux actions possibles : chaque
  /// bouton a son propre `heroTag` (sinon Flutter lève « multiple heroes
  /// share the same tag »).
  Widget? _boutonsFlottants() {
    if (_resume == null) return null;

    final List<Widget> boutons = <Widget>[
      if (_peutDecaisser)
        FloatingActionButton.extended(
          heroTag: 'caisse-fab-decaissement',
          onPressed: _ouvrirDecaissement,
          icon: const Icon(Icons.south_east_rounded),
          label: const Text('Décaissement'),
        ),
      if (_peutCloturer)
        FloatingActionButton.extended(
          heroTag: 'caisse-fab-cloture',
          onPressed: _ouvrirCloture,
          icon: const Icon(Icons.lock_clock_rounded),
          label: const Text('Clôture'),
        ),
    ];

    if (boutons.isEmpty) return null;
    if (boutons.length == 1) return boutons.first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (int i = 0; i < boutons.length; i++) ...<Widget>[
          boutons[i],
          if (i != boutons.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _construireCorps() {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.cloud_off_rounded,
                  size: 56, color: Theme.of(context).colorScheme.error),
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

    final ResumeCaisse resume = _resume ?? const ResumeCaisse();

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          _carteSolde(resume),
          const SizedBox(height: 16),
          _cartesJour(resume.jour),
          if (_peutDecaisser) ...<Widget>[
            const SizedBox(height: 12),
            _carteActions(),
          ],
          const SizedBox(height: 16),
          _carteParMode(resume),
          if (resume.derniereCloture != null) ...<Widget>[
            const SizedBox(height: 16),
            _carteDerniereCloture(resume.derniereCloture!),
          ],
          const SizedBox(height: 24),
          Text(
            'Historique',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _filtresHistorique(),
          const SizedBox(height: 8),
          ..._listeMouvements(),
          if (_journal != null) ...<Widget>[
            const SizedBox(height: 8),
            _piedTotaux(_journal!.totaux),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- actions

  /// Actions rapides : décaisser une dépense, ou consulter le détail des
  /// dépenses déjà enregistrées (écran « Dépenses » du module 10).
  Widget _carteActions() {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.flash_on_rounded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Actions rapides',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _ouvrirDecaissement,
                  icon: const Icon(Icons.south_east_rounded, size: 18),
                  label: const Text('Décaissement'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/main/depenses'),
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: const Text('Dépenses'),
                ),
              ),
            ],
          ),
          // 🔁 CORRECTIF 133 — ENCAISSER UNE DETTE DEPUIS LA CAISSE.
          //  Le client qui vient régulariser son crédit doit trouver l'action
          //  ici, au même endroit que le décaissement : c'est un mouvement de
          //  caisse comme un autre, et l'argent compté entre bien dans le solde.
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _ouvrirDettes,
              icon: const Icon(Icons.handshake_rounded, size: 18),
              label: const Text('Encaisser une dette'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Un décaissement est une sortie de caisse : il réduit le solde et '
            'le bénéfice net, et reste tracé dans le journal.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- solde

  Widget _carteSolde(ResumeCaisse resume) {
    final ThemeData theme = Theme.of(context);
    final double? solde = resume.solde;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[theme.colorScheme.primary, theme.colorScheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'SOLDE DE CAISSE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            solde == null ? '—' : formatMontant(solde),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            solde == null
                ? 'Montant réservé à la direction.'
                : 'Encaissements − décaissements depuis le début.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- jour

  Widget _cartesJour(ResumeCaisseJour jour) {
    final ThemeData theme = Theme.of(context);

    Widget miniCarte({
      required String titre,
      required String valeur,
      required String detail,
      required Color couleur,
      String? valeurSecondaire,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: couleur.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                titre,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                valeur,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: couleur,
                ),
              ),
              if (valeurSecondaire != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  valeurSecondaire,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: couleur.withValues(alpha: 0.85),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                detail,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          "Aujourd'hui",
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            miniCarte(
              titre: 'ENCAISSEMENTS',
              valeur: formatMontant(jour.encaissements),
              valeurSecondaire:
                  '${formatMontant(jour.encaissementsDettes)} de dettes',
              detail: '${jour.nbVentes} vente(s) · ${jour.nbPaiementsDettes} règlement(s)',
              couleur: Colors.green.shade700,
            ),
            const SizedBox(width: 12),
            miniCarte(
              titre: 'DÉCAISSEMENTS',
              valeur: jour.decaissements == null
                  ? '—'
                  : formatMontant(jour.decaissements!),
              detail: '${jour.nbDepenses} dépense(s)',
              couleur: Colors.red.shade700,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.balance_rounded,
                  size: 20, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Text(
                'Net du jour',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const Spacer(),
              Text(
                formatMontant(jour.net),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: jour.net >= 0
                      ? Colors.green.shade800
                      : Colors.red.shade800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- par mode

  Widget _carteParMode(ResumeCaisse resume) {
    final ThemeData theme = Theme.of(context);
    final List<MouvementParMode> modes = resume.parMode.values
        .where((MouvementParMode m) =>
            m.encaissements != 0 || m.decaissements != 0)
        .toList()
      ..sort((MouvementParMode a, MouvementParMode b) =>
          b.encaissements.compareTo(a.encaissements));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              "Détail par mode de paiement (aujourd'hui)",
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (modes.isEmpty)
              Text(
                'Aucun mouvement aujourd\'hui.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...modes.map((MouvementParMode mode) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          FinanceService.libelleMode(mode.mode),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        '+ ${formatMontant(mode.encaissements)}',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (mode.decaissements > 0) ...<Widget>[
                        const SizedBox(width: 10),
                        Text(
                          '− ${formatMontant(mode.decaissements)}',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------- dernière clôture

  Widget _carteDerniereCloture(ClotureCaisseInfo cloture) {
    final ThemeData theme = Theme.of(context);
    final double? ecart = cloture.ecart;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(Icons.lock_clock_rounded,
              color: theme.colorScheme.onSecondaryContainer),
        ),
        title: Text(
          'Dernière clôture — ${formatDate(cloture.dateCloture)}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Théorique : ${formatMontant(cloture.soldeTheorique)}'
          '${cloture.especeComptee == null ? '' : ' · Compté : ${formatMontant(cloture.especeComptee!)}'}',
        ),
        trailing: ecart == null
            ? null
            : Text(
                'Écart\n${ecart > 0 ? '+' : ''}${formatMontant(ecart)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color:
                      ecart == 0 ? theme.colorScheme.onSurfaceVariant : (ecart > 0 ? Colors.green.shade700 : Colors.red.shade700),
                ),
              ),
      ),
    );
  }

  // ------------------------------------------------------------- historique

  Widget _filtresHistorique() {
    final ThemeData theme = Theme.of(context);

    Widget chipPeriode(String code, String libelle) {
      return ChoiceChip(
        label: Text(libelle),
        selected: _periode == code,
        onSelected: (bool selection) {
          if (!selection) return;
          setState(() => _periode = code);
          _charger();
        },
      );
    }

    Widget chipSens(String? code, String libelle) {
      return ChoiceChip(
        label: Text(libelle),
        selected: _sens == code,
        onSelected: (bool selection) {
          if (!selection) return;
          setState(() => _sens = code);
          _charger();
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              chipPeriode('jour', "Aujourd'hui"),
              const SizedBox(width: 8),
              chipPeriode('semaine', '7 jours'),
              const SizedBox(width: 8),
              chipPeriode('mois', '30 jours'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              chipSens(null, 'Tout'),
              const SizedBox(width: 8),
              chipSens('entree', 'Entrées'),
              const SizedBox(width: 8),
              chipSens('sortie', 'Sorties'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Mode de paiement',
            prefixIcon: const Icon(Icons.credit_card_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _mode,
              isExpanded: true,
              isDense: true,
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Tous les modes'),
                ),
                ...FinanceService.modesPaiement.entries.map(
                  (MapEntry<String, String> e) => DropdownMenuItem<String?>(
                    value: e.key,
                    child: Text(e.value),
                  ),
                ),
              ],
              onChanged: (String? valeur) {
                setState(() => _mode = valeur);
                _charger();
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Les dépenses peuvent apparaître en mode « Espèces » (sorties).',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  List<Widget> _listeMouvements() {
    final ResultatJournalCaisse? journal = _journal;
    if (journal == null || journal.lignes.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Column(
              children: <Widget>[
                Icon(Icons.receipt_long_rounded,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 8),
                Text(
                  'Aucun mouvement sur la période.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return journal.lignes
        .map((MouvementCaisse mouvement) => _tuileMouvement(mouvement))
        .toList(growable: false);
  }

  Widget _tuileMouvement(MouvementCaisse mouvement) {
    final ThemeData theme = Theme.of(context);

    final IconData icone;
    switch (mouvement.type) {
      case TypeMouvementCaisse.vente:
        icone = Icons.point_of_sale_rounded;
        break;
      case TypeMouvementCaisse.venteAncienne:
        icone = Icons.history_rounded;
        break;
      case TypeMouvementCaisse.reglementDette:
        icone = Icons.handshake_rounded;
        break;
      case TypeMouvementCaisse.depense:
        icone = Icons.payments_rounded;
        break;
      case TypeMouvementCaisse.inconnu:
        icone = Icons.swap_horiz_rounded;
        break;
    }

    final Color couleur =
        mouvement.estEntree ? Colors.green.shade700 : Colors.red.shade700;

    final String sousTitre = <String>[
      formatDateHeure(mouvement.date),
      FinanceService.libelleMode(mouvement.mode),
      if (mouvement.reference != null) mouvement.reference!,
    ].join(' · ');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: couleur.withValues(alpha: 0.12),
          child: Icon(icone, color: couleur, size: 20),
        ),
        title: Text(
          mouvement.libelle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(sousTitre, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(
          '${mouvement.estEntree ? '+' : '−'} ${formatMontant(mouvement.montant)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: couleur,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _piedTotaux(TotauxJournalCaisse totaux) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '${totaux.nb} mouvement(s)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          '+ ${formatMontant(totaux.entrees)}  |  − ${formatMontant(totaux.sorties)}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
