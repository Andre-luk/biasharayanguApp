class PaiementDette {
  final int? id;
  final int detteId;
  final double montant;
  final String datePaiement;
  final String? ownerId;
  final int isSynced;
  final String? supabaseId;

  PaiementDette({
    this.id,
    required this.detteId,
    required this.montant,
    required this.datePaiement,
    this.ownerId,
    this.isSynced = 0,
    this.supabaseId,
  });

  // 🔹 Convertir objet → Map (SQLite / Supabase)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dette_id': detteId,
      'montant': montant,
      'date_paiement': datePaiement,
      'owner_id': ownerId,
      'is_synced': isSynced,
      'supabase_id': supabaseId,
    };
  }

  // 🔹 Convertir Map → objet
  factory PaiementDette.fromMap(Map<String, dynamic> map) {
    return PaiementDette(
      id: map['id'],
      detteId: map['dette_id'],
      montant: (map['montant'] as num).toDouble(),
      datePaiement: map['date_paiement'],
      ownerId: map['owner_id'],
      isSynced: map['is_synced'] ?? 0,
      supabaseId: map['supabase_id'],
    );
  }

  // 🔹 Pour Supabase (optionnel mais recommandé)
  Map<String, dynamic> toSupabaseMap() {
    return {
      'dette_id': detteId,
      'montant': montant,
      'date_paiement': datePaiement,
      'owner_id': ownerId,
    };
  }
}