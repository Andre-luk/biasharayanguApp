// lib/models/espace.dart
//
// MODULE 15 — PACK AVANCÉ MULTI-ENTREPRISES.
//
// Un « espace » est une entreprise du compte client : boutique, hôtel,
// pharmacie… Toutes les données métier sont cloisonnées par espace (côté
// serveur : `mon_proprietaire()` renvoie l'espace actif — migration 19).
//
// L'espace par défaut porte l'UUID du patron : c'est la compatibilité avec
// toutes les données existantes (aucune réécriture).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Type d'activité d'une entreprise (affichage + filtre).
///
/// 🧩 MODULE 16/17 — la liste reprend les profils seedés du référentiel
/// `types_espaces_modules` (l'Expert peut en créer d'autres : les codes
/// inconnus retombent sur [autre], les modules de l'application suivant, eux,
/// toujours le référentiel côté serveur).
enum TypeEspace {
  boutique('boutique', 'Boutique'),
  depot('depot', 'Dépôt / Entrepôt'),
  hotel('hotel', 'Hôtel'),
  pharmacie('pharmacie', 'Pharmacie'),
  restaurant('restaurant', 'Restaurant'),
  salleFetes('salle_fetes', 'Salle des fêtes'),
  boulangerie('boulangerie', 'Boulangerie'),
  boucherie('boucherie', 'Boucherie'),
  mode('mode', 'Mode & vêtements'),
  salon('salon_de_coiffure', 'Salon de coiffure'),
  autre('autre', 'Autre activité');

  const TypeEspace(this.code, this.libelle);

  /// Valeur stockée dans `public.espaces.type`.
  final String code;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// Convertit un code SQL en type applicatif ([autre] si inconnu).
  static TypeEspace fromCode(String? code) {
    if (code == null) return TypeEspace.autre;

    final String normalise = code.trim().toLowerCase();
    for (final TypeEspace type in values) {
      if (type.code == normalise) return type;
    }
    return TypeEspace.autre;
  }
}

/// Entreprise (point de vente) d'un compte client.
class Espace {
  const Espace({
    required this.id,
    required this.nom,
    this.type = TypeEspace.boutique,
    this.typeCode,
    this.actif = true,
    this.estActif = false,
    this.createdAt,
  });

  final String id;
  final String nom;
  final TypeEspace type;

  /// 🧩 MODULE 17 — code BRUT du type (`espaces.type`) : conserve les
  /// catégories créées par l'Expert (ex. `salon_de_coiffure`) que l'énuméré
  /// ne connaît pas encore. `null` → repli sur [type].code.
  final String? typeCode;

  /// `false` = entreprise désactivée (n'apparaît plus dans le sélecteur).
  final bool actif;

  /// `true` si c'est l'entreprise actuellement sélectionnée.
  final bool estActif;

  final DateTime? createdAt;

  /// Code à envoyer au serveur pour cette entreprise.
  String get codeType =>
      (typeCode != null && typeCode!.trim().isNotEmpty)
          ? typeCode!.trim()
          : type.code;

  factory Espace.fromMap(Map<String, dynamic> map) {
    final String? brut = parseStringOrNull(map['type']);

    return Espace(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      type: TypeEspace.fromCode(brut),
      typeCode: brut,
      actif: map['actif'] == null ? true : map['actif'] == true,
      estActif: map['est_actif'] == true,
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }

  Espace copyWith({bool? estActif}) {
    return Espace(
      id: id,
      nom: nom,
      type: type,
      typeCode: typeCode,
      actif: actif,
      estActif: estActif ?? this.estActif,
      createdAt: createdAt,
    );
  }
}

/// Raison pour laquelle la création d'une entreprise est bloquée.
enum RaisonBlocageCreation {
  role('role', "Seul le propriétaire du compte peut créer une entreprise."),
  quota('quota',
      'Votre pack a atteint sa limite : passez au pack multi-entreprises pour ajouter une boutique, un hôtel ou une pharmacie.'),
  aucuneEntreprise('aucune_entreprise',
      "Créez d'abord votre entreprise principale pour pouvoir en ajouter d'autres.");

  const RaisonBlocageCreation(this.code, this.message);

  final String code;
  final String message;

  static RaisonBlocageCreation? fromCode(String? code) {
    if (code == null) return null;

    for (final RaisonBlocageCreation raison in values) {
      if (raison.code == code) return raison;
    }
    return null;
  }
}

/// État complet renvoyé par `rpc_espaces_lister` : entreprises du compte,
/// entreprise active, quota du pack et droit de création.
class EtatEspaces {
  const EtatEspaces({
    this.espaces = const <Espace>[],
    this.actifId,
    this.maxEspaces = 1,
    this.role,
    this.peutCreer = false,
    this.raison,
  });

  final List<Espace> espaces;
  final String? actifId;

  /// Nombre d'entreprises autorisées par la grille tarifaire.
  final int maxEspaces;

  /// Rôle de l'utilisateur connecté (code SQL).
  final String? role;

  final bool peutCreer;
  final RaisonBlocageCreation? raison;

  /// Entreprise actuellement active (`null` si le compte n'en a aucune).
  Espace? get actif {
    for (final Espace espace in espaces) {
      if (espace.id == actifId) return espace;
    }
    for (final Espace espace in espaces) {
      if (espace.estActif) return espace;
    }
    return espaces.isEmpty ? null : espaces.first;
  }

  /// Le compte gère-t-il plusieurs entreprises ?
  bool get multiEntreprises => espaces.length > 1;

  /// Le pack autorise-t-il plusieurs entreprises (même si une seule existe) ?
  bool get packMulti => maxEspaces > 1;

  /// Places restantes dans le pack (jamais négatif).
  int get placesRestantes {
    final int restantes = maxEspaces - espaces.length;
    return restantes < 0 ? 0 : restantes;
  }

  factory EtatEspaces.fromMap(Map<String, dynamic> map) {
    final int max = parseInt(map['max_espaces'], fallback: 1);

    return EtatEspaces(
      espaces: (map['espaces'] is List)
          ? (map['espaces'] as List)
              .whereType<Map>()
              .map((Map element) =>
                  Espace.fromMap(Map<String, dynamic>.from(element)))
              .toList(growable: false)
          : const <Espace>[],
      actifId: parseStringOrNull(map['actif_id']),
      maxEspaces: max < 1 ? 1 : max,
      role: parseStringOrNull(map['role']),
      peutCreer: map['peut_creer'] == true,
      raison: RaisonBlocageCreation.fromCode(parseStringOrNull(map['raison'])),
    );
  }

  /// Version « chargée » après une bascule locale (sans rappeler le serveur).
  EtatEspaces avecActif(String espaceId) {
    return EtatEspaces(
      espaces: espaces
          .map((Espace e) => e.copyWith(estActif: e.id == espaceId))
          .toList(growable: false),
      actifId: espaceId,
      maxEspaces: maxEspaces,
      role: role,
      peutCreer: peutCreer,
      raison: raison,
    );
  }
}
