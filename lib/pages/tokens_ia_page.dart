// lib/pages/tokens_ia_page.dart
//
// MODULE 13 bis — ÉCRAN « GESTION DES TOKENS IA » (Super Admin).
//
//  Répond à trois questions :
//    1. COMBIEN ÇA COÛTE — tokens réellement consommés chez DeepSeek, coût
//       constaté en CDF, et solde du compte (combien de questions restent) ;
//    2. COMBIEN ÇA RAPPORTE — montant facturé, bénéfice et coefficient de
//       marge constaté, comparé à l'objectif (×16 = 2 $ de coût → 32 $ de
//       recettes, soit 30 $ de bénéfice) ;
//    3. QUI CONSOMME — répartition par entreprise + journal détaillé des
//       appels, et distribution manuelle de quotas (geste commercial tracé).
//
//  Toutes les données viennent de RPC serveur (`rpc_ia_tokens_tableau_bord`,
//  `rpc_ia_usage_lister`, `rpc_ia_usage_par_entreprise`) : aucun calcul
//  financier n'est fait côté application, pour qu'un relevé ne puisse pas
//  être falsifié par le client.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/agent_ia.dart';
import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/services/agent_service.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Écran de pilotage des tokens de l'assistant IA.
class TokensIaPage extends StatefulWidget {
  const TokensIaPage({super.key});

  @override
  State<TokensIaPage> createState() => _TokensIaPageState();
}

class _TokensIaPageState extends State<TokensIaPage> {
  final AgentService _service = AgentService.instance;

  /// Fenêtre d'analyse choisie (7, 30 ou 90 jours).
  int _jours = 30;

  TokensIaTableauBord? _tableau;
  List<RepartitionIaEntreprise> _repartition = const <RepartitionIaEntreprise>[];
  List<LigneUsageIa> _usage = const <LigneUsageIa>[];

  bool _chargement = true;
  bool _chargementPlus = false;
  String? _erreur;

  static const int _taillePage = 50;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final List<Object> resultats = await Future.wait(<Future<Object>>[
        _service.tokensTableauBord(jours: _jours),
        _service.usageParEntreprise(jours: _jours),
        _service.usageLister(limite: _taillePage),
      ]);

      if (!mounted) return;
      setState(() {
        _tableau = resultats[0] as TokensIaTableauBord;
        _repartition = resultats[1] as List<RepartitionIaEntreprise>;
        _usage = resultats[2] as List<LigneUsageIa>;
        _chargement = false;
      });
    } on AgentServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e) {
      debugPrint('TokensIaPage._charger : $e');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger le tableau de bord des tokens.';
        _chargement = false;
      });
    }
  }

  /// Charge la page suivante du journal des appels.
  Future<void> _chargerPlus() async {
    if (_chargementPlus) return;
    setState(() => _chargementPlus = true);

    try {
      final List<LigneUsageIa> suite = await _service.usageLister(
        limite: _taillePage,
        decalage: _usage.length,
      );
      if (!mounted) return;
      setState(() {
        // `usageLister` peut renvoyer des lignes déjà présentes si de nouveaux
        // appels sont arrivés entre-temps : on déduplique par identifiant.
        final Set<int> connus = _usage.map((LigneUsageIa l) => l.id).toSet();
        _usage = <LigneUsageIa>[
          ..._usage,
          ...suite.where((LigneUsageIa l) => connus.add(l.id)),
        ];
        _chargementPlus = false;
      });
    } catch (e) {
      debugPrint('TokensIaPage._chargerPlus : $e');
      if (!mounted) return;
      setState(() => _chargementPlus = false);
      _snack('Chargement impossible : vérifiez votre réseau.', erreur: true);
    }
  }

  void _snack(String message, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: erreur ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _rechargerCredit() async {
    final TextEditingController montant =
        TextEditingController(text: '2');
    final TextEditingController taux = TextEditingController(
      text: (_tableau?.config.tauxUsdCdf ?? 2800).toStringAsFixed(0),
    );
    final TextEditingController note = TextEditingController();

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Recharger le crédit DeepSeek'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Enregistrez ici ce que vous venez de payer sur la plateforme '
                'DeepSeek. Le solde suivi est utilisé pour estimer le nombre de '
                'questions restantes.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: montant,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Montant payé (USD)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: taux,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Change suivi (CDF pour 1 USD)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Note (facultatif)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (valide != true) {
      montant.dispose();
      taux.dispose();
      note.dispose();
      return;
    }

    final double? montantUsd = double.tryParse(montant.text.trim());
    final double? tauxCdf = double.tryParse(taux.text.trim());
    final String texteNote = note.text.trim();
    montant.dispose();
    taux.dispose();
    note.dispose();

    if (montantUsd == null || montantUsd <= 0) {
      _snack('Montant invalide : indiquez un montant en dollars positif.', erreur: true);
      return;
    }
    if (tauxCdf == null || tauxCdf <= 0) {
      _snack('Change invalide : indiquez un taux positif.', erreur: true);
      return;
    }

    try {
      final Map<String, dynamic> resultat = await _service.rechargerCredit(
        montantUsd: montantUsd,
        tauxUsdCdf: tauxCdf,
        note: texteNote.isEmpty ? null : texteNote,
      );
      if (!mounted) return;
      _snack(
        'Recharge enregistrée : '
        '${formatMontant((resultat['montant_usd'] as num?)?.toDouble() ?? 0, devise: 'USD')} '
        '→ solde ${formatMontant((resultat['solde_usd'] as num?)?.toDouble() ?? 0, devise: 'USD')}.',
      );
      await _charger();
    } on AgentServiceException catch (e) {
      if (!mounted) return;
      _snack(e.message, erreur: true);
    } catch (e) {
      debugPrint('TokensIaPage._rechargerCredit : $e');
      if (!mounted) return;
      _snack('Recharge impossible : vérifiez votre réseau.', erreur: true);
    }
  }

  Future<void> _distribuerQuotas() async {
    final List<Entreprise> entreprises = await _chargerEntreprises();
    if (!mounted) return;
    if (entreprises.isEmpty) {
      _snack('Aucune entreprise disponible pour une distribution.', erreur: true);
      return;
    }

    final TextEditingController quotas = TextEditingController(text: '10');
    final TextEditingController motif = TextEditingController();
    String? entrepriseId;

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter maj) => AlertDialog(
          title: const Text('Distribuer des quotas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Offrez des quotas à une entreprise (geste commercial, '
                  'compensation d\'incident…). L\'opération est tracée et '
                  'journalisée.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: entrepriseId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Entreprise bénéficiaire',
                    border: OutlineInputBorder(),
                  ),
                  items: entreprises
                      .map(
                        (Entreprise e) => DropdownMenuItem<String>(
                          value: e.id,
                          child: Text(e.nom, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (String? valeur) => maj(() => entrepriseId = valeur),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quotas,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de quotas',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: motif,
                  decoration: const InputDecoration(
                    labelText: 'Motif (obligatoire, 3 caractères minimum)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Distribuer'),
            ),
          ],
        ),
      ),
    );

    final int? nb = int.tryParse(quotas.text.trim());
    final String texteMotif = motif.text.trim();
    quotas.dispose();
    motif.dispose();

    if (valide != true) return;
    if (entrepriseId == null) {
      _snack('Choisissez une entreprise.', erreur: true);
      return;
    }
    if (nb == null || nb < 1) {
      _snack('Nombre de quotas invalide.', erreur: true);
      return;
    }
    if (texteMotif.length < 3) {
      _snack('Indiquez le motif (3 caractères minimum).', erreur: true);
      return;
    }

    try {
      final Map<String, dynamic> resultat = await _service.distribuerQuotas(
        entrepriseId: entrepriseId!,
        quotas: nb,
        motif: texteMotif,
      );
      if (!mounted) return;
      _snack(
        '$nb quota(s) distribués — solde du pool : '
        '${resultat['solde_pool'] ?? 0} '
        '(valeur ${formatMontant((resultat['montant_cdf'] as num?)?.toDouble() ?? 0)}).',
      );
      await _charger();
    } on AgentServiceException catch (e) {
      if (!mounted) return;
      _snack(e.message, erreur: true);
    } catch (e) {
      debugPrint('TokensIaPage._distribuerQuotas : $e');
      if (!mounted) return;
      _snack('Distribution impossible : vérifiez votre réseau.', erreur: true);
    }
  }

  Future<List<Entreprise>> _chargerEntreprises() async {
    try {
      return await EntrepriseService.instance.getEntreprises();
    } catch (e) {
      debugPrint('TokensIaPage._chargerEntreprises : $e');
      return const <Entreprise>[];
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.estSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tokens IA')),
        body: const AccesRefuse(
          message: 'Cet écran est réservé au Super Admin.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tokens IA',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Recharger le crédit DeepSeek',
            onPressed: _chargement ? null : _rechargerCredit,
            icon: const Icon(Icons.add_card_rounded),
          ),
          IconButton(
            tooltip: 'Distribuer des quotas',
            onPressed: _chargement ? null : _distribuerQuotas,
            icon: const Icon(Icons.card_giftcard_rounded),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _chargement ? null : _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _construireCorps(),
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
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _charger,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final TokensIaTableauBord? t = _tableau;
    if (t == null) {
      return const Center(child: Text('Aucune donnée.'));
    }

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: <Widget>[
          if (t.alerte) _bandeauAlerte(t),
          _cartesFinancieres(t),
          const SizedBox(height: 16),
          _carteSolde(t),
          const SizedBox(height: 16),
          _carteFormule(t),
          const SizedBox(height: 16),
          _carteTokens(t),
          const SizedBox(height: 16),
          _sectionsPeriode(t),
          const SizedBox(height: 16),
          _carteRepartition(),
          const SizedBox(height: 16),
          _carteJournal(),
        ],
      ),
    );
  }

  // — Bandeau d'alerte de solde ————————————————————————————————————————

  Widget _bandeauAlerte(TokensIaTableauBord t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Solde DeepSeek faible : '
              '${formatMontant(t.soldeDeepseekUsd, devise: 'USD')} '
              '(seuil d\'alerte ${formatMontant(t.config.alerteSoldeUsd, devise: 'USD')}). '
              'Rechargez pour éviter une interruption de l\'assistant.',
              style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900),
            ),
          ),
          TextButton(
            onPressed: _rechargerCredit,
            child: const Text('Recharger'),
          ),
        ],
      ),
    );
  }

  // — Cartes financières ——————————————————————————————————————————————

  Widget _cartesFinancieres(TokensIaTableauBord t) {
    final bool objectifAtteint =
        t.coefficient > 0 && t.coefficient >= t.config.tauxMarge;

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _kpi(
                titre: 'Coût DeepSeek',
                valeur: formatMontant(t.coutCdf),
                icone: Icons.local_fire_department_rounded,
                couleur: Colors.red.shade600,
                sousTitre: '${t.appels} appel(s)',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _kpi(
                titre: 'Facturé',
                valeur: formatMontant(t.factureCdf),
                icone: Icons.receipt_long_rounded,
                couleur: Colors.blue.shade700,
                sousTitre: '${t.quotasDebites} quota(s)',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _kpi(
                titre: 'Bénéfice',
                valeur: formatMontant(t.margeCdf),
                icone: Icons.trending_up_rounded,
                couleur: Colors.green.shade700,
                sousTitre: 'objectif ×${_nb(t.config.tauxMarge)}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _kpi(
                titre: 'Coefficient',
                valeur: t.coefficient > 0 ? '×${t.coefficient}' : '—',
                icone: objectifAtteint
                    ? Icons.verified_rounded
                    : Icons.speed_rounded,
                couleur: objectifAtteint
                    ? Colors.green.shade700
                    : Colors.orange.shade700,
                sousTitre: objectifAtteint ? 'objectif atteint' : 'à surveiller',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // — Solde DeepSeek ————————————————————————————————————————————————

  Widget _carteSolde(TokensIaTableauBord t) {
    final double progression =
        (t.consommationPct / 100).clamp(0.0, 1.0).toDouble();

    return _section(
      titre: 'Compte DeepSeek',
      icone: Icons.account_balance_wallet_rounded,
      enfants: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _info(
                'Solde restant',
                formatMontant(t.soldeDeepseekUsd, devise: 'USD'),
                gras: true,
              ),
            ),
            Expanded(
              child: _info('Équivalent', formatMontant(t.soldeCdf)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progression,
            minHeight: 10,
            backgroundColor: Colors.black12,
            color: t.alerte ? Colors.orange.shade700 : Colors.green.shade600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${t.consommationPct.toStringAsFixed(1)} % du crédit suivi déjà consommé.',
          style: const TextStyle(fontSize: 11.5),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.lightbulb_rounded, size: 20, color: Colors.green.shade800),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Avec le solde actuel et un coût moyen de '
                  '${formatMontant(t.coutMoyenQuestionCdf)} par question, il '
                  'reste environ ${_nb(t.questionsRestantes.toDouble())} question(s) '
                  '— soit une marge potentielle de '
                  '${formatMontant(t.margePotentielleCdf)}.',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _rechargerCredit,
            icon: const Icon(Icons.add_card_rounded),
            label: const Text('Enregistrer une recharge'),
          ),
        ),
      ],
    );
  }

  // — Formule appliquée ——————————————————————————————————————————————

  Widget _carteFormule(TokensIaTableauBord t) {
    final AgentIaConfig c = t.config;

    return _section(
      titre: 'Formule appliquée',
      icone: Icons.calculate_rounded,
      enfants: <Widget>[
        _ligne('Taille d\'un quota', '${c.caracteresParQuota} caractères'),
        _ligne('Prix d\'un quota', formatMontant(c.tarifParQuota)),
        _ligne('Prix d\'un caractère', formatMontant(c.prixParCaractere)),
        _ligne('Pack de 10 quotas', formatMontant(c.prixPack10Quotas)),
        _ligne('Quotas offerts', '${c.quotasOffertsInscription} par entreprise'),
        const Divider(height: 22),
        _ligne(
          'Coût moyen constaté',
          '${formatMontant(t.coutMoyenQuestionCdf)} / question',
        ),
        _ligne(
          'Coefficient constaté',
          t.coefficient > 0 ? '×${t.coefficient}' : '— (aucun appel)',
          couleur: t.coefficient >= c.tauxMarge
              ? Colors.green.shade700
              : Colors.orange.shade800,
        ),
        _ligne('Coefficient cible', '×${_nb(c.tauxMarge)}'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Objectif : ${formatMontant(c.tauxUsdCdf * 2, devise: 'CDF')} de crédit '
            'doit produire ${formatMontant(c.tauxUsdCdf * 32, devise: 'CDF')} de recettes, '
            'soit ${formatMontant(c.tauxUsdCdf * 30, devise: 'CDF')} de bénéfice '
            '(coefficient ×${_nb(c.tauxMarge)}).\n'
            'Exemple : une réponse de ${c.caracteresParQuota} caractères = 1 quota '
            '= ${formatMontant(c.tarifParQuota)}.',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  // — Détail des tokens ——————————————————————————————————————————————

  Widget _carteTokens(TokensIaTableauBord t) {
    return _section(
      titre: 'Consommation de tokens',
      icone: Icons.data_usage_rounded,
      enfants: <Widget>[
        _ligne('Tokens d\'entrée', _nb(t.tokensEntree.toDouble())),
        _ligne('Tokens d\'entrée (cache)', _nb(t.tokensCache.toDouble())),
        _ligne('Tokens de sortie', _nb(t.tokensSortie.toDouble())),
        _ligne('Total', _nb(t.tokensTotal.toDouble()), gras: true),
        const Divider(height: 22),
        _ligne('Taux de cache', '${(t.tauxCache * 100).toStringAsFixed(1)} %'),
        const SizedBox(height: 8),
        const Text(
          'Le cache DeepSeek facture les tokens d\'entrée répétés environ '
          '50 fois moins cher. Un taux élevé = un coût plus bas.',
          style: TextStyle(fontSize: 11.5),
        ),
      ],
    );
  }

  // — Période ————————————————————————————————————————————————————————

  Widget _sectionsPeriode(TokensIaTableauBord t) {
    return _section(
      titre: 'Période',
      icone: Icons.calendar_month_rounded,
      enfants: <Widget>[
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment<int>(value: 7, label: Text('7 j')),
            ButtonSegment<int>(value: 30, label: Text('30 j')),
            ButtonSegment<int>(value: 90, label: Text('90 j')),
          ],
          selected: <int>{_jours},
          onSelectionChanged: (Set<int> choix) {
            setState(() => _jours = choix.first);
            _charger();
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: _info('Aujourd\'hui', formatMontant(t.jourCoutCdf)),
            ),
            Expanded(
              child: _info('$_jours jours', formatMontant(t.periodeCoutCdf)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _info('Facturé (période)', formatMontant(t.periodeFactureCdf)),
            ),
            Expanded(
              child: _info('Marge (période)', formatMontant(t.periodeMargeCdf)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ligne('Appels sur la période', '${t.periodeAppels}'),
        _ligne('Quotas facturés', '${t.periodeQuotas}'),
      ],
    );
  }

  // — Répartition par entreprise ————————————————————————————————————

  Widget _carteRepartition() {
    return _section(
      titre: 'Qui consomme ?',
      icone: Icons.pie_chart_rounded,
      enfants: <Widget>[
        if (_repartition.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Aucune consommation sur la période choisie.',
              style: TextStyle(fontSize: 12.5),
            ),
          )
        else
          ..._repartition.map(
            (RepartitionIaEntreprise r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          r.entreprise,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${r.appels} appel(s) · ${r.quotasDebites} quota(s) · '
                          'coût ${formatMontant(r.coutCdf)}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        formatMontant(r.factureCdf),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'marge ${formatMontant(r.margeCdf)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: r.margeCdf >= 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _distribuerQuotas,
            icon: const Icon(Icons.card_giftcard_rounded),
            label: const Text('Distribuer des quotas'),
          ),
        ),
      ],
    );
  }

  // — Journal des appels ——————————————————————————————————————————————

  Widget _carteJournal() {
    return _section(
      titre: 'Journal des appels IA',
      icone: Icons.receipt_long_rounded,
      enfants: <Widget>[
        if (_usage.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Aucun appel enregistré. Le journal se remplit dès la première '
              'question posée à l\'assistant.',
              style: TextStyle(fontSize: 12.5),
            ),
          )
        else
          ..._usage.map(_ligneJournal),
        if (_usage.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _chargementPlus ? null : _chargerPlus,
              icon: _chargementPlus
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: const Text('Charger plus'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ligneJournal(LigneUsageIa l) {
    final bool offert = l.montantCdf <= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: offert ? Colors.grey.shade200 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              offert ? Icons.card_giftcard_rounded : Icons.smart_toy_rounded,
              size: 16,
              color: offert ? Colors.grey.shade700 : Colors.blue.shade800,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.utilisateur?.isNotEmpty == true
                      ? l.utilisateur!
                      : (offert ? 'API Biashara Group' : 'Utilisateur inconnu'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${_nb(l.tokensTotal.toDouble())} tokens '
                  '(${_nb(l.tokensEntree.toDouble())} entrée · '
                  '${_nb(l.tokensCache.toDouble())} cache · '
                  '${_nb(l.tokensSortie.toDouble())} sortie)',
                  style: const TextStyle(fontSize: 11.5),
                ),
                Text(
                  formatDateHeure(l.createdAt),
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                offert ? 'offert' : formatMontant(l.montantCdf),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
              Text(
                'coût ${formatMontant(l.coutCdf)}',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              Text(
                l.margeCdf >= 0
                    ? 'marge +${formatMontant(l.margeCdf)}'
                    : 'perte ${formatMontant(l.margeCdf.abs())}',
                style: TextStyle(
                  fontSize: 11,
                  color: l.margeCdf >= 0
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // — Briques réutilisables ——————————————————————————————————————————

  Widget _section({
    required String titre,
    required IconData icone,
    required List<Widget> enfants,
  }) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icone, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                titre,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...enfants,
        ],
      ),
    );
  }

  Widget _kpi({
    required String titre,
    required String valeur,
    required IconData icone,
    required Color couleur,
    String? sousTitre,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: couleur.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icone, size: 18, color: couleur),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  titre,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: couleur,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valeur,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
          if (sousTitre != null)
            Text(
              sousTitre,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _info(String label, String valeur, {bool gras = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 11.5)),
        const SizedBox(height: 2),
        Text(
          valeur,
          style: TextStyle(
            fontSize: 15,
            fontWeight: gras ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _ligne(String label, String valeur, {Color? couleur, bool gras = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: gras ? FontWeight.w900 : FontWeight.w700,
                color: couleur,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Nombre lisible : séparateur de milliers, sans décimale inutile.
  String _nb(double valeur) => formatMontant(valeur, devise: '');
}
