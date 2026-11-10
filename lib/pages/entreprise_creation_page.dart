// lib/pages/entreprise_creation_page.dart
//
// 🆕 CORRECTIF 73 — CRÉER UNE ENTREPRISE **AVEC** SON PROPRIÉTAIRE.
//
// Une seule fiche, dans l'ordre où l'opérateur de la plateforme travaille :
//
//   1. L'ENTREPRISE  — nom, ville, activité, catégorie d'espace ;
//   2. LE PACK       — grille tarifaire, prix d'installation, prix mensuel,
//                      durée d'essai (7 jours avant tout paiement) ;
//   3. LE PROPRIÉTAIRE — nom, e-mail, téléphone, mot de passe : SON COMPTE
//                      est créé en même temps, et rattaché à l'entreprise.
//
// Tout part en UN SEUL appel serveur (`rpc_admin_entreprise_creer`) : si une
// validation échoue, rien n'est créé — jamais d'entreprise sans patron.
// Le créateur (`cree_par`) est enregistré automatiquement par le serveur.
//
// Rappel de la règle des deux prix (correctif 60) : le prix d'INSTALLATION
// comprend le premier mois d'abonnement ; le prix MENSUEL s'applique aux
// renouvellements.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/activite.dart';
import 'package:biashara_yangu/models/espace.dart';
import 'package:biashara_yangu/models/fiche_entreprise.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/ville.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/services/paiement_platforme_service.dart';
import 'package:biashara_yangu/services/espace_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

class EntrepriseCreationPage extends StatefulWidget {
  const EntrepriseCreationPage({super.key});

  @override
  State<EntrepriseCreationPage> createState() => _EntrepriseCreationPageState();
}

class _EntrepriseCreationPageState extends State<EntrepriseCreationPage> {
  final EntrepriseService _service = EntrepriseService.instance;

  // 1. L'entreprise
  final TextEditingController _nomCtrl = TextEditingController();
  String? _villeId;
  String? _activiteId;
  List<({String code, String libelle})> _categories = const [];
  String _typeEspace = 'boutique';

  // 2. Le pack
  GroupeTarifaire? _groupe;
  final TextEditingController _installationCtrl = TextEditingController();
  final TextEditingController _mensuelCtrl = TextEditingController();

  /// Vrai dès que l'opérateur a touché au prix lui-même : le pack ne doit plus
  /// le remplacer (voir `_choisirGroupe`).
  bool _installationSaisie = false;
  bool _mensuelSaisi = false;

  // 3. Le propriétaire
  final TextEditingController _propNomCtrl = TextEditingController();
  final TextEditingController _propPrenomCtrl = TextEditingController();
  final TextEditingController _propEmailCtrl = TextEditingController();
  final TextEditingController _propTelCtrl = TextEditingController();
  final TextEditingController _motDePasseCtrl = TextEditingController();
  final TextEditingController _confirmationCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  bool _motDePasseVisible = false;

  // Données de référence
  List<Ville> _villes = const [];
  List<Activite> _activites = const [];
  List<GroupeTarifaire> _groupes = const [];

  bool _chargement = true;
  bool _chargementGroupes = false;
  bool _enregistrement = false;
  String? _erreurChargement;
  final Map<String, String?> _erreurs = <String, String?>{};

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _installationCtrl.dispose();
    _mensuelCtrl.dispose();
    _propNomCtrl.dispose();
    _propPrenomCtrl.dispose();
    _propEmailCtrl.dispose();
    _propTelCtrl.dispose();
    _motDePasseCtrl.dispose();
    _confirmationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _initialiser() async {
    setState(() {
      _chargement = true;
      _erreurChargement = null;
    });

    try {
      final List<Ville> villes = await _service.getVilles();
      final List<Activite> activites = await _service.getActivites();
      final List<({String code, String libelle})> categories =
          await EspaceService.instance.listerCategories();

      if (!mounted) return;
      setState(() {
        _villes = villes;
        _activites = activites;
        _categories = categories;
        if (categories.isNotEmpty &&
            !categories.any((({String code, String libelle}) c) =>
                c.code == _typeEspace)) {
          _typeEspace = categories.first.code;
        }
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreurChargement = e is EntrepriseServiceException
            ? e.message
            : 'Impossible de charger les villes et les activités.';
        _chargement = false;
      });
    }
  }

  Future<void> _onActiviteChangee(String? activiteId) async {
    setState(() {
      _activiteId = activiteId;
      _erreurs['activite'] = null;
      _groupe = null;
      _groupes = const [];
      _chargementGroupes = true;
    });

    if (activiteId == null) {
      setState(() => _chargementGroupes = false);
      return;
    }

    try {
      final List<GroupeTarifaire> groupes =
          await _service.getGroupesTarifaires(activiteId: activiteId);
      if (!mounted) return;
      setState(() {
        _groupes = groupes;
        _chargementGroupes = false;
      });
      if (groupes.isNotEmpty) _choisirGroupe(groupes.first);
    } catch (e) {
      if (!mounted) return;
      setState(() => _chargementGroupes = false);
      _message(
        e is EntrepriseServiceException
            ? e.message
            : 'Impossible de charger les grilles tarifaires.',
        estErreur: true,
      );
    }
  }

  /// Sélectionne un pack et PROPOSE ses deux prix.
  ///
  /// ⚠️ Un prix DÉJÀ SAISI par l'opérateur n'est JAMAIS écrasé : sinon, il
  /// tape ses montants, corrige une activité — et le pack reprend la main sans
  /// qu'il s'en aperçoive. C'est exactement ce qui donnait l'impression que
  /// « le prix saisi ne joue aucun rôle ».
  ///
  /// Règle métier : le prix d'installation comprend le premier mois, donc
  /// `frais d'ouverture + abonnement` ; le prix mensuel est l'abonnement seul.
  void _choisirGroupe(GroupeTarifaire groupe) {
    setState(() {
      _groupe = groupe;
      _erreurs['groupe'] = null;

      if (!_installationSaisie) {
        final double installation =
            groupe.fraisOuverture + groupe.montantAbonnement;
        _installationCtrl.text =
            installation > 0 ? installation.toStringAsFixed(0) : '';
      }
      if (!_mensuelSaisi) {
        _mensuelCtrl.text = groupe.montantAbonnement > 0
            ? groupe.montantAbonnement.toStringAsFixed(0)
            : '';
      }
    });
  }

  // ---------------------------------------------------------------------------
  // VALIDATION
  // ---------------------------------------------------------------------------

  bool _valider() {
    final Map<String, String?> erreurs = <String, String?>{};

    if (_nomCtrl.text.trim().length < 2) {
      erreurs['nom'] = "Le nom de l'entreprise est obligatoire (2 caractères).";
    }
    if (_villeId == null) erreurs['ville'] = 'Veuillez sélectionner une ville.';
    if (_activiteId == null) {
      erreurs['activite'] = 'Veuillez sélectionner une activité.';
    }
    if (_groupe == null) {
      erreurs['groupe'] = 'Veuillez sélectionner une grille tarifaire.';
    }

    final double? installation = _montant(_installationCtrl.text);
    if (installation == null || installation <= 0) {
      erreurs['installation'] =
          "Indiquez le prix d'installation (il comprend le premier mois).";
    }

    final double? mensuel = _montant(_mensuelCtrl.text);
    if (mensuel != null && mensuel <= 0) {
      erreurs['mensuel'] = 'Le prix mensuel doit être supérieur à zéro.';
    }

    if (_propNomCtrl.text.trim().isEmpty) {
      erreurs['propNom'] = 'Indiquez le nom du propriétaire.';
    }

    final String email = _propEmailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      erreurs['propEmail'] = 'Adresse e-mail invalide.';
    }

    if (_motDePasseCtrl.text.length < 8) {
      erreurs['motDePasse'] =
          'Le mot de passe doit comporter au moins 8 caractères.';
    } else if (_motDePasseCtrl.text != _confirmationCtrl.text) {
      erreurs['confirmation'] = 'Les deux mots de passe ne correspondent pas.';
    }

    setState(() {
      _erreurs.clear();
      _erreurs.addAll(erreurs);
    });

    return erreurs.isEmpty;
  }

  double? _montant(String texte) => parseMontantSaisi(texte);

  // ---------------------------------------------------------------------------
  // ENREGISTREMENT
  // ---------------------------------------------------------------------------

  Future<void> _enregistrer() async {
    FocusScope.of(context).unfocus();
    if (_enregistrement) return;

    if (!_valider()) {
      _message('Veuillez corriger les champs signalés en rouge.',
          estErreur: true);
      return;
    }

    setState(() => _enregistrement = true);

    try {
      final ResultatCreationEntreprise resultat =
          await _service.creerEntrepriseAvecProprietaire(
        nom: _nomCtrl.text,
        villeId: _villeId,
        activiteId: _activiteId,
        groupeTarifaireId: _groupe?.id,
        typeEspace: _typeEspace,
        proprietaireNom: _propNomCtrl.text,
        proprietairePrenom: _propPrenomCtrl.text,
        proprietaireEmail: _propEmailCtrl.text,
        proprietaireTelephone: _propTelCtrl.text,
        motDePasse: _motDePasseCtrl.text,
        prixInstallation: _montant(_installationCtrl.text),
        prixMensuel: _montant(_mensuelCtrl.text),
        note: _noteCtrl.text,
      );

      if (!mounted) return;
      await _afficherRecapitulatif(resultat);
      if (!mounted) return;
      context.pop(true);
    } on EntrepriseServiceException catch (e) {
      _message(e.message, estErreur: true);
    } catch (e) {
      _message("Impossible de créer le compte : $e", estErreur: true);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  Future<void> _afficherRecapitulatif(ResultatCreationEntreprise r) async {
    final int essai = r.essaiJours;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.check_circle_outline, color: AppCouleurs.succes),
            SizedBox(width: 8),
            Expanded(child: Text('Compte créé')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(r.nom,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              _ligne('Propriétaire :', r.proprietaireEmail),
              _ligne('Prix d\'installation :',
                  formatMontant(r.prixInstallation)),
              if (r.prixMensuel != null)
                _ligne('Prix mensuel :', formatMontant(r.prixMensuel!)),
              _ligne('Essai avant paiement :', '$essai jour(s)'),
              const SizedBox(height: 12),
              const Text(
                "Le compte est EN ATTENTE DE VÉRIFICATION : il doit passer "
                "par le Gestionnaire des comptes, puis par la Finance, avant "
                "d'être opérationnel.",
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppCouleurs.succes.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppCouleurs.succes.withValues(alpha: 0.25),
                  ),
                ),
                child: const Text(
                  "💳 PAIEMENT PAR MOBILE MONEY (SERDIPAY)\n"
                  "Les frais d'installation et l'abonnement se paient "
                  "UNIQUEMENT par Mobile Money : le client règle depuis son "
                  "téléphone. Dès la confirmation, le compte est ACTIF avec son "
                  "mois d'abonnement — les 7 jours d'essai en cours restent "
                  "acquis (30 + 7 jours). Aucun encaissement en espèces n'est "
                  "accepté.",
                  style: TextStyle(fontSize: 12, height: 1.3),
                ),
              ),
              if (r.compteReutilise) ...<Widget>[
                const SizedBox(height: 10),
                const Text(
                  "Cette adresse e-mail avait déjà un compte : son mot de "
                  "passe a été réaligné et le compte a été rattaché à la "
                  "nouvelle entreprise.",
                  style: TextStyle(fontSize: 12.5, color: Colors.orange),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Plus tard'),
          ),
          // 💳 CORRECTIF 134 — LE PAIEMENT SE FAIT ICI, PAR SERDIPAY.
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _payerParMobileMoney(r);
            },
            icon: const Icon(Icons.smartphone_rounded, size: 18),
            label: const Text('Payer par Mobile Money'),
          ),
        ],
      ),
    );
  }

  /// Ouvre le parcours SerdiPay pour l'entreprise qui vient d'être créée.
  ///
  /// Le montant n'est PAS saisi ici : il est calculé en base pour cette
  /// entreprise (installation — premier mois inclus — puis abonnement
  /// mensuel). Le paiement est confirmé par le webhook SerdiPay, et le compte
  /// devient ACTIF avec ses 7 jours d'essai conservés.
  Future<void> _payerParMobileMoney(ResultatCreationEntreprise r) async {
    if (!mounted) return;
    try {
      final bool paye = await PaiementPlatformeService.payerParMobileMoney(
        context,
        entrepriseId: r.entrepriseId,
        libelleEntreprise: r.nom,
      );
      if (!mounted) return;
      if (paye) {
        _message('Paiement confirmé : le compte « ${r.nom} » est activé avec '
            'son mois d\'abonnement (jours d\'essai conservés).');
      } else {
        _message(
          'Paiement non confirmé : le compte reste en attente. Vous pourrez '
          'le régler depuis « Finance » → « Activations ».',
          estErreur: true,
        );
      }
    } catch (e) {
      debugPrint('EntrepriseCreationPage._payerParMobileMoney : $e');
      if (!mounted) return;
      _message('Impossible d\'ouvrir le paiement Mobile Money.', estErreur: true);
    }
  }

  Widget _ligne(String libelle, String valeur) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(libelle,
                style: const TextStyle(
                    fontSize: 12.5, color: Colors.grey, height: 1.3)),
          ),
          Expanded(
            child: Text(valeur,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
          ),
        ],
      ),
    );
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
        appBar: AppBar(title: const Text('Nouvelle entreprise')),
        body: const AccesRefuse(
          message: 'Votre rôle ne permet pas de créer une entreprise.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer une entreprise + son propriétaire'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Aide',
            onPressed: () => context.pushNamed('guide-utilisation'),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: ModernLoader(taille: 34))
          : _erreurChargement != null
              ? _vueErreur()
              : _formulaire(),
    );
  }

  Widget _vueErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 46),
            const SizedBox(height: 12),
            Text(_erreurChargement!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _initialiser,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formulaire() {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        _titreSection(theme, Icons.storefront_outlined, '1. L\'entreprise'),
        const SizedBox(height: 12),
        TextField(
          controller: _nomCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Nom de l\'entreprise *',
            prefixIcon: const Icon(Icons.badge_outlined),
            errorText: _erreurs['nom'],
          ),
        ),
        const SizedBox(height: 14),
        AppDropdownField<String?>(
          label: 'Ville *',
          value: _villeId,
          hint: 'Sélectionnez une ville',
          errorText: _erreurs['ville'],
          prefixIcon: Icons.location_city_outlined,
          items: _itemsVilles(),
          onChanged: (String? v) => setState(() {
            _villeId = v;
            _erreurs['ville'] = null;
          }),
        ),
        const SizedBox(height: 14),
        AppDropdownField<String?>(
          label: 'Activité *',
          value: _activiteId,
          hint: 'Sélectionnez une activité',
          errorText: _erreurs['activite'],
          prefixIcon: Icons.category_outlined,
          enabled: !_chargementGroupes,
          items: _itemsActivites(),
          onChanged: _onActiviteChangee,
        ),
        const SizedBox(height: 14),
        AppDropdownField<String>(
          label: 'Environnement (modules)',
          value: _typeEspace,
          hint: 'Type d\'activité',
          prefixIcon: Icons.dashboard_customize_outlined,
          items: _itemsCategories(),
          onChanged: (String? v) {
            if (v == null) return;
            setState(() => _typeEspace = v);
          },
        ),

        const SizedBox(height: 26),
        _titreSection(theme, Icons.price_change_outlined, '2. Le pack'),
        const SizedBox(height: 12),
        _champGroupe(),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _installationCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => _installationSaisie = true,
                decoration: InputDecoration(
                  labelText: 'Prix d\'installation *',
                  helperText: 'Comprend le 1er mois',
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.install_desktop_outlined),
                  errorText: _erreurs['installation'],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _mensuelCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => _mensuelSaisi = true,
                decoration: InputDecoration(
                  labelText: 'Prix mensuel',
                  helperText: 'Renouvellements',
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.event_repeat_outlined),
                  errorText: _erreurs['mensuel'],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Règle d'or, écrite noir sur blanc : le pack PROPOSE, l'opérateur
        // DÉCIDE. Un montant saisi remplace celui du pack — et il se relit
        // juste en dessous avant d'enregistrer.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppCouleurs.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: AppCouleurs.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Le pack remplit ces deux montants. Si vous en écrivez un '
                  'vous-même, c\'est LE VÔTRE qui est enregistré — le pack ne '
                  'le remplace pas.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_groupe != null) ...[
          const SizedBox(height: 10),
          _apercuGroupe(theme),
        ],

        const SizedBox(height: 26),
        _titreSection(
            theme, Icons.person_add_alt_1_outlined, '3. Le propriétaire'),
        const SizedBox(height: 4),
        Text(
          'Son compte est créé en même temps et rattaché à l\'entreprise. '
          'Remettez-lui ses identifiants : il pourra changer son mot de passe.',
          style: TextStyle(
              fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _propNomCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Nom du propriétaire *',
            prefixIcon: const Icon(Icons.person_outline),
            errorText: _erreurs['propNom'],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _propPrenomCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Prénom (optionnel)',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _propEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Adresse e-mail (identifiant) *',
            prefixIcon: const Icon(Icons.alternate_email_outlined),
            errorText: _erreurs['propEmail'],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _propTelCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Téléphone (optionnel)',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _motDePasseCtrl,
          obscureText: !_motDePasseVisible,
          decoration: InputDecoration(
            labelText: 'Mot de passe *',
            helperText: '8 caractères minimum',
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            errorText: _erreurs['motDePasse'],
            suffixIcon: IconButton(
              icon: Icon(_motDePasseVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              onPressed: () =>
                  setState(() => _motDePasseVisible = !_motDePasseVisible),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmationCtrl,
          obscureText: !_motDePasseVisible,
          decoration: InputDecoration(
            labelText: 'Confirmer le mot de passe *',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            errorText: _erreurs['confirmation'],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _noteCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Note interne (optionnel)',
            prefixIcon: Icon(Icons.sticky_note_2_outlined),
          ),
        ),

        const SizedBox(height: 26),
        FilledButton.icon(
          onPressed: _enregistrement ? null : _enregistrer,
          icon: _enregistrement
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: Colors.white),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_enregistrement ? 'CRÉATION…' : 'CRÉER LE COMPTE'),
        ),
        const SizedBox(height: 10),
        Text(
          'Le compte sera créé « EN ATTENTE DE VÉRIFICATION » : il devra être '
          'vérifié par le Gestionnaire des comptes, puis validé par la Finance.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _titreSection(ThemeData theme, IconData icone, String titre) {
    return Row(
      children: <Widget>[
        Icon(icone, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          titre,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _champGroupe() {
    if (_chargementGroupes) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: ModernLoader(taille: 24)),
      );
    }

    return AppDropdownField<String>(
      label: 'Grille tarifaire (pack) *',
      value: _groupe?.id,
      hint: _activiteId == null
          ? "Sélectionnez d'abord une activité"
          : 'Aucune grille pour cette activité',
      errorText: _erreurs['groupe'],
      prefixIcon: Icons.workspace_premium_outlined,
      enabled: _activiteId != null && _groupes.isNotEmpty,
      items: _groupes
          .map((GroupeTarifaire g) => DropdownMenuItem<String>(
                value: g.id,
                child: Text(g.nom,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (String? id) {
        if (id == null) return;
        final GroupeTarifaire groupe =
            _groupes.firstWhere((GroupeTarifaire g) => g.id == id);
        _choisirGroupe(groupe);
      },
    );
  }

  Widget _apercuGroupe(ThemeData theme) {
    final GroupeTarifaire g = _groupe!;
    final int essai = g.dureeEssaiJours > 0 ? g.dureeEssaiJours : 7;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(g.nom,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          _ligne('Frais d\'ouverture (pack) :', formatMontant(g.fraisOuverture)),
          _ligne('Abonnement (pack) :', formatMontant(g.montantAbonnement)),
          _ligne('Essai avant paiement :', '$essai jour(s)'),
          if (g.dureeAbonnementJours > 0)
            _ligne('Durée d\'un cycle :', '${g.dureeAbonnementJours} jour(s)'),
          _ligne('Entreprises autorisées :', '${g.maxEspaces}'),
        ],
      ),
    );
  }

  List<DropdownMenuItem<String?>> _itemsVilles() {
    return _villes
        .map((Ville ville) => DropdownMenuItem<String?>(
              value: ville.id,
              child: Text(
                ville.pays == null ? ville.nom : '${ville.nom} (${ville.pays})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ))
        .toList();
  }

  List<DropdownMenuItem<String?>> _itemsActivites() {
    return _activites
        .map((Activite activite) => DropdownMenuItem<String?>(
              value: activite.id,
              child: Text(activite.nom,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ))
        .toList();
  }

  List<DropdownMenuItem<String>> _itemsCategories() {
    final List<({String code, String libelle})> liste = _categories.isEmpty
        ? TypeEspace.values
            .map((TypeEspace t) => (code: t.code, libelle: t.libelle))
            .toList()
        : _categories;

    return liste
        .map((({String code, String libelle}) c) => DropdownMenuItem<String>(
              value: c.code,
              child: Text(c.libelle,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ))
        .toList();
  }
}
