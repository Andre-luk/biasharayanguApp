class InventaireQuotidien {
  final int? id;
  final String ownerId;
  final int produitId;
  final double quantiteTheorique;
  final double? quantitePhysique;
  final String dateCloture;
  final int isSynced;
  String? supabaseId;

  InventaireQuotidien({
    this.id,
    required this.ownerId,
    required this.produitId,
    required this.quantiteTheorique,
    this.quantitePhysique,
    required this.dateCloture,
    this.isSynced = 0,
    this.supabaseId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'owner_id': ownerId,
    'produit_id': produitId,
    'quantite_theorique': quantiteTheorique,
    'quantite_physique': quantitePhysique,
    'date_cloture': dateCloture,
    'is_synced': isSynced,
    'supabase_id': supabaseId,
  };

  factory InventaireQuotidien.fromMap(Map<String, dynamic> map) => InventaireQuotidien(
    id: map['id'] as int?,
    ownerId: map['owner_id']?.toString() ?? '',
    produitId: (map['produit_id'] as num?)?.toInt() ?? 0,
    quantiteTheorique: (map['quantite_theorique'] as num?)?.toDouble() ?? 0.0,
    quantitePhysique: (map['quantite_physique'] as num?)?.toDouble(),
    dateCloture: map['date_cloture']?.toString() ?? '',
    isSynced: (map['is_synced'] as int?) ?? 0,
    supabaseId: map['supabase_id']?.toString(),
  );
}