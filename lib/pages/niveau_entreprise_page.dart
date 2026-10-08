// lib/pages/niveau_entreprise_page.dart
//
// 🧩 CORRECTIF 65 — NIVEAU D'ABONNEMENT D'UNE ENTREPRISE.
//
// Le patron NÉGOCIE le prix avec chaque entreprise ; les fonctionnalités
// peuvent l'être aussi. Cet écran permet donc :
//   • de choisir un niveau du catalogue (ou aucun : celui du pack tarifaire) ;
//   • de fixer, si besoin, une liste de fonctionnalités SUR MESURE qui
//     remplace celle du niveau.
//
// ⚠️ Rien n'est appliqué avant l'enregistrement. Et rappel de la règle d'or :
// aucune fonctionnalité n'est masquée tant qu'aucune restriction n'existe —
// c'est la colonne « réellement appliquées » affichée en tête.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/fonctionnalites.dart';
import 'package:biashara_yangu/models/niveau_abonnement.dart';
import 'package:biashara_yangu/services/abonnement_niveaux_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class NiveauEntreprisePage extends StatefulWidget {
  const NiveauEntreprisePage({
    super.key,
    required this.entrepriseId,
    this.nomEntreprise,
  });

  final String entrepriseId;
  final String? nomEntreprise;

  @override
  State<NiveauEntreprisePage> createState() => _NiveauEntreprisePageState();
}

class _NiveauEntreprisePageState extends State<NiveauEntreprisePage> {
  final NiveauxAbonnementService _service = NiveauxAbonnementService.instance;

  List<NiveauAbonnement> _niveaux = <NiveauAbonnement>[];
  NiveauEntreprise _etat = const NiveauEntreprise();

  /// Niveau choisi. `null` = aucun niveau imposé (celui du pack tarifaire).
  String? _niveauChoisi;

  /// Fonctionnalités sur mesure. Vide = suivre le niveau.
  Set<String> _surMesure = <String>{};
  bool _personnaliser = false;

  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);

    try {
      final List<NiveauAbonnement> niveaux = await _service.lister();
      final NiveauEntreprise etat =
          await _service.lireNiveauEntreprise(widget.entrepriseId);

      if (!mounted) return;
      setState(() {
        _niveaux = niveaux.where((NiveauAbonnement n) => n.actif).toList();
        _etat = etat;
        _niveauChoisi = etat.niveau;
        _surMesure = Set<String>.from(etat.fonctionnalites);
        _personnaliser = etat.negocie;
        _chargement = false;
        _erreur = null;
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

  Future<void> _enregistrer() async {
    if (_personnaliser && _surMesure.isEmpty) {
      _message(
        'Choisissez au moins une fonctionnalité, ou décochez « sur mesure ».',
        erreur: true,
      );
      return;
    }

    setState(() => _enregistrement = true);

    try {
      await _service.affecterEntreprise(
        entrepriseId: widget.entrepriseId,
        niveau: _niveauChoisi,
        //  Une liste vide ANNULE la négociation : l'entreprise revient sur son
        //  niveau. C'est ce que fait le serveur (voir correctif 65).
        fonctionnalites: _personnaliser ? _surMesure : const <String>{},
        note: _personnaliser
            ? 'Fonctionnalités négociées'
            : 'Niveau appliqué',
      );

      if (!mounted) return;
      _message('Niveau d\'abonnement enregistré.');
      context.pop(true);
    } on NiveauxAbonnementException catch (e) {
      if (!mounted) return;
      _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool autorise = PermissionService.instance.estSuperAdmin ||
        PermissionService.instance.estPlateforme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Niveau d\'abonnement',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreur!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: <Widget>[
                    if (widget.nomEntreprise != null)
                      Text(
                        widget.nomEntreprise!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    const SizedBox(height: 12),
                    _carteEtatActuel(),
                    const SizedBox(height: 18),
                    _sectionNiveau(),
                    const SizedBox(height: 18),
                    _sectionSurMesure(),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: (!autorise || _enregistrement)
                            ? null
                            : _enregistrer,
                        icon: _enregistrement
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_rounded),
                        label: const Text('Enregistrer'),
                      ),
                    ),
                    if (!autorise) ...<Widget>[
                      const SizedBox(height: 10),
                      const Text(
                        'Seuls la finance, le gestionnaire des comptes ou le '
                        'Super Admin peuvent modifier le niveau d\'une '
                        'entreprise.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _carteEtatActuel() {
    final ThemeData theme = Theme.of(context);
    final Set<String>? effectifs = _etat.modulesEffectifs;

    final String resume;
    if (_etat.sansRestriction) {
      resume = 'Aucune restriction : TOUTES les fonctionnalités sont visibles.';
    } else if (effectifs!.contains(Fonctionnalites.joker)) {
      resume = 'Toutes les fonctionnalités de l\'activité.';
    } else {
      resume = effectifs
          .map((String code) => Fonctionnalites.libelleDe(code))
          .join(' · ');
    }

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
          Text(
            'RÉELLEMENT APPLIQUÉ AUJOURD\'HUI',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(resume, style: const TextStyle(fontSize: 13, height: 1.35)),
          const SizedBox(height: 8),
          Text(
            _etat.niveau == null
                ? 'Aucun niveau imposé : celui du pack tarifaire s\'applique.'
                : 'Niveau imposé : ${_etat.niveau}',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_etat.negocie)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Fonctionnalités NÉGOCIÉES pour cette entreprise '
                '(${_etat.fonctionnalites.length}) — elles remplacent celles '
                'du niveau.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionNiveau() {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _titreSection('Niveau du catalogue', Icons.workspace_premium_outlined),
        //  Volontairement des `ListTile` plutôt que des boutons radio : les
        //  boutons radio de Flutter sont en cours de dépréciation.
        ListTile(
          leading: Icon(_niveauChoisi == null
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded),
          onTap: () => setState(() => _niveauChoisi = null),
          title: const Text('Aucun niveau imposé'),
          subtitle: const Text('Le pack tarifaire décide (comportement actuel).'),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        for (final NiveauAbonnement n in _niveaux)
          ListTile(
            leading: Icon(_niveauChoisi == n.code
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded),
            onTap: () => setState(() => _niveauChoisi = n.code),
            title: Text(n.libelle),
            subtitle: Text(
              '${n.prixMensuelConseille == null ? 'prix conseillé non renseigné' : '${formatMontant(n.prixMensuelConseille!)} conseillé'}'
              ' · ${n.toutesLesFonctionnalites ? 'toutes les fonctionnalités' : '${n.nbFonctionnalites} fonctionnalité${n.nbFonctionnalites > 1 ? 's' : ''}'}',
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        const SizedBox(height: 6),
        Text(
          'Le prix réel reste celui négocié pour cette entreprise : le niveau '
          'ne fixe que les FONCTIONNALITÉS.',
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _sectionSurMesure() {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _titreSection('Fonctionnalités sur mesure', Icons.tune_rounded),
        SwitchListTile(
          value: _personnaliser,
          onChanged: (bool v) => setState(() => _personnaliser = v),
          title: const Text('Négocier une liste particulière'),
          subtitle: const Text(
            'Remplace la liste du niveau. Désactivé, l\'entreprise suit '
            'simplement son niveau.',
          ),
          contentPadding: EdgeInsets.zero,
        ),
        if (_personnaliser) ...<Widget>[
          const SizedBox(height: 4),
          for (final String famille in Fonctionnalites.familles) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              famille.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final Fonctionnalite f in Fonctionnalites.deLaFamille(famille))
              CheckboxListTile(
                value: _surMesure.contains(f.code),
                onChanged: (bool? v) {
                  setState(() {
                    if (v == true) {
                      _surMesure.add(f.code);
                    } else {
                      _surMesure.remove(f.code);
                    }
                  });
                },
                title: Text(f.libelle),
                subtitle: Text(f.code, style: const TextStyle(fontSize: 11)),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
          const SizedBox(height: 8),
          Text(
            '${_surMesure.length} fonctionnalité'
            '${_surMesure.length > 1 ? 's' : ''} sélectionnée'
            '${_surMesure.length > 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _titreSection(String titre, IconData icone) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icone, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          titre,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
