// lib/pages/agent_abonnements_page.dart
//
// CORRECTIF 76 — « ABONNEMENTS DE MES BOUTIQUES » (agent terrain).
//
// L'agent apporte un client, crée son compte… et il ne le voyait plus. Cette
// page lui rend SES boutiques, avec l'état réel de leur abonnement :
//
//   • où en est le dossier (vérification, finance, actif) ;
//   • quand l'abonnement expire, et combien de jours restent ;
//   • ce qui a été encaissé et ce qu'il reste à payer ;
//   • à qui appartient la boutique (nom, e-mail, téléphone).
//
// ⚠️ LECTURE SEULE, et c'est voulu : encaisser et activer restent l'affaire de
// la Finance. L'agent SUIT, il n'engage pas d'argent. La liste vient de
// `rpc_agent_mes_boutiques()` — le serveur décide de ce qu'il a le droit de
// voir, l'écran ne fait aucun filtrage de sécurité.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/boutique_agent.dart';
import 'package:biashara_yangu/pages/entreprise_fiche_page.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class AgentAbonnementsPage extends StatefulWidget {
  const AgentAbonnementsPage({super.key});

  @override
  State<AgentAbonnementsPage> createState() => _AgentAbonnementsPageState();
}

class _AgentAbonnementsPageState extends State<AgentAbonnementsPage> {
  MesBoutiquesAgent? _donnees;
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
      final MesBoutiquesAgent donnees =
          await EntrepriseService.instance.mesBoutiquesAgent();
      if (!mounted) return;
      setState(() {
        _donnees = donnees;
        _chargement = false;
      });
    } on EntrepriseServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  Future<void> _ouvrirFiche(BoutiqueAgent b) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntrepriseFichePage(
          entrepriseId: b.entrepriseId,
          nom: b.nom,
        ),
      ),
    );
    if (mounted) _charger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Abonnements de mes clients'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _charger,
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _charger, child: _corps(context)),
    );
  }

  // ---------------------------------------------------------------------------
  // CORPS
  // ---------------------------------------------------------------------------

  Widget _corps(BuildContext context) {
    if (_chargement) {
      return const Center(child: ModernLoader());
    }

    if (_erreur != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const SizedBox(height: 60),
          const Icon(Icons.error_outline_rounded, size: 56),
          const SizedBox(height: 12),
          Text(_erreur!, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ),
        ],
      );
    }

    final MesBoutiquesAgent donnees = _donnees!;

    if (donnees.vide) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const <Widget>[
          SizedBox(height: 60),
          Icon(Icons.storefront_outlined, size: 56),
          SizedBox(height: 12),
          Text(
            'Aucune boutique pour le moment.\n\n'
            'Les comptes que vous créez, et les dossiers que vous prenez en '
            'charge, apparaîtront ici avec leur abonnement.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: <Widget>[
        _BandeauSynthese(donnees: donnees),
        const SizedBox(height: 12),
        for (final BoutiqueAgent b in donnees.boutiques) ...<Widget>[
          _CarteBoutique(boutique: b, onOuvrir: () => _ouvrirFiche(b)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// BANDEAU DE SYNTHÈSE
// ---------------------------------------------------------------------------

class _BandeauSynthese extends StatelessWidget {
  const _BandeauSynthese({required this.donnees});

  final MesBoutiquesAgent donnees;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(gradient: AppDegrades.primaire),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Mon portefeuille',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${donnees.boutiques.length} boutique(s) · '
                  '${donnees.nbActives} actives · '
                  '${donnees.nbEnAttente} en attente',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _Tuile(
                    libelle: 'À encaisser',
                    valeur: formatMontant(donnees.soldeTotal),
                    couleur: donnees.soldeTotal > 0
                        ? AppCouleurs.alerte
                        : AppCouleurs.succes,
                    icone: Icons.account_balance_wallet_rounded,
                  ),
                ),
                Expanded(
                  child: _Tuile(
                    libelle: 'Échues',
                    valeur: '${donnees.nbEchues}',
                    couleur: donnees.nbEchues > 0
                        ? AppCouleurs.danger
                        : AppCouleurs.succes,
                    icone: Icons.event_busy_rounded,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile({
    required this.libelle,
    required this.valeur,
    required this.couleur,
    required this.icone,
  });

  final String libelle;
  final String valeur;
  final Color couleur;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icone, color: couleur, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(libelle,
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
              Text(
                valeur,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: couleur,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// UNE BOUTIQUE
// ---------------------------------------------------------------------------

class _CarteBoutique extends StatelessWidget {
  const _CarteBoutique({required this.boutique, required this.onOuvrir});

  final BoutiqueAgent boutique;
  final VoidCallback onOuvrir;

  Color get _couleurStatut {
    if (boutique.echu) return AppCouleurs.danger;
    if (boutique.enAttenteFinance) return AppCouleurs.alerte;
    if (boutique.suivi.enAttente) return AppCouleurs.info;
    if (boutique.actif) return AppCouleurs.succes;
    return AppCouleurs.alerte;
  }

  @override
  Widget build(BuildContext context) {
    final double du = boutique.totalDu ?? 0;
    final double paye = boutique.dejaPaye ?? 0;
    final double progression = du <= 0 ? 0 : (paye / du).clamp(0.0, 1.0);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOuvrir,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _couleurStatut.withValues(alpha: 0.14),
                    child: Icon(
                      _iconeActivite(boutique.type),
                      color: _couleurStatut,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          boutique.nom,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          <String>[
                            if (boutique.type != null &&
                                boutique.type!.isNotEmpty)
                              boutique.type!,
                            if (boutique.proprietaireNom != null &&
                                boutique.proprietaireNom!.isNotEmpty)
                              boutique.proprietaireNom!,
                          ].join(' · '),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _Puce(
                    texte: boutique.suivi.libelleStatut,
                    couleur: _couleurStatut,
                  ),
                ],
              ),
            ),

            // ------------------------------------------------ étape du dossier
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: <Widget>[
                  Icon(Icons.timeline_rounded,
                      size: 15, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      boutique.suivi.libelleEtape,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (boutique.enAttenteFinance)
                    const _Puce(
                      texte: 'Dossier finance',
                      couleur: AppCouleurs.alerte,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // --------------------------------------------------- échéance
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: <Widget>[
                  Icon(Icons.event_rounded,
                      size: 15, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${boutique.suivi.libelleEcheance} · '
                      'expire le ${formatDate(boutique.dateExpiration)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: _couleurStatut,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // --------------------------------------------------- l'avance
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              child: Column(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progression,
                      minHeight: 6,
                      backgroundColor: Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progression >= 1
                            ? AppCouleurs.succes
                            : AppCouleurs.marineClair,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      _Montant(
                        libelle: 'Encaissé',
                        valeur: formatMontant(paye),
                        couleur: AppCouleurs.succes,
                      ),
                      _Montant(
                        libelle: 'Reste à payer',
                        valeur: formatMontant(boutique.solde ?? 0),
                        couleur: boutique.soldeRestant
                            ? AppCouleurs.danger
                            : AppCouleurs.succes,
                      ),
                      _Montant(
                        libelle: 'Dû du cycle',
                        valeur: formatMontant(du),
                        couleur: AppCouleurs.marine,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),
            const Divider(height: 1),

            // ------------------------------------------- contact + ouverture
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          boutique.proprietaireTelephone?.isNotEmpty == true
                              ? '☎ ${boutique.proprietaireTelephone}'
                              : (boutique.proprietaireEmail ?? 'Contact non renseigné'),
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (boutique.dateActivation != null)
                          Text(
                            'Activé le ${formatDate(boutique.dateActivation)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onOuvrir,
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Fiche'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconeActivite(String? type) {
    switch (type) {
      case 'pharmacie':
        return Icons.local_pharmacy_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'depot':
        return Icons.warehouse_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }
}

class _Montant extends StatelessWidget {
  const _Montant({
    required this.libelle,
    required this.valeur,
    required this.couleur,
  });

  final String libelle;
  final String valeur;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(libelle,
              style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
          Text(
            valeur,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: couleur,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _Puce extends StatelessWidget {
  const _Puce({required this.texte, required this.couleur});

  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: couleur,
        ),
      ),
    );
  }
}
