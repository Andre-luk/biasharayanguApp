// lib/pages/groupes_tarifaires_page.dart
//
// MODULE 2 — Liste des groupes tarifaires (`public.groupes_tarifaires`).
//
// Chaque ligne affiche le nom, l'activité, le montant de l'abonnement, les
// frais d'ouverture, les durées (essai / abonnement) et le nombre
// d'entreprises rattachées. Un filtre par activité restreint la liste.
//
// La suppression est refusée tant qu'une entreprise utilise le groupe :
// vérification locale (message immédiat) puis vérification du service.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/activite.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/services/referentiel_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class GroupesTarifairesPage extends StatefulWidget {
  const GroupesTarifairesPage({super.key, this.activiteIdInitial});

  /// Filtre appliqué à l'ouverture (issu de l'écran des activités).
  final String? activiteIdInitial;

  @override
  State<GroupesTarifairesPage> createState() => _GroupesTarifairesPageState();
}

class _GroupesTarifairesPageState extends State<GroupesTarifairesPage> {
  final ReferentielService _service = ReferentielService.instance;

  List<Activite> _activites = const <Activite>[];
  List<GroupeTarifaire> _groupes = const <GroupeTarifaire>[];
  CompteursEntreprises _compteurs = const CompteursEntreprises.vide();

  String? _filtreActiviteId;

  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _filtreActiviteId = widget.activiteIdInitial;
    _charger();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

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
    List<GroupeTarifaire> groupes = const <GroupeTarifaire>[];
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
      groupes = resultats[1] as List<GroupeTarifaire>;
      compteurs = resultats[2] as CompteursEntreprises;
    } on ReferentielServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('GroupesTarifairesPage._charger: $e\n$st');
      messageErreur = 'Une erreur inattendue est survenue lors du chargement '
          'des groupes tarifaires.';
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
      _groupes = groupes;
      _compteurs = compteurs;
      _erreur = null;
      _chargement = false;

      // Un filtre qui référence une activité supprimée est réinitialisé :
      // évite une sélection fantôme dans la liste déroulante.
      if (_filtreActiviteId != null &&
          !activites.any(
            (Activite activite) => activite.id == _filtreActiviteId,
          )) {
        _filtreActiviteId = null;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // FILTRAGE
  // ---------------------------------------------------------------------------

  List<GroupeTarifaire> get _groupesFiltres {
    if (_filtreActiviteId == null) return _groupes;

    return _groupes
        .where(
          (GroupeTarifaire groupe) => groupe.activiteId == _filtreActiviteId,
        )
        .toList(growable: false);
  }

  String _nomActivite(String? activiteId) {
    if (activiteId == null || activiteId.isEmpty) {
      return 'Activité non définie';
    }

    for (final Activite activite in _activites) {
      if (activite.id == activiteId) return activite.nom;
    }
    return 'Activité supprimée';
  }

  List<DropdownMenuItem<String?>> get _itemsActivites {
    return <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Toutes les activités'),
      ),
      ..._activites.map(
        (Activite activite) => DropdownMenuItem<String?>(
          value: activite.id,
          child: Text(
            activite.nom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirCreation() async {
    final GoRouter router = GoRouter.of(context);
    final bool? enregistre = await router.push<bool>(
      '/admin/groupes-tarifaires/new',
      extra: _filtreActiviteId,
    );

    if (!mounted || enregistre != true) return;
    await _charger(silencieux: true);
  }

  Future<void> _ouvrirModification(GroupeTarifaire groupe) async {
    final GoRouter router = GoRouter.of(context);
    final bool? enregistre = await router.push<bool>(
      '/admin/groupes-tarifaires/${groupe.id}',
      extra: groupe,
    );

    if (!mounted || enregistre != true) return;
    await _charger(silencieux: true);
  }

  // ---------------------------------------------------------------------------
  // SUPPRESSION
  // ---------------------------------------------------------------------------

  Future<void> _supprimer(GroupeTarifaire groupe) async {
    final int nbEntreprises = _compteurs.pourGroupe(groupe.id);

    if (nbEntreprises > 0) {
      await _afficherSuppressionBloquee(groupe, nbEntreprises);
      return;
    }

    final bool confirme = await _confirmerSuppression(groupe);
    if (!mounted || !confirme) return;

    String? messageErreur;
    try {
      await _service.supprimerGroupeTarifaire(groupe.id);
    } on ReferentielServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('GroupesTarifairesPage._supprimer: $e\n$st');
      messageErreur =
          "Une erreur inattendue est survenue lors de la suppression.";
    }

    if (!mounted) return;

    if (messageErreur != null) {
      _afficherMessage(messageErreur, estErreur: true);
      return;
    }

    _afficherMessage('Groupe tarifaire supprimé avec succès.');
    await _charger(silencieux: true);
  }

  Future<bool> _confirmerSuppression(GroupeTarifaire groupe) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Supprimer ce groupe tarifaire ?'),
          content: Text(
            'Le groupe « ${groupe.nom} » '
            '(${_nomActivite(groupe.activiteId)}) sera définitivement '
            'supprimé.\n\n'
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
    GroupeTarifaire groupe,
    int nbEntreprises,
  ) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Suppression impossible'),
          content: Text(
            'Le groupe « ${groupe.nom} » est utilisé par $nbEntreprises '
            'entreprise${nbEntreprises > 1 ? 's' : ''}.\n\n'
            "Modifiez d'abord l'abonnement de "
            '${nbEntreprises > 1 ? 'ces entreprises' : 'cette entreprise'} '
            'avant de pouvoir supprimer ce groupe tarifaire.',
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
          'Groupes tarifaires',
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
        label: const Text('Nouveau groupe tarifaire'),
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

    final List<GroupeTarifaire> resultats = _groupesFiltres;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: AppDropdownField<String?>(
                  label: 'Filtrer par activité',
                  value: _filtreActiviteId,
                  hint: 'Toutes les activités',
                  prefixIcon: Icons.filter_alt_outlined,
                  items: _itemsActivites,
                  onChanged: (String? valeur) =>
                      setState(() => _filtreActiviteId = valeur),
                ),
              ),
              if (_filtreActiviteId != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => setState(() => _filtreActiviteId = null),
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  tooltip: 'Retirer le filtre',
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${resultats.length} groupe${resultats.length > 1 ? 's' : ''} '
              'tarifaire${resultats.length > 1 ? 's' : ''} '
              'affiché${resultats.length > 1 ? 's' : ''}',
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

  Widget _liste(List<GroupeTarifaire> resultats) {
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
          _carteGroupe(resultats[index]),
    );
  }

  Widget _carteGroupe(GroupeTarifaire groupe) {
    final ThemeData theme = Theme.of(context);
    final int nbEntreprises = _compteurs.pourGroupe(groupe.id);

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _ouvrirModification(groupe),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.sell_rounded,
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
                      groupe.nom.isEmpty
                          ? 'Groupe tarifaire sans nom'
                          : groupe.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Activité : ${_nomActivite(groupe.activiteId)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Abonnement : ${formatMontant(groupe.montantAbonnement)}"
                      " • Ouverture : ${formatMontant(groupe.fraisOuverture)}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _puce(
                          theme,
                          Icons.hourglass_bottom_rounded,
                          'Essai : ${groupe.dureeEssaiJours} j',
                        ),
                        _puce(
                          theme,
                          Icons.calendar_month_rounded,
                          'Durée : ${groupe.dureeAbonnementJours} j',
                        ),
                        _puce(
                          theme,
                          Icons.person_outline_rounded,
                          'Collab. : '
                          '${groupe.prixParCollaborateur.toStringAsFixed(2)} '
                          '$deviseParDefaut',
                        ),
                        _puce(
                          theme,
                          Icons.business_rounded,
                          '$nbEntreprises entreprise'
                          '${nbEntreprises > 1 ? 's' : ''}',
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
                      _ouvrirModification(groupe);
                      break;
                    case 'supprimer':
                      _supprimer(groupe);
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
    final bool filtreActif = _filtreActiviteId != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Icon(
            Icons.sell_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            filtreActif
                ? 'Aucun groupe tarifaire pour cette activité.'
                : 'Aucun groupe tarifaire enregistré pour le moment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            filtreActif
                ? 'Retirez le filtre ou créez un nouveau groupe tarifaire.'
                : 'Appuyez sur « Nouveau groupe tarifaire » pour en ajouter un.',
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
