// lib/models/visibilite_biashara.dart
//
// 🛒 MODULE 19 — « MA VISIBILITÉ BIASHARA ».
//
// Le commerçant doit comprendre ce que Biashara lui apporte. Le modèle
// distingue QUATRE niveaux, du plus faible au plus fort engagement :
//
//   1. VISIBILITÉ — l'article/la boutique a été AFFICHÉ (impression) ;
//   2. INTÉRÊT     — la fiche a été CONSULTÉE, partagée ou cliquée ;
//   3. INTENTION   — la personne a demandé l'ITINÉRAIRE, a APPELÉ ou a
//                    écrit sur WhatsApp ;
//   4. CONVERSION  — un achat a été RÉELLEMENT attribué à Biashara.
//
// ⚠️ Une consultation n'est JAMAIS comptée comme un achat : la conversion
//    n'apparaît que lorsqu'un code/QR/lien d'attribution a été utilisé.

import 'package:biashara_yangu/models/produit_public.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Niveau d'engagement d'un événement analytique.
enum CategorieEvenement {
  visibilite('visibilite', 'Visibilité', 'Affichages dans les résultats'),
  interet('interet', 'Intérêt', 'Fiches consultées, partages, clics'),
  intention('intention', 'Intention', 'Itinéraire, appel, WhatsApp'),
  conversion('conversion', 'Conversion', 'Achats réellement attribués'),
  autre('autre', 'Autre', 'Non classé');

  const CategorieEvenement(this.code, this.libelle, this.description);

  final String code;
  final String libelle;
  final String description;

  static CategorieEvenement fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final CategorieEvenement c in values) {
      if (c.code == normalise) return c;
    }
    return CategorieEvenement.autre;
  }
}

/// Libellés français des types d'événements (miroir du serveur).
const Map<String, String> libellesEvenements = <String, String>{
  'impression_produit': 'Produit affiché dans une recherche',
  'impression_boutique': 'Boutique affichée',
  'impression_publicite': 'Publicité affichée',
  'recherche': 'Recherche ayant trouvé la boutique',
  'vue_produit': 'Fiche produit consultée',
  'vue_boutique': 'Fiche boutique consultée',
  'partage': 'Fiche partagée',
  'clic_publicite': 'Publicité cliquée',
  'clic_itineraire': 'Itinéraire demandé',
  'clic_telephone': 'Appel lancé',
  'clic_whatsapp': 'WhatsApp ouvert',
  'clic_site': 'Site ou lien ouvert',
  'conversion': 'Achat attribué à Biashara',
};

/// Libellé lisible d'un type d'événement.
String libelleEvenement(String type) =>
    libellesEvenements[type] ?? type.replaceAll('_', ' ');

/// Compteurs des quatre niveaux (le « résumé » du tableau de bord).
class ResumeVisibilite {
  const ResumeVisibilite({
    this.visibilite = 0,
    this.interet = 0,
    this.intention = 0,
    this.conversion = 0,
    this.total = 0,
  });

  final int visibilite;
  final int interet;
  final int intention;
  final int conversion;
  final int total;

  factory ResumeVisibilite.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ResumeVisibilite();
    return ResumeVisibilite(
      visibilite: parseInt(map['visibilite']),
      interet: parseInt(map['interet']),
      intention: parseInt(map['intention']),
      conversion: parseInt(map['conversion']),
      total: parseInt(map['total']),
    );
  }

  /// Compteur d'un niveau (utilisé par les cartes du tableau de bord).
  int pour(CategorieEvenement categorie) {
    switch (categorie) {
      case CategorieEvenement.visibilite:
        return visibilite;
      case CategorieEvenement.interet:
        return interet;
      case CategorieEvenement.intention:
        return intention;
      case CategorieEvenement.conversion:
        return conversion;
      case CategorieEvenement.autre:
        return total - (visibilite + interet + intention + conversion);
    }
  }

  /// Taux d'intérêt (vues / affichages), en pourcentage arrondi.
  int? get tauxInteret {
    if (visibilite <= 0) return null;
    return ((interet / visibilite) * 100).round();
  }

  /// Taux d'intention (itinéraires/appels / affichages), en pourcentage.
  int? get tauxIntention {
    if (visibilite <= 0) return null;
    return ((intention / visibilite) * 100).round();
  }
}

/// Compteur d'un type d'événement.
class CompteurEvenement {
  const CompteurEvenement({
    required this.typeEvenement,
    required this.categorie,
    required this.nb,
  });

  final String typeEvenement;
  final CategorieEvenement categorie;
  final int nb;

  String get libelle => libelleEvenement(typeEvenement);

  factory CompteurEvenement.fromMap(Map<String, dynamic> map) {
    return CompteurEvenement(
      typeEvenement: parseString(map['type_evenement']),
      categorie: CategorieEvenement.fromCode(parseStringOrNull(map['categorie'])),
      nb: parseInt(map['nb']),
    );
  }
}

/// Une journée de la courbe d'évolution.
class JourVisibilite {
  const JourVisibilite({
    required this.jour,
    this.visibilite = 0,
    this.interet = 0,
    this.intention = 0,
    this.conversion = 0,
  });

  final DateTime jour;
  final int visibilite;
  final int interet;
  final int intention;
  final int conversion;

  int get total => visibilite + interet + intention + conversion;

  factory JourVisibilite.fromMap(Map<String, dynamic> map) {
    return JourVisibilite(
      jour: parseDateTimeOrNull(map['jour']) ?? DateTime.now(),
      visibilite: parseInt(map['visibilite']),
      interet: parseInt(map['interet']),
      intention: parseInt(map['intention']),
      conversion: parseInt(map['conversion']),
    );
  }
}

/// Produit mis en avant dans le tableau de bord (vues + intentions).
class ProduitVisible {
  const ProduitVisible({
    required this.entiteId,
    required this.nom,
    this.vues = 0,
    this.itineraire = 0,
    this.telephone = 0,
    this.whatsapp = 0,
    this.total = 0,
  });

  final String entiteId;
  final String nom;
  final int vues;
  final int itineraire;
  final int telephone;
  final int whatsapp;
  final int total;

  factory ProduitVisible.fromMap(Map<String, dynamic> map) {
    return ProduitVisible(
      entiteId: parseString(map['entite_id']),
      nom: parseString(map['nom']),
      vues: parseInt(map['vues']),
      itineraire: parseInt(map['itineraire']),
      telephone: parseInt(map['telephone']),
      whatsapp: parseInt(map['whatsapp']),
      total: parseInt(map['total']),
    );
  }
}

/// Données complètes du tableau de bord « Ma visibilité Biashara ».
class VisibiliteBiashara {
  const VisibiliteBiashara({
    this.debut,
    this.fin,
    this.resume = const ResumeVisibilite(),
    this.parType = const <CompteurEvenement>[],
    this.parJour = const <JourVisibilite>[],
    this.topProduits = const <ProduitVisible>[],
    this.nbRecherches = 0,
    this.publicites = const <Map<String, dynamic>>[],
    this.noteConversion,
  });

  final DateTime? debut;
  final DateTime? fin;
  final ResumeVisibilite resume;
  final List<CompteurEvenement> parType;
  final List<JourVisibilite> parJour;
  final List<ProduitVisible> topProduits;

  /// Nombre de recherches distinctes qui ont fait apparaître un article de la
  /// boutique (mesure honnête : on compte la recherche, pas la personne).
  final int nbRecherches;

  final List<Map<String, dynamic>> publicites;

  /// Rappel envoyé par le serveur : la conversion n'est comptée que si elle est
  /// réellement attribuée.
  final String? noteConversion;

  bool get vide => resume.total == 0;

  factory VisibiliteBiashara.fromMap(Map<String, dynamic> map) {
    return VisibiliteBiashara(
      debut: parseDateTimeOrNull(map['debut']),
      fin: parseDateTimeOrNull(map['fin']),
      resume: ResumeVisibilite.fromMap(parseMap(map['resume'])),
      parType: map['par_type'] is List
          ? (map['par_type'] as List)
              .whereType<Map>()
              .map((Map e) =>
                  CompteurEvenement.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <CompteurEvenement>[],
      parJour: map['par_jour'] is List
          ? (map['par_jour'] as List)
              .whereType<Map>()
              .map((Map e) =>
                  JourVisibilite.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <JourVisibilite>[],
      topProduits: map['top_produits'] is List
          ? (map['top_produits'] as List)
              .whereType<Map>()
              .map((Map e) =>
                  ProduitVisible.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <ProduitVisible>[],
      nbRecherches: parseInt(map['nb_recherches']),
      publicites: map['publicites'] is List
          ? (map['publicites'] as List)
              .whereType<Map>()
              .map((Map e) => Map<String, dynamic>.from(e))
              .toList(growable: false)
          : const <Map<String, dynamic>>[],
      noteConversion: parseStringOrNull(map['note_conversion']),
    );
  }

  /// Comparaison de la période courante avec la précédente (évolution).
  ///
  /// Purement calculatoire et testable : c'est la seule façon d'afficher une
  /// « évolution de la visibilité » honnête sans nouvel appel réseau.
  int? evolutionPourcent(int actuel, int precedent) {
    if (precedent <= 0) return actuel > 0 ? 100 : null;
    return (((actuel - precedent) / precedent) * 100).round();
  }
}

/// Rappel : `ProduitPublic` est réutilisé pour la comparaison de prix.
typedef Comparaison = ComparaisonPrix;
