// lib/pages/agent_ia_config_page.dart
//
// MODULE 13 — ÉCRAN « CONFIGURATION IA » (Étape 7 — SUPER ADMIN uniquement).
//
//   • tarif par quota (1 à 1000 CDF depuis le module 13 bis) ;
//   • caractères comptant pour 1 quota (défaut 400) ;
//   • prix du pack de 10 quotas (les packs 20 / 50 / 100 sont proportionnels) ;
//   • quotas offerts à l'ouverture du pool d'une entreprise (bienvenue) ;
//   • activation / désactivation de l'assistant ;
//   • MODULE 13 bis : coefficient de marge, coûts réels DeepSeek (pointe/creuse),
//     change CDF/USD et seuil d'alerte de solde.
//
// Un bouton donne accès à l'écran « Tokens IA » (coût réel, bénéfice,
// distribution et journal des appels).
//
// Chaque enregistrement passe par `rpc_agent_ia_config_maj` (Super Admin
// revérifié côté serveur) et est journalisé (action `AGENT_IA_CONFIG`,
// niveau CRITIQUE).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/agent_ia.dart';
import 'package:biashara_yangu/pages/tokens_ia_page.dart';
import 'package:biashara_yangu/services/agent_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Écran de configuration de l'assistant IA (Super Admin).
class AgentIaConfigPage extends StatefulWidget {
  const AgentIaConfigPage({super.key});

  @override
  State<AgentIaConfigPage> createState() => _AgentIaConfigPageState();
}

class _AgentIaConfigPageState extends State<AgentIaConfigPage> {
  final AgentService _service = AgentService.instance;
  final TextEditingController _tarifController = TextEditingController();
  final TextEditingController _caracteresController = TextEditingController();
  final TextEditingController _pack10Controller = TextEditingController();
  final TextEditingController _offertsController = TextEditingController();
  final TextEditingController _margeController = TextEditingController();
  final TextEditingController _tauxController = TextEditingController();
  final TextEditingController _coutEntreeController = TextEditingController();
  final TextEditingController _coutCacheController = TextEditingController();
  final TextEditingController _coutSortieController = TextEditingController();
  final TextEditingController _alerteController = TextEditingController();

  bool _actif = true;
  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;

  /// 🪙 CORRECTIF 68 — CATALOGUE DES PACKS.
  ///  Les packs étaient codés en dur dans l'application (10/20/50/100 à prix
  ///  strictement proportionnels) : impossible de créer un pack de 30 ou de
  ///  faire une remise sur les gros packs sans republier l'application.
  ///  Ils viennent désormais de la base. `vientDeLaBase == false` signale le
  ///  repli local (migration 68 pas encore exécutée) : on l'affiche, pour ne
  ///  pas laisser croire que les modifications ont été enregistrées.
  List<PackQuotas> _packs = const <PackQuotas>[];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _tarifController.dispose();
    _caracteresController.dispose();
    _pack10Controller.dispose();
    _offertsController.dispose();
    _margeController.dispose();
    _tauxController.dispose();
    _coutEntreeController.dispose();
    _coutCacheController.dispose();
    _coutSortieController.dispose();
    _alerteController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final AgentIaConfig config = await _service.chargerConfig();
      if (!mounted) return;
      setState(() {
        _tarifController.text = _texte(config.tarifParQuota);
        _caracteresController.text = '${config.caracteresParQuota}';
        _pack10Controller.text = _texte(config.prixPack10Quotas);
        _offertsController.text = '${config.quotasOffertsInscription}';
        _margeController.text = _texte(config.tauxMarge);
        _tauxController.text = _texte(config.tauxUsdCdf);
        _coutEntreeController.text = _texte(config.coutCdfParMillionEntree);
        _coutCacheController.text = _texte(config.coutCdfParMillionCache);
        _coutSortieController.text = _texte(config.coutCdfParMillionSortie);
        _alerteController.text = _texte(config.alerteSoldeUsd);
        _actif = config.actif;
        _chargement = false;
      });

      //  Le catalogue est chargé À PART : s'il échoue (migration absente), la
      //  configuration doit rester utilisable — on retombe alors sur la
      //  grille de repli, signalée comme telle.
      final List<PackQuotas> packs = await _service.chargerPacks(
        config: config,
        inclureInactifs: true,
      );
      if (!mounted) return;
      setState(() => _packs = packs);
    } on AgentServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e) {
      debugPrint('AgentIaConfigPage._charger : $e');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger la configuration.';
        _chargement = false;
      });
    }
  }

  static String _texte(double valeur) {
    if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
    return valeur.toString();
  }

  Future<void> _enregistrer() async {
    final double? tarif = double.tryParse(_tarifController.text.trim());
    final int? caracteres = int.tryParse(_caracteresController.text.trim());
    final double? pack10 = double.tryParse(_pack10Controller.text.trim());
    final int? offerts = int.tryParse(_offertsController.text.trim());
    final double? marge = double.tryParse(_margeController.text.trim());
    final double? taux = double.tryParse(_tauxController.text.trim());
    final double? coutEntree = double.tryParse(_coutEntreeController.text.trim());
    final double? coutCache = double.tryParse(_coutCacheController.text.trim());
    final double? coutSortie = double.tryParse(_coutSortieController.text.trim());
    final double? alerte = double.tryParse(_alerteController.text.trim());

    // — Validations locales (le serveur revalide de toute façon) —
    if (tarif == null || tarif < 1 || tarif > 1000) {
      _snack('Tarif invalide : entre 1 et 1000 CDF par quota.', erreur: true);
      return;
    }
    if (caracteres == null || caracteres < 1 || caracteres > 500) {
      _snack('Caractères par quota : entre 1 et 500.', erreur: true);
      return;
    }
    if (pack10 == null || pack10 < 0) {
      _snack('Prix du pack de 10 invalide.', erreur: true);
      return;
    }
    if (offerts == null || offerts < 0 || offerts > 1000) {
      _snack('Quotas offerts : entre 0 et 1000.', erreur: true);
      return;
    }
    if (marge == null || marge < 1 || marge > 1000) {
      _snack('Coefficient de marge : entre 1 et 1000.', erreur: true);
      return;
    }
    if (taux == null || taux <= 0) {
      _snack('Change invalide : indiquez un taux supérieur à 0.', erreur: true);
      return;
    }
    if (coutEntree == null || coutEntree < 0 ||
        coutCache == null || coutCache < 0 ||
        coutSortie == null || coutSortie < 0) {
      _snack('Les coûts par million de tokens doivent être positifs.', erreur: true);
      return;
    }
    if (alerte == null || alerte < 0) {
      _snack('Seuil d\'alerte invalide.', erreur: true);
      return;
    }

    setState(() => _enregistrement = true);
    try {
      await _service.majConfig(
        AgentIaConfig(
          tarifParQuota: tarif,
          caracteresParQuota: caracteres,
          prixPack10Quotas: pack10,
          quotasOffertsInscription: offerts,
          actif: _actif,
          tauxMarge: marge,
          tauxUsdCdf: taux,
          coutCdfParMillionEntree: coutEntree,
          coutCdfParMillionCache: coutCache,
          coutCdfParMillionSortie: coutSortie,
          alerteSoldeUsd: alerte,
        ),
      );
      if (!mounted) return;
      _snack('Configuration enregistrée (journalisée).');
    } on AgentServiceException catch (e) {
      if (!mounted) return;
      _snack(e.message, erreur: true);
    } catch (e) {
      debugPrint('AgentIaConfigPage._enregistrer : $e');
      if (!mounted) return;
      _snack('Enregistrement impossible : vérifiez votre réseau.', erreur: true);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  void _snack(String message, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: erreur ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🪙 CORRECTIF 68 — CATALOGUE DES PACKS
  // ---------------------------------------------------------------------------

  /// Vrai si les packs affichés viennent réellement de la base.
  bool get _catalogueEnBase => _packs.any((PackQuotas p) => p.vientDeLaBase);

  /// Crée (pack == null) ou modifie un pack.
  ///
  /// ⚠️ La TAILLE n'est proposée QU'À LA CRÉATION : le serveur la verrouille
  /// pour un pack existant, car un pack EST une taille. Le laisser modifiable
  /// ferait croire qu'on peut transformer un « pack de 10 » en « pack de 30 »,
  /// alors que les clients ont déjà acheté l'ancien.
  Future<void> _editerPack({PackQuotas? pack}) async {
    final bool creation = pack == null;
    final TextEditingController quotas =
        TextEditingController(text: creation ? '' : '${pack.quotas}');
    final TextEditingController prix = TextEditingController(
      text: creation ? '' : _texte(pack.prix),
    );
    final TextEditingController libelle =
        TextEditingController(text: pack?.libelle ?? '');
    final TextEditingController ordre =
        TextEditingController(text: '${pack?.ordre ?? 0}');
    bool actif = pack?.actif ?? true;

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setEtat) => AlertDialog(
          title: Text(creation ? 'Nouveau pack de quotas' : 'Modifier le pack'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: quotas,
                  enabled: creation,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Nombre de quotas',
                    helperText: creation
                        ? 'Définitif : un pack EST une taille.'
                        : 'La taille d\'un pack ne peut plus changer.',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: prix,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Prix (CDF)',
                    helperText: 'Le client paie exactement ce prix.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: libelle,
                  decoration: const InputDecoration(
                    labelText: 'Nom commercial (optionnel)',
                    hintText: 'Pack boutique',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ordre,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ordre d\'affichage',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: actif,
                  onChanged: (bool v) => setEtat(() => actif = v),
                  title: const Text('Pack proposé aux clients'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Renoncer'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(creation ? 'Créer' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (valide != true) {
      _liberer(<TextEditingController>[quotas, prix, libelle, ordre]);
      return;
    }

    final int? quotasSaisis = int.tryParse(quotas.text.trim());
    final double? prixSaisi = double.tryParse(prix.text.trim().replaceAll(',', '.'));

    if (quotasSaisis == null || quotasSaisis < 1) {
      _snack('Indiquez un nombre de quotas valide.', erreur: true);
      _liberer(<TextEditingController>[quotas, prix, libelle, ordre]);
      return;
    }
    if (prixSaisi == null || prixSaisi < 0) {
      _snack('Indiquez un prix valide.', erreur: true);
      _liberer(<TextEditingController>[quotas, prix, libelle, ordre]);
      return;
    }

    setState(() => _enregistrement = true);
    try {
      await _service.enregistrerPack(
        id: pack?.id,
        quotas: quotasSaisis,
        prix: prixSaisi,
        libelle: libelle.text.trim().isEmpty ? null : libelle.text.trim(),
        ordre: int.tryParse(ordre.text.trim()),
        actif: actif,
      );
      _snack(creation ? 'Pack créé.' : 'Pack enregistré.');
      await _charger();
    } on AgentServiceException catch (e) {
      _snack(e.message, erreur: true);
    } finally {
      _liberer(<TextEditingController>[quotas, prix, libelle, ordre]);
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  Future<void> _supprimerPack(PackQuotas pack) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Supprimer ce pack ?'),
        content: Text(
          '${pack.libelleAffiche} — ${pack.quotas} quotas.\n\n'
          'Les achats DÉJÀ effectués ne sont pas touchés. Préférez la '
          'désactivation : elle fait disparaître le pack de la grille sans '
          'effacer son histoire.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Renoncer'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirme != true || pack.id == null) return;

    setState(() => _enregistrement = true);
    try {
      await _service.supprimerPack(pack.id!);
      _snack('Pack supprimé.');
      await _charger();
    } on AgentServiceException catch (e) {
      _snack(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  static void _liberer(List<TextEditingController> controleurs) {
    for (final TextEditingController c in controleurs) {
      c.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.estSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuration IA')),
        body: const AccesRefuse(
          message: 'Cet écran est réservé au Super Admin.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Configuration IA',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Gestion des tokens (coût et bénéfice)',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TokensIaPage(),
              ),
            ),
            icon: const Icon(Icons.data_usage_rounded),
          ),
          IconButton(
            tooltip: 'Recharger',
            onPressed: _chargement ? null : _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(_erreur!, textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _charger,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: <Widget>[
                    _carte(
                      titre: 'Tarifs',
                      icone: Icons.paid_rounded,
                      enfants: <Widget>[
                        _champ(
                          _tarifController,
                          label: 'Tarif par quota (CDF — 1 à 1000)',
                          clavier: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _champ(
                          _caracteresController,
                          label: 'Caractères par quota (défaut 400)',
                          clavier: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _champ(
                          _pack10Controller,
                          label: 'Prix du pack de 10 quotas (CDF)',
                          clavier: TextInputType.number,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _carteCataloguePacks(),
                    const SizedBox(height: 16),
                    _carte(
                      titre: 'Bienvenue & activation',
                      icone: Icons.card_giftcard_rounded,
                      enfants: <Widget>[
                        _champ(
                          _offertsController,
                          label: 'Quotas offerts (par entreprise, une fois)',
                          clavier: TextInputType.number,
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _actif,
                          onChanged: _enregistrement
                              ? null
                              : (bool valeur) => setState(() => _actif = valeur),
                          title: const Text(
                            'Assistant IA activé',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: const Text(
                            'Désactivé : plus aucune réponse, aucune demande de pack.',
                            style: TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _carte(
                      titre: 'Coûts réels & marge',
                      icone: Icons.trending_up_rounded,
                      enfants: <Widget>[
                        _champ(
                          _margeController,
                          label: 'Coefficient de marge (16 = objectif ×16)',
                          clavier: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _champ(
                          _tauxController,
                          label: 'Change (CDF pour 1 USD)',
                          clavier: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _champ(
                          _coutEntreeController,
                          label: 'Coût / million tokens ENTRÉE (CDF)',
                          clavier: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _champ(
                          _coutCacheController,
                          label: 'Coût / million tokens ENTRÉE CACHÉS (CDF)',
                          clavier: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _champ(
                          _coutSortieController,
                          label: 'Coût / million tokens SORTIE (CDF)',
                          clavier: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _champ(
                          _alerteController,
                          label: 'Seuil d\'alerte de solde (USD)',
                          clavier: TextInputType.number,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Ces valeurs servent à calculer le coût réel de chaque '
                          'appel et à vérifier la marge. Les défauts correspondent '
                          'aux tarifs de pointe de DeepSeek (worst case) : la marge '
                          'affichée est donc un minimum.',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _enregistrement
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const TokensIaPage(),
                                      ),
                                    ),
                            icon: const Icon(Icons.insights_rounded),
                            label: const Text('Voir coût, bénéfice et distribution'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _exemple(),
                    const SizedBox(height: 18),
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
                        label: const Text('Enregistrer la configuration'),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _carte({
    required String titre,
    required IconData icone,
    required List<Widget> enfants,
  }) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icone, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                titre,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...enfants,
        ],
      ),
    );
  }

  Widget _champ(
    TextEditingController controller, {
    required String label,
    TextInputType? clavier,
  }) {
    return TextField(
      controller: controller,
      enabled: !_enregistrement,
      keyboardType: clavier,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _carteCataloguePacks() {
    final ThemeData theme = Theme.of(context);

    return _carte(
      titre: 'Catalogue des packs de quotas',
      icone: Icons.inventory_2_rounded,
      enfants: <Widget>[
        //  Signalé CLAIREMENT : sans cette mention, le Super Admin pourrait
        //  croire que ses modifications ont été enregistrées alors que la
        //  grille affichée est celle de repli.
        if (!_catalogueEnBase)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange, width: 0.8),
            ),
            child: const Text(
              'Grille locale : la migration 68 n''est pas encore exécutée. Les '
              'packs ci-dessous sont ceux d''origine — aucune modification ne '
              'sera conservée.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        const Text(
          'Le client paie EXACTEMENT le prix du pack choisi. La taille d''un '
          'pack est définitive : pour passer de 10 à 30 quotas, créez un '
          'nouveau pack puis désactivez l''ancien.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (_packs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Aucun pack : plus aucun achat n''est possible.',
              style: TextStyle(fontSize: 12.5),
            ),
          )
        else
          ..._packs.map((PackQuotas pack) => _lignePack(theme, pack)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _enregistrement ? null : () => _editerPack(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nouveau pack'),
          ),
        ),
      ],
    );
  }

  Widget _lignePack(ThemeData theme, PackQuotas pack) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: pack.actif
              ? theme.colorScheme.outlineVariant
              : theme.colorScheme.error.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '${pack.quotas} quotas',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(pack.libelleAffiche,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    if (!pack.actif) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        'désactivé',
                        style: TextStyle(
                            fontSize: 11, color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatMontant(pack.prix)} • '
                  '${formatMontant(pack.prixParQuota)} par quota',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          //  Un pack de repli n'existe pas en base : le modifier ou le
          //  supprimer n'aurait aucun effet. On le dit plutôt que d'offrir un
          //  bouton qui ne fait rien.
          if (pack.vientDeLaBase) ...<Widget>[
            IconButton(
              tooltip: 'Modifier',
              onPressed:
                  _enregistrement ? null : () => _editerPack(pack: pack),
              icon: const Icon(Icons.edit_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Supprimer',
              onPressed:
                  _enregistrement ? null : () => _supprimerPack(pack),
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('local', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _exemple() {
    final int caracteres =
        int.tryParse(_caracteresController.text.trim()) ?? 400;
    final double tarif = double.tryParse(_tarifController.text.trim()) ?? 96;

    const int tailleExemple = 400;
    final int quotas = caracteres > 0
        ? (tailleExemple / caracteres).ceil().clamp(1, 1 << 30)
        : 1;
    final double montant = quotas * tarif;
    final double parCaractere = caracteres > 0 ? tarif / caracteres : 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.calculate_rounded, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Exemple : une réponse de $tailleExemple caractères → '
              '$quotas quota(s) → ${formatMontant(montant)} '
              '(au tarif de ${formatMontant(tarif)}/quota, soit '
              '${formatMontant(parCaractere)} le caractère).',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
