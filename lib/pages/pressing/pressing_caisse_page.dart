// lib/pages/pressing/pressing_caisse_page.dart
//
// 🧺 MODULE 35 — CAISSE DU PRESSING.
//
// L'argent d'un pressing entre en plusieurs fois : un acompte au dépôt, le
// solde à la remise. Cet écran répond à la seule question qui compte en fin de
// journée : « qu'est-ce qui est vraiment entré, et par quel moyen ? »
//
// ⚠️ Les encaissements ANNULÉS sont affichés à part : ils n'atténuent jamais le
//    total en silence.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/pressing_caisse.dart';
import 'package:biashara_yangu/services/etablissement_service.dart';
import 'package:biashara_yangu/services/pressing_caisse_pdf_service.dart';
import 'package:biashara_yangu/services/pressing_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class PressingCaissePage extends StatefulWidget {
  const PressingCaissePage({super.key});

  @override
  State<PressingCaissePage> createState() => _PressingCaissePageState();
}

class _PressingCaissePageState extends State<PressingCaissePage> {
  final PressingService _service = PressingService.instance;

  late DateTime _jour = DateTime.now();
  CaisseJourPressing _caisse = const CaisseJourPressing();
  bool _chargement = true;
  String? _erreur;
  String _devise = 'CDF';

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }
    try {
      final CaisseJourPressing caisse = await _service.caisseJour(date: _jour);
      String devise = _devise;
      try {
        final Etablissement etab = await EtablissementService.instance.charger();
        if ((etab.devise).trim().isNotEmpty) devise = etab.devise;
      } catch (_) {
        // Devise : confort d'affichage, jamais bloquant.
      }
      if (!mounted) return;
      setState(() {
        _caisse = caisse;
        _devise = devise;
        _chargement = false;
        _erreur = null;
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

  Future<void> _choisirJour() async {
    final DateTime? choix = await showDatePicker(
      context: context,
      initialDate: _jour,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Journée de la caisse',
    );
    if (choix == null) return;
    setState(() => _jour = choix);
    await _charger();
  }

  Future<void> _imprimer() async {
    try {
      final Etablissement etab = await EtablissementService.instance.charger();
      final DonneesCaissePressing donnees = DonneesCaissePressing(
        etablissement: etab,
        caisse: _caisse,
        devise: _devise,
      );
      await PressingCaissePdfService.instance.imprimer(donnees);
    } catch (e) {
      debugPrint('PressingCaissePage._imprimer : $e');
      _message('Impossible de préparer le rapport sur cet appareil.', erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caisse du pressing'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Changer de journée',
            onPressed: _choisirJour,
            icon: const Icon(Icons.calendar_month_rounded),
          ),
          IconButton(
            tooltip: 'Rapport imprimable',
            onPressed: _chargement ? null : _imprimer,
            icon: const Icon(Icons.print_outlined),
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
              ? _vueErreur(_erreur!)
              : RefreshIndicator(
                  onRefresh: () => _charger(silencieux: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: <Widget>[
                      _enteteJour(),
                      const SizedBox(height: 12),
                      _carteTotaux(),
                      const SizedBox(height: 12),
                      if (_caisse.modesTries.isNotEmpty) _carteModes(),
                      if (_caisse.modesTries.isNotEmpty)
                        const SizedBox(height: 12),
                      _carteActivite(),
                      const SizedBox(height: 16),
                      _titre('Encaissements'),
                      if (_caisse.paiements.isEmpty)
                        _vide()
                      else
                        ..._caisse.paiements.map(_tuilePaiement),
                    ],
                  ),
                ),
    );
  }

  Widget _enteteJour() {
    final bool aujourdhui = _memeJour(_jour, DateTime.now());
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            aujourdhui ? "Aujourd'hui — ${formatDate(_jour)}" : formatDate(_jour),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        TextButton.icon(
          onPressed: _choisirJour,
          icon: const Icon(Icons.edit_calendar_rounded, size: 18),
          label: const Text('Changer'),
        ),
      ],
    );
  }

  static bool _memeJour(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _carteTotaux() {
    return Card(
      elevation: 0,
      color: AppCouleurs.marine,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'ENCAISSÉ',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatMontant(_caisse.encaisse, devise: _devise),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_caisse.nbPaiements} encaissement(s) · '
              '${formatMontant(_caisse.montantFacture, devise: _devise)} facturé',
              style: const TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
            if (_caisse.nbAnnules > 0) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_caisse.nbAnnules} encaissement(s) annulé(s) : '
                  '${formatMontant(_caisse.annule, devise: _devise)} '
                  '(compté à part, jamais déduit en silence)',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _mini('Dépôts', '${_caisse.depots}'),
                ),
                Expanded(
                  child: _mini('Remises', '${_caisse.remises}'),
                ),
                Expanded(
                  child: _mini(
                    'Reste dû',
                    formatMontant(_caisse.resteDu, devise: _devise),
                    alerte: _caisse.resteDu > 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(String libelle, String valeur, {bool alerte = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          libelle,
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
        Text(
          valeur,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: alerte ? const Color(0xFFFFD5D5) : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _carteModes() {
    final ThemeData theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Par moyen de paiement',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._caisse.modesTries.map(
              (TotalModeJour m) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(m.libelle)),
                    Text(
                      '${m.nb}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      formatMontant(m.montant, devise: _devise),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carteActivite() {
    final ThemeData theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline_rounded,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Le reste dû concerne TOUTES les périodes : ce sont les '
                'vêtements déjà remis ou non dont le solde n\'est pas réglé.',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titre(String texte) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texte,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _vide() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: <Widget>[
          Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            'Aucun encaissement ce jour.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _tuilePaiement(PaiementJourPressing p) {
    final ThemeData theme = Theme.of(context);
    final Color couleur = p.annule ? Colors.grey : AppCouleurs.succes;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(
          p.annule ? Icons.cancel_rounded : Icons.payments_rounded,
          color: couleur,
          size: 20,
        ),
        title: Text(
          <String>[
            p.libelleMode,
            if (p.numero.trim().isNotEmpty) p.numero.trim(),
          ].join(' · '),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          <String>[
            if (p.client.trim().isNotEmpty) p.client.trim(),
            if (p.encaisseLe != null) formatDateHeure(p.encaisseLe),
            if (p.agent.trim().isNotEmpty) p.agent.trim(),
            if (p.annule && (p.motifAnnulation ?? '').isNotEmpty)
              'annulé : ${p.motifAnnulation!.trim()}',
          ].join(' · '),
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Text(
          formatMontant(p.montant, devise: _devise),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: p.annule ? Colors.grey : null,
            decoration: p.annule ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }

  Widget _vueErreur(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 56, color: AppCouleurs.danger),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _charger(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
