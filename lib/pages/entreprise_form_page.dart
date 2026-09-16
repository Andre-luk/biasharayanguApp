// lib/pages/entreprise_form_page.dart
import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/activite.dart';
import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/models/ville.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

/// Formulaire de création et de modification d'une entreprise.
///
/// Le groupe tarifaire est présélectionné automatiquement d'après l'activité
/// choisie, puis reste modifiable si l'activité possède plusieurs grilles.
class EntrepriseFormPage extends StatefulWidget {
  const EntrepriseFormPage({super.key, this.entreprise, this.entrepriseId});

  /// Entreprise à modifier. `null` => création.
  final Entreprise? entreprise;

  /// Identifiant utilisé en secours lorsque l'écran est ouvert par URL directe
  /// (sans `extra`).
  final String? entrepriseId;

  bool get estModification => entreprise != null || entrepriseId != null;

  @override
  State<EntrepriseFormPage> createState() => _EntrepriseFormPageState();
}

class _EntrepriseFormPageState extends State<EntrepriseFormPage> {
  final EntrepriseService _service = EntrepriseService.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nomController = TextEditingController();

  Entreprise? _entreprise;
  List<Ville> _villes = const <Ville>[];
  List<Activite> _activites = const <Activite>[];
  List<GroupeTarifaire> _groupesTarifaires = const <GroupeTarifaire>[];

  String? _villeId;
  String? _activiteId;
  GroupeTarifaire? _groupeSelectionne;

  bool _chargement = true;
  bool _chargementGroupes = false;
  bool _enregistrement = false;
  String? _erreurChargement;

  String? _erreurVille;
  String? _erreurActivite;
  String? _erreurGroupe;

  @override
  void initState() {
    super.initState();
    _entreprise = widget.entreprise;
    _initialiser();
  }

  @override
  void dispose() {
    _nomController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT INITIAL
  // ---------------------------------------------------------------------------

  Future<void> _initialiser() async {
    if (!mounted) return;
    setState(() {
      _chargement = true;
      _erreurChargement = null;
    });

    String? messageErreur;
    List<Ville> villes = const <Ville>[];
    List<Activite> activites = const <Activite>[];
    Entreprise? entreprise = widget.entreprise;

    try {
      final List<Future<dynamic>> requetes = <Future<dynamic>>[
        _service.getVilles(),
        _service.getActivites(),
      ];

      if (entreprise == null && widget.entrepriseId != null) {
        requetes.add(_service.getEntrepriseById(widget.entrepriseId!));
      } else {
        requetes.add(Future<Entreprise?>.value(entreprise));
      }

      final List<dynamic> resultats = await Future.wait<dynamic>(requetes);
      villes = resultats[0] as List<Ville>;
      activites = resultats[1] as List<Activite>;
      entreprise = resultats[2] as Entreprise?;
    } on EntrepriseServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('EntrepriseFormPage._initialiser: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement du formulaire.';
    }

    if (!mounted) return;

    if (messageErreur != null) {
      setState(() {
        _erreurChargement = messageErreur;
        _chargement = false;
      });
      return;
    }

    // Mode édition demandé mais entreprise absente de la base.
    if (entreprise == null && widget.estModification) {
      setState(() {
        _erreurChargement =
            'Cette entreprise est introuvable. Elle a peut-être été supprimée.';
        _chargement = false;
      });
      return;
    }

    setState(() {
      _villes = villes;
      _activites = activites;
      _entreprise = entreprise;
      _nomController.text = entreprise?.nom ?? '';
      _villeId = entreprise?.villeId;
      _activiteId = entreprise?.activiteId;
      _chargement = false;
    });

    if (_activiteId != null) {
      await _chargerGroupesTarifaires(
        _activiteId!,
        groupeAConserver: entreprise?.groupeTarifaireId,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // GROUPES TARIFAIRES
  // ---------------------------------------------------------------------------

  /// Charge les groupes tarifaires de l'activité et présélectionne :
  /// 1. le groupe [groupeAConserver] s'il appartient bien à cette activité,
  /// 2. sinon le premier groupe disponible.
  Future<void> _chargerGroupesTarifaires(
    String activiteId, {
    String? groupeAConserver,
  }) async {
    if (!mounted) return;
    setState(() {
      _chargementGroupes = true;
      _groupesTarifaires = const <GroupeTarifaire>[];
      _groupeSelectionne = null;
      _erreurGroupe = null;
    });

    List<GroupeTarifaire> groupes = const <GroupeTarifaire>[];
    String? messageErreur;

    try {
      groupes = await _service.getGroupesTarifaires(activiteId: activiteId);
    } on EntrepriseServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('EntrepriseFormPage._chargerGroupesTarifaires: $e\n$st');
      messageErreur =
          'Impossible de charger les groupes tarifaires de cette activité.';
    }

    if (!mounted) return;

    GroupeTarifaire? choix;
    if (groupes.isNotEmpty) {
      choix = groupes.firstWhere(
        (GroupeTarifaire groupe) => groupe.id == groupeAConserver,
        orElse: () => groupes.first,
      );
    }

    setState(() {
      _chargementGroupes = false;
      _groupesTarifaires = groupes;
      _groupeSelectionne = choix;
      _erreurGroupe = messageErreur ??
          (groupes.isEmpty
              ? "Aucun groupe tarifaire n'est configuré pour cette activité. "
                  "Contactez l'administrateur système avant de créer l'entreprise."
              : null);
    });
  }

  Future<void> _onActiviteChangee(String? activiteId) async {
    setState(() {
      _activiteId = activiteId;
      _erreurActivite = null;
      _groupeSelectionne = null;
      _groupesTarifaires = const <GroupeTarifaire>[];
      _erreurGroupe = null;
    });

    if (activiteId == null || activiteId.isEmpty) return;

    // Le groupe précédent appartenait à l'ancienne activité : on repart du
    // premier groupe de la nouvelle activité.
    await _chargerGroupesTarifaires(activiteId);
  }

  void _onGroupeChange(String? groupeId) {
    if (groupeId == null || _groupesTarifaires.isEmpty) return;

    setState(() {
      _groupeSelectionne = _groupesTarifaires.firstWhere(
        (GroupeTarifaire groupe) => groupe.id == groupeId,
        orElse: () => _groupesTarifaires.first,
      );
      _erreurGroupe = null;
    });
  }

  // ---------------------------------------------------------------------------
  // VALIDATION & ENREGISTREMENT
  // ---------------------------------------------------------------------------

  bool _valider() {
    final bool nomValide = _formKey.currentState?.validate() ?? false;

    setState(() {
      _erreurVille =
          _villeId == null ? 'Veuillez sélectionner une ville.' : null;
      _erreurActivite =
          _activiteId == null ? 'Veuillez sélectionner une activité.' : null;
      _erreurGroupe = _groupeSelectionne == null
          ? (_erreurGroupe ??
              "Aucun groupe tarifaire n'est disponible pour cette activité.")
          : null;
    });

    return nomValide &&
        _villeId != null &&
        _activiteId != null &&
        _groupeSelectionne != null;
  }

  Future<void> _enregistrer() async {
    FocusScope.of(context).unfocus();

    if (!_valider()) {
      _afficherMessage('Veuillez corriger les champs signalés en rouge.',
          estErreur: true);
      return;
    }

    final Entreprise? entreprise = _entreprise;
    final GroupeTarifaire groupe = _groupeSelectionne!;
    final bool estCreation = entreprise == null;

    // Changer de grille tarifaire modifie la facturation : on demande
    // confirmation avant de recalculer quoi que ce soit.
    if (!estCreation && entreprise.groupeTarifaireId != groupe.id) {
      final bool confirme =
          await _confirmerChangementTarifaire(entreprise, groupe);
      if (!mounted || !confirme) return;
    }

    setState(() => _enregistrement = true);

    String? messageErreur;
    try {
      if (estCreation) {
        await _service.createEntreprise(
          nom: _nomController.text,
          villeId: _villeId!,
          activiteId: _activiteId!,
          groupeTarifaire: groupe,
        );
      } else {
        await _service.updateEntreprise(
          entreprise: entreprise,
          nom: _nomController.text,
          villeId: _villeId!,
          activiteId: _activiteId!,
          groupeTarifaire: groupe,
        );
      }
    } on EntrepriseServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('EntrepriseFormPage._enregistrer: $e\n$st');
      messageErreur =
          "Une erreur inattendue est survenue lors de l'enregistrement.";
    }

    if (!mounted) return;

    if (messageErreur == null) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() => _enregistrement = false);
    _afficherMessage(messageErreur, estErreur: true);
  }

  Future<bool> _confirmerChangementTarifaire(
    Entreprise entreprise,
    GroupeTarifaire nouveauGroupe,
  ) async {
    final double nouveauTotal = _service.calculerMontantTotalDu(nouveauGroupe);

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Changer le groupe tarifaire ?'),
          content: Text(
            "Le montant total dû passera de ${formatMontant(entreprise.montantTotalDu)} "
            'à ${formatMontant(nouveauTotal)}.\n\n'
            'Le solde restant sera recalculé en tenant compte des '
            '${formatMontant(entreprise.montantDejaPaye)} déjà payés.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmer'),
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
    final bool formulairePret = !_chargement && _erreurChargement == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.estModification
              ? "Modifier l'entreprise"
              : 'Nouvelle entreprise',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titreSection(
                theme, 'Informations générales', Icons.business_rounded),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nomController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: "Nom de l'entreprise *",
                hintText: 'Ex. : Établissement Lukengu',
                prefixIcon: const Icon(Icons.storefront_outlined),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (String? valeur) {
                final String texte = (valeur ?? '').trim();
                if (texte.isEmpty) {
                  return "Le nom de l'entreprise est obligatoire.";
                }
                if (texte.length < 2) {
                  return 'Le nom doit contenir au moins 2 caractères.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            AppDropdownField<String?>(
              label: 'Ville *',
              value: _villeId,
              hint: 'Sélectionnez une ville',
              errorText: _erreurVille,
              prefixIcon: Icons.location_city_outlined,
              items: _itemsVilles,
              onChanged: (String? valeur) {
                setState(() {
                  _villeId = valeur;
                  _erreurVille = null;
                });
              },
            ),
            const SizedBox(height: 14),
            AppDropdownField<String?>(
              label: 'Activité *',
              value: _activiteId,
              hint: 'Sélectionnez une activité',
              errorText: _erreurActivite,
              prefixIcon: Icons.category_outlined,
              enabled: !_chargementGroupes,
              items: _itemsActivites,
              onChanged: _onActiviteChangee,
            ),
            const SizedBox(height: 14),
            _champGroupeTarifaire(),
            const SizedBox(height: 20),
            if (_groupeSelectionne != null) _apercuAbonnement(theme),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _champGroupeTarifaire() {
    if (_chargementGroupes) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    final bool actif = _activiteId != null && _groupesTarifaires.isNotEmpty;

    return AppDropdownField<String>(
      label: 'Groupe tarifaire',
      value: _groupeSelectionne?.id,
      hint: _activiteId == null
          ? "Sélectionnez d'abord une activité"
          : 'Aucun groupe tarifaire disponible',
      errorText: _erreurGroupe,
      prefixIcon: Icons.price_change_outlined,
      enabled: actif,
      items: _groupesTarifaires
          .map(
            (GroupeTarifaire groupe) => DropdownMenuItem<String>(
              value: groupe.id,
              child: Text(
                '${groupe.nom} — ${formatMontant(groupe.montantAbonnement)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _onGroupeChange,
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

  /// Carte d'aperçu : reprend les valeurs du groupe tarifaire sélectionné pour
  /// que l'administrateur voie exactement ce qui sera facturé.
  Widget _apercuAbonnement(ThemeData theme) {
    final GroupeTarifaire groupe = _groupeSelectionne!;

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
                Icon(Icons.receipt_long_rounded,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  "Aperçu de l'abonnement",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const Divider(height: 22),
            _ligneApercu('Groupe tarifaire', groupe.nom),
            _ligneApercu("Montant de l'abonnement",
                formatMontant(groupe.montantAbonnement)),
            _ligneApercu(
                "Frais d'ouverture", formatMontant(groupe.fraisOuverture)),
            _ligneApercu("Durée de l'essai", groupe.dureeEssaiLibelle),
            _ligneApercu(
                "Durée de l'abonnement", groupe.dureeAbonnementLibelle),
            _ligneApercu('Prix par collaborateur',
                formatMontant(groupe.prixParCollaborateur)),
            const Divider(height: 22),
            _ligneApercu(
              'Montant total dû à la création',
              formatMontant(_service.calculerMontantTotalDu(groupe)),
              accent: true,
            ),
            const SizedBox(height: 10),
            Text(
              "Le montant total dû correspond aux frais d'ouverture "
              "plus le montant de l'abonnement.",
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "À l'enregistrement : statut « Essai 7 jours », "
              'expiration dans ${groupe.dureeEssaiJours} jour'
              '${groupe.dureeEssaiJours > 1 ? 's' : ''}.',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneApercu(String libelle, String valeur, {bool accent = false}) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(libelle, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: accent ? FontWeight.bold : FontWeight.w600,
                color: accent ? theme.colorScheme.primary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barreActions() {
    final bool enregistrementPossible =
        !_enregistrement && !_chargementGroupes && _groupeSelectionne != null;

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
                onPressed: enregistrementPossible ? _enregistrer : null,
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

  // ---------------------------------------------------------------------------
  // ITEMS DES LISTES DÉROULANTES
  // ---------------------------------------------------------------------------

  List<DropdownMenuItem<String?>> get _itemsVilles {
    final List<DropdownMenuItem<String?>> items = _villes
        .map(
          (Ville ville) => DropdownMenuItem<String?>(
            value: ville.id,
            child: Text(
              ville.pays == null ? ville.nom : '${ville.nom} (${ville.pays})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();

    return _itemsAvecSecours(items, _villeId, 'Ville supprimée');
  }

  List<DropdownMenuItem<String?>> get _itemsActivites {
    final List<DropdownMenuItem<String?>> items = _activites
        .map(
          (Activite activite) => DropdownMenuItem<String?>(
            value: activite.id,
            child: Text(
              activite.nom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();

    return _itemsAvecSecours(items, _activiteId, 'Activité supprimée');
  }
}

/// Garantit que [valeur] est présente dans [items].
///
/// Sans cela, `DropdownButton` lève une assertion lorsque la valeur
/// sélectionnée référence une entité supprimée côté Supabase (ville ou activité
/// archivée) : l'écran planterait au lieu d'afficher le problème.
List<DropdownMenuItem<String?>> _itemsAvecSecours(
  List<DropdownMenuItem<String?>> items,
  String? valeur,
  String libelleSecours,
) {
  if (valeur == null || valeur.isEmpty) return items;
  if (items.any((DropdownMenuItem<String?> item) => item.value == valeur)) {
    return items;
  }

  return <DropdownMenuItem<String?>>[
    ...items,
    DropdownMenuItem<String?>(
      value: valeur,
      child: Text(
        '$libelleSecours (introuvable dans la base)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ];
}
