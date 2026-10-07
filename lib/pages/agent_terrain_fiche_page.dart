// lib/pages/agent_terrain_fiche_page.dart
//
// 🧑‍🌾 MODULE 21 ter — « MA FICHE TERRAIN ».
//
// Tableau de bord de l'agent : ce qu'il a créé, ses boutiques, ses QR codes,
// ses abonnements et ce qu'ils ont généré comme revenus, plus ses dernières
// actions. Tout provient de `rpc_agent_fiche`, donc DÉJÀ cloisonné sur lui.
//
// Cet écran remplace le tableau de bord plateforme pour le rôle AGENT_TERRAIN
// (voir `admin_home_page.dart`) : un agent n'a rien à voir dans les revenus
// globaux de la plateforme.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/agent_terrain.dart';
import 'package:biashara_yangu/pages/agent_boutiques_page.dart';
import 'package:biashara_yangu/pages/qr_codes_page.dart';
import 'package:biashara_yangu/services/agent_terrain_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class AgentTerrainFichePage extends StatefulWidget {
  const AgentTerrainFichePage({super.key, this.showAppBar = false, this.agentId});

  /// `false` quand la page est intégrée à l'IndexedStack de l'administration
  /// (l'AppBar est alors fournie par `AdminHomePage`).
  final bool showAppBar;

  /// Fiche d'un autre agent (personnel plateforme uniquement).
  final String? agentId;

  @override
  State<AgentTerrainFichePage> createState() => _AgentTerrainFichePageState();
}

class _AgentTerrainFichePageState extends State<AgentTerrainFichePage> {
  final AgentTerrainService _service = AgentTerrainService.instance;

  FicheAgentTerrain? _fiche;
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final FicheAgentTerrain fiche = await _service.fiche(agentId: widget.agentId);
      if (!mounted) return;
      setState(() {
        _fiche = fiche;
        _chargement = false;
      });
    } on AgentTerrainException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget corps = _corps(context);
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('Ma fiche terrain')) : null,
      body: RefreshIndicator(onRefresh: _charger, child: corps),
    );
  }

  Widget _corps(BuildContext context) {
    if (_chargement) {
      return const Center(child: ModernLoader());
    }
    if (_erreur != null) {
      return ListView(
        children: <Widget>[
          const SizedBox(height: 80),
          const Icon(Icons.lock_clock_rounded, size: 56),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_erreur!, textAlign: TextAlign.center),
          ),
          Center(
            child: FilledButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ),
        ],
      );
    }

    final FicheAgentTerrain f = _fiche!;
    final ColorScheme cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // ------------------------------------------------ en-tête
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 26,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.badge_outlined, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(f.nom.isEmpty ? 'Agent terrain' : f.nom,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(f.email, style: TextStyle(color: cs.outline)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Agent terrain',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.onSecondaryContainer)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ------------------------------------------------ revenus
        Row(
          children: <Widget>[
            Expanded(
              child: _CarteStat(
                libelle: 'Encaissé',
                valeur: formatMontant(f.montantEncaisse.toDouble()),
                icone: Icons.savings_rounded,
                couleur: Colors.green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CarteStat(
                libelle: 'Solde dû',
                valeur: formatMontant(f.soldeDu.toDouble()),
                icone: Icons.request_quote_rounded,
                couleur: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ------------------------------------------------ compteurs
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _CarteStat(
              libelle: 'Mes clients',
              valeur: '${f.nbUtilisateurs}',
              icone: Icons.people_alt_rounded,
              couleur: Colors.blue,
            ),
            _CarteStat(
              libelle: 'Mes boutiques',
              valeur: '${f.nbBoutiques}',
              icone: Icons.storefront_rounded,
              couleur: Colors.indigo,
            ),
            _CarteStat(
              libelle: 'Abonnements actifs',
              valeur: '${f.nbAbonnementsActifs}',
              icone: Icons.verified_rounded,
              couleur: Colors.teal,
            ),
            _CarteStat(
              libelle: 'À traiter',
              valeur: '${f.nbEnAttente}',
              icone: Icons.pending_actions_rounded,
              couleur: Colors.deepOrange,
            ),
            _CarteStat(
              libelle: 'QR codes produits',
              valeur: '${f.nbQrCodes}',
              icone: Icons.qr_code_2_rounded,
              couleur: Colors.brown,
            ),
            _CarteStat(
              libelle: 'Articles publiés',
              valeur: '${f.nbProduitsPublies}',
              icone: Icons.campaign_rounded,
              couleur: Colors.purple,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ------------------------------------------------ actions rapides
        Text('Aller vite', style: _titre(cs)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.store_mall_directory_rounded),
                title: const Text('Mes boutiques & vitrines'),
                subtitle: const Text(
                    'Enregistrer la vitrine et publier les articles de mes boutiques'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const AgentBoutiquesPage())),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.qr_code_2_rounded),
                title: const Text('QR codes des produits'),
                subtitle: const Text('Étiqueter les articles de mes boutiques'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const QrCodesPage(modePlateforme: true))),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ------------------------------------------------ mes entreprises
        Text('Mes entreprises', style: _titre(cs)),
        const SizedBox(height: 8),
        if (f.entreprises.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Aucune entreprise prise en charge'),
              subtitle: Text(
                  'Les dossiers que vous vérifiez ou activez vous sont rattachés automatiquement.'),
            ),
          )
        else
          Card(
            child: Column(
              children: <Widget>[
                for (int i = 0; i < f.entreprises.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  _ligneEntreprise(cs, f.entreprises[i]),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),

        // ------------------------------------------------ mes clients
        Text('Mes clients', style: _titre(cs)),
        const SizedBox(height: 8),
        if (f.utilisateurs.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.person_off_outlined),
              title: Text('Aucun client rattaché'),
            ),
          )
        else
          Card(
            child: Column(
              children: <Widget>[
                for (int i = 0; i < f.utilisateurs.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(f.utilisateurs[i].nom.isEmpty
                        ? f.utilisateurs[i].email
                        : f.utilisateurs[i].nom),
                    subtitle: Text(<String>[
                      if (f.utilisateurs[i].entreprise != null)
                        f.utilisateurs[i].entreprise!,
                      if ((f.utilisateurs[i].telephone ?? '').isNotEmpty)
                        f.utilisateurs[i].telephone!,
                    ].join(' • ')),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),

        // ------------------------------------------------ journal
        Text('Mes dernières actions', style: _titre(cs)),
        const SizedBox(height: 8),
        if (f.journal.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.history_rounded),
              title: Text('Aucune action journalisée'),
            ),
          )
        else
          Card(
            child: Column(
              children: <Widget>[
                for (int i = 0; i < f.journal.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: Icon(_iconeAction(f.journal[i].action)),
                    title: Text(_libelleAction(f.journal[i].action)),
                    subtitle: Text(_date(f.journal[i].createdAt)),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _ligneEntreprise(ColorScheme cs, EntrepriseAgentTerrain e) {
    final Color couleur = e.actif
        ? Colors.green
        : e.enAttente
            ? Colors.orange
            : cs.outline;
    return ListTile(
      leading: Icon(Icons.storefront_rounded, color: couleur),
      title: Text(e.nom.isEmpty ? 'Entreprise' : e.nom),
      subtitle: Text(<String>[
        e.libelleEtape,
        if (e.responsable != null && e.responsable!.isNotEmpty) e.responsable!,
        if (e.impaye) 'Solde ${formatMontant(e.soldeRestant.toDouble())}',
      ].join(' • ')),
      trailing: e.impaye
          ? Text(formatMontant(e.soldeRestant.toDouble()),
              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w700))
          : const Icon(Icons.check_circle_outline, color: Colors.green),
    );
  }

  static TextStyle _titre(ColorScheme cs) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: cs.primary,
      );

  static String _date(DateTime? d) {
    if (d == null) return '';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
  }

  static String _libelleAction(String action) {
    switch (action) {
      case 'AGENT_TERRAIN_RATTACHEMENT':
        return 'Prise en charge d\'un dossier';
      case 'ACTIVATION_VERIFIEE':
        return 'Dossier vérifié';
      case 'ACTIVATION_REJETEE':
        return 'Dossier rejeté (vérification)';
      case 'ACTIVATION_FINANCE':
        return 'Paiement validé / compte activé';
      case 'PAIEMENT_REJETE_FINANCE':
        return 'Paiement rejeté';
      case 'MONTANT_TOTAL_FIXE':
        return 'Montant total dû fixé';
      case 'BIASHARA_VITRINE':
        return 'Vitrine enregistrée';
      case 'ADMIN_AGENT_TERRAIN_CREE':
        return 'Création d\'un agent';
      default:
        return action.replaceAll('_', ' ').toLowerCase();
    }
  }

  static IconData _iconeAction(String action) {
    if (action.contains('REJET')) return Icons.cancel_outlined;
    if (action.contains('PAIEMENT') || action.contains('ACTIVATION')) {
      return Icons.payments_outlined;
    }
    if (action.contains('VITRINE')) return Icons.storefront_outlined;
    if (action.contains('RATTACHEMENT')) return Icons.link_rounded;
    return Icons.history_rounded;
  }
}

class _CarteStat extends StatelessWidget {
  const _CarteStat({
    required this.libelle,
    required this.valeur,
    required this.icone,
    required this.couleur,
  });

  final String libelle;
  final String valeur;
  final IconData icone;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 165,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, color: couleur),
          const SizedBox(height: 8),
          Text(valeur,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(libelle,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}
