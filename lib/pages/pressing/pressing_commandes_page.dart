// lib/pages/pressing/pressing_commandes_page.dart
//
// 🧺 MODULE 35 — DÉPÔTS & COMMANDES DU PRESSING.
//
// Cet écran est le point d'entrée du module : il montre d'abord l'état réel
// du pressing (ce qui est en cours, ce qui est prêt, ce qui est en retard et
// ce qui reste à encaisser), puis la liste des dossiers.
//
// ⚠️ « Facturé » et « encaissé » sont TOUJOURS deux chiffres séparés : un
//    dossier déposé n'est pas de l'argent en caisse.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/pressing.dart';
import 'package:biashara_yangu/services/etablissement_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/pressing_recu_pdf_service.dart';
import 'package:biashara_yangu/services/pressing_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/pages/pressing/pressing_depot_page.dart';

class PressingCommandesPage extends StatefulWidget {
  const PressingCommandesPage({super.key});

  @override
  State<PressingCommandesPage> createState() => _PressingCommandesPageState();
}

class _PressingCommandesPageState extends State<PressingCommandesPage> {
  final TextEditingController _recherche = TextEditingController();

  bool _chargement = true;
  String? _erreur;
  PressingTableauBord _tableau = const PressingTableauBord();
  List<PressingCommandeResume> _commandes = const <PressingCommandeResume>[];
  String? _filtre;

  PressingConfig _config = PressingConfig.defaut;

  bool get _peutCreer =>
      PermissionService.instance.peut(PageAccess.pressingDepots, ActionAccess.creer);

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = _commandes.isEmpty;
      _erreur = null;
    });
    try {
      final PressingTableauBord tableau =
          await PressingService.instance.tableauBord();
      final List<PressingCommandeResume> commandes =
          await PressingService.instance.commandes(
        statut: _filtre,
        recherche: _recherche.text.trim().isEmpty ? null : _recherche.text,
      );
      final PressingConfig config = await PressingService.instance.config();

      if (!mounted) return;
      setState(() {
        _tableau = tableau;
        _commandes = commandes;
        _config = config;
        _chargement = false;
      });
    } on PressingException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? AppCouleurs.danger : null,
      ),
    );
  }

  Future<void> _nouveauDepot() async {
    final dynamic resultat = await Navigator.of(context).push(
      MaterialPageRoute<dynamic>(
        builder: (BuildContext _) => const PressingDepotPage(),
      ),
    );
    if (resultat is PressingCommande) await _charger();
  }

  // ---------------------------------------------------------------------------
  // FICHE D'UNE COMMANDE
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirFiche(PressingCommandeResume resume) async {
    PressingCommande commande;
    try {
      commande = await PressingService.instance.commande(resume.id);
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => _FicheCommande(
        commande: commande,
        config: _config,
        onModifiee: (PressingCommande maj) async {
          Navigator.of(ctx).pop();
          await _charger();
          if (!mounted) return;
          _message('Commande ${maj.numero} mise à jour.');
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dépôts & commandes'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _peutCreer
          ? FloatingActionButton.extended(
              onPressed: _nouveauDepot,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nouveau dépôt'),
            )
          : null,
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur(_erreur!)
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: <Widget>[
                      _indicateurs(),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _recherche,
                        decoration: InputDecoration(
                          hintText: 'Numéro, client, téléphone…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onSubmitted: (_) => _charger(),
                      ),
                      const SizedBox(height: 10),
                      _filtres(),
                      const SizedBox(height: 10),
                      if (_commandes.isEmpty)
                        _vide()
                      else
                        ..._commandes.map(_tuile),
                    ],
                  ),
                ),
    );
  }

  Widget _vueErreur(String message) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const SizedBox(height: 40),
        Icon(Icons.error_outline, size: 48, color: AppCouleurs.danger),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
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

  Widget _indicateurs() {
    final String devise = _config.devise;
    final List<Widget> cartes = <Widget>[
      _kpi('Aujourd\'hui', '${_tableau.commandesAujourdhui}',
          Icons.today_rounded, AppCouleurs.marineClair),
      _kpi('En cours', '${_tableau.commandesEnCours}',
          Icons.local_laundry_service_rounded, AppCouleurs.info),
      _kpi('Prêts', '${_tableau.vetementsPrets}', Icons.check_circle_rounded,
          AppCouleurs.succes),
      _kpi('En retard', '${_tableau.commandesEnRetard}', Icons.schedule_rounded,
          _tableau.commandesEnRetard > 0
              ? AppCouleurs.danger
              : Colors.grey.shade600),
    ];

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int i = 0; i < cartes.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: cartes[i]),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: AppCouleurs.marine,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _montant(
                    'Facturé',
                    formatMontant(_tableau.montantFacture, devise: devise),
                  ),
                ),
                Expanded(
                  child: _montant(
                    'Encaissé',
                    formatMontant(_tableau.montantEncaisse, devise: devise),
                  ),
                ),
                Expanded(
                  child: _montant(
                    'Reste dû',
                    formatMontant(_tableau.montantDu, devise: devise),
                    alerte: _tableau.montantDu > 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kpi(String libelle, String valeur, IconData icone, Color couleur) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: <Widget>[
          Icon(icone, size: 18, color: couleur),
          const SizedBox(height: 4),
          Text(
            valeur,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: couleur,
            ),
          ),
          Text(
            libelle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _montant(String libelle, String valeur, {bool alerte = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          libelle,
          style: const TextStyle(fontSize: 10.5, color: Colors.white70),
        ),
        const SizedBox(height: 2),
        Text(
          valeur,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: alerte ? const Color(0xFFFFD9A8) : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _filtres() {
    const Map<String?, String> options = <String?, String>{
      null: 'Tous',
      'EN_TRAITEMENT': 'En cours',
      'PRETE': 'Prêtes',
      'PARTIELLEMENT_REMISE': 'Partielles',
      'REMISE': 'Remises',
      'ANNULEE': 'Annulées',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.entries.map((MapEntry<String?, String> e) {
          final bool actif = _filtre == e.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e.value),
              selected: actif,
              onSelected: (_) {
                setState(() => _filtre = e.key);
                _charger();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _vide() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: <Widget>[
          Icon(Icons.local_laundry_service_rounded,
              size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            'Aucun dépôt pour le moment.\nUn dépôt garde la trace de chaque '
            'vêtement confié, du dépôt jusqu\'au retrait.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Color _couleurStatut(StatutCommandePressing statut) {
    switch (statut) {
      case StatutCommandePressing.enTraitement:
        return AppCouleurs.info;
      case StatutCommandePressing.prete:
        return AppCouleurs.succes;
      case StatutCommandePressing.partiellementRemise:
        return AppCouleurs.alerte;
      case StatutCommandePressing.remise:
        return Colors.grey.shade600;
      case StatutCommandePressing.annulee:
        return AppCouleurs.danger;
    }
  }

  Widget _tuile(PressingCommandeResume c) {
    final Color couleur = _couleurStatut(c.statut);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        onTap: () => _ouvrirFiche(c),
        leading: CircleAvatar(
          backgroundColor: couleur.withValues(alpha: 0.15),
          child: Icon(Icons.local_laundry_service_rounded, color: couleur),
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                c.numero,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              formatMontant(c.total, devise: c.devise),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              <String>[
                if ((c.clientNom ?? '').isNotEmpty) c.clientNom!,
                '${c.nbLignes} vêtement${c.nbLignes > 1 ? 's' : ''}',
                if (c.nbPrets > 0) '${c.nbPrets} prêt${c.nbPrets > 1 ? 's' : ''}',
                if (c.nbRemis > 0) '${c.nbRemis} remis',
              ].join(' · '),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                _badge(c.statut.libelle, couleur),
                _badge('Retrait ${formatDate(c.datePrevue)}',
                    c.enRetard ? AppCouleurs.danger : Colors.grey.shade600),
                if (c.solde > 0)
                  _badge('Reste ${formatMontant(c.solde, devise: c.devise)}',
                      AppCouleurs.danger),
                if (c.urgence) _badge('Express', AppCouleurs.orange),
              ],
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _badge(String texte, Color couleur) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontSize: 10.5,
          color: couleur,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ============================================================================
//  FICHE D'UNE COMMANDE (feuille modale)
// ============================================================================

class _FicheCommande extends StatefulWidget {
  const _FicheCommande({
    required this.commande,
    required this.config,
    required this.onModifiee,
  });

  final PressingCommande commande;
  final PressingConfig config;
  final void Function(PressingCommande) onModifiee;

  @override
  State<_FicheCommande> createState() => _FicheCommandeState();
}

class _FicheCommandeState extends State<_FicheCommande> {
  late PressingCommande _commande = widget.commande;
  bool _envoi = false;

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? AppCouleurs.danger : null,
      ),
    );
  }

  Future<void> _imprimerRecu() async {
    Etablissement etab = EtablissementService.instance.courant;
    try {
      etab = await EtablissementService.instance.charger();
    } catch (_) {
      // Fiche ancienne acceptée.
    }
    if (!mounted) return;
    final DonneesRecuPressing donnees = DonneesRecuPressing(
      commande: _commande,
      etablissement: etab,
      soldeObligatoire: widget.config.soldeObligatoire,
    );
    final bool ok = await PressingRecuPdfService.instance.telecharger(donnees);
    if (!mounted) return;
    await afficherActionsRecu(
      context,
      donnees,
      telechargeeAutomatiquement: ok,
    );
  }

  Future<void> _encaisser() async {
    final TextEditingController montant = TextEditingController(
      text: _commande.solde == _commande.solde.roundToDouble()
          ? _commande.solde.toStringAsFixed(0)
          : _commande.solde.toStringAsFixed(2),
    );
    String mode = 'especes';

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setEtat) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Encaisser un paiement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: montant,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Montant (${_commande.devise})',
                  helperText:
                      'Reste à payer : ${formatMontant(_commande.solde, devise: _commande.devise)}',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'especes', label: Text('Espèces')),
                  ButtonSegment<String>(
                      value: 'mobile_money', label: Text('Mobile')),
                  ButtonSegment<String>(value: 'carte', label: Text('Carte')),
                ],
                selected: <String>{mode},
                onSelectionChanged: (Set<String> v) =>
                    setEtat(() => mode = v.first),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Encaisser'),
            ),
          ],
        ),
      ),
    );

    final double? valeur =
        double.tryParse(montant.text.replaceAll(',', '.'));
    montant.dispose();

    if (ok != true || valeur == null || valeur <= 0) return;

    setState(() => _envoi = true);
    try {
      await PressingService.instance.paiementAjouter(
        commandeId: _commande.id,
        montant: valeur,
        mode: mode,
      );
      final PressingCommande maj =
          await PressingService.instance.commande(_commande.id);
      if (!mounted) return;
      setState(() {
        _commande = maj;
        _envoi = false;
      });
      _message('Paiement enregistré.');
    } on PressingException catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      _message(e.message, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PressingCommande c = _commande;
    final Color accent = c.estAnnulee ? AppCouleurs.danger : AppCouleurs.marineClair;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (BuildContext ctx, ScrollController controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      c.numero,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      <String>[
                        if ((c.clientNom ?? '').isNotEmpty) c.clientNom!,
                        if ((c.clientTelephone ?? '').isNotEmpty)
                          c.clientTelephone!,
                      ].join(' · '),
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  c.statut.libelle,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _info('Déposé le', formatDate(c.dateDepot)),
              _info('Retrait prévu', formatDate(c.datePrevue)),
              _info('Total', formatMontant(c.total, devise: c.devise)),
              _info('Payé', formatMontant(c.montantPaye, devise: c.devise)),
              _info(
                'Reste',
                formatMontant(c.solde, devise: c.devise),
                alerte: c.solde > 0,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Vêtements', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...c.lignes.map(
            (PressingLigne l) => Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 6),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 13,
                  backgroundColor: (l.estRemis
                          ? Colors.grey
                          : l.estPrete
                              ? AppCouleurs.succes
                              : AppCouleurs.info)
                      .withValues(alpha: 0.15),
                  child: Icon(
                    l.estRemis
                        ? Icons.inventory_rounded
                        : l.estPrete
                            ? Icons.check_rounded
                            : Icons.local_laundry_service_rounded,
                    size: 15,
                    color: l.estRemis
                        ? Colors.grey.shade700
                        : l.estPrete
                            ? AppCouleurs.succes
                            : AppCouleurs.info,
                  ),
                ),
                title: Text(l.titre, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  <String>[
                    l.estRemis
                        ? 'Remis le ${formatDate(l.remisLe)}'
                        : (l.etapeLibelle ?? l.etapeCode),
                    if (l.details.isNotEmpty) l.details,
                    if (l.aDefauts) 'défaut : ${l.defauts!.trim()}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Text(
                  formatMontant(l.prix, devise: c.devise),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
          if (c.paiements.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            const Text('Paiements',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ...c.paiements.map(
              (PressingPaiement p) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  p.estAnnule
                      ? Icons.cancel_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                  color: p.estAnnule ? AppCouleurs.danger : AppCouleurs.succes,
                ),
                title: Text(formatMontant(p.montant, devise: c.devise)),
                subtitle: Text(
                  <String>[
                    p.libelleMode,
                    formatDate(p.encaisseLe),
                    if (p.estAnnule) 'annulé : ${p.motifAnnulation ?? ''}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _imprimerRecu,
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Reçu'),
                ),
              ),
              const SizedBox(width: 8),
              if (!c.estAnnulee && c.solde > 0)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _envoi ? null : _encaisser,
                    icon: const Icon(Icons.payments_rounded),
                    label: const Text('Encaisser'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _info(String libelle, String valeur, {bool alerte = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(libelle, style: const TextStyle(fontSize: 10)),
          Text(
            valeur,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: alerte ? AppCouleurs.danger : null,
            ),
          ),
        ],
      ),
    );
  }
}
