// lib/pages/finance_abonnements_page.dart
//
// MODULE 27 — TABLEAU DE BORD FINANCE / SUPER ADMIN
//
// Une seule question, trois réponses à l'écran :
//   • COMBIEN A-T-ON FACTURÉ ?      → montant facturé (cumul)
//   • COMBIEN A-T-ON ENCAISSÉ ?     → encaissé cumulé + encaissé de la période
//   • COMBIEN RESTE-T-IL DÛ ?       → solde à recouvrer
//
// Puis deux onglets de contrôle :
//   • Entreprises : la situation de chaque boutique (échéance, dû, collaborateurs) ;
//   • Mobile Money : chaque transaction SerdiPay, avec pointage possible.
//
// ⚠️ Tous les montants viennent du serveur : cet écran ne calcule rien.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/services/finance_abonnements_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class FinanceAbonnementsPage extends StatefulWidget {
  const FinanceAbonnementsPage({super.key});

  @override
  State<FinanceAbonnementsPage> createState() => _FinanceAbonnementsPageState();
}

class _FinanceAbonnementsPageState extends State<FinanceAbonnementsPage>
    with SingleTickerProviderStateMixin {
  late TabController _onglets;

  bool _chargement = true;
  String? _erreur;

  ResumeFinance _resume = ResumeFinance.vide;
  List<LigneFinanceEntreprise> _entreprises = const <LigneFinanceEntreprise>[];
  List<TransactionSerdipay> _transactions = const <TransactionSerdipay>[];

  DateTime _debut = DateTime.now().subtract(const Duration(days: 30));
  DateTime _fin = DateTime.now();

  final TextEditingController _rechercheEntreprise = TextEditingController();
  final TextEditingController _rechercheTransaction = TextEditingController();
  String? _statutEntreprise;
  String? _statutTransaction;

  @override
  void initState() {
    super.initState();
    _onglets = TabController(length: 2, vsync: this);
    _charger();
  }

  @override
  void dispose() {
    _onglets.dispose();
    _rechercheEntreprise.dispose();
    _rechercheTransaction.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final ResumeFinance resume = await FinanceAbonnementsService.instance
          .resume(debut: _debut, fin: _fin);
      final List<LigneFinanceEntreprise> entreprises =
          await FinanceAbonnementsService.instance.entreprises(
        recherche: _rechercheEntreprise.text,
        statut: _statutEntreprise,
      );
      final List<TransactionSerdipay> transactions =
          await FinanceAbonnementsService.instance.transactions(
        recherche: _rechercheTransaction.text,
        statut: _statutTransaction,
      );
      if (!mounted) return;
      setState(() {
        _resume = resume;
        _entreprises = entreprises;
        _transactions = transactions;
        _chargement = false;
      });
    } on FinanceAbonnementsException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  Future<void> _choisirPeriode() async {
    final DateTimeRange? choix = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _debut, end: _fin),
      helpText: 'Période à analyser',
      saveText: 'Afficher',
    );
    if (choix == null || !mounted) return;
    setState(() {
      _debut = choix.start;
      _fin = choix.end;
    });
    await _charger();
  }

  Future<void> _basculerRapprochement(TransactionSerdipay t) async {
    final bool cible = !t.rapproche;
    try {
      await FinanceAbonnementsService.instance.rapprocher(t.id, cible);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cible
                ? 'Transaction pointée sur le relevé SerdiPay.'
                : 'Pointage annulé.',
          ),
        ),
      );
      await _charger();
    } on FinanceAbonnementsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppCouleurs.danger,
        ),
      );
    }
  }

  void _ouvrirDetail(LigneFinanceEntreprise ligne) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => _DetailEntreprise(ligne: ligne),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finances des abonnements'),
        bottom: TabBar(
          controller: _onglets,
          tabs: const <Widget>[
            Tab(text: 'Entreprises', icon: Icon(Icons.storefront_rounded)),
            Tab(text: 'Mobile Money', icon: Icon(Icons.smartphone_rounded)),
          ],
        ),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur(_erreur!)
              : Column(
                  children: <Widget>[
                    Expanded(
                      child: TabBarView(
                        controller: _onglets,
                        children: <Widget>[
                          _ongletEntreprises(),
                          _ongletTransactions(),
                        ],
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _charger,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Actualiser'),
      ),
    );
  }

  Widget _vueErreur(String message) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const SizedBox(height: 40),
        Icon(Icons.error_outline, size: 48, color: AppCouleurs.danger),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ONGLET 1 — ENTREPRISES
  // ---------------------------------------------------------------------------

  Widget _ongletEntreprises() {
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          _carteResume(),
          const SizedBox(height: 12),
          _cartePeriode(),
          const SizedBox(height: 12),
          _carteRepartition(),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Situation par entreprise',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${_entreprises.length}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _rechercheEntreprise,
            decoration: InputDecoration(
              hintText: 'Rechercher une boutique…',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onSubmitted: (_) => _charger(),
            textInputAction: TextInputAction.search,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              _filtre('Toutes', null, _statutEntreprise,
                  (String? v) => setState(() => _statutEntreprise = v)),
              _filtre('Actives', 'ACTIF', _statutEntreprise,
                  (String? v) => setState(() => _statutEntreprise = v)),
              _filtre('Expirées', 'EXPIRE', _statutEntreprise,
                  (String? v) => setState(() => _statutEntreprise = v)),
              _filtre('En attente', 'EN_ATTENTE_COMPLEMENT', _statutEntreprise,
                  (String? v) => setState(() => _statutEntreprise = v)),
            ],
          ),
          const SizedBox(height: 8),
          if (_entreprises.isEmpty)
            _vide('Aucune entreprise ne correspond à ce filtre.')
          else
            ..._entreprises.map(
              (LigneFinanceEntreprise l) => _tuileEntreprise(l),
            ),
        ],
      ),
    );
  }

  Widget _carteResume() {
    final bool toutPaye = _resume.soldeARecouvrer <= 0.009;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppDegrades.hero,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'VUE D\'ENSEMBLE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          _ligneMontant('Facturé', _resume.montantFacture, Colors.white),
          const SizedBox(height: 6),
          _ligneMontant(
            'Encaissé',
            _resume.montantEncaisseCumule,
            const Color(0xFF8BE9A6),
          ),
          const Divider(color: Colors.white24, height: 20),
          _ligneMontant(
            'Reste dû',
            _resume.soldeARecouvrer,
            toutPaye ? const Color(0xFF8BE9A6) : const Color(0xFFFFC9A3),
            gras: true,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _resume.tauxRecouvrement / 100,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF8BE9A6),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Taux de recouvrement : '
            '${_resume.tauxRecouvrement.toStringAsFixed(0)} %',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: <Widget>[
              _puce('Boutiques', '${_resume.entreprisesTotal}'),
              _puce('Actifs', '${_resume.abonnementsActifs}'),
              _puce('Expirés', '${_resume.abonnementsExpires}'),
              _puce('En attente', '${_resume.abonnementsEnAttente}'),
              _puce('Partiels', '${_resume.abonnementsPartiels}'),
            ],
          ),
          if (_resume.supplementsCollaborateurs > 0.009) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              'Dont suppléments collaborateurs : '
              '${formatMontant(_resume.supplementsCollaborateurs)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cartePeriode() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.date_range_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Du ${formatDate(_debut)} au ${formatDate(_fin)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: _choisirPeriode,
                  child: const Text('Changer'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_resume.paiementsPeriode} paiement(s) — '
              '${formatMontant(_resume.encaissePeriode)} encaissés',
              style: const TextStyle(fontSize: 13),
            ),
            if (_resume.parJour.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: _miniCourbe(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Courbe très simple : une barre par jour, proportionnelle au montant.
  Widget _miniCourbe() {
    final List<PointEncaissement> points = _resume.parJour;
    double max = 0;
    for (final PointEncaissement p in points) {
      if (p.montant > max) max = p.montant;
    }
    if (max <= 0) max = 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: points
          .map(
            (PointEncaissement p) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Tooltip(
                  message: '${formatDate(p.jour)} : '
                      '${formatMontant(p.montant)} (${p.nombre})',
                  child: Container(
                    height: 8 + (44 * (p.montant / max)),
                    decoration: BoxDecoration(
                      color: AppCouleurs.marineClair,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _carteRepartition() {
    final double total = _resume.encaissePeriode;
    if (total <= 0.009) return const SizedBox.shrink();

    final List<MapEntry<String, double>> parts = <MapEntry<String, double>>[
      MapEntry<String, double>('Espèces', _resume.encaisseEspeces),
      MapEntry<String, double>('Mobile Money', _resume.encaisseMobileMoney),
      MapEntry<String, double>('Carte', _resume.encaisseCarte),
      MapEntry<String, double>('Autres', _resume.encaisseAutres),
    ].where((MapEntry<String, double> e) => e.value > 0.009).toList();

    if (parts.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Répartition des encaissements',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            ...parts.map(
              (MapEntry<String, double> e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(e.key)),
                    Text(
                      formatMontant(e.value),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(e.value / total * 100).toStringAsFixed(0)} %',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tuileEntreprise(LigneFinanceEntreprise l) {
    final bool du = l.enRetard;
    final Color accent = du ? AppCouleurs.danger : AppCouleurs.succes;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        onTap: () => _ouvrirDetail(l),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.15),
          child: Icon(
            du ? Icons.error_outline_rounded : Icons.check_circle_outline,
            color: accent,
          ),
        ),
        title: Text(
          l.nom,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${formatMontant(l.montantEncaisse, devise: l.devise)} payés sur '
          '${formatMontant(l.montantFacture, devise: l.devise)}'
          '${du ? ' • reste ${formatMontant(l.soldeDu, devise: l.devise)}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              l.joursRestants == null ? '—' : '${l.joursRestants} j',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: (l.joursRestants ?? 99) <= 3
                    ? AppCouleurs.danger
                    : Colors.grey.shade700,
              ),
            ),
            if (l.serdipayEnAttente > 0)
              Text(
                '${l.serdipayEnAttente} en attente',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppCouleurs.alerte,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ONGLET 2 — MOBILE MONEY / SERDIPAY
  // ---------------------------------------------------------------------------

  Widget _ongletTransactions() {
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          TextField(
            controller: _rechercheTransaction,
            decoration: InputDecoration(
              hintText: 'Référence, téléphone, payeur, boutique…',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onSubmitted: (_) => _charger(),
            textInputAction: TextInputAction.search,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              _filtre('Toutes', null, _statutTransaction,
                  (String? v) => setState(() => _statutTransaction = v)),
              _filtre('Payées', 'paye', _statutTransaction,
                  (String? v) => setState(() => _statutTransaction = v)),
              _filtre('En attente', 'en_attente', _statutTransaction,
                  (String? v) => setState(() => _statutTransaction = v)),
              _filtre('Échouées', 'echoue', _statutTransaction,
                  (String? v) => setState(() => _statutTransaction = v)),
            ],
          ),
          const SizedBox(height: 12),
          if (_transactions.isEmpty)
            _vide('Aucune transaction pour ce filtre.')
          else
            ..._transactions.map(_tuileTransaction),
        ],
      ),
    );
  }

  Widget _tuileTransaction(TransactionSerdipay t) {
    final Color accent = t.estPayee
        ? AppCouleurs.succes
        : t.estEnAttente
            ? AppCouleurs.alerte
            : AppCouleurs.danger;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.smartphone_rounded, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${formatMontant(t.montant, devise: t.devise)}'
                    ' • ${t.libelleStatut}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.entreprise ?? 'Boutique inconnue',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    <String>[
                      if ((t.operateur ?? '').isNotEmpty) t.operateur!,
                      if ((t.telephone ?? '').isNotEmpty) t.telephone!,
                      if ((t.nomPayeur ?? '').isNotEmpty) t.nomPayeur!,
                    ].join(' • '),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    'Réf. ${t.reference ?? '—'}'
                    '${(t.referenceFournisseur ?? '').isNotEmpty ? ' / ${t.referenceFournisseur}' : ''}'
                    ' • ${formatDateHeure(t.date)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (t.frais != null || t.montantNet != null)
                    Text(
                      'Frais ${t.frais == null ? 'non communiqués' : formatMontant(t.frais!)}'
                      ' • Net ${t.montantNet == null ? 'non communiqué' : formatMontant(t.montantNet!)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  if ((t.motifEchec ?? '').isNotEmpty)
                    Text(
                      t.motifEchec!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppCouleurs.danger,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              children: <Widget>[
                IconButton(
                  tooltip: t.rapproche
                      ? 'Pointée sur le relevé (appuyer pour annuler)'
                      : 'Pointer sur le relevé SerdiPay',
                  onPressed: () => _basculerRapprochement(t),
                  icon: Icon(
                    t.rapproche
                        ? Icons.verified_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: t.rapproche
                        ? AppCouleurs.succes
                        : Colors.grey.shade400,
                  ),
                ),
                if (t.rapprocheLe != null)
                  Text(
                    formatDate(t.rapprocheLe),
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Petits widgets partagés
  // ---------------------------------------------------------------------------

  Widget _ligneMontant(
    String libelle,
    double montant,
    Color couleur, {
    bool gras = false,
  }) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            libelle,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        Text(
          formatMontant(montant),
          style: TextStyle(
            color: couleur,
            fontSize: gras ? 20 : 16,
            fontWeight: gras ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _puce(String libelle, String valeur) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$libelle ',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        Text(
          valeur,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _filtre(
    String libelle,
    String? valeur,
    String? courant,
    ValueChanged<String?> onChange,
  ) {
    final bool actif = courant == valeur;
    return FilterChip(
      label: Text(libelle),
      selected: actif,
      onSelected: (_) {
        onChange(valeur);
        _charger();
      },
    );
  }

  Widget _vide(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: <Widget>[
          Icon(Icons.inbox_rounded, size: 44, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/// Détail financier d'une entreprise (feuille du bas).
class _DetailEntreprise extends StatelessWidget {
  const _DetailEntreprise({required this.ligne});

  final LigneFinanceEntreprise ligne;

  @override
  Widget build(BuildContext context) {
    final String devise = ligne.devise;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            ligne.nom,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Statut : ${ligne.statut.isEmpty ? '—' : ligne.statut}',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          _ligne(context, 'Montant facturé',
              formatMontant(ligne.montantFacture, devise: devise)),
          _ligne(context, 'Montant encaissé',
              formatMontant(ligne.montantEncaisse, devise: devise)),
          _ligne(context, 'Reste dû',
              formatMontant(ligne.soldeDu, devise: devise),
              accent: ligne.enRetard),
          _ligne(context, 'Supplément collaborateurs',
              formatMontant(ligne.supplementCollaborateurs, devise: devise)),
          _ligne(context, 'Collaborateurs', '${ligne.collaborateurs}'),
          _ligne(context, 'Échéance', formatDate(ligne.echeance)),
          _ligne(context, 'Jours restants',
              ligne.joursRestants == null ? '—' : '${ligne.joursRestants}'),
          _ligne(context, 'Dernier paiement', formatDate(ligne.dernierPaiement)),
          _ligne(context, 'Nombre de paiements', '${ligne.totalPaiements}'),
          if (ligne.serdipayEnAttente > 0)
            _ligne(context, 'Mobile Money en attente',
                '${ligne.serdipayEnAttente}'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: '${ligne.nom} — ${ligne.entrepriseId}'),
                );
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copier l\'identifiant'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligne(
    BuildContext context,
    String libelle,
    String valeur, {
    bool accent = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(libelle)),
          Text(
            valeur,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: accent ? AppCouleurs.danger : null,
            ),
          ),
        ],
      ),
    );
  }
}
