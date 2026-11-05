// lib/models/parametres_vente.dart
//
// MODULE 25 — FLEXIBILITÉ COMMERCIALE : réglages et règles.
//
// Le propriétaire décide, l'application obéit :
//   • négociation du prix d'une ligne (dans une limite) ;
//   • réduction sur le total du panier (montant ou pourcentage) ;
//   • cadeau commercial (produit offert, sortie de stock réelle).
//
// ⚠️ CE FICHIER NE DÉCIDE RIEN : les règles ici servent à GUIDER le vendeur.
//    Le serveur (`rpc_vente_valider`, migration 0108) revérifie tout et reste
//    la seule autorité — un appel direct à l'API ne peut pas contourner les
//    limites du propriétaire.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// 🎁 Une règle de bonus AUTOMATIQUE : au-delà d'un montant d'achat, le client
/// reçoit le produit indiqué — sans que le vendeur ait à le choisir.
class RegleBonusAuto {
  const RegleBonusAuto({
    required this.seuilMontant,
    required this.produitId,
    required this.quantite,
    this.produitNom,
    this.actif = true,
  });

  /// Montant d'achat à atteindre (sur le panier, avant réduction globale).
  final double seuilMontant;

  final int produitId;
  final double quantite;
  final String? produitNom;
  final bool actif;

  factory RegleBonusAuto.fromMap(Map<String, dynamic> map) {
    return RegleBonusAuto(
      seuilMontant: parseDouble(map['seuil_montant']),
      produitId: parseInt(map['produit_id']),
      quantite: parseDouble(map['quantite'], fallback: 1),
      produitNom: parseStringOrNull(map['produit_nom']),
      actif: parseBool(map['actif'], fallback: true),
    );
  }

  Map<String, dynamic> versJson() => <String, dynamic>{
        'seuil_montant': seuilMontant,
        'produit_id': produitId,
        'quantite': quantite,
        'actif': actif,
        if (produitNom != null) 'produit_nom': produitNom,
      };

  RegleBonusAuto copyWith({bool? actif}) => RegleBonusAuto(
        seuilMontant: seuilMontant,
        produitId: produitId,
        quantite: quantite,
        produitNom: produitNom,
        actif: actif ?? this.actif,
      );
}

/// Paramètres de vente flexible d'une boutique + droits du demandeur.
class ParametresVente {
  const ParametresVente({
    this.negociationActivee = false,
    this.negociationMaxPct = 0,
    this.negociationPrixMin,
    this.negociationCollaborateurs = const <String>[],
    this.reductionActivee = false,
    this.reductionMaxPct = 0,
    this.reductionMaxMontant,
    this.reductionCollaborateurs = const <String>[],
    this.cadeauxActifs = false,
    this.cadeauCollaborateurs = const <String>[],
    this.bonusAuto = const <RegleBonusAuto>[],
    this.validationSeuil,
    this.estProprietaire = false,
    this.peutNegocier = false,
    this.peutReduire = false,
    this.peutOffrir = false,
  });

  /// Tout est désactivé (boutique sans réglage, ou hors ligne sans cache).
  static const ParametresVente aucun = ParametresVente();

  final bool negociationActivee;

  /// Réduction maximale négociable sur une ligne, en % du prix catalogue.
  final double negociationMaxPct;

  /// Prix unitaire plancher éventuel (facultatif).
  final double? negociationPrixMin;

  /// Comptes autorisés à négocier (vide = tous ceux qui encaissent).
  final List<String> negociationCollaborateurs;

  final bool reductionActivee;
  final double reductionMaxPct;
  final double? reductionMaxMontant;
  final List<String> reductionCollaborateurs;

  final bool cadeauxActifs;
  final List<String> cadeauCollaborateurs;

  /// Règles de bonus automatique (seuil d'achat → produit offert).
  final List<RegleBonusAuto> bonusAuto;

  /// Au-delà de ce montant accordé (négociation + réduction), le responsable
  /// doit valider : le collaborateur est bloqué par le serveur.
  final double? validationSeuil;

  final bool estProprietaire;

  // Droits EFFECTIFS calculés par le serveur pour l'utilisateur connecté.
  final bool peutNegocier;
  final bool peutReduire;
  final bool peutOffrir;

  /// Une flexibilité quelconque est-elle possible pour ce vendeur ?
  bool get aQuelqueChose => peutNegocier || peutReduire || peutOffrir;

  factory ParametresVente.fromMap(Map<String, dynamic> map) {
    List<String> liste(String cle) {
      final dynamic brut = map[cle];
      if (brut is List) {
        return brut.map((dynamic e) => '$e').toList(growable: false);
      }
      return const <String>[];
    }

    return ParametresVente(
      negociationActivee: parseBool(map['negociation_activee']),
      negociationMaxPct: parseDouble(map['negociation_max_pct']),
      negociationPrixMin: parseDoubleOrNull(map['negociation_prix_min']),
      negociationCollaborateurs: liste('negociation_collaborateurs'),
      reductionActivee: parseBool(map['reduction_activee']),
      reductionMaxPct: parseDouble(map['reduction_max_pct']),
      reductionMaxMontant: parseDoubleOrNull(map['reduction_max_montant']),
      reductionCollaborateurs: liste('reduction_collaborateurs'),
      cadeauxActifs: parseBool(map['cadeaux_actifs']),
      cadeauCollaborateurs: liste('cadeau_collaborateurs'),
      bonusAuto: parseMapList(map['bonus_auto'])
          .map(RegleBonusAuto.fromMap)
          .toList(growable: false),
      validationSeuil: parseDoubleOrNull(map['validation_seuil']),
      estProprietaire: parseBool(map['est_proprietaire']),
      peutNegocier: parseBool(map['peut_negocier']),
      peutReduire: parseBool(map['peut_reduire']),
      peutOffrir: parseBool(map['peut_offrir']),
    );
  }

  ParametresVente copyWith({
    bool? negociationActivee,
    double? negociationMaxPct,
    double? negociationPrixMin,
    bool? effacerPrixMin,
    List<String>? negociationCollaborateurs,
    bool? reductionActivee,
    double? reductionMaxPct,
    double? reductionMaxMontant,
    bool? effacerReductionMax,
    List<String>? reductionCollaborateurs,
    bool? cadeauxActifs,
    List<String>? cadeauCollaborateurs,
    List<RegleBonusAuto>? bonusAuto,
    double? validationSeuil,
    bool? effacerSeuil,
  }) {
    return ParametresVente(
      negociationActivee: negociationActivee ?? this.negociationActivee,
      negociationMaxPct: negociationMaxPct ?? this.negociationMaxPct,
      negociationPrixMin:
          effacerPrixMin == true ? null : (negociationPrixMin ?? this.negociationPrixMin),
      negociationCollaborateurs:
          negociationCollaborateurs ?? this.negociationCollaborateurs,
      reductionActivee: reductionActivee ?? this.reductionActivee,
      reductionMaxPct: reductionMaxPct ?? this.reductionMaxPct,
      reductionMaxMontant: effacerReductionMax == true
          ? null
          : (reductionMaxMontant ?? this.reductionMaxMontant),
      reductionCollaborateurs:
          reductionCollaborateurs ?? this.reductionCollaborateurs,
      cadeauxActifs: cadeauxActifs ?? this.cadeauxActifs,
      cadeauCollaborateurs: cadeauCollaborateurs ?? this.cadeauCollaborateurs,
      bonusAuto: bonusAuto ?? this.bonusAuto,
      validationSeuil:
          effacerSeuil == true ? null : (validationSeuil ?? this.validationSeuil),
      estProprietaire: estProprietaire,
      peutNegocier: peutNegocier,
      peutReduire: peutReduire,
      peutOffrir: peutOffrir,
    );
  }

  /// Corps envoyé à `boutique_parametres_vente_enregistrer`.
  Map<String, dynamic> versRpc() => <String, dynamic>{
        'p_negociation_activee': negociationActivee,
        'p_negociation_max_pct': negociationMaxPct,
        'p_negociation_prix_min': negociationPrixMin,
        'p_negociation_collaborateurs': negociationCollaborateurs,
        'p_reduction_activee': reductionActivee,
        'p_reduction_max_pct': reductionMaxPct,
        'p_reduction_max_montant': reductionMaxMontant,
        'p_reduction_collaborateurs': reductionCollaborateurs,
        'p_cadeaux_actifs': cadeauxActifs,
        'p_cadeau_collaborateurs': cadeauCollaborateurs,
        'p_bonus_auto': bonusAuto
            .map((RegleBonusAuto r) => r.versJson())
            .toList(growable: false),
        'p_validation_seuil': validationSeuil,
      };
}

/// Type de réduction globale.
enum TypeReduction {
  montant('montant', 'Montant fixe'),
  pourcentage('pourcentage', 'Pourcentage');

  const TypeReduction(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypeReduction depuis(String? code) =>
      code == 'pourcentage' ? TypeReduction.pourcentage : TypeReduction.montant;
}

/// 🎁 Un produit offert au client.
class CadeauPanier {
  const CadeauPanier({
    required this.produitId,
    required this.nom,
    required this.prixCatalogue,
    required this.quantite,
    required this.quantiteBase,
    this.conditionnementId,
    this.unite,
    this.stockDisponible,
  });

  final int produitId;
  final String nom;

  /// Prix catalogue d'une unité offerte (sert à valoriser le cadeau).
  final double prixCatalogue;

  /// Quantité offerte, en unités vendues.
  final double quantite;

  /// Unités de base retirées du stock (farde de 12 → 12).
  final double quantiteBase;

  final String? conditionnementId;
  final String? unite;

  /// Stock disponible au moment du choix (contrôle local, le serveur tranche).
  final double? stockDisponible;

  /// Clé unique de la ligne cadeau (produit + conditionnement).
  String get cle => 'CADEAU:$produitId:${conditionnementId ?? 'base'}';

  /// Valeur du cadeau au prix du catalogue.
  double get valeur => prixCatalogue * quantite;

  Map<String, dynamic> versPayload() => <String, dynamic>{
        'produit_id': produitId,
        'quantite': quantite,
        'quantite_base': quantiteBase,
        if (conditionnementId != null) 'conditionnement_id': conditionnementId,
      };
}

/// Règles pures de la flexibilité commerciale (testables sans réseau).
abstract final class ReglesVenteFlexible {
  /// Tolérance d'arrondi (les montants sont en CDF, sans centimes).
  static const double tolerance = 0.01;

  /// Arrondi monétaire à 2 décimales.
  static double arrondi(double valeur) => (valeur * 100).roundToDouble() / 100;

  /// La négociation est-elle ouverte au vendeur ?
  static bool negociationPossible(ParametresVente p) =>
      p.negociationActivee && p.peutNegocier;

  static bool reductionPossible(ParametresVente p) =>
      p.reductionActivee && p.peutReduire;

  static bool cadeauPossible(ParametresVente p) =>
      p.cadeauxActifs && p.peutOffrir;

  /// Prix unitaire le plus bas autorisé pour une ligne.
  static double prixPlancher({
    required double prixCatalogue,
    required ParametresVente parametres,
  }) {
    double plancher = prixCatalogue;
    if (parametres.negociationMaxPct > 0 && !parametres.estProprietaire) {
      plancher = prixCatalogue * (1 - parametres.negociationMaxPct / 100);
    }
    final double? minimum = parametres.negociationPrixMin;
    if (minimum != null && minimum > plancher) plancher = minimum;
    return arrondi(plancher < 0 ? 0 : plancher);
  }

  /// Contrôle d'un prix négocié. Renvoie `null` si tout est bon, sinon le
  /// message à afficher au vendeur (mêmes mots que le serveur).
  static String? verifierPrixNegocie({
    required double prixCatalogue,
    required double prixNegocie,
    required ParametresVente parametres,
  }) {
    if (!negociationPossible(parametres)) {
      return 'La négociation des prix est désactivée pour votre boutique.';
    }
    if (prixNegocie <= 0) {
      return 'Le prix négocié doit être supérieur à zéro.';
    }
    if (prixNegocie > prixCatalogue + tolerance) {
      return 'Le prix négocié ne peut pas dépasser le prix catalogue.';
    }
    final double plancher =
        prixPlancher(prixCatalogue: prixCatalogue, parametres: parametres);
    if (!parametres.estProprietaire && prixNegocie < plancher - tolerance) {
      return 'Prix minimum autorisé : $plancher.';
    }
    return null;
  }

  /// Réduction réellement appliquée à un total.
  static double remiseEnMontant({
    required double base,
    required double valeur,
    required TypeReduction type,
  }) {
    if (valeur <= 0 || base <= 0) return 0;
    final double montant =
        type == TypeReduction.pourcentage ? base * valeur / 100 : valeur;
    return arrondi(montant > base ? base : montant);
  }

  /// Plafond de réduction accordable sur un panier.
  static double remisePlafond({
    required double base,
    required ParametresVente parametres,
  }) {
    if (base <= 0) return 0;
    double plafond = base;
    if (!parametres.estProprietaire) {
      if (parametres.reductionMaxPct > 0) {
        plafond = base * parametres.reductionMaxPct / 100;
      }
      final double? maximum = parametres.reductionMaxMontant;
      if (maximum != null && maximum < plafond) plafond = maximum;
    }
    return arrondi(plafond);
  }

  /// Contrôle d'une réduction globale.
  static String? verifierRemise({
    required double base,
    required double valeur,
    required TypeReduction type,
    required ParametresVente parametres,
  }) {
    if (valeur <= 0) return null;
    if (!reductionPossible(parametres)) {
      return 'Les réductions sont désactivées pour votre boutique.';
    }
    if (type == TypeReduction.pourcentage && valeur > 100) {
      return 'Une réduction en pourcentage ne peut pas dépasser 100 %.';
    }
    final double montant = remiseEnMontant(base: base, valeur: valeur, type: type);
    final double plafond =
        remisePlafond(base: base, parametres: parametres);
    if (!parametres.estProprietaire && montant > plafond + tolerance) {
      return 'Réduction maximale autorisée : $plafond.';
    }
    return null;
  }

  /// Le responsable doit-il valider (négociation + réduction au-delà du seuil) ?
  static bool validationRequise({
    required double montantAccorde,
    required ParametresVente parametres,
  }) {
    final double? seuil = parametres.validationSeuil;
    if (seuil == null || seuil <= 0) return false;
    return montantAccorde > seuil + tolerance;
  }
}
