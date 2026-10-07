// lib/pages/ma_vitrine_page.dart
//
// 🛒 MODULE 19 — « MA VITRINE BIASHARA » (ESPACE COMMERÇANT).
//
// Parcours de localisation professionnel, avec les TROIS options demandées :
//   A. « Utiliser ma position actuelle » (GPS de l'appareil) ;
//   B. « Choisir ma position sur la carte » (repère posé à la main) ;
//   C. « Rechercher mon adresse » (aide à la saisie, sans clé d'API).
//
// Puis une CONFIRMATION explicite :
//   « Cette position correspond-elle bien à l'emplacement de votre boutique ? »
// Tant que la réponse est non (ou pas donnée), la position reste « à
// confirmer » : l'application publique l'affiche honnêtement et le classement
// n'en tire aucun avantage. Avant l'enregistrement définitif, un APERÇU montre
// exactement ce que verront les clients.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:biashara_yangu/models/boutique_publique.dart';
import 'package:biashara_yangu/models/localisation_boutique.dart';
import 'package:biashara_yangu/services/geocodage_service.dart';
import 'package:biashara_yangu/services/image_service.dart';
import 'package:biashara_yangu/services/marketplace_service.dart';
import 'package:biashara_yangu/services/vitrine_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/geolocalisation.dart';
import 'package:biashara_yangu/widgets/carte_boutique_publique.dart';
import 'package:biashara_yangu/widgets/choix_ville_sheet.dart';
import 'package:biashara_yangu/widgets/photo_biashara.dart';

/// Horaire d'un jour de la semaine (éditeur compact).
class _JourHoraire {
  _JourHoraire({required this.cle, required this.libelle});

  final String cle;
  final String libelle;

  bool ouvert = false;
  TimeOfDay ouverture = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay fermeture = const TimeOfDay(hour: 18, minute: 0);

  Map<String, dynamic>? versJson() {
    if (!ouvert) return null;
    return <String, dynamic>{
      'j': cle,
      'o': _heure(ouverture),
      'f': _heure(fermeture),
    };
  }

  static String _heure(TimeOfDay h) =>
      '${h.hour.toString().padLeft(2, '0')}:'
      '${h.minute.toString().padLeft(2, '0')}';
}

class MaVitrinePage extends StatefulWidget {
  const MaVitrinePage({super.key, this.espaceId});

  /// 🧑‍🌾 MODULE 21 ter — boutique ciblée. `null` = la boutique active du
  /// compte connecté (commerçant). Un AGENT TERRAIN, qui n'a pas d'entreprise,
  /// passe l'identifiant de la boutique qu'il a prise en charge.
  final String? espaceId;

  @override
  State<MaVitrinePage> createState() => _MaVitrinePageState();
}

class _MaVitrinePageState extends State<MaVitrinePage> {
  final VitrineService _vitrine = VitrineService.instance;
  final MapController _carte = MapController();

  final TextEditingController _description = TextEditingController();
  final TextEditingController _telephone = TextEditingController();
  final TextEditingController _whatsapp = TextEditingController();
  final TextEditingController _adresse = TextEditingController();
  final TextEditingController _quartier = TextEditingController();
  final TextEditingController _avenue = TextEditingController();
  final TextEditingController _numero = TextEditingController();
  final TextEditingController _repere = TextEditingController();

  final List<_JourHoraire> _horaires = <_JourHoraire>[
    _JourHoraire(cle: 'lun', libelle: 'Lundi'),
    _JourHoraire(cle: 'mar', libelle: 'Mardi'),
    _JourHoraire(cle: 'mer', libelle: 'Mercredi'),
    _JourHoraire(cle: 'jeu', libelle: 'Jeudi'),
    _JourHoraire(cle: 'ven', libelle: 'Vendredi'),
    _JourHoraire(cle: 'sam', libelle: 'Samedi'),
    _JourHoraire(cle: 'dim', libelle: 'Dimanche'),
  ];

  LocalisationBoutique? _etat;

  String? _villeId;
  String? _villeNom;
  double? _latitude;
  double? _longitude;
  PrecisionLocalisation? _precision;
  bool _confirmee = false;
  String? _logoUrl;
  String? _photoUrl;
  bool _visible = false;

  bool _chargement = true;
  bool _enregistrement = false;
  bool _localisationEnCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _description.dispose();
    _telephone.dispose();
    _whatsapp.dispose();
    _adresse.dispose();
    _quartier.dispose();
    _avenue.dispose();
    _numero.dispose();
    _repere.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final LocalisationBoutique etat =
          await _vitrine.etat(espaceId: widget.espaceId);

      if (!mounted) return;

      setState(() {
        _etat = etat;
        _description.text = etat.description ?? '';
        _telephone.text = etat.telephone ?? '';
        _whatsapp.text = etat.whatsapp ?? '';
        _adresse.text = etat.adresse ?? '';
        _quartier.text = etat.quartier ?? '';
        _avenue.text = etat.avenue ?? '';
        _numero.text = etat.numero ?? '';
        _repere.text = etat.pointRepere ?? '';
        _villeId = etat.villeId;
        _villeNom = etat.ville;
        _latitude = etat.latitude;
        _longitude = etat.longitude;
        _precision = etat.precision;
        _confirmee = etat.statut.estConfirmee;
        _logoUrl = etat.logoUrl;
        _photoUrl = etat.photoUrl;
        _visible = etat.visiblePubliquement;
        _chargement = false;
      });

      _chargerHoraires(etat);
    } on VitrineException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  void _chargerHoraires(LocalisationBoutique etat) {
    final Object? jours = etat.horaires['jours'];
    if (jours is! List) return;

    for (final Object? element in jours) {
      if (element is! Map) continue;
      final String cle = (element['j'] ?? '').toString();

      for (final _JourHoraire jour in _horaires) {
        if (jour.cle != cle) continue;
        jour.ouvert = true;
        jour.ouverture = _lireHeure(element['o']) ?? jour.ouverture;
        jour.fermeture = _lireHeure(element['f']) ?? jour.fermeture;
        break;
      }
    }
  }

  static TimeOfDay? _lireHeure(dynamic valeur) {
    final String texte = (valeur ?? '').toString();
    final List<String> parties = texte.split(':');
    if (parties.length < 2) return null;
    final int? h = int.tryParse(parties[0]);
    final int? m = int.tryParse(parties[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  // ---------------------------------------------------------------------------
  // OPTION A — MA POSITION ACTUELLE
  // ---------------------------------------------------------------------------

  Future<void> _maPosition() async {
    setState(() => _localisationEnCours = true);
    final ResultatPosition resultat =
        await Geolocalisation.instance.positionActuelle();

    if (!mounted) return;
    setState(() => _localisationEnCours = false);

    final PositionUtilisateur? position = resultat.position;
    if (position == null) {
      _message(resultat.message ?? 'Position indisponible.');
      return;
    }

    setState(() {
      _latitude = position.latitude;
      _longitude = position.longitude;
      _precision = PrecisionLocalisation.gps;
      _confirmee = false;
    });
    _carte.move(LatLng(position.latitude, position.longitude), 16);
    _message('Position GPS obtenue${position.precisionLibelle == null ? '' : ' (${position.precisionLibelle})'}. '
        'Vérifiez le repère, puis confirmez.');
  }

  // ---------------------------------------------------------------------------
  // OPTION B — CHOISIR SUR LA CARTE
  // ---------------------------------------------------------------------------

  void _positionSurCarte(LatLng point) {
    setState(() {
      _latitude = point.latitude;
      _longitude = point.longitude;
      _precision = PrecisionLocalisation.carte;
      _confirmee = false;
    });
  }

  // ---------------------------------------------------------------------------
  // OPTION C — RECHERCHER MON ADRESSE
  // ---------------------------------------------------------------------------

  Future<void> _rechercherAdresse() async {
    final String? requete = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => const _DialogueRechercheAdresse(),
    );
    if (requete == null || !mounted) return;

    setState(() => _localisationEnCours = true);
    final List<PropositionAdresse> propositions =
        await GeocodageService.instance.rechercher(requete);
    if (!mounted) return;
    setState(() => _localisationEnCours = false);

    if (propositions.isEmpty) {
      _message(GeocodageService.messageAucunResultat);
      return;
    }

    final PropositionAdresse? choix = await showModalBottomSheet<PropositionAdresse>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => ListView(
        shrinkWrap: true,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Choisissez votre adresse',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          for (final PropositionAdresse proposition in propositions)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(
                proposition.libelle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(ctx).pop(proposition),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );

    if (choix == null || !mounted) return;

    setState(() {
      _latitude = choix.latitude;
      _longitude = choix.longitude;
      _precision = PrecisionLocalisation.adresse;
      _confirmee = false;
      if (_quartier.text.trim().isEmpty && choix.quartier != null) {
        _quartier.text = choix.quartier!;
      }
      if (_adresse.text.trim().isEmpty) {
        _adresse.text = choix.libelle.split(',').take(2).join(',').trim();
      }
    });
    _carte.move(LatLng(choix.latitude, choix.longitude), 16);
    _message('Adresse proposée. Vérifiez le repère, puis confirmez.');
  }

  // ---------------------------------------------------------------------------
  // ENREGISTREMENT
  // ---------------------------------------------------------------------------

  Future<void> _enregistrer() async {
    if (_visible && (_latitude == null || _longitude == null) && _villeId == null) {
      _message('Indiquez la position de votre boutique ou choisissez au moins '
          'une ville avant de la publier.');
      return;
    }

    // CONFIRMATION demandée par le cahier des charges, uniquement quand une
    // position existe et n'a pas encore été validée.
    bool confirmee = _confirmee;
    if (_latitude != null && _longitude != null && !_confirmee) {
      final bool? reponse = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Confirmation de la position'),
          content: const Text(
            'Cette position correspond-elle bien à l\'emplacement de votre '
            'boutique ?\n\n'
            'Si vous répondez « oui », vos clients verront « Position '
            'confirmée » et l\'itinéraire sera fiable. Sinon, la position '
            'reste « à confirmer ».',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Je vérifierai plus tard'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Oui, c\'est bien ici'),
            ),
          ],
        ),
      );
      confirmee = reponse == true;
    }

    setState(() => _enregistrement = true);

    try {
      final ResultatVitrine resultat = await _vitrine.enregistrer(
        espaceId: _etat?.espaceId,
        adresse: _adresse.text.trim(),
        quartier: _quartier.text.trim(),
        avenue: _avenue.text.trim(),
        numero: _numero.text.trim(),
        pointRepere: _repere.text.trim(),
        villeId: _villeId,
        latitude: _latitude,
        longitude: _longitude,
        precision: _precision?.code,
        confirmee: confirmee,
        telephone: _telephone.text.trim(),
        whatsapp: _whatsapp.text.trim(),
        horaires: <String, dynamic>{
          'jours': _horaires
              .map((_JourHoraire h) => h.versJson())
              .whereType<Map<String, dynamic>>()
              .toList(growable: false),
        },
        description: _description.text.trim(),
        logoUrl: _logoUrl,
        photoUrl: _photoUrl,
        visible: _visible,
      );

      if (!mounted) return;
      setState(() => _enregistrement = false);

      _message(resultat.visible
          ? 'Vitrine enregistrée. Votre boutique est visible sur Biashara.'
          : 'Vitrine enregistrée. Activez « Rendre ma boutique visible » pour '
              'apparaître dans les recherches.');

      await _charger();
    } on VitrineException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _message(e.message);
    }
  }

  Future<void> _choisirImage({required bool logo}) async {
    try {
      final String? chemin = await ImageService.pickFromGallery();
      if (chemin == null || !mounted) return;

      setState(() => _enregistrement = true);
      final String url = await _vitrine.televerserImage(chemin);
      if (!mounted) return;
      setState(() {
        if (logo) {
          _logoUrl = url;
        } else {
          _photoUrl = url;
        }
        _enregistrement = false;
      });
      _message('Image prête. N\'oubliez pas d\'enregistrer votre vitrine.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      _message('Impossible d\'envoyer cette image. Réessayez.');
    }
  }

  Future<void> _choisirVille() async {
    final VillePublique? ville = await ouvrirChoixVille(context);
    if (ville == null || !mounted) return;
    setState(() {
      _villeId = ville.id;
      _villeNom = ville.nom;
    });
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  /// APERÇU PUBLIC — « Voici comment votre boutique apparaîtra sur Biashara ».
  void _apercu() {
    final LocalisationBoutique? etat = _etat;
    if (etat == null) return;

    final ResumeBoutique resume = ResumeBoutique(
      espaceId: etat.espaceId,
      nom: etat.nom,
      slug: etat.slug,
      type: etat.type,
      logoUrl: _logoUrl,
      quartier: _quartier.text.trim().isEmpty ? null : _quartier.text.trim(),
      adresse: _adresse.text.trim().isEmpty ? null : _adresse.text.trim(),
      ville: _villeNom,
      telephone: _telephone.text.trim().isEmpty ? null : _telephone.text.trim(),
      whatsapp: _whatsapp.text.trim().isEmpty ? null : _whatsapp.text.trim(),
      latitude: _latitude,
      longitude: _longitude,
      localisationVerifiee: _confirmee,
      nbProduits: etat.nbProduitsPublies,
    );

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Voici comment votre boutique apparaîtra sur Biashara',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Les clients voient uniquement ces informations : vos prix '
              'd\'achat, votre stock et vos données financières ne sont '
              'jamais publiés.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            CarteBoutiquePublique(boutique: resume),
            const SizedBox(height: 14),
            Text(
              _visible
                  ? '✅ Publication activée.'
                  : '⚠️ Publication désactivée : activez « Rendre ma boutique '
                      'visible » puis enregistrez.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _visible ? AppCouleurs.succes : AppCouleurs.alerte,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma vitrine Biashara'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Aperçu public',
            onPressed: _etat == null ? null : _apercu,
            icon: const Icon(Icons.visibility_rounded),
          ),
          IconButton(
            tooltip: 'Recharger',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: ModernLoader(taille: 46))
          : (_erreur != null ? _etatErreur(theme) : _formulaire(theme)),
      bottomNavigationBar: _etat == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _enregistrement ? null : _enregistrer,
                  icon: _enregistrement
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Enregistrer ma vitrine'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _etatErreur(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.storefront_rounded,
                size: 46, color: AppCouleurs.alerte),
            const SizedBox(height: 12),
            Text(
              _erreur ?? 'Vitrine indisponible.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
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

  Widget _formulaire(ThemeData theme) {
    final LocalisationBoutique etat = _etat!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        // ---- Bandeau d'état (transparence totale) ----
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (etat.visibleEffectivement
                    ? AppCouleurs.succes
                    : AppCouleurs.alerte)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                etat.visibleEffectivement
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: etat.visibleEffectivement
                    ? AppCouleurs.succes
                    : AppCouleurs.alerte,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      etat.nom,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      etat.messageVisibilite,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${etat.nbProduitsPublies} article'
                      '${etat.nbProduitsPublies > 1 ? 's' : ''} publié'
                      '${etat.nbProduitsPublies > 1 ? 's' : ''} '
                      'sur ${etat.nbProduits} au catalogue',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        _titre(theme, 'Position de votre boutique'),
        Text(
          'Choisissez la méthode qui vous convient : le résultat est identique.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _localisationEnCours ? null : _maPosition,
              icon: _localisationEnCours
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('Utiliser ma position actuelle'),
            ),
            OutlinedButton.icon(
              onPressed: () => _message(
                'Touchez la carte ci-dessous pour placer le repère sur votre '
                'boutique.',
              ),
              icon: const Icon(Icons.touch_app_rounded, size: 18),
              label: const Text('Choisir ma position sur la carte'),
            ),
            OutlinedButton.icon(
              onPressed: _localisationEnCours ? null : _rechercherAdresse,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Rechercher mon adresse'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ---- Carte de placement ----
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 230,
            child: FlutterMap(
              mapController: _carte,
              options: MapOptions(
                initialCenter: _latitude != null && _longitude != null
                    ? LatLng(_latitude!, _longitude!)
                    : const LatLng(-11.6609, 27.4794),
                initialZoom: _latitude != null ? 16 : 11.5,
                onTap: (_, LatLng point) => _positionSurCarte(point),
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.biashara_yangu',
                  maxZoom: 19,
                ),
                if (_latitude != null && _longitude != null)
                  MarkerLayer(
                    markers: <Marker>[
                      Marker(
                        point: LatLng(_latitude!, _longitude!),
                        width: 46,
                        height: 46,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _confirmee
                                ? AppCouleurs.succes
                                : AppCouleurs.orangeFonce,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 3),
                          ),
                          child: const Icon(Icons.storefront_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                const RichAttributionWidget(
                  attributions: <SourceAttribution>[
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Touchez la carte pour déplacer le repère. '
          '${_latitude == null ? 'Aucune position définie.' : 'Position : '
              '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Icon(
              _confirmee ? Icons.verified_rounded : Icons.help_outline_rounded,
              size: 18,
              color: _confirmee ? AppCouleurs.succes : AppCouleurs.alerte,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _confirmee
                    ? 'Position confirmée : l\'itinéraire affiché aux clients '
                        'est fiable.'
                    : 'Position à confirmer : l\'enregistrement vous demandera '
                        'de valider l\'emplacement.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        if (_precision != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Méthode utilisée : ${_precision!.libelle}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        const SizedBox(height: 22),
        _titre(theme, 'Adresse visible par les clients'),
        Text(
          'Un client qui ne connaît pas votre ville doit pouvoir vous '
          'trouver. Le point de repère est souvent plus utile qu\'un numéro.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        _champ(_quartier, 'Quartier', Icons.holiday_village_rounded),
        _champ(_avenue, 'Avenue / rue', Icons.signpost_rounded),
        _champ(_numero, 'Numéro (facultatif)', Icons.numbers_rounded),
        _champ(_repere, 'Point de repère (ex. face à la poste)',
            Icons.push_pin_rounded),
        _champ(_adresse, 'Adresse libre (facultatif)', Icons.map_rounded),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.location_city_rounded,
              color: AppCouleurs.marine),
          title: Text(_villeNom ?? 'Choisir une ville'),
          subtitle: const Text('Ville utilisée pour « Rechercher dans une ville »'),
          trailing: TextButton(
            onPressed: _choisirVille,
            child: Text(_villeNom == null ? 'Choisir' : 'Changer'),
          ),
        ),

        const SizedBox(height: 22),
        _titre(theme, 'Contacts publics'),
        Text(
          'Ces numéros seront visibles par tous. N\'indiquez que des lignes '
          'professionnelles.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        _champ(_telephone, 'Téléphone de la boutique', Icons.call_rounded,
            clavier: TextInputType.phone),
        _champ(_whatsapp, 'WhatsApp (format international)', Icons.chat_rounded,
            clavier: TextInputType.phone),

        const SizedBox(height: 22),
        _titre(theme, 'Horaires d\'ouverture'),
        const SizedBox(height: 4),
        for (final _JourHoraire jour in _horaires) _ligneHoraire(theme, jour),

        const SizedBox(height: 22),
        _titre(theme, 'Présentation & visuels'),
        const SizedBox(height: 10),
        TextField(
          controller: _description,
          maxLines: 3,
          maxLength: 400,
          decoration: const InputDecoration(
            labelText: 'Présentation de la boutique',
            hintText: 'Ce que vous vendez, ce qui vous distingue…',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            PhotoBiashara(url: _logoUrl, largeur: 64, hauteur: 64, rayon: 14),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _choisirImage(logo: true),
                icon: const Icon(Icons.image_rounded, size: 18),
                label: const Text('Logo / enseigne'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            PhotoBiashara(
              url: _photoUrl,
              largeur: 64,
              hauteur: 64,
              rayon: 14,
              icone: Icons.photo_camera_rounded,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _choisirImage(logo: false),
                icon: const Icon(Icons.photo_camera_rounded, size: 18),
                label: const Text('Photo de la devanture'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _visible,
          onChanged: (bool valeur) => setState(() => _visible = valeur),
          title: const Text(
            'Rendre ma boutique visible sur Biashara',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'Vos articles publiés, votre position, vos horaires et vos contacts '
            'publics deviennent visibles par tous les visiteurs. Vos prix '
            'd\'achat, votre stock, vos clients et vos finances ne sont jamais '
            'publiés.'
            '${etat.compteOperationnel ? '' : ' Votre vitrine sera visible dès '
                'que votre compte aura été validé.'}',
          ),
        ),
        if (etat.pointsManquants.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppCouleurs.info.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Pour être trouvée plus facilement',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                for (final String point in etat.pointsManquants)
                  Text('• $point', style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  'Ces informations n\'influencent pas la publicité : elles '
                  'aident simplement les clients à vous trouver.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _ligneHoraire(ThemeData theme, _JourHoraire jour) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 86,
            child: Text(jour.libelle, style: theme.textTheme.bodySmall),
          ),
          Switch(
            value: jour.ouvert,
            onChanged: (bool valeur) => setState(() => jour.ouvert = valeur),
          ),
          if (jour.ouvert) ...<Widget>[
            TextButton(
              onPressed: () async {
                final TimeOfDay? choisi = await showTimePicker(
                  context: context,
                  initialTime: jour.ouverture,
                );
                if (choisi != null) setState(() => jour.ouverture = choisi);
              },
              child: Text(_JourHoraire._heure(jour.ouverture)),
            ),
            const Text('–'),
            TextButton(
              onPressed: () async {
                final TimeOfDay? choisi = await showTimePicker(
                  context: context,
                  initialTime: jour.fermeture,
                );
                if (choisi != null) setState(() => jour.fermeture = choisi);
              },
              child: Text(_JourHoraire._heure(jour.fermeture)),
            ),
          ] else
            Expanded(
              child: Text(
                'Fermé',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _titre(ThemeData theme, String titre) {
    return Text(
      titre,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
    );
  }

  Widget _champ(
    TextEditingController controleur,
    String label,
    IconData icone, {
    TextInputType clavier = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controleur,
        keyboardType: clavier,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icone)),
      ),
    );
  }
}

/// Boîte de dialogue « Rechercher mon adresse » (option C).
class _DialogueRechercheAdresse extends StatefulWidget {
  const _DialogueRechercheAdresse();

  @override
  State<_DialogueRechercheAdresse> createState() =>
      _DialogueRechercheAdresseState();
}

class _DialogueRechercheAdresseState extends State<_DialogueRechercheAdresse> {
  final TextEditingController _requete = TextEditingController();

  @override
  void dispose() {
    _requete.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rechercher mon adresse'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Tapez votre adresse la plus précise possible. Exemple : '
            '« avenue Kasaï, Katuba, Lubumbashi ».',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _requete,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'Adresse',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onSubmitted: (String valeur) {
              if (valeur.trim().length >= 3) {
                Navigator.of(context).pop(valeur.trim());
              }
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final String valeur = _requete.text.trim();
            if (valeur.length < 3) return;
            Navigator.of(context).pop(valeur);
          },
          child: const Text('Rechercher'),
        ),
      ],
    );
  }
}
