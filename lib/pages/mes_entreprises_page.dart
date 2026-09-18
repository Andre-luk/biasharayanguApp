// lib/pages/mes_entreprises_page.dart
//
// MODULE 15 — ÉCRAN « MES ENTREPRISES » (PACK AVANCÉ MULTI-ENTREPRISES).
//
// Le patron gère ici toutes ses activités : boutique, hôtel, pharmacie…
//   • voir l'entreprise ACTIVE et basculer en un geste ;
//   • créer une entreprise supplémentaire (selon le pack de la grille
//     tarifaire : `groupes_tarifaires.max_espaces`) ;
//   • consulter la place disponible dans le pack.
//
// 🔒 La création est réservée au PROPRIÉTAIRE et limitée par le pack —
// vérifié à TROIS niveaux : cet écran (permissions), le bouton (état du
// pack) et la RPC `rpc_espace_creer` (serveur).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/espace.dart';
import 'package:biashara_yangu/services/espace_service.dart';
import 'package:biashara_yangu/widgets/selecteur_espace.dart';

class MesEntreprisesPage extends StatefulWidget {
  const MesEntreprisesPage({super.key});

  @override
  State<MesEntreprisesPage> createState() => _MesEntreprisesPageState();
}

class _MesEntreprisesPageState extends State<MesEntreprisesPage> {
  EtatEspaces? _etat;
  bool _chargement = true;
  String? _erreur;

  /// Entreprise en cours de bascule (désactive les boutons de sa carte).
  String? _enBascule;

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
      final EtatEspaces etat = await EspaceService.instance.charger();
      if (!mounted) return;
      setState(() {
        _etat = etat;
        _chargement = false;
      });
    } on EspaceServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _basculer(Espace espace) async {
    if (espace.estActif) return;

    setState(() => _enBascule = espace.id);

    try {
      await EspaceService.instance.basculer(espace.id);
      if (!mounted) return;
      setState(() {
        _etat = EspaceService.instance.etat.value;
        _enBascule = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Entreprise « ${espace.nom} » activée.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } on EspaceServiceException catch (e) {
      if (!mounted) return;
      setState(() => _enBascule = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _creerEntreprise() async {
    final EtatEspaces? etat = _etat;
    if (etat == null) return;

    if (!etat.peutCreer) {
      final String message = etat.raison?.message ??
          'La création d\'une entreprise supplémentaire est indisponible.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    final _FormulaireEspace? saisie =
        await showDialog<_FormulaireEspace>(
      context: context,
      builder: (BuildContext context) => const _DialogueCreationEspace(),
    );

    if (saisie == null) return;

    try {
      final Espace espace = await EspaceService.instance.creer(
        nom: saisie.nom,
        type: saisie.type,
      );
      if (!mounted) return;
      setState(() => _etat = EspaceService.instance.etat.value);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Entreprise « ${espace.nom} » créée. Utilisez « Basculer » pour y accéder.',
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } on EspaceServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mes entreprises',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _charger,
        child: _chargement
            ? const Center(child: CircularProgressIndicator())
            : _erreur != null
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: <Widget>[
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.red.shade700),
                      const SizedBox(height: 12),
                      Text(_erreur!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Center(
                        child: FilledButton.icon(
                          onPressed: _charger,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ),
                    ],
                  )
                : _contenu(context, _etat!),
      ),
      floatingActionButton: (_etat?.peutCreer ?? false)
          ? FloatingActionButton.extended(
              onPressed: _creerEntreprise,
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('Nouvelle entreprise'),
            )
          : null,
    );
  }

  Widget _contenu(BuildContext context, EtatEspaces etat) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        _bandeauPack(context, etat),
        const SizedBox(height: 12),
        ...etat.espaces.map((Espace espace) => _carteEspace(context, espace)),
        if (!etat.peutCreer && etat.raison != null) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.info_outline_rounded,
                    size: 17, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    etat.raison!.message,
                    style: TextStyle(
                        fontSize: 12.5, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _bandeauPack(BuildContext context, EtatEspaces etat) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            colorScheme.primary.withValues(alpha: 0.92),
            colorScheme.primary.withValues(alpha: 0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.workspace_premium_rounded,
              color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  etat.packMulti
                      ? 'Pack multi-entreprises'
                      : 'Pack standard (1 entreprise)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${etat.espaces.length} entreprise(s) sur ${etat.maxEspaces} autorisée(s)'
                  '${etat.packMulti ? '  •  ${etat.placesRestantes} place(s) restante(s)' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteEspace(BuildContext context, Espace espace) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool enCours = _enBascule == espace.id;

    return Card(
      elevation: espace.estActif ? 3 : 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: espace.estActif
            ? BorderSide(color: colorScheme.primary, width: 1.6)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 22,
              backgroundColor: espace.estActif
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              child: Icon(
                iconePourTypeEspace(espace.type),
                size: 20,
                color: espace.estActif
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          espace.nom,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (espace.estActif) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    espace.type.libelle,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            if (!espace.estActif)
              FilledButton.tonal(
                onPressed: enCours ? null : () => _basculer(espace),
                child: enCours
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Basculer'),
              )
            else
              Icon(Icons.check_circle_rounded, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FORMULAIRE DE CRÉATION
// ---------------------------------------------------------------------------

class _FormulaireEspace {
  const _FormulaireEspace({required this.nom, required this.type});

  final String nom;
  final TypeEspace type;
}

class _DialogueCreationEspace extends StatefulWidget {
  const _DialogueCreationEspace();

  @override
  State<_DialogueCreationEspace> createState() =>
      _DialogueCreationEspaceState();
}

class _DialogueCreationEspaceState extends State<_DialogueCreationEspace> {
  final TextEditingController _nom = TextEditingController();
  TypeEspace _type = TypeEspace.boutique;
  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  void _valider() {
    final String nom = _nom.text.trim();
    if (nom.length < 2) {
      setState(() => _erreur = 'Donnez un nom (2 caractères minimum).');
      return;
    }

    Navigator.of(context).pop(_FormulaireEspace(nom: nom, type: _type));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle entreprise'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Ajoutez une activité à votre compte : elle aura ses propres '
              'ventes, son stock et ses finances.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nom,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nom de l\'entreprise',
                hintText: 'Ex. : Hôtel Royal, Pharmacie Centrale…',
                errorText: _erreur,
                prefixIcon: const Icon(Icons.storefront_rounded),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _erreur = null),
              onSubmitted: (_) => _valider(),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TypeEspace.values
                  .map(
                    (TypeEspace type) => ChoiceChip(
                      avatar: Icon(iconePourTypeEspace(type), size: 16),
                      label: Text(type.libelle),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _valider,
          icon: const Icon(Icons.add_business_rounded),
          label: const Text('Créer'),
        ),
      ],
    );
  }
}
