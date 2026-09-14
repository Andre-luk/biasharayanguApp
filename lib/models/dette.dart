class Dette {
  final int? id;
  final String ownerId;
  final int clientId;
  final int? venteId;
  final double montantTotal;
  final double montantPaye;
  final String dateCreation;
  final String statut;
  final int isSynced;
  String? supabaseId;

  Dette({
    this.id,
    required this.ownerId,
    required this.clientId,
    this.venteId,
    required this.montantTotal,
    this.montantPaye = 0,
    required this.dateCreation,
    this.statut = 'non_paye',
    this.isSynced = 0,
    this.supabaseId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'owner_id': ownerId,
    'client_id': clientId,
    'vente_id': venteId,
    'montant_total': montantTotal,
    'montant_paye': montantPaye,
    'date_creation': dateCreation,
    'statut': statut,
    'is_synced': isSynced,
    'supabase_id': supabaseId,
  };

  factory Dette.fromMap(Map<String, dynamic> map) => Dette(
    id: map['id'] as int?,
    ownerId: map['owner_id']?.toString() ?? '',
    clientId: (map['client_id'] as num?)?.toInt() ?? 0,
    venteId: (map['vente_id'] as num?)?.toInt(),
    montantTotal: (map['montant_total'] as num?)?.toDouble() ?? 0.0,
    montantPaye: (map['montant_paye'] as num?)?.toDouble() ?? 0.0,
    dateCreation: map['date_creation']?.toString() ?? '',
    statut: map['statut']?.toString() ?? 'non_paye',
    isSynced: (map['is_synced'] as int?) ?? 0,
    supabaseId: map['supabase_id']?.toString(),
  );
}