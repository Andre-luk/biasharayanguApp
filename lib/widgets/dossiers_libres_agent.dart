// lib/widgets/dossiers_libres_agent.dart
//
// 🧑‍🌾 MODULE 21 ter — « DOSSIERS LIBRES À PRENDRE EN CHARGE ».
//
// Un dossier LIBRE est une entreprise qui n'est encore rattachée à AUCUN agent
// (`agent_id IS NULL`) et dont l'activation est en cours. L'agent (secours qui
// va vite) peut les consulter ici, SÉPARÉMENT de ses propres dossiers, et
// choisir explicitement de les prendre en charge.
//
// Objectif : ses listes de travail (« Vérifications », « Activations ») ne
// contiennent QUE ses dossiers ; les libres ne s'y mélangent jamais.
//
// 🔒 La prise en charge est refusée côté serveur si un autre agent s'en est
// déjà saisi (`DROIT_REFUSE`).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/agent_terrain.dart';
import 'package:biashara_yangu/services/agent_terrain_service.dart';

/// Ouvre la feuille des dossiers libres.
///
/// Retourne `true` si au moins un dossier a été pris en charge (l'appelant
/// peut alors rafraîchir ses listes).
Future<bool> ouvrirFeuilleDossiersLibres(BuildContext context) async {
  final bool? resultat = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _FeuilleDossiersLibres(),
  );
  return resultat == true;
}

class _FeuilleDossiersLibres extends StatefulWidget {
  const _FeuilleDossiersLibres();

  @override
  State<_FeuilleDossiersLibres> createState() => _FeuilleDossiersLibresState();
}

class _FeuilleDossiersLibresState extends State<_FeuilleDossiersLibres> {
  final AgentTerrainService _service = AgentTerrainService.instance;

  List<EntrepriseAgentTerrain> _dossiers = const <EntrepriseAgentTerrain>[];
  bool _chargement = true;
  bool _pris = false;
  String? _erreur;
  String? _enCours;

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
      final List<EntrepriseAgentTerrain> dossiers =
          await _service.dossiersLibres();
      if (!mounted) return;
      setState(() {
        _dossiers = dossiers;
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

  Future<void> _prendre(EntrepriseAgentTerrain d) async {
    setState(() => _enCours = d.id);
    try {
      await _service.rattacher(d.id);
      if (!mounted) return;
      setState(() {
        _dossiers = _dossiers.where((EntrepriseAgentTerrain e) => e.id != d.id).toList();
        _pris = true;
        _enCours = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('« ${d.nom} » vous est maintenant rattaché.'),
      ));
    } on AgentTerrainException catch (e) {
      if (!mounted) return;
      setState(() => _enCours = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      _charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.inbox_rounded, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Dossiers libres à prendre en charge',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(_pris),
                ),
              ],
            ),
            const Text(
              'Ces dossiers ne sont rattachés à aucun agent. Prenez-en un : '
              'il rejoindra vos listes (Vérifications, Activations, Mes boutiques).',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: _contenu(cs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenu(ColorScheme cs) {
    if (_chargement) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_erreur != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_erreur!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    if (_dossiers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text('Aucun dossier libre pour le moment.',
              textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _dossiers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int i) {
        final EntrepriseAgentTerrain d = _dossiers[i];
        final bool enCours = _enCours == d.id;
        return ListTile(
          leading: Icon(Icons.storefront_rounded, color: cs.primary),
          title: Text(d.nom.isEmpty ? 'Entreprise' : d.nom),
          subtitle: Text(<String>[
            d.libelleEtape,
            if ((d.responsable ?? '').isNotEmpty) d.responsable!,
            if ((d.contact ?? '').isNotEmpty) d.contact!,
          ].join(' • ')),
          trailing: enCours
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton.tonal(
                  onPressed: () => _prendre(d),
                  child: const Text('Prendre'),
                ),
        );
      },
    );
  }
}
