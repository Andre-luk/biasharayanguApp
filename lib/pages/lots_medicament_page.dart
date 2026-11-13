// lib/pages/lots_medicament_page.dart
//
// MODULE 36 — « LOTS & PÉREMPTION » D'UN MÉDICAMENT.
//
// Un médicament reçu trois fois = trois lots, trois dates de péremption,
// trois prix d'achat. Cet écran montre la vérité du rayon :
//   • chaque lot avec sa quantité RESTANTE et son état ;
//   • le stock vendable (hors lots périmés ou retirés) ;
//   • l'ordre FEFO : le lot qui périme le plus tôt part en premier ;
//   • la réception d'un nouveau lot et le retrait d'un lot (casse, rappel,
//     péremption) avec motif obligatoire.
//
// ⚠️ Aucun calcul de stock ici : le serveur ajoute la quantité reçue au
//    stock, consomme les lots à la vente et trace chaque mouvement.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/lot_medicament.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/peremption_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/pharmacie_lots_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

class LotsMedicamentPage extends StatefulWidget {
  const LotsMedicamentPage({
    super.key,
    required this.articleId,
    this.articleNom,
  });

  final int articleId;

  /// Nom connu à l'ouverture (évite un titre vide pendant le chargement).
  final String? articleNom;

  @override
  State<LotsMedicamentPage> createState() => _LotsMedicamentPageState();
}

class _LotsMedicamentPageState extends State<LotsMedicamentPage> {
  final PharmacieLotsService _service = PharmacieLotsService.instance;

  DossierLots? _dossier;
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    if (!mounted) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    final int jours = await PeremptionService.instance.charger();

    try {
      final DossierLots dossier =
          await _service.lister(widget.articleId, joursAlarme: jours);
      if (!mounted) return;
      setState(() {
        _dossier = dossier;
        _chargement = false;
      });
    } on PharmacieLotsException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirReception() async {
    final DossierLots? dossier = _dossier;
    if (dossier == null) return;

    final _SaisieLot? saisie = await showDialog<_SaisieLot>(
      context: context,
      builder: (BuildContext context) => _DialogueReceptionLot(
        produit: dossier.produit,
      ),
    );
    if (saisie == null) return;

    try {
      final ResultatReceptionLot resultat = await _service.recevoir(
        produitId: widget.articleId,
        numeroLot: saisie.numeroLot,
        datePeremption: saisie.datePeremption,
        quantite: saisie.quantite,
        prixAchatUnitaire: saisie.prixAchatUnitaire,
        fournisseur: saisie.fournisseur,
        dateFabrication: saisie.dateFabrication,
        observations: saisie.observations,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lot ${saisie.numeroLot} enregistré : '
            '+${formatQuantite(resultat.quantiteRecue)} — '
            'stock ${formatQuantite(resultat.stockApres)}.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
      await _charger();
    } on PharmacieLotsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _retirer(LotMedicament lot) async {
    final String? motif = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _DialogueRetraitLot(lot: lot),
    );
    if (motif == null) return;

    try {
      final ResultatRetraitLot resultat =
          await _service.retirer(lotId: lot.id, motif: motif);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lot ${lot.numeroLot} retiré : '
            '−${formatQuantite(resultat.quantiteRetiree)} — '
            'stock ${formatQuantite(resultat.stockApres)}.',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      await _charger();
    } on PharmacieLotsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // AFFICHAGE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final DossierLots? dossier = _dossier;
    final bool peutCreer =
        PermissionService.instance.peutCreer(PageAccess.stock);
    final bool peutRetirer =
        PermissionService.instance.peut(PageAccess.stock, ActionAccess.modifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          dossier == null
              ? (widget.articleNom ?? 'Lots')
              : 'Lots · ${dossier.produit}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      floatingActionButton: (dossier != null && peutCreer)
          ? FloatingActionButton.extended(
              onPressed: _ouvrirReception,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Réception de lot'),
            )
          : null,
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null || dossier == null
              ? _vueErreur()
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      _resume(dossier),
                      const SizedBox(height: 12),
                      _bandeauFefo(dossier),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Lots (${dossier.lots.length})',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            'Du plus urgent au plus récent',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (dossier.lots.isEmpty)
                        _aucunLot()
                      else
                        ...dossier.lots.map(
                          (LotMedicament lot) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _carteLot(dossier, lot,
                                peutRetirer: peutRetirer),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _vueErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 56, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              _erreur ?? 'Lots indisponibles.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resume(DossierLots dossier) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: _indicateur('Stock fiche',
                        formatQuantite(dossier.stock), Icons.inventory_2_outlined)),
                Expanded(
                  child: _indicateur(
                    'Vendable',
                    formatQuantite(dossier.stockVendable),
                    Icons.verified_outlined,
                    alerte: dossier.stockVendable <= 0,
                  ),
                ),
                Expanded(
                  child: _indicateur(
                    'Périmé',
                    formatQuantite(dossier.lotsPerimes.fold<double>(
                        0, (double s, LotMedicament l) => s + l.quantiteRestante)),
                    Icons.warning_amber_rounded,
                    alerte: dossier.lotsPerimes.isNotEmpty,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text(
              'Valeur d\'achat encore en stock : '
              '${formatMontant(dossier.valeurTotale)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (dossier.ecart.abs() > 0.0005) ...[
              const SizedBox(height: 6),
              Text(
                '⚠ Écart fiche / lots : ${formatQuantiteSignee(dossier.ecart)}. '
                'Le stock a probablement été saisi avant la mise en place des lots.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade800,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _indicateur(String libelle, String valeur, IconData icone,
      {bool alerte = false}) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color couleur = alerte ? scheme.error : scheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 18, color: couleur),
        const SizedBox(height: 4),
        Text(
          valeur,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: couleur),
        ),
        Text(
          libelle,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _bandeauFefo(DossierLots dossier) {
    final LotMedicament? prochain = dossier.prochainLot;
    if (prochain == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.block_rounded, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                dossier.aLots
                    ? 'Aucun lot vendable : tous les lots sont périmés ou retirés. '
                        'La vente est bloquée par le serveur.'
                    : 'Aucun lot enregistré. Le stock actuel n\'est pas suivi par lot.',
                style: TextStyle(fontSize: 12, color: Colors.red.shade900),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.sort_rounded, color: Colors.blue.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'FEFO — à servir en premier : lot ${prochain.numeroLot} '
              '(péremption ${formatDate(prochain.datePeremption)}, '
              '${formatQuantite(prochain.quantiteRestante)} restant).',
              style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aucunLot() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            const Text(
              'Aucun lot pour cet article.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Enregistrez la première réception : le stock, la date de '
              'péremption et le prix d\'achat appartiendront à ce lot.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carteLot(DossierLots dossier, LotMedicament lot,
      {required bool peutRetirer}) {
    final bool prochain = dossier.prochainLot?.id == lot.id;
    final Color color = _couleur(lot.statut);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: prochain ? Colors.blue.shade300 : Colors.grey.shade200,
          width: prochain ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    lot.numeroLot,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                if (prochain)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'FEFO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    lot.statut.libelle,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ligne(
                    'Péremption',
                    formatDate(lot.datePeremption),
                    couleur: lot.statut == StatutLot.perime ? color : null,
                  ),
                ),
                Expanded(
                  child: _ligne(
                    'Restant',
                    '${formatQuantite(lot.quantiteRestante)} '
                    '/ ${formatQuantite(lot.quantiteRecue)}',
                  ),
                ),
              ],
            ),
            if (lot.prixAchatUnitaire != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _ligne('Prix d\'achat',
                        '${formatMontant(lot.prixAchatUnitaire!)} / unité'),
                  ),
                  Expanded(
                    child: _ligne('Valeur', formatMontant(lot.valeurAchat)),
                  ),
                ],
              ),
            ],
            if (lot.fournisseur != null) ...[
              const SizedBox(height: 6),
              _ligne('Fournisseur', lot.fournisseur!),
            ],
            if (lot.retireLe != null) ...[
              const SizedBox(height: 6),
              _ligne(
                'Retiré le',
                '${formatDate(lot.retireLe)}'
                '${lot.motifRetrait == null ? '' : ' · ${lot.motifRetrait}'}',
                couleur: Colors.orange.shade800,
              ),
            ],
            if (lot.retireLe == null && lot.quantiteRestante > 0 && peutRetirer)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _retirer(lot),
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  label: const Text('Retirer du stock'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ligne(String libelle, String valeur, {Color? couleur}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          libelle,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
        Text(
          valeur,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: couleur,
          ),
        ),
      ],
    );
  }

  static Color _couleur(StatutLot statut) {
    switch (statut) {
      case StatutLot.perime:
        return Colors.red.shade700;
      case StatutLot.proche:
        return Colors.orange.shade800;
      case StatutLot.valide:
        return Colors.green.shade700;
      case StatutLot.retire:
        return Colors.grey.shade600;
      case StatutLot.inconnu:
        return Colors.blueGrey;
    }
  }
}

// ===========================================================================
//  SAISIE D'UN LOT
// ===========================================================================

class _SaisieLot {
  const _SaisieLot({
    required this.numeroLot,
    required this.datePeremption,
    required this.quantite,
    this.prixAchatUnitaire,
    this.fournisseur,
    this.dateFabrication,
    this.observations,
  });

  final String numeroLot;
  final DateTime datePeremption;
  final double quantite;
  final double? prixAchatUnitaire;
  final String? fournisseur;
  final DateTime? dateFabrication;
  final String? observations;
}

class _DialogueReceptionLot extends StatefulWidget {
  const _DialogueReceptionLot({required this.produit});

  final String produit;

  @override
  State<_DialogueReceptionLot> createState() => _DialogueReceptionLotState();
}

class _DialogueReceptionLotState extends State<_DialogueReceptionLot> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _lot = TextEditingController();
  final TextEditingController _quantite = TextEditingController();
  final TextEditingController _prix = TextEditingController();
  final TextEditingController _fournisseur = TextEditingController();
  final TextEditingController _observations = TextEditingController();

  DateTime? _peremption;
  DateTime? _fabrication;
  bool _envoi = false;

  @override
  void dispose() {
    _lot.dispose();
    _quantite.dispose();
    _prix.dispose();
    _fournisseur.dispose();
    _observations.dispose();
    super.dispose();
  }

  Future<void> _choisirDate({required bool peremption}) async {
    final DateTime maintenant = DateTime.now();
    final DateTime? choix = await showDatePicker(
      context: context,
      initialDate: peremption
          ? (maintenant.add(const Duration(days: 365)))
          : maintenant,
      firstDate: peremption ? maintenant : DateTime(2000),
      lastDate: DateTime(2100),
      helpText: peremption ? 'Date de péremption' : 'Date de fabrication',
    );
    if (choix == null) return;
    setState(() {
      if (peremption) {
        _peremption = choix;
      } else {
        _fabrication = choix;
      }
    });
  }

  void _valider() {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_peremption == null) {
      _message('Indiquez la date de péremption du lot.');
      return;
    }

    final DateTime jour = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    if (_peremption!.isBefore(jour)) {
      _message('Ce lot est déjà périmé : refusez-le plutôt que de l\'entrer.');
      return;
    }

    setState(() => _envoi = true);
    Navigator.of(context).pop(
      _SaisieLot(
        numeroLot: _lot.text.trim(),
        datePeremption: _peremption!,
        quantite: double.tryParse(_quantite.text.replaceAll(',', '.')) ?? 0,
        prixAchatUnitaire: double.tryParse(_prix.text.replaceAll(',', '.')),
        fournisseur: _fournisseur.text.trim(),
        dateFabrication: _fabrication,
        observations: _observations.text.trim(),
      ),
    );
  }

  void _message(String texte) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texte)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Réception d\'un lot'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.produit,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lot,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Numéro de lot *',
                    hintText: 'ex. LOT-2026-A',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? v) =>
                      (v == null || v.trim().isEmpty) ? 'Obligatoire' : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _choisirDate(peremption: true),
                        icon: const Icon(Icons.event_busy_rounded, size: 18),
                        label: Text(
                          _peremption == null
                              ? 'Péremption *'
                              : formatDate(_peremption),
                          style: TextStyle(
                            color: _peremption == null
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _choisirDate(peremption: false),
                        icon: const Icon(Icons.event_available_rounded, size: 18),
                        label: Text(
                          _fabrication == null
                              ? 'Fabrication'
                              : formatDate(_fabrication),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantite,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Quantité reçue *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (String? v) {
                          final double? q =
                              double.tryParse((v ?? '').replaceAll(',', '.'));
                          if (q == null || q <= 0) return '> 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _prix,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Prix d\'achat / unité',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _fournisseur,
                  decoration: const InputDecoration(
                    labelText: 'Fournisseur',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _observations,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observations',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'La quantité reçue s\'ajoute au stock de l\'article. '
                  'Les lots existants ne sont jamais modifiés.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _envoi ? null : _valider,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// ===========================================================================
//  RETRAIT D'UN LOT
// ===========================================================================

class _DialogueRetraitLot extends StatefulWidget {
  const _DialogueRetraitLot({required this.lot});

  final LotMedicament lot;

  @override
  State<_DialogueRetraitLot> createState() => _DialogueRetraitLotState();
}

class _DialogueRetraitLotState extends State<_DialogueRetraitLot> {
  final TextEditingController _motif = TextEditingController();

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Retirer ce lot du stock ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lot ${widget.lot.numeroLot} — '
            '${formatQuantite(widget.lot.quantiteRestante)} encore en stock, '
            'péremption ${formatDate(widget.lot.datePeremption)}.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            'La quantité sera sortie du stock et tracée comme perte '
            '(casse, rappel, péremption). Le lot restera dans l\'historique.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _motif,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Motif *',
              hintText: 'ex. périmé, casse, rappel fournisseur',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        PermissionGate(
          page: PageAccess.stock,
          action: ActionAccess.modifier,
          child: FilledButton(
            onPressed: () {
              final String texte = _motif.text.trim();
              if (texte.length < 3) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Indiquez la raison du retrait.'),
                  ),
                );
                return;
              }
              Navigator.of(context).pop(texte);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
            ),
            child: const Text('Retirer'),
          ),
        ),
      ],
    );
  }
}
