// lib/pages/publicite_biashara_form_page.dart
//
// 🛒 MODULE 19 — COMPOSITION D'UNE CAMPAGNE PUBLICITAIRE.
//
// Le commerçant choisit ce qu'il promeut (produit, boutique, promotion, offre),
// la période, un budget prévisionnel et — c'est la partie géolocalisée — une
// ZONE : sa ville, un quartier, un rayon autour de sa boutique, ou une
// catégorie de produit.
//
// ⚠️ Le ciblage géographique ne localise JAMAIS un visiteur : il compare la
//    ville que le visiteur a CHOISIE, la catégorie qu'il consulte, ou la
//    distance à un point que le commerçant a lui-même défini.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/localisation_boutique.dart';
import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/models/publication_produit.dart';
import 'package:biashara_yangu/services/image_service.dart';
import 'package:biashara_yangu/services/marketplace_service.dart';
import 'package:biashara_yangu/services/publicite_service.dart';
import 'package:biashara_yangu/services/vitrine_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/photo_biashara.dart';

class PubliciteBiasharaFormPage extends StatefulWidget {
  const PubliciteBiasharaFormPage({super.key, this.publicite});

  final PubliciteBiashara? publicite;

  @override
  State<PubliciteBiasharaFormPage> createState() =>
      _PubliciteBiasharaFormPageState();
}

class _PubliciteBiasharaFormPageState extends State<PubliciteBiasharaFormPage> {
  final PubliciteService _publicites = PubliciteService.instance;
  final VitrineService _vitrine = VitrineService.instance;

  final TextEditingController _titre = TextEditingController();
  final TextEditingController _annonce = TextEditingController();
  final TextEditingController _prixPromo = TextEditingController();
  final TextEditingController _budget = TextEditingController();
  final TextEditingController _plafond = TextEditingController();
  final TextEditingController _quartier = TextEditingController();
  final TextEditingController _categorie = TextEditingController();
  final TextEditingController _rayon = TextEditingController();

  TypeContenuPublicite _type = TypeContenuPublicite.produit;
  int? _produitId;
  String? _imageUrl;
  DateTime? _debut;
  DateTime? _fin;

  bool _ciblerVille = false;
  bool _ciblerQuartier = false;
  bool _ciblerCategorie = false;
  bool _ciblerRayon = false;

  String? _villeId;
  String? _villeNom;
  List<VillePublique> _villes = const <VillePublique>[];
  List<PublicationProduit> _produits = const <PublicationProduit>[];

  double? _boutiqueLat;
  double? _boutiqueLng;

  bool _chargement = true;
  bool _enregistrement = false;
  bool _envoiImage = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _titre.dispose();
    _annonce.dispose();
    _prixPromo.dispose();
    _budget.dispose();
    _plafond.dispose();
    _quartier.dispose();
    _categorie.dispose();
    _rayon.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final LocalisationBoutique etat = await _vitrine.etat();      final EtatPublications publications =
          await _vitrine.publications(filtre: FiltrePublications.publies);
      final List<VillePublique> villes =
          await MarketplaceService.instance.villes();

      if (!mounted) return;

      final PubliciteBiashara? p = widget.publicite;

      setState(() {
        _villes = villes;
        _produits = publications.articles;
        _boutiqueLat = etat.latitude;
        _boutiqueLng = etat.longitude;
        _villeId = etat.villeId;
        _villeNom = etat.ville;

        if (p != null) {
          _titre.text = p.titre;
          _annonce.text = p.message ?? '';
          _type = p.typeContenu;
          _produitId = p.produitId;
          _imageUrl = p.imageUrl;
          _prixPromo.text =
              p.prixPromo == null ? '' : p.prixPromo!.toStringAsFixed(0);
          _budget.text = p.budget == null ? '' : p.budget!.toStringAsFixed(0);
          _plafond.text = p.plafondImpressions?.toString() ?? '';
          _debut = p.dateDebut;
          _fin = p.dateFin;

          for (final CiblePublicite cible in p.cibles) {
            switch (cible.type) {
              case TypeCiblePublicite.ville:
                _ciblerVille = true;
                _villeId = cible.villeId ?? _villeId;
              case TypeCiblePublicite.quartier:
                _ciblerQuartier = true;
                _quartier.text = cible.quartier ?? '';
              case TypeCiblePublicite.categorie:
                _ciblerCategorie = true;
                _categorie.text = cible.categorie ?? '';
              case TypeCiblePublicite.rayon:
                _ciblerRayon = true;
                _rayon.text =
                    cible.rayonKm == null ? '' : cible.rayonKm!.toStringAsFixed(0);
            }
          }
        }

        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _chargement = false);
      _message('Impossible de charger le formulaire. Réessayez.');
    }
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  Future<void> _choisirImage() async {
    try {
      final String? chemin = await ImageService.pickFromGallery();
      if (chemin == null || !mounted) return;

      setState(() => _envoiImage = true);
      final String url = await _vitrine.televerserImage(chemin);
      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _envoiImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoiImage = false);
      _message('Impossible d\'envoyer cette image.');
    }
  }

  Future<void> _choisirDate({required bool debut}) async {
    final DateTime maintenant = DateTime.now();
    final DateTime? choisi = await showDatePicker(
      context: context,
      initialDate: (debut ? _debut : _fin) ?? maintenant,
      firstDate: debut ? maintenant : (_debut ?? maintenant),
      lastDate: maintenant.add(const Duration(days: 365)),
    );
    if (choisi == null || !mounted) return;
    setState(() {
      if (debut) {
        _debut = choisi;
      } else {
        _fin = choisi;
      }
    });
  }

  /// Construit la liste des cibles saisies.
  List<CiblePublicite> _cibles() {
    final List<CiblePublicite> cibles = <CiblePublicite>[];

    if (_ciblerVille && _villeId != null) {
      cibles.add(CiblePublicite(
        type: TypeCiblePublicite.ville,
        villeId: _villeId,
      ));
    }
    if (_ciblerQuartier && _quartier.text.trim().isNotEmpty) {
      cibles.add(CiblePublicite(
        type: TypeCiblePublicite.quartier,
        quartier: _quartier.text.trim(),
      ));
    }
    if (_ciblerCategorie && _categorie.text.trim().isNotEmpty) {
      cibles.add(CiblePublicite(
        type: TypeCiblePublicite.categorie,
        categorie: _categorie.text.trim(),
      ));
    }
    if (_ciblerRayon && _rayon.text.trim().isNotEmpty) {
      cibles.add(CiblePublicite(
        type: TypeCiblePublicite.rayon,
        rayonKm: double.tryParse(_rayon.text.replaceAll(',', '.')),
        // Le rayon est centré sur la BOUTIQUE du commerçant : aucun visiteur
        // n'est localisé pour ce ciblage.
        centreLat: _boutiqueLat,
        centreLng: _boutiqueLng,
      ));
    }

    return cibles;
  }

  Future<void> _enregistrer({required bool soumettre}) async {
    if (_titre.text.trim().isEmpty) {
      _message('Donnez un titre à votre annonce.');
      return;
    }

    if (_ciblerRayon && (_boutiqueLat == null || _boutiqueLng == null)) {
      _message('Pour cibler un rayon, renseignez d\'abord la position de votre '
          'boutique dans « Ma vitrine ».');
      return;
    }

    setState(() => _enregistrement = true);

    try {
      await _publicites.enregistrer(
        id: widget.publicite?.id,
        titre: _titre.text.trim(),
        message: _annonce.text.trim(),
        typeContenu: _type,
        produitId: _produitId,
        imageUrl: _imageUrl,
        prixPromo: double.tryParse(_prixPromo.text.replaceAll(',', '.')),
        dateDebut: _debut,
        dateFin: _fin,
        budget: double.tryParse(_budget.text.replaceAll(',', '.')),
        plafondImpressions: int.tryParse(_plafond.text.trim()),
        cibles: _cibles(),
        soumettre: soumettre,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PubliciteException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _message(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.publicite == null
            ? 'Nouvelle campagne'
            : 'Modifier la campagne'),
      ),
      body: _chargement
          ? const Center(child: ModernLoader(taille: 46))
          : _formulaire(theme),
    );
  }

  Widget _formulaire(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppCouleurs.marine.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Votre annonce sera toujours affichée avec la mention '
                '« PUBLICITÉ »',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
              ),
              const SizedBox(height: 4),
              Text(
                'Elle apparaît dans un emplacement dédié, jamais au milieu des '
                'résultats organiques, et ne masque jamais les boutiques qui '
                'ne font pas de publicité.',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        TextField(
          controller: _titre,
          decoration: const InputDecoration(
            labelText: 'Titre de l\'annonce',
            hintText: 'ex. Riz parfumé 25 kg en promotion',
            prefixIcon: Icon(Icons.campaign_rounded),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _annonce,
          maxLines: 2,
          maxLength: 180,
          decoration: const InputDecoration(
            labelText: 'Message (facultatif)',
            hintText: 'Ce que vous voulez dire aux clients',
          ),
        ),
        const SizedBox(height: 6),
        AppDropdownField<TypeContenuPublicite>(
          label: 'Ce que vous promouvez',
          value: _type,
          prefixIcon: Icons.category_rounded,
          items: <DropdownMenuItem<TypeContenuPublicite>>[
            for (final TypeContenuPublicite t in TypeContenuPublicite.values)
              DropdownMenuItem<TypeContenuPublicite>(
                value: t,
                child: Text(t.libelle),
              ),
          ],
          onChanged: (TypeContenuPublicite? valeur) {
            if (valeur == null) return;
            setState(() => _type = valeur);
          },
        ),
        const SizedBox(height: 10),
        if (_produits.isEmpty)
          Text(
            'Aucun article publié : publiez d\'abord un article dans '
            '« Mes publications » pour pouvoir le promouvoir.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppCouleurs.alerte,
            ),
          )
        else
          AppDropdownField<int>(
            label: 'Article promu (facultatif)',
            value: _produitId,
            prefixIcon: Icons.inventory_2_rounded,
            items: <DropdownMenuItem<int>>[
              for (final PublicationProduit produit in _produits)
                DropdownMenuItem<int>(
                  value: produit.produitId,
                  child: Text(
                    produit.nom,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (int? valeur) => setState(() => _produitId = valeur),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: _prixPromo,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Prix promotionnel (facultatif)',
            prefixIcon: Icon(Icons.sell_rounded),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            PhotoBiashara(
              url: _imageUrl,
              largeur: 58,
              hauteur: 58,
              rayon: 12,
              icone: Icons.campaign_rounded,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _envoiImage ? null : _choisirImage,
                icon: _envoiImage
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_rounded, size: 18),
                label: const Text('Visuel de l\'annonce'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),
        Text(
          'Période & budget',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _choisirDate(debut: true),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(_debut == null
                    ? 'Début'
                    : '${_debut!.day}/${_debut!.month}/${_debut!.year}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _choisirDate(debut: false),
                icon: const Icon(Icons.event_available_rounded, size: 18),
                label: Text(_fin == null
                    ? 'Fin'
                    : '${_fin!.day}/${_fin!.month}/${_fin!.year}'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _budget,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Budget prévisionnel',
                  prefixIcon: Icon(Icons.payments_rounded),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _plafond,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Affichages max.',
                  prefixIcon: Icon(Icons.visibility_rounded),
                ),
              ),
            ),
          ],
        ),
        Text(
          'Le budget est indicatif : aucune dépense n\'est prélevée '
          'automatiquement. Biashara vous contacte avant toute diffusion '
          'payante.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 22),
        Text(
          'Zone ciblée (géolocalisation respectueuse)',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'Sans cible, votre annonce peut être vue partout. Avec une cible, '
          'elle s\'adresse à la ville choisie par le visiteur, à la catégorie '
          'qu\'il consulte, ou à un rayon autour de votre boutique. La position '
          'personnelle des visiteurs n\'est jamais utilisée ni consultée.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _ciblerVille,
          onChanged: (bool v) => setState(() => _ciblerVille = v),
          title: const Text('Cibler une ville'),
          subtitle: Text(_villeNom ?? 'Aucune ville renseignée dans la vitrine'),
        ),
        if (_ciblerVille && _villes.isNotEmpty)
          AppDropdownField<String>(
            label: 'Ville',
            value: _villeId,
            prefixIcon: Icons.location_city_rounded,
            items: <DropdownMenuItem<String>>[
              for (final VillePublique ville in _villes)
                DropdownMenuItem<String>(
                  value: ville.id,
                  child: Text(ville.nom),
                ),
            ],
            onChanged: (String? valeur) => setState(() => _villeId = valeur),
          ),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _ciblerQuartier,
          onChanged: (bool v) => setState(() => _ciblerQuartier = v),
          title: const Text('Cibler un quartier'),
        ),
        if (_ciblerQuartier)
          TextField(
            controller: _quartier,
            decoration: const InputDecoration(
              labelText: 'Quartier',
              hintText: 'ex. Katuba',
              prefixIcon: Icon(Icons.holiday_village_rounded),
            ),
          ),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _ciblerCategorie,
          onChanged: (bool v) => setState(() => _ciblerCategorie = v),
          title: const Text('Cibler une catégorie de produit'),
        ),
        if (_ciblerCategorie)
          TextField(
            controller: _categorie,
            decoration: const InputDecoration(
              labelText: 'Catégorie',
              hintText: 'ex. boissons',
              prefixIcon: Icon(Icons.local_offer_rounded),
            ),
          ),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _ciblerRayon,
          onChanged: (bool v) => setState(() => _ciblerRayon = v),
          title: const Text('Cibler un rayon autour de ma boutique'),
          subtitle: Text(
            _boutiqueLat == null
                ? 'Renseignez la position de votre boutique dans « Ma vitrine »'
                : 'Rayon centré sur votre boutique '
                    '(${_boutiqueLat!.toStringAsFixed(4)}, '
                    '${_boutiqueLng!.toStringAsFixed(4)})',
          ),
        ),
        if (_ciblerRayon)
          TextField(
            controller: _rayon,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Rayon (km)',
              hintText: 'ex. 5',
              prefixIcon: Icon(Icons.radar_rounded),
            ),
          ),

        const SizedBox(height: 26),
        FilledButton.icon(
          onPressed: _enregistrement
              ? null
              : () => _enregistrer(soumettre: true),
          icon: _enregistrement
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: const Text('Soumettre pour validation'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed:
              _enregistrement ? null : () => _enregistrer(soumettre: false),
          icon: const Icon(Icons.save_rounded),
          label: const Text('Enregistrer en brouillon'),
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
      ],
    );
  }
}
