class Approvisionnement {
  final int? id;
  final int produitId;
  final double quantiteAjoutee;
  final double prixAchatUnitaire;
  final String dateApprovisionnement;

  // Champs de synchronisation
  String? uuid;      // <-- ajouté
  String? supabaseId;
  int? isSynced; // 0 = non sync, 1 = sync
  String? ownerId; // UUID Supabase du propriétaire

  Approvisionnement({
    this.id,
    required this.produitId,
    required this.quantiteAjoutee,
    required this.prixAchatUnitaire,
    required this.dateApprovisionnement,
    this.uuid,
    this.supabaseId,
    this.isSynced = 0,
    this.ownerId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'produit_id': produitId,
      'quantite_ajoutee': quantiteAjoutee,
      'prix_achat_unitaire': prixAchatUnitaire,
      'date_approvisionnement': dateApprovisionnement,
      'uuid': uuid,
      'supabase_id': supabaseId,
      'is_synced': isSynced ?? 0,
      'owner_id': ownerId,
    };
  }

  factory Approvisionnement.fromMap(Map<String, dynamic> map) {
    return Approvisionnement(
      id: map['id'] as int?,
      produitId: (map['produit_id'] as num?)?.toInt() ?? 0,
      quantiteAjoutee: (map['quantite_ajoutee'] as num?)?.toDouble() ?? 0.0,
      prixAchatUnitaire: (map['prix_achat_unitaire'] as num?)?.toDouble() ?? 0.0,
      dateApprovisionnement: (map['date_approvisionnement'] as String?) ?? '',
      uuid: (map['uuid'] as dynamic)?.toString(),
      supabaseId: (map['supabase_id'] as dynamic)?.toString(),
      isSynced: (map['is_synced'] is int) ? map['is_synced'] as int : (map['is_synced'] != null ? int.tryParse(map['is_synced'].toString()) : 0),
      ownerId: (map['owner_id'] as dynamic)?.toString(),
    );
  }
}