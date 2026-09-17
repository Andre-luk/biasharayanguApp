// lib/pages/agent_ia_config_page.dart
//
// MODULE 13 — ÉCRAN « CONFIGURATION IA » (Étape 7 — SUPER ADMIN uniquement).
//
//   • tarif par quota (borné 100 à 150 CDF — exigence du cahier des charges) ;
//   • caractères comptant pour 1 quota (défaut 20) ;
//   • prix du pack de 10 quotas (les packs 20 / 50 / 100 sont proportionnels) ;
//   • quotas offerts à l'ouverture du pool d'une entreprise (bienvenue) ;
//   • activation / désactivation de l'assistant.
//
// Chaque enregistrement passe par `rpc_agent_ia_config_maj` (Super Admin
// revérifié côté serveur) et est journalisé (action `AGENT_IA_CONFIG`,
// niveau CRITIQUE).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/agent_ia.dart';
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

  bool _actif = true;
  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;

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
        _actif = config.actif;
        _chargement = false;
      });
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

    // — Validations locales (le serveur revalide de toute façon) —
    if (tarif == null || tarif < 100 || tarif > 150) {
      _snack('Tarif invalide : entre 100 et 150 CDF par quota.', erreur: true);
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

    setState(() => _enregistrement = true);
    try {
      await _service.majConfig(
        AgentIaConfig(
          tarifParQuota: tarif,
          caracteresParQuota: caracteres,
          prixPack10Quotas: pack10,
          quotasOffertsInscription: offerts,
          actif: _actif,
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
                          label: 'Tarif par quota (CDF — 100 à 150)',
                          clavier: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _champ(
                          _caracteresController,
                          label: 'Caractères par quota (défaut 20)',
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

  Widget _exemple() {
    final int caracteres =
        int.tryParse(_caracteresController.text.trim()) ?? 20;
    final double tarif = double.tryParse(_tarifController.text.trim()) ?? 150;

    const int tailleExemple = 105;
    final int quotas = caracteres > 0
        ? (tailleExemple / caracteres).ceil().clamp(1, 1 << 30)
        : 1;
    final double montant = quotas * tarif;

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
              '(au tarif de ${formatMontant(tarif)}/quota).',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
