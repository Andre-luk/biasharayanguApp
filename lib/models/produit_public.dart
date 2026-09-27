// lib/models/produit_public.dart
//
// 🛒 MODULE 19 — PRODUITS DU CATALOGUE PUBLIC & RÉSULTAT DE RECHERCHE.
//
// Un [ProduitPublic] est TOUJOURS accompagné de sa boutique : le visiteur doit
// comprendre immédiatement « Produit → Prix → Boutique → Distance », qui est
// la promesse centrale du module.
//
// ⚠️ Un résultat de recherche ne contient JAMAIS de stock exact, de prix
//    d'achat ni de marge : uniquement un booléen de disponibilité.

import 'package:biashara_yangu/models/boutique_publique.dart';
import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/utils/geo_utils.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Critère de tri proposé au visiteur (page de résultats).
///
/// La proximité occupe une place importante par défaut, mais le visiteur peut
/// toujours choisir « Prix le plus bas » : le produit le moins cher n'est pas
/// présenté d'office comme le meilleur choix.
enum TriRecherche {
  pertinence('pertinence', 'Pertinence', 'Les plus pertinents d\'abord'),
  distance('distance', 'Plus proche', 'Les boutiques les plus proches'),
  prix('prix', 'Prix le plus bas', 'Du moins cher au plus cher');

  const TriRecherche(this.code, this.libelle, this.description);

  final String code;
  final String libelle;
  final String description;

  static TriRecherche fromCode(String? code) {
    if (code == null) return TriRecherche.pertinence;
    final String normalise = code.trim().toLowerCase();
    for (final TriRecherche tri in values) {
      if (tri.code == normalise) return tri;
    }
    return TriRecherche.pertinence;
  }
}

/// Un article du catalogue public, avec la boutique qui le vend.
class ProduitPublic {
  const ProduitPublic({
    required this.publicationId,
    required this.produitId,
    required this.nom,
    required this.boutique,
    this.description,
    this.photo,
    this.prix = 0,
    this.unite = 'unité',
    this.categorie,
    this.disponible = false,
    this.vendableAuPoids = false,
    this.attributs = const <String, String>{},
    this.distanceKm,
    this.score = 0,
  });

  final String publicationId;
  final int produitId;
  final String nom;
  final ResumeBoutique boutique;

  final String? description;
  final String? photo;

  /// Prix public (promotion éventuelle comprise), dans la devise de la boutique.
  final double prix;

  /// Unité de vente (« pièce », « kg », « 25 kg »…).
  final String unite;

  final String? categorie;

  /// Disponibilité DÉCLARÉE : le catalogue public ne divulgue jamais le stock
  /// exact (information commercialement sensible).
  final bool disponible;

  /// 🥩 Vente au poids (boucherie) : le client comprend que le prix est au kilo.
  final bool vendableAuPoids;

  /// 👕 Variantes (taille, couleur, marque…), vide s'il n'y en a pas.
  final Map<String, String> attributs;

  final double? distanceKm;

  /// Score de pertinence serveur (affiché nulle part : sert au contrôle).
  final double score;

  factory ProduitPublic.fromMap(Map<String, dynamic> map) {
    return ProduitPublic(
      publicationId: parseString(map['publication_id']),
      produitId: parseInt(map['produit_id']),
      nom: parseString(map['nom']),
      boutique: ResumeBoutique.fromMap(
        parseMap(map['boutique']) ?? <String, dynamic>{},
      ),
      description: parseStringOrNull(map['description']),
      photo: parseStringOrNull(map['photo']),
      prix: parseDouble(map['prix']),
      unite: parseString(map['unite'], fallback: 'unité'),
      categorie: parseStringOrNull(map['categorie']),
      disponible: map['disponible'] == true,
      vendableAuPoids: map['vendable_au_poids'] == true,
      attributs: _attributs(map['attributs']),
      distanceKm: parseDoubleOrNull(map['distance_km']),
      score: parseDouble(map['score']),
    );
  }

  static Map<String, String> _attributs(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return const <String, String>{};

    final Map<String, String> resultat = <String, String>{};
    map.forEach((String cle, dynamic v) {
      final String texte = v?.toString().trim() ?? '';
      if (texte.isNotEmpty) resultat[cle] = texte;
    });
    return resultat;
  }

  String? get distanceLibelle => formatDistance(distanceKm);

  /// Résumé des variantes (« M · Bleu »), ou `null`.
  String? get resumeVariantes {
    if (attributs.isEmpty) return null;
    return attributs.values.join(' · ');
  }

  /// « 1 500 CDF / kg » — l'unité est TOUJOURS visible à côté du prix, sinon
  /// un prix « 25 000 » ne veut rien dire pour le visiteur.
  String prixAvecUnite(String montantFormate) => '$montantFormate / $unite';

  /// Chemin public de la fiche produit.
  String get cheminPublic => '/biashara/produit/$publicationId';
}

/// Résultat complet d'une recherche publique.
class ResultatRecherchePublic {
  const ResultatRecherchePublic({
    this.texte,
    this.tri = TriRecherche.pertinence,
    this.total = 0,
    this.nbBoutiques = 0,
    this.resultats = const <ProduitPublic>[],
    this.publicites = const <PubliciteBiashara>[],
    this.rechercheId,
  });

  final String? texte;
  final TriRecherche tri;

  /// Nombre total de résultats (avant pagination).
  final int total;

  /// Nombre de boutiques distinctes proposant un résultat.
  final int nbBoutiques;

  final List<ProduitPublic> resultats;

  /// Emplacements SPONSORISÉS — volontairement SÉPARÉS des résultats
  /// organiques : jamais mélangés, toujours marqués « PUBLICITÉ ».
  final List<PubliciteBiashara> publicites;

  /// Identifiant de la recherche enregistrée (permet de rattacher, plus tard,
  /// une conversion à la recherche qui l'a provoquée).
  final int? rechercheId;

  bool get vide => resultats.isEmpty;

  factory ResultatRecherchePublic.fromMap(Map<String, dynamic> map) {
    return ResultatRecherchePublic(
      texte: parseStringOrNull(map['texte']),
      tri: TriRecherche.fromCode(parseStringOrNull(map['tri'])),
      total: parseInt(map['total']),
      nbBoutiques: parseInt(map['nb_boutiques']),
      resultats: map['resultats'] is List
          ? (map['resultats'] as List)
              .whereType<Map>()
              .map((Map e) =>
                  ProduitPublic.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <ProduitPublic>[],
      publicites: map['publicites'] is List
          ? (map['publicites'] as List)
              .whereType<Map>()
              .map((Map e) =>
                  PubliciteBiashara.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <PubliciteBiashara>[],
      rechercheId: map['recherche_id'] == null
          ? null
          : parseInt(map['recherche_id']),
    );
  }
}

/// Regroupement de comparaison de prix : plusieurs boutiques, un même produit.
class ComparaisonPrix {
  const ComparaisonPrix({required this.nom, required this.offres});

  final String nom;
  final List<ProduitPublic> offres;

  /// Prix le plus bas de la sélection.
  double? get prixMin =>
      offres.isEmpty ? null : offres.map((ProduitPublic p) => p.prix).reduce(
            (double a, double b) => a < b ? a : b,
          );

  /// Prix le plus élevé (permet d'afficher l'écart entre boutiques).
  double? get prixMax =>
      offres.isEmpty ? null : offres.map((ProduitPublic p) => p.prix).reduce(
            (double a, double b) => a > b ? a : b,
          );

  /// Écart en pourcentage entre l'offre la plus chère et la moins chère.
  int? get ecartPourcent {
    final double? min = prixMin;
    final double? max = prixMax;
    if (min == null || max == null || min <= 0 || max <= min) return null;
    return (((max - min) / min) * 100).round();
  }

  /// Distance la plus courte (utile pour la suggestion par défaut).
  double? get distanceMin {
    final List<double> distances = offres
        .where((ProduitPublic p) => p.distanceKm != null)
        .map((ProduitPublic p) => p.distanceKm!)
        .toList(growable: false);
    if (distances.isEmpty) return null;
    return distances.reduce((double a, double b) => a < b ? a : b);
  }

  /// Regroupe une liste de résultats par nom de produit normalisé.
  ///
  /// La comparaison est proposée dès que PLUSIEURS boutiques proposent un
  /// produit correspondant : c'est la promesse « comparer les prix ».
  static List<ComparaisonPrix> depuisProduits(List<ProduitPublic> produits) {
    final Map<String, List<ProduitPublic>> groupes =
        <String, List<ProduitPublic>>{};

    for (final ProduitPublic produit in produits) {
      final String cle = normaliserRecherche(produit.nom);
      groupes.putIfAbsent(cle, () => <ProduitPublic>[]).add(produit);
    }

    final List<ComparaisonPrix> resultat = groupes.entries
        .where((MapEntry<String, List<ProduitPublic>> e) => e.value.length > 1)
        .map((MapEntry<String, List<ProduitPublic>> e) {
      final List<ProduitPublic> offres = List<ProduitPublic>.from(e.value)
        ..sort((ProduitPublic a, ProduitPublic b) => a.prix.compareTo(b.prix));
      return ComparaisonPrix(
        nom: offres.first.nom,
        offres: offres,
      );
    }).toList(growable: false)
      ..sort((ComparaisonPrix a, ComparaisonPrix b) =>
          b.offres.length.compareTo(a.offres.length));

    return resultat;
  }
}
