// lib/pages/recipients_page.dart
//
// REFONTE ABONNEMENTS & DISTRIBUTION — RÉCIPIENTS & BONUS.
//
// Trois onglets, directement branchés sur les RPC de la migration 0084 :
//   • TYPES   : bidons, casiers, fardes + prix de consigne, et déclaration
//               des pertes (casse / perdu) ;
//   • BONUS   : règles configurables (« 5 fardes = 1 offerte ») ;
//   • CLIENTS : ce que chaque client détient encore (récipients à récupérer).
//
// ⚠️ Aucun écran ne calcule un montant « à la main » : les totaux viennent du
// serveur (`rpc_recipients_tableau_bord`) ou du modèle pur `CalculRecipient`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/recipients.dart';
import 'package:biashara_yangu/services/distribution_service.dart';
import 'package:biashara_yangu/services/recipients_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class RecipientsPage extends StatefulWidget {
  const RecipientsPage({super.key});

  @override
  State<RecipientsPage> createState() => _RecipientsPageState();
}

class _RecipientsPageState extends State<RecipientsPage>
    with SingleTickerProviderStateMixin {
  final RecipientsService _service = RecipientsService.instance;
  late final TabController _onglets;

  bool _chargement = true;
  String? _erreur;

  TableauBordRecipients _tableau = TableauBordRecipients.vide;
  List<TypeRecipient> _types = const <TypeRecipient>[];
  List<RegleBonus> _regles = const <RegleBonus>[];
  List<Map<String, dynamic>> _clients = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _onglets = TabController(length: 3, vsync: this);
    _charger();
  }

  @override
  void dispose() {
    _onglets.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    if (mounted) setState(() => _chargement = true);
    try {
      final List<dynamic> resultats = await Future.wait(<Future<dynamic>>[
        _service.tableauBord(),
        _service.types(),
        _service.regles(),
        DistributionService.instance.listerClients(),
      ]);
      if (!mounted) return;
      setState(() {
        _tableau = resultats[0] as TableauBordRecipients;
        _types = resultats[1] as List<TypeRecipient>;
        _regles = resultats[2] as List<RegleBonus>;
        _clients = resultats[3] as List<Map<String, dynamic>>;
        _erreur = null;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e is RecipientsException ? e.message : e.toString();
        _chargement = false;
      });
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Récipients & bonus'),
        bottom: TabBar(
          controller: _onglets,
          tabs: const <Widget>[
            Tab(text: 'Types'),
            Tab(text: 'Bonus'),
            Tab(text: 'Clients'),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _construireCorps(),
    );
  }

  Widget _construireCorps() {
    if (_chargement) {
      return const Center(child: ModernLoader(legende: 'Chargement…'));
    }
    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off_rounded, size: 48),
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
      );
    }
    return TabBarView(
      controller: _onglets,
      children: <Widget>[
        _ongletTypes(),
        _ongletBonus(),
        _ongletClients(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ONGLET 1 — TYPES DE RÉCIPIENTS
  // ---------------------------------------------------------------------------
  Widget _ongletTypes() {
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _carteTableauDeBord(),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('Récipients configurés',
                  style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: _ajouterType,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          if (_types.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Aucun récipient configuré. Ajoutez par exemple '
                '« Bidon 20 L » ou « Casier 12 bouteilles ».',
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._types.map(_tuileType),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _declarerPerte,
            icon: const Icon(Icons.report_gmailerrorred_rounded),
            label: const Text('Déclarer une casse ou une perte'),
          ),
        ],
      ),
    );
  }

  Widget _carteTableauDeBord() {
    Widget tuile(String libelle, int valeur, IconData icone, Color couleur) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icone, color: couleur, size: 20),
              const SizedBox(height: 6),
              Text('$valeur',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: couleur,
                  )),
              Text(libelle, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            tuile('Chez les clients', _tableau.chezClients,
                Icons.people_alt_rounded, const Color(0xFF0F766E)),
            const SizedBox(width: 10),
            tuile('Livrés', _tableau.livres, Icons.local_shipping_rounded,
                const Color(0xFF2563EB)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            tuile('Récupérés', _tableau.recuperes, Icons.replay_rounded,
                const Color(0xFF059669)),
            const SizedBox(width: 10),
            tuile('Perdus / cassés', _tableau.perdus + _tableau.casses,
                Icons.report_rounded, const Color(0xFFB91C1C)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Taux de récupération : '
          '${(_tableau.tauxRecuperation * 100).round()} %',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _tuileType(TypeRecipient t) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppCouleurs.marine.withValues(alpha: 0.12),
          child: Icon(Icons.inventory_2_rounded, color: AppCouleurs.marine),
        ),
        title: Text(t.libelle),
        subtitle: Text(
          '${formatMontant(t.prixConsigne)} de consigne'
          '${t.contenanceLitres > 0 ? ' · ${t.contenanceLitres} L' : ''}'
          '${t.actif ? '' : ' · inactif'}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit_rounded),
          onPressed: () => _ajouterType(existant: t),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ONGLET 2 — RÈGLES DE BONUS
  // ---------------------------------------------------------------------------
  Widget _ongletBonus() {
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Exemple : « 5 fardes achetées = 1 offerte ». Le bonus est calculé '
            'automatiquement et n\'est jamais compté comme une vente.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('Règles', style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: _ajouterRegle,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          if (_regles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Aucune règle de bonus.', textAlign: TextAlign.center),
            )
          else
            ..._regles.map(
              (RegleBonus r) => Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    r.actif
                        ? Icons.card_giftcard_rounded
                        : Icons.block_rounded,
                    color: r.actif ? AppCouleurs.marine : Colors.grey,
                  ),
                  title: Text(r.libelle),
                  subtitle: Text(
                    '${r.quantiteDeclencheur} ${r.typeDeclencheur}(s) '
                    '→ ${r.quantiteOfferte} ${r.typeOffert}(s) offert(s)'
                    '${r.actif ? '' : ' · inactive'}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: () => _ajouterRegle(existante: r),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ONGLET 3 — CLIENTS ET RÉCIPIENTS DÉTENUS
  // ---------------------------------------------------------------------------
  Widget _ongletClients() {
    if (_clients.isEmpty) {
      return const Center(child: Text('Aucun client enregistré.'));
    }
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _clients.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int i) {
          final Map<String, dynamic> c = _clients[i];
          final String nom = (c['nom'] ?? 'Client').toString();
          final String? id = c['id']?.toString();
          return ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(nom),
            subtitle: Text((c['telephone'] ?? '').toString()),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: id == null ? null : () => _voirSoldeClient(id, nom),
          );
        },
      ),
    );
  }

  Future<void> _voirSoldeClient(String clientId, String nom) async {
    try {
      final SoldeRecipients s = await _service.soldeClient(clientId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(nom),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ligne('Récipients détenus', s.detenus, misEnAvant: true),
              _ligne('Livrés', s.livres),
              _ligne('Récupérés', s.recuperes),
              _ligne('Vendus', s.vendus),
              _ligne('Perdus', s.perdus),
              _ligne('Cassés', s.casses),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (e) {
      _message(
        e is RecipientsException ? e.message : e.toString(),
        erreur: true,
      );
    }
  }

  Widget _ligne(String libelle, int valeur, {bool misEnAvant = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(libelle),
          Text(
            '$valeur',
            style: TextStyle(
              fontWeight: misEnAvant ? FontWeight.w700 : FontWeight.w500,
              color: misEnAvant ? AppCouleurs.marine : null,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DIALOGUES
  // ---------------------------------------------------------------------------
  Future<void> _ajouterType({TypeRecipient? existant}) async {
    final TextEditingController libelle =
        TextEditingController(text: existant?.libelle ?? '');
    final TextEditingController consigne = TextEditingController(
        text: existant == null ? '' : existant.prixConsigne.toString());
    final TextEditingController contenance = TextEditingController(
        text: (existant?.contenanceLitres ?? 0) == 0
            ? ''
            : existant!.contenanceLitres.toString());

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(existant == null ? 'Nouveau récipient' : 'Modifier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: libelle,
                decoration: const InputDecoration(
                  labelText: 'Nom (ex. Bidon 20 L)',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: consigne,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Prix de consigne',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contenance,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Contenance en litres (facultatif)',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (libelle.text.trim().isEmpty) {
      _message('Indiquez le nom du récipient.', erreur: true);
      return;
    }
    try {
      await _service.enregistrerType(
        id: existant?.id,
        libelle: libelle.text.trim(),
        contenanceLitres: double.tryParse(
            contenance.text.replaceAll(',', '.').trim()),
        prixConsigne:
            double.tryParse(consigne.text.replaceAll(',', '.').trim()) ?? 0,
        actif: existant?.actif ?? true,
        ordre: existant?.ordre ?? 50,
      );
      _message('Récipient enregistré.');
      await _charger();
    } catch (e) {
      _message(e is RecipientsException ? e.message : e.toString(),
          erreur: true);
    }
  }

  Future<void> _ajouterRegle({RegleBonus? existante}) async {
    final TextEditingController libelle =
        TextEditingController(text: existante?.libelle ?? '');
    final TextEditingController declencheur = TextEditingController(
        text: (existante?.quantiteDeclencheur ?? 5).toString());
    final TextEditingController offert = TextEditingController(
        text: (existante?.quantiteOfferte ?? 1).toString());
    String typeDeclencheur = existante?.typeDeclencheur ?? 'farde';
    String typeOffert = existante?.typeOffert ?? 'farde';

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setEtat) => AlertDialog(
          title: Text(existante == null ? 'Nouvelle règle' : 'Modifier'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: libelle,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la règle',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: declencheur,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Achetés'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: typeDeclencheur,
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: 'farde', child: Text('farde')),
                          DropdownMenuItem(
                              value: 'recipient', child: Text('récipient')),
                          DropdownMenuItem(value: 'unite', child: Text('unité')),
                        ],
                        onChanged: (String? v) =>
                            setEtat(() => typeDeclencheur = v ?? 'farde'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: offert,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Offerts'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: typeOffert,
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: 'farde', child: Text('farde')),
                          DropdownMenuItem(
                              value: 'recipient', child: Text('récipient')),
                          DropdownMenuItem(value: 'unite', child: Text('unité')),
                        ],
                        onChanged: (String? v) =>
                            setEtat(() => typeOffert = v ?? 'farde'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (libelle.text.trim().isEmpty) {
      _message('Donnez un nom à la règle.', erreur: true);
      return;
    }
    try {
      await _service.enregistrerRegle(
        id: existante?.id,
        libelle: libelle.text.trim(),
        quantiteDeclencheur: int.tryParse(declencheur.text.trim()) ?? 5,
        typeDeclencheur: typeDeclencheur,
        quantiteOfferte: int.tryParse(offert.text.trim()) ?? 1,
        typeOffert: typeOffert,
        actif: existante?.actif ?? true,
      );
      _message('Règle enregistrée.');
      await _charger();
    } catch (e) {
      _message(e is RecipientsException ? e.message : e.toString(),
          erreur: true);
    }
  }

  Future<void> _declarerPerte() async {
    final List<TypeRecipient> actifs = _types
        .where((TypeRecipient t) => t.actif)
        .toList(growable: false);
    if (actifs.isEmpty) {
      _message('Configurez d\'abord un type de récipient.', erreur: true);
      return;
    }
    String typeId = actifs.first.id;
    String sens = 'perdu';
    final TextEditingController qte = TextEditingController(text: '1');

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setEtat) => AlertDialog(
          title: const Text('Casse ou perte'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: typeId,
                decoration: const InputDecoration(labelText: 'Récipient'),
                items: actifs
                    .map((TypeRecipient t) => DropdownMenuItem<String>(
                          value: t.id,
                          child: Text(t.libelle),
                        ))
                    .toList(growable: false),
                onChanged: (String? v) => setEtat(() => typeId = v ?? typeId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: sens,
                decoration: const InputDecoration(labelText: 'Nature'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'perdu', child: Text('Perdu')),
                  DropdownMenuItem(value: 'casse', child: Text('Cassé')),
                ],
                onChanged: (String? v) => setEtat(() => sens = v ?? 'perdu'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qte,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantité'),
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
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    try {
      await _service.enregistrerPerte(
        typeId: typeId,
        quantite: int.tryParse(qte.text.trim()) ?? 1,
        casse: sens == 'casse',
      );
      _message('Perte enregistrée.');
      await _charger();
    } catch (e) {
      _message(e is RecipientsException ? e.message : e.toString(),
          erreur: true);
    }
  }
}
