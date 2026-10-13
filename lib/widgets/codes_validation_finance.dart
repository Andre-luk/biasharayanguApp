// lib/widgets/codes_validation_finance.dart
//
// 🔐 CORRECTIF 69 — CÔTÉ FINANCE : ÉMETTRE LE CODE, PUIS CONFIRMER.
//
// Deux listes, qui répondent aux deux moitiés de la demande :
//
//   1. LES DEMANDES EN COURS — l'agent a demandé un code, la Finance lit les
//      6 chiffres et les lui dicte au téléphone. C'est le seul endroit de
//      l'application où un code est affiché, et il n'est affiché qu'à
//      FINANCE_LAPERLE et SUPER_ADMIN.
//
//   2. LES DOSSIERS À CONFIRMER — les comptes vérifiés sans aucun code validé
//      parce que le délai de 5 minutes était écoulé. C'est la contrepartie
//      indispensable de la règle « l'agent peut continuer » : si l'agent peut
//      passer outre, la Finance DOIT le voir. Sans cette liste, laisser
//      continuer l'agent reviendrait à supprimer le contrôle.
//
// ⚠️ Un code affiché à l'écran ne doit jamais être recopié dans un journal, un
//   champ de note ou un message. Le widget ne fait que l'afficher.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/code_validation_agent.dart';
import 'package:biashara_yangu/services/code_validation_agent_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';

/// Bandeau « codes de validation » pour l'écran Finance.
///
/// Ne prend AUCUNE hauteur quand il n'y a rien à faire : il se réduit à une
/// ligne discrète, afin de ne pas voler la place de la liste des paiements.
class CodesValidationFinanceSection extends StatefulWidget {
  const CodesValidationFinanceSection({super.key});

  @override
  State<CodesValidationFinanceSection> createState() =>
      _CodesValidationFinanceSectionState();
}

class _CodesValidationFinanceSectionState
    extends State<CodesValidationFinanceSection> {
  List<CodeValidationAgent> _ouvertes = const <CodeValidationAgent>[];
  DossiersSansCode _aConfirmer = DossiersSansCode.vide;
  bool _chargement = true;
  bool _deplie = false;
  bool _nonDeploye = false;
  String? _erreur;
  String? _enCours;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);

    try {
      final List<CodeValidationAgent> tous =
          await CodeValidationAgentService.instance.lister(limite: 100);
      DossiersSansCode dossiers = DossiersSansCode.vide;
      try {
        dossiers = await CodeValidationAgentService.instance.dossiersSansCode();
      } on CodeAgentException {
        //  Un agent qui ouvrirait cet écran n'a pas le droit à cette liste ;
        //  ce n'est pas une raison pour lui masquer les demandes de code.
        dossiers = DossiersSansCode.vide;
      }
      if (!mounted) return;

      setState(() {
        _ouvertes = tous.where((CodeValidationAgent c) => c.estOuverte).toList();
        _aConfirmer = dossiers;
        _chargement = false;
        _nonDeploye = false;
        _erreur = null;
      });
    } on CodeAgentException catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _nonDeploye = e.type == TypeErreurCodeAgent.nonDeploye;
        _erreur = _nonDeploye
            ? 'Migration 69 non installée : le code de validation n\'est pas '
                'encore actif sur ce serveur.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = 'Codes de validation indisponibles : $e';
      });
    }
  }

  Future<void> _emettre(CodeValidationAgent demande) async {
    setState(() => _enCours = demande.id);
    try {
      final EmissionCodeAgent? emission =
          await CodeValidationAgentService.instance.emettre(demande.id);
      if (!mounted) return;

      if (emission == null) {
        setState(() => _erreur = 'La Finance n\'a reçu aucun code exploitable.');
        return;
      }

      //  ⚠️ On n'écrit le code nulle part : il est seulement montré, le temps
      //  que la Finance le dicte à l'agent.
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => _DialogueCodeEmis(
          code: emission.code,
          nomCompte: demande.nomAffiche,
          expireLe: emission.expireLe,
          // 🆕 CORRECTIF 75 — l'émission du code a OUVERT le compte.
          activation: emission.activation,
        ),
      );
      await _charger();
    } on CodeAgentException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = null);
    }
  }

  Future<void> _revoquer(CodeValidationAgent demande) async {
    final TextEditingController motif = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Révoquer cette demande ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'La demande pour « ${demande.nomAffiche} » ne sera plus '
              'utilisable. L\'agent devra en demander une autre.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motif,
              decoration: const InputDecoration(
                labelText: 'Motif (enregistré)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );

    final String note = motif.text.trim();
    motif.dispose();
    if (ok != true || !mounted) return;

    setState(() => _enCours = demande.id);
    try {
      await CodeValidationAgentService.instance
          .revoquer(demande.id, motif: note.isEmpty ? null : note);
      if (!mounted) return;
      await _charger();
    } on CodeAgentException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme couleur = Theme.of(context).colorScheme;
    final int nbDemandes = _ouvertes.length;
    final int nbAConfirmer = _aConfirmer.total;
    final int total = nbDemandes + nbAConfirmer;

    //  Rien à signaler : trois lignes discrètes, et surtout pas un gros
    //  panneau vide qui repousserait les dossiers de paiement.
    if (_erreur != null && !_nonDeploye) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _encart(
          couleur.errorContainer,
          couleur.onErrorContainer,
          Icons.error_outline,
          _erreur!,
          action: TextButton(onPressed: _charger, child: const Text('Réessayer')),
        ),
      );
    }

    if (_chargement) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (_nonDeploye) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _encart(
          Colors.grey.shade200,
          Colors.grey.shade800,
          Icons.cloud_off_rounded,
          _erreur!,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (total == 0)
            _encart(
              Colors.green.shade50,
              Colors.green.shade900,
              Icons.verified_user_outlined,
              'Aucun code en attente et aucun dossier à confirmer. '
              'Tout ce qui a été vérifié est couvert par un code.',
              action: IconButton(
                onPressed: _charger,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: 'Actualiser',
              ),
            )
          else
            Material(
              color: nbDemandes > 0
                  ? couleur.primaryContainer
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _deplie = !_deplie),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        nbDemandes > 0
                            ? Icons.pin_outlined
                            : Icons.fact_check_outlined,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          <String>[
                            if (nbDemandes > 0)
                              '$nbDemandes demande(s) de code',
                            if (nbAConfirmer > 0)
                              '$nbAConfirmer dossier(s) à confirmer',
                          ].join('  •  '),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: _charger,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        tooltip: 'Actualiser',
                      ),
                      Icon(_deplie
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded),
                    ],
                  ),
                ),
              ),
            ),
          if (_deplie && total > 0)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final CodeValidationAgent d in _ouvertes)
                      _ligneDemande(d),
                    if (nbAConfirmer > 0) ...<Widget>[
                      const SizedBox(height: 4),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Icon(Icons.fact_check_outlined,
                              size: 16, color: Colors.orange.shade900),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Vérifiés sans code — la Finance doit confirmer',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                          if (_aConfirmer.dossiers.length < nbAConfirmer)
                            Text(
                              '${_aConfirmer.dossiers.length}/$nbAConfirmer affichés',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade700),
                            ),
                        ],
                      ),
                      for (final DossierSansCode d in _aConfirmer.dossiers)
                        _ligneDossier(d),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ligneDemande(CodeValidationAgent d) {
    final bool attente = d.statut == StatutCodeAgent.enAttente;
    final bool enCours = _enCours == d.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            attente ? Icons.hourglass_top_rounded : Icons.lock_open_rounded,
            size: 18,
            color: attente ? Colors.orange.shade800 : Colors.green.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  d.nomAffiche,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  <String>[
                    if (d.demandeParNom != null)
                      'Demandé par ${d.demandeParNom}',
                    if (d.minutesRestantes > 0) d.libelleDelai,
                  ].join('  •  '),
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          if (!attente && d.codeDisponible)
            TextButton.icon(
              onPressed: enCours ? null : () => _montrerCode(d),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Voir'),
            ),
          FilledButton.tonalIcon(
            onPressed: enCours ? null : () => _emettre(d),
            icon: enCours
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(attente ? Icons.send_rounded : Icons.autorenew_rounded,
                    size: 18),
            label: Text(attente ? 'Émettre' : 'Renvoyer'),
          ),
          IconButton(
            onPressed: enCours ? null : () => _revoquer(d),
            icon: const Icon(Icons.block_outlined, size: 18),
            tooltip: 'Révoquer',
          ),
        ],
      ),
    );
  }

  Widget _ligneDossier(DossierSansCode d) {
    //  ⚠️ Les deux cas ne se valent pas : « l'agent n'a rien demandé » et
    //  « la Finance n'a pas répondu » n'appellent pas la même personne.
    final bool agentEnCause = !d.aDemandeUnCode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Icon(
            agentEnCause ? Icons.person_off_outlined : Icons.schedule_rounded,
            size: 15,
            color: agentEnCause ? Colors.red.shade700 : Colors.orange.shade900,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              d.nomAffiche,
              style: const TextStyle(fontSize: 12.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            d.responsabilite,
            style: TextStyle(
              fontSize: 11,
              color:
                  agentEnCause ? Colors.red.shade700 : Colors.orange.shade900,
            ),
          ),
        ],
      ),
    );
  }

  void _montrerCode(CodeValidationAgent d) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => _DialogueCodeEmis(
        code: d.code ?? '',
        nomCompte: d.nomAffiche,
        expireLe: d.expireLe,
        minutesRestantes: d.minutesRestantes,
      ),
    );
  }

  Widget _encart(
    Color fond,
    Color texte,
    IconData icone,
    String message, {
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, 8, action == null ? 12 : 4, 8),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(icone, size: 18, color: texte),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: texte),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LE CODE, MONTRÉ POUR ÊTRE DICTÉ
// ---------------------------------------------------------------------------

class _DialogueCodeEmis extends StatelessWidget {
  const _DialogueCodeEmis({
    required this.code,
    required this.nomCompte,
    this.expireLe,
    this.minutesRestantes,
    this.activation,
  });

  final String code;
  final String nomCompte;
  final DateTime? expireLe;
  final int? minutesRestantes;

  /// 🆕 CORRECTIF 75 — le compte a été ouvert en émettant ce code.
  final ActivationParCode? activation;

  @override
  Widget build(BuildContext context) {
    final ActivationParCode? act = activation;

    //  ⚠️ Le code est affiché en très gros et sélectionnable : la Finance doit
    //  pouvoir le lire au téléphone ou le recopier dans un message. En
    //  revanche il n'existe AUCUN champ « note » ici : prolonger la vie du
    //  code hors de cet écran affaiblirait le contrôle.
    return AlertDialog(
      title: const Text('Code à dicter à l\'agent'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(nomCompte, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          SelectableText(
            code,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: 10,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            minutesRestantes == null
                ? 'Valable 5 minutes. Communiquez-le de vive voix à l\'agent.'
                : 'Il reste $minutesRestantes min. Communiquez-le de vive voix '
                    'à l\'agent.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          if (act != null) ...<Widget>[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (act.ok ? AppCouleurs.succes : Colors.orange)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (act.ok ? AppCouleurs.succes : Colors.orange)
                      .withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    act.ok
                        ? Icons.verified_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: act.ok ? AppCouleurs.succes : Colors.orange.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      act.resume,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Code copié (pour vous, pas pour un journal).'),
              ),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copier'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('J\'ai dicté le code'),
        ),
      ],
    );
  }
}
