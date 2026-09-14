class Depense {
  final int? id;
  final String ownerId;
  final String motif;
  final double montant;
  final String date;
  final int isSynced;
  String? supabaseId;

  Depense({
    this.id,
    required this.ownerId,
    required this.motif,
    required this.montant,
    required this.date,
    this.isSynced = 0,
    this.supabaseId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'owner_id': ownerId,
    'motif': motif,
    'montant': montant,
    'date': date,
    'is_synced': isSynced,
    'supabase_id': supabaseId,
  };

  factory Depense.fromMap(Map<String, dynamic> map) => Depense(
    id: map['id'] as int?,
    ownerId: map['owner_id']?.toString() ?? '',
    motif: map['motif']?.toString() ?? '',
    montant: (map['montant'] as num?)?.toDouble() ?? 0.0,
    date: map['date']?.toString() ?? '',
    isSynced: (map['is_synced'] as int?) ?? 0,
    supabaseId: map['supabase_id']?.toString(),
  );
}