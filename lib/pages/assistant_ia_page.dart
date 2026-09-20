// lib/pages/assistant_ia_page.dart
//
// MODULE 13 — ÉCRAN « ASSISTANT IA » (CHAT).
//
//   • bulles : utilisateur (dégradé marine, à droite), assistant (carte
//     claire, à gauche), erreurs (fond rouge doux) ;
//   • actions exécutées par l'agent : encadré vert avec ✓ (rouge si échec) —
//     c'est la trace visible de ce que l'IA a RÉELLEMENT fait ;
//   • badge de QUOTAS restants dans la barre (mis à jour après chaque
//     réponse) + bouton d'achat quand le solde est bas ;
//   • « L'assistant réfléchit… » pendant l'appel à l'Edge Function ;
//   • suggestions de départ ; bouton « Nouvelle conversation » (vide l'écran,
//     l'historique serveur est conservé pour le contexte) ;
//   • actions sensibles (annulation, suppression, prix, stock) : l'assistant
//     DEMANDE une confirmation écrite avant d'exécuter (garde serveur) ; la
//     même règle s'applique donc ici sans popup supplémentaire.
//
// ⚠️ Aucun appel direct à DeepSeek : tout passe par l'Edge Function `agent-ia`
// (clé secrète côté serveur, abonnement vérifié, quotas débités, outils
// exécutés avec VOS droits, tout journalisé).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/agent_ia.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/agent_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Écran de conversation avec l'assistant IA.
class AssistantIaPage extends StatefulWidget {
  const AssistantIaPage({super.key});

  @override
  State<AssistantIaPage> createState() => _AssistantIaPageState();
}

class _AssistantIaPageState extends State<AssistantIaPage> {
  final AgentService _service = AgentService.instance;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<MessageAgent> _messages = <MessageAgent>[];
  EtatAgentIa? _etat;
  bool _chargementEtat = true;
  bool _envoiEnCours = false;
  int? _soldeRestant;

  /// Suggestions affichées quand la conversation est vide.
  static const List<String> _suggestions = <String>[
    'Quelles sont les ventes d\'aujourd\'hui ?',
    'Montre-moi le stock faible',
    'Rapport des ventes des 7 derniers jours',
    'Combien me reste-t-il de quotas ?',
  ];

  int get _solde =>
      _soldeRestant ?? _etat?.moi.quotasDisponibles ?? 0;

  @override
  void initState() {
    super.initState();
    _chargerEtat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // ÉTAT DES QUOTAS
  // ---------------------------------------------------------------------------

  Future<void> _chargerEtat() async {
    setState(() => _chargementEtat = true);
    try {
      final EtatAgentIa etat = await _service.chargerEtat();
      if (!mounted) return;
      setState(() {
        _etat = etat;
        _soldeRestant = etat.moi.quotasDisponibles;
        _chargementEtat = false;
      });
    } on AgentServiceException catch (e) {
      if (!mounted) return;
      setState(() => _chargementEtat = false);
      _snack(e.message, erreur: true);
    } catch (e) {
      debugPrint('AssistantIaPage._chargerEtat : $e');
      if (mounted) setState(() => _chargementEtat = false);
    }
  }

  // ---------------------------------------------------------------------------
  // ENVOI D'UN MESSAGE
  // ---------------------------------------------------------------------------

  Future<void> _envoyer([String? texteForce]) async {
    final String message = (texteForce ?? _controller.text).trim();
    if (message.isEmpty || _envoiEnCours) return;

    setState(() {
      _messages = <MessageAgent>[
        ..._messages,
        MessageAgent(role: 'user', contenu: message),
      ];
      _envoiEnCours = true;
    });
    _controller.clear();
    _defilerEnBas();

    try {
      final ReponseAgent reponse = await _service.envoyerMessage(message);
      if (!mounted) return;
      setState(() {
        _messages = <MessageAgent>[
          ..._messages,
          MessageAgent(
            role: 'assistant',
            contenu: reponse.reponse,
            actions: reponse.actions,
            quotasConsommes: reponse.quotasConsommes,
            montantCdf: reponse.montantCdf,
          ),
        ];
        _soldeRestant = reponse.soldeRestant;
      });
    } on AgentServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = <MessageAgent>[
          ..._messages,
          MessageAgent(
            role: 'assistant',
            contenu: e.message,
            erreur: true,
            codeErreur: e.code,
          ),
        ];
        if (e.solde != null) _soldeRestant = e.solde;
      });
    } catch (e) {
      debugPrint('AssistantIaPage._envoyer : $e');
      if (!mounted) return;
      setState(() {
        _messages = <MessageAgent>[
          ..._messages,
          const MessageAgent(
            role: 'assistant',
            contenu: 'Une erreur inattendue est survenue. Réessayez.',
            erreur: true,
          ),
        ];
      });
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
      _defilerEnBas();
    }
  }

  void _defilerEnBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _nouvelleConversation() {
    setState(() => _messages = <MessageAgent>[]);
    _snack('Nouvelle conversation (l\'historique reste conservé pour le contexte).');
  }

  void _snack(String message, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: erreur ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.peutVoir(PageAccess.assistantIa)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Assistant IA')),
        body: const AccesRefuse(
          message: 'Votre rôle ne permet pas d\'utiliser l\'assistant IA.',
        ),
      );
    }

    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Assistant IA',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          // Badge de quotas restants.
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _solde <= 5
                    ? Colors.orange.withValues(alpha: 0.15)
                    : theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _solde <= 5
                      ? Colors.orange.shade700.withValues(alpha: 0.5)
                      : theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.bolt_rounded,
                    size: 16,
                    color: _solde <= 5
                        ? Colors.orange.shade800
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _chargementEtat ? '…' : '$_solde quotas',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _solde <= 5
                          ? Colors.orange.shade900
                          : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Nouvelle conversation',
            onPressed: _messages.isEmpty ? null : _nouvelleConversation,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
          IconButton(
            tooltip: 'Acheter des quotas',
            onPressed: () async {
              await context.pushNamed('achat-quotas');
              if (mounted) _chargerEtat();
            },
            icon: const Icon(Icons.shopping_cart_checkout_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_etat != null && !_etat!.config.actif)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: Colors.amber.withValues(alpha: 0.2),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.pause_circle_outline_rounded, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'L\'assistant est temporairement désactivé par l\'administrateur.',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _messages.isEmpty && !_envoiEnCours
                ? _vueAccueil(theme)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    itemCount: _messages.length + (_envoiEnCours ? 1 : 0),
                    itemBuilder: (BuildContext context, int index) {
                      if (index >= _messages.length) {
                        return _bulleReflexion(theme);
                      }
                      return _bulle(theme, _messages[index]);
                    },
                  ),
          ),
          _barreSaisie(theme),
        ],
      ),
    );
  }

  Widget _vueAccueil(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      children: <Widget>[
        Icon(
          Icons.smart_toy_rounded,
          size: 76,
          color: theme.colorScheme.primary.withValues(alpha: 0.8),
        ),
        const SizedBox(height: 14),
        Text(
          'Bonjour ! Je suis l\'assistant de Biashara Yangu.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Je peux consulter et agir sur votre boutique (ventes, stock, clients, '
          'rapports…) selon vos droits. Chaque réponse est facturée en quotas '
          '(1 quota ≈ 20 caractères, 150 CDF).',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Essayez par exemple :',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _suggestions
              .map(
                (String suggestion) => ActionChip(
                  label: Text(suggestion),
                  onPressed: _envoiEnCours ? null : () => _envoyer(suggestion),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _bulleReflexion(ThemeData theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'L\'assistant réfléchit…',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bulle(ThemeData theme, MessageAgent message) {
    if (message.deUtilisateur) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          margin: const EdgeInsets.only(bottom: 10, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            gradient: AppDegrades.primaire,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(
            message.contenu,
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
          ),
        ),
      );
    }

    // — Assistant (réponse normale ou erreur) —
    final bool erreur = message.erreur;
    final Color fond = erreur
        ? Colors.red.shade50
        : theme.colorScheme.surfaceContainer;
    final Color bordure = erreur
        ? Colors.red.shade200
        : theme.colorScheme.outlineVariant;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        margin: const EdgeInsets.only(bottom: 10, right: 30),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: fond,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
          ),
          border: Border.all(color: bordure),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (erreur)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message.contenu,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                message.contenu,
                style: const TextStyle(fontSize: 14, height: 1.35),
              ),

            // — Actions exécutées (encadré vert, ✓) —
            if (message.actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final ActionAgent action in message.actions)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              action.succes
                                  ? Icons.check_circle_rounded
                                  : Icons.error_rounded,
                              size: 16,
                              color: action.succes
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                action.libelle,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],

            // — Coût de la réponse —
            if (!erreur && message.quotasConsommes > 0) ...<Widget>[
              const SizedBox(height: 7),
              Text(
                '${message.quotasConsommes} quota(s) · '
                '${formatMontant(message.montantCdf, devise: deviseParDefaut)}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            // — Invitation à acheter quand les quotas sont épuisés —
            if (erreur && message.codeErreur == 'QUOTAS_EPUISES') ...<Widget>[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await context.pushNamed('achat-quotas');
                  if (mounted) _chargerEtat();
                },
                icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
                label: const Text('Acheter des quotas'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _barreSaisie(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                enabled: !_envoiEnCours,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _envoyer(),
                decoration: InputDecoration(
                  hintText: 'Écrivez votre demande…',
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _envoiEnCours ? null : () => _envoyer(),
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(14),
              ),
              child: const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
