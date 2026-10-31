// lib/pages/paiement_serdipay_page.dart
//
// PASSERELLE SERDIPAY — écran de règlement en ligne de l'abonnement.
//
// Parcours :
//   1. le patron saisit son numéro Mobile Money et choisit l'opérateur ;
//   2. l'application ouvre un paiement (montant calculé par le serveur) ;
//   3. si SerdiPay renvoie une page de paiement, elle est ouverte dans le
//      navigateur ; sinon l'utilisateur valide la demande USSD sur son
//      téléphone ;
//   4. l'écran sonde l'état toutes les 3 secondes jusqu'à confirmation.
//
// ⚠️ La confirmation RÉELLE vient du webhook SerdiPay (côté serveur). Si
// l'utilisateur ferme l'application avant la fin, l'abonnement sera crédité
// de la même façon : rien ne dépend de cet écran.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/activation.dart';
import 'package:biashara_yangu/models/etat_installation.dart';
import 'package:biashara_yangu/models/paiement_serdipay.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/activation_service.dart';
import 'package:biashara_yangu/services/serdipay_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class PaiementSerdipayPage extends StatefulWidget {
  const PaiementSerdipayPage(
      {super.key, this.objet = 'abonnement', this.objetId});

  /// `abonnement` (cycle en cours) ou `facture`.
  final String objet;

  /// Identifiant de la facture quand [objet] vaut `facture`.
  final String? objetId;

  @override
  State<PaiementSerdipayPage> createState() => _PaiementSerdipayPageState();
}

class _PaiementSerdipayPageState extends State<PaiementSerdipayPage> {
  final TextEditingController _telephone = TextEditingController();

  /// Montant réellement payé : la totalité par défaut, ou une AVANCE que le
  /// client choisit. Le serveur refuse tout montant supérieur au solde.
  final TextEditingController _montant = TextEditingController();

  EtatActivation? _etat;
  bool _chargement = true;
  bool _enCours = false;
  bool _sondage = false;
  String? _erreur;

  OperateurSerdipay _operateur = OperateurSerdipay.orange;

  /// Nature du cycle ouvert par la préparation : « Installation (premier mois
  /// inclus) » ou « Abonnement du mois ». Le client doit savoir ce qu'il paie.
  PreparationRenouvellement _preparation = PreparationRenouvellement.aucune;
  PaiementSerdipay? _paiement;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _telephone.dispose();
    _montant.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // CHARGEMENT
  // -------------------------------------------------------------------------

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      EtatActivation etat = await ActivationService.instance.chargerEtat();

      // 🔁 ABONNEMENT ÉCHU ET DÉJÀ SOLDÉ : il n'y a « rien à payer » parce
      // qu'aucun cycle n'est ouvert. On l'ouvre au prix mensuel négocié —
      // c'est ce qui permet au client de se renouveler SEUL.
      PreparationRenouvellement preparation = PreparationRenouvellement.aucune;
      if (widget.objet == 'abonnement' && etat.doitRenouveler) {
        preparation = await AbonnementService.instance.preparerRenouvellement();
        etat = await ActivationService.instance.chargerEtat();
      }

      final String? numero = await _telephoneConnu();

      if (!mounted) return;
      setState(() {
        _etat = etat;
        _preparation = preparation;
        _chargement = false;
        if (_telephone.text.trim().isEmpty && numero != null) {
          _telephone.text = numero;
        }
        if (_montant.text.trim().isEmpty && !etat.estSolde) {
          _montant.text = etat.soldeRestant.toStringAsFixed(0);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger votre dossier : $e';
        _chargement = false;
      });
    }
  }

  /// Numéro enregistré sur la fiche utilisateur (best-effort).
  Future<String?> _telephoneConnu() async {
    try {
      final User? user = SupabaseService.instance.auth.currentUser;
      if (user == null) return null;

      final dynamic ligne = await SupabaseService.instance.client
          .from('utilisateurs')
          .select('telephone')
          .eq('id', user.id)
          .maybeSingle();

      if (ligne is Map && ligne['telephone'] != null) {
        return ligne['telephone'].toString();
      }
    } catch (_) {
      // Le champ n'est peut-être pas encore rempli : l'utilisateur saisira.
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // PAIEMENT
  // -------------------------------------------------------------------------

  Future<void> _payer() async {
    if (_enCours) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final PaiementSerdipay paiement = await SerdipayService.instance.initier(
        telephone: _telephone.text,
        operateur: _operateur,
        objet: widget.objet,
        objetId: widget.objetId,
        montant: _montantPartiel(),
      );

      if (!mounted) return;
      setState(() {
        _paiement = paiement;
        _enCours = false;
      });

      // Page hébergée : on l'ouvre tout de suite (meilleure conversion).
      if (paiement.demandeOuvertureNavigateur) {
        await SerdipayService.instance.ouvrirLien(paiement.urlPaiement);
      }

      await _sonder(depart: paiement);
    } on SerdipayException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _enCours = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Paiement impossible pour le moment : $e';
        _enCours = false;
      });
    }
  }

  /// Montant d'une avance, ou `null` pour payer la totalité du solde.
  ///
  /// Un montant vide, invalide, nul ou égal au solde renvoie `null` : on
  /// paie alors tout, et le serveur recalcule de toute façon.
  double? _montantPartiel() {
    if (widget.objet != 'abonnement') return null;

    final double solde = _etat?.soldeRestant ?? 0;
    final double? saisi =
        double.tryParse(_montant.text.replaceAll(' ', '').replaceAll(',', '.'));

    if (saisi == null || saisi <= 0 || saisi >= solde - 0.01) return null;
    return saisi;
  }

  Future<void> _sonder({PaiementSerdipay? depart}) async {
    final PaiementSerdipay paiement = depart ?? _paiement!;
    if (_sondage) return;

    setState(() => _sondage = true);

    final PaiementSerdipay resultat =
        await SerdipayService.instance.attendreConfirmation(
      paiement,
      onChangement: (PaiementSerdipay p) {
        if (mounted) setState(() => _paiement = p);
      },
    );

    if (!mounted) return;
    setState(() {
      _paiement = resultat;
      _sondage = false;
    });
  }

  // -------------------------------------------------------------------------
  // INTERFACE
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payer par Mobile Money'),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _charger,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  if (_erreur != null) ...<Widget>[
                    _bandeauErreur(_erreur!),
                    const SizedBox(height: 12),
                  ],
                  _carteMontant(),
                  const SizedBox(height: 12),
                  if (_paiement == null) ...<Widget>[
                    _formulaire(),
                  ] else
                    _suivi(_paiement!),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _bandeauErreur(String message) {
    final ColorScheme couleurs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: couleurs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, color: couleurs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: couleurs.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteMontant() {
    final double solde =
        widget.objet == 'facture' ? 0 : (_etat?.soldeRestant ?? 0);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.account_balance_wallet_outlined,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Montant à régler',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.objet == 'facture'
                  ? 'Solde exact calculé par le serveur'
                  : formatMontant(solde),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            if (_preparation.cycleOuvert) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                _preparation.libelleCycle,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              "Le montant est vérifié et recalculé sur le serveur au moment "
              "du paiement : il ne peut pas être modifié depuis l'application.",
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_etat != null &&
                !_etat!.estSolde &&
                widget.objet != 'facture') ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Total dû ${formatMontant(_etat!.montantTotalDu)} · '
                'déjà payé ${formatMontant(_etat!.montantDejaPaye)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _formulaire() {
    final bool rienAPayer =
        widget.objet != 'facture' && (_etat?.estSolde ?? false);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Numéro Mobile Money',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: '+243 970 000 000',
                prefixIcon: Icon(Icons.phone_android_rounded),
              ),
            ),
            // 💰 AVANCE : le client choisit ce qu'il verse maintenant.
            // Le champ est pré-rempli avec le solde ; le serveur refuse
            // tout montant supérieur. Une avance laisse le compte en
            // « complément attendu » — il s'active dès que le cycle est soldé.
            if (widget.objet == 'abonnement' &&
                !(_etat?.estSolde ?? true)) ...<Widget>[
              const SizedBox(height: 16),
              TextFormField(
                controller: _montant,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Montant à payer',
                  helperText: 'Vous pouvez payer une partie seulement : '
                      'le reste sera à compléter. Total dû '
                      '${formatMontant(_etat?.soldeRestant ?? 0)}.',
                  prefixIcon: const Icon(Icons.payments_rounded),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Moyen de paiement',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final OperateurSerdipay operateur
                    in OperateurSerdipay.values)
                  ChoiceChip(
                    label: Text(operateur.libelle),
                    selected: _operateur == operateur,
                    onSelected: (_) => setState(() => _operateur = operateur),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (rienAPayer || _enCours) ? null : _payer,
                icon: _enCours
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_rounded),
                label: Text(
                  rienAPayer
                      ? 'Abonnement déjà réglé'
                      : _enCours
                          ? 'Ouverture du paiement…'
                          : 'Payer maintenant',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Paiement sécurisé par SerdiPay. Aucune information bancaire '
              "n'est stockée par Biashara Yangu.",
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suivi(PaiementSerdipay paiement) {
    final ColorScheme couleurs = Theme.of(context).colorScheme;

    final Color couleur = switch (paiement.statut) {
      StatutPaiementSerdipay.paye => Colors.green.shade700,
      StatutPaiementSerdipay.enAttente => Colors.orange.shade800,
      _ => couleurs.error,
    };

    final IconData icone = switch (paiement.statut) {
      StatutPaiementSerdipay.paye => Icons.check_circle_rounded,
      StatutPaiementSerdipay.enAttente => Icons.hourglass_top_rounded,
      _ => Icons.cancel_rounded,
    };

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icone, color: couleur, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        paiement.statut.libelle,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: couleur,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${paiement.montantLibelle} · réf. ${paiement.reference}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (paiement.message != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                paiement.message!,
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (paiement.motifEchec != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'Motif : ${paiement.motifEchec}',
                style: TextStyle(fontSize: 12, color: couleurs.error),
              ),
            ],
            const SizedBox(height: 16),
            if (paiement.demandeOuvertureNavigateur)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      SerdipayService.instance.ouvrirLien(paiement.urlPaiement),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Ouvrir la page de paiement'),
                ),
              ),
            if (paiement.estEnAttente) ...<Widget>[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _sondage ? null : () => _sonder(),
                  icon: _sondage
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(
                    _sondage
                        ? 'Vérification automatique…'
                        : 'Vérifier maintenant',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Validez la demande reçue sur votre téléphone. Cet écran se "
                "met à jour automatiquement dès que SerdiPay confirme.",
                style: TextStyle(
                  fontSize: 11.5,
                  color: couleurs.onSurfaceVariant,
                ),
              ),
            ],
            if (paiement.estPaye) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Retour à mon dossier'),
                ),
              ),
            ],
            if (paiement.statut == StatutPaiementSerdipay.echoue ||
                paiement.statut == StatutPaiementSerdipay.annule ||
                paiement.statut == StatutPaiementSerdipay.expire) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _paiement = null;
                    _erreur = null;
                  }),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Réessayer'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
