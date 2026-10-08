// lib/pages/niveau_abonnement_form_page.dart
//
// 🧩 CORRECTIF 65 — FICHE D'UN NIVEAU D'ABONNEMENT (création / modification).
//
// On y règle : le code (identité), le nom affiché, l'ordre, le prix mensuel
// CONSEILLÉ, l'état, et surtout la LISTE DES FONCTIONNALITÉS ouvertes.
//
// `["*"]` = toutes les fonctionnalités de l'activité : c'est le niveau le plus
// élevé, et il restera correct quand de nouvelles fonctionnalités seront
// ajoutées à l'application. D'où l'interrupteur « tout » en tête.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/fonctionnalites.dart';
import 'package:biashara_yangu/models/niveau_abonnement.dart';
import 'package:biashara_yangu/services/abonnement_niveaux_service.dart';

class NiveauAbonnementFormPage extends StatefulWidget {
  /// Code du niveau à modifier. `null` = création.
  const NiveauAbonnementFormPage({super.key, this.code});

  final String? code;

  @override
  State<NiveauAbonnementFormPage> createState() =>
      _NiveauAbonnementFormPageState();
}

class _NiveauAbonnementFormPageState extends State<NiveauAbonnementFormPage> {
  final NiveauxAbonnementService _service = NiveauxAbonnementService.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _libelleController = TextEditingController();
  final TextEditingController _ordreController = TextEditingController();
  final TextEditingController _prixController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  Set<String> _fonctionnalites = <String>{};
  bool _toutes = false;
  bool _actif = true;

  bool _chargement = false;
  bool _enregistrement = false;

  bool get _estModification => (widget.code ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_estModification) {
      _charger();
    } else {
      _ordreController.text = '0';
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _libelleController.dispose();
    _ordreController.dispose();
    _prixController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final List<NiveauAbonnement> niveaux = await _service.lister();
      final String code = widget.code!.trim();

      NiveauAbonnement? trouve;
      for (final NiveauAbonnement n in niveaux) {
        if (n.code == code) {
          trouve = n;
          break;
        }
      }

      if (!mounted) return;

      if (trouve == null) {
        setState(() => _chargement = false);
        _message('Ce niveau n\'existe plus.', erreur: true);
        return;
      }

      final NiveauAbonnement niveau = trouve;
      setState(() {
        _codeController.text = niveau.code;
        _libelleController.text = niveau.libelle;
        _ordreController.text = niveau.ordre.toString();
        _prixController.text = niveau.prixMensuelConseille == null
            ? ''
            : niveau.prixMensuelConseille!.round().toString();
        _descriptionController.text = niveau.description ?? '';
        _toutes = niveau.toutesLesFonctionnalites;
        _fonctionnalites = Set<String>.from(niveau.fonctionnalites);
        _actif = niveau.actif;
        _chargement = false;
      });
    } on NiveauxAbonnementException catch (e) {
      if (!mounted) return;
      setState(() => _chargement = false);
      _message(e.message, erreur: true);
    }
  }

  void _message(String texte, {bool erreur = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _enregistrer() async {
    if (_formKey.currentState?.validate() != true) return;

    final Set<String> fonctionnalites = _toutes
        ? <String>{Fonctionnalites.joker}
        : Set<String>.from(_fonctionnalites);

    if (!_toutes && fonctionnalites.isEmpty) {
      _message(
        'Choisissez au moins une fonctionnalité, ou activez « tout ».',
        erreur: true,
      );
      return;
    }

    final double? prix = _prixController.text.trim().isEmpty
        ? null
        : double.tryParse(
            _prixController.text.trim().replaceAll(',', '.').replaceAll(' ', ''),
          );

    setState(() => _enregistrement = true);

    try {
      await _service.enregistrer(
        NiveauAbonnement(
          code: _codeController.text.trim().toUpperCase(),
          libelle: _libelleController.text.trim(),
          ordre: int.tryParse(_ordreController.text.trim()) ?? 0,
          prixMensuelConseille: prix,
          fonctionnalites: fonctionnalites,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          actif: _actif,
        ),
      );

      if (!mounted) return;
      _message(_estModification
          ? 'Niveau modifié.'
          : 'Niveau créé.');
      context.pop(true);
    } on NiveauxAbonnementException catch (e) {
      if (!mounted) return;
      _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _estModification ? 'Modifier le niveau' : 'Nouveau niveau',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: <Widget>[
                  TextFormField(
                    controller: _codeController,
                    enabled: !_estModification,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
                      LengthLimitingTextInputFormatter(24),
                    ],
                    decoration: _decoration(
                      'Code (identité du niveau)',
                      aide: _estModification
                          ? 'Le code ne change pas : il est déjà utilisé.'
                          : 'Lettres, chiffres et souligné. Ex. : ESSENTIEL',
                    ),
                    validator: (String? v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Le code est obligatoire.'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _libelleController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _decoration('Nom affiché',
                        aide: 'Ce que le commerçant lira. Ex. : Essentiel'),
                    validator: (String? v) => (v == null || v.trim().isEmpty)
                        ? 'Le nom est obligatoire.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: _ordreController,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration:
                              _decoration('Ordre', aide: '1, 2, 3…'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _prixController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                          ],
                          decoration: _decoration(
                            'Prix conseillé / mois',
                            aide: 'Indicatif — jamais facturé',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration:
                        _decoration('Description (optionnelle)'),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    value: _actif,
                    onChanged: (bool v) => setState(() => _actif = v),
                    title: const Text('Niveau actif'),
                    subtitle: const Text(
                      'Un niveau inactif reste au catalogue mais ne s\'applique '
                      'plus aux entreprises qui le portent.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(height: 28),
                  _sectionFonctionnalites(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _enregistrement ? null : _enregistrer,
                      icon: _enregistrement
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: const Text('Enregistrer le niveau'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionFonctionnalites() {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.widgets_rounded, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Fonctionnalités ouvertes par ce niveau',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _toutes,
          onChanged: (bool v) => setState(() => _toutes = v),
          title: const Text('Tout — toutes les fonctionnalités'),
          subtitle: const Text(
            'Recommandé pour le niveau le plus élevé : il restera correct même '
            'quand de nouvelles fonctionnalités seront ajoutées.',
          ),
          contentPadding: EdgeInsets.zero,
        ),
        if (!_toutes) ...<Widget>[
          const SizedBox(height: 4),
          for (final String famille in Fonctionnalites.familles) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              famille.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final Fonctionnalite f
                in Fonctionnalites.deLaFamille(famille))
              CheckboxListTile(
                value: _fonctionnalites.contains(f.code),
                onChanged: (bool? v) {
                  setState(() {
                    if (v == true) {
                      _fonctionnalites.add(f.code);
                    } else {
                      _fonctionnalites.remove(f.code);
                    }
                  });
                },
                title: Text(f.libelle),
                subtitle: Text(
                  f.code,
                  style: const TextStyle(fontSize: 11),
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
          const SizedBox(height: 8),
          Text(
            '${_fonctionnalites.length} fonctionnalité'
            '${_fonctionnalites.length > 1 ? 's' : ''} sélectionnée'
            '${_fonctionnalites.length > 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _decoration(String label, {String? aide}) {
    return InputDecoration(
      labelText: label,
      helperText: aide,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
