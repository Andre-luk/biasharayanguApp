class Vente {
  int? id;
  int produitId;
  double quantite;
  double prix;
  String modePaiement;
  String createdAt;

  String? ownerId;
  String? sellerId;
  int? clientId;

  String? supabaseId;
  int? isSynced;

  Vente({
    this.id,
    required this.produitId,
    required this.quantite,
    required this.prix,
    required this.modePaiement,
    required this.createdAt,
    this.ownerId,
    this.sellerId,
    this.clientId,
    this.supabaseId,
    this.isSynced = 0,
  });

  DateTime? get createdAtDate => DateTime.tryParse(createdAt);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'produit_id': produitId,
      'quantite': quantite,
      'prix': prix,
      'mode_paiement': modePaiement,
      'date': createdAt,
      'owner_id': ownerId,
      'seller_id': sellerId,
      'client_id': clientId,
      'supabase_id': supabaseId,
      'is_synced': isSynced ?? 0,
    };
  }

  factory Vente.fromMap(Map<String, dynamic> map) {
    return Vente(
      id: _asInt(map['id']),
      produitId: _asInt(map['produit_id']) ?? 0,
      quantite: _asDouble(map['quantite']),
      prix: _asDouble(map['prix']),
      modePaiement: _asString(map['mode_paiement']) ?? 'cash',
      createdAt: _asString(map['date']) ??
          _asString(map['created_at']) ??
          DateTime.now().toIso8601String(),
      ownerId: _asString(map['owner_id']),
      sellerId: _asString(map['seller_id']),
      clientId: _asInt(map['client_id']),
      supabaseId: _asString(map['supabase_id']),
      isSynced: _asInt(map['is_synced']) ?? 0,
    );
  }
}

class VenteDetail {
  final String produitNom;
  final double quantite;
  final DateTime dateVente;
  final double prixTotal;
  final String? produitIdInt;

  VenteDetail({
    required this.produitNom,
    required this.quantite,
    required this.dateVente,
    required this.prixTotal,
    this.produitIdInt,
  });
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

String? _asString(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}