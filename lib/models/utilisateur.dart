class Utilisateur {
  final String? id;
  final String prenom; // ajouté si tu veux gérer prénom et nom séparés
  final String nom;
  final String email;
  final String? avatar;

  /// Ancien rôle texte (`admin`, `vendor`, `collaborator`…).
  ///
  /// Conservé pour la compatibilité : les versions précédentes de
  /// l'application écrivaient dans cette colonne. La référence du Module 4 est
  /// [newRole].
  final String role;

  /// Rôle officiel du Module 4 (`public.utilisateurs.new_role`,
  /// type `role_utilisateur_enum`). `null` tant que la migration n'a pas
  /// rattrapé le compte.
  final String? newRole;

  /// Entreprise (boutique) à laquelle le compte est rattaché, si elle est
  /// connue. Les permissions applicatives dépendent du **rôle**, pas de
  /// l'entreprise : cette colonne sert au cloisonnement des données.
  final String? entrepriseId;

  final int valide;
  final String? parentId;
  final String? passwordHash; // hash SHA256 du mot de passe

  Utilisateur({
    this.id,
    this.prenom = '',
    required this.nom,
    required this.email,
    this.avatar,
    this.role = 'vendor',
    this.newRole,
    this.entrepriseId,
    this.valide = 1,
    this.parentId,
    this.passwordHash,
  });

  /// Retourne le nom complet
  String get fullName {
    if (prenom.isEmpty) return nom;
    return '$prenom $nom';
  }

  factory Utilisateur.fromMap(Map<String, dynamic> map) {
    return Utilisateur(
      id: map['id'] as String?,
      prenom: (map['prenom'] as String?) ?? '',
      nom: (map['nom'] as String?) ?? 'Utilisateur',
      email: (map['email'] as String?) ?? '',
      avatar: map['avatar'] as String?,
      role: (map['role'] as String?) ?? 'vendor',
      newRole: map['new_role'] as String?,
      entrepriseId: map['entreprise_id'] as String?,
      valide: map['valide'] as int? ?? 1,
      parentId: map['parent_id'] as String?,
      passwordHash: map['password_hash'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'prenom': prenom,
      'nom': nom,
      'email': email,
      'avatar': avatar,
      'role': role,
      'new_role': newRole,
      'entreprise_id': entrepriseId,
      'valide': valide,
      'parent_id': parentId,
      'password_hash': passwordHash,
    };
  }

  Utilisateur copyWith({
    String? id,
    String? prenom,
    String? nom,
    String? email,
    String? avatar,
    String? role,
    String? newRole,
    String? entrepriseId,
    int? valide,
    String? parentId,
    String? passwordHash,
  }) {
    return Utilisateur(
      id: id ?? this.id,
      prenom: prenom ?? this.prenom,
      nom: nom ?? this.nom,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      role: role ?? this.role,
      newRole: newRole ?? this.newRole,
      entrepriseId: entrepriseId ?? this.entrepriseId,
      valide: valide ?? this.valide,
      parentId: parentId ?? this.parentId,
      passwordHash: passwordHash ?? this.passwordHash,
    );
  }
}
