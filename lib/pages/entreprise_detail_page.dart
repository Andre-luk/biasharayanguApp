// lib/pages/entreprise_detail_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/fonctionnalites.dart';
import 'package:biashara_yangu/models/paiement_abonnement.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/models/utilisateur_entreprise.dart';
import 'package:biashara_yangu/services/abonnement_niveaux_service.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/statut_abonnement_chip.dart';

/// Fiche détaillée d'une entreprise : informations générales, état de
/// l'abonnement et actions de gestion (modifier / suspendre / activer).
class EntrepriseDetailPage extends StatefulWidget {
  const EntrepriseDetailPage({super.key, this.entreprise, this.entrepriseId});

  /// Entreprise transmise par l'écran liste (évite un aller-retour réseau).
  final Entreprise? entreprise;

  /// Identifiant, utilisé lorsque l'écran est ouvert par URL directe.
  final String? entrepriseId;

  @override
  State<EntrepriseDetailPage> createState() => _EntrepriseDetailPageState();
}

class _EntrepriseDetailPageState extends State<EntrepriseDetailPage> {
  final EntrepriseService _service = EntrepriseService.instance;

  Entreprise? _entreprise;
  bool _chargement = false;
  bool _actionEnCours = false;
  String? _erreur;

  List<PaiementAbonnement> _paiements = const <PaiementAbonnement>[];
  Set<String> _utilisateursRattaches = <String>{};

  @override
  void initState() {
    super.initState();
    _entreprise = widget.entreprise;

    if (_entreprise == null) {
      _charger();
    }
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

    Entreprise? resultat;
    List<PaiementAbonnement> paiements = const <PaiementAbonnement>[];
    Set<String> rattaches = <String>{};
    String? messageErreur;

    try {
      resultat = await _service.getEntrepriseById(id);

      if (resultat == null) {
        messageErreur =
            'Cette entreprise est introuvable. Elle a peut-être été supprimée.';
      } else {
        // Historique et rattachement : best-effort côté service, ces appels ne
        // font jamais échouer l'affichage de la fiche.
        final List<dynamic> complement = await Future.wait<dynamic>([
          _service.getPaiements(id),
          _service.getUtilisateursRattaches(id),
        ]);

        paiements = complement[0] as List<PaiementAbonnement>;
        rattaches = complement[1] as Set<String>;
      }
    } on EntrepriseServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('EntrepriseDetailPage._charger: $e\n$st');
      messageErreur = 'Une erreur inattendue est survenue lors du chargement.';
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
      _entreprise = resultat;
      _paiements = paiements;
      _utilisateursRattaches = rattaches;
      _erreur = null;
      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirModification() async {
    final Entreprise? entreprise = _entreprise;
    if (entreprise == null) return;

    final GoRouter router = GoRouter.of(context);
    final bool? enregistre = await router.push<bool>(
      '/admin/entreprises/${entreprise.id}/edit',
      extra: entreprise,
    );

    if (!mounted || enregistre != true) return;

    _afficherMessage('Entreprise modifiée avec succès.');
    await _charger(silencieux: true);
  }

  /// 💳 MODULE 3 — Ouvre le détail d'abonnement du moteur d'abonnement
  /// (paiements typés, renouvellement, historique de la table La Perle).
  /// 🔒 CORRECTIF 63 — l'AGENT DE TERRAIN ne suspend ni ne réactive un compte.
  ///
  /// La base le refuse désormais (policies restrictives + déclencheur sur le
  /// statut) ; on masque donc le bouton pour ne pas lui infliger un refus
  /// incompréhensible. Les autres rôles — plateforme et patron — le gardent.
  bool get _peutSuspendre => !PermissionService.instance.estAgentTerrain;

  Future<void> _ouvrirAbonnement() async {
    final Entreprise? entreprise = _entreprise;
    if (entreprise == null) return;

    final GoRouter router = GoRouter.of(context);
    await router.push<void>(
      '/admin/abonnements/${entreprise.id}',
      extra: entreprise,
    );

    // Un paiement a pu changer le statut : on rafraîchit la fiche.
    if (!mounted) return;
    await _charger(silencieux: true);
  }

  Future<void> _basculerStatut() async {
    final Entreprise? entreprise = _entreprise;
    if (entreprise == null) return;

    final bool versSuspension = !entreprise.estSuspendue;
    final StatutAbonnement nouveauStatut =
        versSuspension ? StatutAbonnement.suspendu : StatutAbonnement.actif;

    final bool confirme =
        await _confirmerChangementStatut(entreprise, versSuspension);
    if (!mounted || !confirme) return;

    setState(() => _actionEnCours = true);

    String? messageErreur;
    try {
      await _service.changerStatut(id: entreprise.id, statut: nouveauStatut);
    } on EntrepriseServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('EntrepriseDetailPage._basculerStatut: $e\n$st');
      messageErreur =
          "Une erreur inattendue est survenue lors du changement de statut.";
    }

    if (!mounted) return;

    if (messageErreur != null) {
      setState(() => _actionEnCours = false);
      _afficherMessage(messageErreur, estErreur: true);
      return;
    }

    // Mise à jour immédiate de l'affichage, puis resynchronisation avec la base
    // (le serveur peut compléter `updated_at`).
    setState(() {
      _entreprise = entreprise.copyWith(statut: nouveauStatut);
    });
    _afficherMessage(
        versSuspension ? 'Entreprise suspendue.' : 'Entreprise activée.');

    await _charger(silencieux: true);
    if (mounted) setState(() => _actionEnCours = false);
  }

  Future<bool> _confirmerChangementStatut(
    Entreprise entreprise,
    bool versSuspension,
  ) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(
            versSuspension
                ? "Suspendre l'entreprise ?"
                : "Activer l'entreprise ?",
          ),
          content: Text(
            versSuspension
                ? "L'entreprise « ${entreprise.nom} » sera suspendue. Ses utilisateurs "
                    "perdront l'accès à l'application jusqu'à sa réactivation."
                : "L'entreprise « ${entreprise.nom} » sera réactivée et passera au "
                    'statut ACTIF. Ses dates d\'activation et d\'expiration restent '
                    'inchangées.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                versSuspension ? 'Suspendre' : 'Activer',
                style: TextStyle(
                  color: versSuspension
                      ? Colors.orange.shade800
                      : Colors.green.shade700,
                ),
              ),
            ),
          ],
        );
      },
    );

    return confirme ?? false;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Détail de l'entreprise",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          // 💳 MODULE 3 — Accès au détail d'abonnement du moteur (paiements
          // typés, renouvellement, historique du moteur).
          IconButton(
            onPressed:
                _entreprise == null ? null : () => _ouvrirAbonnement(),
            icon: const Icon(Icons.card_membership_rounded),
            tooltip: "Détail de l'abonnement",
          ),
          IconButton(
            onPressed: () => _charger(silencieux: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _construireCorps(theme, entreprise),
    );
  }

  Widget _construireCorps(ThemeData theme, Entreprise? entreprise) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreur != null || entreprise == null) {
      return _vueErreur(theme);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _entete(theme, entreprise),
          const SizedBox(height: 16),
          _carteInformations(theme, entreprise),
          const SizedBox(height: 16),
          _carteAbonnement(theme, entreprise),
          const SizedBox(height: 16),
          //  🧩 CORRECTIF 65 — ce que cette entreprise peut VOIR : son niveau
          //  d'abonnement et les fonctionnalités réellement appliquées.
          _carteNiveau(theme, entreprise),
          const SizedBox(height: 16),
          _cartePaiements(theme),
          const SizedBox(height: 16),
          _carteUtilisateurs(theme),
          const SizedBox(height: 20),
          _actions(entreprise),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _entete(ThemeData theme, Entreprise entreprise) {
    final String localisation = <String>[
      if ((entreprise.villeNom ?? '').isNotEmpty) entreprise.villeNom!,
      if ((entreprise.activiteNom ?? '').isNotEmpty) entreprise.activiteNom!,
    ].join(' • ');

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
                    Icons.business_rounded,
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
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        localisation.isEmpty
                            ? 'Ville et activité non renseignées'
                            : localisation,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            StatutAbonnementChip(statut: entreprise.statutEffectif),
          ],
        ),
      ),
    );
  }

  Widget _carteInformations(ThemeData theme, Entreprise entreprise) {
    return _carte(
      theme: theme,
      titre: 'Informations',
      icone: Icons.info_outline_rounded,
      enfants: [
        _ligneInfo('Ville', entreprise.villeNom ?? 'Non renseignée'),
        _ligneInfo('Activité', entreprise.activiteNom ?? 'Non renseignée'),
        _ligneInfo(
          'Groupe tarifaire',
          entreprise.groupeTarifaireNom ?? 'Non renseigné',
        ),
        _ligneInfo("Date d'enregistrement", formatDate(entreprise.createdAt)),
        _ligneInfo(
            'Dernière modification', formatDateHeure(entreprise.updatedAt)),
      ],
    );
  }

  /// 💰 CORRECTIF 60 — réglage des DEUX prix de l'abonnement d'une entreprise.
  ///
  /// Le prix d'installation comprend le premier mois ; les renouvellements
  /// facturent le prix mensuel seul. Sans ces deux valeurs, le moteur ne peut
  /// pas détecter qu'il s'apprête à refacturer une installation — c'est ce
  /// qui est arrivé à Biashara Group.
  Future<void> _modifierPrix(
    ThemeData theme,
    Entreprise entreprise,
    PrixAbonnement? prix,
  ) async {
    final TextEditingController installation = TextEditingController(
      text: prix?.installation == null
          ? ''
          : prix!.installation!.round().toString(),
    );
    final TextEditingController mensuel = TextEditingController(
      text: prix?.mensuel == null ? '' : prix!.mensuel!.round().toString(),
    );

    final bool? enregistrer = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Prix de l\'abonnement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Le prix d\'installation comprend le premier mois. Les '
              'renouvellements facturent le prix mensuel. Laisser un champ '
              'vide ne le modifie pas.',
              style: TextStyle(fontSize: 12.5, height: 1.3),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: installation,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Prix d\'installation (CDF)',
                helperText: 'Premier mois inclus',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mensuel,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Prix mensuel (CDF)',
                helperText: 'Appliqué au renouvellement',
                border: OutlineInputBorder(),
              ),
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
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    final double? nouvelleInstallation = _lireMontant(installation.text);
    final double? nouveauMensuel = _lireMontant(mensuel.text);

    installation.dispose();
    mensuel.dispose();

    if (enregistrer != true) return;

    try {
      await NiveauxAbonnementService.instance.definirPrix(
        entrepriseId: entreprise.id,
        installation: nouvelleInstallation,
        mensuel: nouveauMensuel,
        note: 'Prix fixés depuis la fiche entreprise',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prix de l\'abonnement enregistrés.'),
          duration: Duration(seconds: 3),
        ),
      );
      await _charger(silencieux: true);
    } on NiveauxAbonnementException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Montant saisi, ou `null` si le champ est vide (⇒ prix inchangé).
  static double? _lireMontant(String texte) {
    final String propre =
        texte.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (propre.isEmpty) return null;
    return double.tryParse(propre);
  }

  Widget _carteAbonnement(ThemeData theme, Entreprise entreprise) {
    final Color couleurSolde = entreprise.estSolde
        ? Colors.green.shade700
        : Colors.deepOrange.shade700;

    return _carte(
      theme: theme,
      titre: 'Abonnement',
      icone: Icons.card_membership_rounded,
      enfants: [
        _ligneInfo('Statut actuel', entreprise.statutEffectif.libelle),
        if (entreprise.statutDesynchronise)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Statut enregistré en base : « ${entreprise.statut.libelle} ». '
              'Il sera automatiquement basculé en « Expiré » par la base de données.',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const Divider(height: 22),
        _ligneInfo(
          'Montant total dû',
          formatMontant(entreprise.montantTotalDu),
        ),
        _ligneInfo(
          'Montant déjà payé',
          formatMontant(entreprise.montantDejaPaye),
          couleurValeur: Colors.green.shade700,
        ),
        _ligneInfo(
          'Solde restant',
          formatMontant(entreprise.soldeRestant),
          couleurValeur: couleurSolde,
          gras: true,
        ),

        //  💰 CORRECTIF 60-62 — LES DEUX PRIX de l'abonnement. Le premier
        //  cycle facture l'installation (premier mois inclus), les suivants
        //  facturent le mensuel seul.
        const Divider(height: 22),
        FutureBuilder<PrixAbonnement>(
          future: NiveauxAbonnementService.instance.lirePrix(entreprise.id),
          builder: (BuildContext ctx, AsyncSnapshot<PrixAbonnement> snap) {
            final PrixAbonnement? prix = snap.data;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ligneInfo(
                  'Prix d\'installation',
                  prix?.installation == null
                      ? 'non renseigné'
                      : formatMontant(prix!.installation!),
                ),
                _ligneInfo(
                  'Prix mensuel',
                  prix?.mensuel == null
                      ? 'non renseigné'
                      : formatMontant(prix!.mensuel!),
                ),
                if (prix != null && prix.vide && !snap.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Aucun prix propre : le prochain renouvellement '
                      'retiendra le montant encaissé.',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _modifierPrix(theme, entreprise, prix),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Modifier les prix'),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: entreprise.tauxPaiement,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: entreprise.estSolde
                ? Colors.green.shade600
                : theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${(entreprise.tauxPaiement * 100).round()} % de l\'abonnement réglé',
          style: TextStyle(
              fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
        ),
        const Divider(height: 22),
        _ligneInfo("Date d'activation", formatDate(entreprise.dateActivation)),
        _ligneInfo("Date d'expiration", formatDate(entreprise.dateExpiration)),
        _ligneInfo(
          'Jours restants',
          _libelleJoursRestants(entreprise),
          couleurValeur: _couleurJoursRestants(entreprise),
          gras: true,
        ),
      ],
    );
  }

  Widget _actions(Entreprise entreprise) {
    final bool desactive = _actionEnCours;
    final bool estSuspendue = entreprise.estSuspendue;
    final bool solde = entreprise.estSolde;

    return Column(
      children: [
        FilledButton.icon(
          onPressed: desactive || solde ? null : _ouvrirEncaissement,
          icon: const Icon(Icons.payments_rounded),
          label: Text(
            solde ? 'Abonnement entièrement réglé' : 'Encaisser un paiement',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: desactive ? null : _ouvrirModification,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Modifier'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    (desactive || !_peutSuspendre) ? null : _basculerStatut,
                icon: desactive
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(estSuspendue
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded),
                label: Text(estSuspendue ? 'Activer' : 'Suspendre'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: estSuspendue
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ENCAISSEMENT
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirEncaissement() async {
    final Entreprise? entreprise = _entreprise;
    if (entreprise == null) return;

    final bool? enregistre = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) =>
          _FeuilleEncaissement(entreprise: entreprise),
    );

    if (!mounted || enregistre != true) return;

    _afficherMessage('Paiement enregistré avec succès.');
    await _charger(silencieux: true);
  }

  /// Historique des encaissements, du plus récent au plus ancien.
  Widget _cartePaiements(ThemeData theme) {
    final List<PaiementAbonnement> paiements = _paiements;

    return _carte(
      theme: theme,
      titre: 'Historique des paiements',
      icone: Icons.history_rounded,
      enfants: [
        if (paiements.isEmpty)
          Text(
            'Aucun encaissement enregistré pour le moment.',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...paiements.map(
            (PaiementAbonnement paiement) => _lignePaiement(theme, paiement),
          ),
      ],
    );
  }

  Widget _lignePaiement(ThemeData theme, PaiementAbonnement paiement) {
    final String auteur = paiement.enregistreParNom ?? 'Auteur inconnu';
    final double? soldeApres = paiement.soldeApres;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded,
              size: 18, color: Colors.green.shade700),
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
                    if (soldeApres != null)
                      Text(
                        'reste ${formatMontant(soldeApres)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDateHeure(paiement.createdAt)} • $auteur',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (paiement.aProlonge)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'Abonnement prolongé de ${paiement.prolongationJours} '
                      'jour${paiement.prolongationJours > 1 ? 's' : ''}',
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

  /// Utilisateurs rattachés : conditionne le blocage de l'accès à la connexion
  /// lorsque l'entreprise est suspendue ou expirée.
  Widget _carteUtilisateurs(ThemeData theme) {
    final int nombre = _utilisateursRattaches.length;

    return _carte(
      theme: theme,
      titre: 'Utilisateurs rattachés',
      icone: Icons.people_alt_rounded,
      enfants: [
        Text(
          nombre == 0
              ? "Aucun utilisateur n'est rattaché à cette entreprise. Tant "
                  "qu'aucun rattachement n'existe, les utilisateurs ne sont "
                  'jamais bloqués.'
              : '$nombre utilisateur${nombre > 1 ? 's' : ''} rattaché'
                  "${nombre > 1 ? 's' : ''} à cette entreprise.",
          style: TextStyle(
            fontSize: 12.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _actionEnCours ? null : _ouvrirRattachement,
          icon: const Icon(Icons.manage_accounts_rounded, size: 18),
          label: const Text('Gérer les utilisateurs'),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _ouvrirRattachement() async {
    final Entreprise? entreprise = _entreprise;
    if (entreprise == null) return;

    final bool? modifie = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => _FeuilleRattachement(
        entreprise: entreprise,
        rattachesInitiaux: _utilisateursRattaches,
      ),
    );

    if (!mounted || modifie != true) return;

    await _charger(silencieux: true);
  }

  /// 🧩 CORRECTIF 65 — niveau d'abonnement : ce que cette entreprise voit.
  ///
  /// Affiche les fonctionnalités RÉELLEMENT appliquées (résolues côté
  /// serveur) et permet d'ouvrir l'écran de réglage. Rappel affiché : aucune
  /// restriction = tout reste visible.
  Widget _carteNiveau(ThemeData theme, Entreprise entreprise) {
    return FutureBuilder<NiveauEntreprise>(
      future: NiveauxAbonnementService.instance
          .lireNiveauEntreprise(entreprise.id),
      builder: (BuildContext ctx, AsyncSnapshot<NiveauEntreprise> snap) {
        final List<Widget> enfants = <Widget>[];

        if (snap.connectionState != ConnectionState.done) {
          enfants.add(const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          ));
        } else if (snap.hasError || snap.data == null) {
          //  Best-effort : une lecture impossible ne doit jamais gêner cette
          //  fiche — et surtout pas laisser croire à une restriction.
          enfants.add(const Text(
            'Niveau indisponible pour le moment. Aucune restriction n\'est '
            'appliquée.',
            style: TextStyle(fontSize: 12.5, height: 1.3),
          ));
        } else {
          final NiveauEntreprise etat = snap.data!;
          final Set<String>? effectifs = etat.modulesEffectifs;

          if (etat.sansRestriction) {
            enfants.add(const Text(
              'Aucune restriction : toutes les fonctionnalités restent '
              'visibles.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ));
          } else if (effectifs!.contains(Fonctionnalites.joker)) {
            enfants.add(const Text(
              'Toutes les fonctionnalités de l\'activité.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ));
          } else {
            enfants.add(Text(
              '${effectifs.length} fonctionnalité'
              '${effectifs.length > 1 ? 's' : ''} ouverte'
              '${effectifs.length > 1 ? 's' : ''}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ));
            enfants.add(const SizedBox(height: 4));
            enfants.add(Text(
              effectifs
                  .map((String code) => Fonctionnalites.libelleDe(code))
                  .join(' · '),
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ));
          }

          enfants.add(const SizedBox(height: 8));
          enfants.add(Text(
            etat.niveau == null
                ? 'Aucun niveau imposé : celui du pack tarifaire s\'applique.'
                : 'Niveau imposé : ${etat.niveau}'
                    '${etat.negocie ? ' · fonctionnalités négociées' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ));
        }

        enfants.add(const SizedBox(height: 12));
        enfants.add(Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              final bool? modifie = await ctx.push<bool>(
                '/entreprise/${entreprise.id}/niveau',
              );
              if (modifie == true) await _charger(silencieux: true);
            },
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Changer le niveau'),
          ),
        ));

        return _carte(
          theme: theme,
          titre: 'Niveau d\'abonnement',
          icone: Icons.workspace_premium_outlined,
          enfants: enfants,
        );
      },
    );
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
                  fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
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

  String _libelleJoursRestants(Entreprise entreprise) {
    final int? jours = entreprise.joursRestants;

    if (jours == null) {
      return 'Non planifiée';
    }
    if (jours < 0) {
      return 'Expiré depuis ${-jours} jour${-jours > 1 ? 's' : ''}';
    }
    if (jours == 0) {
      return "Expire aujourd'hui";
    }
    return '$jours jour${jours > 1 ? 's' : ''} restant${jours > 1 ? 's' : ''}';
  }

  Color _couleurJoursRestants(Entreprise entreprise) {
    final int? jours = entreprise.joursRestants;

    if (jours == null) {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }
    if (jours < 0) {
      return Colors.red.shade700;
    }
    if (jours <= 3) {
      return Colors.orange.shade800;
    }
    return Colors.green.shade700;
  }

  Widget _vueErreur(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Entreprise indisponible',
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
              child: const Text('Retour à la liste'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Feuille modale d'encaissement d'un paiement d'abonnement.
///
/// N'agit que sur `montant_deja_paye` et `solde_restant` : ni le statut, ni les
/// dates de l'abonnement ne sont modifiés.
class _FeuilleEncaissement extends StatefulWidget {
  const _FeuilleEncaissement({required this.entreprise});

  final Entreprise entreprise;

  @override
  State<_FeuilleEncaissement> createState() => _FeuilleEncaissementState();
}

class _FeuilleEncaissementState extends State<_FeuilleEncaissement> {
  final EntrepriseService _service = EntrepriseService.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _montantController;

  bool _enregistrement = false;
  late bool _prolonger;

  @override
  void initState() {
    super.initState();

    // Préremplissage avec le solde restant : le règlement intégral est le cas
    // le plus fréquent.
    final double solde = widget.entreprise.soldeRestant;
    _montantController = TextEditingController(
      text: solde > 0 ? solde.toStringAsFixed(0) : '',
    );
    _montantController.addListener(_rafraichirApercu);

    // La prolongation est proposée par défaut dès que la grille tarifaire
    // indique une durée d'abonnement : c'est le cas nominal d'un encaissement.
    _prolonger = (widget.entreprise.groupeTarifaireDureeJours ?? 0) > 0;
  }

  @override
  void dispose() {
    _montantController.removeListener(_rafraichirApercu);
    _montantController.dispose();
    super.dispose();
  }

  void _rafraichirApercu() {
    if (!mounted) return;
    setState(() {});
  }

  /// Accepte « 15 000 », « 15000 » et « 15000,50 ».
  double? _analyserMontant(String texte) {
    final String nettoye = texte
        .replaceAll(' ', '')
        .replaceAll('\u00A0', '')
        .replaceAll('\u202F', '')
        .replaceAll(',', '.');

    if (nettoye.isEmpty) return null;
    return double.tryParse(nettoye);
  }

  double get _montantSaisi => _analyserMontant(_montantController.text) ?? 0;

  Future<void> _enregistrer() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _enregistrement = true);

    String? messageErreur;
    try {
      await _service.enregistrerPaiement(
        entreprise: widget.entreprise,
        montant: _montantSaisi,
        prolonger: _prolonger,
      );
    } on EntrepriseServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('_FeuilleEncaissement._enregistrer: $e\n$st');
      messageErreur =
          "Une erreur inattendue est survenue lors de l'encaissement.";
    }

    if (!mounted) return;

    if (messageErreur == null) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() => _enregistrement = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(messageErreur),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double solde = widget.entreprise.soldeRestant;
    final double montant = _montantSaisi;
    final double nouveauSolde = solde - montant;
    final bool montantValide = montant > 0 && montant <= solde + 0.001;
    final int dureeProlongation =
        widget.entreprise.groupeTarifaireDureeJours ?? 0;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.payments_rounded,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Encaisser un paiement',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.entreprise.nom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Divider(height: 24),
              _ligneRecap(
                'Montant total dû',
                formatMontant(widget.entreprise.montantTotalDu),
              ),
              _ligneRecap(
                'Déjà payé',
                formatMontant(widget.entreprise.montantDejaPaye),
              ),
              _ligneRecap('Solde restant', formatMontant(solde), accent: true),
              const SizedBox(height: 18),
              TextFormField(
                controller: _montantController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Montant encaissé *',
                  suffixText: deviseParDefaut,
                  prefixIcon: const Icon(Icons.attach_money_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (String? valeur) {
                  final String texte = (valeur ?? '').trim();
                  if (texte.isEmpty) {
                    return 'Veuillez saisir le montant encaissé.';
                  }

                  final double? analyse = _analyserMontant(texte);
                  if (analyse == null) {
                    return 'Montant invalide : utilisez uniquement des chiffres.';
                  }
                  if (analyse <= 0) {
                    return 'Le montant doit être supérieur à zéro.';
                  }
                  if (analyse > solde + 0.001) {
                    return 'Le montant dépasse le solde restant '
                        '(${formatMontant(solde)}).';
                  }
                  return null;
                },
              ),
              if (montantValide) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _ligneRecap('Montant encaissé', formatMontant(montant)),
                      const SizedBox(height: 6),
                      _ligneRecap(
                        'Nouveau solde restant',
                        formatMontant(nouveauSolde > 0 ? nouveauSolde : 0),
                        accent: true,
                      ),
                    ],
                  ),
                ),
              ],
              if (dureeProlongation > 0)
                CheckboxListTile(
                  value: _prolonger,
                  onChanged: _enregistrement
                      ? null
                      : (bool? valeur) =>
                          setState(() => _prolonger = valeur ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    "Prolonger l'abonnement de $dureeProlongation "
                    "jour${dureeProlongation > 1 ? 's' : ''}",
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _prolonger
                        ? "Le statut passera à « Actif » et la date d'expiration "
                            'sera repoussée depuis aujourd\'hui (ou depuis la date '
                            "d'expiration si elle est encore future)."
                        : "L'abonnement ne sera pas prolongé : seul le solde est "
                            'mis à jour.',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _enregistrement
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _enregistrement || !montantValide
                          ? null
                          : _enregistrer,
                      icon: _enregistrement
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                          _enregistrement ? 'Enregistrement...' : 'Encaisser'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ligneRecap(String libelle, String valeur, {bool accent = false}) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(libelle, style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Text(
          valeur,
          style: TextStyle(
            fontSize: 13,
            fontWeight: accent ? FontWeight.bold : FontWeight.w600,
            color: accent ? theme.colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}

/// Feuille modale de gestion des utilisateurs rattachés à une entreprise.
///
/// Le rattachement est enregistré immédiatement (pas de bouton « Enregistrer ») :
/// la liste est courte, l'action est réversible et l'interface reste réactive
/// grâce à une mise à jour optimiste annulée en cas d'échec.
class _FeuilleRattachement extends StatefulWidget {
  const _FeuilleRattachement({
    required this.entreprise,
    required this.rattachesInitiaux,
  });

  final Entreprise entreprise;
  final Set<String> rattachesInitiaux;

  @override
  State<_FeuilleRattachement> createState() => _FeuilleRattachementState();
}

class _FeuilleRattachementState extends State<_FeuilleRattachement> {
  final EntrepriseService _service = EntrepriseService.instance;

  late Set<String> _rattaches;
  List<UtilisateurEntreprise> _utilisateurs = const <UtilisateurEntreprise>[];
  bool _chargement = true;
  String? _erreur;
  bool _modifie = false;
  String _recherche = '';

  @override
  void initState() {
    super.initState();
    _rattaches = <String>{...widget.rattachesInitiaux};
    _charger();
  }

  Future<void> _charger() async {
    List<UtilisateurEntreprise> utilisateurs = const <UtilisateurEntreprise>[];
    String? erreur;

    try {
      utilisateurs = await _service.getUtilisateurs();
    } on EntrepriseServiceException catch (e) {
      erreur = e.message;
    } catch (e, st) {
      debugPrint('_FeuilleRattachement._charger: $e\n$st');
      erreur = 'Impossible de charger la liste des utilisateurs.';
    }

    if (!mounted) return;
    setState(() {
      _utilisateurs = utilisateurs;
      _erreur = erreur;
      _chargement = false;
    });
  }

  List<UtilisateurEntreprise> get _utilisateursFiltres {
    final String recherche = _recherche.trim().toLowerCase();
    if (recherche.isEmpty) {
      return _utilisateurs;
    }

    return _utilisateurs.where((UtilisateurEntreprise utilisateur) {
      return utilisateur.nomComplet.toLowerCase().contains(recherche) ||
          utilisateur.email.toLowerCase().contains(recherche);
    }).toList(growable: false);
  }

  /// Nom du patron d'un collaborateur, s'il fait partie de la liste chargée.
  String? _nomDuPatron(String? parentId) {
    if (parentId == null) return null;

    for (final UtilisateurEntreprise utilisateur in _utilisateurs) {
      if (utilisateur.id == parentId) return utilisateur.nomComplet;
    }
    return null;
  }

  Future<void> _basculer(
      UtilisateurEntreprise utilisateur, bool rattacher) async {
    final String userId = utilisateur.id;
    if (userId.isEmpty) return;

    _appliquer(userId, rattacher);

    try {
      if (rattacher) {
        await _service.rattacherUtilisateur(
          entrepriseId: widget.entreprise.id,
          userId: userId,
        );
      } else {
        await _service.detacherUtilisateur(userId: userId);
      }
      _modifie = true;
    } on EntrepriseServiceException catch (e) {
      if (!mounted) return;
      _appliquer(userId, !rattacher);
      _afficherErreur(e.message);
    } catch (e, st) {
      debugPrint('_FeuilleRattachement._basculer: $e\n$st');
      if (!mounted) return;
      _appliquer(userId, !rattacher);
      _afficherErreur('Une erreur inattendue est survenue.');
    }
  }

  /// Mise à jour optimiste de l'ensemble local (annulée si l'appel échoue).
  void _appliquer(String userId, bool rattacher) {
    if (!mounted) return;

    setState(() {
      if (rattacher) {
        _rattaches.add(userId);
      } else {
        _rattaches.remove(userId);
      }
    });
  }

  void _afficherErreur(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<UtilisateurEntreprise> filtres = _utilisateursFiltres;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.people_alt_rounded,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Utilisateurs rattachés',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.entreprise.nom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (String valeur) =>
                        setState(() => _recherche = valeur),
                    decoration: InputDecoration(
                      labelText: 'Rechercher un utilisateur',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Expanded(child: _corpsListe(theme, filtres)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_modifie),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Terminer'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _corpsListe(ThemeData theme, List<UtilisateurEntreprise> filtres) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 40, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _chargement = true);
                  _charger();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (filtres.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _utilisateurs.isEmpty
                ? 'Aucun utilisateur dans la base.'
                : 'Aucun utilisateur ne correspond à la recherche.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: filtres.length,
      itemBuilder: (BuildContext context, int index) {
        final UtilisateurEntreprise utilisateur = filtres[index];
        // `_rattaches` porte l'état optimiste : l'interface réagit
        // immédiatement, puis l'appel réseau confirme ou annule.
        final bool rattache = _rattaches.contains(utilisateur.id);
        final bool rattacheAilleurs =
            utilisateur.entrepriseId != null && !rattache;
        final String? nomPatron =
            rattacheAilleurs ? null : _nomDuPatron(utilisateur.parentId);

        // Tuile personnalisée plutôt que CheckboxListTile : le sous-titre peut
        // comporter jusqu'à trois lignes, ce que ListTile ne garantit pas.
        return InkWell(
          onTap: utilisateur.id.isEmpty
              ? null
              : () => _basculer(utilisateur, !rattache),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: rattache,
                  onChanged: utilisateur.id.isEmpty
                      ? null
                      : (bool? valeur) =>
                          _basculer(utilisateur, valeur ?? false),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          utilisateur.nomComplet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${utilisateur.email} • ${utilisateur.roleLibelle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (rattacheAilleurs)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Déjà rattaché à une autre entreprise',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        if (nomPatron != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Collaborateur de $nomPatron — hérite de son '
                              'entreprise',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
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
      },
    );
  }
}
