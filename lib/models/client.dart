class Client {
  int? id;
  String? ownerId;
  String nom;
  String? telephone;
  String? email;
  String? adresse;

  String? supabaseId;
  int? isSynced;

  Client({
    this.id,
    this.ownerId,
    required this.nom,
    this.telephone,
    this.email,
    this.adresse,
    this.supabaseId,
    this.isSynced = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'nom': nom,
      'telephone': telephone,
      'email': email,
      'adresse': adresse,
      'supabase_id': supabaseId,
      'is_synced': isSynced ?? 0,
    };
  }

  factory Client.fromMap(Map<String, dynamic> map) {
    return Client(
      id: _asInt(map['id']),
      ownerId: _asString(map['owner_id']),
      nom: _asString(map['nom']) ?? '',
      telephone: _asString(map['telephone']),
      email: _asString(map['email']),
      adresse: _asString(map['adresse']),
      supabaseId: _asString(map['supabase_id']),
      isSynced: _asBoolInt(map['is_synced']),
    );
  }

  Client copyWith({
    int? id,
    String? ownerId,
    String? nom,
    String? telephone,
    String? email,
    String? adresse,
    String? supabaseId,
    int? isSynced,
  }) {
    return Client(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      nom: nom ?? this.nom,
      telephone: telephone ?? this.telephone,
      email: email ?? this.email,
      adresse: adresse ?? this.adresse,
      supabaseId: supabaseId ?? this.supabaseId,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  String toString() => '$nom (${telephone ?? ""}${email != null ? " / $email" : ""})';
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString());
}

int _asBoolInt(dynamic value) {
  if (value == null) return 0;
  if (value is bool) return value ? 1 : 0;
  if (value is int) return value;
  return int.tryParse(value.toString()) ?? 0;
}

String? _asString(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}