// lib/models/collaborateur_entreprise.dart
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Un collaborateur rattaché à l'entreprise du propriétaire.
///
/// ⚠️ Ce modèle ne décrit QUE la fiche serveur renvoyée par
/// `rpc_collaborateurs_lister` (migration 0140). Les métiers propres à un
/// module (pressing, distribution, restaurant…) restent gérés par leur écran
/// dédié : ici on ne parle que du rôle général du Module 4.
class CollaborateurEntreprise {
  final String id;
  final String nom;
  final String prenom;
  final String email;
  final String telephone;

  /// Rôle effectif (`PROPRIETAIRE`, `VENDEUR`, `MAGASINIER`,
  /// `COMPTABLE_ENTREPRISE`, `SUPER_ADMIN`…).
  final String role;

  final bool actif;

  const CollaborateurEntreprise({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.email,
    required this.telephone,
    required this.role,
    required this.actif,
  });

  factory CollaborateurEntreprise.depuisJson(Map<String, dynamic> json) {
    return CollaborateurEntreprise(
      id: parseString(json['id']),
      nom: parseString(json['nom']),
      prenom: parseString(json['prenom']),
      email: parseString(json['email']),
      telephone: parseString(json['telephone']),
      role: parseString(json['role']).toUpperCase(),
      actif: parseBool(json['actif'], fallback: true),
    );
  }

  String get nomComplet {
    final String complet = '${prenom.trim()} ${nom.trim()}'.trim();
    return complet.isEmpty ? email : complet;
  }

  String get initiales {
    final String p = prenom.trim();
    final String n = nom.trim();
    if (p.isNotEmpty && n.isNotEmpty) {
      return '${p[0]}${n[0]}'.toUpperCase();
    }
    if (n.isNotEmpty) return n[0].toUpperCase();
    if (p.isNotEmpty) return p[0].toUpperCase();
    return '?';
  }

  /// Libellé lisible d'un rôle du Module 4.
  static String libelleRole(String code) {
    switch (code.toUpperCase()) {
      case 'PROPRIETAIRE':
        return 'Responsable (tous les droits)';
      case 'VENDEUR':
        return 'Vendeur / caissier';
      case 'MAGASINIER':
        return 'Magasinier / stock';
      case 'COMPTABLE_ENTREPRISE':
        return 'Comptable';
      case 'SUPER_ADMIN':
        return 'Super administrateur';
      case 'GESTIONNAIRE':
        return 'Gestionnaire';
      case 'FINANCE':
        return 'Finance';
      case 'SUPPORT':
        return 'Support';
      default:
        return code.isEmpty ? 'Collaborateur' : code;
    }
  }

  String get libelleRoleCourt => libelleRole(role);
}
