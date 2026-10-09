// lib/widgets/code_validation_agent.dart
//
// 🔐 CORRECTIF 69 — EXIGER UN CODE AVANT QUE L'AGENT CONFIRME.
//
// « avant que l'agent confirme le compte ou valide, il faut un code de
//   validation que finance et super admin doivent pouvoir envoyer pour la
//   traçabilité ; si ce code n'est pas envoyé dans 5 minutes, l'agent peut
//   créer ».
//
// ⚠️ CE DISPOSITIF N'EST PAS UN VERROU — C'EST UNE TRACE.
//
//   Le laisser croire serait la pire des erreurs. La règle voulue est : passé
//   le délai, l'agent CONTINUE (sinon le terrain se bloque et les gens
//   contournent l'application). Ce que la trace apporte, c'est que la Finance
//   VOIT ensuite, dans « Dossiers à confirmer », les comptes vérifiés sans
//   aucun code — et qu'aucun code n'a pu être fabriqué par l'agent lui-même.
//
// ⚠️ LE CODE N'EST JAMAIS AFFICHÉ À L'AGENT COMME VALEUR À LIRE, et il n'est
//   jamais journalisé. L'agent ne fait que SAISIR les 6 chiffres que la
//   Finance lui dicte au téléphone. C'est tout l'intérêt : sans cet échange,
//   l'agent pourrait valider seul, et le contrôle n'existerait plus.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/code_validation_agent.dart';
import 'package:biashara_yangu/services/code_validation_agent_service.dart';

/// Ouvre la boîte « code de validation ».
///
/// Renvoie `true` si l'agent peut poursuivre : soit le code a été SAISI ET
/// ACCEPTÉ, soit le délai de 5 minutes est écoulé (la trace dira alors que
/// l'agent a continué sans code, et la Finance devra confirmer après coup).
/// Renvoie `false` si l'agent a renoncé.
Future<bool> exigerCodeValidationAgent(
  BuildContext context, {
  required String entrepriseId,
  required String nomCompte,
}) async {
  final bool? resultat = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => _DialogueCodeAgent(
      entrepriseId: entrepriseId,
      nomCompte: nomCompte,
    ),
  );
  return resultat == true;
}

class _DialogueCodeAgent extends StatefulWidget {
  const _DialogueCodeAgent({
    required this.entrepriseId,
    required this.nomCompte,
  });

  final String entrepriseId;
  final String nomCompte;

  @override
  State<_DialogueCodeAgent> createState() => _DialogueCodeAgentState();
}

class _DialogueCodeAgentState extends State<_DialogueCodeAgent> {
  final TextEditingController _saisie = TextEditingController();

  CodeValidationAgent? _demande;
  bool _chargement = true;
  bool _action = false;
  String? _erreur;
  Timer? _horloge;

  @override
  void initState() {
    super.initState();
    _charger();
    //  ⚠️ On redemande au SERVEUR toutes les 30 s plutôt que de décrémenter le
    //  délai avec l'horloge du téléphone : si l'appareil est décalé, l'agent
    //  croirait le délai écoulé alors qu'il ne l'est pas (ou l'inverse).
    _horloge = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_action) _charger(silencieux: true);
    });
  }

  @override
  void dispose() {
    _horloge?.cancel();
    _saisie.dispose();
    super.dispose();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    try {
      final List<CodeValidationAgent> codes =
          await CodeValidationAgentService.instance.lister(
        entrepriseId: widget.entrepriseId,
        limite: 20,
      );
      if (!mounted) return;

      //  La demande ouverte la plus récente : le serveur renvoie déjà du plus
      //  récent au plus ancien.
      CodeValidationAgent? ouverte;
      for (final CodeValidationAgent c in codes) {
        if (c.estOuverte) {
          ouverte = c;
          break;
        }
      }

      setState(() {
        _demande = ouverte;
        _chargement = false;
        _erreur = null;
      });
    } on CodeAgentException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.type == TypeErreurCodeAgent.nonDeploye
            ? 'La mise à jour de la base n\'est pas encore installée. '
                'Le code de validation n\'est pas disponible sur ce serveur.'
            : e.message;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de vérifier l\'état du code : $e';
        _chargement = false;
      });
    }
  }

  Future<void> _demander() async {
    setState(() => _action = true);
    try {
      final DemandeCodeAgent? demande =
          await CodeValidationAgentService.instance.demander(
        widget.entrepriseId,
        motif: 'Validation du compte ${widget.nomCompte}',
      );
      if (!mounted) return;

      await _charger(silencieux: true);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            demande?.dejaOuverte == true
                ? 'Une demande était déjà en cours : elle a été conservée.'
                : 'Demande envoyée à la Finance. Elle doit vous dicter le code.',
          ),
        ),
      );
    } on CodeAgentException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _action = false);
    }
  }

  Future<void> _valider() async {
    final String code = _saisie.text.trim();
    if (code.length < 6 || _demande == null) return;

    setState(() => _action = true);
    try {
      await CodeValidationAgentService.instance.valider(_demande!.id, code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CodeAgentException catch (e) {
      if (!mounted) return;
      //  Le serveur explique exactement ce qui ne va pas (faux, expiré, déjà
      //  servi, jamais émis) : on affiche son message tel quel.
      setState(() {
        _action = false;
        _erreur = e.message;
      });
      _saisie.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _action = false;
        _erreur = 'Code non validé : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme couleur = Theme.of(context).colorScheme;
    final CodeValidationAgent? d = _demande;

    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.pin_outlined),
          SizedBox(width: 8),
          Expanded(child: Text('Code de validation')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.nomCompte,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (_chargement)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_erreur != null)
                _encart(couleur.errorContainer, couleur.onErrorContainer,
                    Icons.error_outline, _erreur!)
              else if (d == null)
                ..._vueSansDemande()
              else if (d.statut == StatutCodeAgent.enAttente)
                ..._vueEnAttente(d)
              else
                ..._vueCodeEmis(d),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text(
                'Cette étape est une TRACE, pas un blocage : si la Finance ne '
                'répond pas dans les 5 minutes, vous pouvez continuer — elle '
                'devra alors confirmer le compte après coup.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (_demande?.peutContinuerSansCode == true && !_action)
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.fast_forward_rounded),
            label: const Text('Continuer sans code'),
          ),
        TextButton(
          onPressed: _action ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
      ],
    );
  }

  // --- États de l'écran -------------------------------------------------------

  List<Widget> _vueSansDemande() {
    return <Widget>[
      _encart(
        Colors.orange.shade50,
        Colors.orange.shade900,
        Icons.help_outline_rounded,
        'Aucun code n\'a encore été demandé pour ce compte. Demandez-le : la '
        'Finance vous le dictera, et la saisie sera enregistrée.',
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _action ? null : _demander,
        icon: _action
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.send_rounded),
        label: const Text('Demander un code à la Finance'),
      ),
    ];
  }

  List<Widget> _vueEnAttente(CodeValidationAgent d) {
    return <Widget>[
      _encart(
        Colors.blue.shade50,
        Colors.blue.shade900,
        Icons.hourglass_top_rounded,
        'Demande envoyée à la Finance. En attente de son code…',
      ),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          Icon(Icons.timer_outlined, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              d.libelleDelai.isEmpty ? 'délai écoulé' : d.libelleDelai,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
            ),
          ),
          TextButton(
            onPressed: _action ? null : () => _charger(),
            child: const Text('Actualiser'),
          ),
        ],
      ),
      const SizedBox(height: 4),
      //  Le champ n'apparaît qu'une fois le code émis : le proposer avant
      //  ferait croire à l'agent qu'il peut inventer un code.
      Opacity(
        opacity: 0.5,
        child: Text(
          'La saisie s\'ouvrira dès que la Finance aura émis le code.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      ),
    ];
  }

  List<Widget> _vueCodeEmis(CodeValidationAgent d) {
    final bool bloque = !d.peutEtreSaisi;
    return <Widget>[
      _encart(
        bloque ? Colors.orange.shade50 : Colors.green.shade50,
        bloque ? Colors.orange.shade900 : Colors.green.shade900,
        bloque ? Icons.timer_off_outlined : Icons.lock_open_rounded,
        bloque
            ? 'Le délai de 5 minutes est écoulé. Le code n\'est plus '
                'acceptable — vous pouvez continuer, la Finance confirmera.'
            : 'La Finance a émis un code. Saisissez les 6 chiffres qu\'elle '
                'vous dicte.',
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _saisie,
        enabled: !bloque && !_action,
        autofocus: !bloque,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: 10,
        ),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          counterText: '',
          hintText: '••••••',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          Icon(Icons.timer_outlined, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            d.libelleDelai,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed:
                bloque || _action || _saisie.text.trim().length < 6 ? null : _valider,
            icon: _action
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded),
            label: const Text('Valider'),
          ),
        ],
      ),
    ];
  }

  Widget _encart(Color fond, Color texte, IconData icone, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, size: 18, color: texte),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: texte),
            ),
          ),
        ],
      ),
    );
  }
}
