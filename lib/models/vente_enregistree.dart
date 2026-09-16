// lib/models/vente_enregistree.dart
//
// MODULE 8 — RÉSULTATS DE LA VALIDATION DE VENTE.
//
//   • [LigneVenteEnregistree] + [VenteEnregistree] — récapitulatif renvoyé
//     par la transaction `rpc_vente_valider` (écran de confirmation / reçu) ;
//   • [LigneVenteHistorique] + [VenteHistorique] — une vente relue dans
//     `public.ventes` pour l'historique du vendeur (lignes groupées par
//     `vente_uuid`).
//
// Les prix sont TOUJOURS ceux écrits par le serveur : la réponse de la
// transaction sert de source de vérité, jamais les valeurs affichées avant.

import 'dart:convert';

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Ligne de la vente qui vient d'être validée.
class LigneVenteEnregistree {
  final int produitId;
  final String nom;

  /// Libellé du conditionnement (« Farde de 12 »), ou `null` pour l'unité de
  /// base.
  final String? conditionnement;

  /// Unité vendue : conditionnement ou unité de base (« bouteille »).
  final String unite;

  /// Quantité vendue en unités vendues (3 fardes, 2 bouteilles…).
  final double quantiteVendue;

  /// Quantité retirée du stock, en unités de base (36 pour 3 fardes de 12).
  final double quantiteBase;

  final double prixUnitaire;
  final double total;

  const LigneVenteEnregistree({
    required this.produitId,
    required this.nom,
    required this.unite,
    required this.quantiteVendue,
    required this.quantiteBase,
    required this.prixUnitaire,
    required this.total,
    this.conditionnement,
  });

  factory LigneVenteEnregistree.fromMap(Map<String, dynamic> map) {
    return LigneVenteEnregistree(
      produitId: parseInt(map['produit_id']),
      nom: parseString(map['nom']),
      conditionnement: parseStringOrNull(map['conditionnement']),
      unite: parseString(map['unite'], fallback: 'unité'),
      quantiteVendue: parseDouble(map['quantite_vendue']),
      quantiteBase: parseDouble(map['quantite_base']),
      prixUnitaire: parseDouble(map['prix_unitaire']),
      total: parseDouble(map['total']),
    );
  }
}

/// Vente validée : numéro unique + récapitulatif complet.
class VenteEnregistree {
  final String numeroVente;

  /// Identifiant interne regroupant les lignes de cette vente.
  final String venteUuid;

  final double total;
  final String modePaiement;
  final double? montantRecu;

  /// Monnaie rendue (espèces uniquement).
  final double? rendu;

  final DateTime? date;
  final List<LigneVenteEnregistree> lignes;

  const VenteEnregistree({
    required this.numeroVente,
    required this.venteUuid,
    required this.total,
    required this.modePaiement,
    required this.lignes,
    this.montantRecu,
    this.rendu,
    this.date,
  });

  /// Construit depuis la réponse JSON de `rpc_vente_valider`.
  factory VenteEnregistree.fromRpc(Map<String, dynamic> map) {
    final List<LigneVenteEnregistree> lignes = parseMapList(map['lignes'])
        .map(LigneVenteEnregistree.fromMap)
        .toList(growable: false);

    return VenteEnregistree(
      numeroVente: parseString(map['numero_vente']),
      venteUuid: parseString(map['vente_uuid']),
      total: parseDouble(map['total']),
      modePaiement: parseString(map['mode_paiement'], fallback: 'especes'),
      montantRecu: parseDoubleOrNull(map['montant_recu']),
      rendu: parseDoubleOrNull(map['rendu']),
      date: parseDateTimeOrNull(map['date']),
      lignes: lignes,
    );
  }

  /// Nombre de lignes (articles distincts).
  int get nombreLignes => lignes.length;
}

/// Ligne d'une vente relue dans l'historique (`public.ventes`).
class LigneVenteHistorique {
  final int id;
  final int produitId;
  final String nom;
  final String uniteBase;

  /// Conditionnement vendu, si la ligne en désigne un.
  final String? conditionnementId;
  final String? conditionnementLibelle;

  /// Nombre d'unités de base par emballage (12 pour une farde de 12).
  final double? conditionnementUnitesBase;

  /// Unités de base retirées du stock.
  final double quantiteBase;

  /// Total de la ligne (colonne `prix`).
  final double total;

  const LigneVenteHistorique({
    required this.id,
    required this.produitId,
    required this.nom,
    required this.uniteBase,
    required this.quantiteBase,
    required this.total,
    this.conditionnementId,
    this.conditionnementLibelle,
    this.conditionnementUnitesBase,
  });

  /// Quantité en unités vendues : nombre d'emballages pour un conditionnement
  /// (36 base / 12 = 3 fardes), unités de base sinon.
  double get quantiteVendue {
    final double? parEmballage = conditionnementUnitesBase;
    if (conditionnementId != null && parEmballage != null && parEmballage > 0) {
      return quantiteBase / parEmballage;
    }
    return quantiteBase;
  }

  /// Unité affichée : libellé du conditionnement ou unité de base.
  String get unite => conditionnementLibelle ?? uniteBase;
}

/// Une vente complète de l'historique du vendeur.
class VenteHistorique {
  /// Numéro `VTE-YYYYMMDD-XXXX` — `null` pour les ventes historiques
  /// enregistrées avant le Module 8.
  final String? numeroVente;

  /// Clé de regroupement des lignes (`vente_uuid`, ou `ligne:<id>` pour les
  /// ventes historiques sans regroupement).
  final String cle;

  final DateTime? date;
  final String modePaiement;
  final double total;
  final List<LigneVenteHistorique> lignes;

  const VenteHistorique({
    required this.cle,
    required this.modePaiement,
    required this.total,
    required this.lignes,
    this.numeroVente,
    this.date,
  });

  int get nombreLignes => lignes.length;

  /// « VTE-20260916-0001 » ou « Vente sans numéro » (historique).
  String get libelleNumero =>
      (numeroVente == null || numeroVente!.isEmpty)
          ? 'Vente sans numéro'
          : numeroVente!;
}

/// Conversion tolérante d'une réponse RPC (`jsonb`) en Map.
///
/// `rpc_vente_valider` renvoie un objet jsonb : selon la version du client
/// Supabase, il arrive déjà décodé (Map) ou sous forme de chaîne JSON.
Map<String, dynamic>? reponseRpcEnMap(dynamic reponse) {
  if (reponse == null) return null;
  if (reponse is Map) return Map<String, dynamic>.from(reponse);
  if (reponse is String && reponse.trim().isNotEmpty) {
    try {
      final dynamic decode = jsonDecode(reponse);
      if (decode is Map) return Map<String, dynamic>.from(decode);
    } catch (_) {
      // Réponse illisible : traité comme une absence de résultat.
    }
  }
  return null;
}
