// lib/pages/niveaux_abonnement_page.dart
//
// 🧩 CORRECTIF 65 — CATALOGUE DES NIVEAUX D'ABONNEMENT.
//
// Écran du Super Admin : la LISTE des niveaux, avec création, modification et
// suppression. Chaque niveau porte la liste des fonctionnalités qu'il ouvre.
//
// Principe rappelé à l'écran : `fonctionnalités = activité ∩ niveau payé`.
// L'activité dit ce qui a du SENS, le niveau dit ce qui est PAYÉ.
//
// ⚠️ Les écritures passent par les RPC (rôle vérifié, opération journalisée) :
// la table elle-même n'accepte aucune écriture directe (correctif 66).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/fonctionnalites.dart';
import 'package:biashara_yangu/models/niveau_abonnement.dart';
import 'package:biashara_yangu/services/abonnement_niveaux_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class NiveauxAbonnementPage extends StatefulWidget {
  const NiveauxAbonnementPage({super.key});

  @override
  State<NiveauxAbonnementPage> createState() => _NiveauxAbonnementPageState();
}

class _NiveauxAbonnementPageState extends State<NiveauxAbonnementPage> {
  final NiveauxAbonnementService _service = NiveauxAbonnementService.instance;

  List<NiveauAbonnement> _niveaux = <NiveauAbonnement>[];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    if (mounted) setState(() => _chargement = true);

    try {
      final List<NiveauAbonnement> niveaux = await _service.lister();
      if (!mounted) return;
      setState(() {
        _niveaux = niveaux;
        _erreur = null;
        _chargement = false;
      });
    } on NiveauxAbonnementException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  void _message(String texte, {bool erreur = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _ouvrirFormulaire([NiveauAbonnement? niveau]) async {
    final bool? modifie = await context.push<bool>(
      niveau == null
          ? '/niveaux-abonnement/nouveau'
          : '/niveaux-abonnement/${niveau.code}',
    );

    if (modifie == true) await _charger();
  }

  Future<void> _supprimer(NiveauAbonnement niveau) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
        title: Text('Supprimer le niveau « ${niveau.libelle} » ?'),
        content: const Text(
          'Le niveau disparaîtra du catalogue. La suppression est refusée si '
          'des entreprises ou des packs tarifaires l\'utilisent encore.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Retour'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirme != true) return;

    try {
      await _service.supprimer(niveau.code);
      if (!mounted) return;
      _message('Niveau « ${niveau.libelle} » supprimé.');
      await _charger();
    } on NiveauxAbonnementException catch (e) {
      if (!mounted) return;
      _message(e.message, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.estSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Niveaux d\'abonnement')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'Seul le Super Admin définit les niveaux d\'abonnement.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Niveaux d\'abonnement',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _chargement ? null : _charger,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ouvrirFormulaire(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouveau niveau'),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur()
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: <Widget>[
                      _cartePrincipe(),
                      const SizedBox(height: 16),
                      if (_niveaux.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            'Aucun niveau au catalogue. Créez le premier : il '
                            'définira les fonctionnalités ouvertes par un '
                            'abonnement.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ..._niveaux.map(_carteNiveau),
                    ],
                  ),
                ),
    );
  }

  Widget _vueErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(_erreur!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartePrincipe() {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.info_outline_rounded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Comment ça marche',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Un écran doit avoir du SENS (l\'activité : pharmacie, hôtel…) '
            'ET être PAYÉ (le niveau d\'abonnement). Les deux règles se '
            'croisent.\n\n'
            'Tant qu\'aucun niveau n\'est affecté à une entreprise, TOUTES les '
            'fonctionnalités restent visibles : cette page ne peut donc rien '
            'retirer par accident.',
            style: TextStyle(fontSize: 12.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _carteNiveau(NiveauAbonnement niveau) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _ouvrirFormulaire(niveau),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      niveau.libelle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (!niveau.actif)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'inactif',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (String valeur) {
                      if (valeur == 'modifier') {
                        _ouvrirFormulaire(niveau);
                      } else {
                        _supprimer(niveau);
                      }
                    },
                    itemBuilder: (BuildContext ctx) =>
                        const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'modifier',
                        child: Text('Modifier'),
                      ),
                      PopupMenuItem<String>(
                        value: 'supprimer',
                        child: Text('Supprimer'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                niveau.prixMensuelConseille == null
                    ? 'prix conseillé non renseigné'
                    : '${formatMontant(niveau.prixMensuelConseille!)} / mois '
                        '(conseillé)',
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(Icons.widgets_outlined,
                      size: 15, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    niveau.toutesLesFonctionnalites
                        ? 'Toutes les fonctionnalités de l\'activité'
                        : '${niveau.nbFonctionnalites} fonctionnalité'
                            '${niveau.nbFonctionnalites > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                niveau.toutesLesFonctionnalites
                    ? 'Tout le catalogue, y compris les fonctionnalités à venir.'
                    : niveau.fonctionnalitesTriees
                        .map((String code) => Fonctionnalites.libelleDe(code))
                        .join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
