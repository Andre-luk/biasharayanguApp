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

  /// 🧾 MODULE 28 — FORMAT VENDU (farde, carton…).
  ///
  /// L'identifiant du conditionnement va jusqu'au serveur : sans lui, une
  /// farde vendue 12 000 était renvoyée au PRIX DE L'UNITÉ × 12 (14 400 par
  /// exemple) et le rapport d'activité ne voyait pas le bon montant.
  String? conditionnementId;

  /// Nombre d'UNITÉS VENDUES (1 pour une farde, 2 pour deux cartons).
  ///
  /// ⚠️ [quantite] reste en UNITÉS DE BASE (12 pour une farde de 12) : c'est
  /// ce que le stock consomme. Le serveur, lui, a besoin des DEUX : les unités
  /// de base pour le stock et les unités vendues pour le prix
  /// (prix du conditionnement × 1, et non × 12).
  double? quantiteVendue;

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
    this.conditionnementId,
    this.quantiteVendue,
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
      'conditionnement_id': conditionnementId,
      'quantite_vendue': quantiteVendue,
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
      conditionnementId: _asString(map['conditionnement_id']),
      quantiteVendue: map['quantite_vendue'] == null
          ? null
          : _asDouble(map['quantite_vendue']),
    );
  }
}

class VenteDetail {
  final String produitNom;
  final double quantite;
  final DateTime dateVente;
  final double prixTotal;
  final String? produitIdInt;

  /// 🧑‍🤝‍🧑 CORRECTIF 179 — traçabilité du stock au moment de la vente.
  ///
  /// `stockAvant` / `stockApres` viennent du serveur (mouvements réels) :
  /// c'est ce qui permet d'afficher « il restait 4 beignets » dans le rapport
  /// d'un collaborateur. `null` = article supprimé, stock non reconstituable.
  final double? stockAvant;
  final double? stockApres;

  /// Nom du vendeur de l'unité précédente du même article.
  final String? venduAvantPar;

  VenteDetail({
    required this.produitNom,
    required this.quantite,
    required this.dateVente,
    required this.prixTotal,
    this.produitIdInt,
    this.stockAvant,
    this.stockApres,
    this.venduAvantPar,
  });

  bool get stockConnu => stockApres != null;
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