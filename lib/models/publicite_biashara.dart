// lib/models/publicite_biashara.dart
//
// 🛒 MODULE 19 — PUBLICITÉS BIASHARA (PRÉPARATION COMMERCIALE).
//
// Une campagne porte TOUJOURS la mention « PUBLICITÉ ». Elle n'est jamais
// mélangée aux résultats organiques : l'application l'affiche dans un
// emplacement dédié, visuellement distinct.
//
// ⚠️ Le ciblage porte sur la VILLE choisie par le visiteur, la CATÉGORIE
//    consultée ou un RAYON autour d'un point. Il ne donne jamais accès à la
//    position d'une personne.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Statut d'une campagne dans son cycle de vie.
enum StatutPublicite {
  brouillon('brouillon', 'Brouillon'),
  soumise('soumise', 'En attente de validation'),
  active('active', 'Active'),
  pause('pause', 'En pause'),
  terminee('terminee', 'Terminée'),
  refusee('refusee', 'Refusée');

  const StatutPublicite(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutPublicite fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final StatutPublicite statut in values) {
      if (statut.code == normalise) return statut;
    }
    return StatutPublicite.brouillon;
  }

  /// Le commerçant peut-il encore la modifier ?
  bool get modifiable =>
      this == StatutPublicite.brouillon ||
      this == StatutPublicite.pause ||
      this == StatutPublicite.refusee;

  /// Campagne visible par le public ?
  bool get diffusee => this == StatutPublicite.active;
}

/// Nature du contenu promu.
enum TypeContenuPublicite {
  produit('produit', 'Un produit'),
  boutique('boutique', 'Ma boutique'),
  promotion('promotion', 'Une promotion'),
  offre('offre', 'Une offre spéciale');

  const TypeContenuPublicite(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypeContenuPublicite fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final TypeContenuPublicite t in values) {
      if (t.code == normalise) return t;
    }
    return TypeContenuPublicite.produit;
  }
}

/// Type de ciblage d'une campagne.
enum TypeCiblePublicite {
  ville('ville', 'Ville'),
  quartier('quartier', 'Quartier'),
  rayon('rayon', 'Rayon autour d\'un point'),
  categorie('categorie', 'Catégorie de produit');

  const TypeCiblePublicite(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypeCiblePublicite? fromCode(String? code) {
    if (code == null) return null;
    final String normalise = code.trim().toLowerCase();
    for (final TypeCiblePublicite t in values) {
      if (t.code == normalise) return t;
    }
    return null;
  }
}

/// Zone ou catégorie visée par une campagne.
class CiblePublicite {
  const CiblePublicite({
    required this.type,
    this.villeId,
    this.quartier,
    this.categorie,
    this.rayonKm,
    this.centreLat,
    this.centreLng,
  });

  final TypeCiblePublicite type;
  final String? villeId;
  final String? quartier;
  final String? categorie;
  final double? rayonKm;
  final double? centreLat;
  final double? centreLng;

  factory CiblePublicite.fromMap(Map<String, dynamic> map) {
    return CiblePublicite(
      type: TypeCiblePublicite.fromCode(parseStringOrNull(map['type_cible'])) ??
          TypeCiblePublicite.ville,
      villeId: parseStringOrNull(map['ville_id']),
      quartier: parseStringOrNull(map['quartier']),
      categorie: parseStringOrNull(map['categorie']),
      rayonKm: parseDoubleOrNull(map['rayon_km']),
      centreLat: parseDoubleOrNull(map['centre_lat']),
      centreLng: parseDoubleOrNull(map['centre_lng']),
    );
  }

  /// Représentation envoyée au serveur.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'type_cible': type.code,
        'ville_id': villeId,
        'quartier': quartier,
        'categorie': categorie,
        'rayon_km': rayonKm,
        'centre_lat': centreLat,
        'centre_lng': centreLng,
      };

  /// Libellé lisible (« Ville : Lubumbashi », « Rayon de 5 km »…).
  String get libelle {
    switch (type) {
      case TypeCiblePublicite.ville:
        return 'Ville : ${villeId ?? '—'}';
      case TypeCiblePublicite.quartier:
        return 'Quartier : ${quartier ?? '—'}';
      case TypeCiblePublicite.categorie:
        return 'Catégorie : ${categorie ?? '—'}';
      case TypeCiblePublicite.rayon:
        final String rayon =
            rayonKm == null ? '—' : '${rayonKm!.toStringAsFixed(0)} km';
        return 'Rayon de $rayon';
    }
  }
}

/// Campagne publicitaire (vue commerçant ET emplacement publicitaire public).
class PubliciteBiashara {
  const PubliciteBiashara({
    required this.id,
    required this.titre,
    this.message,
    this.mention = 'PUBLICITÉ',
    this.typeContenu = TypeContenuPublicite.produit,
    this.produitId,
    this.publicationId,
    this.imageUrl,
    this.prixPromo,
    this.dateDebut,
    this.dateFin,
    this.budget,
    this.plafondImpressions,
    this.statut = StatutPublicite.brouillon,
    this.impressions = 0,
    this.clics = 0,
    this.conversions = 0,
    this.noteModeration,
    this.espaceId,
    this.boutiqueNom,
    this.boutiqueSlug,
    this.quartier,
    this.ville,
    this.cibles = const <CiblePublicite>[],
    this.createdAt,
  });

  final String id;
  final String titre;
  final String? message;

  /// Mention légale/éthique : toujours affichée.
  final String mention;

  final TypeContenuPublicite typeContenu;
  final int? produitId;
  final String? publicationId;
  final String? imageUrl;
  final double? prixPromo;
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final double? budget;
  final int? plafondImpressions;
  final StatutPublicite statut;
  final int impressions;
  final int clics;
  final int conversions;
  final String? noteModeration;
  final String? espaceId;
  final String? boutiqueNom;
  final String? boutiqueSlug;
  final String? quartier;
  final String? ville;
  final List<CiblePublicite> cibles;
  final DateTime? createdAt;

  /// Cible de la campagne principale (« Ville : … »). `null` = tous publics.
  String get ciblageLisible {
    if (cibles.isEmpty) return 'Toute la plateforme';
    return cibles.map((CiblePublicite c) => c.libelle).join(' · ');
  }

  /// Taux de clic (clics / impressions), en pourcentage arrondi.
  int? get tauxClic {
    if (impressions <= 0) return null;
    return ((clics / impressions) * 1000 / 10).round();
  }

  /// Campagne encore dans les dates prévues ?
  bool get dansLesDates {
    final DateTime maintenant = DateTime.now();
    if (dateDebut != null && maintenant.isBefore(dateDebut!)) return false;
    if (dateFin != null && maintenant.isAfter(dateFin!)) return false;
    return true;
  }

  /// Chemin public à ouvrir quand un visiteur touche l'annonce.
  String? get cheminPublic {
    if (publicationId != null && publicationId!.isNotEmpty) {
      return '/biashara/produit/$publicationId';
    }
    if (boutiqueSlug != null && boutiqueSlug!.isNotEmpty) {
      return '/biashara/boutique/$boutiqueSlug';
    }
    return null;
  }

  factory PubliciteBiashara.fromMap(Map<String, dynamic> map) {
    return PubliciteBiashara(
      id: parseString(map['id']),
      titre: parseString(map['titre']),
      message: parseStringOrNull(map['message']),
      mention: parseString(map['mention'], fallback: 'PUBLICITÉ'),
      typeContenu:
          TypeContenuPublicite.fromCode(parseStringOrNull(map['type_contenu'])),
      produitId: map['produit_id'] == null ? null : parseInt(map['produit_id']),
      publicationId: parseStringOrNull(map['publication_id']),
      imageUrl: parseStringOrNull(map['image_url']),
      prixPromo: parseDoubleOrNull(map['prix_promo']),
      dateDebut: parseDateTimeOrNull(map['date_debut']),
      dateFin: parseDateTimeOrNull(map['date_fin']),
      budget: parseDoubleOrNull(map['budget']),
      plafondImpressions: map['plafond_impressions'] == null
          ? null
          : parseInt(map['plafond_impressions']),
      statut: StatutPublicite.fromCode(parseStringOrNull(map['statut'])),
      impressions: parseInt(map['impressions']),
      clics: parseInt(map['clics']),
      conversions: parseInt(map['conversions']),
      noteModeration: parseStringOrNull(map['note_moderation']),
      espaceId: parseStringOrNull(map['espace_id']),
      boutiqueNom: parseStringOrNull(map['boutique_nom']),
      boutiqueSlug: parseStringOrNull(map['boutique_slug']),
      quartier: parseStringOrNull(map['quartier']),
      ville: parseStringOrNull(map['ville']),
      cibles: map['cibles'] is List
          ? (map['cibles'] as List)
              .whereType<Map>()
              .map((Map e) =>
                  CiblePublicite.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <CiblePublicite>[],
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }
}
