// lib/pages/type_activite_form_page.dart
//
// 🧩 MODULE 16 — CRÉATION / MODIFICATION D'UN TYPE D'ACTIVITÉ.
//
// L'« Expert Administrateur » :
//   • nomme le type (« Salon de coiffure ») → le code technique est généré
//     automatiquement (« salon_de_coiffure »), modifiable ;
//   • coche les modules du profil (groupés par usage) ;
//   • active/désactive le type (le profil « Boutique », repli universel,
//     reste toujours actif).
//
// Les modules « bientôt » (phases C de la roadmap) peuvent déjà être cochés :
// ils préparent les profils, aucun écran ne les consomme encore.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/services/modules_service.dart';

class TypeActiviteFormPage extends StatefulWidget {
  const TypeActiviteFormPage({super.key, this.profil, this.typeCode});

  /// Profil à modifier. `null` => création.
  final ProfilModules? profil;

  /// Code utilisé en secours lorsque l'écran est ouvert par URL directe
  /// (sans `extra`).
  final String? typeCode;

  bool get estModification => profil != null || typeCode != null;

  @override
  State<TypeActiviteFormPage> createState() => _TypeActiviteFormPageState();
}

class _TypeActiviteFormPageState extends State<TypeActiviteFormPage> {
  final ModulesService _service = ModulesService.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _libelleController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  ProfilModules? _profil;

  /// Autres types chargés depuis la base (détection des doublons avant réseau).
  List<ProfilModules> _autres = const <ProfilModules>[];

  /// Modules cochés.
  final Set<String> _selection = <String>{};

  bool _actif = true;

  /// L'expert a-t-il modifié le code technique à la main (création) ?
  /// Tant que non, le code suit automatiquement le nom.
  bool _codePersonnalise = false;

  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreurChargement;

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  @override
  void dispose() {
    _libelleController.dispose();
    _codeController.dispose();
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
    ProfilModules? profil = widget.profil;
    List<ProfilModules> tous = const <ProfilModules>[];

    try {
      tous = await _service.listerProfils();

      if (profil == null && widget.typeCode != null) {
        for (final ProfilModules candidat in tous) {
          if (candidat.type == widget.typeCode) {
            profil = candidat;
            break;
          }
        }
      }
    } on ModulesServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('TypeActiviteFormPage._initialiser: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement du formulaire.';
    }

    if (!mounted) return;

    // Mode édition demandé mais profil introuvable.
    if (messageErreur == null && profil == null && widget.estModification) {
      messageErreur =
          "Ce type d'activité est introuvable. Il a peut-être été supprimé.";
    }

    if (messageErreur != null) {
      setState(() {
        _erreurChargement = messageErreur;
        _chargement = false;
      });
      return;
    }

    setState(() {
      _profil = profil;
      _autres = tous
          .where((ProfilModules p) => p.type != profil?.type)
          .toList(growable: false);
      _libelleController.text = profil?.libelle ?? '';
      _codeController.text = profil?.type ?? '';
      _selection
        ..clear()
        ..addAll(profil?.modules ?? ModulesService.modulesBase);
      _actif = profil?.actif ?? true;
      _codePersonnalise = false;
      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // VALIDATION
  // ---------------------------------------------------------------------------

  String? _validerLibelle(String? valeur) {
    final String texte = (valeur ?? '').trim();

    if (texte.isEmpty) {
      return "Le nom du type d'activité est obligatoire.";
    }
    if (texte.length < 2) {
      return 'Le nom doit contenir au moins 2 caractères.';
    }
    if (texte.length > 60) {
      return 'Le nom est trop long (60 caractères maximum).';
    }

    final String recherche = texte.toLowerCase();
    final bool doublon = _autres.any(
      (ProfilModules autre) => autre.libelle.trim().toLowerCase() == recherche,
    );
    if (doublon) {
      return "Un type d'activité porte déjà ce nom.";
    }

    return null;
  }

  String? _validerCode(String? valeur) {
    final String texte = (valeur ?? '').trim().toLowerCase();

    if (texte.isEmpty) {
      return 'Le code technique est obligatoire.';
    }
    // Miroir de la validation SQL (`rpc_type_espace_modules_maj`).
    if (!RegExp(r'^[a-z][a-z0-9_]{1,40}$').hasMatch(texte)) {
      return 'Minuscules, chiffres et « _ » uniquement '
          '(ex : salon_de_coiffure).';
    }
    if (!widget.estModification &&
        _autres.any((ProfilModules autre) => autre.type == texte)) {
      return 'Ce code est déjà utilisé par un autre type.';
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // ENREGISTREMENT
  // ---------------------------------------------------------------------------

  Future<void> _enregistrer() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      _afficherMessage(
        'Veuillez corriger les champs signalés en rouge.',
        estErreur: true,
      );
      return;
    }

    final ProfilModules? profil = _profil;
    final bool estCreation = profil == null;

    setState(() => _enregistrement = true);

    String? messageErreur;
    try {
      await _service.enregistrerProfil(
        type: _codeController.text,
        libelle: _libelleController.text,
        modules: _selection,
        actif: _actif,
      );
    } on ModulesServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('TypeActiviteFormPage._enregistrer: $e\n$st');
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
      estCreation ? "Type d'activité créé avec succès." : 'Type modifié.',
    );
    Navigator.of(context).pop(true);
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

  /// Le profil « boutique » (repli universel) doit rester actif.
  bool get _profilProtege =>
      _codeController.text.trim().toLowerCase() == ModuleCode.profilDefaut ||
      (_profil?.profilDefaut ?? false);

  void _basculerModule(String code, bool? coche) {
    setState(() {
      if (coche == true) {
        _selection.add(code);
      } else {
        _selection.remove(code);
      }
    });
  }

  void _toutCocher(bool cocher) {
    setState(() {
      if (cocher) {
        _selection.addAll(
          ModuleActivite.catalogue.map((ModuleActivite m) => m.code),
        );
      } else {
        _selection.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool pret = !_chargement && _erreurChargement == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.estModification
              ? "Modifier le type d'activité"
              : "Nouveau type d'activité",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: _construireCorps(theme),
      bottomNavigationBar: pret ? _barreActions() : null,
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titreSection(theme, 'Informations', Icons.edit_note_rounded),
            const SizedBox(height: 12),
            TextFormField(
              controller: _libelleController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              enabled: !_enregistrement,
              decoration: InputDecoration(
                labelText: "Nom du type d'activité *",
                hintText: 'Ex. : Salon de coiffure',
                prefixIcon: const Icon(Icons.label_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: _validerLibelle,
              onChanged: (String valeur) {
                if (!widget.estModification && !_codePersonnalise) {
                  setState(() {
                    _codeController.text =
                        ModulesService.codeProfilDepuisLibelle(valeur);
                  });
                }
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _codeController,
              enabled: !widget.estModification && !_enregistrement,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
              ],
              decoration: InputDecoration(
                labelText: 'Code technique *',
                hintText: 'salon_de_coiffure',
                prefixIcon: const Icon(Icons.tag_rounded),
                helperText: widget.estModification
                    ? 'Le code ne peut plus être modifié après création.'
                    : 'Généré automatiquement depuis le nom — modifiable.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: _validerCode,
              onChanged: (_) {
                if (!widget.estModification) _codePersonnalise = true;
                setState(() {}); // rafraîchit l'état de la protection
              },
            ),
            const SizedBox(height: 16),
            _carteActivation(theme),
            const SizedBox(height: 20),
            _titreSection(theme, 'Modules', Icons.widgets_rounded),
            const SizedBox(height: 6),
            Text(
              'Cochez les modules de cette activité. Un module masque les '
              'écrans qui ne le concernent pas — les données restent intactes.',
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            _barreSelection(theme),
            const SizedBox(height: 6),
            for (final ModuleCategorie categorie in ModuleCategorie.values)
              if (_modulesDe(categorie).isNotEmpty) ...[
                _titreCategorie(theme, categorie),
                for (final ModuleActivite module in _modulesDe(categorie))
                  _ligneModule(module),
              ],
            if (_modulesInconnus.isNotEmpty) ...[
              const SizedBox(height: 8),
              _titreCategorie(theme, null),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final String code in _modulesInconnus)
                    InputChip(
                      label: Text(code),
                      avatar: const Icon(Icons.help_outline_rounded, size: 16),
                      onDeleted: _enregistrement
                          ? null
                          : () => _basculerModule(code, false),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Module(s) défini(s) par une version plus récente du '
                'référentiel : ils seront conservés tels quels.',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<ModuleActivite> _modulesDe(ModuleCategorie categorie) {
    return ModuleActivite.catalogue
        .where((ModuleActivite m) => m.categorie == categorie)
        .toList(growable: false);
  }

  Set<String> get _modulesInconnus => _selection
      .where((String code) => !ModuleActivite.codeConnu(code))
      .toSet();

  Widget _carteActivation(ThemeData theme) {
    final ProfilModules? profil = _profil;
    final bool protege = _profilProtege;

    String sousTitre;
    if (protege) {
      sousTitre = 'Profil par défaut de l\'application : il doit rester actif.';
    } else if (profil != null && profil.nbEspaces > 0) {
      sousTitre = '${profil.nbEspaces} entreprise'
          '${profil.nbEspaces > 1 ? 's' : ''} utilise'
          '${profil.nbEspaces > 1 ? 'nt' : ''} ce type.';
    } else {
      sousTitre = 'Un type inactif n\'est plus proposé aux entreprises.';
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        value: protege ? true : _actif,
        onChanged: protege || _enregistrement
            ? null
            : (bool valeur) => setState(() => _actif = valeur),
        title: const Text(
          'Type actif',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(sousTitre, style: const TextStyle(fontSize: 12)),
        secondary: Icon(
          _actif ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
          color: _actif
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _barreSelection(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '${_selection.length} module'
            '${_selection.length > 1 ? 's' : ''} coché'
            '${_selection.length > 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        TextButton(
          onPressed: _enregistrement ? null : () => _toutCocher(true),
          child: const Text('Tout cocher'),
        ),
        TextButton(
          onPressed: _enregistrement ? null : () => _toutCocher(false),
          child: const Text('Tout décocher'),
        ),
      ],
    );
  }

  Widget _titreCategorie(ThemeData theme, ModuleCategorie? categorie) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4, left: 2),
      child: Text(
        (categorie?.libelle ?? 'Autres modules').toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _ligneModule(ModuleActivite module) {
    final bool coche = _selection.contains(module.code);

    return CheckboxListTile(
      value: coche,
      onChanged: _enregistrement
          ? null
          : (bool? valeur) => _basculerModule(module.code, valeur),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      controlAffinity: ListTileControlAffinity.leading,
      secondary: Icon(
        module.icone,
        size: 20,
        color: coche
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              module.libelle,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          if (!module.disponible) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'bientôt',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        module.description,
        style: const TextStyle(fontSize: 12),
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
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _barreActions() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _enregistrement ? null : _enregistrer,
            icon: _enregistrement
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(
              _enregistrement
                  ? 'Enregistrement…'
                  : widget.estModification
                      ? 'Enregistrer les modifications'
                      : "Créer le type d'activité",
            ),
          ),
        ),
      ),
    );
  }

  Widget _vueErreur(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              _erreurChargement ?? 'Erreur inconnue.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _initialiser,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
