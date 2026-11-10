// lib/pages/activations_finance_page.dart
//
// MODULE 14 — ÉCRAN « ACTIVATIONS & PAIEMENTS » (FINANCE PLATEFORME).
//
// Deuxième validation du workflow d'activation : la finance contrôle le
// paiement réellement reçu, l'enregistre (montant, mode, référence) puis
// l'activation est AUTOMATIQUE :
//
//   • paiement total   → compte ACTIF, 30 jours immédiats ;
//   • paiement partiel → 7 jours d'essai + solde à régler avant l'échéance ;
//   • solde impayé à l'échéance → restriction automatique (les données sont
//     conservées) ; la régularisation réactive le compte (30 jours).
//
// Les dossiers « Restreints » apparaissent ici pour permettre la
// régularisation (paiement du solde).
//
// 🔒 Seule la finance (ou le Super Admin) peut valider l'activation finale :
// le gestionnaire des comptes ne fait que vérifier le dossier. Les deux RPC
// revérifient le rôle côté serveur, et chaque décision est journalisée.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/activation.dart';
import 'package:biashara_yangu/models/paiement_laperle.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/activation_service.dart';
import 'package:biashara_yangu/services/paiement_platforme_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/codes_validation_finance.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Filtres proposés (valeurs d'étape SQL — `null` = tous).
enum _FiltreFinance {
  aValider('verifie', 'À valider'),
  restreints('restreint', 'Restreints (à régulariser)'),
  actifs('actif', 'Actifs'),
  tous(null, 'Tous');

  const _FiltreFinance(this.etape, this.libelle);

  final String? etape;
  final String libelle;
}

class ActivationsFinancePage extends StatefulWidget {
  const ActivationsFinancePage({super.key});

  @override
  State<ActivationsFinancePage> createState() =>
      _ActivationsFinancePageState();
}

class _ActivationsFinancePageState extends State<ActivationsFinancePage> {
  final TextEditingController _recherche = TextEditingController();

  _FiltreFinance _filtre = _FiltreFinance.aValider;
  List<DossierActivation> _dossiers = const <DossierActivation>[];
  bool _chargement = true;
  String? _erreur;
  String? _enCours;

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
      final List<DossierActivation> dossiers =
          await ActivationService.instance.lister(etape: _filtre.etape);
      if (!mounted) return;
      setState(() {
        _dossiers = dossiers;
        _chargement = false;
      });
    } on ActivationServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger les dossiers : $e';
        _chargement = false;
      });
    }
  }

  List<DossierActivation> get _visibles {
    final String recherche = _recherche.text.trim().toLowerCase();
    if (recherche.isEmpty) return _dossiers;

    return _dossiers.where((DossierActivation d) {
      return d.nom.toLowerCase().contains(recherche) ||
          (d.responsable ?? '').toLowerCase().contains(recherche) ||
          (d.contact ?? '').toLowerCase().contains(recherche);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  /// Ouvre le formulaire de validation du paiement puis appelle la RPC.
  Future<void> _validerPaiement(DossierActivation dossier) async {
    final _ResultatPaiement? paiement = await showDialog<_ResultatPaiement>(
      context: context,
      builder: (BuildContext context) => _DialoguePaiement(dossier: dossier),
    );

    if (paiement == null) return;

    setState(() => _enCours = dossier.id);

    try {
      // ⚙️ MODULE 21 — Le MONTANT TOTAL DÛ est enregistré AVANT le paiement :
      // le moteur d'abonnement (et la passerelle SerdiPay) calculent le solde
      // à partir de lui.
      final double? totalSaisi = paiement.montantTotalDu;
      if (totalSaisi != null &&
          totalSaisi > 0 &&
          totalSaisi != dossier.montantTotalDu) {
        await ActivationService.instance.definirMontantTotal(
          entrepriseId: dossier.id,
          montant: totalSaisi,
          note: paiement.note,
        );
      }

      // 💳 CORRECTIF 134 — SERDIPAY UNIQUEMENT, MÊME POUR LE SUPER ADMIN.
      //
      //  Aucun rôle (finance, super administrateur, agent) ne peut plus
      //  encaisser un abonnement ou des frais d'installation en espèces : le
      //  client paie depuis SON téléphone, et l'abonnement n'est crédité
      //  qu'après confirmation réelle de la transaction.
      if (!PaiementPlatformeService.estMobileMoney(paiement.modePaiement)) {
        if (!mounted) return;
        setState(() => _enCours = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(PaiementPlatformeService.messageSerdipayUniquement),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }

      if (!mounted) return;
      final bool paye = await PaiementPlatformeService.payerParMobileMoney(
        context,
        entrepriseId: dossier.id,
        libelleEntreprise: dossier.nom,
      );
      if (!mounted) return;
      setState(() => _enCours = null);
      if (paye) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Paiement Mobile Money confirmé par SerdiPay : abonnement '
              'crédité.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Paiement Mobile Money non confirmé : aucun abonnement n\'a '
              'été crédité.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      await _charger();
      return;
    } on ActivationServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opération impossible : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _enCours = null);
    }
  }

  /// Rejette le paiement annoncé (le dossier reste à son étape).
  Future<void> _rejeterPaiement(DossierActivation dossier) async {
    final TextEditingController motif = TextEditingController();

    final String? note = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _DialogueMotifFinance(
        titre: 'Paiement non confirmé ?',
        message:
            'Le paiement annoncé pour « ${dossier.nom} » sera rejeté. Le '
            'compte reste en attente ; le motif est enregistré dans le '
            "journal d'audit.",
        controleur: motif,
      ),
    );

    motif.dispose();
    if (note == null) return;

    setState(() => _enCours = dossier.id);

    try {
      await ActivationService.instance.validerFinance(
        entrepriseId: dossier.id,
        approuver: false,
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Paiement de « ${dossier.nom} » rejeté (motif enregistré).'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      await _charger();
    } on ActivationServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _enCours = null);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.peut(
        PageAccess.activationsFinance, ActionAccess.voir)) {
      return const AccesRefuse(
        message: 'Seule la finance plateforme (ou le Super Admin) peut '
            'valider les paiements et activer les comptes.',
      );
    }

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

    final List<DossierActivation> visibles = _visibles;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _recherche,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Rechercher (nom, responsable, email)…',
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
              ..._FiltreFinance.values.map(
                (_FiltreFinance filtre) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filtre.libelle),
                    selected: _filtre == filtre,
                    onSelected: (_) {
                      setState(() => _filtre = filtre);
                      _charger();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // 🔐 CORRECTIF 69 — Codes de validation des agents.
        // Deux choses à surveiller ici : les demandes de code en attente (la
        // Finance doit le dicter à l'agent) et les comptes vérifiés SANS code
        // — ceux que l'agent a pu valider après l'expiration des 5 minutes et
        // que la Finance doit donc confirmer. Ce bandeau se réduit à une ligne
        // quand il n'y a rien à faire : il ne prend pas la place des paiements.
        const CodesValidationFinanceSection(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _charger,
            child: visibles.isEmpty
                ? ListView(
                    children: <Widget>[
                      const SizedBox(height: 80),
                      Center(
                        child: Column(
                          children: <Widget>[
                            Icon(Icons.inbox_rounded,
                                size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              _filtre == _FiltreFinance.aValider
                                  ? 'Aucun dossier vérifié en attente de '
                                      'validation finance.'
                                  : 'Aucun dossier à afficher.',
                              style: TextStyle(color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visibles.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _carteDossier(context, visibles[index]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _carteDossier(BuildContext context, DossierActivation dossier) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool enCours = _enCours == dossier.id;
    final bool peutValider = PermissionService.instance.peut(
        PageAccess.activationsFinance, ActionAccess.valider);
    // Actionnable : dossier vérifié (1ʳᵉ validation faite), compte restreint
    // (régularisation du solde) ou compte actif (complément d'avance).
    final bool actionnable = dossier.etape == EtapeActivation.verifie ||
        dossier.etape == EtapeActivation.restreint ||
        dossier.etape == EtapeActivation.actif;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(Icons.account_balance_rounded,
                      color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        dossier.nom,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        <String>[
                          if ((dossier.ville ?? '').isNotEmpty) dossier.ville!,
                          if ((dossier.activite ?? '').isNotEmpty)
                            dossier.activite!,
                        ].join(' • '),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                _chipEtape(dossier.etape),
              ],
            ),
            const SizedBox(height: 10),
            _ligneInfo(
              Icons.payments_outlined,
              'Total : ${dossier.montantTotalDu.toStringAsFixed(0)} CDF'
              '  •  Payé : ${dossier.montantDejaPaye.toStringAsFixed(0)}'
              '  •  Solde : ${dossier.soldeRestant.toStringAsFixed(0)} CDF',
              couleur: dossier.estSolde ? Colors.green.shade700 : null,
            ),
            if ((dossier.responsable ?? '').isNotEmpty ||
                (dossier.contact ?? '').isNotEmpty ||
                (dossier.telephone ?? '').isNotEmpty)
              _ligneInfo(
                Icons.person_outline_rounded,
                <String>[
                  if ((dossier.responsable ?? '').isNotEmpty)
                    dossier.responsable!,
                  if ((dossier.contact ?? '').isNotEmpty) dossier.contact!,
                  if ((dossier.telephone ?? '').isNotEmpty)
                    dossier.telephone!,
                ].join('  •  '),
              ),
            if (dossier.verifieLe != null)
              _ligneInfo(
                Icons.verified_outlined,
                'Vérifié par le gestionnaire le ${_date(dossier.verifieLe!)}',
              ),
            if (dossier.dateExpiration != null &&
                dossier.etape == EtapeActivation.actif)
              _ligneInfo(
                Icons.event_available_outlined,
                'Expire le ${_date(dossier.dateExpiration!)}',
              ),
            if ((dossier.dernierMotif ?? '').isNotEmpty)
              _ligneInfo(
                Icons.info_outline_rounded,
                'Dernier motif : ${dossier.dernierMotif!}',
                couleur: Colors.red.shade700,
              ),
            if (actionnable && peutValider) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: enCours ? null : () => _rejeterPaiement(dossier),
                    icon: const Icon(Icons.cancel_outlined,
                        color: Colors.red),
                    label: const Text('Rejeter',
                        style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: enCours ? null : () => _validerPaiement(dossier),
                    icon: enCours
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.task_alt_rounded),
                    label: const Text('Valider le paiement'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chipEtape(EtapeActivation etape) {
    late final Color couleur;
    switch (etape) {
      case EtapeActivation.enAttenteVerification:
        couleur = Colors.orange.shade700;
      case EtapeActivation.verifie:
        couleur = Colors.blue.shade700;
      case EtapeActivation.actif:
        couleur = Colors.green.shade700;
      case EtapeActivation.restreint:
        couleur = Colors.deepOrange.shade800;
      case EtapeActivation.rejete:
        couleur = Colors.red.shade700;
      case EtapeActivation.aucune:
        couleur = Colors.grey.shade600;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: couleur.withValues(alpha: 0.5)),
      ),
      child: Text(
        etape.libelle,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: couleur),
      ),
    );
  }

  Widget _ligneInfo(IconData icone, String texte, {Color? couleur}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, size: 15, color: couleur ?? Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texte,
              style: TextStyle(
                  fontSize: 12.5, color: couleur ?? Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ---------------------------------------------------------------------------
// DONNÉES DU FORMULAIRE DE PAIEMENT
// ---------------------------------------------------------------------------

class _ResultatPaiement {
  const _ResultatPaiement({
    required this.montant,
    required this.modePaiement,
    this.montantTotalDu,
    this.reference,
    this.note,
  });

  final double montant;
  final String modePaiement;

  /// 🧮 Montant total dû de l'abonnement, quand l'opérateur l'a fixé ou
  /// corrigé dans la fenêtre. `null` = on garde celui du dossier.
  final double? montantTotalDu;

  final String? reference;
  final String? note;
}

// ---------------------------------------------------------------------------
// DIALOGUE DE VALIDATION DU PAIEMENT (montant / mode / référence / note)
// ---------------------------------------------------------------------------

class _DialoguePaiement extends StatefulWidget {
  const _DialoguePaiement({required this.dossier});

  final DossierActivation dossier;

  @override
  State<_DialoguePaiement> createState() => _DialoguePaiementState();
}

class _DialoguePaiementState extends State<_DialoguePaiement> {
  late final TextEditingController _montant;

  /// 🧮 MODULE 21 — Montant total dû de l'abonnement. C'est ce montant que le
  /// moteur d'abonnement utilise pour calculer le solde : sans lui, une
  /// entreprise sans grille tarifaire ne peut pas être activée.
  late final TextEditingController _montantTotal;

  final TextEditingController _reference = TextEditingController();
  final TextEditingController _note = TextEditingController();

  String _modePaiement = modesPaiementDisponibles.first;
  String? _erreurMontant;
  String? _erreurTotal;

  @override
  void initState() {
    super.initState();
    // Pré-rempli avec le solde restant (cas le plus courant : régularisation
    // ou paiement total). La finance peut saisir un montant inférieur
    // (paiement partiel → essai initial).
    final double solde = widget.dossier.soldeRestant;
    _montant = TextEditingController(
      text: solde > 0 ? solde.toStringAsFixed(0) : '',
    );

    // Montant total dû connu du dossier (peut être vide si la base ne le
    // porte pas encore : c'est précisément le cas que ce champ règle).
    final double total = widget.dossier.montantTotalDu;
    _montantTotal = TextEditingController(
      text: total > 0 ? total.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _montant.dispose();
    _montantTotal.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _montantSaisi =>
      double.tryParse(_montant.text.trim().replaceAll(' ', '')) ?? 0;

  /// Montant total dû saisi dans la fenêtre (0 = non renseigné).
  double get _montantTotalSaisi =>
      double.tryParse(_montantTotal.text.trim().replaceAll(' ', '')) ?? 0;

  /// Montant total dû retenu : la saisie de l'opérateur prime sur celui du
  /// dossier (le serveur l'enregistre AVANT d'encaisser le paiement).
  double get _totalDu => _montantTotalSaisi > 0
      ? _montantTotalSaisi
      : widget.dossier.montantTotalDu;

  /// Solde qui sera réellement réclamé par le moteur d'abonnement
  /// (total dû − déjà payé).
  double get _soldeEffectif {
    final double calcule = _totalDu - widget.dossier.montantDejaPaye;
    if (calcule > 0) return calcule;
    return widget.dossier.soldeRestant;
  }

  /// Aperçu du scénario appliqué par la base (total → 30 j ; partiel → essai).
  String get _apercu {
    final double montant = _montantSaisi;
    if (_montantTotalSaisi <= 0 && widget.dossier.montantTotalDu <= 0) {
      return 'Renseignez le MONTANT TOTAL DÛ de l\'abonnement : sans lui, '
          'le serveur refuse l\'activation (il ne saurait pas quel solde '
          'réclamer).';
    }
    if (montant <= 0) return 'Saisissez le montant réellement reçu.';

    final double solde = _soldeEffectif;

    if (montant >= solde && solde > 0) {
      return 'Paiement TOTAL : le compte sera ACTIVÉ immédiatement '
          '(abonnement de 30 jours).';
    }
    if (solde <= 0) {
      return 'Abonnement déjà soldé : ce paiement sera enregistré '
          '(prolongation / régularisation selon la grille tarifaire).';
    }
    return 'Paiement PARTIEL : essai initial accordé (7 jours par défaut), '
        'solde restant de ${solde.toStringAsFixed(0)} CDF à régulariser '
        'avant l\'échéance.';
  }

  void _valider() {
    if (_montantSaisi <= 0) {
      setState(() => _erreurMontant = 'Montant invalide.');
      return;
    }

    // Sans montant total dû, le moteur d'abonnement ne peut pas calculer de
    // solde : on l'exige AVANT d'appeler le serveur (message clair plutôt
    // qu'un échec MONTANT_TOTAL_INCONNU).
    if (_montantTotalSaisi <= 0 && widget.dossier.montantTotalDu <= 0) {
      setState(() => _erreurTotal =
          'Indiquez le montant total dû de l\'abonnement.');
      return;
    }

    Navigator.of(context).pop(
      _ResultatPaiement(
        montant: _montantSaisi,
        modePaiement: _modePaiement,
        montantTotalDu: _montantTotalSaisi > 0 ? _montantTotalSaisi : null,
        reference: _reference.text.trim().isEmpty
            ? null
            : _reference.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Valider le paiement — ${widget.dossier.nom}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Solde restant : ${widget.dossier.soldeRestant.toStringAsFixed(0)} CDF',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            // 🧮 MODULE 21 — MONTANT TOTAL DÛ : le champ qui manquait. Le
            // solde_restant de la base est calculé à partir de ce montant.
            TextFormField(
              controller: _montantTotal,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
              ],
              onChanged: (_) => setState(() => _erreurTotal = null),
              decoration: InputDecoration(
                labelText: 'Montant total dû (abonnement, CDF)',
                helperText: widget.dossier.montantTotalDu > 0
                    ? 'Montant négocié pour cette entreprise. Il prime sur le '
                        'prix du pack tarifaire.'
                    : 'Non renseigné dans la base : saisissez-le, sinon le '
                        'serveur refuse l\'activation.',
                helperMaxLines: 3,
                errorText: _erreurTotal,
                prefixIcon: const Icon(Icons.request_quote_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _montant,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
              ],
              onChanged: (_) => setState(() => _erreurMontant = null),
              decoration: InputDecoration(
                labelText: 'Montant reçu (CDF)',
                errorText: _erreurMontant,
                prefixIcon: const Icon(Icons.payments_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            AppDropdownField<String>(
              label: 'Mode de paiement',
              value: _modePaiement,
              prefixIcon: Icons.credit_card_rounded,
              items: modesPaiementDisponibles
                  .map((String mode) => DropdownMenuItem<String>(
                        value: mode,
                        child: Text(mode),
                      ))
                  .toList(growable: false),
              onChanged: (String? valeur) {
                if (valeur != null) setState(() => _modePaiement = valeur);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Référence transaction (optionnel)',
                hintText: 'Ex. : MOMO-2026-00123',
                prefixIcon: Icon(Icons.receipt_long_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optionnel)',
                prefixIcon: Icon(Icons.notes_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _apercu,
                      style: TextStyle(
                          fontSize: 12, color: Colors.blue.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _valider,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Valider et activer'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// DIALOGUE DE MOTIF (rejet finance — motif obligatoire)
// ---------------------------------------------------------------------------

class _DialogueMotifFinance extends StatefulWidget {
  const _DialogueMotifFinance({
    required this.titre,
    required this.message,
    required this.controleur,
  });

  final String titre;
  final String message;
  final TextEditingController controleur;

  @override
  State<_DialogueMotifFinance> createState() => _DialogueMotifFinanceState();
}

class _DialogueMotifFinanceState extends State<_DialogueMotifFinance> {
  String? _erreur;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.message),
          const SizedBox(height: 12),
          TextField(
            controller: widget.controleur,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Motif (obligatoire)',
              hintText: 'Ex. : paiement introuvable sur le relevé Mobile Money',
              errorText: _erreur,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final String valeur = widget.controleur.text.trim();
            if (valeur.length < 3) {
              setState(() => _erreur =
                  'Précisez le motif (3 caractères minimum).');
              return;
            }
            Navigator.of(context).pop(valeur);
          },
          child: const Text('Rejeter le paiement'),
        ),
      ],
    );
  }
}
