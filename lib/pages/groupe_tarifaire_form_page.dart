// lib/pages/groupe_tarifaire_form_page.dart
//
// MODULE 2 — Création / modification d'un groupe tarifaire
// (`public.groupes_tarifaires`).
//
// Champs : nom, activité (liste déroulante alimentée par `public.activites`),
// frais d'ouverture, montant de l'abonnement (obligatoire, strictement
// positif), durée d'essai (défaut 7 j), durée d'abonnement (défaut 30 j) et
// prix par collaborateur (défaut 0,50).
//
// Un aperçu affiche en direct le nombre d'entreprises concernées :
// « Ce groupe s'appliquera à X entreprises de type Y ».

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/activite.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/services/referentiel_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class GroupeTarifaireFormPage extends StatefulWidget {
  const GroupeTarifaireFormPage({
    super.key,
    this.groupe,
    this.groupeId,
    this.activiteIdInitial,
  });

  /// Groupe tarifaire à modifier. `null` => création.
  final GroupeTarifaire? groupe;

  /// Identifiant utilisé en secours lorsque l'écran est ouvert par URL directe
  /// (sans `extra`).
  final String? groupeId;

  /// Activité présélectionnée à la création (issue du filtre de la liste).
  final String? activiteIdInitial;

  bool get estModification => groupe != null || groupeId != null;

  @override
  State<GroupeTarifaireFormPage> createState() =>
      _GroupeTarifaireFormPageState();
}

class _GroupeTarifaireFormPageState extends State<GroupeTarifaireFormPage> {
  final ReferentielService _service = ReferentielService.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _fraisOuvertureController =
      TextEditingController(text: '0');
  final TextEditingController _montantAbonnementController =
      TextEditingController();
  final TextEditingController _dureeEssaiController =
      TextEditingController(text: '7');
  final TextEditingController _dureeAbonnementController =
      TextEditingController(text: '30');
  final TextEditingController _prixCollaborateurController =
      TextEditingController(text: '0.50');

  GroupeTarifaire? _groupe;
  List<Activite> _activites = const <Activite>[];
  CompteursEntreprises _compteurs = const CompteursEntreprises.vide();

  String? _activiteId;
  String? _erreurActivite;

  bool _chargement = true;
  bool _enregistrement = false;
  bool _suppressionEnCours = false;
  String? _erreurChargement;

  @override
  void initState() {
    super.initState();
    _groupe = widget.groupe;
    _initialiser();
  }

  @override
  void dispose() {
    _nomController.dispose();
    _fraisOuvertureController.dispose();
    _montantAbonnementController.dispose();
    _dureeEssaiController.dispose();
    _dureeAbonnementController.dispose();
    _prixCollaborateurController.dispose();
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
    GroupeTarifaire? groupe = widget.groupe;
    List<Activite> activites = const <Activite>[];
    CompteursEntreprises compteurs = const CompteursEntreprises.vide();

    try {
      final List<Future<dynamic>> requetes = <Future<dynamic>>[
        _service.getActivites(),
        _service.getCompteursEntreprises(),
      ];

      if (groupe == null && widget.groupeId != null) {
        requetes.add(_service.getGroupeTarifaireById(widget.groupeId!));
      } else {
        requetes.add(Future<GroupeTarifaire?>.value(groupe));
      }

      final List<dynamic> resultats = await Future.wait<dynamic>(requetes);

      activites = resultats[0] as List<Activite>;
      compteurs = resultats[1] as CompteursEntreprises;
      groupe = resultats[2] as GroupeTarifaire?;
    } on ReferentielServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('GroupeTarifaireFormPage._initialiser: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement du formulaire.';
    }

    if (!mounted) return;

    // Mode édition demandé mais groupe absent de la base.
    if (messageErreur == null && groupe == null && widget.estModification) {
      messageErreur =
          'Ce groupe tarifaire est introuvable. Il a peut-être été supprimé.';
    }

    if (messageErreur != null) {
      setState(() {
        _erreurChargement = messageErreur;
        _chargement = false;
      });
      return;
    }

    // Présélection de l'activité : celle du groupe en modification, sinon
    // celle transmise par la liste filtrée.
    String? activiteId = groupe?.activiteId ?? widget.activiteIdInitial;
    if (activiteId != null &&
        !activites.any((Activite activite) => activite.id == activiteId)) {
      activiteId = null;
    }

    setState(() {
      _groupe = groupe;
      _activites = activites;
      _compteurs = compteurs;
      _activiteId = activiteId;
      _chargement = false;

      _nomController.text = groupe?.nom ?? '';
      _fraisOuvertureController.text =
          _formatSaisie(groupe?.fraisOuverture ?? 0);
      _montantAbonnementController.text =
          groupe == null ? '' : _formatSaisie(groupe.montantAbonnement);
      _dureeEssaiController.text = (groupe?.dureeEssaiJours ?? 7).toString();
      _dureeAbonnementController.text =
          (groupe?.dureeAbonnementJours ?? 30).toString();
      _prixCollaborateurController.text =
          _formatSaisie(groupe?.prixParCollaborateur ?? 0.5);
    });
  }

  /// `2000.0` devient `2000`, `0.5` devient `0.5` : les valeurs sont
  /// pré-remplies au format le plus naturel possible.
  String _formatSaisie(double valeur) {
    if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
    return valeur.toString();
  }

  // ---------------------------------------------------------------------------
  // LECTURE DES CHAMPS
  // ---------------------------------------------------------------------------

  /// Convertit une saisie en `double` en acceptant le point et la virgule.
  double? _lireDouble(String texte) {
    final String nettoye = texte.trim().replaceAll(',', '.');
    if (nettoye.isEmpty) return null;
    return double.tryParse(nettoye);
  }

  int? _lireEntier(String texte) {
    final String nettoye = texte.trim();
    if (nettoye.isEmpty) return null;
    return int.tryParse(nettoye);
  }

  Activite? get _activiteSelectionnee {
    final String? id = _activiteId;
    if (id == null) return null;

    for (final Activite activite in _activites) {
      if (activite.id == id) return activite;
    }
    return null;
  }

  int get _nbUtilisations {
    final GroupeTarifaire? groupe = _groupe;
    return groupe == null ? 0 : _compteurs.pourGroupe(groupe.id);
  }

  // ---------------------------------------------------------------------------
  // VALIDATION
  // ---------------------------------------------------------------------------

  String? _validerNom(String? valeur) {
    final String texte = (valeur ?? '').trim();
    if (texte.isEmpty) {
      return 'Le nom du groupe tarifaire est obligatoire.';
    }
    if (texte.length < 2) {
      return 'Le nom doit contenir au moins 2 caractères.';
    }
    return null;
  }

  String? _validerFraisOuverture(String? valeur) {
    final String texte = (valeur ?? '').trim();
    if (texte.isEmpty) return null; // Facultatif : 0 par défaut.

    final double? montant = _lireDouble(texte);
    if (montant == null) {
      return 'Saisissez un montant valide (ex. : 5000 ou 5000,5).';
    }
    if (montant < 0) {
      return 'Le montant ne peut pas être négatif.';
    }
    return null;
  }

  String? _validerMontantAbonnement(String? valeur) {
    final String texte = (valeur ?? '').trim();
    if (texte.isEmpty) {
      return "Le montant de l'abonnement est obligatoire.";
    }

    final double? montant = _lireDouble(texte);
    if (montant == null) {
      return 'Saisissez un montant valide (ex. : 5000 ou 5000,5).';
    }
    if (montant <= 0) {
      return "Le montant doit être supérieur à zéro.";
    }
    return null;
  }

  String? _validerDureeEssai(String? valeur) {
    final String texte = (valeur ?? '').trim();
    if (texte.isEmpty) {
      return "Saisissez une durée (0 pour désactiver l'essai).";
    }

    final int? duree = _lireEntier(texte);
    if (duree == null) {
      return 'Saisissez un nombre entier de jours.';
    }
    if (duree < 0) {
      return 'La durée ne peut pas être négative.';
    }
    return null;
  }

  String? _validerDureeAbonnement(String? valeur) {
    final String texte = (valeur ?? '').trim();
    if (texte.isEmpty) {
      return "La durée de l'abonnement est obligatoire.";
    }

    final int? duree = _lireEntier(texte);
    if (duree == null) {
      return 'Saisissez un nombre entier de jours.';
    }
    if (duree <= 0) {
      return 'La durée doit être supérieure à zéro.';
    }
    return null;
  }

  String? _validerPrixCollaborateur(String? valeur) {
    final String texte = (valeur ?? '').trim();
    if (texte.isEmpty) return null; // Facultatif : 0 par défaut.

    final double? montant = _lireDouble(texte);
    if (montant == null) {
      return 'Saisissez un montant valide (ex. : 0,50).';
    }
    if (montant < 0) {
      return 'Le montant ne peut pas être négatif.';
    }
    return null;
  }

  bool _valider() {
    final bool champsValides = _formKey.currentState?.validate() ?? false;

    setState(() {
      _erreurActivite = _activiteId == null
          ? "Veuillez sélectionner l'activité du groupe tarifaire."
          : null;
    });

    return champsValides && _activiteId != null;
  }

  // ---------------------------------------------------------------------------
  // ENREGISTREMENT
  // ---------------------------------------------------------------------------

  Future<void> _enregistrer() async {
    FocusScope.of(context).unfocus();

    if (!_valider()) {
      _afficherMessage(
        'Veuillez corriger les champs signalés en rouge.',
        estErreur: true,
      );
      return;
    }

    final GroupeTarifaire? groupe = _groupe;
    final String activiteId = _activiteId!;

    // Un groupe utilisé peut changer d'activité, mais les entreprises qui
    // pointent vers lui ne sont pas modifiées : on prévient l'administrateur.
    if (groupe != null &&
        groupe.activiteId != activiteId &&
        _nbUtilisations > 0) {
      final bool confirme = await _confirmerChangementActivite(groupe);
      if (!mounted || !confirme) return;
    }

    final double fraisOuverture =
        _lireDouble(_fraisOuvertureController.text) ?? 0;
    final double montantAbonnement =
        _lireDouble(_montantAbonnementController.text)!;
    final int dureeEssaiJours = _lireEntier(_dureeEssaiController.text)!;
    final int dureeAbonnementJours =
        _lireEntier(_dureeAbonnementController.text)!;
    final double prixParCollaborateur =
        _lireDouble(_prixCollaborateurController.text) ?? 0;

    setState(() => _enregistrement = true);

    String? messageErreur;
    try {
      if (groupe == null) {
        await _service.creerGroupeTarifaire(
          nom: _nomController.text,
          activiteId: activiteId,
          fraisOuverture: fraisOuverture,
          montantAbonnement: montantAbonnement,
          dureeEssaiJours: dureeEssaiJours,
          dureeAbonnementJours: dureeAbonnementJours,
          prixParCollaborateur: prixParCollaborateur,
        );
      } else {
        await _service.modifierGroupeTarifaire(
          id: groupe.id,
          nom: _nomController.text,
          activiteId: activiteId,
          fraisOuverture: fraisOuverture,
          montantAbonnement: montantAbonnement,
          dureeEssaiJours: dureeEssaiJours,
          dureeAbonnementJours: dureeAbonnementJours,
          prixParCollaborateur: prixParCollaborateur,
        );
      }
    } on ReferentielServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('GroupeTarifaireFormPage._enregistrer: $e\n$st');
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
      groupe == null
          ? 'Groupe tarifaire créé avec succès.'
          : 'Groupe tarifaire modifié.',
    );
    Navigator.of(context).pop(true);
  }

  Future<bool> _confirmerChangementActivite(GroupeTarifaire groupe) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text("Changer l'activité du groupe ?"),
          content: Text(
            'Ce groupe tarifaire est utilisé par $_nbUtilisations '
            'entreprise${_nbUtilisations > 1 ? 's' : ''}.\n\n'
            "Changer son activité ne modifie pas leur fiche : elles "
            'continueront d\'utiliser ce groupe.',
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

  // ---------------------------------------------------------------------------
  // SUPPRESSION
  // ---------------------------------------------------------------------------

  Future<void> _supprimer() async {
    final GroupeTarifaire? groupe = _groupe;
    if (groupe == null) return;

    if (_nbUtilisations > 0) {
      await _afficherSuppressionBloquee(groupe);
      return;
    }

    final bool confirme = await _confirmerSuppression(groupe);
    if (!mounted || !confirme) return;

    setState(() => _suppressionEnCours = true);

    String? messageErreur;
    try {
      await _service.supprimerGroupeTarifaire(groupe.id);
    } on ReferentielServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('GroupeTarifaireFormPage._supprimer: $e\n$st');
      messageErreur =
          "Une erreur inattendue est survenue lors de la suppression.";
    }

    if (!mounted) return;

    if (messageErreur != null) {
      setState(() => _suppressionEnCours = false);
      _afficherMessage(messageErreur, estErreur: true);
      return;
    }

    _afficherMessage('Groupe tarifaire supprimé avec succès.');
    Navigator.of(context).pop(true);
  }

  Future<bool> _confirmerSuppression(GroupeTarifaire groupe) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Supprimer ce groupe tarifaire ?'),
          content: Text(
            'Le groupe « ${groupe.nom} » sera définitivement supprimé.\n\n'
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

  Future<void> _afficherSuppressionBloquee(GroupeTarifaire groupe) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Suppression impossible'),
          content: Text(
            'Le groupe « ${groupe.nom} » est utilisé par $_nbUtilisations '
            'entreprise${_nbUtilisations > 1 ? 's' : ''}.\n\n'
            "Modifiez d'abord l'abonnement de "
            '${_nbUtilisations > 1 ? 'ces entreprises' : 'cette entreprise'} '
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
    final bool formulairePret = !_chargement && _erreurChargement == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.estModification
              ? 'Modifier le groupe tarifaire'
              : 'Nouveau groupe tarifaire',
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
            _titreSection(theme, 'Identification', Icons.sell_rounded),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nomController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Nom du groupe *',
                hintText: 'Ex. : Standard, Premium, PME…',
                prefixIcon: const Icon(Icons.label_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: _validerNom,
            ),
            const SizedBox(height: 14),
            AppDropdownField<String?>(
              label: 'Activité *',
              value: _activiteId,
              hint: _activites.isEmpty
                  ? "Aucune activité disponible — créez d'abord une activité"
                  : 'Sélectionnez une activité',
              errorText: _erreurActivite,
              prefixIcon: Icons.category_outlined,
              items: _itemsActivites,
              onChanged: (String? valeur) {
                setState(() {
                  _activiteId = valeur;
                  _erreurActivite = null;
                });
              },
            ),
            const SizedBox(height: 24),
            _titreSection(theme, 'Montants', Icons.monetization_on_outlined),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fraisOuvertureController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: "Frais d'ouverture",
                hintText: 'Ex. : 5000 (0 si aucun frais)',
                prefixIcon: const Icon(Icons.door_front_door_outlined),
                suffixText: deviseParDefaut,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: _validerFraisOuverture,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _montantAbonnementController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: "Montant de l'abonnement *",
                hintText: 'Ex. : 15000',
                prefixIcon: const Icon(Icons.payments_outlined),
                suffixText: deviseParDefaut,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: _validerMontantAbonnement,
            ),
            const SizedBox(height: 24),
            _titreSection(theme, 'Durées', Icons.hourglass_bottom_rounded),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dureeEssaiController,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: "Durée d'essai (jours)",
                hintText: 'Défaut : 7',
                prefixIcon: const Icon(Icons.timelapse_rounded),
                suffixText: 'jours',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: _validerDureeEssai,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _dureeAbonnementController,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: "Durée de l'abonnement (jours)",
                hintText: 'Défaut : 30',
                prefixIcon: const Icon(Icons.calendar_month_rounded),
                suffixText: 'jours',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: _validerDureeAbonnement,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _prixCollaborateurController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Prix par collaborateur',
                hintText: 'Défaut : 0,50',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                suffixText: deviseParDefaut,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: _validerPrixCollaborateur,
            ),
            const SizedBox(height: 24),
            _apercu(theme),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Aperçu en direct : entreprises concernées, montants et durées repris des
  /// champs en cours de saisie.
  Widget _apercu(ThemeData theme) {
    final Activite? activite = _activiteSelectionnee;
    final int nbEntreprises = _compteurs.pourActivite(_activiteId);

    final double? frais = _lireDouble(_fraisOuvertureController.text);
    final double? abonnement = _lireDouble(_montantAbonnementController.text);
    final int? essai = _lireEntier(_dureeEssaiController.text);
    final int? duree = _lireEntier(_dureeAbonnementController.text);
    final double? prix = _lireDouble(_prixCollaborateurController.text);

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
                  Icons.receipt_long_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Aperçu',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const Divider(height: 22),
            _encartApplication(theme, activite, nbEntreprises),
            const SizedBox(height: 12),
            _ligneApercu(
              "Montant de l'abonnement",
              abonnement == null ? '—' : formatMontant(abonnement),
            ),
            _ligneApercu(
              "Frais d'ouverture",
              frais == null ? '—' : formatMontant(frais),
            ),
            _ligneApercu(
              "Durée de l'essai",
              essai == null ? '—' : '$essai jour${essai > 1 ? 's' : ''}',
            ),
            _ligneApercu(
              "Durée de l'abonnement",
              duree == null ? '—' : '$duree jour${duree > 1 ? 's' : ''}',
            ),
            _ligneApercu(
              'Prix par collaborateur',
              prix == null
                  ? '—'
                  : '${prix.toStringAsFixed(2)} $deviseParDefaut',
            ),
            const Divider(height: 22),
            _ligneApercu(
              'Montant total dû à la création',
              (frais == null || abonnement == null)
                  ? '—'
                  : formatMontant(frais + abonnement),
              accent: true,
            ),
            if (widget.estModification && _nbUtilisations > 0) ...[
              const SizedBox(height: 10),
              Text(
                '$_nbUtilisations entreprise${_nbUtilisations > 1 ? 's' : ''} '
                'utilise${_nbUtilisations > 1 ? 'nt' : ''} actuellement ce '
                'groupe tarifaire.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              "Le montant total dû correspond aux frais d'ouverture "
              "plus le montant de l'abonnement.",
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

  /// Phrase demandée par le cahier des charges :
  /// « Ce groupe s'appliquera à X entreprises de type Y ».
  Widget _encartApplication(
    ThemeData theme,
    Activite? activite,
    int nbEntreprises,
  ) {
    final String message = activite == null
        ? "Sélectionnez une activité : l'aperçu indiquera combien "
            "d'entreprises seront concernées."
        : 'Ce groupe s\'appliquera à $nbEntreprises '
            'entreprise${nbEntreprises > 1 ? 's' : ''} de type '
            '« ${activite.nom} ».';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
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

  // ---------------------------------------------------------------------------
  // ITEMS DES LISTES DÉROULANTES
  // ---------------------------------------------------------------------------

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

    // Garantit que la valeur sélectionnée existe dans les items : sans cela,
    // `DropdownButton` lèverait une assertion si l'activité a été supprimée
    // entre-temps.
    final String? valeur = _activiteId;
    if (valeur == null || valeur.isEmpty) return items;
    if (items.any(
      (DropdownMenuItem<String?> item) => item.value == valeur,
    )) {
      return items;
    }

    return <DropdownMenuItem<String?>>[
      ...items,
      DropdownMenuItem<String?>(
        value: valeur,
        child: const Text(
          'Activité supprimée',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];
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
