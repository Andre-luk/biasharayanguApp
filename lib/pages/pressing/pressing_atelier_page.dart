// lib/pages/pressing/pressing_atelier_page.dart
//
// 🧺 MODULE 35 — L'ATELIER : la file de travail des agents.
//
// CE QUE VOIT L'AGENT
//   Chaque VÊTEMENT à traiter (pas les dossiers) : ce qu'il est, à qui il
//   appartient, quand il est attendu, et où il en est. Il peut :
//     • filtrer par étape (prêt, lavage, repassage…) et par agent ;
//     • sélectionner plusieurs vêtements et les faire avancer d'un coup ;
//     • passer le contrôle qualité (conforme ⇒ prêt, sinon ⇒ à retraiter).
//
// ⚠️ Le serveur décide : il refuse d'avancer un vêtement déjà remis, vérifie
//    les droits et écrit l'historique (qui, quand, de quelle étape à quelle
//    étape). Cet écran n'invente aucun statut.
//
// ⚠️ Les défauts constatés AU DÉPÔT sont affichés : l'agent sait ce qu'il ne
//    doit pas être accusé d'avoir causé.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/pressing.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/pressing_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class PressingAtelierPage extends StatefulWidget {
  const PressingAtelierPage({super.key});

  @override
  State<PressingAtelierPage> createState() => _PressingAtelierPageState();
}

class _PressingAtelierPageState extends State<PressingAtelierPage> {
  bool _chargement = true;
  bool _envoi = false;
  String? _erreur;

  List<PressingEtape> _etapes = const <PressingEtape>[];
  List<PressingLigneAtelier> _lignes = const <PressingLigneAtelier>[];
  final Set<String> _selection = <String>{};

  String? _filtreEtape;
  bool _mesVetements = false;

  bool get _peutModifier =>
      PermissionService.instance.peut(
        PageAccess.pressingAtelier,
        ActionAccess.modifier,
      ) ||
      PermissionService.instance.peut(
        PageAccess.pressingDepots,
        ActionAccess.modifier,
      );

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = _lignes.isEmpty;
      _erreur = null;
    });
    try {
      List<PressingEtape> etapes = await PressingService.instance.etapes();
      if (etapes.isEmpty) {
        etapes = await PressingService.instance.amorcerEtapes();
      }
      final List<PressingLigneAtelier> lignes =
          await PressingService.instance.atelier(miennes: _mesVetements);

      if (!mounted) return;
      setState(() {
        _etapes = etapes;
        _lignes = lignes;
        _chargement = false;
        _selection.removeWhere(
          (String id) => !lignes.any((PressingLigneAtelier l) => l.ligneId == id),
        );
      });
    } on PressingException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? AppCouleurs.danger : null,
      ),
    );
  }

  List<PressingLigneAtelier> get _visibles => _filtreEtape == null
      ? _lignes
      : _lignes
          .where((PressingLigneAtelier l) => l.etapeCode == _filtreEtape)
          .toList(growable: false);

  int _compter(String? etape) => etape == null
      ? _lignes.length
      : _lignes.where((PressingLigneAtelier l) => l.etapeCode == etape).length;

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  /// Étape suivante logique : celle qui vient APRÈS l'étape courante.
  PressingEtape? _etapeSuivante(String codeActuel) {
    final List<PressingEtape> actives =
        _etapes.where((PressingEtape e) => e.actif).toList()
          ..sort((PressingEtape a, PressingEtape b) =>
              a.ordre.compareTo(b.ordre));
    for (int i = 0; i < actives.length; i++) {
      if (actives[i].code == codeActuel) {
        return i + 1 < actives.length ? actives[i + 1] : null;
      }
    }
    return actives.isEmpty ? null : actives.first;
  }

  Future<void> _choisirEtape(List<PressingLigneAtelier> cibles) async {
    if (cibles.isEmpty) {
      _message('Sélectionnez au moins un vêtement.', erreur: true);
      return;
    }

    final String? choix = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              title: Text(
                'Faire avancer ${cibles.length} vêtement'
                '${cibles.length > 1 ? 's' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Choisissez la nouvelle étape'),
            ),
            const Divider(height: 1),
            ..._etapes.where((PressingEtape e) => e.actif).map(
                  (PressingEtape e) => ListTile(
                    leading: Icon(
                      e.estFinale
                          ? Icons.check_circle_rounded
                          : Icons.arrow_forward_rounded,
                      color: e.estFinale ? AppCouleurs.succes : null,
                    ),
                    title: Text(e.libelle),
                    subtitle: e.estFinale
                        ? const Text('Rend le vêtement remis­able')
                        : null,
                    onTap: () => Navigator.of(ctx).pop(e.code),
                  ),
                ),
          ],
        ),
      ),
    );

    if (choix == null) return;
    await _avancer(cibles, choix);
  }

  Future<void> _avancer(
    List<PressingLigneAtelier> cibles,
    String etapeCode,
  ) async {
    setState(() => _envoi = true);
    try {
      await PressingService.instance.avancerLot(
        cibles.map((PressingLigneAtelier l) => l.ligneId).toList(),
        etapeCode,
      );
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _selection.clear();
      });
      _message('${cibles.length} vêtement(s) mis à jour.');
      await _charger();
    } on PressingException catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      _message(e.message, erreur: true);
    }
  }

  Future<void> _controle(PressingLigneAtelier ligne) async {
    final TextEditingController note = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Contrôle — ${ligne.titre}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Vérifiez que le vêtement est propre, correctement repassé, '
              'complet et prêt à être remis.',
              style: TextStyle(fontSize: 12.5),
            ),
            if (ligne.aDefauts) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Défaut signalé au dépôt : ${ligne.defauts!.trim()}',
                style: const TextStyle(fontSize: 12, color: AppCouleurs.alerte),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observation (facultatif)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annuler'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(ctx).pop(false),
            icon: const Icon(Icons.replay_rounded),
            label: const Text('À retraiter'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Conforme'),
          ),
        ],
      ),
    );

    final String texte = note.text.trim();
    note.dispose();

    if (ok == null) return;

    setState(() => _envoi = true);
    try {
      await PressingService.instance.controleQualite(
        ligne.ligneId,
        ok,
        note: texte.isEmpty ? null : texte,
      );
      if (!mounted) return;
      setState(() => _envoi = false);
      _message(ok ? 'Vêtement déclaré prêt.' : 'Vêtement à retraiter.');
      await _charger();
    } on PressingException catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atelier & qualité'),
        actions: <Widget>[
          IconButton(
            tooltip: _mesVetements ? 'Voir tout l\'atelier' : 'Mes vêtements',
            onPressed: () {
              setState(() => _mesVetements = !_mesVetements);
              _charger();
            },
            icon: Icon(
              _mesVetements
                  ? Icons.person_rounded
                  : Icons.people_alt_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _envoi ? null : _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _selection.isEmpty || !_peutModifier
          ? null
          : FloatingActionButton.extended(
              onPressed: _envoi
                  ? null
                  : () => _choisirEtape(
                        _visibles
                            .where((PressingLigneAtelier l) =>
                                _selection.contains(l.ligneId))
                            .toList(growable: false),
                      ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text('Avancer (${_selection.length})'),
            ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur(_erreur!)
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: <Widget>[
                      _filtresEtapes(),
                      const SizedBox(height: 10),
                      if (_visibles.isEmpty)
                        _vide()
                      else
                        ..._visibles.map(_carte),
                    ],
                  ),
                ),
    );
  }

  Widget _vueErreur(String message) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const SizedBox(height: 40),
        Icon(Icons.error_outline, size: 48, color: AppCouleurs.danger),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
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

  Widget _filtresEtapes() {
    final List<PressingEtape> actives =
        _etapes.where((PressingEtape e) => e.actif).toList()
          ..sort((PressingEtape a, PressingEtape b) =>
              a.ordre.compareTo(b.ordre));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _mesVetements
              ? 'Mes vêtements à traiter'
              : 'Tous les vêtements en atelier',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('Tout (${_compter(null)})'),
                  selected: _filtreEtape == null,
                  onSelected: (_) => setState(() => _filtreEtape = null),
                ),
              ),
              ...actives.map(
                (PressingEtape e) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${e.libelle} (${_compter(e.code)})'),
                    selected: _filtreEtape == e.code,
                    onSelected: (_) =>
                        setState(() => _filtreEtape = e.code),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vide() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: <Widget>[
          Icon(Icons.check_circle_outline_rounded,
              size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            _filtreEtape == null
                ? 'Aucun vêtement en atelier.\nTout ce qui a été déposé a été '
                    'remis.'
                : 'Aucun vêtement à cette étape.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _carte(PressingLigneAtelier ligne) {
    final bool selectionne = _selection.contains(ligne.ligneId);
    final Color accent = ligne.estPrete
        ? AppCouleurs.succes
        : ligne.enRetard
            ? AppCouleurs.danger
            : AppCouleurs.info;
    final PressingEtape? suivante = _etapeSuivante(ligne.etapeCode);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: selectionne
          ? AppCouleurs.marineClair.withValues(alpha: 0.08)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => setState(() {
          if (selectionne) {
            _selection.remove(ligne.ligneId);
          } else {
            _selection.add(ligne.ligneId);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Checkbox(
                value: selectionne,
                onChanged: (_) => setState(() {
                  if (selectionne) {
                    _selection.remove(ligne.ligneId);
                  } else {
                    _selection.add(ligne.ligneId);
                  }
                }),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '${ligne.position} · ${ligne.titre}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ligne.etapeLibelle ?? ligne.etapeCode,
                            style: TextStyle(
                              fontSize: 10,
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (ligne.details.isNotEmpty)
                      Text(
                        ligne.details,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    Text(
                      <String>[
                        if ((ligne.prestationNom ?? '').isNotEmpty)
                          ligne.prestationNom!,
                        ligne.numero,
                        if ((ligne.clientNom ?? '').isNotEmpty) ligne.clientNom!,
                        'prévu ${formatDate(ligne.datePrevue)}',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (ligne.aDefauts)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.warning_amber_rounded,
                                size: 14, color: AppCouleurs.alerte),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Défaut au dépôt : ${ligne.defauts!.trim()}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppCouleurs.alerte,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (ligne.urgence || ligne.enRetard)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: <Widget>[
                            if (ligne.urgence)
                              _etiquette('Express', AppCouleurs.orange),
                            if (ligne.enRetard) ...<Widget>[
                              const SizedBox(width: 6),
                              _etiquette('En retard', AppCouleurs.danger),
                            ],
                          ],
                        ),
                      ),
                    if (_peutModifier)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          TextButton.icon(
                            onPressed: _envoi ? null : () => _controle(ligne),
                            icon: const Icon(Icons.verified_rounded, size: 16),
                            label: const Text('Contrôle'),
                          ),
                          if (suivante != null)
                            TextButton.icon(
                              onPressed: _envoi
                                  ? null
                                  : () => _avancer(
                                        <PressingLigneAtelier>[ligne],
                                        suivante.code,
                                      ),
                              icon: const Icon(Icons.arrow_forward_rounded,
                                  size: 16),
                              label: Text(suivante.libelle),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _etiquette(String texte, Color couleur) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontSize: 9.5,
          color: couleur,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
