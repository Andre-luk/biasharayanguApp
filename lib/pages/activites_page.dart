// lib/pages/activites_page.dart
//
// MODULE 2 — Liste des activités commerciales (`public.activites`).
//
// Chaque ligne affiche le nom, la description et le nombre d'éléments
// rattachés (entreprises / groupes tarifaires). Un appui ouvre le formulaire
// de modification ; le menu de chaque ligne propose aussi l'accès direct aux
// groupes tarifaires de l'activité et la suppression.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/activite.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/services/referentiel_service.dart';

class ActivitesPage extends StatefulWidget {
  const ActivitesPage({super.key});

  @override
  State<ActivitesPage> createState() => _ActivitesPageState();
}

class _ActivitesPageState extends State<ActivitesPage> {
  final ReferentielService _service = ReferentielService.instance;
  final TextEditingController _rechercheController = TextEditingController();

  List<Activite> _activites = const <Activite>[];
  Map<String, int> _groupesParActivite = <String, int>{};
  CompteursEntreprises _compteurs = const CompteursEntreprises.vide();

  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _rechercheController.addListener(_reagirSaisie);
    _charger();
  }

  @override
  void dispose() {
    _rechercheController.removeListener(_reagirSaisie);
    _rechercheController.dispose();
    super.dispose();
  }

  void _reagirSaisie() {
    if (!mounted) return;
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  /// [silencieux] évite l'écran de chargement complet lors d'un
  /// rafraîchissement de fond (retour depuis un formulaire, pull-to-refresh…).
  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    String? messageErreur;
    List<Activite> activites = const <Activite>[];
    Map<String, int> groupesParActivite = <String, int>{};
    CompteursEntreprises compteurs = const CompteursEntreprises.vide();

    try {
      final List<dynamic> resultats = await Future.wait<dynamic>(
        <Future<dynamic>>[
          _service.getActivites(),
          _service.getGroupesTarifaires(),
          _service.getCompteursEntreprises(),
        ],
      );

      activites = resultats[0] as List<Activite>;

      final List<GroupeTarifaire> groupes =
          resultats[1] as List<GroupeTarifaire>;
      final Map<String, int> comptes = <String, int>{};
      for (final GroupeTarifaire groupe in groupes) {
        final String? activiteId = groupe.activiteId;
        if (activiteId != null) {
          comptes[activiteId] = (comptes[activiteId] ?? 0) + 1;
        }
      }
      groupesParActivite = comptes;

      compteurs = resultats[2] as CompteursEntreprises;
    } on ReferentielServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ActivitesPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des activités.';
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
      _activites = activites;
      _groupesParActivite = groupesParActivite;
      _compteurs = compteurs;
      _erreur = null;
      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // FILTRAGE
  // ---------------------------------------------------------------------------

  List<Activite> get _activitesFiltrees {
    final String recherche = _rechercheController.text.trim().toLowerCase();
    if (recherche.isEmpty) return _activites;

    return _activites
        .where(
          (Activite activite) =>
              activite.nom.toLowerCase().contains(recherche) ||
              (activite.description ?? '').toLowerCase().contains(recherche),
        )
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirCreation() async {
    final GoRouter router = GoRouter.of(context);
    final bool? enregistre = await router.push<bool>('/admin/activites/new');

    if (!mounted || enregistre != true) return;
    await _charger(silencieux: true);
  }

  Future<void> _ouvrirModification(Activite activite) async {
    final GoRouter router = GoRouter.of(context);
    final bool? enregistre = await router.push<bool>(
      '/admin/activites/${activite.id}',
      extra: activite,
    );

    if (!mounted || enregistre != true) return;
    await _charger(silencieux: true);
  }

  /// Ouvre la liste des groupes tarifaires pré-filtrée sur cette activité.
  Future<void> _ouvrirGroupes(Activite activite) async {
    final GoRouter router = GoRouter.of(context);
    await router.push<void>(
      '/admin/groupes-tarifaires',
      extra: activite.id,
    );

    // Des groupes ont pu être ajoutés / supprimés : on rafraîchit les compteurs.
    if (!mounted) return;
    await _charger(silencieux: true);
  }

  // ---------------------------------------------------------------------------
  // SUPPRESSION
  // ---------------------------------------------------------------------------

  Future<void> _supprimer(Activite activite) async {
    final int nbEntreprises = _compteurs.pourActivite(activite.id);
    final int nbGroupes = _groupesParActivite[activite.id] ?? 0;

    // Élément encore utilisé : la suppression est bloquée, on explique pourquoi.
    if (nbEntreprises > 0 || nbGroupes > 0) {
      await _afficherSuppressionBloquee(activite, nbEntreprises, nbGroupes);
      return;
    }

    final bool confirme = await _confirmerSuppression(activite);
    if (!mounted || !confirme) return;

    String? messageErreur;
    try {
      await _service.supprimerActivite(activite.id);
    } on ReferentielServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ActivitesPage._supprimer: $e\n$st');
      messageErreur =
          "Une erreur inattendue est survenue lors de la suppression.";
    }

    if (!mounted) return;

    if (messageErreur != null) {
      _afficherMessage(messageErreur, estErreur: true);
      return;
    }

    _afficherMessage('Activité supprimée avec succès.');
    await _charger(silencieux: true);
  }

  Future<bool> _confirmerSuppression(Activite activite) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Supprimer cette activité ?'),
          content: Text(
            "L'activité « ${activite.nom} » sera définitivement supprimée.\n\n"
            'Cette action est irréversible.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Supprimer',
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          ],
        );
      },
    );

    return confirme ?? false;
  }

  Future<void> _afficherSuppressionBloquee(
    Activite activite,
    int nbEntreprises,
    int nbGroupes,
  ) {
    final List<String> raisons = <String>[
      if (nbGroupes > 0)
        '$nbGroupes groupe${nbGroupes > 1 ? 's' : ''} tarifaire'
            '${nbGroupes > 1 ? 's' : ''}',
      if (nbEntreprises > 0)
        '$nbEntreprises entreprise${nbEntreprises > 1 ? 's' : ''}',
    ];

    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Suppression impossible'),
          content: Text(
            "L'activité « ${activite.nom} » est encore utilisée :\n\n"
            '• ${raisons.join('\n• ')}\n\n'
            'Supprimez ou rattachez ces éléments à une autre activité avant '
            'de pouvoir la supprimer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Compris'),
            ),
          ],
        );
      },
    );
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
      appBar: AppBar(
        title: const Text(
          'Activités',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ouvrirCreation,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle activité'),
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

    final List<Activite> resultats = _activitesFiltrees;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _rechercheController,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Rechercher une activité',
              hintText: 'Nom ou description',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _rechercheController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Effacer la recherche',
                      onPressed: () => _rechercheController.clear(),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${resultats.length} activité${resultats.length > 1 ? 's' : ''} '
              'affichée${resultats.length > 1 ? 's' : ''}',
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

  Widget _liste(List<Activite> resultats) {
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
          _carteActivite(resultats[index]),
    );
  }

  Widget _carteActivite(Activite activite) {
    final ThemeData theme = Theme.of(context);
    final int nbEntreprises = _compteurs.pourActivite(activite.id);
    final int nbGroupes = _groupesParActivite[activite.id] ?? 0;
    final String? description = activite.description;

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _ouvrirModification(activite),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.storefront_rounded,
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
                      activite.nom.isEmpty ? 'Activité sans nom' : activite.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _puce(
                          theme,
                          Icons.business_rounded,
                          '$nbEntreprises entreprise'
                          '${nbEntreprises > 1 ? 's' : ''}',
                        ),
                        _puce(
                          theme,
                          Icons.sell_rounded,
                          '$nbGroupes groupe${nbGroupes > 1 ? 's' : ''} '
                          'tarifaire${nbGroupes > 1 ? 's' : ''}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (String action) {
                  switch (action) {
                    case 'modifier':
                      _ouvrirModification(activite);
                      break;
                    case 'groupes':
                      _ouvrirGroupes(activite);
                      break;
                    case 'supprimer':
                      _supprimer(activite);
                      break;
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'modifier',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Modifier'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'groupes',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.sell_outlined),
                      title: Text('Groupes tarifaires'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'supprimer',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade700,
                      ),
                      title: Text(
                        'Supprimer',
                        style: TextStyle(color: Colors.red.shade700),
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

  Widget _puce(ThemeData theme, IconData icone, String libelle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            libelle,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _etatVide() {
    final ThemeData theme = Theme.of(context);
    final bool rechercheActive = _rechercheController.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            rechercheActive
                ? 'Aucune activité ne correspond à votre recherche.'
                : 'Aucune activité enregistrée pour le moment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Appuyez sur « Nouvelle activité » pour en ajouter une.',
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
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: theme.colorScheme.error,
            ),
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
