// lib/pages/mes_publications_page.dart
//
// 🛒 MODULE 19 — « MES PUBLICATIONS » (CE QUI EST VISIBLE SUR BIASHARA).
//
// Le commerçant décide, article par article, de ce qui apparaît dans le
// catalogue public. Il voit pour chacun un indicateur de COMPLÉTUDE : la
// visibilité ne dépend pas du budget, mais de la qualité des informations
// fournies (photo, texte, disponibilité, position de la boutique).
//
// ⚠️ Les prix d'achat, les marges et le stock exact ne sont JAMAIS publiés.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/publication_produit.dart';
import 'package:biashara_yangu/services/image_service.dart';
import 'package:biashara_yangu/services/vitrine_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/photo_biashara.dart';

class MesPublicationsPage extends StatefulWidget {
  const MesPublicationsPage({super.key, this.espaceId});

  /// 🧑‍🌾 MODULE 21 ter — boutique ciblée (agent terrain) ; `null` = boutique
  /// active du compte connecté.
  final String? espaceId;

  @override
  State<MesPublicationsPage> createState() => _MesPublicationsPageState();
}

class _MesPublicationsPageState extends State<MesPublicationsPage> {
  final VitrineService _vitrine = VitrineService.instance;
  final TextEditingController _recherche = TextEditingController();

  EtatPublications _etat = const EtatPublications();
  FiltrePublications _filtre = FiltrePublications.tous;
  bool _chargement = true;
  bool _traitement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final EtatPublications etat = await _vitrine.publications(
        espaceId: widget.espaceId,
        recherche: _recherche.text.trim().isEmpty ? null : _recherche.text.trim(),
        filtre: _filtre,
      );
      if (!mounted) return;
      setState(() {
        _etat = etat;
        _chargement = false;
      });
    } on VitrineException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  /// Bascule la publication d'un article.
  Future<void> _basculer(PublicationProduit article, bool publie) async {
    setState(() => _traitement = true);
    try {
      await _vitrine.enregistrerPublication(
        produitId: article.produitId,
        publie: publie,
        prixPublic: article.prixPublic,
        unite: article.unite,
        description: article.descriptionCourte,
        photo: article.photo,
        motsCles: article.motsCles,
        disponible: article.disponible,
      );
      _message(publie
          ? '« ${article.nom} » est maintenant visible sur Biashara.'
          : '« ${article.nom} » a été retiré du catalogue public.');
      await _charger();
    } on VitrineException catch (e) {
      _message(e.message);
    } finally {
      if (mounted) setState(() => _traitement = false);
    }
  }

  /// Publie / dépublie tous les articles affichés (opération en lot).
  Future<void> _lot({required bool publie}) async {
    final List<PublicationProduit> cibles = _etat.articles;
    if (cibles.isEmpty) return;

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(publie ? 'Tout publier ?' : 'Tout retirer ?'),
        content: Text(
          publie
              ? '${cibles.length} article(s) deviendront visibles dans le '
                  'catalogue Biashara.'
              : '${cibles.length} article(s) seront retirés du catalogue '
                  'Biashara (vos articles restent intacts dans votre '
                  'boutique).',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    setState(() => _traitement = true);
    try {
      final resultat = await _vitrine.enregistrerPublicationLot(
        produits: cibles
            .map((PublicationProduit p) => <String, dynamic>{
                  'produit_id': p.produitId,
                })
            .toList(growable: false),
        publie: publie,
      );

      _message('${resultat.nbTraites} article(s) mis à jour.'
          '${resultat.erreurs.isEmpty ? '' : ' ${resultat.erreurs.length} en '
              'échec.'}');
      await _charger();
    } on VitrineException catch (e) {
      _message(e.message);
    } finally {
      if (mounted) setState(() => _traitement = false);
    }
  }

  /// Fiche de réglage d'une publication (prix public, texte, photo…).
  Future<void> _modifier(PublicationProduit article) async {
    final _ReglagePublication? reglage =
        await showModalBottomSheet<_ReglagePublication>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => _FeuilleReglage(article: article),
    );
    if (reglage == null || !mounted) return;

    setState(() => _traitement = true);
    try {
      await _vitrine.enregistrerPublication(
        produitId: article.produitId,
        publie: reglage.publie,
        prixPublic: reglage.prixPublic,
        unite: reglage.unite,
        description: reglage.description,
        photo: reglage.photo,
        motsCles: reglage.motsCles,
        disponible: reglage.disponible,
      );
      _message('Publication mise à jour.');
      await _charger();
    } on VitrineException catch (e) {
      _message(e.message);
    } finally {
      if (mounted) setState(() => _traitement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes publications'),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: 'Actions groupées',
            onSelected: (String valeur) =>
                _lot(publie: valeur == 'publier'),
            itemBuilder: (BuildContext ctx) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'publier',
                child: Text('Publier tout ce qui est affiché'),
              ),
              PopupMenuItem<String>(
                value: 'retirer',
                child: Text('Retirer tout ce qui est affiché'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Recharger',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_traitement) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: TextField(
              controller: _recherche,
              onSubmitted: (String _) => _charger(),
              decoration: const InputDecoration(
                hintText: 'Rechercher un article…',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: <Widget>[
                for (final FiltrePublications filtre
                    in FiltrePublications.values) ...<Widget>[
                  ChoiceChip(
                    label: Text(filtre.libelle),
                    selected: _filtre == filtre,
                    onSelected: (_) {
                      setState(() => _filtre = filtre);
                      _charger();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(child: _corps(theme)),
        ],
      ),
    );
  }

  Widget _corps(ThemeData theme) {
    if (_chargement) return const Center(child: ModernLoader(taille: 46));

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.wifi_off_rounded,
                  size: 40, color: AppCouleurs.alerte),
              const SizedBox(height: 12),
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _charger,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: <Widget>[
          _bandeau(theme),
          const SizedBox(height: 12),
          if (_etat.articles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: <Widget>[
                  const Icon(Icons.inventory_2_outlined,
                      size: 42, color: AppCouleurs.orange),
                  const SizedBox(height: 10),
                  Text(
                    _recherche.text.trim().isEmpty
                        ? 'Aucun article dans votre catalogue.'
                        : 'Aucun article ne correspond à cette recherche.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          else
            for (final PublicationProduit article in _etat.articles)
              _ligne(theme, article),
        ],
      ),
    );
  }

  Widget _bandeau(ThemeData theme) {
    final bool aucunPublie = _etat.nbPublies == 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (aucunPublie ? AppCouleurs.alerte : AppCouleurs.succes)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            aucunPublie ? Icons.info_outline_rounded : Icons.public_rounded,
            color: aucunPublie ? AppCouleurs.alerte : AppCouleurs.succes,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${_etat.nbPublies} article'
                  '${_etat.nbPublies > 1 ? 's' : ''} visible'
                  '${_etat.nbPublies > 1 ? 's' : ''} sur ${_etat.total}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  aucunPublie
                      ? 'Publiez au moins un article pour être trouvé par les '
                          'clients qui cherchent vos produits autour d\'eux.'
                      : 'Ces articles apparaissent dans les recherches '
                          'publiques, avec leur prix, votre boutique et la '
                          'distance. Vos prix d\'achat et votre stock ne sont '
                          'jamais publiés.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligne(ThemeData theme, PublicationProduit article) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _modifier(article),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PhotoBiashara(
                url: article.photo,
                largeur: 54,
                hauteur: 54,
                rayon: 12,
                icone: Icons.inventory_2_rounded,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      article.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatMontant(article.prixAffiche)} / ${article.unite}'
                      '${article.prixPersonnalise ? '  (prix public)' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppCouleurs.orangeFonce,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        _puce(
                          theme,
                          article.publie ? 'Publié' : 'Non publié',
                          article.publie
                              ? AppCouleurs.succes
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        if (article.publie && !article.disponible)
                          _puce(theme, 'Indisponible', AppCouleurs.danger),
                        if (article.publie && article.disponible)
                          _puce(
                            theme,
                            'Complétude ${article.completude} %',
                            article.completude >= 80
                                ? AppCouleurs.succes
                                : AppCouleurs.alerte,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Switch(
                value: article.publie,
                onChanged: _traitement
                    ? null
                    : (bool valeur) => _basculer(article, valeur),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _puce(ThemeData theme, String texte, Color couleur) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: theme.textTheme.labelSmall?.copyWith(
          color: couleur,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Valeurs saisies dans la feuille de réglage d'une publication.
class _ReglagePublication {
  const _ReglagePublication({
    required this.publie,
    required this.disponible,
    required this.unite,
    this.prixPublic,
    this.description,
    this.photo,
    this.motsCles,
  });

  final bool publie;
  final bool disponible;
  final String unite;
  final double? prixPublic;
  final String? description;
  final String? photo;
  final String? motsCles;
}

class _FeuilleReglage extends StatefulWidget {
  const _FeuilleReglage({required this.article});

  final PublicationProduit article;

  @override
  State<_FeuilleReglage> createState() => _FeuilleReglageState();
}

class _FeuilleReglageState extends State<_FeuilleReglage> {
  late final TextEditingController _prix;
  late final TextEditingController _unite;
  late final TextEditingController _description;
  late final TextEditingController _motsCles;

  late bool _publie;
  late bool _disponible;
  String? _photo;
  bool _envoiPhoto = false;

  @override
  void initState() {
    super.initState();
    final PublicationProduit a = widget.article;
    _prix = TextEditingController(
      text: a.prixPublic == null ? '' : a.prixPublic!.toStringAsFixed(0),
    );
    _unite = TextEditingController(text: a.unite);
    _description = TextEditingController(text: a.descriptionCourte ?? '');
    _motsCles = TextEditingController(text: a.motsCles ?? '');
    _publie = a.publie;
    _disponible = a.disponible;
    _photo = a.photo;
  }

  @override
  void dispose() {
    _prix.dispose();
    _unite.dispose();
    _description.dispose();
    _motsCles.dispose();
    super.dispose();
  }

  Future<void> _choisirPhoto() async {
    try {
      final String? chemin = await ImageService.pickFromGallery();
      if (chemin == null || !mounted) return;

      setState(() => _envoiPhoto = true);
      final String url = await VitrineService.instance.televerserImage(chemin);
      if (!mounted) return;
      setState(() {
        _photo = url;
        _envoiPhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoiPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'envoyer cette image.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PublicationProduit article = widget.article;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              article.nom,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              'Prix de vente en boutique : '
              '${formatMontant(article.prixVente)} / ${article.unite}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _publie,
              onChanged: (bool v) => setState(() => _publie = v),
              title: const Text('Visible sur Biashara',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _disponible,
              onChanged: (bool v) => setState(() => _disponible = v),
              title: const Text('Actuellement disponible',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text(
                'Décochez si l\'article est en rupture : les clients verront '
                '« Indisponible » au lieu de se déplacer pour rien.',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _prix,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Prix public (facultatif)',
                hintText: 'Laissez vide pour utiliser votre prix de vente',
                prefixIcon: Icon(Icons.sell_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _unite,
              decoration: const InputDecoration(
                labelText: 'Unité affichée',
                hintText: 'pièce, kg, sac de 25 kg…',
                prefixIcon: Icon(Icons.straighten_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              maxLines: 2,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Courte description',
                hintText: 'Ce qui aide le client à choisir',
              ),
            ),
            TextField(
              controller: _motsCles,
              decoration: const InputDecoration(
                labelText: 'Mots-clés recherchés (facultatif)',
                hintText: 'ex. farine, pain, boulangerie',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                PhotoBiashara(url: _photo, largeur: 58, hauteur: 58, rayon: 12),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _envoiPhoto ? null : _choisirPhoto,
                    icon: _envoiPhoto
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_rounded, size: 18),
                    label: const Text('Choisir une photo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(
                _ReglagePublication(
                  publie: _publie,
                  disponible: _disponible,
                  unite: _unite.text.trim().isEmpty
                      ? article.unite
                      : _unite.text.trim(),
                  prixPublic: double.tryParse(_prix.text.replaceAll(',', '.')),
                  description: _description.text.trim(),
                  photo: _photo,
                  motsCles: _motsCles.text.trim(),
                ),
              ),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Valider'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
