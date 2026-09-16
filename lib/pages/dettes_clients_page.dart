// lib/pages/dettes_clients_page.dart
//
// MODULE 10 — ÉCRAN « DETTES CLIENTS » (Supabase).
//
//   • liste des dettes (statut, restant dû, ancienneté, échéance) ;
//   • encaissement d'un règlement PARTIEL ou soldant (trigger serveur :
//     `montant_paye` et statut recalculés) ;
//   • relance du client : message pré-rédigé par le serveur + ouverture de
//     WhatsApp / SMS / appels, action tracée dans `journal_audit`.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:biashara_yangu/models/dette_client.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/dette_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class DettesClientsPage extends StatefulWidget {
  const DettesClientsPage({super.key});

  @override
  State<DettesClientsPage> createState() => _DettesClientsPageState();
}

class _DettesClientsPageState extends State<DettesClientsPage> {
  final DetteService _dettes = DetteService.instance;
  final TextEditingController _rechercheCtrl = TextEditingController();

  bool _chargement = true;
  String? _erreur;
  ResultatListeDettes? _liste;
  String? _statut;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = _liste == null;
      _erreur = null;
    });
    try {
      final ResultatListeDettes liste = await _dettes.listerDettes(
        statut: _statut,
        recherche: _rechercheCtrl.text,
      );
      if (!mounted) return;
      setState(() => _liste = liste);
    } on DetteServiceException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'Impossible de charger les dettes : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  bool get _peutEncaisser =>
      PermissionService.instance.peut(PageAccess.caisse, ActionAccess.creer);

  Future<void> _ouvrirCreation() async {
    final bool? cree = await context.push<bool>('/main/dettes/new');
    if (cree == true) _charger();
  }

  // ---------------------------------------------------------------------------
  // PAIEMENT
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirPaiement(DetteClient dette) async {
    final ResultatPaiementDette? resultat =
        await showModalBottomSheet<ResultatPaiementDette>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => _FeuillePaiement(dette: dette),
    );

    if (resultat == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resultat.statut == StatutDette.paye
              ? 'Dette de ${resultat.client} SOLDÉE — ${formatMontant(resultat.montant)} encaissés.'
              : 'Règlement de ${formatMontant(resultat.montant)} enregistré pour ${resultat.client} — reste ${formatMontant(resultat.restant)}.',
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
    _charger();
  }

  // ---------------------------------------------------------------------------
  // RELANCE
  // ---------------------------------------------------------------------------

  Future<void> _relancer(DetteClient dette) async {
    final String? canal = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 12),
            Text(
              'Relancer ${dette.client}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Reste à payer : ${formatMontant(dette.restant)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ...DetteService.canauxRelance.entries.map(
              (MapEntry<String, String> canal) => ListTile(
                leading: Icon(switch (canal.key) {
                  'whatsapp' => Icons.chat_rounded,
                  'sms' => Icons.sms_rounded,
                  _ => Icons.call_rounded,
                }),
                title: Text(canal.value),
                onTap: () => Navigator.of(context).pop(canal.key),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (canal == null || !mounted) return;

    try {
      final RelanceDette relance =
          await _dettes.relancer(detteId: dette.id, canal: canal);

      final Uri lien = switch (canal) {
        'whatsapp' => DetteService.lienWhatsApp(relance.telephone, relance.message),
        'sms' => DetteService.lienSms(relance.telephone, relance.message),
        _ => DetteService.lienAppel(relance.telephone),
      };

      bool ouvert = false;
      try {
        ouvert = await launchUrl(lien, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('DettesClientsPage : ouverture du lien impossible ($e)');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ouvert
                ? 'Relance tracée. Le message s\'ouvre dans l\'application.'
                : 'Relance tracée dans le journal (application de contact indisponible).',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } on DetteServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // RENDU
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Dettes clients',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _peutEncaisser
          ? FloatingActionButton.extended(
              onPressed: _ouvrirCreation,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nouvelle dette'),
            )
          : null,
      body: _construireCorps(),
    );
  }

  Widget _construireCorps() {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.cloud_off_rounded,
                  size: 56, color: Theme.of(context).colorScheme.error),
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

    final ResultatListeDettes liste = _liste ?? const ResultatListeDettes();

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          _carteResume(liste.resume),
          const SizedBox(height: 12),
          _filtres(),
          const SizedBox(height: 12),
          if (liste.lignes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: <Widget>[
                    Icon(Icons.credit_score_rounded,
                        size: 40,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 8),
                    const Text('Aucune dette pour ce filtre.'),
                  ],
                ),
              ),
            )
          else
            ...liste.lignes.map((DetteClient dette) => _carteDette(dette)),
        ],
      ),
    );
  }

  Widget _carteResume(ResumeDettes resume) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.deepOrange.shade600,
            Colors.orange.shade700,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.deepOrange.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.credit_score_rounded,
                  color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'TOTAL RESTANT DÛ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatMontant(resume.totalRestant),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${resume.nbNonPaye} non payée(s) · ${resume.nbPartiel} partielle(s) · ${resume.nbPaye} soldée(s)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtres() {
    Widget chipStatut(String? code, String libelle) {
      return ChoiceChip(
        label: Text(libelle),
        selected: _statut == code,
        onSelected: (bool selection) {
          if (!selection) return;
          setState(() => _statut = code);
          _charger();
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              chipStatut(null, 'Toutes'),
              const SizedBox(width: 8),
              chipStatut('non_paye', 'Non payées'),
              const SizedBox(width: 8),
              chipStatut('partiel', 'Partielles'),
              const SizedBox(width: 8),
              chipStatut('paye', 'Payées'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _rechercheCtrl,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _charger(),
          decoration: InputDecoration(
            labelText: 'Rechercher un client (nom, téléphone)',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Rechercher',
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: _charger,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _carteDette(DetteClient dette) {
    final ThemeData theme = Theme.of(context);

    final (Color statutFond, Color statutTexte) = switch (dette.statut) {
      StatutDette.paye => (
          Colors.green.shade700.withValues(alpha: 0.12),
          Colors.green.shade800
        ),
      StatutDette.partiel => (
          Colors.orange.shade700.withValues(alpha: 0.14),
          Colors.orange.shade900
        ),
      StatutDette.nonPaye => (
          Colors.red.shade700.withValues(alpha: 0.12),
          Colors.red.shade800
        ),
      StatutDette.inconnu => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant
        ),
    };

    final bool enRetard = dette.enRetard();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Text(
                    dette.client.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        dette.client,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (dette.telephone != null)
                        Text(
                          dette.telephone!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      formatMontant(dette.restant),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: dette.estSoldee
                            ? Colors.green.shade700
                            : Colors.deepOrange.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statutFond,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        dette.statut.libelle,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statutTexte,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              <String>[
                'Créée le ${formatDate(dette.dateCreation)} (${dette.jours} j)',
                if (dette.dateEcheance != null)
                  'Échéance : ${formatDate(dette.dateEcheance)}',
                if (dette.nbPaiements > 0)
                  '${dette.nbPaiements} règlement(s) · payé ${formatMontant(dette.montantPaye)} / ${formatMontant(dette.montantTotal)}',
              ].join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (enRetard) ...<Widget>[
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: Colors.red.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'En retard — à relancer',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            if (!dette.estSoldee)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (_peutEncaisser)
                    TextButton.icon(
                      onPressed: () => _ouvrirPaiement(dette),
                      icon: const Icon(Icons.payments_rounded, size: 18),
                      label: const Text('Encaisser'),
                    ),
                  TextButton.icon(
                    onPressed: () => _relancer(dette),
                    icon: const Icon(Icons.campaign_rounded, size: 18),
                    label: const Text('Relancer'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// FEUILLE D'ENCAISSEMENT D'UN RÈGLEMENT
// =============================================================================

class _FeuillePaiement extends StatefulWidget {
  const _FeuillePaiement({required this.dette});

  final DetteClient dette;

  @override
  State<_FeuillePaiement> createState() => _FeuillePaiementState();
}

class _FeuillePaiementState extends State<_FeuillePaiement> {
  final DetteService _dettes = DetteService.instance;

  late final TextEditingController _montantCtrl = TextEditingController(
    text: widget.dette.restant.toStringAsFixed(
      widget.dette.restant == widget.dette.restant.roundToDouble() ? 0 : 2,
    ),
  );

  String _mode = 'especes';
  bool _enregistrement = false;

  @override
  void dispose() {
    _montantCtrl.dispose();
    super.dispose();
  }

  double get _montant {
    final String texte =
        _montantCtrl.text.replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(texte) ?? 0;
  }

  Future<void> _encaisser() async {
    if (_montant <= 0) {
      _afficherErreur('Le montant du règlement doit être supérieur à zéro.');
      return;
    }
    if (_montant > widget.dette.restant + 0.005) {
      _afficherErreur(
          'Le montant dépasse le restant dû (${formatMontant(widget.dette.restant)}).');
      return;
    }

    setState(() => _enregistrement = true);
    try {
      final ResultatPaiementDette resultat = await _dettes.enregistrerPaiement(
        detteId: widget.dette.id,
        montant: _montant,
        modePaiement: _mode,
      );
      if (!mounted) return;
      Navigator.of(context).pop(resultat);
    } on DetteServiceException catch (e) {
      if (!mounted) return;
      _afficherErreur(e.message);
    } catch (e) {
      if (!mounted) return;
      _afficherErreur('Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  void _afficherErreur(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DetteClient dette = widget.dette;
    final bool soldeComplet = _montant >= dette.restant - 0.005;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Encaisser un règlement',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${dette.client} — reste ${formatMontant(dette.restant)} '
            '(total ${formatMontant(dette.montantTotal)})',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _montantCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Montant reçu (CDF)',
              prefixIcon: const Icon(Icons.payments_rounded),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          AppDropdownField<String>(
            label: 'Mode de paiement',
            value: _mode,
            prefixIcon: Icons.credit_card_rounded,
            items: DetteService.modesPaiement.entries
                .map((MapEntry<String, String> entry) =>
                    DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ))
                .toList(growable: false),
            onChanged: (String? valeur) {
              if (valeur != null) setState(() => _mode = valeur);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Icon(
                soldeComplet
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                size: 18,
                color: soldeComplet
                    ? Colors.green.shade700
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  soldeComplet
                      ? 'Règlement complet : la dette sera SOLDÉE.'
                      : 'Règlement partiel : il restera ${formatMontant(dette.restant - _montant)} à payer.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: soldeComplet
                        ? Colors.green.shade700
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _enregistrement ? null : _encaisser,
              icon: _enregistrement
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _enregistrement ? 'Enregistrement…' : 'Encaisser le règlement',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
