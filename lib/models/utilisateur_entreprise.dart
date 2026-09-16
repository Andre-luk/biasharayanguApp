// lib/models/utilisateur_entreprise.dart
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Vue allégée d'un utilisateur pour le module Entreprises.
///
/// Pourquoi ne pas réutiliser `Utilisateur` : le modèle partagé ne contient pas
/// `entreprise_id`, et l'y ajouter casserait les écritures SQLite locales — la
/// table locale `utilisateurs` de `db_helper.dart` n'a pas cette colonne, et
/// `Utilisateur.toMap()` est utilisé pour des `insert`.
///
/// Ce modèle est en **lecture seule** : aucune écriture ne passe par `toMap()`.
class UtilisateurEntreprise {
  final String id;
  final String prenom;
  final String nom;
  final String email;
  final String role;

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
      parentId: parseStringOrNull(map['parent_id']),
      entrepriseId: parseStringOrNull(map['entreprise_id']),
    );
  }

  /// Nom affiché, avec repli sur l'e-mail si le nom est vide.
  String get nomComplet {
    final String complet = '$prenom $nom'.trim();
    return complet.isEmpty ? email : complet;
  }

  bool get estAdministrateur => role == 'admin';

  bool get estCollaborateur => role == 'collaborator';

  /// Libellé lisible du rôle technique stocké en base.
  String get roleLibelle {
    switch (role) {
      case 'admin':
        return 'Administrateur';
      case 'collaborator':
        return 'Collaborateur';
      case 'vendor':
        return 'Patron / Vendeur';
      default:
        return role;
    }
  }
}
