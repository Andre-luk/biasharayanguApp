// lib/pages/admin_moderation_page.dart
//
// 🛡️ MODULE 20 — MODÉRATION DU CATALOGUE PUBLIC (administration plateforme).
//
// Manque identifié par l'audit final : aucune RPC ni écran ne permettait de
// retirer un article illicite, dangereux ou trompeur du marketplace public.
// Cet écran donne à la plateforme une vue sur TOUT le catalogue publié, avec
// une seule décision : retirer du public, ou remettre.
//
// Exigences de transparence tenues par l'architecture :
//   • un RETRAIT exige un motif (contrôlé côté serveur ET côté écran) ;
//   • le motif est journalisé dans l'audit et conservé sur la publication,
//     donc lisible par le commerçant : il comprend la décision ;
//   • rien n'est supprimé : la modération n'efface jamais un article.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/admin_plateforme.dart';
import 'package:biashara_yangu/services/admin_plateforme_service.dart';
import 'package:biashara_yangu/ui/mise_en_page_adaptative.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/photo_biashara.dart';

const List<(String, String)> _filtres = <(String, String)>[
  ('toutes', 'Toutes'),
  ('publiees', 'Publiées'),
  ('retirees', 'Retirées'),
  ('indisponibles', 'Indisponibles'),
];

class AdminModerationPage extends StatefulWidget {
  const AdminModerationPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<AdminModerationPage> createState() => _AdminModerationPageState();
}

class _AdminModerationPageState extends State<AdminModerationPage> {
  final TextEditingController _recherche = TextEditingController();

  List<PublicationAdmin> _publications = const <PublicationAdmin>[];
  ResumePublications _resume = ResumePublications.vide;

  bool _chargement = true;
  bool _enCours = false;
  String? _erreur;
  String _filtre = 'toutes';
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
      final (List<PublicationAdmin> publications, ResumePublications resume) =
          await AdminPlateformeService.instance.listerPublications(
        recherche: _recherche.text,
        filtre: _filtre,
      );
      if (!mounted) return;
      setState(() {
        _publications = publications;
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
  // MODÉRATION
  // ---------------------------------------------------------------------------

  Future<void> _retirer(PublicationAdmin publication) async {
    final String? motif = await _demanderMotif(
      titre: 'Retirer du catalogue public ?',
      message:
          '« ${publication.nom} » (${publication.boutique ?? 'boutique'}) ne sera '
          'plus visible des clients. L\'article n\'est PAS supprimé : le '
          'commerçant le retrouve dans ses publications, avec votre motif.',
      libelleAction: 'Retirer du catalogue',
    );
    if (motif == null) return;
    await _appliquer(publication, publie: false, motif: motif);
  }

  Future<void> _republier(PublicationAdmin publication) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Remettre dans le catalogue ?'),
        content: Text(
          '« ${publication.nom} » redeviendra visible des clients de Biashara.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remettre en ligne'),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    await _appliquer(publication, publie: true, motif: null);
  }

  Future<void> _appliquer(
    PublicationAdmin publication, {
    required bool publie,
    String? motif,
  }) async {
    setState(() => _enCours = true);
    try {
      await AdminPlateformeService.instance.modererPublication(
        publicationId: publication.publicationId,
        publie: publie,
        motif: motif,
      );
      if (!mounted) return;
      _message(publie
          ? 'Article remis dans le catalogue public.'
          : 'Article retiré du catalogue. Le motif est enregistré.');
      await _charger();
    } on AdminPlateformeException catch (e) {
      if (!mounted) return;
      _message(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  /// Motif obligatoire : renvoie `null` si l'administrateur annule.
  Future<String?> _demanderMotif({
    required String titre,
    required String message,
    required String libelleAction,
  }) async {
    final TextEditingController motif = TextEditingController();
    String? erreurMotif;

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setEtat) => AlertDialog(
          title: Text(titre),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 16),
              TextField(
                controller: motif,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Motif (obligatoire)',
                  hintText: 'Ex. : prix trompeur, produit interdit, photo non conforme',
                  errorText: erreurMotif,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Le motif est visible par le commerçant et conservé dans le '
                'journal d\'audit.',
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
                if (motif.text.trim().length < 6) {
                  setEtat(() => erreurMotif =
                      'Le motif doit être explicite (6 caractères minimum).');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(libelleAction),
            ),
          ],
        ),
      ),
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
          _encartPrincipe(),
          const SizedBox(height: 12),
          TextField(
            controller: _recherche,
            textInputAction: TextInputAction.search,
            onChanged: _rechercherAvecDelai,
            onSubmitted: (_) => _charger(),
            decoration: InputDecoration(
              hintText: 'Rechercher un article, une catégorie, une boutique…',
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
          ),
          const SizedBox(height: 12),
          Wrap(
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
          ),
          const SizedBox(height: 14),
          if (_chargement)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: ModernLoader(taille: 46)),
            )
          else if (_erreur != null)
            _etatErreur()
          else ...<Widget>[
            _resumeCatalogue(),
            const SizedBox(height: 14),
            if (_publications.isEmpty) _etatVide() else ..._cartes(),
          ],
        ],
      ),
    );

    if (!widget.showAppBar) return contenu;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modération du catalogue'),
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

  Widget _encartPrincipe() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppCouleurs.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppCouleurs.info.withValues(alpha: 0.2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.gavel_rounded, size: 18, color: AppCouleurs.info),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Un retrait n\'efface rien : l\'article reste dans la boutique, '
              'accompagné du motif. Le commerçant peut corriger puis demander '
              'sa remise en ligne.',
              style: TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumeCatalogue() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _compteur('Publications', _resume.publications,
              Icons.inventory_2_rounded, AppCouleurs.marine),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _compteur('Publiées', _resume.publiees,
              Icons.visibility_rounded, AppCouleurs.succes),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _compteur('Retirées', _resume.retirees,
              Icons.visibility_off_rounded, AppCouleurs.danger),
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
                fontSize: 20, fontWeight: FontWeight.w800, color: couleur),
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
      for (final PublicationAdmin publication in _publications) ...<Widget>[
        _carte(publication),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _carte(PublicationAdmin publication) {
    final bool retiree = !publication.publie;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (retiree ? AppCouleurs.danger : AppCouleurs.succes)
              .withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PhotoBiashara(
            url: publication.photo,
            largeur: 64,
            hauteur: 64,
            rayon: 14,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  publication.nom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatMontant(publication.prix)}'
                  '${publication.unite == null ? '' : ' / ${publication.unite}'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  <String>[
                    if ((publication.boutique ?? '').isNotEmpty)
                      publication.boutique!,
                    if ((publication.ville ?? '').isNotEmpty) publication.ville!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    _badge(
                      publication.publie ? 'Publiée' : 'Retirée',
                      publication.publie
                          ? AppCouleurs.succes
                          : AppCouleurs.danger,
                    ),
                    if (!publication.disponible)
                      _badge('Indisponible', AppCouleurs.alerte),
                    if (publication.retireParPlateforme)
                      _badge('Retrait plateforme', AppCouleurs.marineClair),
                  ],
                ),
                if (publication.dejaModere &&
                    (publication.moderationNote ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppCouleurs.alerte.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Motif : ${publication.moderationNote}',
                      style: const TextStyle(fontSize: 12, height: 1.3),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: publication.publie
                      ? OutlinedButton.icon(
                          onPressed:
                              _enCours ? null : () => _retirer(publication),
                          icon: const Icon(Icons.visibility_off_rounded,
                              size: 18),
                          label: const Text('Retirer du catalogue'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppCouleurs.danger,
                          ),
                        )
                      : FilledButton.icon(
                          onPressed:
                              _enCours ? null : () => _republier(publication),
                          icon: const Icon(Icons.visibility_rounded, size: 18),
                          label: const Text('Remettre en ligne'),
                        ),
                ),
              ],
            ),
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
          const Icon(Icons.inventory_2_rounded,
              size: 44, color: AppCouleurs.marineClair),
          const SizedBox(height: 12),
          Text(
            _recherche.text.trim().isEmpty && _filtre == 'toutes'
                ? 'Aucune publication pour le moment.\n'
                    'Le catalogue public se remplit dès que les commerçants '
                    'publient leurs articles.'
                : 'Aucune publication ne correspond à cette recherche ou à ce filtre.',
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
          const Icon(Icons.cloud_off_rounded,
              size: 42, color: AppCouleurs.alerte),
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
