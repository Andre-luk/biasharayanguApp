// lib/pages/pressing/pressing_retraits_page.dart
//
// 🧺 MODULE 35 — RETRAITS : scan du reçu et remise des vêtements.
//
// CE QUE FAIT L'AGENT
//   1. Il scanne le QR du reçu (ou saisit le numéro de commande).
//   2. L'écran affiche le dossier, les vêtements PRÊTS, ceux qui ne le sont
//      pas encore, le total, ce qui est payé et ce qui reste dû.
//   3. Il coche uniquement ce que le client emporte AUJOURD'HUI : la remise
//      peut être PARTIELLE (6 vêtements sur 10, les 4 autres restent en
//      traitement).
//   4. Il encaisse éventuellement le solde, note qui a récupéré.
//
// ⚠️ SÉCURITÉ — c'est le serveur qui tranche, jamais l'écran :
//    • un vêtement déjà remis est refusé (message clair, pas de double
//      validation) ;
//    • un vêtement qui n'est pas à l'étape finale est refusé ;
//    • si le pressing exige le solde, la DERNIÈRE remise est refusée tant
//      qu'il reste de l'argent dû ;
//    • un QR d'un autre pressing est refusé avec le même message qu'un QR
//      inconnu (on n'aide pas à deviner).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/pressing.dart';
import 'package:biashara_yangu/services/etablissement_service.dart';
import 'package:biashara_yangu/services/pressing_recu_pdf_service.dart';
import 'package:biashara_yangu/services/pressing_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/code_barre_lecteur.dart';

class PressingRetraitsPage extends StatefulWidget {
  const PressingRetraitsPage({super.key});

  @override
  State<PressingRetraitsPage> createState() => _PressingRetraitsPageState();
}

class _PressingRetraitsPageState extends State<PressingRetraitsPage> {
  final TextEditingController _recherche = TextEditingController();
  final TextEditingController _montant = TextEditingController();
  final TextEditingController _signataire = TextEditingController();
  final TextEditingController _observations = TextEditingController();

  PressingConfig _config = PressingConfig.defaut;
  PressingCommande? _commande;
  final Set<String> _choisis = <String>{};
  String _mode = 'especes';

  bool _chargement = false;
  bool _envoi = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _chargerConfig();
  }

  @override
  void dispose() {
    _recherche.dispose();
    _montant.dispose();
    _signataire.dispose();
    _observations.dispose();
    super.dispose();
  }

  Future<void> _chargerConfig() async {
    try {
      final PressingConfig config = await PressingService.instance.config();
      if (!mounted) return;
      setState(() => _config = config);
    } catch (_) {
      // Les valeurs par défaut suffisent pour afficher l'écran.
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

  // ---------------------------------------------------------------------------
  // CHARGEMENT D'UN DOSSIER
  // ---------------------------------------------------------------------------

  Future<void> _scanner() async {
    final String? code = await lireCodeBarre(
      context,
      titre: 'Scanner le reçu',
      aide: 'Placez le QR code du reçu dans le cadre.',
    );
    if (code == null || code.trim().isEmpty) return;
    await _chargerParCode(code.trim());
  }

  Future<void> _chargerParCode(String code) async {
    setState(() {
      _chargement = true;
      _erreur = null;
      _commande = null;
      _choisis.clear();
    });
    try {
      PressingCommande commande;
      // Le QR contient le jeton ; le numéro tapé à la main est accepté aussi.
      if (code.toUpperCase().startsWith('PR-')) {
        final List<PressingCommandeResume> trouvees =
            await PressingService.instance.commandes(recherche: code, limite: 5);
        if (trouvees.isEmpty) {
          throw const PressingException(
            'Aucune commande ne porte ce numéro dans ce pressing.',
          );
        }
        commande = await PressingService.instance.commande(trouvees.first.id);
      } else {
        commande = await PressingService.instance.commandeParQr(code);
      }

      if (!mounted) return;
      setState(() {
        _commande = commande;
        _chargement = false;
        _erreur = null;
        // Pré-remplit le montant avec le solde exact.
        _montant.text = commande.solde <= 0
            ? ''
            : (commande.solde == commande.solde.roundToDouble()
                ? commande.solde.toStringAsFixed(0)
                : commande.solde.toStringAsFixed(2));
        _signataire.text = commande.clientNom ?? '';
        // Sélectionne d'office tous les vêtements prêts (geste le plus courant).
        _choisis
          ..clear()
          ..addAll(commande.lignesPretes.map((PressingLigne l) => l.id));
      });
      _recherche.clear();
    } on PressingException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // REMISE
  // ---------------------------------------------------------------------------

  Future<void> _remettre() async {
    final PressingCommande? commande = _commande;
    if (commande == null || _choisis.isEmpty || _envoi) return;

    setState(() => _envoi = true);
    try {
      final double? montant =
          double.tryParse(_montant.text.replaceAll(',', '.'));

      final PressingCommande maj = await PressingService.instance.retrait(
        commandeId: commande.id,
        ligneIds: _choisis.toList(growable: false),
        montantEncaisse: (montant != null && montant > 0) ? montant : null,
        mode: _mode,
        observations: _observations.text.trim().isEmpty
            ? null
            : _observations.text.trim(),
        signataire: _signataire.text.trim().isEmpty
            ? null
            : _signataire.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _commande = maj;
        _choisis.clear();
        _envoi = false;
        _observations.clear();
        _montant.text = maj.solde <= 0
            ? ''
            : (maj.solde == maj.solde.roundToDouble()
                ? maj.solde.toStringAsFixed(0)
                : maj.solde.toStringAsFixed(2));
      });

      _message(
        maj.statut == StatutCommandePressing.remise
            ? 'Commande ${maj.numero} entièrement remise.'
            : 'Remise partielle enregistrée : ${maj.nbRemis}/${maj.nbLignes} '
                'vêtements remis.',
      );

      // Le client repart avec un reçu à jour (ce qui reste en garde).
      await _proposerRecu(maj);
    } on PressingException catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      // Les refus du serveur sont affichés en clair dans un bandeau : l'agent
      // doit comprendre POURQUOI il ne peut pas remettre.
      setState(() => _erreur = e.message);
      _message(e.message, erreur: true);
    }
  }

  Future<void> _proposerRecu(PressingCommande commande) async {
    Etablissement etab = EtablissementService.instance.courant;
    try {
      etab = await EtablissementService.instance.charger();
    } catch (_) {
      // Fiche ancienne acceptée.
    }
    if (!mounted) return;
    final DonneesRecuPressing donnees = DonneesRecuPressing(
      commande: commande,
      etablissement: etab,
      soldeObligatoire: _config.soldeObligatoire,
    );
    final bool ok = await PressingRecuPdfService.instance.telecharger(donnees);
    if (!mounted) return;
    await afficherActionsRecu(
      context,
      donnees,
      telechargeeAutomatiquement: ok,
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retraits & scan'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Scanner le reçu',
            onPressed: _chargement ? null : _scanner,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          _blocScan(),
          if (_erreur != null) ...<Widget>[
            const SizedBox(height: 12),
            _bandeauErreur(_erreur!),
          ],
          if (_chargement)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_commande != null) ...<Widget>[
            const SizedBox(height: 14),
            ..._dossier(_commande!),
          ],
        ],
      ),
    );
  }

  Widget _blocScan() {
    return Card(
      elevation: 0,
      color: AppCouleurs.marine,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Remettre des vêtements',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Scannez le QR du reçu, ou saisissez le numéro de commande.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _recherche,
                    style: const TextStyle(color: Colors.white),
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (String v) {
                      if (v.trim().isEmpty) return;
                      _chargerParCode(v.trim());
                    },
                    decoration: InputDecoration(
                      hintText: 'PR-2026-000001',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.12),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppCouleurs.orange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _chargement ? null : _scanner,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scanner'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bandeauErreur(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppCouleurs.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppCouleurs.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.block_rounded, color: AppCouleurs.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _erreur = null),
          ),
        ],
      ),
    );
  }

  List<Widget> _dossier(PressingCommande c) {
    final int nbPrets = c.lignesPretes.length;
    final double resteApres = (c.solde -
            (double.tryParse(_montant.text.replaceAll(',', '.')) ?? 0))
        .clamp(0, double.infinity);

    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  c.numero,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  <String>[
                    if ((c.clientNom ?? '').isNotEmpty) c.clientNom!,
                    if ((c.clientTelephone ?? '').isNotEmpty) c.clientTelephone!,
                  ].join(' · '),
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _couleurStatut(c.statut).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              c.statut.libelle,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _couleurStatut(c.statut),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _ligneInfo(c),
      const SizedBox(height: 12),
      Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              'Vêtements',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (nbPrets > 0 && c.estAnnulee == false)
            TextButton(
              onPressed: () => setState(() {
                if (_choisis.length == nbPrets) {
                  _choisis.clear();
                } else {
                  _choisis
                    ..clear()
                    ..addAll(
                      c.lignesPretes.map((PressingLigne l) => l.id),
                    );
                }
              }),
              child: Text(
                _choisis.length == nbPrets ? 'Tout décocher' : 'Tout cocher',
              ),
            ),
        ],
      ),
      ...c.lignes.map((PressingLigne l) => _tuileLigne(c, l)),
      const SizedBox(height: 12),
      if (!c.estAnnulee) _blocRemise(c, resteApres),
    ];
  }

  Widget _ligneInfo(PressingCommande c) {
    return Wrap(
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
    );
  }

  /// Coche / décoche un vêtement (geste fréquent : le corps doit rester une
  /// méthode, une flèche dans un `?:` avalerait le `: null`).
  void _basculer(PressingLigne l) {
    setState(() {
      if (_choisis.contains(l.id)) {
        _choisis.remove(l.id);
      } else {
        _choisis.add(l.id);
      }
    });
  }

  Widget _tuileLigne(PressingCommande c, PressingLigne l) {
    final bool remis = l.estRemis;
    final bool pret = l.estPrete && !remis;
    final bool selectionne = _choisis.contains(l.id);
    final bool selectionnable = pret && !c.estAnnulee;

    final String sousTitre;
    if (remis) {
      sousTitre = 'Déjà remis le ${formatDate(l.remisLe)}';
    } else if (!pret) {
      sousTitre = 'Pas encore prêt — ${l.etapeLibelle ?? l.etapeCode}';
    } else {
      sousTitre = 'Prêt à remettre';
    }

    final Color couleur = remis
        ? Colors.grey.shade600
        : pret
            ? AppCouleurs.succes
            : AppCouleurs.alerte;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: selectionne
          ? AppCouleurs.marineClair.withValues(alpha: 0.08)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        enabled: selectionnable,
        onTap: selectionnable ? () => _basculer(l) : null,
        leading: Checkbox(
          value: selectionne,
          onChanged: selectionnable ? (bool? _) => _basculer(l) : null,
        ),
        title: Text(
          l.titre,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            decoration: remis ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              sousTitre,
              style: TextStyle(fontSize: 11.5, color: couleur),
            ),
            if (l.details.isNotEmpty)
              Text(l.details, style: const TextStyle(fontSize: 11)),
            if (l.aDefauts)
              Text(
                'Défaut au dépôt : ${l.defauts!.trim()}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppCouleurs.alerte,
                ),
              ),
          ],
        ),
        trailing: Text(
          formatMontant(l.prix, devise: c.devise),
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _blocRemise(PressingCommande c, double resteApres) {
    final int nb = _choisis.length;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Encaissement au retrait',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _montant,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Montant reçu (${c.devise})',
                helperText: c.solde > 0
                    ? 'Solde actuel : ${formatMontant(c.solde, devise: c.devise)}'
                    : 'Aucun solde à payer',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'especes',
                  label: Text('Espèces'),
                  icon: Icon(Icons.payments_rounded),
                ),
                ButtonSegment<String>(
                  value: 'mobile_money',
                  label: Text('Mobile'),
                  icon: Icon(Icons.phone_android_rounded),
                ),
                ButtonSegment<String>(
                  value: 'carte',
                  label: Text('Carte'),
                  icon: Icon(Icons.credit_card_rounded),
                ),
              ],
              selected: <String>{_mode},
              onSelectionChanged: (Set<String> v) =>
                  setState(() => _mode = v.first),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _signataire,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Qui récupère ? (nom)',
                helperText: 'Preuve de réception en cas de contestation',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _observations,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observation (facultatif)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (c.solde > 0 && resteApres > 0 && _config.soldeObligatoire)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: AppCouleurs.alerte),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Il restera '
                        '${formatMontant(resteApres, devise: c.devise)} à payer : '
                        'la remise finale sera refusée tant que le solde n\'est '
                        'pas réglé.',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (nb == 0 || _envoi) ? null : _remettre,
                icon: _envoi
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.inventory_rounded),
                label: Text(
                  nb == 0
                      ? 'Sélectionnez des vêtements'
                      : 'Remettre $nb vêtement${nb > 1 ? 's' : ''}',
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Remise partielle possible : les vêtements non cochés restent '
              'dans la commande.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ],
        ),
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
}
