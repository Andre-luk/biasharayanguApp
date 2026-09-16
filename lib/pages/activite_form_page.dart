// lib/pages/activite_form_page.dart
//
// MODULE 2 — Création / modification d'une activité (`public.activites`).
//
// Sert aussi de fiche de détail : en modification, l'écran affiche le nombre
// de groupes tarifaires et d'entreprises rattachés, et propose la suppression
// (bloquée tant que l'activité est utilisée).
//
// Validation : nom obligatoire (2 caractères minimum) et unique — le doublon
// est détecté à la saisie, puis confirmé par la base (index insensible à la
// casse).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/activite.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/services/referentiel_service.dart';

class ActiviteFormPage extends StatefulWidget {
  const ActiviteFormPage({super.key, this.activite, this.activiteId});

  /// Activité à modifier. `null` => création.
  final Activite? activite;

  /// Identifiant utilisé en secours lorsque l'écran est ouvert par URL directe
  /// (sans `extra`).
  final String? activiteId;

  bool get estModification => activite != null || activiteId != null;

  @override
  State<ActiviteFormPage> createState() => _ActiviteFormPageState();
}

class _ActiviteFormPageState extends State<ActiviteFormPage> {
  final ReferentielService _service = ReferentielService.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  Activite? _activite;

  /// Autres activités chargées depuis la base, pour détecter les doublons de
  /// nom avant même l'appel réseau.
  List<Activite> _autresActivites = const <Activite>[];

  int _nbEntreprises = 0;
  int _nbGroupes = 0;

  bool _chargement = true;
  bool _enregistrement = false;
  bool _suppressionEnCours = false;
  String? _erreurChargement;

  @override
  void initState() {
    super.initState();
    _activite = widget.activite;
    _initialiser();
  }

  @override
  void dispose() {
    _nomController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _initialiser() async {
    if (!mounted) return;
    setState(() {
      _chargement = true;
      _erreurChargement = null;
    });

    String? messageErreur;
    Activite? activite = widget.activite;
    List<Activite> autres = const <Activite>[];
    int nbEntreprises = 0;
    int nbGroupes = 0;

    try {
      final List<Future<dynamic>> requetes = <Future<dynamic>>[
        _service.getActivites(),
        _service.getCompteursEntreprises(),
      ];

      if (activite == null && widget.activiteId != null) {
        requetes.add(_service.getActiviteById(widget.activiteId!));
      } else {
        requetes.add(Future<Activite?>.value(activite));
      }

      final List<dynamic> resultats = await Future.wait<dynamic>(requetes);

      final List<Activite> toutes = resultats[0] as List<Activite>;
      final CompteursEntreprises compteurs =
          resultats[1] as CompteursEntreprises;
      activite = resultats[2] as Activite?;

      autres = toutes
          .where((Activite a) => a.id != activite?.id)
          .toList(growable: false);

      if (activite != null) {
        nbEntreprises = compteurs.pourActivite(activite.id);

        final List<GroupeTarifaire> groupes =
            await _service.getGroupesTarifaires(activiteId: activite.id);
        nbGroupes = groupes.length;
      }
    } on ReferentielServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ActiviteFormPage._initialiser: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement du formulaire.';
    }

    if (!mounted) return;

    // Mode édition demandé mais activité absente de la base.
    if (messageErreur == null && activite == null && widget.estModification) {
      messageErreur =
          'Cette activité est introuvable. Elle a peut-être été supprimée.';
    }

    if (messageErreur != null) {
      setState(() {
        _erreurChargement = messageErreur;
        _chargement = false;
      });
      return;
    }

    setState(() {
      _activite = activite;
      _autresActivites = autres;
      _nbEntreprises = nbEntreprises;
      _nbGroupes = nbGroupes;
      _nomController.text = activite?.nom ?? '';
      _descriptionController.text = activite?.description ?? '';
      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // VALIDATION & ENREGISTREMENT
  // ---------------------------------------------------------------------------

  String? _validerNom(String? valeur) {
    final String texte = (valeur ?? '').trim();

    if (texte.isEmpty) {
      return "Le nom de l'activité est obligatoire.";
    }
    if (texte.length < 2) {
      return 'Le nom doit contenir au moins 2 caractères.';
    }

    final String recherche = texte.toLowerCase();
    final bool doublon = _autresActivites.any(
      (Activite autre) => autre.nom.trim().toLowerCase() == recherche,
    );
    if (doublon) {
      return 'Une activité porte déjà ce nom.';
    }

    return null;
  }

  Future<void> _enregistrer() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      _afficherMessage(
        'Veuillez corriger les champs signalés en rouge.',
        estErreur: true,
      );
      return;
    }

    final Activite? activite = _activite;
    final bool estCreation = activite == null;

    setState(() => _enregistrement = true);

    String? messageErreur;
    try {
      if (estCreation) {
        await _service.creerActivite(
          nom: _nomController.text,
          description: _descriptionController.text,
        );
      } else {
        await _service.modifierActivite(
          id: activite.id,
          nom: _nomController.text,
          description: _descriptionController.text,
        );
      }
    } on ReferentielServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ActiviteFormPage._enregistrer: $e\n$st');
      messageErreur =
          "Une erreur inattendue est survenue lors de l'enregistrement.";
    }

    if (!mounted) return;

    if (messageErreur != null) {
      setState(() => _enregistrement = false);
      _afficherMessage(messageErreur, estErreur: true);
      return;
    }

    _afficherMessage(
      estCreation ? 'Activité créée avec succès.' : 'Activité modifiée.',
    );
    Navigator.of(context).pop(true);
  }

  // ---------------------------------------------------------------------------
  // SUPPRESSION
  // ---------------------------------------------------------------------------

  Future<void> _supprimer() async {
    final Activite? activite = _activite;
    if (activite == null) return;

    if (_nbEntreprises > 0 || _nbGroupes > 0) {
      await _afficherSuppressionBloquee(activite);
      return;
    }

    final bool confirme = await _confirmerSuppression(activite);
    if (!mounted || !confirme) return;

    setState(() => _suppressionEnCours = true);

    String? messageErreur;
    try {
      await _service.supprimerActivite(activite.id);
    } on ReferentielServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ActiviteFormPage._supprimer: $e\n$st');
      messageErreur =
          "Une erreur inattendue est survenue lors de la suppression.";
    }

    if (!mounted) return;

    if (messageErreur != null) {
      setState(() => _suppressionEnCours = false);
      _afficherMessage(messageErreur, estErreur: true);
      return;
    }

    _afficherMessage('Activité supprimée avec succès.');
    Navigator.of(context).pop(true);
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

  Future<void> _afficherSuppressionBloquee(Activite activite) {
    final List<String> raisons = <String>[
      if (_nbGroupes > 0)
        '$_nbGroupes groupe${_nbGroupes > 1 ? 's' : ''} tarifaire'
            '${_nbGroupes > 1 ? 's' : ''}',
      if (_nbEntreprises > 0)
        '$_nbEntreprises entreprise${_nbEntreprises > 1 ? 's' : ''}',
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
    final bool formulairePret = !_chargement && _erreurChargement == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.estModification ? "Modifier l'activité" : 'Nouvelle activité',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          if (widget.estModification && formulairePret)
            IconButton(
              onPressed: _suppressionEnCours ? null : _supprimer,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Supprimer',
            ),
        ],
      ),
      body: _construireCorps(theme),
      bottomNavigationBar: formulairePret ? _barreActions() : null,
    );
  }

  Widget _construireCorps(ThemeData theme) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreurChargement != null) {
      return _vueErreur(theme);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titreSection(theme, 'Informations générales', Icons.storefront),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nomController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: "Nom de l'activité *",
                hintText: 'Ex. : Boulangerie',
                prefixIcon: const Icon(Icons.label_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: _validerNom,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'À quoi correspond cette activité ? (facultatif)',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 52),
                  child: Icon(Icons.notes_rounded),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (widget.estModification && _activite != null) ...[
              const SizedBox(height: 20),
              _carteUtilisation(theme),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Carte de synthèse propre au mode modification : rappelle l'utilisation de
  /// l'activité et explique le blocage éventuel de la suppression.
  Widget _carteUtilisation(ThemeData theme) {
    final bool utilisee = _nbEntreprises > 0 || _nbGroupes > 0;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.insights_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Utilisation',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const Divider(height: 22),
            _ligneUtilisation(
              theme,
              Icons.sell_outlined,
              'Groupes tarifaires',
              '$_nbGroupes',
            ),
            const SizedBox(height: 6),
            _ligneUtilisation(
              theme,
              Icons.business_outlined,
              'Entreprises rattachées',
              '$_nbEntreprises',
            ),
            if (utilisee) ...[
              const SizedBox(height: 12),
              Text(
                "La suppression de cette activité est bloquée tant que des "
                'groupes tarifaires ou des entreprises y sont rattachés.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ligneUtilisation(
    ThemeData theme,
    IconData icone,
    String libelle,
    String valeur,
  ) {
    return Row(
      children: [
        Icon(icone, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(libelle, style: const TextStyle(fontSize: 13)),
        ),
        Text(
          valeur,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _titreSection(ThemeData theme, String titre, IconData icone) {
    return Row(
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
    );
  }

  Widget _barreActions() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
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
                onPressed: _enregistrement ? null : _enregistrer,
                icon: _enregistrement
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label:
                    Text(_enregistrement ? 'Enregistrement...' : 'Enregistrer'),
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
              'Formulaire indisponible',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _erreurChargement!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _initialiser,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Retour'),
            ),
          ],
        ),
      ),
    );
  }
}
