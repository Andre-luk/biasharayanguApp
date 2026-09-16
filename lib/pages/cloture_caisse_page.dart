// lib/pages/cloture_caisse_page.dart
//
// MODULE 10 — CLÔTURE DE CAISSE.
//
// Le serveur fige la journée dans `clotures_caisse` : totaux calculés en
// temps réel, fond de caisse déclaré, espèce comptée, écart et commentaire.
// L'écart se calcule sur l'ESPÈCE :
//
//   attendu = fond initial + encaissements espèces − dépenses (espèces)
//   écart   = espèce comptée − attendu

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/mouvement_caisse.dart';
import 'package:biashara_yangu/services/finance_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class ClotureCaissePage extends StatefulWidget {
  const ClotureCaissePage({super.key});

  @override
  State<ClotureCaissePage> createState() => _ClotureCaissePageState();
}

class _ClotureCaissePageState extends State<ClotureCaissePage> {
  final FinanceService _finance = FinanceService.instance;

  final TextEditingController _fondCtrl = TextEditingController(text: '0');
  final TextEditingController _compteeCtrl = TextEditingController();
  final TextEditingController _commentaireCtrl = TextEditingController();

  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;
  ResumeCaisse? _resume;

  @override
  void initState() {
    super.initState();
    _fondCtrl.addListener(_rafraichir);
    _compteeCtrl.addListener(_rafraichir);
    _charger();
  }

  @override
  void dispose() {
    _fondCtrl.dispose();
    _compteeCtrl.dispose();
    _commentaireCtrl.dispose();
    super.dispose();
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final ResumeCaisse resume = await _finance.resumeCaisse();
      if (!mounted) return;
      setState(() => _resume = resume);
    } on FinanceServiceException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'Impossible de charger la caisse : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  // ---------------------------------------------------------------------------
  // CALCULS
  // ---------------------------------------------------------------------------

  double get _fondInitial {
    final String texte = _fondCtrl.text.replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(texte) ?? 0;
  }

  double? get _especeComptee {
    final String texte = _compteeCtrl.text.replaceAll(' ', '').replaceAll(',', '.');
    if (texte.trim().isEmpty) return null;
    return double.tryParse(texte);
  }

  /// Espèces attendues : fond + encaissements espèces − décaissements espèces.
  double get _attenduEspeces {
    final ResumeCaisse? resume = _resume;
    if (resume == null) return _fondInitial;
    final MouvementParMode? especes = resume.parMode['especes'];
    final double encaissements = especes?.encaissements ?? 0;
    final double decaissements = especes?.decaissements ?? 0;
    return _fondInitial + encaissements - decaissements;
  }

  double? get _ecart {
    final double? comptee = _especeComptee;
    if (comptee == null) return null;
    return comptee - _attenduEspeces;
  }

  Future<void> _valider() async {
    final ResumeCaisse? resume = _resume;
    if (resume == null) return;

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clôturer la caisse ?'),
        content: Text(
          'Journée du ${formatDate(DateTime.now())}\n\n'
          'Encaissements : ${formatMontant(resume.jour.encaissements)}\n'
          'Décaissements : ${resume.jour.decaissements == null ? '—' : formatMontant(resume.jour.decaissements!)}\n'
          '${_especeComptee == null ? '' : 'Écart espèces : ${_ecart! >= 0 ? '+' : ''}${formatMontant(_ecart!)}\n'}'
          '\nLes totaux seront figés et la clôture tracée dans le journal.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );

    if (confirme != true) return;

    setState(() => _enregistrement = true);
    try {
      final ResultatClotureCaisse resultat = await _finance.cloturerCaisse(
        fondInitial: _fondInitial,
        especeComptee: _especeComptee,
        commentaire: _commentaireCtrl.text,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Row(
            children: <Widget>[
              Icon(Icons.check_circle_rounded, color: Colors.green),
              SizedBox(width: 8),
              Text('Caisse clôturée'),
            ],
          ),
          content: Text(
            'Journée du ${formatDate(resultat.dateCloture)}\n\n'
            'Encaissements : ${formatMontant(resultat.encaissementsTotal)}\n'
            'Décaissements : ${formatMontant(resultat.decaissementsTotal)}\n'
            'Solde théorique : ${formatMontant(resultat.soldeTheorique)}\n'
            '${resultat.especeComptee == null ? '' : 'Espèce comptée : ${formatMontant(resultat.especeComptee!)}\n'}'
            '${resultat.ecart == null ? '' : 'Écart : ${resultat.ecart! >= 0 ? '+' : ''}${formatMontant(resultat.ecart!)}'}\n'
            '${resultat.commentaire == null || resultat.commentaire!.isEmpty ? '' : '\n« ${resultat.commentaire} »'}',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Terminer'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FinanceServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur inattendue : $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  // ---------------------------------------------------------------------------
  // RENDU
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Clôture de caisse',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.cloud_off_rounded,
                            size: 56, color: theme.colorScheme.error),
                        const SizedBox(height: 12),
                        Text(_erreur!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _charger,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : _construireFormulaire(theme),
    );
  }

  Widget _construireFormulaire(ThemeData theme) {
    final ResumeCaisse resume = _resume ?? const ResumeCaisse();
    final double? ecart = _ecart;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Journée du ${formatDate(DateTime.now())}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _ligneResume('Encaissements', formatMontant(resume.jour.encaissements),
                    Colors.green.shade700),
                _ligneResume(
                  'Décaissements',
                  resume.jour.decaissements == null
                      ? '—'
                      : formatMontant(resume.jour.decaissements!),
                  Colors.red.shade700,
                ),
                const Divider(height: 20),
                _ligneResume('Net du jour', formatMontant(resume.jour.net),
                    theme.colorScheme.primary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _fondCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Fond de caisse initial',
            helperText: 'Argent présent en caisse AVANT les opérations du jour.',
            prefixIcon: const Icon(Icons.savings_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _compteeCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Espèce comptée (facultatif)',
            helperText:
                'Laissez vide si vous ne comptez pas l\'espèce ; l\'écart ne sera pas calculé.',
            prefixIcon: const Icon(Icons.pin_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (ecart != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (ecart >= 0 ? Colors.green : Colors.red)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color:
                    (ecart >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  ecart == 0
                      ? Icons.check_circle_rounded
                      : (ecart > 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded),
                  color: ecart >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Espèce attendue : ${formatMontant(_attenduEspeces)}\n'
                    'Écart : ${ecart > 0 ? '+' : ''}${formatMontant(ecart)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ecart >= 0
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _commentaireCtrl,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Commentaire (facultatif)',
            hintText: 'Ex. : écart de caisse expliqué par un rendu de monnaie.',
            prefixIcon: const Icon(Icons.notes_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _enregistrement ? null : _valider,
            icon: _enregistrement
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_clock_rounded),
            label: Text(
              _enregistrement ? 'Enregistrement…' : 'Valider la clôture',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'La clôture fige les totaux du jour et trace l\'opération dans le '
          'journal (CLOTURE_CAISSE). Re-clôturer la même journée remplace la '
          'clôture précédente.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _ligneResume(String libelle, String valeur, Color couleur) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(libelle)),
          Text(
            valeur,
            style: TextStyle(fontWeight: FontWeight.bold, color: couleur),
          ),
        ],
      ),
    );
  }
}
