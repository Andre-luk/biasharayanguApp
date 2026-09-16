// lib/models/utilisateur_entreprise.dart
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Vue allégée d'un utilisateur pour le module Entreprises.
///
/// Ce modèle est en **lecture seule** : aucune écriture ne passe par `toMap()`.
/// Le rôle y est exposé sous deux formes — l'ancien texte (`role`) et le rôle
/// officiel du Module 4 (`new_role`) — afin que l'affichage reste juste avant
/// comme après la migration des comptes.
class UtilisateurEntreprise {
  final String id;
  final String prenom;
  final String nom;
  final String email;
  final String role;

  /// Rôle officiel du Module 4 (`new_role`). `null` pour les comptes créés
  /// avant la migration.
  final String? newRole;

  /// Patron du collaborateur (`parent_id`). `null` pour un compte autonome.
  final String? parentId;

  /// Entreprise rattachée. `null` tant que le rattachement n'a pas été fait.
  final String? entrepriseId;

  const UtilisateurEntreprise({
    required this.id,
    this.prenom = '',
    this.nom = '',
    this.email = '',
    this.role = 'vendor',
    this.newRole,
    this.parentId,
    this.entrepriseId,
  });

  factory UtilisateurEntreprise.fromMap(Map<String, dynamic> map) {
    return UtilisateurEntreprise(
      id: parseString(map['id']),
      prenom: parseString(map['prenom']),
      nom: parseString(map['nom']),
      email: parseString(map['email']),
      role: parseString(map['role'], fallback: 'vendor'),
      newRole: parseStringOrNull(map['new_role']),
      parentId: parseStringOrNull(map['parent_id']),
      entrepriseId: parseStringOrNull(map['entreprise_id']),
    );
  }

  /// Nom affiché, avec repli sur l'e-mail si le nom est vide.
  String get nomComplet {
    final String complet = '$prenom $nom'.trim();
    return complet.isEmpty ? email : complet;
  }

  /// Rôle effectif du Module 4, en repli sur l'ancien rôle texte.
  RoleUtilisateur get roleModule4 {
    final RoleUtilisateur depuisNouveau = RoleUtilisateur.fromCode(newRole);
    if (depuisNouveau != RoleUtilisateur.inconnu) return depuisNouveau;
    return RoleUtilisateur.fromCode(role);
  }

  bool get estAdministrateur =>
      role == 'admin' || roleModule4 == RoleUtilisateur.superAdmin;

  bool get estCollaborateur => role == 'collaborator';

  /// Libellé lisible de l'**ancien** rôle (écrans du module Entreprises).
  ///
  /// ⚠️ Ce libellé est conservé à l'identique pour ne pas modifier les écrans
  /// existants. Pour le libellé officiel du Module 4 (« Vendeur »,
  /// « Magasinier »…), utilisez [roleModule4Libelle].
  String get roleLibelle {
    switch (role) {
      case 'admin':
        return 'Administrateur';
      case 'collaborator':
        return 'Collaborateur';
      case 'vendor':
        return 'Patron / Vendeur';
      default:
        // Ancien rôle inconnu (ou absent) : on affiche le rôle du Module 4
        // s'il est exploitable, sinon la valeur brute.
        final RoleUtilisateur effectif = roleModule4;
        return effectif == RoleUtilisateur.inconnu ? role : effectif.libelle;
    }
  }

  /// Libellé du rôle officiel du Module 4, avec repli sur l'ancien libellé.
  String get roleModule4Libelle {
    final RoleUtilisateur effectif = roleModule4;
    return effectif == RoleUtilisateur.inconnu ? roleLibelle : effectif.libelle;
  }
}
