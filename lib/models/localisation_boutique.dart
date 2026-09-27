// lib/models/localisation_boutique.dart
//
// 🛒 MODULE 19 — LOCALISATION & VITRINE PUBLIQUE D'UNE BOUTIQUE (VUE PATRON).
//
// Ce modèle décrit ce que le commerçant VOIT et MODIFIE dans son application :
// position, statut de confirmation, adresse détaillée, contacts publics,
// horaires, visuels et nombre d'articles publiés.

import 'package:biashara_yangu/utils/geo_utils.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// État de la localisation d'une boutique.
enum StatutLocalisation {
  nonRenseignee('non_renseignee', 'Position non renseignée'),
  aVerifier('a_verifier', 'Position à confirmer'),
  verifiee('verifiee', 'Position confirmée');

  const StatutLocalisation(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutLocalisation fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final StatutLocalisation statut in values) {
      if (statut.code == normalise) return statut;
    }
    return StatutLocalisation.nonRenseignee;
  }

  bool get estConfirmee => this == StatutLocalisation.verifiee;
}

/// Origine de la position retenue par le commerçant (options A / B / C).
enum PrecisionLocalisation {
  gps('gps', 'Ma position actuelle', 'Utilise le GPS de l\'appareil'),
  carte('carte', 'Position choisie sur la carte', 'Vous placez le repère'),
  adresse('adresse', 'Adresse recherchée', 'Recherche par nom de lieu'),
  manuelle('manuelle', 'Saisie manuelle', 'Coordonnées saisies à la main');

  const PrecisionLocalisation(this.code, this.libelle, this.description);

  final String code;
  final String libelle;
  final String description;

  /// Libellé d'une précision éventuellement `null` (position ancienne).
  static String libelleOuInconnu(String? code) {
    if (code == null || code.trim().isEmpty) return 'Origine inconnue';
    for (final PrecisionLocalisation p in values) {
      if (p.code == code.trim().toLowerCase()) return p.libelle;
    }
    return 'Origine inconnue';
  }

  static PrecisionLocalisation? fromCode(String? code) {
    if (code == null) return null;
    final String normalise = code.trim().toLowerCase();
    for (final PrecisionLocalisation p in values) {
      if (p.code == normalise) return p;
    }
    return null;
  }
}

/// État complet de la vitrine publique d'une boutique.
class LocalisationBoutique {
  const LocalisationBoutique({
    required this.espaceId,
    required this.nom,
    this.type = 'boutique',
    this.visiblePubliquement = false,
    this.slug,
    this.description,
    this.telephone,
    this.whatsapp,
    this.horaires = const <String, dynamic>{},
    this.logoUrl,
    this.photoUrl,
    this.adresse,
    this.quartier,
    this.avenue,
    this.numero,
    this.pointRepere,
    this.latitude,
    this.longitude,
    this.precision,
    this.statut = StatutLocalisation.nonRenseignee,
    this.majLe,
    this.villeId,
    this.ville,
    this.nbProduitsPublies = 0,
    this.nbProduits = 0,
    this.compteOperationnel = true,
    this.visibleEffectivement = false,
    this.activationEtape,
  });

  final String espaceId;
  final String nom;
  final String type;

  /// Opt-in explicite : sans lui, la boutique n'apparaît nulle part.
  final bool visiblePubliquement;

  final String? slug;
  final String? description;
  final String? telephone;
  final String? whatsapp;
  final Map<String, dynamic> horaires;
  final String? logoUrl;
  final String? photoUrl;
  final String? adresse;
  final String? quartier;
  final String? avenue;
  final String? numero;
  final String? pointRepere;
  final double? latitude;
  final double? longitude;
  final PrecisionLocalisation? precision;
  final StatutLocalisation statut;
  final DateTime? majLe;
  final String? villeId;
  final String? ville;
  final int nbProduitsPublies;
  final int nbProduits;

  /// Le compte est-il validé (module 14) ? Un compte en attente peut
  /// PRÉPARER sa vitrine, mais elle ne sera visible du public qu'à l'activation.
  final bool compteOperationnel;

  /// La vitrine est-elle réellement visible dans le catalogue public ?
  /// (opt-in du commerçant **et** compte opérationnel).
  final bool visibleEffectivement;

  /// Étape du dossier d'activation (`actif`, `restreint`,
  /// `en_attente_verification`, `verifie`, `rejete`).
  final String? activationEtape;

  bool get aPosition => latitude != null && longitude != null;

  /// La vitrine est prête mais attend la validation de la plateforme.
  bool get enAttenteActivation => visiblePubliquement && !compteOperationnel;

  /// Message honnête à afficher au commerçant sur l'état de sa vitrine.
  String get messageVisibilite {
    if (!visiblePubliquement) {
      return 'Votre boutique n\'est pas encore publiée sur Biashara : activez '
          '« Rendre ma boutique visible » pour apparaître dans les recherches.';
    }
    if (!compteOperationnel) {
      return 'Votre vitrine est PRÊTE. Elle sera visible du public dès que '
          'votre compte aura été validé par la plateforme.';
    }
    if (!aPosition) {
      return 'Ajoutez la position de votre boutique pour apparaître sur la '
          'carte et dans « Autour de moi ».';
    }
    if (nbProduitsPublies == 0) {
      return 'Publiez au moins un article pour être trouvé par les clients.';
    }
    return 'Votre boutique est visible dans le catalogue Biashara.';
  }

  /// Chemin public de la vitrine (`null` tant qu'elle n'a pas été publiée).
  String? get cheminPublic =>
      (slug != null && slug!.isNotEmpty) ? '/biashara/boutique/$slug' : null;

  /// Adresse complète telle qu'un visiteur étranger la lira.
  String get adresseLisible => adresseComplete(
        numero: numero,
        avenue: avenue,
        quartier: quartier,
        adresse: adresse,
        pointRepere: pointRepere,
        ville: ville,
      );

  /// Points qu'il reste à renseigner avant de publier utilement la boutique.
  ///
  /// Ce diagnostic est TRANSPARENT : il alimente la liste « Pour être mieux
  /// trouvée… » de l'écran de localisation.
  List<String> get pointsManquants {
    final List<String> manquants = <String>[];
    if (!aPosition) manquants.add('Position de la boutique');
    if (villeId == null) manquants.add('Ville');
    if (quartier == null || quartier!.trim().isEmpty) manquants.add('Quartier');
    if (pointRepere == null || pointRepere!.trim().isEmpty) {
      manquants.add('Point de repère');
    }
    if (telephone == null || telephone!.trim().isEmpty) {
      manquants.add('Téléphone');
    }
    if (horaires.isEmpty) manquants.add('Horaires');
    if (logoUrl == null && photoUrl == null) manquants.add('Logo ou photo');
    return manquants;
  }

  /// Prêt à publier : une position ET au moins un article publié.
  bool get pretAPublier => aPosition && nbProduitsPublies > 0;

  factory LocalisationBoutique.fromMap(Map<String, dynamic> map) {
    return LocalisationBoutique(
      espaceId: parseString(map['espace_id']),
      nom: parseString(map['nom']),
      type: parseString(map['type'], fallback: 'boutique'),
      visiblePubliquement: map['visible_publiquement'] == true,
      slug: parseStringOrNull(map['slug']),
      description: parseStringOrNull(map['description_publique']),
      telephone: parseStringOrNull(map['telephone_public']),
      whatsapp: parseStringOrNull(map['whatsapp']),
      horaires: parseMap(map['horaires']) ?? <String, dynamic>{},
      logoUrl: parseStringOrNull(map['logo_url']),
      photoUrl: parseStringOrNull(map['photo_url']),
      adresse: parseStringOrNull(map['adresse']),
      quartier: parseStringOrNull(map['quartier']),
      avenue: parseStringOrNull(map['avenue']),
      numero: parseStringOrNull(map['numero']),
      pointRepere: parseStringOrNull(map['point_repere']),
      latitude: parseDoubleOrNull(map['latitude']),
      longitude: parseDoubleOrNull(map['longitude']),
      precision: PrecisionLocalisation.fromCode(
        parseStringOrNull(map['precision_localisation']),
      ),
      statut: StatutLocalisation.fromCode(
        parseStringOrNull(map['statut_localisation']),
      ),
      majLe: parseDateTimeOrNull(map['localisation_maj_le']),
      villeId: parseStringOrNull(map['ville_id']),
      ville: parseStringOrNull(map['ville']),
      nbProduitsPublies: parseInt(map['nb_produits_publies']),
      nbProduits: parseInt(map['nb_produits']),
      compteOperationnel: map['compte_operationnel'] != false,
      visibleEffectivement: map['visible_effectivement'] == true,
      activationEtape: parseStringOrNull(map['activation_etape']),
    );
  }
}
