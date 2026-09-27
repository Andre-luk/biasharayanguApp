// lib/models/boutique_publique.dart
//
// 🛒 MODULE 19 — BOUTIQUES DU CATALOGUE PUBLIC.
//
// Deux niveaux :
//   • [ResumeBoutique]  : informations compactes (résultat de recherche,
//     marqueur de carte, encart publicitaire) ;
//   • [BoutiquePublique]: fiche complète (page `/biashara/boutique/<slug>`).
//
// ⚠️ Ces objets ne contiennent QUE des données publiques : le catalogue
//    public ne reçoit jamais de prix d'achat, de stock exact, de clientèle ni
//    d'information financière (filtrage fait côté serveur par les RPC du
//    module 19).

import 'package:biashara_yangu/models/espace.dart';
import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/utils/geo_utils.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Informations publiques compactes d'une boutique.
class ResumeBoutique {
  const ResumeBoutique({
    required this.espaceId,
    required this.nom,
    this.slug,
    this.type = 'boutique',
    this.logoUrl,
    this.photoUrl,
    this.quartier,
    this.adresse,
    this.ville,
    this.telephone,
    this.whatsapp,
    this.latitude,
    this.longitude,
    this.localisationVerifiee = false,
    this.distanceKm,
    this.nbProduits = 0,
  });

  final String espaceId;
  final String nom;

  /// Identifiant d'URL partageable (`/biashara/boutique/<slug>`).
  final String? slug;

  /// Code d'activité (`boutique`, `hotel`, `pharmacie`, `salon_de_coiffure`…).
  final String type;

  final String? logoUrl;
  final String? photoUrl;
  final String? quartier;
  final String? adresse;
  final String? ville;
  final String? telephone;
  final String? whatsapp;

  final double? latitude;
  final double? longitude;

  /// `true` = le commerçant a CONFIRMÉ que la position est la bonne.
  final bool localisationVerifiee;

  /// Distance calculée par le serveur (jamais stockée côté visiteur).
  final double? distanceKm;

  /// Nombre d'articles publiés par la boutique.
  final int nbProduits;

  factory ResumeBoutique.fromMap(Map<String, dynamic> map) {
    return ResumeBoutique(
      espaceId: parseString(map['espace_id']),
      nom: parseString(map['nom']),
      slug: parseStringOrNull(map['slug']),
      type: parseString(map['type'], fallback: 'boutique'),
      logoUrl: parseStringOrNull(map['logo_url']),
      photoUrl: parseStringOrNull(map['photo_url']),
      quartier: parseStringOrNull(map['quartier']),
      adresse: parseStringOrNull(map['adresse']),
      ville: parseStringOrNull(map['ville']),
      telephone: parseStringOrNull(map['telephone']),
      whatsapp: parseStringOrNull(map['whatsapp']),
      latitude: parseDoubleOrNull(map['latitude']),
      longitude: parseDoubleOrNull(map['longitude']),
      localisationVerifiee: map['localisation_verifiee'] == true,
      distanceKm: parseDoubleOrNull(map['distance_km']),
      nbProduits: parseInt(map['nb_produits']),
    );
  }

  /// La boutique est-elle géolocalisée (donc plaçable sur la carte) ?
  bool get aPosition => latitude != null && longitude != null;

  /// Libellé de la distance (« 850 m », « 1,2 km ») ou `null`.
  String? get distanceLibelle => formatDistance(distanceKm);

  /// Adresse lisible par un visiteur qui ne connaît pas la ville.
  String get adresseLisible => adresseComplete(
        adresse: adresse,
        quartier: quartier,
        ville: ville,
      );

  /// Libellé humain de l'activité (« Hôtel », « Salon de coiffure »…).
  String get typeLibelle => TypeEspace.fromCode(type).libelle;

  /// Chemin public de la fiche boutique (`null` si le slug n'existe pas encore).
  String? get cheminPublic =>
      (slug != null && slug!.isNotEmpty) ? '/biashara/boutique/$slug' : null;

  /// Lien d'itinéraire vers la boutique, ou `null` si elle n'est pas placée.
  String? lienItineraireDepuis({double? lat, double? lng}) {
    if (!aPosition) return null;
    return lienItineraire(
      latitude: latitude!,
      longitude: longitude!,
      depuisLat: lat,
      depuisLng: lng,
      libelle: nom,
    );
  }
}

/// Fiche PUBLIQUE complète d'une boutique.
class BoutiquePublique {
  const BoutiquePublique({
    required this.resume,
    this.description,
    this.horaires = const <String, dynamic>{},
    this.avenue,
    this.numero,
    this.pointRepere,
    this.pays,
    this.produits = const <Map<String, dynamic>>[],
    this.nbProduits = 0,
    this.publicites = const <PubliciteBiashara>[],
  });

  final ResumeBoutique resume;
  final String? description;

  /// Objet libre (`{"jours":[{"j":"lun","o":"08:00","f":"18:00"}],"note":"…"}`).
  final Map<String, dynamic> horaires;

  final String? avenue;
  final String? numero;
  final String? pointRepere;
  final String? pays;

  /// Articles publiés (objets bruts du serveur : la conversion en
  /// `ProduitPublic` est faite par le service, qui connaît la boutique).
  final List<Map<String, dynamic>> produits;

  final int nbProduits;

  /// Emplacements sponsorisés servis avec la fiche (toujours marqués
  /// « PUBLICITÉ » et affichés HORS des produits organiques).
  final List<PubliciteBiashara> publicites;

  // --- Raccourcis de lecture (la fiche est souvent utilisée pour l'en-tête) --
  String get nom => resume.nom;
  String? get slug => resume.slug;
  String get typeLibelle => resume.typeLibelle;
  String? get telephone => resume.telephone;
  String? get whatsapp => resume.whatsapp;
  String? get logoUrl => resume.logoUrl;
  String? get photoUrl => resume.photoUrl;
  bool get aPosition => resume.aPosition;
  String? get distanceLibelle => resume.distanceLibelle;
  bool get localisationVerifiee => resume.localisationVerifiee;

  /// Adresse complète, pensée pour un visiteur ÉTRANGER (repère + quartier +
  /// ville), même sans numéro de rue.
  String get adresseLisible => adresseComplete(
        numero: numero,
        avenue: avenue,
        quartier: resume.quartier,
        adresse: resume.adresse,
        pointRepere: pointRepere,
        ville: resume.ville,
        pays: pays,
      );

  /// Horaires lisibles, une ligne par jour (« lun : 08:00 – 18:00 »).
  ///
  /// Le format est volontairement tolérant : un objet inattendu produit une
  /// liste vide plutôt qu'une erreur d'affichage.
  List<String> get horairesLisibles {
    final List<String> lignes = <String>[];

    final Object? jours = horaires['jours'];
    if (jours is List) {
      for (final Object? element in jours) {
        if (element is! Map) continue;
        final String jour = (element['j'] ?? element['jour'] ?? '').toString();
        final String ouverture =
            (element['o'] ?? element['ouverture'] ?? '').toString();
        final String fermeture =
            (element['f'] ?? element['fermeture'] ?? '').toString();

        if (jour.isEmpty) continue;
        if (ouverture.isEmpty && fermeture.isEmpty) {
          lignes.add('$jour : fermé');
        } else {
          lignes.add('$jour : $ouverture – $fermeture');
        }
      }
    }

    final String note = (horaires['note'] ?? '').toString().trim();
    if (note.isNotEmpty) lignes.add(note);

    return lignes;
  }

  factory BoutiquePublique.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic> brutBoutique =
        parseMap(map['boutique']) ?? <String, dynamic>{};

    final Map<String, dynamic> horaires =
        parseMap(brutBoutique['horaires']) ?? <String, dynamic>{};

    final List<Map<String, dynamic>> produits = map['produits'] is List
        ? (map['produits'] as List)
            .whereType<Map>()
            .map((Map e) => Map<String, dynamic>.from(e))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];

    return BoutiquePublique(
      resume: ResumeBoutique.fromMap(brutBoutique),
      description: parseStringOrNull(brutBoutique['description']),
      horaires: horaires,
      avenue: parseStringOrNull(brutBoutique['avenue']),
      numero: parseStringOrNull(brutBoutique['numero']),
      pointRepere: parseStringOrNull(brutBoutique['point_repere']),
      pays: parseStringOrNull(brutBoutique['pays']),
      produits: produits,
      nbProduits: parseInt(map['nb_produits'], fallback: produits.length),
      publicites: map['publicites'] is List
          ? (map['publicites'] as List)
              .whereType<Map>()
              .map((Map e) =>
                  PubliciteBiashara.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <PubliciteBiashara>[],
    );
  }
}
