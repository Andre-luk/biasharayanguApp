// lib/pages/mon_activation_page.dart
//
// MODULE 14 — « MON DOSSIER D'ACTIVATION » (ESPACE ENTREPRISE).
//
// Tableau de bord transparent pour le patron : à quelle étape en est son
// compte, combien il a payé, quel solde reste, jusqu'à quand l'abonnement
// court, et l'historique complet des décisions (vérification, paiement,
// éventuel rejet ou restriction).
//
// Les données proviennent de `rpc_activation_etat` (migration 18) : le
// serveur n'expose le dossier qu'aux membres de l'entreprise et au personnel
// plateforme. Aucune donnée n'est jamais supprimée — un compte restreint
// reste consultable.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/activation.dart';
// � MODULE 26 — abonnement par collaborateur (base + supplément).
import 'package:biashara_yangu/models/abonnement_collaborateurs.dart';
// �🪙 MODULE 18 — devise de travail et taux de change (équivalences).
import 'package:biashara_yangu/models/devise.dart';
import 'package:biashara_yangu/models/etat_installation.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/activation_service.dart';
import 'package:biashara_yangu/services/devise_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class MonActivationPage extends StatefulWidget {
  const MonActivationPage({super.key});

  @override
  State<MonActivationPage> createState() => _MonActivationPageState();
}

class _MonActivationPageState extends State<MonActivationPage> {
  EtatActivation? _etat;
  bool _chargement = true;
  bool _renouvellement = false;

  /// 🩹 Correctif 112 — ouverture d'un cycle anticipé (essai / avant échéance).
  bool _avance = false;
  String? _erreur;

  /// 🧮 MODULE 26 — détail : base + collaborateurs actifs facturés.
  Map<String, dynamic>? _detailCollaborateurs;

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
      final EtatActivation etat =
          await ActivationService.instance.chargerEtat();
      final Map<String, dynamic>? detail =
          await AbonnementService.instance.detailCollaborateurs();
      if (!mounted) return;
      setState(() {
        _etat = etat;
        _detailCollaborateurs = detail;
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
        _erreur = 'Impossible de charger votre dossier : $e';
        _chargement = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mon dossier d\'activation',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _charger,
        child: _chargement
            ? const Center(child: CircularProgressIndicator())
            : _erreur != null
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: <Widget>[
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.red.shade700),
                      const SizedBox(height: 12),
                      Text(_erreur!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Center(
                        child: FilledButton.icon(
                          onPressed: _charger,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ),
                    ],
                  )
                : _contenu(context, _etat!, colorScheme),
      ),
    );
  }

  Widget _contenu(
    BuildContext context,
    EtatActivation etat,
    ColorScheme colorScheme,
  ) {
    if (!etat.aUnDossier) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const SizedBox(height: 40),
          Icon(Icons.folder_open_rounded,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'Aucun dossier d\'activation',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Votre compte n'est rattaché à aucune entreprise pour le moment. "
            'Le dossier apparaîtra ici dès la création de votre boutique.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _carteEtape(etat, colorScheme),
        const SizedBox(height: 12),
        _carteMontants(etat, colorScheme),
        if (_detailCollaborateurs != null) ...<Widget>[
          const SizedBox(height: 12),
          _carteCollaborateurs(_detailCollaborateurs!),
        ],
        // 💳 LE CLIENT PAIE SEUL — Y COMPRIS PENDANT L'ESSAI.
        // Trois situations, un seul bouton visible :
        //   • un solde est dû            → paiement direct ;
        //   • l'abonnement est échu      → ouverture du mois suivant ;
        //   • essai en cours / à jour    → paiement par anticipation
        //     (le serveur ouvre le cycle, le statut n'est pas touché).
        if (etat.aPayer || etat.peutPayerAnticipe) ...<Widget>[
          const SizedBox(height: 12),
          _blocPaiement(etat),
        ],
        const SizedBox(height: 12),
        _carteDates(etat),
        const SizedBox(height: 12),
        _carteHistorique(etat),
        const SizedBox(height: 24),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PAIEMENT EN LIGNE (passerelle SerdiPay)
  // ---------------------------------------------------------------------------

  /// Ouvre l'écran de paiement Mobile Money puis rafraîchit le dossier :
  /// la confirmation réelle vient du webhook SerdiPay, pas de l'écran.
  Future<void> _ouvrirPaiement() async {
    await context.push<Object?>('/main/paiement-serdipay');
    if (!mounted) return;
    await _charger();
  }

  /// Ouvre le mois suivant au prix négocié, puis rafraîchit le dossier :
  /// le bouton « Payer » apparaît alors avec le montant exact.
  ///
  /// Si l'abonnement court encore, le serveur refuse d'ouvrir un cycle : le
  /// client ne peut donc pas payer deux fois le même mois.
  Future<void> _renouveler() async {
    setState(() => _renouvellement = true);
    try {
      final PreparationRenouvellement prep =
          await AbonnementService.instance.preparerRenouvellement();
      if (!mounted) return;

      if (prep.motif == 'CYCLE_EN_COURS') {
        _afficher(
          'Votre abonnement court encore : le renouvellement sera possible '
          'à l\'échéance.',
        );
      } else if (prep.aPayer) {
        _afficher(
          '${prep.libelleCycle} : ${formatMontant(prep.soldeRestant)} '
          '${prep.devise} à régler.',
        );
      } else {
        _afficher('Aucun montant à régler pour le moment.');
      }
      await _charger();
    } on AbonnementServiceException catch (e) {
      if (!mounted) return;
      _afficher(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _renouvellement = false);
    }
  }

  void _afficher(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? const Color(0xFFB91C1C) : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🩹 CORRECTIF 112 — PAYER MÊME PENDANT L'ESSAI DE 7 JOURS.
  // ---------------------------------------------------------------------------

  /// Ouvre le cycle suivant (base + collaborateurs) sans toucher au statut ni
  /// aux dates, puis lance le paiement Mobile Money.
  ///
  /// Sans cela, un compte en essai n'a aucun solde dû : la passerelle refusait
  /// le paiement et le client devait attendre l'échéance.
  /// 🗓️ MODULE 30 — COMBIEN DE MOIS LE CLIENT VEUT-IL RÉGLER ?
  ///
  /// Le montant n'est jamais calculé ici : on demande simplement la durée,
  /// puis le SERVEUR ouvre le cycle et renvoie le prix exact.
  Future<int?> _choisirDuree() async {
    final int? choix = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Payer combien de mois ?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Un paiement de plusieurs mois prolonge votre accès d\'autant, '
                'sans perdre les jours qui vous restent.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            for (final int mois in <int>[1, 3, 6, 12])
              ListTile(
                leading: Icon(
                  mois == 1
                      ? Icons.looks_one_rounded
                      : Icons.calendar_month_rounded,
                ),
                title: Text(mois == 1 ? '1 mois' : '$mois mois'),
                subtitle: Text(mois == 1 ? 'Le prochain cycle' : 'Paiement unique'),
                onTap: () => Navigator.of(ctx).pop(mois),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    return choix;
  }

  Future<void> _payerAvance() async {
    // 🗓️ MODULE 30 — la durée d'abord (1, 3, 6 ou 12 mois).
    final int? mois = await _choisirDuree();
    if (mois == null || !mounted) return;

    setState(() => _avance = true);
    try {
      final AvanceCycle avance =
          await AbonnementService.instance.ouvrirAvance(mois: mois);
      if (!mounted) return;

      if (!avance.aPayer) {
        _afficher('Aucun montant à régler pour le moment.');
        await _charger();
        return;
      }

      _afficher(
        '${avance.libelleDuree} : '
        '${formatMontant(avance.montant)} ${avance.devise} à régler.',
      );
      // Le solde est désormais ouvert en base : l'écran de paiement le lit
      // lui-même, on ne transmet aucun montant depuis le client.
      await _ouvrirPaiement();
    } on AbonnementServiceException catch (e) {
      if (!mounted) return;
      _afficher(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _avance = false);
    }
  }

  /// Bloc de paiement unique : explication + montant + bouton.
  ///
  /// Visible pour TOUS les comptes non soldés, essai de 7 jours compris.
  Widget _blocPaiement(EtatActivation etat) {
    final bool soldeDu = etat.soldeRestant > 0.009;
    final bool echu = etat.abonnementEchu;
    final Color accent =
        soldeDu || echu ? Colors.red.shade700 : Colors.orange.shade800;
    final bool enCours = _avance || _renouvellement;

    VoidCallback? action;
    IconData icone;
    String libelle = etat.libellePaiement;

    if (soldeDu) {
      action = _ouvrirPaiement;
      icone = Icons.credit_card_rounded;
    } else if (echu && etat.estSolde) {
      action = _renouvellement ? null : _renouveler;
      icone = Icons.autorenew_rounded;
      if (_renouvellement) libelle = 'Ouverture du nouveau mois…';
    } else {
      action = _avance ? null : _payerAvance;
      icone = Icons.account_balance_wallet_rounded;
      if (_avance) libelle = 'Préparation du paiement…';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icone, color: accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  soldeDu
                      ? 'Paiement en attente'
                      : echu
                          ? 'Abonnement échu'
                          : etat.enEssai
                              ? 'Vous n\'avez pas encore payé'
                              : 'Payer par anticipation',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (soldeDu)
                Text(
                  formatMontant(etat.soldeRestant),
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            etat.explicationPaiement,
            style: TextStyle(color: Colors.grey.shade800, height: 1.35),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: enCours ? null : action,
              style: FilledButton.styleFrom(backgroundColor: accent),
              icon: Icon(icone),
              label: Text(libelle),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CARTE 1 — ÉTAPE (stepper simplifié + message)
  // ---------------------------------------------------------------------------
  Widget _carteEtape(EtatActivation etat, ColorScheme colorScheme) {
    final bool restreint = etat.etape == EtapeActivation.restreint;
    final bool rejete = etat.etape == EtapeActivation.rejete;

    final Color couleur = restreint || rejete
        ? Colors.red.shade700
        : etat.etape == EtapeActivation.actif
            ? Colors.green.shade700
            : Colors.orange.shade800;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  etat.etape == EtapeActivation.actif
                      ? Icons.verified_rounded
                      : restreint || rejete
                          ? Icons.error_rounded
                          : Icons.hourglass_top_rounded,
                  color: couleur,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        etat.nom ?? 'Mon entreprise',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        etat.etape.libelle,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: couleur),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _etapesChronologie(etat),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: couleur.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.info_outline_rounded, size: 16, color: couleur),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      etat.messageEtape,
                      style: TextStyle(fontSize: 12.5, color: couleur),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chronologie : Déposé → Vérifié → Activé.
  Widget _etapesChronologie(EtatActivation etat) {
    final bool verifieOk = etat.verifieLe != null ||
        etat.etape == EtapeActivation.verifie ||
        etat.etape == EtapeActivation.actif ||
        etat.etape == EtapeActivation.restreint;
    final bool active = etat.valideLeFinance != null ||
        etat.etape == EtapeActivation.actif ||
        etat.etape == EtapeActivation.restreint;

    final List<(String, bool, IconData)> etapes = <(String, bool, IconData)>[
      ('Déposé', true, Icons.assignment_turned_in_outlined),
      ('Vérifié (comptes)', verifieOk, Icons.fact_check_outlined),
      ('Activé (finance)', active, Icons.rocket_launch_outlined),
    ];

    return Row(
      children: <Widget>[
        for (int i = 0; i < etapes.length; i++) ...<Widget>[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color:
                    etapes[i].$2 ? Colors.green.shade400 : Colors.grey.shade300,
              ),
            ),
          Column(
            children: <Widget>[
              Icon(
                etapes[i].$3,
                size: 20,
                color: etapes[i].$2 ? Colors.green.shade700 : Colors.grey,
              ),
              const SizedBox(height: 2),
              Text(
                etapes[i].$1,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: etapes[i].$2 ? Colors.green.shade700 : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // CARTE 2 — MONTANTS (total / payé / solde + progression)
  // ---------------------------------------------------------------------------

  Widget _carteMontants(EtatActivation etat, ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text(
                  'Paiement',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    etat.typePaiement.libelle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _montantBloc('Total dû', etat.montantTotalDu, Colors.black87),
                _montantBloc(
                    'Déjà payé', etat.montantDejaPaye, Colors.green.shade700),
                _montantBloc(
                  'Solde',
                  etat.soldeRestant,
                  etat.estSolde ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: etat.tauxPaiement,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color:
                    etat.estSolde ? Colors.green.shade600 : colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(etat.tauxPaiement * 100).toStringAsFixed(0)} % réglé',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            // 🪙 MODULE 18 — taux de change utilisé pour les équivalences.
            Text(
              'Équivalences au taux 1 USD = '
              '${DeviseService.instance.taux.toStringAsFixed(0)} CDF',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _montantBloc(String titre, double valeur, Color couleur) {
    // 🪙 MODULE 18 — l'abonnement est facturé en CDF par la plateforme :
    // on affiche l'équivalent dans l'autre devise (taux de change).
    final String equivalent =
        DeviseService.instance.equivalent(valeur, depuis: Devise.cdf);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(titre,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text(
            '${valeur.toStringAsFixed(0)} CDF',
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: couleur),
          ),
          if (equivalent.isNotEmpty)
            Text(
              equivalent,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CARTE 3 — DATES & STATUT
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // 🧮 MODULE 26 — COMMENT L'ABONNEMENT EST CALCULÉ
  // ---------------------------------------------------------------------------
  //  Le propriétaire voit EXACTEMENT ce qui est facturé : prix de base,
  //  nombre de collaborateurs actifs, prix unitaire, supplément, total.
  //  Un collaborateur désactivé n'apparaît plus dans le compte.

  Widget _carteCollaborateurs(Map<String, dynamic> detail) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final AbonnementCollaborateurs calcul =
        AbonnementCollaborateurs.fromMap(detail);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.groups_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Prochain abonnement',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const Divider(height: 20),
            _ligneCalcul('Abonnement de base', formatMontant(calcul.base)),
            _ligneCalcul('Collaborateurs actifs facturés',
                '${calcul.nbCollaborateurs}'),
            _ligneCalcul(
                'Prix par collaborateur', formatMontant(calcul.prixUnitaire)),
            _ligneCalcul(
                'Supplément collaborateurs', formatMontant(calcul.supplement)),
            const Divider(height: 16),
            _ligneCalcul(
              'Total à payer',
              formatMontant(calcul.totalProchainCycle),
              gras: true,
              couleur: colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              calcul.nbCollaborateurs == 0
                  ? 'Aucun collaborateur actif : seul l\'abonnement de base est '
                      'facturé.'
                  : 'Le propriétaire n\'est pas compté. Un collaborateur '
                      'désactivé n\'est plus facturé au prochain '
                      'renouvellement.',
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (calcul.prorata) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Prorata activé : un collaborateur ajouté en cours de période '
                'est facturé sur le cycle en cours.',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ligneCalcul(
    String libelle,
    String valeur, {
    bool gras = false,
    Color? couleur,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(
            child: Text(
              libelle,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: gras ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            valeur,
            style: TextStyle(
              fontSize: gras ? 15 : 13,
              fontWeight: gras ? FontWeight.w900 : FontWeight.w600,
              color: couleur,
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteDates(EtatActivation etat) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Dates & statut',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            if (etat.statut != null)
              _ligne(Icons.badge_outlined, 'Statut d\'abonnement',
                  etat.statut!.libelle),
            if (etat.dateActivation != null)
              _ligne(Icons.play_circle_outline, 'Activé le',
                  _date(etat.dateActivation!)),
            if (etat.dateExpiration != null)
              _ligne(Icons.event_outlined, 'Expire le',
                  _date(etat.dateExpiration!)),
            if (etat.joursRestants != null)
              _ligne(
                Icons.timer_outlined,
                'Jours restants',
                '${etat.joursRestants} jour(s)',
                couleur: etat.joursRestants! <= 3 ? Colors.red.shade700 : null,
              ),
            if (etat.verifieLe != null)
              _ligne(Icons.fact_check_outlined, 'Vérifié le',
                  _date(etat.verifieLe!)),
            if (etat.valideLeFinance != null)
              _ligne(Icons.task_alt_rounded, 'Validé (finance) le',
                  _date(etat.valideLeFinance!)),
          ],
        ),
      ),
    );
  }

  Widget _ligne(IconData icone, String titre, String valeur, {Color? couleur}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Icon(icone, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(titre,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          ),
          Text(
            valeur,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: couleur),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CARTE 4 — HISTORIQUE (timeline)
  // ---------------------------------------------------------------------------

  Widget _carteHistorique(EtatActivation etat) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Historique du dossier',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            if (etat.historique.isEmpty)
              Text(
                'Aucune action enregistrée pour le moment.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              )
            else
              ...etat.historique.map(_entree),
          ],
        ),
      ),
    );
  }

  Widget _entree(EntreeActivation entree) {
    final Color couleur = entree.estRejet
        ? Colors.red.shade700
        : entree.estPaiement
            ? Colors.green.shade700
            : Colors.blue.shade700;

    final IconData icone = entree.estRejet
        ? Icons.cancel_outlined
        : entree.estPaiement
            ? Icons.payments_outlined
            : entree.etape == EtapeHistoriqueActivation.soumission
                ? Icons.assignment_outlined
                : Icons.fact_check_outlined;

    final List<String> details = <String>[
      if (entree.montant != null) '${entree.montant!.toStringAsFixed(0)} CDF',
      if ((entree.modePaiement ?? '').isNotEmpty) entree.modePaiement!,
      if ((entree.reference ?? '').isNotEmpty) 'Réf. ${entree.reference}',
      if ((entree.note ?? '').isNotEmpty) entree.note!,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, size: 18, color: couleur),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        entree.etape?.libelle ?? 'Action',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (entree.le != null)
                      Text(
                        _dateHeure(entree.le!),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                  ],
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join('  •  '),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _dateHeure(DateTime d) =>
      '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
