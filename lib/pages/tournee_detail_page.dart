// lib/pages/tournee_detail_page.dart
//
// 🚚 MODULE 23 — DÉTAIL D'UNE TOURNÉE (patron).
//
// Affiche la dotation, les ventes de l'agent, les consignes et les bonus, puis
// permet de DÉMARRER ou de CLÔTURER (déclaration des retours et calcul de
// l'écart). La clôture est définitive : l'écart reste dans l'historique.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/distribution_terrain.dart';
import 'package:biashara_yangu/services/distribution_service.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class TourneeDetailPage extends StatefulWidget {
  const TourneeDetailPage({super.key, required this.tournee});

  final TourneeDistribution tournee;

  @override
  State<TourneeDetailPage> createState() => _TourneeDetailPageState();
}

class _TourneeDetailPageState extends State<TourneeDetailPage> {
  final DistributionService _service = DistributionService.instance;

  late TourneeDistribution _tournee = widget.tournee;
  List<LigneTournee> _lignes = const <LigneTournee>[];
  List<ConsigneRecipient> _consignes = const <ConsigneRecipient>[];
  List<BonusClient> _bonus = const <BonusClient>[];

  bool _chargement = true;
  bool _action = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final List<dynamic> resultats = await Future.wait(<Future<dynamic>>[
      _service.lignesTournee(_tournee.id),
      _service.consignesDeTournee(_tournee.id),
      _service.bonusDeTournee(_tournee.id),
    ]);

    if (!mounted) return;
    setState(() {
      _lignes = resultats[0] as List<LigneTournee>;
      _consignes = resultats[1] as List<ConsigneRecipient>;
      _bonus = resultats[2] as List<BonusClient>;
      _chargement = false;
    });
  }

  Future<void> _demarrer() async {
    setState(() => _action = true);
    try {
      await _service.demarrerTournee(_tournee.id);
      if (!mounted) return;
      setState(() {
        _tournee = _copierStatut(TourneeStatut.enCours);
        _action = false;
      });
      _message('Tournée démarrée : l\'agent peut vendre sa dotation.');
    } on DistributionException catch (e) {
      if (!mounted) return;
      setState(() => _action = false);
      _message(e.message, erreur: true);
    }
  }

  Future<void> _cloturer() async {
    final Map<int, TextEditingController> controleurs =
        <int, TextEditingController>{
      for (final LigneTournee l in _lignes)
        l.produitId: TextEditingController(text: '0'),
    };

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Clôturer la tournée'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Déclarez les quantités RENDUES à la boutique. Ce qui n\'est '
                  'ni vendu ni rendu devient un ÉCART (responsabilité de '
                  'l\'agent).',
                ),
                const SizedBox(height: 12),
                ..._lignes.map((LigneTournee l) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(l.nom, overflow: TextOverflow.ellipsis),
                              Text(
                                'restant ${formatQuantite(l.restante)} '
                                '${l.unite}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: controleurs[l.produitId],
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]')),
                            ],
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Rendu',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );

    if (confirme != true) {
      for (final TextEditingController c in controleurs.values) {
        c.dispose();
      }
      return;
    }

    final List<Map<String, dynamic>> retours = <Map<String, dynamic>>[];
    for (final LigneTournee l in _lignes) {
      final double q = double.tryParse(
            controleurs[l.produitId]!.text.replaceAll(',', '.'),
          ) ??
          0;
      if (q > 0) {
        retours.add(<String, dynamic>{
          'produit_id': l.produitId,
          'quantite': q,
        });
      }
    }
    for (final TextEditingController c in controleurs.values) {
      c.dispose();
    }

    setState(() => _action = true);
    try {
      final ResultatCloture resultat = await _service.cloturerTournee(
        _tournee.id,
        retours: retours,
        modele: _tournee,
      );
      if (!mounted) return;
      setState(() {
        _tournee = resultat.tournee;
        _action = false;
      });
      await _charger();
      if (!mounted) return;
      _message(
        'Tournée clôturée : écart ${formatQuantite(resultat.tournee.ecart)}.',
      );
    } on DistributionException catch (e) {
      if (!mounted) return;
      setState(() => _action = false);
      _message(e.message, erreur: true);
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

  TourneeDistribution _copierStatut(TourneeStatut statut) {
    return TourneeDistribution(
      id: _tournee.id,
      reference: _tournee.reference,
      dateTournee: _tournee.dateTournee,
      agentId: _tournee.agentId,
      agentNom: _tournee.agentNom,
      zone: _tournee.zone,
      statut: statut,
      nbArticles: _tournee.nbArticles,
      quantiteAttribuee: _tournee.quantiteAttribuee,
      quantiteVendue: _tournee.quantiteVendue,
      quantiteRetournee: _tournee.quantiteRetournee,
      ecart: _tournee.ecart,
      chiffreAffaires: _tournee.chiffreAffaires,
      consignesOuvertes: _tournee.consignesOuvertes,
      consignesTotal: _tournee.consignesTotal,
      bonusTotal: _tournee.bonusTotal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool peutDemarrer = _tournee.statut == TourneeStatut.preparee;
    final bool peutCloturer = _tournee.statut == TourneeStatut.enCours;

    return Scaffold(
      appBar: AppBar(title: Text(_tournee.reference)),
      body: _chargement
          ? const Center(child: ModernLoader(legende: 'Chargement…'))
          : RefreshIndicator(
              onRefresh: _charger,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: <Widget>[
                  _entete(theme),
                  const SizedBox(height: 16),
                  if (_action)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (peutDemarrer)
                    FilledButton.icon(
                      onPressed: _action ? null : _demarrer,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Démarrer la tournée'),
                    ),
                  if (peutCloturer)
                    FilledButton.tonalIcon(
                      onPressed: _action ? null : _cloturer,
                      icon: const Icon(Icons.flag_rounded),
                      label: const Text('Clôturer et déclarer les retours'),
                    ),
                  const SizedBox(height: 20),
                  Text('Dotation', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_lignes.isEmpty)
                    const Text('Aucune ligne.')
                  else
                    ..._lignes.map((LigneTournee l) => _LigneCarte(ligne: l)),
                  const SizedBox(height: 20),
                  Text('Consignes (${_consignes.length})',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_consignes.isEmpty)
                    Text(
                      'Aucun récipient laissé chez un client.',
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    ..._consignes.map((ConsigneRecipient c) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text(c.clientNom.isEmpty
                                ? 'Client non nommé'
                                : c.clientNom),
                            subtitle: Text(<String>[
                              c.libelle,
                              '${c.restante}/${c.quantite} restant(s)',
                              if (c.zone.isNotEmpty) c.zone,
                              c.libelleStatut,
                            ].join(' • ')),
                          ),
                        )),
                  const SizedBox(height: 20),
                  Text('Bonus (${_bonus.length})',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_bonus.isEmpty)
                    Text(
                      'Aucun bonus accordé sur cette tournée.',
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    ..._bonus.map((BonusClient b) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.card_giftcard_rounded),
                            title: Text(b.clientNom.isEmpty
                                ? 'Client non nommé'
                                : b.clientNom),
                            subtitle: Text(<String>[
                              b.libelleNature,
                              if (b.description.isNotEmpty) b.description,
                            ].join(' • ')),
                            trailing: Text(
                              formatMontant(b.montant),
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }

  Widget _entete(ThemeData theme) {
    final DateTime? date = _tournee.dateTournee;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _tournee.agentNom.isEmpty ? 'Agent sans nom' : _tournee.agentNom,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            <String>[
              _tournee.statut.libelle,
              if (date != null) _dateFr(date),
              if (_tournee.zone.isNotEmpty) _tournee.zone,
            ].join(' • '),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _Stat(label: 'Attribué', valeur: formatQuantite(_tournee.quantiteAttribuee)),
              _Stat(label: 'Vendu', valeur: formatQuantite(_tournee.quantiteVendue)),
              _Stat(label: 'Rendu', valeur: formatQuantite(_tournee.quantiteRetournee)),
              _Stat(
                label: 'Écart',
                valeur: formatQuantite(_tournee.ecart),
                couleur: _tournee.ecart > 0.0001 ? const Color(0xFFDC2626) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Chiffre d\'affaires : ${formatMontant(_tournee.chiffreAffaires)}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _LigneCarte extends StatelessWidget {
  const _LigneCarte({required this.ligne});

  final LigneTournee ligne;

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
                  '${formatQuantite(ligne.vendue)} / '
                  '${formatQuantite(ligne.attribuee)} ${ligne.unite}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(value: progression, minHeight: 6),
            ),
            const SizedBox(height: 6),
            Text(
              'Restant ${formatQuantite(ligne.restante)} • '
              'rendu ${formatQuantite(ligne.retournee)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.valeur, this.couleur});

  final String label;
  final String valeur;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            valeur,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: couleur,
            ),
          ),
        ],
      ),
    );
  }
}

String _dateFr(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';
