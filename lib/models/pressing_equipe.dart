// lib/models/pressing_equipe.dart
//
// 🧺 MODULE 35 — L'ÉQUIPE DU PRESSING.
//
// Un patron de pressing ne dit pas « tu es magasinier » : il dit « tu es à
// l'atelier », « tu es à l'accueil », « tu es à la caisse ». Ces métiers ne
// sont pas décoratifs — chacun ouvre un droit différent :
//
//   • responsable : les réglages, le catalogue et les tarifs ;
//   • accueil     : prendre un dépôt, créer un client ;
//   • atelier     : faire avancer un vêtement, passer le contrôle qualité ;
//   • caisse      : encaisser et remettre un vêtement.
//
// ⚠️ Le métier est DISTINCT du rôle générique de l'application (`new_role`) :
//    le générique décide des pages visibles, le métier décide de ce qui est
//    réellement permis dans le pressing. Les deux sont vérifiés côté serveur.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Métier d'un collaborateur dans le pressing.
enum RolePressing {
  responsable(
    'responsable',
    'Responsable',
    "Réglages, catalogue et tarifs — remplace le patron.",
  ),
  accueil(
    'accueil',
    'Accueil & dépôt',
    'Reçoit les vêtements, crée les clients, imprime le reçu.',
  ),
  atelier(
    'atelier',
    'Atelier',
    'Traite les vêtements et passe le contrôle qualité.',
  ),
  caisse(
    'caisse',
    'Caisse & retrait',
    'Encaisse et remet les vêtements au client.',
  );

  const RolePressing(this.code, this.libelle, this.explication);

  /// Valeur stockée dans `utilisateurs.role_pressing`.
  final String code;

  final String libelle;
  final String explication;

  /// Réglages, catalogue et tarifs.
  bool get peutRegler => this == RolePressing.responsable;

  /// Prendre un dépôt, créer un client.
  bool get peutAccueillir =>
      this == RolePressing.responsable || this == RolePressing.accueil;

  /// Faire avancer un vêtement, contrôle qualité.
  bool get peutAtelier =>
      this == RolePressing.responsable || this == RolePressing.atelier;

  /// Encaisser et remettre un vêtement.
  bool get peutEncaisser =>
      this == RolePressing.responsable ||
      this == RolePressing.caisse ||
      this == RolePressing.accueil;

  /// Métiers proposés quand on crée un collaborateur.
  static List<RolePressing> get tous => values;

  /// Retrouve un métier depuis le serveur (`null` si absent ou inconnu).
  static RolePressing? depuisCode(String? code) {
    final String propre = (code ?? '').trim().toLowerCase();
    if (propre.isEmpty) return null;
    for (final RolePressing role in values) {
      if (role.code == propre) return role;
    }
    return null;
  }

  static String libelleDe(String? code) =>
      depuisCode(code)?.libelle ?? (code ?? '').trim();
}

/// Un collaborateur du pressing.
class CollaborateurPressing {
  const CollaborateurPressing({
    required this.id,
    required this.nom,
    this.prenom = '',
    this.email = '',
    this.telephone = '',
    this.role,
    this.actif = true,
  });

  final String id;
  final String nom;
  final String prenom;
  final String email;
  final String telephone;

  /// `null` = compte sans métier (créé avant cette version).
  final RolePressing? role;

  final bool actif;

  String get nomComplet {
    final String p = prenom.trim();
    final String n = nom.trim();
    if (p.isEmpty) return n;
    if (n.isEmpty) return p;
    return '$p $n';
  }

  String get initiales {
    final String n = nom.trim();
    final String p = prenom.trim();
    final String a = n.isEmpty ? '' : n[0];
    final String b = p.isEmpty ? '' : p[0];
    final String r = '$a$b'.toUpperCase();
    return r.isEmpty ? '?' : r;
  }

  factory CollaborateurPressing.fromMap(Map<String, dynamic> map) {
    return CollaborateurPressing(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      prenom: parseString(map['prenom']),
      email: parseString(map['email']),
      telephone: parseString(map['telephone']),
      role: RolePressing.depuisCode(parseStringOrNull(map['role'])),
      actif: parseBool(map['actif'], fallback: true),
    );
  }
}

/// L'équipe + le métier du compte qui la consulte.
class EquipePressing {
  const EquipePressing({
    this.roleCourant,
    this.collaborateurs = const <CollaborateurPressing>[],
  });

  /// Métier du compte connecté (`null` = patron ou compte sans métier).
  final RolePressing? roleCourant;

  final List<CollaborateurPressing> collaborateurs;

  bool get estVide => collaborateurs.isEmpty;

  factory EquipePressing.fromRpc(Map<String, dynamic> map) {
    return EquipePressing(
      roleCourant: RolePressing.depuisCode(parseStringOrNull(map['role'])),
      collaborateurs: parseMapList(map['lignes'])
          .map(CollaborateurPressing.fromMap)
          .toList(growable: false),
    );
  }
}
