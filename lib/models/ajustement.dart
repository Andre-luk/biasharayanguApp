class Ajustement {
  int? id;
  int produitId;
  double quantite;
  String raison;
  String date;
  String? ownerId;

  String? supabaseId;
  int isSynced;

  Ajustement({
    this.id,
    required this.produitId,
    required this.quantite,
    required this.raison,
    required this.date,
    this.ownerId,
    this.supabaseId,
    this.isSynced = 0,
  });

  // 🔥 Utile pour debug + logique
  DateTime? get dateParsed => DateTime.tryParse(date);

  factory Ajustement.fromMap(Map<String, dynamic> map) {
    return Ajustement(
      id: _asInt(map['id']),
      produitId: _asInt(map['produit_id']) ?? 0,
      quantite: _asDouble(map['quantite']),
      raison: _asString(map['raison']) ?? '',
      date: _asString(map['date']) ??
          DateTime.now().toIso8601String(),
      ownerId: _asString(map['owner_id']),
      supabaseId: _asString(map['supabase_id']),
      isSynced: _asBoolInt(map['is_synced']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'produit_id': produitId,
      'quantite': quantite,
      'raison': raison,
      'date': date,
      'owner_id': ownerId,
      'supabase_id': supabaseId,
      'is_synced': isSynced,
    };
  }

  // 🔥 ULTRA IMPORTANT pour sync propre
  Ajustement copyWith({
    int? id,
    int? produitId,
    double? quantite,
    String? raison,
    String? date,
    String? ownerId,
    String? supabaseId,
    int? isSynced,
  }) {
    return Ajustement(
      id: id ?? this.id,
      produitId: produitId ?? this.produitId,
      quantite: quantite ?? this.quantite,
      raison: raison ?? this.raison,
      date: date ?? this.date,
      ownerId: ownerId ?? this.ownerId,
      supabaseId: supabaseId ?? this.supabaseId,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

// ================= HELPERS =================

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

