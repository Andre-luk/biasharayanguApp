// lib/pages/entreprise_list_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';
import 'package:biashara_yangu/widgets/statut_abonnement_chip.dart';

/// Liste des entreprises avec recherche par nom et filtres
/// (ville / activité / statut).
class EntrepriseListPage extends StatefulWidget {
  const EntrepriseListPage({super.key, this.showAppBar = true});

  /// `false` lorsque la page est intégrée dans l'onglet de l'espace
  /// administrateur : l'`AppBar` est alors fournie par `AdminHomePage`.
  final bool showAppBar;

  @override
  State<EntrepriseListPage> createState() => _EntrepriseListPageState();
}

class _EntrepriseListPageState extends State<EntrepriseListPage> {
  final EntrepriseService _service = EntrepriseService.instance;
  final TextEditingController _rechercheController = TextEditingController();

  List<Entreprise> _entreprises = const <Entreprise>[];
  bool _chargement = true;
  String? _erreur;

  String? _filtreVilleId;
  String? _filtreActiviteId;
  StatutAbonnement? _filtreStatut;

  RealtimeChannel? _canalTempsReel;
  Timer? _antiRebondTempsReel;

  @override
  void initState() {
    super.initState();
    _rechercheController.addListener(_rafraichirRecherche);
    _demarrerEcouteTempsReel();
    _charger();
  }

  @override
  void dispose() {
    _antiRebondTempsReel?.cancel();

    final RealtimeChannel? canal = _canalTempsReel;
    if (canal != null) {
      // Libération du canal : sans cela, un abonnement reste actif à chaque
      // ouverture de l'écran.
      unawaited(_service.arreterEcoute(canal));
    }

    _rechercheController.removeListener(_rafraichirRecherche);
    _rechercheController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // TEMPS RÉEL
  // ---------------------------------------------------------------------------

  void _demarrerEcouteTempsReel() {
    try {
      _canalTempsReel = _service.ecouterChangements(_planifierRechargement);
    } catch (e) {
      // Le temps réel est un confort : son indisponibilité ne doit jamais
      // empêcher l'écran de fonctionner.
      debugPrint('EntrepriseListPage : temps réel indisponible ($e)');
    }
  }

  /// Regroupe une rafale d'événements en un seul rechargement.
  void _planifierRechargement() {
    _antiRebondTempsReel?.cancel();
    _antiRebondTempsReel = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _charger(silencieux: true);
    });
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  /// [silencieux] évite d'afficher l'écran de chargement lors d'un
  /// rafraîchissement de fond (retour depuis le détail, pull-to-refresh…).
  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    String? messageErreur;
    List<Entreprise> donnees = const <Entreprise>[];

    try {
      donnees = await _service.getEntreprises();
    } on EntrepriseServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('EntrepriseListPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des entreprises.';
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
      _entreprises = donnees;
      _erreur = null;
      _chargement = false;

      // Un filtre qui ne correspond plus à aucune entreprise chargée est
      // réinitialisé : évite une sélection fantôme dans les listes déroulantes.
      _filtreVilleId = _villeExiste(_filtreVilleId) ? _filtreVilleId : null;
      _filtreActiviteId =
          _activiteExiste(_filtreActiviteId) ? _filtreActiviteId : null;
    });
  }

  void _rafraichirRecherche() {
    if (!mounted) return;
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // FILTRAGE
  // ---------------------------------------------------------------------------

  List<Entreprise> get _entreprisesFiltrees {
    final String recherche = _rechercheController.text.trim().toLowerCase();

    return _entreprises.where((Entreprise entreprise) {
      if (_filtreVilleId != null && entreprise.villeId != _filtreVilleId) {
        return false;
      }
      if (_filtreActiviteId != null &&
          entreprise.activiteId != _filtreActiviteId) {
        return false;
      }
      if (_filtreStatut != null && entreprise.statut != _filtreStatut) {
        return false;
      }
      if (recherche.isNotEmpty &&
          !entreprise.nom.toLowerCase().contains(recherche)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  bool get _filtresActifs =>
      _filtreVilleId != null ||
      _filtreActiviteId != null ||
      _filtreStatut != null;

  bool _villeExiste(String? id) {
    if (id == null) return true;
    return _entreprises.any((Entreprise e) => e.villeId == id);
  }

  bool _activiteExiste(String? id) {
    if (id == null) return true;
    return _entreprises.any((Entreprise e) => e.activiteId == id);
  }

  void _reinitialiserFiltres() {
    _rechercheController.clear();
    setState(() {
      _filtreVilleId = null;
      _filtreActiviteId = null;
      _filtreStatut = null;
    });
  }

  /// Villes proposées en filtre : uniquement celles réellement présentes dans
  /// les entreprises chargées, ce qui évite les filtres qui ne renvoient rien.
  List<DropdownMenuItem<String?>> get _itemsVilles {
    final Map<String, String> parId = <String, String>{};
    for (final Entreprise entreprise in _entreprises) {
      final String? id = entreprise.villeId;
      if (id != null) {
        parId[id] = entreprise.villeNom ?? 'Ville inconnue';
      }
    }

    final List<String> ids = parId.keys.toList()
      ..sort((String a, String b) => parId[a]!.compareTo(parId[b]!));

    return <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
          value: null, child: Text('Toutes les villes')),
      ...ids.map(
        (String id) => DropdownMenuItem<String?>(
          value: id,
          child: Text(parId[id]!, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
  }

  /// Activités proposées en filtre (même logique que [_itemsVilles]).
  List<DropdownMenuItem<String?>> get _itemsActivites {
    final Map<String, String> parId = <String, String>{};
    for (final Entreprise entreprise in _entreprises) {
      final String? id = entreprise.activiteId;
      if (id != null) {
        parId[id] = entreprise.activiteNom ?? 'Activité inconnue';
      }
    }

    final List<String> ids = parId.keys.toList()
      ..sort((String a, String b) => parId[a]!.compareTo(parId[b]!));

    return <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
          value: null, child: Text('Toutes les activités')),
      ...ids.map(
        (String id) => DropdownMenuItem<String?>(
          value: id,
          child: Text(parId[id]!, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
  }

  List<DropdownMenuItem<StatutAbonnement?>> get _itemsStatuts {
    return <DropdownMenuItem<StatutAbonnement?>>[
      const DropdownMenuItem<StatutAbonnement?>(
          value: null, child: Text('Tous les statuts')),
      ...StatutAbonnement.statutsFiltrables.map(
        (StatutAbonnement statut) => DropdownMenuItem<StatutAbonnement?>(
          value: statut,
          child: Text(statut.libelle,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirCreation() async {
    final GoRouter router = GoRouter.of(context);
    final bool? cree = await router.push<bool>('/admin/entreprises/new');

    if (!mounted || cree != true) return;

    _afficherMessage('Entreprise créée avec succès.');
    await _charger(silencieux: true);
  }

  Future<void> _ouvrirDetail(Entreprise entreprise) async {
    final GoRouter router = GoRouter.of(context);
    await router.push<bool>(
      '/admin/entreprises/${entreprise.id}',
      extra: entreprise,
    );

    // Le détail a pu suspendre / activer l'entreprise : on rafraîchit sans
    // réafficher l'écran de chargement complet.
    if (!mounted) return;
    await _charger(silencieux: true);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text(
                'Entreprises',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              actions: [
                IconButton(
                  onPressed: () => _charger(),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Actualiser',
                ),
              ],
            )
          : null,
      floatingActionButton: PermissionGate(
        page: PageAccess.entreprises,
        action: ActionAccess.creer,
        child: FloatingActionButton.extended(
          onPressed: _ouvrirCreation,
          icon: const Icon(Icons.add_business_rounded),
          label: const Text('Nouvelle entreprise'),
        ),
      ),
      body: _construireCorps(theme),
    );
  }

  Widget _construireCorps(ThemeData theme) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreur != null) {
      return _vueErreur(theme);
    }

    final List<Entreprise> resultats = _entreprisesFiltrees;

    return Column(
      children: [
        _barreRechercheEtFiltres(theme),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${resultats.length} entreprise${resultats.length > 1 ? 's' : ''} affichée${resultats.length > 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _charger(),
            color: theme.colorScheme.primary,
            child: _liste(resultats),
          ),
        ),
      ],
    );
  }

  Widget _barreRechercheEtFiltres(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _rechercheController,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Rechercher une entreprise',
              hintText: 'Nom de l\'entreprise',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _rechercheController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Effacer la recherche',
                      onPressed: () => _rechercheController.clear(),
                    ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          // Défilement horizontal : garantit qu'aucun libellé ne déborde,
          // quelle que soit la largeur de l'écran.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  width: 160,
                  child: AppDropdownField<String?>(
                    label: 'Ville',
                    value: _filtreVilleId,
                    hint: 'Toutes les villes',
                    items: _itemsVilles,
                    onChanged: (String? valeur) =>
                        setState(() => _filtreVilleId = valeur),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 160,
                  child: AppDropdownField<String?>(
                    label: 'Activité',
                    value: _filtreActiviteId,
                    hint: 'Toutes les activités',
                    items: _itemsActivites,
                    onChanged: (String? valeur) =>
                        setState(() => _filtreActiviteId = valeur),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 190,
                  child: AppDropdownField<StatutAbonnement?>(
                    label: 'Statut',
                    value: _filtreStatut,
                    hint: 'Tous les statuts',
                    items: _itemsStatuts,
                    onChanged: (StatutAbonnement? valeur) =>
                        setState(() => _filtreStatut = valeur),
                  ),
                ),
              ],
            ),
          ),
          if (_filtresActifs)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _reinitialiserFiltres,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Réinitialiser les filtres'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _liste(List<Entreprise> resultats) {
    if (resultats.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 40),
          _etatVide(),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: resultats.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) =>
          _carteEntreprise(resultats[index]),
    );
  }

  Widget _carteEntreprise(Entreprise entreprise) {
    final ThemeData theme = Theme.of(context);

    final String localisation = <String>[
      if ((entreprise.villeNom ?? '').isNotEmpty) entreprise.villeNom!,
      if ((entreprise.activiteNom ?? '').isNotEmpty) entreprise.activiteNom!,
    ].join(' • ');

    final Color couleurSolde = entreprise.estSolde
        ? Colors.green.shade700
        : Colors.deepOrange.shade700;

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _ouvrirDetail(entreprise),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.business_rounded,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entreprise.nom.isEmpty
                          ? 'Entreprise sans nom'
                          : entreprise.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      localisation.isEmpty
                          ? 'Ville et activité non renseignées'
                          : localisation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        StatutAbonnementChip(
                            statut: entreprise.statutEffectif, compact: true),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Solde : ${formatMontant(entreprise.soldeRestant)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: couleurSolde,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 13,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _etatVide() {
    final ThemeData theme = Theme.of(context);
    final bool rechercheActive =
        _rechercheController.text.trim().isNotEmpty || _filtresActifs;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Icon(Icons.business_outlined,
              size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            rechercheActive
                ? 'Aucune entreprise ne correspond à votre recherche.'
                : 'Aucune entreprise enregistrée pour le moment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Appuyez sur « Nouvelle entreprise » pour en ajouter une.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
          ),
        ],
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
            Icon(Icons.cloud_off_rounded,
                size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Chargement impossible',
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
          ],
        ),
      ),
    );
  }
}
