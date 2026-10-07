// lib/pages/agent_boutiques_page.dart
//
// 🧑‍🌾 MODULE 21 ter — « MES BOUTIQUES » (agent terrain).
//
// L'agent choisit une de SES boutiques et va droit au but : enregistrer sa
// vitrine (ville, position, contacts), publier ses articles, imprimer ses
// QR codes. C'est le « faire aller vite » de la visite terrain.
//
// ⚠️ La liste vient de `rpc_admin_espaces_lister`, désormais CLOISONNÉE : le
// serveur ne renvoie que les boutiques des entreprises prises en charge par
// l'agent. Une interface filtrée ne suffirait pas.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/admin_plateforme.dart';
import 'package:biashara_yangu/pages/ma_vitrine_page.dart';
import 'package:biashara_yangu/pages/mes_publications_page.dart';
import 'package:biashara_yangu/pages/qr_codes_page.dart';
import 'package:biashara_yangu/services/admin_plateforme_service.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';

class AgentBoutiquesPage extends StatefulWidget {
  const AgentBoutiquesPage({super.key});

  @override
  State<AgentBoutiquesPage> createState() => _AgentBoutiquesPageState();
}

class _AgentBoutiquesPageState extends State<AgentBoutiquesPage> {
  final AdminPlateformeService _service = AdminPlateformeService.instance;

  List<EspaceAdmin> _espaces = const <EspaceAdmin>[];
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
      final (List<EspaceAdmin> espaces, ResumeParcEspaces _) =
          await _service.listerEspaces(limite: 300);
      if (!mounted) return;
      setState(() {
        _espaces = espaces;
        _chargement = false;
      });
    } on AdminPlateformeException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  Future<void> _ouvrirVitrine(EspaceAdmin e) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MaVitrinePage(espaceId: e.espaceId),
    ));
    if (mounted) _charger();
  }

  Future<void> _ouvrirPublications(EspaceAdmin e) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MesPublicationsPage(espaceId: e.espaceId),
    ));
    if (mounted) _charger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes boutiques'),
        actions: <Widget>[
          IconButton(
            tooltip: 'QR codes des produits',
            icon: const Icon(Icons.qr_code_2_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const QrCodesPage(modePlateforme: true))),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _charger, child: _corps(context)),
    );
  }

  Widget _corps(BuildContext context) {
    if (_chargement) return const Center(child: ModernLoader());

    if (_erreur != null) {
      return ListView(
        children: <Widget>[
          const SizedBox(height: 80),
          const Icon(Icons.error_outline, size: 56),
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

    if (_espaces.isEmpty) {
      return ListView(
        children: const <Widget>[
          SizedBox(height: 80),
          Icon(Icons.storefront_outlined, size: 56),
          SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aucune boutique dans votre périmètre. Vérifiez ou activez un '
              'dossier : la boutique vous sera rattachée automatiquement.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (final EspaceAdmin e in _espaces) _carte(context, e),
      ],
    );
  }

  Widget _carte(BuildContext context, EspaceAdmin e) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool enLigne = e.visiblePubliquement;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.storefront_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(e.nom,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(
                        <String>[
                          if (e.entreprise != null) e.entreprise!,
                          if (e.ville != null) e.ville!,
                          if (e.quartier != null) e.quartier!,
                        ].join(' • '),
                        style: TextStyle(fontSize: 12, color: cs.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: enLigne
                        ? Colors.green.withValues(alpha: 0.15)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    enLigne ? 'Visible' : 'Privée',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: enLigne ? Colors.green.shade800 : cs.outline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${e.nbProduitsPublies}/${e.nbProduits} article(s) publié(s) • '
              '${e.localisationCourte}',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _ouvrirVitrine(e),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Vitrine'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _ouvrirPublications(e),
                    icon: const Icon(Icons.campaign_outlined, size: 18),
                    label: const Text('Publier'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
