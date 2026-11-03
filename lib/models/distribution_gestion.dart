// lib/models/distribution_gestion.dart
//
// 🚚 MODULE 24 — DISTRIBUTION : PRODUCTION, STOCK, TERRAIN, CAISSE.
//
// Objets PURS (aucun import Flutter, aucun accès réseau). Ils lisent les
// réponses JSON des RPC `dist_*` et exposent des getters de lecture métier
// (statuts lisibles, soldes, écarts). Les calculs d'autorité restent côté
// serveur : ces classes ne font que présenter ce que le serveur a confirmé.

import 'package:biashara_yangu/utils/json_parsing.dart';

// ---------------------------------------------------------------------------
// RÔLES
// ---------------------------------------------------------------------------

/// Rôle du compte DANS la distribution (indépendant du rôle global).
enum RoleDistribution {
  proprietaire('proprietaire', 'Propriétaire'),
  gerant('gerant', 'Gérant'),
  production('production', 'Responsable de production'),
  stock('stock', 'Gestionnaire de stock'),
  commercial('commercial', 'Commercial'),
  comptable('comptable', 'Comptable'),
  aucun('aucun', 'Aucun rôle distribution');

  const RoleDistribution(this.code, this.libelle);

  final String code;
  final String libelle;

  bool get estDirection =>
      this == RoleDistribution.proprietaire || this == RoleDistribution.gerant;

  bool get peutGererCollaborateurs => this == RoleDistribution.proprietaire;

  bool get peutProduire =>
      this == RoleDistribution.production || estDirection;

  bool get peutGererStock =>
      this == RoleDistribution.stock || estDirection;

  bool get peutVendre => this == RoleDistribution.commercial;

  bool get peutValiderArgent =>
      this == RoleDistribution.comptable || estDirection;

  static RoleDistribution depuisCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    for (final RoleDistribution r in values) {
      if (r.code == valeur) return r;
    }
    return RoleDistribution.aucun;
  }
}

// ---------------------------------------------------------------------------
// OPÉRATIONS EN ATTENTE
// ---------------------------------------------------------------------------

/// Une opération qui attend une confirmation précise.
class OperationAttente {
  const OperationAttente({
    required this.type,
    required this.id,
    this.numero = '',
    this.libelle = '',
    this.role = RoleDistribution.aucun,
    this.date,
  });

  final String type;
  final String id;
  final String numero;
  final String libelle;
  final RoleDistribution role;
  final DateTime? date;

  String get icone => switch (type) {
        'reception_intrants' => '📥',
        'demande_intrants_stock' => '📋',
        'demande_intrants_reception' => '🧪',
        'production_reception' => '🏭',
        'demande_commercial_production' => '🛒',
        'demande_commercial_stock' => '📦',
        'demande_commercial_reception' => '🚚',
        'retour_reception' => '↩️',
        'remise_comptable' => '💵',
        'remise_gerant' => '✅',
        'depense_validation' => '🧾',
        'anomalie' => '⚠️',
        _ => '•',
      };

  factory OperationAttente.depuisJson(Map<String, dynamic> json) {
    return OperationAttente(
      type: parseString(json['type']),
      id: parseString(json['id']),
      numero: parseString(json['numero']),
      libelle: parseString(json['libelle']),
      role: RoleDistribution.depuisCode(parseString(json['role'])),
      date: parseDateTimeOrNull(json['date']),
    );
  }
}

// ---------------------------------------------------------------------------
// TABLEAU DE BORD
// ---------------------------------------------------------------------------

/// Toutes les données du tableau de bord Distribution.
class TableauBordDistribution {
  const TableauBordDistribution({
    this.role = RoleDistribution.aucun,
    this.devise = 'CDF',
    this.intrantsTotal = 0,
    this.pet = 0,
    this.caps = 0,
    this.bouteillesVides = 0,
    this.produitsTotal = 0,
    this.fardes = 0,
    this.bouteilles = 0,
    this.bidons = 0,
    this.attribuesCommerciaux = 0,
    this.demandesIntrantsAttenteStock = 0,
    this.demandesIntrantsAttenteProduction = 0,
    this.productionsAttenteStock = 0,
    this.receptionsAttenteGerant = 0,
    this.demandesCommercialesEnCours = 0,
    this.retoursAttenteStock = 0,
    this.remisesAttenteComptable = 0,
    this.remisesAttenteGerant = 0,
    this.depensesAttente = 0,
    this.ventesTotal = 0,
    this.collecteCommerciaux = 0,
    this.montantRecuComptable = 0,
    this.collecteNonRemise = 0,
    this.caisseSolde = 0,
    this.depensesMois = 0,
    this.anomaliesOuvertes = 0,
    this.tourneesEnCours = 0,
    this.operations = const <OperationAttente>[],
  });

  final RoleDistribution role;
  final String devise;

  final double intrantsTotal;
  final double pet;
  final double caps;
  final double bouteillesVides;

  final double produitsTotal;
  final double fardes;
  final double bouteilles;
  final double bidons;

  final double attribuesCommerciaux;

  final int demandesIntrantsAttenteStock;
  final int demandesIntrantsAttenteProduction;
  final int productionsAttenteStock;
  final int receptionsAttenteGerant;
  final int demandesCommercialesEnCours;
  final int retoursAttenteStock;
  final int remisesAttenteComptable;
  final int remisesAttenteGerant;
  final int depensesAttente;

  final double ventesTotal;
  final double collecteCommerciaux;
  final double montantRecuComptable;
  final double collecteNonRemise;
  final double caisseSolde;
  final double depensesMois;

  final int anomaliesOuvertes;
  final int tourneesEnCours;
  final List<OperationAttente> operations;

  /// Résultat approximatif : ventes − dépenses validées du mois.
  /// (Le coût des marchandises n'est pas déduit ici : le serveur reste
  /// l'autorité pour la marge comptable.)
  double get resultatBrut => ventesTotal - depensesMois;

  int get totalEnAttente => demandesIntrantsAttenteStock +
      demandesIntrantsAttenteProduction +
      productionsAttenteStock +
      receptionsAttenteGerant +
      demandesCommercialesEnCours +
      retoursAttenteStock +
      remisesAttenteComptable +
      remisesAttenteGerant +
      depensesAttente +
      anomaliesOuvertes;

  factory TableauBordDistribution.depuisJson(Map<String, dynamic> json) {
    final Map<String, dynamic> intrants =
        parseMap(json['intrants']) ?? <String, dynamic>{};
    final Map<String, dynamic> produits =
        parseMap(json['produits']) ?? <String, dynamic>{};

    return TableauBordDistribution(
      role: RoleDistribution.depuisCode(parseString(json['role'])),
      devise: parseString(json['devise'], fallback: 'CDF'),
      intrantsTotal: parseDouble(intrants['total']),
      pet: parseDouble(intrants['pet']),
      caps: parseDouble(intrants['caps']),
      bouteillesVides: parseDouble(intrants['bouteilles_vides']),
      produitsTotal: parseDouble(produits['total']),
      fardes: parseDouble(produits['fardes']),
      bouteilles: parseDouble(produits['bouteilles']),
      bidons: parseDouble(produits['bidons']),
      attribuesCommerciaux: parseDouble(json['attribues_commerciaux']),
      demandesIntrantsAttenteStock:
          parseInt(json['demandes_intrants_attente_stock']),
      demandesIntrantsAttenteProduction:
          parseInt(json['demandes_intrants_attente_production']),
      productionsAttenteStock: parseInt(json['productions_attente_stock']),
      receptionsAttenteGerant: parseInt(json['receptions_attente_gerant']),
      demandesCommercialesEnCours:
          parseInt(json['demandes_commerciales_en_cours']),
      retoursAttenteStock: parseInt(json['retours_attente_stock']),
      remisesAttenteComptable: parseInt(json['remises_attente_comptable']),
      remisesAttenteGerant: parseInt(json['remises_attente_gerant']),
      depensesAttente: parseInt(json['depenses_attente']),
      ventesTotal: parseDouble(json['ventes_total']),
      collecteCommerciaux: parseDouble(json['collecte_commerciaux']),
      montantRecuComptable: parseDouble(json['montant_recu_comptable']),
      collecteNonRemise: parseDouble(json['collecte_non_remise']),
      caisseSolde: parseDouble(json['caisse_solde']),
      depensesMois: parseDouble(json['depenses_mois']),
      anomaliesOuvertes: parseInt(json['anomalies_ouvertes']),
      tourneesEnCours: parseInt(json['tournees_en_cours']),
      operations: parseMapList(json['operations'])
          .map(OperationAttente.depuisJson)
          .toList(growable: false),
    );
  }
}

// ---------------------------------------------------------------------------
// STOCK
// ---------------------------------------------------------------------------

/// Un poste de stock : intrant OU produit fini.
class LigneStockDistribution {
  const LigneStockDistribution({
    required this.id,
    this.nom = '',
    this.unite = '',
    this.stock = 0,
    this.seuil = 0,
    this.prix = 0,
    this.format = '',
    this.estIntrant = true,
  });

  final String id;
  final String nom;
  final String unite;
  final double stock;
  final double seuil;
  final double prix;
  final String format;
  final bool estIntrant;

  bool get alerte => stock <= seuil;
  bool get rupture => stock <= 0;

  String get designation =>
      format.isEmpty ? nom : '$nom · $format';

  factory LigneStockDistribution.depuisJson(
    Map<String, dynamic> json, {
    required bool intrant,
  }) {
    return LigneStockDistribution(
      id: parseString(json['id']),
      nom: parseString(json['nom']),
      unite: parseString(json['unite']),
      stock: parseDouble(json['stock']),
      seuil: parseDouble(json['seuil']),
      prix: parseDouble(intrant ? json['prix'] : json['prix_vente']),
      format: parseString(json['format']),
      estIntrant: intrant,
    );
  }
}

/// Résumé complet du stock (intrants + produits finis).
class StockDistribution {
  const StockDistribution({
    this.role = RoleDistribution.aucun,
    this.intrants = const <LigneStockDistribution>[],
    this.produits = const <LigneStockDistribution>[],
  });

  final RoleDistribution role;
  final List<LigneStockDistribution> intrants;
  final List<LigneStockDistribution> produits;

  double get totalIntrants =>
      intrants.fold<double>(0, (double t, LigneStockDistribution l) => t + l.stock);
  double get totalProduits =>
      produits.fold<double>(0, (double t, LigneStockDistribution l) => t + l.stock);
  int get alertes =>
      intrants.where((LigneStockDistribution l) => l.alerte).length +
      produits.where((LigneStockDistribution l) => l.alerte).length;

  static StockDistribution depuisJson(Map<String, dynamic> json) {
    return StockDistribution(
      role: RoleDistribution.depuisCode(parseString(json['role'])),
      intrants: parseMapList(json['intrants'])
          .map((Map<String, dynamic> m) =>
              LigneStockDistribution.depuisJson(m, intrant: true))
          .toList(growable: false),
      produits: parseMapList(json['produits'])
          .map((Map<String, dynamic> m) =>
              LigneStockDistribution.depuisJson(m, intrant: false))
          .toList(growable: false),
    );
  }
}

/// Une ligne de réception d'intrants.
class LigneReceptionIntrant {
  const LigneReceptionIntrant({
    required this.intrantId,
    this.nom = '',
    this.unite = '',
    this.quantiteAnnoncee = 0,
    this.quantiteComptee = 0,
  });

  final String intrantId;
  final String nom;
  final String unite;
  final double quantiteAnnoncee;
  final double quantiteComptee;

  double get ecart => quantiteComptee - quantiteAnnoncee;

  factory LigneReceptionIntrant.depuisJson(Map<String, dynamic> json) {
    return LigneReceptionIntrant(
      intrantId: parseString(json['intrant_id']),
      nom: parseString(json['nom']),
      unite: parseString(json['unite']),
      quantiteAnnoncee: parseDouble(json['quantite_annoncee']),
      quantiteComptee: parseDouble(json['quantite_comptee']),
    );
  }
}

/// Réception d'intrants (double confirmation).
class ReceptionIntrants {
  const ReceptionIntrants({
    required this.id,
    this.numero = '',
    this.fournisseur = '',
    this.statut = 'attente_gerant',
    this.note = '',
    this.lignes = const <LigneReceptionIntrant>[],
    this.creeLe,
  });

  final String id;
  final String numero;
  final String fournisseur;
  final String statut;
  final String note;
  final List<LigneReceptionIntrant> lignes;
  final DateTime? creeLe;

  bool get enAttente => statut == 'attente_gerant';
  bool get validee => statut == 'validee';

  String get libelleStatut => switch (statut) {
        'validee' => 'Validée',
        'refusee' => 'Refusée',
        _ => 'Attente du gérant',
      };

  factory ReceptionIntrants.depuisJson(Map<String, dynamic> json) {
    return ReceptionIntrants(
      id: parseString(json['id']),
      numero: parseString(json['numero']),
      fournisseur: parseString(json['fournisseur']),
      statut: parseString(json['statut'], fallback: 'attente_gerant'),
      note: parseString(json['note']),
      creeLe: parseDateTimeOrNull(json['cree_le']),
      lignes: parseMapList(json['lignes'])
          .map(LigneReceptionIntrant.depuisJson)
          .toList(growable: false),
    );
  }
}

// ---------------------------------------------------------------------------
// DEMANDES D'INTRANTS
// ---------------------------------------------------------------------------

class LigneDemandeIntrant {
  const LigneDemandeIntrant({
    required this.intrantId,
    this.nom = '',
    this.unite = '',
    this.demandee = 0,
    this.autorisee = 0,
    this.sortie = 0,
    this.recue = 0,
  });

  final String intrantId;
  final String nom;
  final String unite;
  final double demandee;
  final double autorisee;
  final double sortie;
  final double recue;

  double get ecart => sortie - recue;

  factory LigneDemandeIntrant.depuisJson(Map<String, dynamic> json) {
    return LigneDemandeIntrant(
      intrantId: parseString(json['intrant_id']),
      nom: parseString(json['nom']),
      unite: parseString(json['unite']),
      demandee: parseDouble(json['quantite_demandee']),
      autorisee: parseDouble(json['quantite_autorisee']),
      sortie: parseDouble(json['quantite_sortie']),
      recue: parseDouble(json['quantite_recue']),
    );
  }
}

class DemandeIntrant {
  const DemandeIntrant({
    required this.id,
    this.numero = '',
    this.statut = 'attente_stock',
    this.note = '',
    this.motif = '',
    this.demandeur = '',
    this.creeLe,
    this.lignes = const <LigneDemandeIntrant>[],
  });

  final String id;
  final String numero;
  final String statut;
  final String note;
  final String motif;
  final String demandeur;
  final DateTime? creeLe;
  final List<LigneDemandeIntrant> lignes;

  bool get attenteStock => statut == 'attente_stock';
  bool get attenteReception => statut == 'attente_reception';
  bool get enLitige => statut == 'en_litige';

  String get libelleStatut => switch (statut) {
        'attente_stock' => 'Attente du stock',
        'attente_reception' => 'Attente du producteur',
        'recue' => 'Reçue',
        'refusee' => 'Refusée',
        'en_litige' => 'En litige',
        _ => statut,
      };

  factory DemandeIntrant.depuisJson(Map<String, dynamic> json) {
    return DemandeIntrant(
      id: parseString(json['id']),
      numero: parseString(json['numero']),
      statut: parseString(json['statut'], fallback: 'attente_stock'),
      note: parseString(json['note']),
      motif: parseString(json['motif']),
      demandeur: parseString(json['demandeur']),
      creeLe: parseDateTimeOrNull(json['cree_le']),
      lignes: parseMapList(json['lignes'])
          .map(LigneDemandeIntrant.depuisJson)
          .toList(growable: false),
    );
  }
}

// ---------------------------------------------------------------------------
// PRODUCTIONS
// ---------------------------------------------------------------------------

class LigneProductionIntrant {
  const LigneProductionIntrant({
    required this.intrantId,
    this.nom = '',
    this.unite = '',
    this.recue = 0,
    this.consommee = 0,
    this.perdue = 0,
    this.restante = 0,
  });

  final String intrantId;
  final String nom;
  final String unite;
  final double recue;
  final double consommee;
  final double perdue;
  final double restante;

  factory LigneProductionIntrant.depuisJson(Map<String, dynamic> json) {
    return LigneProductionIntrant(
      intrantId: parseString(json['intrant_id']),
      nom: parseString(json['nom']),
      unite: parseString(json['unite']),
      recue: parseDouble(json['quantite_recue']),
      consommee: parseDouble(json['quantite_consommee']),
      perdue: parseDouble(json['quantite_perdue']),
      restante: parseDouble(json['quantite_restante']),
    );
  }
}

class LigneProductionSortie {
  const LigneProductionSortie({
    required this.produitId,
    this.nom = '',
    this.unite = '',
    this.produite = 0,
    this.remise = 0,
    this.recue = 0,
    this.constat = '',
  });

  final String produitId;
  final String nom;
  final String unite;
  final double produite;
  final double remise;
  final double recue;
  final String constat;

  double get ecart => remise - recue;

  factory LigneProductionSortie.depuisJson(Map<String, dynamic> json) {
    return LigneProductionSortie(
      produitId: parseString(json['produit_id']),
      nom: parseString(json['nom']),
      unite: parseString(json['unite']),
      produite: parseDouble(json['quantite_produite']),
      remise: parseDouble(json['quantite_remise']),
      recue: parseDouble(json['quantite_recue']),
      constat: parseString(json['constat']),
    );
  }
}

class ProductionDistribution {
  const ProductionDistribution({
    required this.id,
    this.numero = '',
    this.statut = 'attente_stock',
    this.note = '',
    this.motifPertes = '',
    this.responsable = '',
    this.creeLe,
    this.intrants = const <LigneProductionIntrant>[],
    this.sorties = const <LigneProductionSortie>[],
  });

  final String id;
  final String numero;
  final String statut;
  final String note;
  final String motifPertes;
  final String responsable;
  final DateTime? creeLe;
  final List<LigneProductionIntrant> intrants;
  final List<LigneProductionSortie> sorties;

  bool get attenteStock => statut == 'attente_stock';
  bool get enLitige => statut == 'en_litige';

  double get quantiteProduite => sorties.fold<double>(
      0, (double t, LigneProductionSortie s) => t + s.produite);
  double get quantiteRemise => sorties.fold<double>(
      0, (double t, LigneProductionSortie s) => t + s.remise);
  double get quantiteRecue => sorties.fold<double>(
      0, (double t, LigneProductionSortie s) => t + s.recue);
  double get pertesIntrants => intrants.fold<double>(
      0, (double t, LigneProductionIntrant l) => t + l.perdue);
  double get resteIntrants => intrants.fold<double>(
      0, (double t, LigneProductionIntrant l) => t + l.restante);

  String get libelleStatut => switch (statut) {
        'attente_stock' => 'Attente de réception au stock',
        'cloturee' => 'Clôturée',
        'en_litige' => 'En litige',
        _ => statut,
      };

  factory ProductionDistribution.depuisJson(Map<String, dynamic> json) {
    return ProductionDistribution(
      id: parseString(json['id']),
      numero: parseString(json['numero']),
      statut: parseString(json['statut'], fallback: 'attente_stock'),
      note: parseString(json['note']),
      motifPertes: parseString(json['motif_pertes']),
      responsable: parseString(json['responsable']),
      creeLe: parseDateTimeOrNull(json['cree_le']),
      intrants: parseMapList(json['intrants'])
          .map(LigneProductionIntrant.depuisJson)
          .toList(growable: false),
      sorties: parseMapList(json['sorties'])
          .map(LigneProductionSortie.depuisJson)
          .toList(growable: false),
    );
  }
}

// ---------------------------------------------------------------------------
// DEMANDES COMMERCIALES
// ---------------------------------------------------------------------------

class LigneDemandeCommercial {
  const LigneDemandeCommercial({
    required this.produitId,
    this.nom = '',
    this.unite = '',
    this.demandee = 0,
    this.confirmee = 0,
    this.sortie = 0,
    this.recue = 0,
  });

  final String produitId;
  final String nom;
  final String unite;
  final double demandee;
  final double confirmee;
  final double sortie;
  final double recue;

  factory LigneDemandeCommercial.depuisJson(Map<String, dynamic> json) {
    return LigneDemandeCommercial(
      produitId: parseString(json['produit_id']),
      nom: parseString(json['nom']),
      unite: parseString(json['unite']),
      demandee: parseDouble(json['quantite_demandee']),
      confirmee: parseDouble(json['quantite_confirmee']),
      sortie: parseDouble(json['quantite_sortie']),
      recue: parseDouble(json['quantite_recue']),
    );
  }
}

class DemandeCommercial {
  const DemandeCommercial({
    required this.id,
    this.numero = '',
    this.statut = 'attente_production',
    this.note = '',
    this.motif = '',
    this.commercialId = '',
    this.commercial = '',
    this.creeLe,
    this.lignes = const <LigneDemandeCommercial>[],
  });

  final String id;
  final String numero;
  final String statut;
  final String note;
  final String motif;
  final String commercialId;
  final String commercial;
  final DateTime? creeLe;
  final List<LigneDemandeCommercial> lignes;

  bool get attenteProduction => statut == 'attente_production';
  bool get attenteStock => statut == 'attente_stock';
  bool get attenteCommercial => statut == 'attente_commercial';
  bool get enLitige => statut == 'en_litige';

  String get libelleStatut => switch (statut) {
        'attente_production' => 'Attente production',
        'attente_stock' => 'Attente stock',
        'attente_commercial' => 'Attente commercial',
        'recue' => 'Reçue',
        'refusee_production' => 'Refusée (production)',
        'refusee_stock' => 'Refusée (stock)',
        'en_litige' => 'En litige',
        _ => statut,
      };

  factory DemandeCommercial.depuisJson(Map<String, dynamic> json) {
    return DemandeCommercial(
      id: parseString(json['id']),
      numero: parseString(json['numero']),
      statut: parseString(json['statut'], fallback: 'attente_production'),
      note: parseString(json['note']),
      motif: parseString(json['motif']),
      commercialId: parseString(json['commercial_id']),
      commercial: parseString(json['commercial']),
      creeLe: parseDateTimeOrNull(json['cree_le']),
      lignes: parseMapList(json['lignes'])
          .map(LigneDemandeCommercial.depuisJson)
          .toList(growable: false),
    );
  }
}

// ---------------------------------------------------------------------------
// CLIENTS ET VENTES
// ---------------------------------------------------------------------------

class ClientDistribution {
  const ClientDistribution({
    required this.id,
    this.nom = '',
    this.telephone = '',
    this.adresse = '',
    this.zone = '',
    this.note = '',
    this.commercialId = '',
    this.commercial = '',
  });

  final String id;
  final String nom;
  final String telephone;
  final String adresse;
  final String zone;
  final String note;
  final String commercialId;
  final String commercial;

  String get localisation =>
      <String>[adresse, zone].where((String s) => s.trim().isNotEmpty).join(' · ');

  factory ClientDistribution.depuisJson(Map<String, dynamic> json) {
    return ClientDistribution(
      id: parseString(json['id']),
      nom: parseString(json['nom']),
      telephone: parseString(json['telephone']),
      adresse: parseString(json['adresse']),
      zone: parseString(json['zone']),
      note: parseString(json['note']),
      commercialId: parseString(json['commercial_id']),
      commercial: parseString(json['commercial']),
    );
  }
}

class LigneVenteDistribution {
  const LigneVenteDistribution({
    this.nom = '',
    this.quantite = 0,
    this.prixUnitaire = 0,
    this.total = 0,
  });

  final String nom;
  final double quantite;
  final double prixUnitaire;
  final double total;

  factory LigneVenteDistribution.depuisJson(Map<String, dynamic> json) {
    return LigneVenteDistribution(
      nom: parseString(json['nom']),
      quantite: parseDouble(json['quantite']),
      prixUnitaire: parseDouble(json['prix_unitaire']),
      total: parseDouble(json['total']),
    );
  }
}

class VenteDistribution {
  const VenteDistribution({
    required this.id,
    this.numero = '',
    this.date,
    this.commercialId = '',
    this.commercial = '',
    this.client = '',
    this.total = 0,
    this.montantPaye = 0,
    this.credit = 0,
    this.modePaiement = '',
    this.lignes = const <LigneVenteDistribution>[],
  });

  final String id;
  final String numero;
  final DateTime? date;
  final String commercialId;
  final String commercial;
  final String client;
  final double total;
  final double montantPaye;
  final double credit;
  final String modePaiement;
  final List<LigneVenteDistribution> lignes;

  bool get aCredit => credit > 0.009;

  factory VenteDistribution.depuisJson(Map<String, dynamic> json) {
    return VenteDistribution(
      id: parseString(json['id']),
      numero: parseString(json['numero']),
      date: parseDateTimeOrNull(json['date']),
      commercialId: parseString(json['commercial_id']),
      commercial: parseString(json['commercial']),
      client: parseString(json['client'], fallback: 'Client comptant'),
      total: parseDouble(json['total']),
      montantPaye: parseDouble(json['montant_paye']),
      credit: parseDouble(json['credit']),
      modePaiement: parseString(json['mode_paiement']),
      lignes: parseMapList(json['lignes'])
          .map(LigneVenteDistribution.depuisJson)
          .toList(growable: false),
    );
  }
}

/// Facture prête à imprimer/partager.
class FactureDistribution {
  const FactureDistribution({
    this.entreprise = '',
    this.entrepriseAdresse = '',
    this.entrepriseTelephone = '',
    this.numero = '',
    this.date,
    this.commercial = '',
    this.client = '',
    this.clientTelephone = '',
    this.clientAdresse = '',
    this.modePaiement = '',
    this.lignes = const <LigneVenteDistribution>[],
    this.total = 0,
    this.montantPaye = 0,
    this.credit = 0,
  });

  final String entreprise;
  final String entrepriseAdresse;
  final String entrepriseTelephone;
  final String numero;
  final DateTime? date;
  final String commercial;
  final String client;
  final String clientTelephone;
  final String clientAdresse;
  final String modePaiement;
  final List<LigneVenteDistribution> lignes;
  final double total;
  final double montantPaye;
  final double credit;

  static FactureDistribution depuisJson(Map<String, dynamic> json) {
    return FactureDistribution(
      entreprise: parseString(json['entreprise'], fallback: 'Entreprise'),
      entrepriseAdresse: parseString(json['entreprise_adresse']),
      entrepriseTelephone: parseString(json['entreprise_telephone']),
      numero: parseString(json['numero']),
      date: parseDateTimeOrNull(json['date']),
      commercial: parseString(json['commercial']),
      client: parseString(json['client'], fallback: 'Client comptant'),
      clientTelephone: parseString(json['client_telephone']),
      clientAdresse: parseString(json['client_adresse']),
      modePaiement: parseString(json['mode_paiement']),
      lignes: parseMapList(json['lignes'])
          .map(LigneVenteDistribution.depuisJson)
          .toList(growable: false),
      total: parseDouble(json['total']),
      montantPaye: parseDouble(json['montant_paye']),
      credit: parseDouble(json['credit']),
    );
  }
}

// ---------------------------------------------------------------------------
// RETOURS, REMISES, CAISSE, DÉPENSES, ANOMALIES
// ---------------------------------------------------------------------------

class LigneRetour {
  const LigneRetour({
    required this.produitId,
    this.nom = '',
    this.unite = '',
    this.declaree = 0,
    this.recue = 0,
  });

  final String produitId;
  final String nom;
  final String unite;
  final double declaree;
  final double recue;

  double get ecart => declaree - recue;

  factory LigneRetour.depuisJson(Map<String, dynamic> json) {
    return LigneRetour(
      produitId: parseString(json['produit_id']),
      nom: parseString(json['nom']),
      unite: parseString(json['unite']),
      declaree: parseDouble(json['quantite_declaree']),
      recue: parseDouble(json['quantite_recue']),
    );
  }
}

class RetourCommercial {
  const RetourCommercial({
    required this.id,
    this.numero = '',
    this.statut = 'attente_stock',
    this.note = '',
    this.motif = '',
    this.commercialId = '',
    this.commercial = '',
    this.creeLe,
    this.lignes = const <LigneRetour>[],
  });

  final String id;
  final String numero;
  final String statut;
  final String note;
  final String motif;
  final String commercialId;
  final String commercial;
  final DateTime? creeLe;
  final List<LigneRetour> lignes;

  bool get enAttente => statut == 'attente_stock';
  String get libelleStatut => switch (statut) {
        'recue' => 'Reçu',
        'en_litige' => 'En litige',
        _ => 'Attente du stock',
      };

  factory RetourCommercial.depuisJson(Map<String, dynamic> json) {
    return RetourCommercial(
      id: parseString(json['id']),
      numero: parseString(json['numero']),
      statut: parseString(json['statut'], fallback: 'attente_stock'),
      note: parseString(json['note']),
      motif: parseString(json['motif']),
      commercialId: parseString(json['commercial_id']),
      commercial: parseString(json['commercial']),
      creeLe: parseDateTimeOrNull(json['cree_le']),
      lignes: parseMapList(json['lignes'])
          .map(LigneRetour.depuisJson)
          .toList(growable: false),
    );
  }
}

class RemiseArgent {
  const RemiseArgent({
    required this.id,
    this.numero = '',
    this.statut = 'declaree',
    this.commercialId = '',
    this.commercial = '',
    this.montantDeclare = 0,
    this.montantRecu = 0,
    this.montantValide = 0,
    this.modePaiement = '',
    this.motif = '',
    this.declareLe,
    this.recuLe,
    this.valideLe,
  });

  final String id;
  final String numero;
  final String statut;
  final String commercialId;
  final String commercial;
  final double montantDeclare;
  final double montantRecu;
  final double montantValide;
  final String modePaiement;
  final String motif;
  final DateTime? declareLe;
  final DateTime? recuLe;
  final DateTime? valideLe;

  bool get attenteComptable => statut == 'declaree';
  bool get attenteGerant => statut == 'recue' || statut == 'litige';

  String get libelleStatut => switch (statut) {
        'declaree' => 'Déclarée (attente comptable)',
        'recue' => 'Reçue (attente gérant)',
        'litige' => 'Écart à valider',
        'validee' => 'Validée',
        'refusee' => 'Refusée',
        _ => statut,
      };

  factory RemiseArgent.depuisJson(Map<String, dynamic> json) {
    return RemiseArgent(
      id: parseString(json['id']),
      numero: parseString(json['numero']),
      statut: parseString(json['statut'], fallback: 'declaree'),
      commercialId: parseString(json['commercial_id']),
      commercial: parseString(json['commercial']),
      montantDeclare: parseDouble(json['montant_declare']),
      montantRecu: parseDouble(json['montant_recu']),
      montantValide: parseDouble(json['montant_valide']),
      modePaiement: parseString(json['mode_paiement']),
      motif: parseString(json['motif']),
      declareLe: parseDateTimeOrNull(json['declare_le']),
      recuLe: parseDateTimeOrNull(json['recu_le']),
      valideLe: parseDateTimeOrNull(json['valide_le']),
    );
  }
}

class MouvementCaisseDistribution {
  const MouvementCaisseDistribution({
    required this.id,
    this.sens = 'entree',
    this.montant = 0,
    this.motif = '',
    this.categorie = '',
    this.auteur = '',
    this.date,
  });

  final String id;
  final String sens;
  final double montant;
  final String motif;
  final String categorie;
  final String auteur;
  final DateTime? date;

  bool get entree => sens == 'entree';

  factory MouvementCaisseDistribution.depuisJson(Map<String, dynamic> json) {
    return MouvementCaisseDistribution(
      id: parseString(json['id']),
      sens: parseString(json['sens'], fallback: 'entree'),
      montant: parseDouble(json['montant']),
      motif: parseString(json['motif']),
      categorie: parseString(json['categorie']),
      auteur: parseString(json['auteur']),
      date: parseDateTimeOrNull(json['date']),
    );
  }
}

class ResumeCaisseDistribution {
  const ResumeCaisseDistribution({
    this.soldeInitial = 0,
    this.entrees = 0,
    this.sorties = 0,
    this.solde = 0,
    this.mouvements = const <MouvementCaisseDistribution>[],
  });

  final double soldeInitial;
  final double entrees;
  final double sorties;
  final double solde;
  final List<MouvementCaisseDistribution> mouvements;

  static ResumeCaisseDistribution depuisJson(Map<String, dynamic> json) {
    return ResumeCaisseDistribution(
      soldeInitial: parseDouble(json['solde_initial']),
      entrees: parseDouble(json['entrees']),
      sorties: parseDouble(json['sorties']),
      solde: parseDouble(json['solde']),
      mouvements: parseMapList(json['mouvements'])
          .map(MouvementCaisseDistribution.depuisJson)
          .toList(growable: false),
    );
  }
}

class DepenseDistribution {
  const DepenseDistribution({
    required this.id,
    this.numero = '',
    this.categorie = 'autre',
    this.montant = 0,
    this.devise = 'CDF',
    this.motif = '',
    this.date,
    this.justificatif = '',
    this.statut = 'en_attente',
    this.motifRefus = '',
    this.auteur = '',
  });

  final String id;
  final String numero;
  final String categorie;
  final double montant;
  final String devise;
  final String motif;
  final DateTime? date;
  final String justificatif;
  final String statut;
  final String motifRefus;
  final String auteur;

  bool get enAttente => statut == 'en_attente';

  String get libelleStatut => switch (statut) {
        'validee' => 'Validée',
        'refusee' => 'Refusée',
        _ => 'En attente',
      };

  factory DepenseDistribution.depuisJson(Map<String, dynamic> json) {
    return DepenseDistribution(
      id: parseString(json['id']),
      numero: parseString(json['numero']),
      categorie: parseString(json['categorie'], fallback: 'autre'),
      montant: parseDouble(json['montant']),
      devise: parseString(json['devise'], fallback: 'CDF'),
      motif: parseString(json['motif']),
      date: parseDateTimeOrNull(json['date_depense']),
      justificatif: parseString(json['justificatif']),
      statut: parseString(json['statut'], fallback: 'en_attente'),
      motifRefus: parseString(json['motif_refus']),
      auteur: parseString(json['auteur']),
    );
  }
}

class AnomalieDistribution {
  const AnomalieDistribution({
    required this.id,
    this.type = '',
    this.description = '',
    this.quantite = 0,
    this.montant = 0,
    this.statut = 'ouverte',
    this.creeLe,
    this.decision = '',
    this.motif = '',
  });

  final String id;
  final String type;
  final String description;
  final double quantite;
  final double montant;
  final String statut;
  final DateTime? creeLe;
  final String decision;
  final String motif;

  bool get ouverte => statut == 'ouverte';

  factory AnomalieDistribution.depuisJson(Map<String, dynamic> json) {
    return AnomalieDistribution(
      id: parseString(json['id']),
      type: parseString(json['type']),
      description: parseString(json['description']),
      quantite: parseDouble(json['quantite']),
      montant: parseDouble(json['montant']),
      statut: parseString(json['statut'], fallback: 'ouverte'),
      creeLe: parseDateTimeOrNull(json['cree_le']),
      decision: parseString(json['decision']),
      motif: parseString(json['motif']),
    );
  }
}

// ---------------------------------------------------------------------------
// COLLABORATEURS
// ---------------------------------------------------------------------------

class CollaborateurDistribution {
  const CollaborateurDistribution({
    required this.id,
    this.nom = '',
    this.prenom = '',
    this.email = '',
    this.telephone = '',
    this.role = RoleDistribution.aucun,
    this.actif = true,
  });

  final String id;
  final String nom;
  final String prenom;
  final String email;
  final String telephone;
  final RoleDistribution role;
  final bool actif;

  String get nomComplet =>
      <String>[nom, prenom].where((String s) => s.trim().isNotEmpty).join(' ');

  factory CollaborateurDistribution.depuisJson(Map<String, dynamic> json) {
    return CollaborateurDistribution(
      id: parseString(json['id']),
      nom: parseString(json['nom']),
      prenom: parseString(json['prenom']),
      email: parseString(json['email']),
      telephone: parseString(json['telephone']),
      role: RoleDistribution.depuisCode(parseString(json['role_distribution'])),
      actif: json['actif'] != false,
    );
  }
}

/// Une ligne du stock personnel d'un commercial.
class ProduitCommercial {
  const ProduitCommercial({
    required this.produitId,
    this.nom = '',
    this.unite = '',
    this.quantite = 0,
    this.prixVente = 0,
  });

  final String produitId;
  final String nom;
  final String unite;
  final double quantite;
  final double prixVente;

  factory ProduitCommercial.depuisJson(Map<String, dynamic> json) {
    return ProduitCommercial(
      produitId: parseString(json['produit_id']),
      nom: parseString(json['nom']),
      unite: parseString(json['unite']),
      quantite: parseDouble(json['quantite']),
      prixVente: parseDouble(json['prix_vente']),
    );
  }
}

/// Une entrée du journal de traçabilité (`dist_journal_lister`).
///
/// [action] est le code technique écrit par les RPC (ex. `VENTE_ENREGISTREE`),
/// [libelle] sa traduction lisible, [details] le contexte JSON de l'opération.
class EntreeJournalDistribution {
  const EntreeJournalDistribution({
    required this.id,
    required this.action,
    this.entite = '',
    this.entiteId = '',
    this.auteur = '',
    this.role = '',
    this.details = const <String, dynamic>{},
    this.date,
  });

  final int id;
  final String action;
  final String entite;
  final String entiteId;
  final String auteur;
  final String role;
  final Map<String, dynamic> details;
  final DateTime? date;

  /// Traduction française du code d'action (repli : le code lui-même).
  String get libelle {
    const Map<String, String> traductions = <String, String>{
      'COLLABORATEUR_CREE': 'Collaborateur créé',
      'COLLABORATEUR_MODIFIE': 'Collaborateur modifié',
      'INTRANT_CREE': 'Intrant créé',
      'PRODUIT_CREE': 'Produit fini créé',
      'STOCK_AJUSTE': 'Stock ajusté',
      'RECEPTION_INTRANTS_CREE': 'Réception d\'intrants enregistrée',
      'RECEPTION_INTRANTS_CONFIRMEE': 'Réception d\'intrants confirmée',
      'RECEPTION_INTRANTS_REFUSEE': 'Réception d\'intrants refusée',
      'DEMANDE_INTRANTS_CREE': 'Demande d\'intrants créée',
      'DEMANDE_INTRANTS_VALIDEE': 'Demande d\'intrants validée',
      'DEMANDE_INTRANTS_REFUSEE': 'Demande d\'intrants refusée',
      'DEMANDE_INTRANTS_TRAITEE': 'Demande d\'intrants traitée',
      'DEMANDE_INTRANTS_RECEPTIONNEE': 'Demande d\'intrants réceptionnée',
      'PRODUCTION_ENREGISTREE': 'Production enregistrée',
      'PRODUCTION_RECEPTIONNEE': 'Production réceptionnée par le stock',
      'PRODUCTION_REINTEGREE': 'Production réintégrée au stock',
      'DEMANDE_COMMERCIALE_CREE': 'Demande commerciale créée',
      'DEMANDE_COMMERCIALE_CONFIRMEE': 'Demande commerciale confirmée',
      'DEMANDE_COMMERCIALE_AUTORISEE': 'Demande commerciale autorisée',
      'DEMANDE_COMMERCIALE_REFUSEE_PRODUCTION':
          'Demande commerciale refusée en production',
      'DEMANDE_COMMERCIALE_REFUSEE_STOCK':
          'Demande commerciale refusée au stock',
      'DEMANDE_COMMERCIALE_RECEPTIONNEE': 'Demande commerciale réceptionnée',
      'CLIENT_CREE': 'Client enregistré',
      'VENTE_ENREGISTREE': 'Vente enregistrée',
      'RETOUR_DECLARE': 'Retour déclaré',
      'RETOUR_RECEPTIONNE': 'Retour réceptionné',
      'REMISE_DECLAREE': 'Remise d\'argent déclarée',
      'REMISE_RECEPTIONNEE': 'Remise d\'argent réceptionnée',
      'REMISE_VALIDEE': 'Remise d\'argent validée',
      'CAISSE_APPORT': 'Apport de caisse',
      'DEPENSE_CREEE': 'Dépense enregistrée',
      'DEPENSE_VALIDEE': 'Dépense validée',
      'DEPENSE_REFUSEE': 'Dépense refusée',
      'ANOMALIE_RESOLUE': 'Anomalie résolue',
      'PARAMETRES_DEFINIS': 'Paramètres définis',
    };
    return traductions[action] ?? action;
  }

  /// Résumé d'une ligne de détail, pour l'affichage compact.
  String get resume {
    final List<String> morceaux = <String>[];
    details.forEach((String cle, dynamic valeur) {
      if (valeur == null) return;
      final String texte = valeur.toString();
      if (texte.trim().isEmpty) return;
      morceaux.add('$cle : $texte');
    });
    return morceaux.join(' · ');
  }

  factory EntreeJournalDistribution.depuisJson(Map<String, dynamic> json) {
    final dynamic brut = json['details'];
    return EntreeJournalDistribution(
      id: (json['id'] as num?)?.toInt() ?? 0,
      action: parseString(json['action']),
      entite: parseString(json['entite']),
      entiteId: parseString(json['entite_id']),
      auteur: parseString(json['auteur']),
      role: parseString(json['role']),
      details: brut is Map
          ? brut.map<String, dynamic>(
              (dynamic cle, dynamic valeur) =>
                  MapEntry<String, dynamic>(cle.toString(), valeur),
            )
          : const <String, dynamic>{},
      date: parseDateTimeOrNull(json['created_at']),
    );
  }
}

// ---------------------------------------------------------------------------
// TARIFS (grille multi-tarifs des bidons) — module 24 §9
// ---------------------------------------------------------------------------

/// Nature commerciale d'une opération sur un produit (bidon).
enum TypeOperationTarif {
  standard('standard', 'Prix normal'),
  bidonNeuf('bidon_neuf', 'Bidon neuf avec eau'),
  eauAvecEchange('eau_avec_echange', 'Eau + échange d\'un bidon vide'),
  remplissage('remplissage', 'Remplissage du bidon du client'),
  bidonVide('bidon_vide', 'Vente d\'un bidon vide'),
  remplacementEndommage(
      'remplacement_endommage', 'Remplacement d\'un bidon endommagé');

  const TypeOperationTarif(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypeOperationTarif depuisCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    for (final TypeOperationTarif t in values) {
      if (t.code == valeur) return t;
    }
    return TypeOperationTarif.standard;
  }
}

/// Un prix de la grille tarifaire d'un produit fini.
class TarifBidon {
  const TarifBidon({
    required this.id,
    required this.produitId,
    this.produit = '',
    required this.type,
    this.libelle = '',
    this.prix = 0,
    this.actif = true,
  });

  final String id;
  final String produitId;
  final String produit;
  final TypeOperationTarif type;
  final String libelle;
  final double prix;
  final bool actif;

  String get libelleAffiche => libelle.isNotEmpty ? libelle : type.libelle;

  factory TarifBidon.depuisJson(Map<String, dynamic> json) {
    return TarifBidon(
      id: parseString(json['id']),
      produitId: parseString(json['produit_id']),
      produit: parseString(json['produit']),
      type: TypeOperationTarif.depuisCode(parseString(json['type_operation'])),
      libelle: parseString(json['libelle']),
      prix: parseDouble(json['prix']),
      actif: json['actif'] != false,
    );
  }
}

// ---------------------------------------------------------------------------
// BONUS ET PRODUITS ENDOMMAGÉS — module 24 §10
// ---------------------------------------------------------------------------

/// Nature d'une déclaration de bonus / marchandise perdue.
enum NatureBonus {
  bonus('bonus', 'Bonus offert'),
  endommage('endommage', 'Produit endommagé'),
  casse('casse', 'Produit cassé'),
  perdu('perdu', 'Produit perdu');

  const NatureBonus(this.code, this.libelle);

  final String code;
  final String libelle;

  bool get estBonus => this == NatureBonus.bonus;

  static NatureBonus depuisCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    for (final NatureBonus n in values) {
      if (n.code == valeur) return n;
    }
    return NatureBonus.bonus;
  }
}

/// Une déclaration de bonus / dommage d'un commercial.
class BonusDommage {
  const BonusDommage({
    required this.id,
    this.commercialId = '',
    this.commercial = '',
    this.produitId = '',
    this.nomProduit = '',
    required this.nature,
    this.quantite = 0,
    this.prixUnitaire = 0,
    this.valeur = 0,
    this.motif = '',
    this.justificatif = '',
    this.statut = 'en_attente',
    this.motifRefus = '',
    this.date,
  });

  final String id;
  final String commercialId;
  final String commercial;
  final String produitId;
  final String nomProduit;
  final NatureBonus nature;
  final double quantite;
  final double prixUnitaire;
  final double valeur;
  final String motif;
  final String justificatif;
  final String statut;
  final String motifRefus;
  final DateTime? date;

  bool get enAttente => statut == 'en_attente';
  bool get valide => statut == 'valide';

  String get libelleStatut => switch (statut) {
        'valide' => 'Validé',
        'refuse' => 'Refusé',
        _ => 'Attente du gérant',
      };

  factory BonusDommage.depuisJson(Map<String, dynamic> json) {
    return BonusDommage(
      id: parseString(json['id']),
      commercialId: parseString(json['commercial_id']),
      commercial: parseString(json['commercial']),
      produitId: parseString(json['produit_id']),
      nomProduit: parseString(json['nom_produit']),
      nature: NatureBonus.depuisCode(parseString(json['nature'])),
      quantite: parseDouble(json['quantite']),
      prixUnitaire: parseDouble(json['prix_unitaire']),
      valeur: parseDouble(json['valeur']),
      motif: parseString(json['motif']),
      justificatif: parseString(json['justificatif']),
      statut: parseString(json['statut'], fallback: 'en_attente'),
      motifRefus: parseString(json['motif_refus']),
      date: parseDateTimeOrNull(json['created_at']),
    );
  }
}

/// Comparaison des bonus / dommages entre commerciaux.
class ResumeBonusCommercial {
  const ResumeBonusCommercial({
    required this.commercialId,
    this.commercial = '',
    this.bonusValeur = 0,
    this.dommageValeur = 0,
    this.totalValeur = 0,
    this.nbLignes = 0,
  });

  final String commercialId;
  final String commercial;
  final double bonusValeur;
  final double dommageValeur;
  final double totalValeur;
  final int nbLignes;

  factory ResumeBonusCommercial.depuisJson(Map<String, dynamic> json) {
    return ResumeBonusCommercial(
      commercialId: parseString(json['commercial_id']),
      commercial: parseString(json['commercial']),
      bonusValeur: parseDouble(json['bonus_valeur']),
      dommageValeur: parseDouble(json['dommage_valeur']),
      totalValeur: parseDouble(json['total_valeur']),
      nbLignes: parseInt(json['nb_lignes']),
    );
  }
}

// ---------------------------------------------------------------------------
// COÛT DE REVIENT ET MARGES — module 24 §11
// ---------------------------------------------------------------------------

/// Coût de revient observé d'un produit fini.
///
/// [coutComplet] vaut `false` dès qu'un intrant n'a pas de prix : la marge est
/// alors `null` — le serveur ne fabrique jamais un chiffre.
class CoutRevientProduit {
  const CoutRevientProduit({
    required this.produitId,
    this.produit = '',
    this.format = '',
    this.unite = '',
    this.quantite = 0,
    this.coutTotal = 0,
    this.coutUnitaire,
    this.prixVente = 0,
    this.margeUnitaire,
    this.margePct,
    this.coutComplet = false,
    this.derniereProduction,
  });

  final String produitId;
  final String produit;
  final String format;
  final String unite;
  final double quantite;
  final double coutTotal;
  final double? coutUnitaire;
  final double prixVente;
  final double? margeUnitaire;
  final double? margePct;
  final bool coutComplet;
  final DateTime? derniereProduction;

  factory CoutRevientProduit.depuisJson(Map<String, dynamic> json) {
    double? nulOuDouble(dynamic v) =>
        v == null ? null : parseDouble(v);
    return CoutRevientProduit(
      produitId: parseString(json['produit_id']),
      produit: parseString(json['produit']),
      format: parseString(json['format']),
      unite: parseString(json['unite']),
      quantite: parseDouble(json['quantite']),
      coutTotal: parseDouble(json['cout_total']),
      coutUnitaire: nulOuDouble(json['cout_unitaire']),
      prixVente: parseDouble(json['prix_vente']),
      margeUnitaire: nulOuDouble(json['marge_unitaire']),
      margePct: nulOuDouble(json['marge_pct']),
      coutComplet: json['cout_complet'] == true,
      derniereProduction: parseDateTimeOrNull(json['derniere_production']),
    );
  }
}

/// Marge d'un commercial sur la période.
class MargeCommercial {
  const MargeCommercial({
    required this.commercialId,
    this.commercial = '',
    this.ca = 0,
    this.nbVentes = 0,
  });

  final String commercialId;
  final String commercial;
  final double ca;
  final int nbVentes;

  factory MargeCommercial.depuisJson(Map<String, dynamic> json) {
    return MargeCommercial(
      commercialId: parseString(json['commercial_id']),
      commercial: parseString(json['commercial'] ?? ''),
      ca: parseDouble(json['ca']),
      nbVentes: parseInt(json['nb_ventes']),
    );
  }
}

/// Analyse de rentabilité d'une période.
class RentabiliteDistribution {
  const RentabiliteDistribution({
    this.ca = 0,
    this.coutMarchandises = 0,
    this.margeBrute = 0,
    this.margePct,
    this.bonusDommages = 0,
    this.coutComplet = false,
    this.parCommercial = const <MargeCommercial>[],
    this.produits = const <CoutRevientProduit>[],
    this.debut,
    this.fin,
  });

  final double ca;
  final double coutMarchandises;
  final double margeBrute;
  final double? margePct;
  final double bonusDommages;
  final bool coutComplet;
  final List<MargeCommercial> parCommercial;
  final List<CoutRevientProduit> produits;
  final DateTime? debut;
  final DateTime? fin;

  factory RentabiliteDistribution.depuisJson(Map<String, dynamic> json) {
    final List<Map<String, dynamic>> commerciaux =
        parseMapList(json['par_commercial']);
    final List<Map<String, dynamic>> prods = parseMapList(json['produits']);
    return RentabiliteDistribution(
      ca: parseDouble(json['ca']),
      coutMarchandises: parseDouble(json['cout_marchandises']),
      margeBrute: parseDouble(json['marge_brute']),
      margePct:
          json['marge_pct'] == null ? null : parseDouble(json['marge_pct']),
      bonusDommages: parseDouble(json['bonus_dommages']),
      coutComplet: json['cout_complet'] == true,
      parCommercial:
          commerciaux.map(MargeCommercial.depuisJson).toList(growable: false),
      produits:
          prods.map(CoutRevientProduit.depuisJson).toList(growable: false),
      debut: parseDateTimeOrNull(json['debut']),
      fin: parseDateTimeOrNull(json['fin']),
    );
  }
}
