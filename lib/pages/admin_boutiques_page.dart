// lib/pages/admin_boutiques_page.dart
//
// 🛡️ MODULE 20 — PARC DES BOUTIQUES (administration plateforme).
//
// Avant l'audit final, la plateforme ne pouvait agir sur une boutique qu'en
// passant par la fiche de son entreprise : impossible de voir le parc entier,
// impossible de retirer UNE boutique du catalogue public sans toucher à
// l'entreprise. Cet écran comble ce manque.
//
// Deux actions seulement, volontairement :
//   • activer / désactiver la boutique (accès du commerçant) ;
//   • afficher / retirer du catalogue public.
// La désactivation retire automatiquement du catalogue (règle serveur) : aucun
// état incohérent n'est possible depuis l'interface.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/admin_plateforme.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/admin_plateforme_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/ui/mise_en_page_adaptative.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';

/// Filtres proposés à l'administrateur (codes envoyés au serveur).
const List<(String, String)> _filtres = <(String, String)>[
  ('tous', 'Toutes'),
  ('actifs', 'Actives'),
  ('inactifs', 'Désactivées'),
  ('visibles', 'Dans le catalogue'),
  ('non_visibles', 'Hors catalogue'),
];

class AdminBoutiquesPage extends StatefulWidget {
  const AdminBoutiquesPage({super.key, this.showAppBar = true});

  /// `false` lorsque l'écran est affiché dans un onglet (l'AppBar est fournie
  /// par la page conteneur) — convention des écrans d'administration.
  final bool showAppBar;

  @override
  State<AdminBoutiquesPage> createState() => _AdminBoutiquesPageState();
}

class _AdminBoutiquesPageState extends State<AdminBoutiquesPage> {
  final TextEditingController _recherche = TextEditingController();

  List<EspaceAdmin> _espaces = const <EspaceAdmin>[];
  ResumeParcEspaces _resume = ResumeParcEspaces.vide;

  bool _chargement = true;
  bool _enCours = false;
  String? _erreur;
  String _filtre = 'tous';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final (List<EspaceAdmin> espaces, ResumeParcEspaces resume) =
          await AdminPlateformeService.instance.listerEspaces(
        recherche: _recherche.text,
        filtre: _filtre,
      );
      if (!mounted) return;
      setState(() {
        _espaces = espaces;
        _resume = resume;
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

  void _rechercherAvecDelai(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), _charger);
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _changerStatut(EspaceAdmin espace, {bool? actif, bool? visible}) async {
    final bool desactivation = actif == false;
    final bool retrait = visible == false;

    final String titre = desactivation
        ? 'Désactiver cette boutique ?'
        : retrait
            ? 'Retirer du catalogue public ?'
            : actif == true
                ? 'Réactiver cette boutique ?'
                : 'Afficher dans le catalogue public ?';

    final String message = desactivation
        ? 'La boutique « ${espace.nom} » ne pourra plus être utilisée par son '
            'équipe et disparaîtra du catalogue public. Les ventes, le stock et '
            'les historiques sont conservés : l\'opération est réversible.'
        : retrait
            ? 'La boutique « ${espace.nom} » et ses articles ne seront plus '
                'visibles des clients. Aucune donnée n\'est supprimée.'
            : actif == true
                ? 'La boutique « ${espace.nom} » redeviendra accessible à son '
                    'équipe.'
                : 'La boutique « ${espace.nom} » réapparaîtra dans le catalogue '
                    'public si le commerçant a déjà publié sa vitrine.';

    final String? motif = await _demanderMotif(
      titre: titre,
      message: message,
      libelleAction: desactivation || retrait ? 'Confirmer' : 'Continuer',
      motifObligatoire: desactivation,
    );
    if (motif == null) return; // annulé

    setState(() => _enCours = true);
    try {
      await AdminPlateformeService.instance.changerStatutEspace(
        espaceId: espace.espaceId,
        actif: actif,
        visible: visible,
        motif: motif,
      );
      if (!mounted) return;
      _message('Boutique mise à jour. Les données sont intactes.');
      await _charger();
    } on AdminPlateformeException catch (e) {
      if (!mounted) return;
      _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  /// Demande un motif à l'administrateur.
  ///
  /// Renvoie `null` si l'opération est annulée, sinon le motif saisi (qui peut
  /// être vide lorsque [motifObligatoire] est faux).
  Future<String?> _demanderMotif({
    required String titre,
    required String message,
    required String libelleAction,
    bool motifObligatoire = false,
  }) async {
    final TextEditingController motif = TextEditingController();
    String? erreurMotif;

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setEtat) {
            return AlertDialog(
              title: Text(titre),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  TextField(
                    controller: motif,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: motifObligatoire
                          ? 'Motif (obligatoire)'
                          : 'Motif (facultatif)',
                      hintText: 'Ex. : contenu illicite signalé par un client',
                      errorText: erreurMotif,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Le motif est enregistré dans le journal d\'audit.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () {
                    if (motifObligatoire && motif.text.trim().length < 4) {
                      setEtat(() => erreurMotif =
                          'Indiquez un motif (4 caractères minimum).');
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: Text(libelleAction),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirme != true) {
      motif.dispose();
      return null;
    }
    final String valeur = motif.text.trim();
    motif.dispose();
    return valeur;
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? AppCouleurs.danger : AppCouleurs.succes,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final double marge = MiseEnPageAdaptative.margeLaterale(
      MediaQuery.sizeOf(context).width,
    );

    final Widget contenu = RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: EdgeInsets.fromLTRB(marge, 12, marge, 32),
        children: <Widget>[
          _barreRecherche(),
          const SizedBox(height: 12),
          _pucesFiltres(),
          const SizedBox(height: 14),
          if (_chargement)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: ModernLoader(taille: 46)),
            )
          else if (_erreur != null)
            _etatErreur()
          else ...<Widget>[
            _resumeParc(),
            const SizedBox(height: 14),
            if (_espaces.isEmpty) _etatVide() else ..._cartes(),
          ],
        ],
      ),
    );

    if (!widget.showAppBar) return contenu;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Boutiques & espaces'),
        actions: <Widget>[
          IconButton(
            onPressed: _enCours ? null : _charger,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: contenu,
    );
  }

  Widget _barreRecherche() {
    return TextField(
      controller: _recherche,
      textInputAction: TextInputAction.search,
      onChanged: _rechercherAvecDelai,
      onSubmitted: (_) => _charger(),
      decoration: InputDecoration(
        hintText: 'Rechercher une boutique, une entreprise, une ville…',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _recherche.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Effacer',
                onPressed: () {
                  _recherche.clear();
                  _charger();
                },
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _pucesFiltres() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final (String code, String libelle) in _filtres)
          ChoiceChip(
            label: Text(libelle),
            selected: _filtre == code,
            onSelected: (_) {
              if (_filtre == code) return;
              setState(() => _filtre = code);
              _charger();
            },
          ),
      ],
    );
  }

  Widget _resumeParc() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _compteur(
            'Boutiques',
            _resume.espaces,
            Icons.storefront_rounded,
            AppCouleurs.marine,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _compteur(
            'Actives',
            _resume.actifs,
            Icons.check_circle_rounded,
            AppCouleurs.succes,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _compteur(
            'Dans le catalogue',
            _resume.visibles,
            Icons.public_rounded,
            AppCouleurs.orange,
          ),
        ),
      ],
    );
  }

  Widget _compteur(String libelle, int valeur, IconData icone, Color couleur) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: couleur.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, size: 20, color: couleur),
          const SizedBox(height: 8),
          Text(
            '$valeur',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: couleur,
            ),
          ),
          Text(
            libelle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, height: 1.25),
          ),
        ],
      ),
    );
  }

  List<Widget> _cartes() {
    return <Widget>[
      for (final EspaceAdmin espace in _espaces) ...<Widget>[
        _carte(espace),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _carte(EspaceAdmin espace) {
    final Color couleurEtat = !espace.actif
        ? AppCouleurs.danger
        : espace.visibleEffectivement
            ? AppCouleurs.succes
            : AppCouleurs.alerte;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: couleurEtat.withValues(alpha: 0.22)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppCouleurs.marine.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: couleurEtat.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.storefront_rounded,
                    color: couleurEtat, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      espace.nom,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${espace.typeLisible}'
                      '${(espace.entreprise ?? '').isEmpty ? '' : ' · ${espace.entreprise}'}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      espace.localisationCourte,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (PermissionService.instance.peutVoir(PageAccess.boutiques))
                PopupMenuButton<String>(
                  enabled: !_enCours,
                  tooltip: 'Actions',
                  onSelected: (String choix) {
                    switch (choix) {
                      case 'desactiver':
                        _changerStatut(espace, actif: false);
                      case 'activer':
                        _changerStatut(espace, actif: true);
                      case 'masquer':
                        _changerStatut(espace, visible: false);
                      case 'afficher':
                        _changerStatut(espace, visible: true);
                    }
                  },
                  itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                    if (espace.actif)
                      const PopupMenuItem<String>(
                        value: 'desactiver',
                        child: Text('Désactiver la boutique'),
                      )
                    else
                      const PopupMenuItem<String>(
                        value: 'activer',
                        child: Text('Réactiver la boutique'),
                      ),
                    if (espace.visiblePubliquement)
                      const PopupMenuItem<String>(
                        value: 'masquer',
                        child: Text('Retirer du catalogue'),
                      )
                    else
                      const PopupMenuItem<String>(
                        value: 'afficher',
                        child: Text('Afficher au catalogue'),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              _badge(
                espace.actif ? 'Active' : 'Désactivée',
                espace.actif ? AppCouleurs.succes : AppCouleurs.danger,
              ),
              _badge(
                espace.visiblePubliquement
                    ? 'Vitrine publiée'
                    : 'Vitrine non publiée',
                espace.visiblePubliquement
                    ? AppCouleurs.info
                    : AppCouleurs.alerte,
              ),
              _badge(
                espace.localisationVerifiee
                    ? 'Position confirmée'
                    : 'Position à confirmer',
                espace.localisationVerifiee
                    ? AppCouleurs.succes
                    : AppCouleurs.alerte,
              ),
              _badge(
                '${espace.nbProduitsPublies}/${espace.nbProduits} articles publiés',
                AppCouleurs.marineClair,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Pourquoi la boutique n'est pas visible : l'administrateur doit
          // pouvoir répondre au téléphone sans ouvrir cinq écrans.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                espace.visibleEffectivement
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 16,
                color: couleurEtat,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  espace.raisonInvisibilite,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: couleurEtat,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String texte, Color couleur) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: couleur,
        ),
      ),
    );
  }

  Widget _etatVide() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: <Widget>[
          const Icon(Icons.store_mall_directory_rounded,
              size: 44, color: AppCouleurs.marineClair),
          const SizedBox(height: 12),
          Text(
            _recherche.text.trim().isEmpty && _filtre == 'tous'
                ? 'Aucune boutique sur la plateforme pour le moment.\n'
                    'Les boutiques apparaissent ici dès qu\'une entreprise est créée.'
                : 'Aucune boutique ne correspond à cette recherche ou à ce filtre.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _etatErreur() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 42, color: AppCouleurs.alerte),
          const SizedBox(height: 12),
          Text(
            _erreur ?? 'Chargement impossible.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
