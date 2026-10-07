// lib/pages/comptes_verification_page.dart
//
// MODULE 14 — ÉCRAN « COMPTES À VÉRIFIER » (GESTIONNAIRE DES COMPTES).
//
// Première validation du workflow d'activation : le gestionnaire des comptes
// vérifie les dossiers des nouvelles entreprises puis les TRANSMET à la
// finance (ou les rejette avec un motif).
//
// 🔒 SÉPARATION DES RESPONSABILITÉS : cet écran ne peut PAS activer un
// compte — il n'expose aucune action de paiement. Même le Super Admin qui
// voit cet écran doit passer par l'écran Finance (« Activations & paiements »)
// pour valider un paiement. Les deux RPC vérifient le rôle côté serveur.
//
// Chaque décision (vérification, rejet) est consignée dans le journal
// d'audit et dans la table `activations_entreprise`.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/activation.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/activation_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/widgets/dossiers_libres_agent.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Filtres proposés (valeurs d'étape SQL — `null` = tous).
enum _FiltreVerification {
  aVerifier('en_attente_verification', 'À vérifier'),
  rejetes('rejete', 'Rejetés'),
  tous(null, 'Tous');

  const _FiltreVerification(this.etape, this.libelle);

  final String? etape;
  final String libelle;
}

class ComptesVerificationPage extends StatefulWidget {
  const ComptesVerificationPage({super.key});

  @override
  State<ComptesVerificationPage> createState() =>
      _ComptesVerificationPageState();
}

class _ComptesVerificationPageState extends State<ComptesVerificationPage> {
  final TextEditingController _recherche = TextEditingController();

  _FiltreVerification _filtre = _FiltreVerification.aVerifier;
  List<DossierActivation> _dossiers = const <DossierActivation>[];
  bool _chargement = true;
  String? _erreur;

  /// Entreprise en cours de traitement (désactive les boutons de sa carte).
  String? _enCours;

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
      _chargement = true;
      _erreur = null;
    });

    try {
      final List<DossierActivation> dossiers =
          await ActivationService.instance.lister(etape: _filtre.etape);
      if (!mounted) return;
      setState(() {
        _dossiers = dossiers;
        _chargement = false;
      });
    } on ActivationServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger les dossiers : $e';
        _chargement = false;
      });
    }
  }

  List<DossierActivation> get _visibles {
    final String recherche = _recherche.text.trim().toLowerCase();
    if (recherche.isEmpty) return _dossiers;

    return _dossiers.where((DossierActivation d) {
      return d.nom.toLowerCase().contains(recherche) ||
          (d.responsable ?? '').toLowerCase().contains(recherche) ||
          (d.contact ?? '').toLowerCase().contains(recherche);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _approuver(DossierActivation dossier) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Vérifier ce compte ?'),
        content: Text(
          'Le dossier « ${dossier.nom} » sera marqué VÉRIFIÉ et transmis à '
          'la finance pour la validation du paiement et l\'activation.\n\n'
          'Rappel : la vérification n\'active pas le compte — seule la '
          'finance valide l\'activation finale.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Vérifier'),
          ),
        ],
      ),
    );

    if (confirme != true) return;
    await _executer(
      dossier,
      () => ActivationService.instance.verifier(
        entrepriseId: dossier.id,
        approuver: true,
      ),
      succes: 'Dossier « ${dossier.nom} » vérifié et transmis à la finance.',
    );
  }

  Future<void> _rejeter(DossierActivation dossier) async {
    final TextEditingController motif = TextEditingController();

    final String? note = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _DialogueMotif(
        titre: 'Rejeter ce dossier ?',
        message:
            'Le dossier « ${dossier.nom} » sera rejeté. Le demandeur pourra '
            'corriger puis resoumettre. Le motif est enregistré dans le '
            "journal d'audit.",
        bouton: 'Rejeter',
        controleur: motif,
      ),
    );

    motif.dispose();
    if (note == null) return;

    await _executer(
      dossier,
      () => ActivationService.instance.verifier(
        entrepriseId: dossier.id,
        approuver: false,
        note: note,
      ),
      succes: 'Dossier « ${dossier.nom} » rejeté (motif enregistré).',
    );
  }

  Future<void> _executer(
    DossierActivation dossier,
    Future<Object?> Function() action, {
    required String succes,
  }) async {
    setState(() => _enCours = dossier.id);

    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(succes),
          backgroundColor: Colors.green.shade700,
        ),
      );
      await _charger();
    } on ActivationServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opération impossible : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _enCours = null);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Étage 3 du middleware : même si la navigation a laissé passer,
    // l'écran vérifie lui-même la permission.
    if (!PermissionService.instance.peut(
        PageAccess.verificationComptes, ActionAccess.voir)) {
      return const AccesRefuse(
        message: 'Seul le gestionnaire des comptes (ou le Super Admin) '
            'peut vérifier les dossiers d\'activation.',
      );
    }

    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
              const SizedBox(height: 12),
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
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

    final List<DossierActivation> visibles = _visibles;

    return Column(
      children: <Widget>[
        // 🧑‍🌾 MODULE 21 ter — pour un agent, la liste est STRICTEMENT la
        // sienne : les dossiers libres se prennent À PART, jamais mélangés.
        if (PermissionService.instance.estAgentTerrain)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.lock_outline, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Vous ne voyez que VOS dossiers.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final bool pris = await ouvrirFeuilleDossiersLibres(context);
                    if (pris) _charger();
                  },
                  child: const Text('Dossiers libres'),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _recherche,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Rechercher (nom, responsable, email)…',
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: <Widget>[
              ..._FiltreVerification.values.map(
                (_FiltreVerification filtre) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filtre.libelle),
                    selected: _filtre == filtre,
                    onSelected: (_) {
                      setState(() => _filtre = filtre);
                      _charger();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _charger,
            child: visibles.isEmpty
                ? ListView(
                    children: <Widget>[
                      const SizedBox(height: 80),
                      Center(
                        child: Column(
                          children: <Widget>[
                            Icon(Icons.inbox_rounded,
                                size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              _filtre == _FiltreVerification.aVerifier
                                  ? 'Aucun dossier en attente de vérification.'
                                  : 'Aucun dossier à afficher.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visibles.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _carteDossier(context, visibles[index]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _carteDossier(BuildContext context, DossierActivation dossier) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool enCours = _enCours == dossier.id;
    final bool peutValider = PermissionService.instance.peut(
        PageAccess.verificationComptes, ActionAccess.valider);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(Icons.business_rounded,
                      color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        dossier.nom,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        <String>[
                          if ((dossier.ville ?? '').isNotEmpty) dossier.ville!,
                          if ((dossier.activite ?? '').isNotEmpty)
                            dossier.activite!,
                        ].join(' • '),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                _chipEtape(dossier.etape),
              ],
            ),
            const SizedBox(height: 10),
            if ((dossier.responsable ?? '').isNotEmpty ||
                (dossier.contact ?? '').isNotEmpty ||
                (dossier.telephone ?? '').isNotEmpty)
              _ligneInfo(
                Icons.person_outline_rounded,
                <String>[
                  if ((dossier.responsable ?? '').isNotEmpty)
                    dossier.responsable!,
                  if ((dossier.contact ?? '').isNotEmpty) dossier.contact!,
                  if ((dossier.telephone ?? '').isNotEmpty)
                    dossier.telephone!,
                ].join('  •  '),
              ),
            _ligneInfo(
              Icons.payments_outlined,
              'Abonnement : ${dossier.montantTotalDu.toStringAsFixed(0)} CDF'
              '  •  Payé : ${dossier.montantDejaPaye.toStringAsFixed(0)}'
              '  •  Solde : ${dossier.soldeRestant.toStringAsFixed(0)} CDF',
            ),
            if (dossier.createdAt != null)
              _ligneInfo(
                Icons.event_outlined,
                'Dossier déposé le ${_date(dossier.createdAt!)}'
                '${dossier.verifieLe != null ? '  •  Vérifié le ${_date(dossier.verifieLe!)}' : ''}',
              ),
            if ((dossier.dernierMotif ?? '').isNotEmpty)
              _ligneInfo(
                Icons.info_outline_rounded,
                'Dernier motif : ${dossier.dernierMotif!}',
                couleur: Colors.red.shade700,
              ),
            if ((dossier.etape == EtapeActivation.enAttenteVerification ||
                    dossier.etape == EtapeActivation.rejete) &&
                peutValider) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: enCours ? null : () => _rejeter(dossier),
                    icon: const Icon(Icons.cancel_outlined,
                        color: Colors.red),
                    label: const Text('Rejeter',
                        style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: enCours ? null : () => _approuver(dossier),
                    icon: enCours
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_outlined),
                    label: const Text('Vérifier'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chipEtape(EtapeActivation etape) {
    late final Color couleur;
    switch (etape) {
      case EtapeActivation.enAttenteVerification:
        couleur = Colors.orange.shade700;
      case EtapeActivation.verifie:
        couleur = Colors.blue.shade700;
      case EtapeActivation.actif:
        couleur = Colors.green.shade700;
      case EtapeActivation.restreint:
        couleur = Colors.deepOrange.shade800;
      case EtapeActivation.rejete:
        couleur = Colors.red.shade700;
      case EtapeActivation.aucune:
        couleur = Colors.grey.shade600;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: couleur.withValues(alpha: 0.5)),
      ),
      child: Text(
        etape.libelle,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: couleur),
      ),
    );
  }

  Widget _ligneInfo(IconData icone, String texte, {Color? couleur}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, size: 15, color: couleur ?? Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texte,
              style: TextStyle(fontSize: 12.5, color: couleur ?? Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ---------------------------------------------------------------------------
// DIALOGUE DE MOTIF (rejet — motif obligatoire, 3 caractères minimum)
// ---------------------------------------------------------------------------

class _DialogueMotif extends StatefulWidget {
  const _DialogueMotif({
    required this.titre,
    required this.message,
    required this.bouton,
    required this.controleur,
  });

  final String titre;
  final String message;
  final String bouton;
  final TextEditingController controleur;

  @override
  State<_DialogueMotif> createState() => _DialogueMotifState();
}

class _DialogueMotifState extends State<_DialogueMotif> {
  String? _erreur;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.message),
          const SizedBox(height: 12),
          TextField(
            controller: widget.controleur,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Motif (obligatoire)',
              hintText: 'Ex. : informations de l\'entreprise incomplètes',
              errorText: _erreur,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final String valeur = widget.controleur.text.trim();
            if (valeur.length < 3) {
              setState(() => _erreur =
                  'Précisez le motif (3 caractères minimum).');
              return;
            }
            Navigator.of(context).pop(valeur);
          },
          child: Text(widget.bouton),
        ),
      ],
    );
  }
}
