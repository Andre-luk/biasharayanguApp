class Produit {
  int? id;
  String nom;
  String categorie;
  double prixAchat;
  double prixVente;
  double quantite;
  String uniteMesure;
  String? photo;
  String? createdAt;
  String? updatedAt;
  String? ownerId;
  String? supabaseId;
  int? isSynced;

  Produit({
    this.id,
    required this.nom,
    required this.categorie,
    required this.prixAchat,
    required this.prixVente,
    required this.quantite,
    required this.uniteMesure,
    this.photo,
    this.createdAt,
    this.updatedAt,
    this.ownerId,
    this.supabaseId,
    this.isSynced = 0,
  });

  DateTime? get updatedAtDate => updatedAt == null ? null : DateTime.tryParse(updatedAt!);
  DateTime? get createdAtDate => createdAt == null ? null : DateTime.tryParse(createdAt!);

  /// 🔴 CORRECTIF 77 — L'IDENTIFIANT QUI COMPTE POUR LE SERVEUR.
  ///
  /// `id` est l'identifiant **LOCAL** (SQLite, auto-incrémenté) : il ne veut
  /// rien dire pour Supabase. L'identifiant de la ligne dans
  /// `public.produits` est [supabaseId], attribué au premier envoi (ou reçu au
  /// téléchargement).
  ///
  /// ⚠️ Toute opération côté serveur — vente (`rpc_vente_valider`), stock,
  ///    QR code, fiche article — DOIT utiliser [idServeur]. Envoyer `id` à la
  ///    place produit l'erreur « Article n° 83 introuvable : il a peut-être
  ///    été supprimé. » alors que l'article existe.
  int? get idServeur => int.tryParse((supabaseId ?? '').trim());

  /// L'article existe-t-il dans la base serveur ?
  ///
  /// `false` = créé sur ce téléphone et pas encore envoyé : il ne peut pas
  /// être vendu tant que la synchronisation n'a pas abouti.
  bool get synchronise => idServeur != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nom': nom,
      'categorie': categorie,
      'prix_achat': prixAchat,
      'prix_vente': prixVente,
      'quantite': quantite,
      'unite_mesure': uniteMesure,
      'photo': photo,
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
      'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
      'owner_id': ownerId,
      'supabase_id': supabaseId,
      'is_synced': isSynced ?? 0,
    };
  }

  factory Produit.fromMap(Map<String, dynamic> map) {
    return Produit(
      id: _asInt(map['id']),
      nom: _asString(map['nom']) ?? '',
      categorie: _asString(map['categorie']) ?? '',
      prixAchat: _asDouble(map['prix_achat']),
      prixVente: _asDouble(map['prix_vente']),
      quantite: _asDouble(map['quantite']),
      uniteMesure: _asString(map['unite_mesure']) ?? 'unité',
      photo: _asString(map['photo']),
      createdAt: _asString(map['created_at']),
      updatedAt: _asString(map['updated_at']),
      ownerId: _asString(map['owner_id']),
      supabaseId: _asString(map['supabase_id']),
      isSynced: _asBoolInt(map['is_synced']),
    );
  }
}

extension ProduitCopy on Produit {
  Produit copyWith({
    int? id,
    String? nom,
    String? categorie,
    double? prixAchat,
    double? prixVente,
    double? quantite,
    String? uniteMesure,
    String? photo,
    String? createdAt,
    String? updatedAt,
    String? ownerId,
    String? supabaseId,
    int? isSynced,
  }) {
    return Produit(
      id: id ?? this.id,
      nom: nom ?? this.nom,
      categorie: categorie ?? this.categorie,
      prixAchat: prixAchat ?? this.prixAchat,
      prixVente: prixVente ?? this.prixVente,
      quantite: quantite ?? this.quantite,
      uniteMesure: uniteMesure ?? this.uniteMesure,
      photo: photo ?? this.photo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ownerId: ownerId ?? this.ownerId,
      supabaseId: supabaseId ?? this.supabaseId,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString());
}

double _asDouble(dynamic value, {double fallback = 0.0}) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '.')) ?? fallback;
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