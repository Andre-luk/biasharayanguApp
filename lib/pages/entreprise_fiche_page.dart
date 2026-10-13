// lib/pages/entreprise_fiche_page.dart
//
// 🆕 CORRECTIF 73 — LA FICHE UNIQUE D'UNE ENTREPRISE.
//
// Un seul écran, un seul appel serveur (`rpc_entreprise_fiche`) :
//
//   • ABONNEMENT   — le pack, la durée d'un cycle, l'essai avant paiement ;
//   • INSTALLATION — le prix du premier cycle (il comprend le premier mois)
//                    et le prix mensuel des renouvellements ;
//   • SUIVI        — l'étape d'activation, le statut, les dates, les jours
//                    restants, qui a vérifié et qui a validé ;
//   • AVANCE       — le dû du cycle, ce qui est encaissé, le solde, la
//                    progression, et TOUT l'historique des paiements.
//
// Et qui a créé le compte (`cree_par`) : agent terrain, gestionnaire des
// comptes ou Super Admin.
//
// Actions disponibles selon les droits renvoyés par le serveur :
//   • ajuster les deux prix (`rpc_abonnement_definir_prix`) ;
//   • ouvrir l'abonnement complet (encaissement, historique du module 3).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/fiche_entreprise.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

class EntrepriseFichePage extends StatefulWidget {
  const EntrepriseFichePage({
    super.key,
    required this.entrepriseId,
    this.nom,
  });

  final String entrepriseId;

  /// Nom connu à l'ouverture (affiché pendant le chargement).
  final String? nom;

  @override
  State<EntrepriseFichePage> createState() => _EntrepriseFichePageState();
}

class _EntrepriseFichePageState extends State<EntrepriseFichePage> {
  FicheEntreprise? _fiche;
  bool _chargement = true;
  String? _erreur;

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
      final FicheEntreprise? fiche =
          await EntrepriseService.instance.chargerFiche(widget.entrepriseId);
      if (!mounted) return;
      setState(() {
        _fiche = fiche;
        _chargement = false;
        _erreur = fiche == null
            ? 'Réponse du serveur illisible pour cette entreprise.'
            : null;
      });
    } on EntrepriseServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger la fiche : $e';
        _chargement = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _ajusterPrix() async {
    final FicheEntreprise? fiche = _fiche;
    if (fiche == null) return;

    final TextEditingController installationCtrl = TextEditingController(
      text: fiche.prix.installation == null
          ? ''
          : fiche.prix.installation!.toStringAsFixed(0),
    );
    final TextEditingController mensuelCtrl = TextEditingController(
      text: fiche.prix.mensuel == null
          ? ''
          : fiche.prix.mensuel!.toStringAsFixed(0),
    );
    final TextEditingController noteCtrl = TextEditingController();

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Ajuster les deux prix'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                "L'installation comprend le premier mois d'abonnement ; le "
                'prix mensuel s\'applique aux renouvellements.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: installationCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Prix d\'installation',
                  prefixIcon: Icon(Icons.install_desktop_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mensuelCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Prix mensuel',
                  prefixIcon: Icon(Icons.event_repeat_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motif (optionnel)',
                  prefixIcon: Icon(Icons.sticky_note_2_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (confirme != true) {
      installationCtrl.dispose();
      mensuelCtrl.dispose();
      noteCtrl.dispose();
      return;
    }

    try {
      await EntrepriseService.instance.definirPrix(
        entrepriseId: widget.entrepriseId,
        installation: _montant(installationCtrl.text),
        mensuel: _montant(mensuelCtrl.text),
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      _message('Prix enregistrés.');
      await _charger();
    } on EntrepriseServiceException catch (e) {
      _message(e.message, estErreur: true);
    } finally {
      installationCtrl.dispose();
      mensuelCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  double? _montant(String texte) {
    final String nettoye =
        texte.replaceAll(' ', '').replaceAll('\u00A0', '').replaceAll(',', '.');
    if (nettoye.isEmpty) return null;
    return double.tryParse(nettoye);
  }

  void _message(String texte, {bool estErreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: estErreur ? AppCouleurs.danger : AppCouleurs.succes,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.peutVoir(PageAccess.entreprises)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fiche entreprise')),
        body: const AccesRefuse(
          message: 'Votre rôle ne permet pas de consulter les entreprises.',
        ),
      );
    }

    final FicheEntreprise? fiche = _fiche;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          fiche?.entreprise.nom ?? widget.nom ?? 'Fiche entreprise',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: ModernLoader(taille: 34))
          : fiche == null
              ? _vueErreur()
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: <Widget>[
                      _carteIdentite(fiche),
                      const SizedBox(height: 14),
                      _cartePrix(fiche),
                      const SizedBox(height: 14),
                      _carteSuivi(fiche),
                      const SizedBox(height: 14),
                      _cartePaiements(fiche),
                      const SizedBox(height: 14),
                      _carteHistorique(fiche),
                      const SizedBox(height: 20),
                      if (fiche.droits.peutGererPrix)
                        OutlinedButton.icon(
                          onPressed: _ajusterPrix,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Ajuster les deux prix'),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => context.pushNamed(
                          'abonnement-detail',
                          pathParameters: <String, String>{
                            'id': widget.entrepriseId,
                          },
                          extra: fiche.entreprise,
                        ),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Encaisser / abonnement complet'),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _vueErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.info_outline_rounded, size: 44),
            const SizedBox(height: 12),
            Text(_erreur ?? 'Fiche indisponible.',
                textAlign: TextAlign.center),
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

  // ------------------------------------------------ IDENTITÉ + PROPRIÉTAIRE

  Widget _carteIdentite(FicheEntreprise fiche) {
    return _carte(
      titre: 'Entreprise & responsable',
      icone: Icons.storefront_outlined,
      enfants: <Widget>[
        _ligne('Nom', fiche.entreprise.nom),
        _ligne('Ville', fiche.entreprise.villeNom ?? '—'),
        _ligne('Activité', fiche.entreprise.activiteNom ?? '—'),
        const Divider(height: 22),
        _sousTitre('Propriétaire (patron du compte)'),
        if (fiche.proprietaire == null)
          const Text('Aucun compte rattaché à cette entreprise.',
              style: TextStyle(fontSize: 12.5, color: Colors.orange))
        else ...<Widget>[
          _ligne('Nom', fiche.proprietaire!.nomComplet),
          _ligne('E-mail', fiche.proprietaire!.email ?? '—'),
          _ligne('Téléphone', fiche.proprietaire!.telephone ?? '—'),
          _ligne('Rôle', fiche.proprietaire!.role ?? '—'),
        ],
        const Divider(height: 22),
        _sousTitre('Compte créé par'),
        if (fiche.createur == null)
          const Text('Inscription autonome du patron (aucun créateur externe).',
              style: TextStyle(fontSize: 12.5))
        else ...<Widget>[
          _ligne('Nom', fiche.createur!.nomComplet),
          _ligne('E-mail', fiche.createur!.email ?? '—'),
          _ligne('Rôle', fiche.createur!.role ?? '—'),
        ],
      ],
    );
  }

  // ------------------------------------------- ABONNEMENT + INSTALLATION

  Widget _cartePrix(FicheEntreprise fiche) {
    final PrixFiche prix = fiche.prix;

    return _carte(
      titre: 'Abonnement & installation',
      icone: Icons.price_change_outlined,
      enfants: <Widget>[
        if (fiche.grille != null) ...<Widget>[
          _ligne('Pack', fiche.grille!.nom),
          _ligne(
            'Durée d\'un cycle',
            fiche.grille!.dureeAbonnementJours > 0
                ? '${fiche.grille!.dureeAbonnementJours} jour(s)'
                : '—',
          ),
          _ligne(
            'Essai avant paiement',
            '${fiche.grille!.dureeEssaiJours > 0 ? fiche.grille!.dureeEssaiJours : 7} jour(s)',
          ),
          const Divider(height: 22),
        ],
        _ligne(
          'Prix d\'installation (1er cycle)',
          prix.installation == null ? '—' : formatMontant(prix.installation!),
          gras: true,
        ),
        _ligne(
          'Prix mensuel (renouvellements)',
          prix.mensuel == null ? '—' : formatMontant(prix.mensuel!),
          gras: true,
        ),
        _ligne(
          'Prochain encaissement',
          prix.prochainMontant == null
              ? '—'
              : formatMontant(prix.prochainMontant!),
        ),
        const Divider(height: 22),
        _sousTitre('Cycle en cours'),
        _ligne('Dû', formatMontant(prix.totalDu)),
        _ligne('Déjà payé', formatMontant(prix.dejaPaye)),
        _ligne('Solde restant', formatMontant(prix.solde), gras: true),
        if (prix.paiementsCumules > 0)
          _ligne('Encaissé (historique)', formatMontant(prix.paiementsCumules)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: prix.progression,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          prix.estSolde
              ? 'Cycle entièrement réglé.'
              : '${(prix.progression * 100).round()} % du cycle réglé.',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- SUIVI

  Widget _carteSuivi(FicheEntreprise fiche) {
    final SuiviFiche suivi = fiche.suivi;

    return _carte(
      titre: 'Suivi',
      icone: Icons.timeline_rounded,
      enfants: <Widget>[
        Row(
          children: <Widget>[
            _puce(_libelleStatutCourt(suivi), suivi),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                suivi.libelleEtape,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ligne('Échéance', suivi.libelleEcheance),
        _ligne(
          'Activé le',
          suivi.dateActivation == null
              ? '—'
              : formatDate(suivi.dateActivation!),
        ),
        _ligne(
          'Expire le',
          suivi.dateExpiration == null
              ? '—'
              : formatDate(suivi.dateExpiration!),
        ),
        const Divider(height: 22),
        _ligne('Vérifié par', _court(suivi.verifiePar)),
        _ligne('Validé par la finance', _court(suivi.valideParFinance)),
      ],
    );
  }

  String _court(String? identifiant) {
    if (identifiant == null || identifiant.isEmpty) return '—';
    if (identifiant.length <= 8) return identifiant;
    return '${identifiant.substring(0, 8)}…';
  }

  String _libelleStatutCourt(SuiviFiche suivi) {
    if (suivi.activationEtape == 'actif') return 'ACTIF';
    if (suivi.activationEtape == 'restreint') return 'RESTREINT';
    if (suivi.activationEtape == 'rejete') return 'REJETÉ';
    if (suivi.enAttente) return 'EN ATTENTE';
    return suivi.libelleStatut.toUpperCase();
  }

  Widget _puce(String texte, SuiviFiche suivi) {
    final bool ok = suivi.activationEtape == 'actif';
    final bool attente = suivi.enAttente;
    final Color couleur = ok
        ? AppCouleurs.succes
        : attente
            ? Colors.orange.shade700
            : Colors.red.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: couleur.withValues(alpha: 0.5)),
      ),
      child: Text(
        texte,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800, color: couleur),
      ),
    );
  }

  // ------------------------------------------------- ANCAISSE (L'AVANCE)

  Widget _cartePaiements(FicheEntreprise fiche) {
    if (fiche.paiements.isEmpty) {
      return _carte(
        titre: 'Paiements (avance)',
        icone: Icons.payments_outlined,
        enfants: const <Widget>[
          Text('Aucun encaissement enregistré pour le moment.',
              style: TextStyle(fontSize: 13)),
        ],
      );
    }

    return _carte(
      titre: 'Paiements (avance)',
      icone: Icons.payments_outlined,
      enfants: <Widget>[
        for (final PaiementFiche p in fiche.paiements)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  p.typePaiement == 'AVANCE'
                      ? Icons.savings_outlined
                      : p.typePaiement == 'SOLDE'
                          ? Icons.price_check_rounded
                          : Icons.autorenew_rounded,
                  size: 18,
                  color: AppCouleurs.succes,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${p.libelleType} • ${formatMontant(p.montant)}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        <String>[
                          if (p.createdAt != null)
                            formatDate(p.createdAt!),
                          if ((p.modePaiement ?? '').isNotEmpty)
                            p.modePaiement!,
                          if (p.prolongationJours > 0)
                            '+${p.prolongationJours} j',
                          if (p.soldeApres != null)
                            'solde : ${formatMontant(p.soldeApres!)}',
                        ].join('  •  '),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      if ((p.note ?? '').isNotEmpty)
                        Text(p.note!,
                            style: const TextStyle(
                                fontSize: 11.5, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _carteHistorique(FicheEntreprise fiche) {
    if (fiche.historique.isEmpty) {
      return _carte(
        titre: 'Dossier d\'activation',
        icone: Icons.history_rounded,
        enfants: const <Widget>[
          Text('Aucune étape enregistrée.', style: TextStyle(fontSize: 13)),
        ],
      );
    }

    return _carte(
      titre: 'Dossier d\'activation',
      icone: Icons.history_rounded,
      enfants: <Widget>[
        for (final EtapeFiche e in fiche.historique)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.circle, size: 8),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(e.libelle,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(
                        <String>[
                          if (e.createdAt != null)
                            formatDate(e.createdAt!),
                          if (e.montant != null) formatMontant(e.montant!),
                          if ((e.modePaiement ?? '').isNotEmpty)
                            e.modePaiement!,
                          if (e.acteurRole != null) e.acteurRole!,
                        ].join('  •  '),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      if ((e.note ?? '').isNotEmpty)
                        Text(e.note!,
                            style: const TextStyle(
                                fontSize: 11.5, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ OUTILS UI

  Widget _carte({
    required String titre,
    required IconData icone,
    required List<Widget> enfants,
  }) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icone, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titre,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...enfants,
        ],
      ),
    );
  }

  Widget _sousTitre(String texte) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texte,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _ligne(String libelle, String valeur, {bool gras = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(libelle,
                style: const TextStyle(fontSize: 12.5, height: 1.3)),
          ),
          Expanded(
            flex: 5,
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: gras ? 14 : 13,
                fontWeight: gras ? FontWeight.w800 : FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
