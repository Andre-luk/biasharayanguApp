// lib/models/admin_plateforme.dart
//
// 🛡️ MODULE 20 — ADMINISTRATION PLATEFORME.
//
// Modèles des trois écrans d'administration ajoutés par l'audit final :
//   • le PARC DES BOUTIQUES (espaces de toutes les entreprises) ;
//   • la MODÉRATION DU CATALOGUE PUBLIC (produits publiés) ;
//   • la SUPPRESSION SÛRE D'UN UTILISATEUR (diagnostic des dépendances).
//
// Ces modèles sont volontairement sans dépendance Flutter : ils sont testables
// sans binding, comme le reste des modèles du projet.

import 'package:biashara_yangu/utils/json_parsing.dart';

// ============================================================================
//  1. PARC DES BOUTIQUES
// ============================================================================

/// Une boutique (espace) vue par l'administration de la plateforme.
class EspaceAdmin {
  const EspaceAdmin({
    required this.espaceId,
    required this.nom,
    this.type,
    this.actif = true,
    this.visiblePubliquement = false,
    this.statutLocalisation = 'non_renseignee',
    this.ville,
    this.quartier,
    this.entrepriseId,
    this.entreprise,
    this.entrepriseStatut,
    this.activationEtape,
    this.nbProduits = 0,
    this.nbProduitsPublies = 0,
    this.latitude,
    this.longitude,
  });

  final String espaceId;
  final String nom;

  /// Type d'espace : boutique, hôtel, restaurant, pharmacie, salle…
  final String? type;

  /// Le commerçant peut utiliser la boutique.
  final bool actif;

  /// La boutique apparaît dans le catalogue public (opt-in du commerçant).
  final bool visiblePubliquement;

  /// `non_renseignee` | `a_verifier` | `verifiee`.
  final String statutLocalisation;

  final String? ville;
  final String? quartier;
  final String? entrepriseId;

  /// Nom de l'entreprise propriétaire.
  final String? entreprise;

  /// Statut de l'entreprise : ACTIF, SUSPENDU…
  final String? entrepriseStatut;

  /// Étape du dossier d'activation (module 14).
  final String? activationEtape;

  final int nbProduits;
  final int nbProduitsPublies;

  final double? latitude;
  final double? longitude;

  /// La localisation a-t-elle été confirmée par le commerçant ?
  bool get localisationVerifiee => statutLocalisation == 'verifiee';

  /// Position connue ? Sans position, la boutique ne peut pas être « proche ».
  bool get geolocalisee => latitude != null && longitude != null;

  /// La boutique est-elle RÉELLEMENT visible du public ?
  ///
  /// L'opt-in seul ne suffit pas : le dossier d'activation doit être accepté.
  /// C'est exactement la règle appliquée par la vue `v_biashara_boutiques`,
  /// reformulée ici pour que l'administration voie la vérité du terrain.
  bool get visibleEffectivement {
    if (!actif || !visiblePubliquement || !geolocalisee) return false;
    final String etape = (activationEtape ?? 'actif').toLowerCase();
    if (etape == 'rejete') return false;
    if ((entrepriseStatut ?? '').toUpperCase() == 'SUSPENDU') return false;
    return true;
  }

  /// Raison lisible de l'invisibilité — jamais de message technique.
  String get raisonInvisibilite {
    if (visibleEffectivement) return 'Visible dans le catalogue public';
    if (!actif) return 'Boutique désactivée par la plateforme';
    if (!visiblePubliquement) return 'Le commerçant n\'a pas publié sa vitrine';
    if (!geolocalisee) return 'Position non renseignée';
    final String etape = (activationEtape ?? '').toLowerCase();
    if (etape == 'rejete') return 'Dossier d\'activation rejeté';
    if ((entrepriseStatut ?? '').toUpperCase() == 'SUSPENDU') {
      return 'Entreprise suspendue';
    }
    return 'En attente de validation';
  }

  /// Libellé court du type d'espace, prêt à afficher.
  String get typeLisible {
    final String brut = (type ?? 'boutique').trim();
    if (brut.isEmpty) return 'Boutique';
    return brut[0].toUpperCase() + brut.substring(1);
  }

  /// Adresse condensée : quartier puis ville (ce qu'un visiteur reconnaît).
  String get localisationCourte {
    final List<String> morceaux = <String>[
      if ((quartier ?? '').trim().isNotEmpty) quartier!.trim(),
      if ((ville ?? '').trim().isNotEmpty) ville!.trim(),
    ];
    return morceaux.isEmpty ? 'Localisation non renseignée' : morceaux.join(' · ');
  }

  factory EspaceAdmin.fromMap(Map<String, dynamic> map) {
    return EspaceAdmin(
      espaceId: parseString(map['espace_id']),
      nom: parseString(map['nom']),
      type: parseStringOrNull(map['type']),
      actif: map['actif'] != false,
      visiblePubliquement: map['visible_publiquement'] == true,
      statutLocalisation:
          parseString(map['statut_localisation'], fallback: 'non_renseignee'),
      ville: parseStringOrNull(map['ville']),
      quartier: parseStringOrNull(map['quartier']),
      entrepriseId: parseStringOrNull(map['entreprises_id']),
      entreprise: parseStringOrNull(map['entreprise']),
      entrepriseStatut: parseStringOrNull(map['entreprise_statut']),
      activationEtape: parseStringOrNull(map['activation_etape']),
      nbProduits: parseInt(map['nb_produits']),
      nbProduitsPublies: parseInt(map['nb_produits_publies']),
      latitude: parseDoubleOrNull(map['latitude']),
      longitude: parseDoubleOrNull(map['longitude']),
    );
  }
}

/// Compteurs globaux du parc des boutiques.
class ResumeParcEspaces {
  const ResumeParcEspaces({
    this.espaces = 0,
    this.actifs = 0,
    this.visibles = 0,
  });

  final int espaces;
  final int actifs;
  final int visibles;

  static const ResumeParcEspaces vide = ResumeParcEspaces();

  /// Espaces désactivés (calculé, jamais renvoyé par le serveur).
  int get inactifs => (espaces - actifs).clamp(0, espaces);

  factory ResumeParcEspaces.fromMap(Map<String, dynamic>? map) {
    if (map == null) return vide;
    return ResumeParcEspaces(
      espaces: parseInt(map['espaces']),
      actifs: parseInt(map['actifs']),
      visibles: parseInt(map['visibles']),
    );
  }
}

// ============================================================================
//  2. MODÉRATION DU CATALOGUE PUBLIC
// ============================================================================

/// Un article publié (ou retiré) du catalogue public, vu par la plateforme.
class PublicationAdmin {
  const PublicationAdmin({
    required this.publicationId,
    required this.produitId,
    required this.nom,
    this.categorie,
    this.prix = 0,
    this.unite,
    this.photo,
    this.publie = true,
    this.disponible = true,
    this.espaceId,
    this.boutique,
    this.boutiqueSlug,
    this.ville,
    this.moderationNote,
    this.moderationLe,
    this.misAJourLe,
  });

  final String publicationId;
  final int produitId;
  final String nom;
  final String? categorie;
  final double prix;
  final String? unite;
  final String? photo;

  /// Publié dans le catalogue public.
  final bool publie;

  /// Disponibilité annoncée par le commerçant.
  final bool disponible;

  final String? espaceId;
  final String? boutique;
  final String? boutiqueSlug;
  final String? ville;

  /// Motif de la dernière décision de modération (visible du commerçant).
  final String? moderationNote;
  final DateTime? moderationLe;
  final DateTime? misAJourLe;

  /// Cet article a-t-il déjà été modéré par la plateforme ?
  bool get dejaModere => moderationLe != null;

  /// Retiré par la plateforme (et non par le commerçant) ?
  bool get retireParPlateforme => !publie && dejaModere;

  factory PublicationAdmin.fromMap(Map<String, dynamic> map) {
    return PublicationAdmin(
      publicationId: parseString(map['publication_id']),
      produitId: parseInt(map['produit_id']),
      nom: parseString(map['nom']),
      categorie: parseStringOrNull(map['categorie']),
      prix: parseDouble(map['prix']),
      unite: parseStringOrNull(map['unite']),
      photo: parseStringOrNull(map['photo']),
      publie: map['publie'] == true,
      disponible: map['disponible'] == true,
      espaceId: parseStringOrNull(map['espace_id']),
      boutique: parseStringOrNull(map['boutique']),
      boutiqueSlug: parseStringOrNull(map['boutique_slug']),
      ville: parseStringOrNull(map['ville']),
      moderationNote: parseStringOrNull(map['moderation_note']),
      moderationLe: parseDateTimeOrNull(map['moderation_le']),
      misAJourLe: parseDateTimeOrNull(map['mis_a_jour_le']),
    );
  }
}

/// Compteurs du catalogue public modéré.
class ResumePublications {
  const ResumePublications({
    this.publications = 0,
    this.publiees = 0,
    this.retirees = 0,
  });

  final int publications;
  final int publiees;
  final int retirees;

  static const ResumePublications vide = ResumePublications();

  factory ResumePublications.fromMap(Map<String, dynamic>? map) {
    if (map == null) return vide;
    return ResumePublications(
      publications: parseInt(map['publications']),
      publiees: parseInt(map['publiees']),
      retirees: parseInt(map['retirees']),
    );
  }
}

// ============================================================================
//  3. SUPPRESSION SÛRE D'UN UTILISATEUR
// ============================================================================

/// Stratégie de retrait d'un compte, du plus prudent au plus radical.
///
/// Une vente, un paiement, une dette ou une ligne d'audit ne doivent JAMAIS
/// disparaître parce qu'un collaborateur quitte l'entreprise.
enum StrategieSuppression {
  /// Le compte ne peut plus se connecter — réversible, aucune donnée touchée.
  desactivation('desactivation', 'Désactivation',
      'Le compte ne peut plus se connecter. Toutes les données restent intactes et l\'opération est réversible.'),

  /// Désactivation + effacement de l'identité (les historiques restent).
  anonymisation('anonymisation', 'Anonymisation',
      'L\'identité est effacée (« Compte supprimé ») mais les ventes, paiements et audits restent traçables.'),

  /// Suppression réelle, réservée aux comptes sans aucune attache.
  suppression('suppression', 'Suppression réelle',
      'Le compte est effacé définitivement. Uniquement possible si le compte ne porte aucune donnée.'),

  /// 🧹 MODULE 21 — Purge totale : le compte ET toutes ses données.
  ///
  /// Contrairement à [suppression], cette stratégie ne recule devant aucune
  /// attache : elle efface aussi les ventes, paiements, dettes, stock et
  /// traces d'audit du compte. Réservée au **Super Admin**, avec recopie de
  /// l'adresse e-mail du compte comme confirmation explicite.
  purge('purge', 'Purge totale (compte + données)',
      'Le compte et TOUTES ses données sont effacés : ventes, paiements, dettes, stock, audits. Irréversible — réservé au Super Admin, confirmation par l\'adresse e-mail.');

  const StrategieSuppression(this.code, this.libelle, this.description);

  final String code;
  final String libelle;
  final String description;

  static StrategieSuppression? depuisCode(String? code) {
    final String brut = (code ?? '').trim().toLowerCase();
    for (final StrategieSuppression s in StrategieSuppression.values) {
      if (s.code == brut) return s;
    }
    return null;
  }
}

/// Diagnostic des dépendances d'un utilisateur AVANT toute suppression.
class DependancesUtilisateur {
  const DependancesUtilisateur({
    required this.utilisateurId,
    this.entrepriseId,
    this.estPatron = false,
    this.nbEspaces = 0,
    this.nbCollaborateurs = 0,
    this.totalDonnees = 0,
    this.detail = const <String, int>{},
    this.suppressionPossible = false,
    this.anonymisationPossible = true,
    this.recommandation,
  });

  final String utilisateurId;
  final String? entrepriseId;

  /// L'utilisateur est-il le propriétaire de l'entreprise ?
  final bool estPatron;

  final int nbEspaces;
  final int nbCollaborateurs;

  /// Nombre total de lignes de gestion rattachées (`owner_id`).
  final int totalDonnees;

  /// Détail par table — sert à MONTRER l'impact, pas seulement à le calculer.
  final Map<String, int> detail;

  final bool suppressionPossible;
  final bool anonymisationPossible;

  /// Stratégie conseillée par le serveur (source unique de vérité).
  final StrategieSuppression? recommandation;

  /// Libellés lisibles des tables impactées, triés par volume décroissant.
  List<MapEntry<String, int>> get detailTrie {
    final List<MapEntry<String, int>> entrees = detail.entries.toList();
    entrees.sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
        b.value.compareTo(a.value));
    return entrees;
  }

  /// Une suppression réelle est-elle réellement sans danger ?
  bool get sansImpact => totalDonnees == 0 && nbEspaces == 0 && nbCollaborateurs == 0;

  factory DependancesUtilisateur.fromMap(Map<String, dynamic> map) {
    final Map<String, int> detail = <String, int>{};
    final Map<String, dynamic>? brut = parseMap(map['detail']);
    brut?.forEach((String cle, dynamic valeur) {
      if (valeur is num) {
        detail[cle] = valeur.toInt();
      } else {
        detail[cle] = parseInt(valeur);
      }
    });

    return DependancesUtilisateur(
      utilisateurId: parseString(map['utilisateur_id']),
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      estPatron: map['est_patron'] == true,
      nbEspaces: parseInt(map['nb_espaces']),
      nbCollaborateurs: parseInt(map['nb_collaborateurs']),
      totalDonnees: parseInt(map['total_donnees']),
      detail: Map<String, int>.unmodifiable(detail),
      suppressionPossible: map['suppression_possible'] == true,
      anonymisationPossible: map['anonymisation_possible'] != false,
      recommandation: StrategieSuppression.depuisCode(
          parseStringOrNull(map['recommandation'])),
    );
  }
}
