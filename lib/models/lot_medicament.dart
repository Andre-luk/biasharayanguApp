// lib/models/lot_medicament.dart
//
// MODULE 36 — LOTS DE MÉDICAMENTS.
//
// Un lot = UNE RÉCEPTION, avec sa propre date de péremption. Un médicament
// reçu trois fois possède trois lots : 100 boîtes (déc. 2026), 150 (juin
// 2027), 80 (sept. 2027). La fiche de l'article n'affiche qu'un RÉSUMÉ (la
// péremption la plus proche encore valide) — la vérité est ici.
//
// ⚠️ RÈGLE FEFO (First Expired, First Out)
//   Le lot qui périme le plus tôt est vendu en premier. C'est le SERVEUR qui
//   applique cette règle (`trg_vente_lots_fefo`) : ce modèle sert à
//   l'AFFICHER, jamais à décider d'une sortie de stock.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// État d'un lot, du plus urgent au plus sain.
enum StatutLot {
  perime('perime', 'Périmé'),
  proche('proche', 'Périme bientôt'),
  valide('valide', 'Valide'),
  retire('retire', 'Retiré du stock'),
  inconnu('inconnu', 'État inconnu');

  const StatutLot(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutLot fromCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    for (final StatutLot statut in values) {
      if (statut.code == valeur) return statut;
    }
    return StatutLot.inconnu;
  }

  /// Le lot peut-il encore être vendu ?
  bool get vendable => this == StatutLot.valide || this == StatutLot.proche;

  /// Le lot ne doit plus être proposé à la vente.
  bool get bloquant => this == StatutLot.perime || this == StatutLot.retire;
}

/// Un lot reçu pour un article.
class LotMedicament {
  const LotMedicament({
    required this.id,
    required this.produitId,
    required this.numeroLot,
    required this.datePeremption,
    required this.quantiteRecue,
    required this.quantiteRestante,
    this.dateFabrication,
    this.prixAchatUnitaire,
    this.fournisseur,
    this.observations,
    this.recuLe,
    this.retireLe,
    this.motifRetrait,
    this.joursRestants,
    this.statut = StatutLot.inconnu,
    this.vendable = false,
  });

  final String id;
  final int produitId;
  final String numeroLot;
  final DateTime datePeremption;
  final double quantiteRecue;
  final double quantiteRestante;

  final DateTime? dateFabrication;
  final double? prixAchatUnitaire;
  final String? fournisseur;
  final String? observations;

  final DateTime? recuLe;
  final DateTime? retireLe;
  final String? motifRetrait;

  /// Jours avant péremption (négatif = périmé depuis N jours).
  final int? joursRestants;

  /// Statut calculé PAR LE SERVEUR (il connaît la date du jour et le délai
  /// d'alerte de la boutique).
  final StatutLot statut;

  /// `true` = encore vendable selon le serveur (non retiré, non périmé,
  /// quantité restante > 0).
  final bool vendable;

  /// Valeur d'achat encore immobilisée dans ce lot.
  double get valeurAchat =>
      (prixAchatUnitaire ?? 0) * quantiteRestante;

  /// Quantité déjà sortie (vendue ou retirée) de ce lot.
  double get quantiteSortie {
    final double sortie = quantiteRecue - quantiteRestante;
    return sortie < 0 ? 0 : sortie;
  }

  /// Libellé court : « LOT-A · 12/2026 ».
  String get designation => '$numeroLot · ${_moisAnnee(datePeremption)}';

  static String _moisAnnee(DateTime date) {
    final String mois = date.month.toString().padLeft(2, '0');
    return '$mois/${date.year}';
  }

  factory LotMedicament.fromMap(Map<String, dynamic> map) {
    final String? statutBrut = parseStringOrNull(map['statut']);
    final DateTime peremption =
        parseDateTimeOrNull(map['date_peremption']) ?? DateTime(1970);
    final DateTime? retire = parseDateTimeOrNull(map['retire_le']);

    return LotMedicament(
      id: parseString(map['id']),
      produitId: parseInt(map['produit_id']),
      numeroLot: parseString(map['numero_lot']),
      datePeremption: peremption,
      quantiteRecue: parseDouble(map['quantite_recue']),
      quantiteRestante: parseDouble(map['quantite_restante']),
      dateFabrication: parseDateTimeOrNull(map['date_fabrication']),
      prixAchatUnitaire: map['prix_achat_unitaire'] == null
          ? null
          : parseDouble(map['prix_achat_unitaire']),
      fournisseur: parseStringOrNull(map['fournisseur']),
      observations: parseStringOrNull(map['observations']),
      recuLe: parseDateTimeOrNull(map['recu_le']),
      retireLe: retire,
      motifRetrait: parseStringOrNull(map['motif_retrait']),
      joursRestants: map['jours_restants'] == null
          ? null
          : parseInt(map['jours_restants']),
      statut: statutBrut == null
          ? _statutLocal(peremption, retire)
          : StatutLot.fromCode(statutBrut),
      vendable: map['vendable'] == true,
    );
  }

  /// Repli hors ligne : même règle que le serveur, sans délai configurable.
  static StatutLot _statutLocal(DateTime peremption, DateTime? retireLe) {
    if (retireLe != null) return StatutLot.retire;

    final DateTime aujourdHui = DateTime.now();
    final DateTime jour =
        DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day);
    final DateTime limite = DateTime(
      peremption.year,
      peremption.month,
      peremption.day,
    );

    if (limite.isBefore(jour)) return StatutLot.perime;
    if (limite.difference(jour).inDays <= 30) return StatutLot.proche;
    return StatutLot.valide;
  }
}

/// Dossier complet renvoyé par `rpc_lots_lister`.
class DossierLots {
  const DossierLots({
    required this.produitId,
    required this.produit,
    required this.stock,
    required this.stockLots,
    required this.stockVendable,
    required this.lots,
    this.dateExpiration,
    this.joursAlarme = 30,
  });

  final int produitId;
  final String produit;

  /// Stock de la FICHE article (doit égaler [stockLots] hors stock ancien).
  final double stock;

  /// Somme des quantités restantes de tous les lots non retirés.
  final double stockLots;

  /// Somme des quantités restantes des lots encore valides (vendables).
  final double stockVendable;

  /// Lots triés FEFO par le serveur (péremption la plus proche d'abord).
  final List<LotMedicament> lots;

  final DateTime? dateExpiration;
  final int joursAlarme;

  /// Lots encore vendables, dans l'ordre FEFO.
  List<LotMedicament> get lotsVendables =>
      lots.where((LotMedicament l) => l.vendable).toList();

  /// Premier lot à servir en caisse (null si aucun).
  LotMedicament? get prochainLot {
    final List<LotMedicament> vendables = lotsVendables;
    return vendables.isEmpty ? null : vendables.first;
  }

  /// Lots périmés qui immobilisent encore du stock.
  List<LotMedicament> get lotsPerimes => lots
      .where((LotMedicament l) => l.statut == StatutLot.perime &&
          l.quantiteRestante > 0)
      .toList();

  /// Valeur d'achat restant dans les lots non retirés.
  double get valeurTotale => lots
      .where((LotMedicament l) => l.retireLe == null)
      .fold<double>(0, (double s, LotMedicament l) => s + l.valeurAchat);

  /// Écart entre la fiche et les lots (diagnostic).
  double get ecart => stock - stockLots;

  bool get aLots => lots.isNotEmpty;

  factory DossierLots.fromRpc(Map<String, dynamic> map) {
    final List<LotMedicament> lots =
        (map['lots'] is List ? map['lots'] as List : const <dynamic>[])
            .whereType<Map>()
            .map((Map e) => LotMedicament.fromMap(
                  Map<String, dynamic>.from(e),
                ))
            .toList();

    return DossierLots(
      produitId: parseInt(map['produit_id']),
      produit: parseString(map['produit']),
      stock: parseDouble(map['stock']),
      stockLots: parseDouble(map['total_lots_restants']),
      stockVendable: parseDouble(map['total_vendable']),
      dateExpiration: parseDateTimeOrNull(map['date_expiration']),
      lots: lots,
    );
  }
}

/// Résultat d'une réception de lot.
class ResultatReceptionLot {
  const ResultatReceptionLot({
    required this.lotId,
    required this.stockApres,
    required this.quantiteRecue,
    this.dateExpiration,
  });

  final String lotId;
  final double stockApres;
  final double quantiteRecue;
  final DateTime? dateExpiration;

  factory ResultatReceptionLot.depuisRpc(Map<String, dynamic> map) {
    return ResultatReceptionLot(
      lotId: parseString(map['lot_id']),
      stockApres: parseDouble(map['stock']),
      quantiteRecue: parseDouble(map['quantite_recue']),
      dateExpiration: parseDateTimeOrNull(map['date_expiration']),
    );
  }
}

/// Résultat d'un retrait de lot.
class ResultatRetraitLot {
  const ResultatRetraitLot({
    required this.quantiteRetiree,
    required this.stockApres,
  });

  final double quantiteRetiree;
  final double stockApres;

  factory ResultatRetraitLot.depuisRpc(Map<String, dynamic> map) {
    return ResultatRetraitLot(
      quantiteRetiree: parseDouble(map['quantite_retiree']),
      stockApres: parseDouble(map['stock']),
    );
  }
}
