// lib/models/commande.dart
//
// 🍽️ MODULE 16 (phase C3) — RESTAURANT : COMMANDE & LIGNES.
//
// Circuit : ouverte (saisie) → envoyee (en cuisine) → en_preparation →
// prete → servie → encaissee (vente réelle passée par la caisse) ; ou
// annulee. Les lignes figent libellé + prix (snapshot du catalogue).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Statut d'une commande (table `public.commandes`).
enum StatutCommande {
  ouverte('ouverte', 'En saisie'),
  envoyee('envoyee', 'Envoyée'),
  enPreparation('en_preparation', 'En préparation'),
  prete('prete', 'Prête'),
  servie('servie', 'Servie'),
  encaissee('encaissee', 'Encaissée'),
  annulee('annulee', 'Annulée');

  const StatutCommande(this.code, this.libelle);

  final String code;
  final String libelle;

  /// La commande compte encore (ni encaissée ni annulée).
  bool get estActive =>
      this != StatutCommande.encaissee && this != StatutCommande.annulee;

  /// La commande est dans le circuit cuisine.
  bool get enCuisine =>
      this == StatutCommande.envoyee ||
      this == StatutCommande.enPreparation ||
      this == StatutCommande.prete;

  static StatutCommande fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final StatutCommande statut in values) {
      if (statut.code == normalise) return statut;
    }
    return StatutCommande.ouverte;
  }
}

/// Une ligne de commande — table `public.lignes_commande`.
class LigneCommande {
  const LigneCommande({
    required this.id,
    required this.produitId,
    required this.libelle,
    this.quantite = 1,
    this.quantiteVendue = 1,
    this.prixUnitaire = 0,
    this.total = 0,
  });

  final String id;
  final int produitId;

  /// Nom de l'article FIGÉ au moment de la commande.
  final String libelle;

  /// Quantité en unités de base (stock).
  final double quantite;

  /// Quantité facturée (égale à [quantite] hors conditionnement).
  final double quantiteVendue;

  final double prixUnitaire;
  final double total;

  factory LigneCommande.fromMap(Map<String, dynamic> map) {
    return LigneCommande(
      id: parseString(map['id']),
      produitId: parseInt(map['produit_id']),
      libelle: parseString(map['libelle'], fallback: 'Article'),
      quantite: parseDouble(map['quantite'], fallback: 1),
      quantiteVendue: parseDouble(map['quantite_vendue'], fallback: 1),
      prixUnitaire: parseDouble(map['prix_unitaire']),
      total: parseDouble(map['total']),
    );
  }
}

/// Une commande de restaurant — table `public.commandes`.
class Commande {
  const Commande({
    required this.id,
    required this.tableId,
    this.tableNumero = '',
    this.numero,
    this.clientNom,
    this.nbPersonnes = 1,
    this.statut = StatutCommande.ouverte,
    this.note,
    this.montantTotal = 0,
    this.numeroVente,
    this.createdAt,
    this.lignes = const <LigneCommande>[],
  });

  final String id;
  final String tableId;

  /// Numéro de la table (rempli par la jointure de lecture).
  final String tableNumero;

  /// Numéro journalier « CMD-AAAAMMJJ-0001 ».
  final String? numero;

  final String? clientNom;
  final int nbPersonnes;
  final StatutCommande statut;
  final String? note;
  final double montantTotal;

  /// Numéro de la vente créée à l'encaissement (caisse).
  final String? numeroVente;

  final DateTime? createdAt;

  /// Lignes de la commande (remplies par la lecture avec jointure).
  final List<LigneCommande> lignes;

  /// Nombre de lignes distinctes.
  int get nbArticles => lignes.length;

  /// Résumé court des lignes (« 2× Poulet braisé, 1× Fanta »).
  String get resume {
    if (lignes.isEmpty) return 'Aucun article';
    return lignes
        .map((LigneCommande l) => '${_quantite(l.quantiteVendue)}× ${l.libelle}')
        .join(', ');
  }

  static String _quantite(double valeur) => valeur == valeur.roundToDouble()
      ? valeur.toStringAsFixed(0)
      : valeur.toString();

  factory Commande.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic>? table = parseMap(map['tables_salle']);

    final List<LigneCommande> lignes = map['lignes_commande'] is List
        ? (map['lignes_commande'] as List)
            .whereType<Map>()
            .map((Map e) =>
                LigneCommande.fromMap(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : const <LigneCommande>[];

    return Commande(
      id: parseString(map['id']),
      tableId: parseString(map['table_id']),
      tableNumero: parseString(table?['numero']),
      numero: parseStringOrNull(map['numero']),
      clientNom: parseStringOrNull(map['client_nom']),
      nbPersonnes: parseInt(map['nb_personnes'], fallback: 1),
      statut: StatutCommande.fromCode(parseStringOrNull(map['statut'])),
      note: parseStringOrNull(map['note']),
      montantTotal: parseDouble(map['montant_total']),
      numeroVente: parseStringOrNull(map['numero_vente']),
      createdAt: parseDateTimeOrNull(map['created_at']),
      lignes: lignes,
    );
  }

  Commande copyWith({
    String? id,
    String? tableId,
    String? tableNumero,
    String? numero,
    String? clientNom,
    int? nbPersonnes,
    StatutCommande? statut,
    String? note,
    double? montantTotal,
    String? numeroVente,
    DateTime? createdAt,
    List<LigneCommande>? lignes,
  }) {
    return Commande(
      id: id ?? this.id,
      tableId: tableId ?? this.tableId,
      tableNumero: tableNumero ?? this.tableNumero,
      numero: numero ?? this.numero,
      clientNom: clientNom ?? this.clientNom,
      nbPersonnes: nbPersonnes ?? this.nbPersonnes,
      statut: statut ?? this.statut,
      note: note ?? this.note,
      montantTotal: montantTotal ?? this.montantTotal,
      numeroVente: numeroVente ?? this.numeroVente,
      createdAt: createdAt ?? this.createdAt,
      lignes: lignes ?? this.lignes,
    );
  }
}
