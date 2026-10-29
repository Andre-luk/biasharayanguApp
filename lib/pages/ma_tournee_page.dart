// lib/pages/ma_tournee_page.dart
//
// 🚚 MODULE 23 — « MA TOURNÉE » (vue de l'agent / livreur).
//
// L'agent ne voit QUE sa dotation du jour :
//   • il vend à l'unité, dans la limite de ce qui lui a été confié ;
//   • il enregistre les consignes (récipients laissés chez un client) ;
//   • il enregistre les bonus accordés ;
//   • la vente est une VRAIE vente serveur (caisse, numéro, stock, journal).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/distribution_terrain.dart';
import 'package:biashara_yangu/services/distribution_service.dart';
import 'package:biashara_yangu/services/donnees_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class MaTourneePage extends StatefulWidget {
  const MaTourneePage({super.key});

  @override
  State<MaTourneePage> createState() => _MaTourneePageState();
}

class _MaTourneePageState extends State<MaTourneePage> {
  final DistributionService _service = DistributionService.instance;
  final TextEditingController _recherche = TextEditingController();

  MaTournee? _tournee;
  List<Map<String, dynamic>> _clients = const <Map<String, dynamic>>[];

  bool _chargement = true;
  bool _action = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _recherche.addListener(() => setState(() {}));
    DonneesService.instance.revision.addListener(_rechargerSilencieux);
    _charger();
  }

  @override
  void dispose() {
    DonneesService.instance.revision.removeListener(_rechargerSilencieux);
    _recherche.dispose();
    super.dispose();
  }

  void _rechargerSilencieux() {
    if (mounted) _charger(silencieux: true);
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux && mounted) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    try {
      final List<dynamic> resultats = await Future.wait(<Future<dynamic>>[
        _service.maTournee(),
        _service.listerClients(),
      ]);
      if (!mounted) return;
      setState(() {
        _tournee = resultats[0] as MaTournee?;
        _clients = resultats[1] as List<Map<String, dynamic>>;
        _chargement = false;
        _erreur = null;
      });
    } on DistributionException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e) {
      debugPrint('MaTourneePage._charger : $e');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger votre tournée.';
        _chargement = false;
      });
    }
  }

  Future<void> _demarrer() async {
    final MaTournee? t = _tournee;
    if (t == null) return;
    setState(() => _action = true);
    try {
      await _service.demarrerTournee(t.id);
      await _charger(silencieux: true);
      _message('Tournée démarrée. Bonne route !');
    } on DistributionException catch (e) {
      _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _action = false);
    }
  }

  // ---------------------------------------------------------------------------
  // VENTE
  // ---------------------------------------------------------------------------

  Future<void> _vendre(LigneTournee ligne) async {
    if (ligne.epuisee) {
      _message('Cet article est épuisé dans votre dotation.', erreur: true);
      return;
    }

    final TextEditingController q = TextEditingController(text: '1');
    String mode = 'especes';

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) maj) {
          final double quantite =
              double.tryParse(q.text.replaceAll(',', '.')) ?? 0;
          final double total = quantite * ligne.prixVente;

          return AlertDialog(
            title: Text(ligne.nom),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Restant : ${formatQuantite(ligne.restante)} ${ligne.unite} '
                  '• ${formatMontant(ligne.prixVente)} l\'unité',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: q,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => maj(() {}),
                  decoration: InputDecoration(
                    labelText: 'Quantité',
                    suffixText: ligne.unite,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                        value: 'especes', label: Text('Espèces')),
                    ButtonSegment<String>(
                        value: 'mobile_money', label: Text('Mobile')),
                  ],
                  selected: <String>{mode},
                  onSelectionChanged: (Set<String> s) =>
                      maj(() => mode = s.first),
                ),
                const SizedBox(height: 12),
                Text(
                  'Total : ${formatMontant(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: quantite <= 0 || quantite > ligne.restante + 0.0001
                    ? null
                    : () => Navigator.of(ctx).pop(true),
                child: const Text('Encaisser'),
              ),
            ],
          );
        },
      ),
    );

    final double quantite =
        double.tryParse(q.text.replaceAll(',', '.')) ?? 0;
    q.dispose();
    if (valide != true || quantite <= 0) return;

    setState(() => _action = true);
    try {
      final Map<String, dynamic> vente = await _service.vendre(
        lignes: <Map<String, dynamic>>[
          <String, dynamic>{'produit_id': ligne.produitId, 'quantite': quantite},
        ],
        modePaiement: mode,
      );
      await _charger(silencieux: true);
      final String numero = (vente['numero_vente'] ?? '').toString();
      _message(
        'Vente ${numero.isEmpty ? '' : '$numero '}enregistrée : '
        '${formatMontant((vente['total'] as num?)?.toDouble() ?? 0)}.',
      );
    } on DistributionException catch (e) {
      _message(e.message, erreur: true);
    } catch (e) {
      debugPrint('MaTourneePage._vendre : $e');
      _message('Vente non confirmée : réessayez.', erreur: true);
    } finally {
      if (mounted) setState(() => _action = false);
    }
  }

  // ---------------------------------------------------------------------------
  // CONSIGNE / BONUS
  // ---------------------------------------------------------------------------

  Future<int?> _choisirClient() async {
    return showDialog<int>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Client'),
        content: SizedBox(
          width: 420,
          height: 320,
          child: _clients.isEmpty
              ? const Text('Aucun client enregistré.')
              : ListView.builder(
                  itemCount: _clients.length,
                  itemBuilder: (BuildContext c, int i) {
                    final Map<String, dynamic> client = _clients[i];
                    final int id = int.tryParse('${client['id']}') ?? 0;
                    return ListTile(
                      title: Text('${client['nom'] ?? 'Client'}'),
                      subtitle: client['telephone'] == null
                          ? null
                          : Text('${client['telephone']}'),
                      onTap: () => Navigator.of(ctx).pop(id),
                    );
                  },
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _consigne() async {
    final int? clientId = await _choisirClient();
    if (clientId == null || !mounted) return;

    final TextEditingController q = TextEditingController(text: '1');
    final TextEditingController libelle =
        TextEditingController(text: 'Casier');

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Consigne client'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: libelle,
              decoration: const InputDecoration(
                labelText: 'Type de récipient',
                hintText: 'Casier, bouteille, seau…',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: q,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(labelText: 'Quantité laissée'),
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
    );

    final int quantite = int.tryParse(q.text) ?? 0;
    final String type = libelle.text.trim();
    q.dispose();
    libelle.dispose();

    if (valide != true || quantite <= 0) return;

    setState(() => _action = true);
    try {
      await _service.enregistrerConsigne(
        clientId: clientId,
        libelle: type.isEmpty ? 'Récipient' : type,
        quantite: quantite,
      );
      await _charger(silencieux: true);
      _message('Consigne enregistrée.');
    } on DistributionException catch (e) {
      _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _action = false);
    }
  }

  Future<void> _bonus() async {
    final int? clientId = await _choisirClient();
    if (clientId == null || !mounted) return;

    final TextEditingController montant = TextEditingController(text: '0');
    String nature = 'remise';

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) maj) =>
            AlertDialog(
          title: const Text('Bonus client'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'remise', label: Text('Remise')),
                  ButtonSegment<String>(value: 'cadeau', label: Text('Cadeau')),
                  ButtonSegment<String>(
                      value: 'fidelite', label: Text('Fidélité')),
                ],
                selected: <String>{nature},
                onSelectionChanged: (Set<String> s) =>
                    maj(() => nature = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: montant,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(labelText: 'Montant'),
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

    final double valeur =
        double.tryParse(montant.text.replaceAll(',', '.')) ?? 0;
    montant.dispose();
    if (valide != true) return;

    setState(() => _action = true);
    try {
      await _service.enregistrerBonus(
        clientId: clientId,
        nature: nature,
        montant: valeur,
      );
      await _charger(silencieux: true);
      _message('Bonus enregistré.');
    } on DistributionException catch (e) {
      _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _action = false);
    }
  }

  Future<void> _recuperer(ConsigneRecipient consigne) async {
    final TextEditingController q =
        TextEditingController(text: '${consigne.restante}');

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Récupérer — ${consigne.clientNom}'),
        content: TextField(
          controller: q,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: 'Quantité récupérée',
            helperText: 'Restant : ${consigne.restante}',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Récupérer'),
          ),
        ],
      ),
    );

    final int quantite = int.tryParse(q.text) ?? 0;
    q.dispose();
    if (valide != true || quantite <= 0) return;

    setState(() => _action = true);
    try {
      await _service.recupererConsigne(consigne.id, quantite);
      await _charger(silencieux: true);
      _message('Consigne mise à jour.');
    } on DistributionException catch (e) {
      _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _action = false);
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? const Color(0xFFB91C1C) : null,
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
        title: const Text('Ma tournée'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: () => _charger(silencieux: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: ModernLoader(legende: 'Chargement…'))
          : _corps(),
    );
  }

  Widget _corps() {
    final ThemeData theme = Theme.of(context);
    final MaTournee? t = _tournee;

    if (_erreur != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(_erreur!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _charger(),
            child: const Text('Réessayer'),
          ),
        ],
      );
    }

    if (t == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const SizedBox(height: 60),
          Icon(Icons.local_shipping_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Aucune tournée en cours',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Votre patron prépare votre dotation depuis son espace '
            '« Tournées & distribution ». Elle apparaîtra ici.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final List<LigneTournee> lignes = t.lignes;

    return RefreshIndicator(
      onRefresh: () => _charger(silencieux: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppDegrades.hero,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t.reference,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  <String>[
                    t.statut.libelle,
                    if (t.zone.isNotEmpty) 'Zone ${t.zone}',
                    '${t.produitsRestants} article(s) à vendre',
                  ].join(' • '),
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _Bloc(
                      label: 'Restant',
                      valeur: formatQuantite(t.quantiteRestante),
                    ),
                    _Bloc(
                      label: 'Vendu',
                      valeur: formatMontant(t.chiffreAffairesPotentiel),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_action)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          if (!t.demarree) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _action ? null : _demarrer,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Démarrer ma tournée'),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _action ? null : _consigne,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Consigne'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _action ? null : _bonus,
                  icon: const Icon(Icons.card_giftcard_rounded),
                  label: const Text('Bonus'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Ma dotation', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _recherche,
            decoration: const InputDecoration(
              hintText: 'Rechercher un article…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 8),
          ...lignes
              .where((LigneTournee l) => l.nom
                  .toLowerCase()
                  .contains(_recherche.text.trim().toLowerCase()))
              .map((LigneTournee l) => _CarteVente(
                    ligne: l,
                    desactive: _action || !t.demarree,
                    onVendre: () => _vendre(l),
                  )),
          if (t.consignes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text('Consignes ouvertes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...t.consignes.map((ConsigneRecipient c) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(c.clientNom.isEmpty
                        ? 'Client non nommé'
                        : c.clientNom),
                    subtitle: Text(<String>[
                      c.libelle,
                      '${c.restante} restant(s)',
                      if (c.zone.isNotEmpty) c.zone,
                    ].join(' • ')),
                    trailing: TextButton(
                      onPressed: _action ? null : () => _recuperer(c),
                      child: const Text('Récupérer'),
                    ),
                  ),
                )),
          ],
          if (t.bonus.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text('Bonus du jour', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...t.bonus.map((BonusClient b) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.card_giftcard_rounded),
                  title: Text(b.clientNom.isEmpty
                      ? 'Client non nommé'
                      : b.clientNom),
                  subtitle: Text(b.libelleNature),
                  trailing: Text(
                    formatMontant(b.montant),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _Bloc extends StatelessWidget {
  const _Bloc({required this.label, required this.valeur});

  final String label;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(
            valeur,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteVente extends StatelessWidget {
  const _CarteVente({
    required this.ligne,
    required this.desactive,
    required this.onVendre,
  });

  final LigneTournee ligne;
  final bool desactive;
  final VoidCallback onVendre;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double progression = ligne.attribuee <= 0
        ? 0
        : (ligne.vendue / ligne.attribuee).clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    ligne.nom,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatMontant(ligne.prixVente),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: progression,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${formatQuantite(ligne.vendue)} / '
                    '${formatQuantite(ligne.attribuee)} ${ligne.unite} • '
                    'restant ${formatQuantite(ligne.restante)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                FilledButton.tonal(
                  onPressed: desactive || ligne.epuisee ? null : onVendre,
                  child: Text(ligne.epuisee ? 'Épuisé' : 'Vendre'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
