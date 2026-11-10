// lib/pages/abonnement_detail_page.dart
//
// MODULE 3 — Écran « Détail abonnement » (admin).
//
// Affiche l'état complet de l'abonnement d'une entreprise : total dû, déjà
// payé, solde, statut, dates, jours restants, ainsi que l'historique des
// paiements du moteur (table `paiements_abonnements_laperle`).
//
// Actions : enregistrer un paiement (avance / solde / renouvellement) et
// encaisser le nouveau cycle par Mobile Money (SerdiPay).
//
// 🚫 MIGRATION 126 — PLUS DE RÉACTIVATION GRATUITE : ouvrir un nouveau cycle
// se PAIE. L'ancien bouton « Réactiver l'abonnement » repoussait la date de
// 30 jours sans encaisser un franc ; il est remplacé par un encaissement
// SerdiPay réel. Le serveur refuse même un appel direct.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/etat_installation.dart';
import 'package:biashara_yangu/models/paiement_laperle.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/pages/paiement_serdipay_page.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/statut_abonnement_chip.dart';

class AbonnementDetailPage extends StatefulWidget {
  const AbonnementDetailPage({super.key, this.entreprise, this.entrepriseId});

  /// Entreprise transmise par l'écran appelant (évite un aller-retour réseau).
  final Entreprise? entreprise;

  /// Identifiant, utilisé lorsque l'écran est ouvert par URL directe.
  final String? entrepriseId;

  @override
  State<AbonnementDetailPage> createState() => _AbonnementDetailPageState();
}

class _AbonnementDetailPageState extends State<AbonnementDetailPage> {
  final AbonnementService _service = AbonnementService.instance;

  Entreprise? _entreprise;
  SoldeAbonnement? _solde;
  List<PaiementLaperle> _paiements = const <PaiementLaperle>[];
  int _dureeAbonnementJours = 30;

  /// Ce que le prochain encaissement doit demander, et si l'installation est
  /// déjà réglée. Lu sur le serveur, jamais déduit à l'écran.
  EtatInstallation _installation = EtatInstallation.inconnu;

  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _entreprise = widget.entreprise;
    _charger();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _charger({bool silencieux = false}) async {
    final String? id = widget.entrepriseId ?? _entreprise?.id;

    if (id == null) {
      setState(() {
        _erreur = "Identifiant de l'entreprise manquant.";
        _chargement = false;
      });
      return;
    }

    if (!mounted) return;
    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    Entreprise? entreprise;
    SoldeAbonnement? solde;
    List<PaiementLaperle> paiements = const <PaiementLaperle>[];
    int duree = 30;
    EtatInstallation installation = EtatInstallation.inconnu;
    String? messageErreur;

    try {
      entreprise = await _service.getEntreprise(id);

      if (entreprise == null) {
        messageErreur =
            'Cette entreprise est introuvable. Elle a peut-être été supprimée.';
      } else {
        solde = AbonnementService.soldeDepuisEntreprise(entreprise);

        final List<dynamic> complement = await Future.wait<dynamic>([
          _service.getHistorique(id),
          _service.getDureeAbonnement(entreprise.groupeTarifaireId),
          _service.etatInstallation(entrepriseId: id),
        ]);

        paiements = complement[0] as List<PaiementLaperle>;
        duree = complement[1] as int;
        installation = complement[2] as EtatInstallation;
      }
    } on AbonnementServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('AbonnementDetailPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement du détail.';
    }

    if (!mounted) return;

    if (messageErreur != null) {
      if (silencieux) {
        _afficherMessage(messageErreur, estErreur: true);
        return;
      }
      setState(() {
        _erreur = messageErreur;
        _chargement = false;
      });
      return;
    }

    setState(() {
      _entreprise = entreprise;
      _solde = solde;
      _paiements = paiements;
      _dureeAbonnementJours = duree;
      _installation = installation;
      _erreur = null;
      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  /// Ouvre l'écran « Enregistrer un paiement » du moteur.
  Future<void> _ouvrirPaiement() async {
    final Entreprise? entreprise = _entreprise;
    if (entreprise == null) return;

    final GoRouter router = GoRouter.of(context);
    final bool? enregistre = await router.push<bool>(
      '/admin/abonnements/${entreprise.id}/paiement',
      extra: entreprise,
    );

    if (!mounted || enregistre != true) return;

    _afficherMessage('Paiement enregistré avec succès.');
    await _charger(silencieux: true);
  }

  /// 💳 MIGRATION 126 — ENCAISSEMENT DU NOUVEAU CYCLE PAR MOBILE MONEY.
  ///
  /// Remplace l'ancien « Réactiver l'abonnement » (30 jours offerts sans
  /// paiement). On ouvre la passerelle SerdiPay : le serveur ouvre le cycle au
  /// prix mensuel négocié, le client valide sur son téléphone, et le webhook
  /// crédite puis active l'abonnement. Aucun jour n'est accordé sans argent.
  Future<void> _encaisserMobileMoney() async {
    final Entreprise? entreprise = _entreprise;
    if (entreprise == null) return;

    final bool? paye = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PaiementSerdipayPage(
          objet: 'abonnement',
          entrepriseId: entreprise.id,
          libelleEntreprise: entreprise.nom,
        ),
      ),
    );

    if (!mounted) return;

    if (paye == true) {
      _afficherMessage('Paiement Mobile Money confirmé par SerdiPay.');
    }
    // Même sans confirmation immédiate, l'état a pu changer côté serveur
    // (webhook reçu entre-temps) : on relit toujours la fiche.
    await _charger(silencieux: true);
  }

  void _afficherMessage(String message, {bool estErreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: estErreur
            ? Colors.red.shade700
            : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Entreprise? entreprise = _entreprise;
    final SoldeAbonnement? solde = _solde;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Détail de l'abonnement",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            onPressed: () => _charger(silencieux: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _construireCorps(theme, entreprise, solde),
      bottomNavigationBar:
          (entreprise != null && solde != null) ? _barreActions(solde) : null,
    );
  }

  Widget _construireCorps(
    ThemeData theme,
    Entreprise? entreprise,
    SoldeAbonnement? solde,
  ) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreur != null || entreprise == null || solde == null) {
      return _vueErreur(theme);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _entete(theme, entreprise, solde),
          if (solde.statut == StatutAbonnement.expire ||
              solde.statut == StatutAbonnement.enAttenteComplement ||
              solde.statut == StatutAbonnement.suspendu) ...[
            const SizedBox(height: 12),
            _alerteStatut(theme, solde.statut),
          ],
          const SizedBox(height: 16),
          _encartInstallation(theme),
          const SizedBox(height: 16),
          _carteMontants(theme, solde),
          const SizedBox(height: 16),
          _carteEcheances(theme, entreprise, solde),
          const SizedBox(height: 16),
          _carteHistorique(theme),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _entete(
    ThemeData theme,
    Entreprise entreprise,
    SoldeAbonnement solde,
  ) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.card_membership_rounded,
                    size: 24,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entreprise.nom.isEmpty
                            ? 'Entreprise sans nom'
                            : entreprise.nom,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Suivi du moteur d\'abonnement',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                StatutAbonnementChip(statut: solde.statut),
                const Spacer(),
                if (solde.joursRestants != null) ...[
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: _couleurJours(solde.joursRestants),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _libelleJoursRestants(solde.joursRestants!),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _couleurJours(solde.joursRestants),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _alerteStatut(ThemeData theme, StatutAbonnement statut) {
    final bool suspendu = statut == StatutAbonnement.suspendu;
    final bool attente = statut == StatutAbonnement.enAttenteComplement;

    final Color couleur =
        suspendu || attente ? Colors.orange.shade800 : Colors.red.shade700;

    final String message = suspendu
        ? "Accès de l'entreprise suspendu par l'administrateur."
        : attente
            ? "L'essai / l'abonnement est échu : un complément de paiement est "
                'attendu. L\'entreprise conserve un accès en lecture seule.'
            : "L'abonnement a expiré. L'entreprise conserve un accès en "
                'lecture seule ; enregistrez un renouvellement pour la '
                'réactiver.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: couleur.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: couleur),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: couleur,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 🔁 L'INSTALLATION NE SE PAIE QU'UNE FOIS.
  ///
  /// Le patron doit voir noir sur blanc ce que le prochain encaissement
  /// demandera. Sans cet encart, la même question revient à chaque
  /// renouvellement : « est-ce que je dois encore payer l'installation ? »
  Widget _encartInstallation(ThemeData theme) {
    final EtatInstallation etat = _installation;
    if (etat.entrepriseId.isEmpty) return const SizedBox.shrink();

    final bool reglee = etat.installationDejaReglee;
    final Color couleur =
        reglee ? const Color(0xFF0F766E) : const Color(0xFFB45309);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: couleur.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            reglee ? Icons.verified_rounded : Icons.info_outline_rounded,
            size: 20,
            color: couleur,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  etat.libelleInstallation,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Prochain encaissement : '
                  '${etat.libelleProchainEncaissement}',
                  style: theme.textTheme.bodySmall,
                ),
                if (etat.cyclesSoldes > 0)
                  Text(
                    '${etat.cyclesSoldes} cycle(s) déjà soldé(s).',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteMontants(ThemeData theme, SoldeAbonnement solde) {
    final Color couleurSolde =
        solde.estSolde ? Colors.green.shade700 : Colors.deepOrange.shade700;

    return _carte(
      theme: theme,
      titre: 'Soldes',
      icone: Icons.account_balance_wallet_rounded,
      enfants: [
        _ligneInfo('Montant total dû', formatMontant(solde.total)),
        _ligneInfo(
          'Montant déjà payé',
          formatMontant(solde.paye),
          couleurValeur: Colors.green.shade700,
        ),
        _ligneInfo(
          'Solde restant',
          formatMontant(solde.solde),
          couleurValeur: couleurSolde,
          gras: true,
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: solde.tauxPaiement,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: solde.estSolde
                ? Colors.green.shade600
                : theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${(solde.tauxPaiement * 100).round()} % de l\'abonnement réglé',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _carteEcheances(
    ThemeData theme,
    Entreprise entreprise,
    SoldeAbonnement solde,
  ) {
    return _carte(
      theme: theme,
      titre: 'Échéances',
      icone: Icons.event_available_rounded,
      enfants: [
        _ligneInfo("Date d'activation", formatDate(entreprise.dateActivation)),
        _ligneInfo(
          "Date d'expiration",
          formatDate(solde.dateExpiration),
        ),
        _ligneInfo(
          'Jours restants',
          solde.joursRestants == null
              ? 'Non planifiée'
              : _libelleJoursRestants(solde.joursRestants!),
          couleurValeur: _couleurJours(solde.joursRestants),
          gras: true,
        ),
        _ligneInfo(
          "Durée d'abonnement (grille)",
          '$_dureeAbonnementJours jour${_dureeAbonnementJours > 1 ? 's' : ''}',
        ),
        const SizedBox(height: 8),
        Text(
          'Un paiement complet fixe la date d\'expiration à '
          "$_dureeAbonnementJours jours à partir d'aujourd'hui — ou depuis "
          'la date actuelle si elle est encore future (renouvellement '
          'anticipé).',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _carteHistorique(ThemeData theme) {
    final List<PaiementLaperle> paiements = _paiements;

    return _carte(
      theme: theme,
      titre: 'Historique des paiements',
      icone: Icons.history_rounded,
      enfants: [
        if (paiements.isEmpty)
          Text(
            'Aucun paiement enregistré par le moteur pour le moment.',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...paiements.map(
            (PaiementLaperle paiement) => _lignePaiement(theme, paiement),
          ),
      ],
    );
  }

  Widget _lignePaiement(ThemeData theme, PaiementLaperle paiement) {
    final String auteur = paiement.enregistreParNom ?? 'Auteur inconnu';
    final double? soldeApres = paiement.soldeApres;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: Colors.green.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatMontant(paiement.montant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (paiement.typePaiement != null)
                      _puce(
                        theme,
                        paiement.typePaiement!.libelle,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    formatDateHeure(paiement.createdAt),
                    if ((paiement.modePaiement ?? '').isNotEmpty)
                      paiement.modePaiement!,
                    auteur,
                  ].join(' • '),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if ((paiement.note ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      paiement.note!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (soldeApres != null || paiement.aProlonge)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      <String>[
                        if (soldeApres != null)
                          'reste ${formatMontant(soldeApres)}',
                        if (paiement.aProlonge)
                          'prolongé de ${paiement.prolongationJours} '
                              'jour${paiement.prolongationJours > 1 ? 's' : ''}',
                      ].join(' • '),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _barreActions(SoldeAbonnement solde) {
    // 🚫 MIGRATION 126 : plus de réactivation gratuite. Un abonnement échu et
    // soldé ne repart qu'après un ENCAISSEMENT réel (Mobile Money / SerdiPay
    // ici, ou « Enregistrer un paiement » pour les espèces).
    final bool peutEncaisserMm = solde.estSolde &&
        (solde.statut == StatutAbonnement.expire ||
            solde.statut == StatutAbonnement.enAttenteComplement);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: _ouvrirPaiement,
              icon: const Icon(Icons.payments_rounded),
              label: Text(
                solde.estSolde
                    ? 'Enregistrer un renouvellement'
                    : 'Enregistrer un paiement',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (peutEncaisserMm) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _encaisserMobileMoney,
                icon: const Icon(Icons.smartphone_rounded),
                label: const Text('Encaisser par Mobile Money'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _libelleJoursRestants(int jours) {
    if (jours < 0) {
      return 'Expiré depuis ${-jours} jour${-jours > 1 ? 's' : ''}';
    }
    if (jours == 0) return "Expire aujourd'hui";
    return '$jours jour${jours > 1 ? 's' : ''} restant${jours > 1 ? 's' : ''}';
  }

  Color _couleurJours(int? jours) {
    if (jours == null) return Theme.of(context).colorScheme.onSurfaceVariant;
    if (jours < 0) return Colors.red.shade700;
    if (jours <= 3) return Colors.orange.shade800;
    return Colors.green.shade700;
  }

  Widget _carte({
    required ThemeData theme,
    required String titre,
    required IconData icone,
    required List<Widget> enfants,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  titre,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            ...enfants,
          ],
        ),
      ),
    );
  }

  Widget _ligneInfo(
    String libelle,
    String valeur, {
    Color? couleurValeur,
    bool gras = false,
  }) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              libelle,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: gras ? FontWeight.bold : FontWeight.w600,
                color: couleurValeur,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _puce(ThemeData theme, String libelle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        libelle,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _vueErreur(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Abonnement indisponible',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _erreur ?? 'Erreur inconnue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _charger(),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Retour'),
            ),
          ],
        ),
      ),
    );
  }
}
