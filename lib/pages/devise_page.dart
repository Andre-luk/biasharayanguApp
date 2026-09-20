// lib/pages/devise_page.dart
//
// 🪙 MODULE 18 — ÉCRAN « DEVISE & CONVERSION ».
//
// Deux usages dans un seul écran :
//   • ENTREPRISE (`/settings/devise`) : le patron choisit la devise de
//     travail de son activité (CDF / USD) et, s'il le souhaite, son propre
//     taux de change « 1 USD = X CDF » ;
//   • PLATEFORME (`/admin/devises`, Super Admin) : taux de change par défaut
//     appliqué à toutes les entreprises + configuration ponctuelle d'une
//     entreprise.
//
// ⚠️ La devise est une UNITÉ D'AFFICHAGE/SAISIE : changer de devise ne
// convertit PAS les montants déjà enregistrés (la valeur reste identique).
// L'écran affiche cette règle et propose un SIMULATEUR de conversion.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/devise.dart';
import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/services/devise_service.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class DevisePage extends StatefulWidget {
  const DevisePage({super.key, this.modePlateforme = false});

  /// Mode plateforme : réglage du taux par défaut + configuration d'une
  /// entreprise (Super Admin).
  final bool modePlateforme;

  @override
  State<DevisePage> createState() => _DevisePageState();
}

class _DevisePageState extends State<DevisePage> {
  final DeviseService _service = DeviseService.instance;
  final TextEditingController _tauxCtrl = TextEditingController();
  final TextEditingController _simulationCtrl = TextEditingController();

  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;

  /// Taux imposé par l'entreprise (case « taux de la plateforme » décochée).
  bool _tauxPropre = false;

  /// Montant saisi dans le simulateur (dans la devise active).
  double _simulation = 0;

  // --- Mode plateforme -------------------------------------------------------
  final TextEditingController _tauxPlateformeCtrl = TextEditingController();
  Devise _devisePlateforme = Devise.cdf;
  List<Entreprise> _entreprises = const <Entreprise>[];
  Entreprise? _entrepriseCible;
  Devise? _deviseCible;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _tauxCtrl.dispose();
    _simulationCtrl.dispose();
    _tauxPlateformeCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    String? erreur;
    try {
      final EtatDevise configuration = await _service.charger();
      _appliquerSaisies(configuration);

      if (widget.modePlateforme) {
        final List<Entreprise> entreprises = await _entreprisesPourAdmin();
        if (mounted) setState(() => _entreprises = entreprises);
      }
    } on DeviseServiceException catch (e) {
      erreur = e.message;
    } catch (e) {
      erreur = 'Impossible de charger la configuration : $e';
    }

    if (!mounted) return;
    setState(() {
      _chargement = false;
      _erreur = erreur;
    });
  }

  /// Charge la liste des entreprises (mode plateforme) — best-effort.
  Future<List<Entreprise>> _entreprisesPourAdmin() async {
    try {
      return await EntrepriseService.instance.getEntreprises();
    } catch (e) {
      debugPrint('DevisePage : entreprises indisponibles ($e)');
      return const <Entreprise>[];
    }
  }

  /// Recopie l'état serveur dans les champs de saisie.
  void _appliquerSaisies(EtatDevise configuration) {
    _tauxPropre = configuration.tauxPropreEntreprise;
    _tauxCtrl.text = configuration.tauxPropreEntreprise
        ? _nombre(configuration.tauxEntreprise!)
        : _nombre(configuration.tauxUsdCdf);
    _tauxPlateformeCtrl.text = _nombre(configuration.tauxPlateforme);
    if (widget.modePlateforme) {
      _devisePlateforme = configuration.devisePlateforme;
      _deviseCible = null;
    }
  }

  static String _nombre(double valeur) =>
      valeur == valeur.roundToDouble()
          ? valeur.toStringAsFixed(0)
          : valeur
              .toStringAsFixed(2)
              .replaceAll(RegExp(r'0+$'), '')
              .replaceAll(RegExp(r'\.$'), '');

  void _snack(String message, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: erreur ? AppCouleurs.danger : AppCouleurs.succes,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS — ENTREPRISE
  // ---------------------------------------------------------------------------

  /// Change la devise de l'entreprise (avec confirmation explicite).
  Future<void> _choisirDevise(Devise devise) async {
    final EtatDevise configuration = _service.configuration;
    if (devise == configuration.devise) return;

    if (!configuration.peutModifier) {
      _snack(
        'Seul le propriétaire du compte peut changer la devise de travail.',
        erreur: true,
      );
      return;
    }

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Changer la devise de travail ?'),
        content: Text(
          'Votre entreprise va travailler en ${devise.libelle} '
          '(${devise.symbole}).\n\n'
          '⚠️ Les montants DÉJÀ ENREGISTRÉS ne sont pas convertis : '
          '15 000 restera 15 000, mais sera désormais lu comme '
          '15 000 ${devise.symbole} au lieu de '
          '15 000 ${configuration.devise.symbole}.\n\n'
          'Vérifiez vos prix (articles, chambres, commandes…) après le '
          'changement.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Travailler en ${devise.code}'),
          ),
        ],
      ),
    );

    if (confirme != true) return;
    await _enregistrer(devise: devise);
  }

  /// Enregistre le taux de change propre à l'entreprise.
  Future<void> _enregistrerTaux() async {
    final double? taux = double.tryParse(
      _tauxCtrl.text.trim().replaceAll(' ', '').replaceAll(',', '.'),
    );

    if (_tauxPropre && (taux == null || taux <= 0)) {
      _snack('Indiquez un taux positif (1 USD = X CDF).', erreur: true);
      return;
    }

    await _enregistrer(
      devise: _service.devise,
      taux: _tauxPropre ? taux : 0,
    );
  }

  Future<void> _enregistrer({required Devise devise, double? taux}) async {
    setState(() => _enregistrement = true);

    try {
      final EtatDevise configuration = await _service.configurer(
        devise: devise,
        taux: taux,
      );
      if (!mounted) return;
      _appliquerSaisies(configuration);
      setState(() => _enregistrement = false);
      _snack(
        'Devise enregistrée : ${configuration.devise.libelle} '
        '(${configuration.devise.symbole}) — '
        '1 USD = ${_nombre(configuration.tauxUsdCdf)} CDF.',
      );
    } on DeviseServiceException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _snack(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS — PLATEFORME
  // ---------------------------------------------------------------------------

  Future<void> _enregistrerPlateforme() async {
    final double? taux = double.tryParse(
      _tauxPlateformeCtrl.text.trim().replaceAll(' ', '').replaceAll(',', '.'),
    );

    if (taux == null || taux <= 0) {
      _snack('Indiquez un taux positif (1 USD = X CDF).', erreur: true);
      return;
    }

    setState(() => _enregistrement = true);
    try {
      final EtatDevise configuration = await _service.definirTauxPlateforme(
        taux: taux,
        deviseDefaut: _devisePlateforme,
      );
      if (!mounted) return;
      _appliquerSaisies(configuration);
      setState(() => _enregistrement = false);
      _snack('Taux de la plateforme : 1 USD = ${_nombre(taux)} CDF.');
    } on DeviseServiceException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _snack(e.message, erreur: true);
    }
  }

  Future<void> _configurerEntreprise() async {
    final Entreprise? entreprise = _entrepriseCible;
    final Devise? devise = _deviseCible;
    if (entreprise == null || devise == null) {
      _snack('Choisissez une entreprise et sa devise.', erreur: true);
      return;
    }

    setState(() => _enregistrement = true);
    try {
      await _service.configurer(
        devise: devise,
        entrepriseId: entreprise.id,
      );
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _snack('« ${entreprise.nom} » travaillera en ${devise.libelle}.');
    } on DeviseServiceException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _snack(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final EtatDevise configuration = _service.configuration;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.modePlateforme ? 'Devises & taux' : 'Devise & conversion',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: _chargement
          ? const Center(child: ModernLoader())
          : _erreur != null
              ? _vueErreur(_erreur!)
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: <Widget>[
                      if (widget.modePlateforme) ..._blocsPlateforme(),
                      if (!widget.modePlateforme) ..._blocsEntreprise(),
                      const SizedBox(height: 8),
                      _carteSimulateur(configuration),
                      const SizedBox(height: 16),
                      _carteRegle(),
                    ],
                  ),
                ),
    );
  }

  Widget _vueErreur(String message) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: FilledButton.icon(
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ),
      ],
    );
  }

  // --- Blocs entreprise ------------------------------------------------------

  List<Widget> _blocsEntreprise() {
    final EtatDevise configuration = _service.configuration;

    return <Widget>[
      _carte(
        titre: 'Devise de travail de votre entreprise',
        icone: Icons.currency_exchange_rounded,
        enfant: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Tous vos montants (prix des articles, ventes, dépenses, '
              'caisse, dettes, rapports, paiements) s\'affichent dans cette '
              'devise.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            for (final Devise devise in configuration.devises)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _tuileDevise(
                  devise: devise,
                  selectionnee: devise == configuration.devise,
                  onTap: configuration.peutModifier
                      ? () => _choisirDevise(devise)
                      : null,
                ),
              ),
            if (!configuration.peutModifier)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Seul le propriétaire du compte peut changer la devise.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _carteTauxChange(configuration),
      const SizedBox(height: 16),
    ];
  }

  Widget _tuileDevise({
    required Devise devise,
    required bool selectionnee,
    VoidCallback? onTap,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selectionnee
                ? scheme.primaryContainer.withValues(alpha: 0.55)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selectionnee ? scheme.primary : scheme.outlineVariant,
              width: selectionnee ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selectionnee
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  devise.symbole,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: devise.symbole.length > 1 ? 13 : 17,
                    color: selectionnee ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      devise.libelle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      'Code officiel : ${devise.code}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selectionnee)
                Icon(Icons.check_circle_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _carteTauxChange(EtatDevise configuration) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool actif = configuration.peutModifier;

    return _carte(
      titre: 'Taux de change',
      icone: Icons.swap_horiz_rounded,
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Utilisé pour afficher l\'équivalent de vos montants dans l\'autre '
            'devise (et par la plateforme pour vos abonnements).',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: !_tauxPropre,
            onChanged: actif
                ? (bool valeur) {
                    setState(() {
                      _tauxPropre = !valeur;
                      if (!_tauxPropre) {
                        _tauxCtrl.text = _nombre(configuration.tauxPlateforme);
                      }
                    });
                  }
                : null,
            title: const Text(
              'Utiliser le taux de la plateforme',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: Text(
              'Taux actuel de la plateforme : 1 USD = '
              '${_nombre(configuration.tauxPlateforme)} CDF',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _tauxCtrl,
                  enabled: actif && _tauxPropre,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Taux propre à l\'entreprise',
                    hintText: 'ex : 2850',
                    prefixIcon: const Icon(Icons.trending_up_rounded, size: 20),
                    suffixText: 'CDF',
                    enabled: actif && _tauxPropre,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '1 USD = ${_tauxCtrl.text.isEmpty ? '—' : _tauxCtrl.text} CDF',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          if (actif) ...<Widget>[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _enregistrement ? null : _enregistrerTaux,
              icon: _enregistrement
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('ENREGISTRER LE TAUX'),
            ),
          ],
        ],
      ),
    );
  }

  // --- Blocs plateforme ------------------------------------------------------

  List<Widget> _blocsPlateforme() {
    final EtatDevise configuration = _service.configuration;

    return <Widget>[
      _carte(
        titre: 'Taux de change par défaut (plateforme)',
        icone: Icons.public_rounded,
        enfant: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Ce taux s\'applique à toutes les entreprises qui n\'ont pas '
              'défini le leur (abonnements, équivalences, rapports '
              'plateforme).',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _tauxPlateformeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Taux de la plateforme',
                      hintText: 'ex : 2800',
                      prefixIcon: Icon(Icons.trending_up_rounded, size: 20),
                      suffixText: 'CDF',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppDropdownField<Devise>(
              label: 'Devise proposée par défaut',
              value: _devisePlateforme,
              prefixIcon: Icons.flag_outlined,
              items: <DropdownMenuItem<Devise>>[
                for (final Devise devise in configuration.devises)
                  DropdownMenuItem<Devise>(
                    value: devise,
                    child: Text('${devise.libelle} (${devise.symbole})'),
                  ),
              ],
              onChanged: (Devise? valeur) {
                if (valeur == null) return;
                setState(() => _devisePlateforme = valeur);
              },
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _enregistrement ? null : _enregistrerPlateforme,
              icon: const Icon(Icons.save_rounded),
              label: const Text('ENREGISTRER LE TAUX PLATEFORME'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _carte(
        titre: 'Configurer une entreprise',
        icone: Icons.apartment_rounded,
        enfant: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Force la devise d\'une entreprise précise (support client).',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            AppDropdownField<String>(
              label: 'Entreprise',
              value: _entrepriseCible?.id,
              prefixIcon: Icons.storefront_outlined,
              hint: _entreprises.isEmpty
                  ? 'Aucune entreprise chargée'
                  : 'Choisir une entreprise',
              items: <DropdownMenuItem<String>>[
                for (final Entreprise entreprise in _entreprises)
                  DropdownMenuItem<String>(
                    value: entreprise.id,
                    child: Text(entreprise.nom),
                  ),
              ],
              onChanged: (String? id) {
                if (id == null) return;
                setState(() {
                  _entrepriseCible = _entreprises.firstWhere(
                    (Entreprise e) => e.id == id,
                    orElse: () => _entreprises.first,
                  );
                });
              },
            ),
            const SizedBox(height: 12),
            AppDropdownField<Devise>(
              label: 'Devise',
              value: _deviseCible,
              prefixIcon: Icons.currency_exchange_rounded,
              hint: 'Choisir la devise',
              items: <DropdownMenuItem<Devise>>[
                for (final Devise devise in configuration.devises)
                  DropdownMenuItem<Devise>(
                    value: devise,
                    child: Text('${devise.libelle} (${devise.symbole})'),
                  ),
              ],
              onChanged: (Devise? valeur) => setState(() => _deviseCible = valeur),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: _enregistrement ? null : _configurerEntreprise,
              icon: const Icon(Icons.check_rounded),
              label: const Text('APPLIQUER LA DEVISE'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  // --- Simulateur & règle ----------------------------------------------------

  Widget _carteSimulateur(EtatDevise configuration) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Devise source = configuration.devise;
    final Devise cible = configuration.deviseOpposee;
    final double converti = configuration.convertir(
      _simulation,
      deviseSource: source,
      deviseCible: cible,
    );

    return _carte(
      titre: 'Simulateur de conversion',
      icone: Icons.calculate_rounded,
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '1 USD = ${_nombre(configuration.tauxUsdCdf)} CDF '
            '${configuration.tauxPropreEntreprise ? '(taux de votre entreprise)' : '(taux de la plateforme)'}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _simulationCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Montant à convertir',
              hintText: 'ex : 100000',
              prefixIcon: const Icon(Icons.payments_outlined, size: 20),
              suffixText: source.symbole,
            ),
            onChanged: (String valeur) {
              final double? saisi = double.tryParse(
                valeur.trim().replaceAll(' ', '').replaceAll(',', '.'),
              );
              setState(() => _simulation = saisi ?? 0);
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${_afficher(_simulation)} ${source.symbole}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '= ${_afficher(converti)} ${cible.symbole}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _afficher(double valeur) {
    final String fixe = valeur.abs().toStringAsFixed(2);
    final List<String> parties = fixe.split('.');
    final String entiere = parties.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (Match m) => '${m[1]} ',
    );
    final String decimales = parties.last == '00' ? '' : ',${parties.last}';
    return '${valeur < 0 ? '-' : ''}$entiere$decimales';
  }

  Widget _carteRegle() {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppCouleurs.marine.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppCouleurs.marine),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Changer de devise change l\'UNITÉ affichée, pas les montants '
              'enregistrés : 15 000 CDF devient 15 000 USD avec le même '
              'nombre. Ajustez vos prix après un changement si nécessaire '
              '(le simulateur ci-dessus vous aide à convertir).',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _carte({
    required String titre,
    required IconData icone,
    required Widget enfant,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icone, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titre,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          enfant,
        ],
      ),
    );
  }
}
