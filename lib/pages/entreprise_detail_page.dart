// lib/pages/entreprise_detail_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
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
    String? messageErreur;

    try {
      resultat = await _service.getEntrepriseById(id);
      if (resultat == null) {
        messageErreur =
            'Cette entreprise est introuvable. Elle a peut-être été supprimée.';
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
                onPressed: desactive ? null : _basculerStatut,
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
