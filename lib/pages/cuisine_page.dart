// lib/pages/cuisine_page.dart
//
// 🍽️ MODULE 16 (phase C3) — RESTAURANT : ÉCRAN CUISINE.
//
// Tableau des commandes à préparer (envoyées), en préparation et prêtes.
// La cuisine fait avancer le circuit (« Commencer » → « Prête ») ; le
// service marque « Servie ». Rafraîchissement automatique toutes les
// 20 secondes + tirer pour actualiser.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/commande.dart';
import 'package:biashara_yangu/services/restaurant_service.dart';
import 'package:biashara_yangu/widgets/statut_restaurant_chips.dart';

class CuisinePage extends StatefulWidget {
  const CuisinePage({super.key});

  @override
  State<CuisinePage> createState() => _CuisinePageState();
}

class _CuisinePageState extends State<CuisinePage> {
  final RestaurantService _service = RestaurantService.instance;

  Timer? _minuteur;
  List<Commande> _commandes = const <Commande>[];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
    // La cuisine suit les commandes en continu.
    _minuteur = Timer.periodic(const Duration(seconds: 20), (_) {
      _charger(silencieux: true);
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    String? messageErreur;
    List<Commande> commandes = const <Commande>[];

    try {
      final List<Commande> toutes = await _service.listerCommandes();
      commandes = toutes
          .where((Commande c) => c.statut.enCuisine)
          .toList(growable: false)
        ..sort((Commande a, Commande b) => (a.createdAt ?? DateTime.now())
            .compareTo(b.createdAt ?? DateTime.now()));
    } on RestaurantServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('CuisinePage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement de la cuisine.';
    }

    if (!mounted) return;

    if (messageErreur != null) {
      if (silencieux) return;
      setState(() {
        _erreur = messageErreur;
        _chargement = false;
      });
      return;
    }

    setState(() {
      _commandes = commandes;
      _erreur = null;
      _chargement = false;
    });
  }

  void _message(String texte, {bool erreur = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red.shade700 : null,
      ),
    );
  }

  List<Commande> _de(StatutCommande statut) =>
      _commandes.where((Commande c) => c.statut == statut).toList();

  Future<void> _avancer(Commande commande, StatutCommande etape) async {
    try {
      await _service.avancer(commande.id, etape);
      final String quoi = commande.tableNumero.isEmpty
          ? (commande.numero ?? 'Commande')
          : 'Table ${commande.tableNumero}';
      _message('$quoi : ${etape.libelle.toLowerCase()}.');
      _charger(silencieux: true);
    } on RestaurantServiceException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  String _depuis(DateTime? date) {
    if (date == null) return '';
    final Duration ecart = DateTime.now().difference(date);
    if (ecart.inMinutes < 1) return 'à l\'instant';
    if (ecart.inMinutes < 60) return 'il y a ${ecart.inMinutes} min';
    if (ecart.inHours < 24) return 'il y a ${ecart.inHours} h';
    return 'il y a ${ecart.inDays} j';
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuisine'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Guide d\'utilisation',
            onPressed: () => context.pushNamed('guide-utilisation'),
            icon: const Icon(Icons.help_outline_rounded),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => _charger(),
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
                    child: Text(_erreur!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _charger(silencieux: true),
                  child: _tableau(),
                ),
    );
  }

  Widget _tableau() {
    final List<Commande> aPreparer = _de(StatutCommande.envoyee);
    final List<Commande> enPreparation = _de(StatutCommande.enPreparation);
    final List<Commande> pretes = _de(StatutCommande.prete);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: <Widget>[
        _titreSection('À préparer', Icons.send_rounded, aPreparer.length),
        if (aPreparer.isEmpty)
          _vide('Aucune commande en attente.')
        else
          ...aPreparer.map((Commande c) => _carte(
                c,
                ActionCuisine.commencer,
                const Color(0xFFF59E0B),
              )),
        const SizedBox(height: 8),
        _titreSection('En préparation', Icons.soup_kitchen_rounded,
            enPreparation.length),
        if (enPreparation.isEmpty)
          _vide('Rien sur le feu pour le moment.')
        else
          ...enPreparation.map((Commande c) => _carte(
                c,
                ActionCuisine.prete,
                const Color(0xFFEA580C),
              )),
        const SizedBox(height: 8),
        _titreSection('Prêtes à servir', Icons.notifications_active_rounded,
            pretes.length),
        if (pretes.isEmpty)
          _vide('Aucun plat en attente de service.')
        else
          ...pretes.map((Commande c) => _carte(
                c,
                ActionCuisine.servie,
                const Color(0xFF2563EB),
              )),
      ],
    );
  }

  Widget _titreSection(String texte, IconData icone, int nombre) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: Row(
        children: <Widget>[
          Icon(icone, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texte,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (nombre > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$nombre',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _vide(String texte) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Text(texte, style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Widget _carte(Commande commande, ActionCuisine action, Color couleur) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 18,
                  backgroundColor: couleur.withValues(alpha: 0.14),
                  child: Icon(action.icone, size: 18, color: couleur),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Table ${commande.tableNumero.isEmpty ? '—' : commande.tableNumero}'
                        '${commande.numero == null ? '' : ' • ${commande.numero}'}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${_depuis(commande.createdAt)}'
                        '${commande.clientNom == null ? '' : ' • ${commande.clientNom}'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatutCommandeChip(statut: commande.statut, compact: true),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              commande.resume,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (commande.note != null && commande.note!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text('📝 ${commande.note}', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => _avancer(commande, action.cible),
                icon: Icon(action.icone, size: 18),
                label: Text(action.libelle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Action du bouton principal d'une carte cuisine.
enum ActionCuisine {
  commencer('Commencer', StatutCommande.enPreparation,
      Icons.soup_kitchen_rounded),
  prete('Prête', StatutCommande.prete, Icons.notifications_active_rounded),
  servie('Marquer servie', StatutCommande.servie, Icons.room_service_rounded);

  const ActionCuisine(this.libelle, this.cible, this.icone);

  final String libelle;
  final StatutCommande cible;
  final IconData icone;
}
