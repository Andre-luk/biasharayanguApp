// lib/models/distribution_terrain.dart
//
// 🚚 MODULE 23 — DISTRIBUTION TERRAIN.
//
// Objets purs (aucun accès réseau, aucun import Flutter) : ils peuvent être
// testés sans binding et restent la seule façon dont les écrans lisent les
// réponses des RPC du module.
//
// Vocabulaire :
//   • TOURNÉE   : la dotation d'un agent pour une date et une zone ;
//   • LIGNE     : un produit attribué, avec vendu / rendu / restant ;
//   • CONSIGNE  : un récipient de l'entreprise resté chez un client ;
//   • BONUS     : une remise ou un cadeau accordé à un client.

/// État d'une tournée.
enum TourneeStatut {
  preparee('preparee', 'Préparée'),
  enCours('en_cours', 'En cours'),
  cloturee('cloturee', 'Clôturée'),
  annulee('annulee', 'Annulée');

  const TourneeStatut(this.code, this.libelle);

  final String code;
  final String libelle;

  bool get estActive =>
      this == TourneeStatut.preparee || this == TourneeStatut.enCours;

  static TourneeStatut fromCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    for (final TourneeStatut s in values) {
      if (s.code == valeur) return s;
    }
    return TourneeStatut.preparee;
  }
}

/// Une tournée telle que renvoyée par `rpc_tournee_rapport`.
class TourneeDistribution {
  const TourneeDistribution({
    required this.id,
    required this.reference,
    required this.dateTournee,
    required this.statut,
    this.agentId,
    this.agentNom = '',
    this.zone = '',
    this.nbArticles = 0,
    this.quantiteAttribuee = 0,
    this.quantiteVendue = 0,
    this.quantiteRetournee = 0,
    this.quantiteCasse = 0,
    this.quantiteBonus = 0,
    this.ecart = 0,
    this.chiffreAffaires = 0,
    this.coutAchat = 0,
    this.consignesOuvertes = 0,
    this.consignesTotal = 0,
    this.bonusTotal = 0,
    this.objectifMontant,
    this.commissionTaux,
    this.commissionMontant = 0,
  });

  final String id;
  final String reference;
  final DateTime? dateTournee;
  final String? agentId;
  final String agentNom;
  final String zone;
  final TourneeStatut statut;

  final int nbArticles;
  final double quantiteAttribuee;
  final double quantiteVendue;
  final double quantiteRetournee;

  /// Cassée ou perdue : tracée séparément, ne produit aucun chiffre d'affaires.
  final double quantiteCasse;

  /// Offerte en bonus : sort de la dotation sans créer de chiffre d'affaires.
  final double quantiteBonus;

  /// Quantité ni vendue, ni rendue, ni cassée, ni offerte : la responsabilité
  /// de l'agent. Toujours calculée par le serveur, jamais saisie.
  final double ecart;
  final double chiffreAffaires;

  /// Coût d'achat des unités réellement vendues (prix figé à la dotation).
  final double coutAchat;
  final int consignesOuvertes;
  final int consignesTotal;
  final double bonusTotal;

  /// Objectif de chiffre d'affaires fixé par le patron (null = pas d'objectif).
  final double? objectifMontant;

  /// Taux de commission en pourcentage (null = pas de commission).
  final double? commissionTaux;

  /// Commission calculée à la clôture (0 tant que la tournée tourne).
  final double commissionMontant;

  /// Part du stock attribué réellement vendue (0 → 1).
  double get tauxVente => quantiteAttribuee <= 0
      ? 0
      : (quantiteVendue / quantiteAttribuee).clamp(0, 1);

  /// Avancement vers l'objectif (0 → 1, plafonné pour l'affichage).
  double get tauxObjectif {
    final double? cible = objectifMontant;
    if (cible == null || cible <= 0) return 0;
    return (chiffreAffaires / cible).clamp(0, 1);
  }

  bool get objectifAtteint {
    final double? cible = objectifMontant;
    return cible != null && cible > 0 && chiffreAffaires >= cible;
  }

  /// Marge estimée : ce qui reste après le coût d'achat des unités vendues.
  double get marge => chiffreAffaires - coutAchat;

  /// Ce que l'agent a en moins par rapport à ce qui lui a été confié.
  double get manquant =>
      quantiteAttribuee -
      quantiteVendue -
      quantiteRetournee -
      quantiteCasse -
      quantiteBonus;

  factory TourneeDistribution.depuisJson(Map<String, dynamic> json) {
    return TourneeDistribution(
      id: _texte(json['id']),
      reference: _texte(json['reference']),
      dateTournee: _date(json['date_tournee']),
      agentId: _texteOuNull(json['agent_id']),
      agentNom: _texte(json['agent_nom']),
      zone: _texte(json['zone']),
      statut: TourneeStatut.fromCode(_texteOuNull(json['statut'])),
      nbArticles: _entier(json['nb_articles']),
      quantiteAttribuee: _nombre(json['quantite_attribuee']),
      quantiteVendue: _nombre(json['quantite_vendue']),
      quantiteRetournee: _nombre(json['quantite_retournee']),
      quantiteCasse: _nombre(json['quantite_casse']),
      quantiteBonus: _nombre(json['quantite_bonus']),
      ecart: _nombre(json['ecart']),
      chiffreAffaires: _nombre(json['chiffre_affaires']),
      coutAchat: _nombre(json['cout_achat']),
      consignesOuvertes: _entier(json['consignes_ouvertes']),
      consignesTotal: _entier(json['consignes_total']),
      bonusTotal: _nombre(json['bonus_total']),
      objectifMontant: _nombreOuNull(json['objectif_montant']),
      commissionTaux: _nombreOuNull(json['commission_taux']),
      commissionMontant: _nombre(json['commission_montant']),
    );
  }

  /// Ligne telle que renvoyée par `rpc_tournee_cloturer`.
  factory TourneeDistribution.depuisCloture(
    Map<String, dynamic> json, {
    TourneeDistribution? modele,
  }) {
    return TourneeDistribution(
      id: _texte(json['id']),
      reference: _texte(json['reference']),
      dateTournee: modele?.dateTournee,
      agentId: modele?.agentId,
      agentNom: modele?.agentNom ?? '',
      zone: modele?.zone ?? '',
      statut: TourneeStatut.fromCode(_texteOuNull(json['statut'])),
      nbArticles: modele?.nbArticles ?? 0,
      quantiteAttribuee: modele?.quantiteAttribuee ?? 0,
      quantiteVendue: modele?.quantiteVendue ?? 0,
      quantiteRetournee: modele?.quantiteRetournee ?? 0,
      quantiteCasse: modele?.quantiteCasse ?? 0,
      quantiteBonus: modele?.quantiteBonus ?? 0,
      ecart: _nombre(json['ecart_total']),
      chiffreAffaires: _nombre(json['chiffre_affaires']),
      coutAchat: modele?.coutAchat ?? 0,
      consignesOuvertes: modele?.consignesOuvertes ?? 0,
      consignesTotal: modele?.consignesTotal ?? 0,
      bonusTotal: modele?.bonusTotal ?? 0,
      objectifMontant: modele?.objectifMontant,
      commissionTaux:
          _nombreOuNull(json['commission_taux']) ?? modele?.commissionTaux,
      commissionMontant: _nombre(json['commission_montant']),
    );
  }
}

/// Une ligne de dotation (produit attribué à l'agent).
class LigneTournee {
  const LigneTournee({
    required this.produitId,
    required this.nom,
    this.unite = '',
    this.attribuee = 0,
    this.vendue = 0,
    this.retournee = 0,
    this.bonus = 0,
    this.casse = 0,
    this.restante = 0,
    this.prixVente = 0,
  });

  final int produitId;
  final String nom;
  final String unite;
  final double attribuee;
  final double vendue;
  final double retournee;

  /// Offerte en bonus (ne produit pas de chiffre d'affaires).
  final double bonus;

  /// Cassée ou perdue.
  final double casse;

  /// Ce qu'il reste à vendre (ou à rendre).
  final double restante;
  final double prixVente;

  bool get epuisee => restante <= 0.0001;

  factory LigneTournee.depuisJson(Map<String, dynamic> json) {
    return LigneTournee(
      produitId: _entier(json['produit_id']),
      nom: _texte(json['nom']),
      unite: _texte(json['unite']),
      attribuee: _nombre(json['attribuee']),
      vendue: _nombre(json['vendue']),
      retournee: _nombre(json['retournee']),
      bonus: _nombre(json['bonus']),
      casse: _nombre(json['casse']),
      restante: _nombre(json['restante']),
      prixVente: _nombre(json['prix_vente']),
    );
  }

  /// Ligne du rapport de clôture.
  factory LigneTournee.depuisCloture(Map<String, dynamic> json) {
    return LigneTournee(
      produitId: _entier(json['produit_id']),
      nom: _texte(json['nom']),
      unite: _texte(json['unite']),
      attribuee: _nombre(json['attribuee']),
      vendue: _nombre(json['vendue']),
      retournee: _nombre(json['retournee']),
      bonus: _nombre(json['bonus']),
      casse: _nombre(json['casse']),
      restante: _nombre(json['ecart']),
    );
  }
}

/// Consigne : récipient de l'entreprise resté chez un client.
class ConsigneRecipient {
  const ConsigneRecipient({
    required this.id,
    this.clientId,
    this.clientNom = '',
    this.zone = '',
    this.libelle = 'Récipient',
    this.quantite = 0,
    this.recuperee = 0,
    this.statut = 'chez_client',
    this.date,
  });

  final String id;
  final int? clientId;
  final String clientNom;
  final String zone;
  final String libelle;
  final int quantite;
  final int recuperee;
  final String statut;
  final DateTime? date;

  int get restante => (quantite - recuperee).clamp(0, quantite);

  bool get ouverte =>
      restante > 0 && statut != 'perdue' && statut != 'recuperee';

  String get libelleStatut => switch (statut) {
        'recuperee' => 'Récupérée',
        'partielle' => 'Partielle',
        'perdue' => 'Perdue',
        _ => 'Chez le client',
      };

  factory ConsigneRecipient.depuisJson(Map<String, dynamic> json) {
    return ConsigneRecipient(
      id: _texte(json['id']),
      clientId: _entierOuNull(json['client_id']),
      clientNom: _texte(json['client_nom']),
      zone: _texte(json['zone']),
      libelle: _texte(json['libelle']),
      quantite: _entier(json['quantite']),
      recuperee: _entier(json['recuperee']),
      statut: _texte(json['statut']).isEmpty
          ? 'chez_client'
          : _texte(json['statut']),
      date: _date(json['date']),
    );
  }
}

/// Bonus accordé à un client (remise, cadeau, fidélité).
class BonusClient {
  const BonusClient({
    required this.id,
    this.clientNom = '',
    this.nature = 'remise',
    this.montant = 0,
    this.description = '',
    this.date,
  });

  final String id;
  final String clientNom;
  final String nature;
  final double montant;
  final String description;
  final DateTime? date;

  String get libelleNature => switch (nature) {
        'cadeau' => 'Cadeau',
        'fidelite' => 'Fidélité',
        'autre' => 'Autre',
        _ => 'Remise',
      };

  factory BonusClient.depuisJson(Map<String, dynamic> json) {
    return BonusClient(
      id: _texte(json['id']),
      clientNom: _texte(json['client_nom']),
      nature:
          _texte(json['nature']).isEmpty ? 'remise' : _texte(json['nature']),
      montant: _nombre(json['montant']),
      description: _texte(json['description']),
      date: _date(json['date']),
    );
  }
}

/// Tournée vue par l'AGENT connecté (`rpc_ma_tournee`).
class MaTournee {
  const MaTournee({
    required this.id,
    required this.reference,
    required this.statut,
    this.zone = '',
    this.note = '',
    this.dateTournee,
    this.lignes = const <LigneTournee>[],
    this.consignes = const <ConsigneRecipient>[],
    this.bonus = const <BonusClient>[],
    this.objectifMontant,
    this.commissionTaux,
    this.commissionEstimee = 0,
    this.chiffreAffaires = 0,
  });

  final String id;
  final String reference;
  final TourneeStatut statut;
  final String zone;
  final String note;
  final DateTime? dateTournee;
  final List<LigneTournee> lignes;
  final List<ConsigneRecipient> consignes;
  final List<BonusClient> bonus;

  /// Objectif de chiffre d'affaires fixé par le patron (null = aucun).
  final double? objectifMontant;

  /// Taux de commission en pourcentage (null = aucune).
  final double? commissionTaux;

  /// Ce que l'agent gagne si la tournée s'arrête maintenant. Estimé par le
  /// serveur, figé à la clôture.
  final double commissionEstimee;

  /// Chiffre d'affaires réellement encaissé sur cette tournée.
  final double chiffreAffaires;

  bool get demarree => statut == TourneeStatut.enCours;

  /// Avancement vers l'objectif (0 → 1).
  double get tauxObjectif {
    final double? cible = objectifMontant;
    if (cible == null || cible <= 0) return 0;
    return (chiffreAffaires / cible).clamp(0, 1);
  }

  bool get objectifAtteint {
    final double? cible = objectifMontant;
    return cible != null && cible > 0 && chiffreAffaires >= cible;
  }

  /// Montant qui reste à faire pour atteindre l'objectif (0 si atteint).
  double get restePourObjectif {
    final double? cible = objectifMontant;
    if (cible == null || cible <= 0) return 0;
    final double reste = cible - chiffreAffaires;
    return reste > 0 ? reste : 0;
  }

  int get produitsRestants =>
      lignes.where((LigneTournee l) => !l.epuisee).length;

  double get quantiteRestante => lignes.fold<double>(
      0, (double total, LigneTournee l) => total + l.restante);

  double get chiffreAffairesPotentiel => lignes.fold<double>(
      0, (double total, LigneTournee l) => total + l.vendue * l.prixVente);

  static MaTournee? depuisJson(Map<String, dynamic> json) {
    if (json['ok'] != true) return null;
    final Map<String, dynamic> t =
        (json['tournee'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    if (t.isEmpty) return null;

    return MaTournee(
      id: _texte(t['id']),
      reference: _texte(t['reference']),
      statut: TourneeStatut.fromCode(_texteOuNull(t['statut'])),
      zone: _texte(t['zone']),
      note: _texte(t['note']),
      dateTournee: _date(t['date_tournee']),
      lignes: _liste(json['lignes']).map(LigneTournee.depuisJson).toList(),
      consignes:
          _liste(json['consignes']).map(ConsigneRecipient.depuisJson).toList(),
      bonus: _liste(json['bonus']).map(BonusClient.depuisJson).toList(),
      objectifMontant: _nombreOuNull(t['objectif_montant']),
      commissionTaux: _nombreOuNull(t['commission_taux']),
      commissionEstimee: _nombre(t['commission_estimee']),
      chiffreAffaires: _nombre(t['chiffre_affaires']),
    );
  }
}

/// Totaux du rapport de distribution.
class TotauxDistribution {
  const TotauxDistribution({
    this.tournees = 0,
    this.chiffreAffaires = 0,
    this.quantiteVendue = 0,
    this.ecart = 0,
    this.casse = 0,
    this.quantiteBonus = 0,
    this.commission = 0,
    this.coutAchat = 0,
    this.consignesOuvertes = 0,
    this.bonus = 0,
  });

  final int tournees;
  final double chiffreAffaires;
  final double quantiteVendue;
  final double ecart;

  /// Quantité cassée ou perdue sur la période.
  final double casse;

  /// Quantité offerte en bonus sur la période.
  final double quantiteBonus;

  /// Commissions dues aux agents sur la période.
  final double commission;

  /// Coût d'achat des unités vendues (prix figés à la dotation).
  final double coutAchat;
  final double consignesOuvertes;
  final double bonus;

  /// Marge estimée : chiffre d'affaires − coût d'achat des unités vendues.
  double get marge => chiffreAffaires - coutAchat;

  factory TotauxDistribution.depuisJson(Map<String, dynamic>? json) {
    final Map<String, dynamic> j = json ?? <String, dynamic>{};
    return TotauxDistribution(
      tournees: _entier(j['tournees']),
      chiffreAffaires: _nombre(j['chiffre_affaires']),
      quantiteVendue: _nombre(j['quantite_vendue']),
      ecart: _nombre(j['ecart']),
      casse: _nombre(j['casse']),
      quantiteBonus: _nombre(j['quantite_bonus']),
      commission: _nombre(j['commission']),
      coutAchat: _nombre(j['cout_achat']),
      consignesOuvertes: _nombre(j['consignes_ouvertes']),
      bonus: _nombre(j['bonus']),
    );
  }
}

/// Rapport consolidé (`rpc_tournee_rapport`).
class RapportDistribution {
  const RapportDistribution({
    this.tournees = const <TourneeDistribution>[],
    this.totaux = const TotauxDistribution(),
  });

  final List<TourneeDistribution> tournees;
  final TotauxDistribution totaux;

  static RapportDistribution depuisJson(Map<String, dynamic> json) {
    return RapportDistribution(
      tournees: _liste(json['lignes'])
          .map(TourneeDistribution.depuisJson)
          .toList(growable: false),
      totaux: TotauxDistribution.depuisJson(
        (json['totaux'] as Map?)?.cast<String, dynamic>(),
      ),
    );
  }
}

/// Compteurs de la carte d'accueil.
class CompteursDistribution {
  const CompteursDistribution({
    this.tourneesActives = 0,
    this.agentsActifs = 0,
    this.consignesOuvertes = 0,
    this.bonusMois = 0,
  });

  final int tourneesActives;
  final int agentsActifs;
  final int consignesOuvertes;
  final double bonusMois;

  static const CompteursDistribution vide = CompteursDistribution();

  factory CompteursDistribution.depuisJson(Map<String, dynamic> json) {
    return CompteursDistribution(
      tourneesActives: _entier(json['tournees_actives']),
      agentsActifs: _entier(json['agents_actifs']),
      consignesOuvertes: _entier(json['consignes_ouvertes']),
      bonusMois: _nombre(json['bonus_mois']),
    );
  }
}

/// Agent proposé dans le sélecteur de tournée.
class AgentDistribution {
  const AgentDistribution({
    required this.id,
    required this.nom,
    this.role = '',
  });

  final String id;
  final String nom;
  final String role;

  String get libelle => nom.isEmpty ? 'Agent sans nom' : nom;
}

// ---------------------------------------------------------------------------
// RADAR DE TOURNÉE (phase 6)
// ---------------------------------------------------------------------------

/// Niveau d'anomalie d'un agent, du plus serein au plus préoccupant.
enum NiveauAnomalie {
  normal('normal', 'Normal'),
  surveiller('surveiller', 'À surveiller'),
  alerte('alerte', 'Alerte');

  const NiveauAnomalie(this.code, this.libelle);

  final String code;
  final String libelle;

  static NiveauAnomalie fromCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    for (final NiveauAnomalie n in values) {
      if (n.code == valeur) return n;
    }
    // Un code inconnu ne doit jamais transformer un agent en suspect.
    return NiveauAnomalie.normal;
  }
}

/// Un écart constaté sur UN produit : jamais noyé dans un total.
class EcartProduit {
  const EcartProduit({
    required this.produitId,
    this.nom = '',
    this.unite = '',
    this.attribuee = 0,
    this.vendue = 0,
    this.retournee = 0,
    this.bonus = 0,
    this.casse = 0,
    this.ecart = 0,
    this.valeur = 0,
  });

  final int produitId;
  final String nom;
  final String unite;
  final double attribuee;
  final double vendue;
  final double retournee;
  final double bonus;
  final double casse;

  /// Ce qui manque : confié − vendu − rendu − offert − cassé.
  final double ecart;

  /// Ce que cet écart représente en argent (au prix de vente).
  final double valeur;

  bool get manquant => ecart > 0.0001;
  bool get excedent => ecart < -0.0001;

  factory EcartProduit.depuisJson(Map<String, dynamic> json) {
    return EcartProduit(
      produitId: _entier(json['produit_id']),
      nom: _texte(json['nom']),
      unite: _texte(json['unite']),
      attribuee: _nombre(json['attribuee']),
      vendue: _nombre(json['vendue']),
      retournee: _nombre(json['retournee']),
      bonus: _nombre(json['bonus']),
      casse: _nombre(json['casse']),
      ecart: _nombre(json['ecart']),
      valeur: _nombre(json['valeur']),
    );
  }
}

/// Quantité conseillée pour la prochaine tournée, calée sur l'historique réel.
class RecommandationChargement {
  const RecommandationChargement({
    required this.produitId,
    this.nom = '',
    this.unite = '',
    this.medianeVendue = 0,
    this.tauxRetour = 0,
    this.nbTournees = 0,
    this.quantiteSuggeree = 0,
    this.stockDisponible = 0,
    this.quantiteRetenue = 0,
  });

  final int produitId;
  final String nom;
  final String unite;

  /// Médiane des quantités vendues sur les dernières tournées de la zone.
  final double medianeVendue;

  /// Part de la dotation revenue en retour (0 → 1).
  final double tauxRetour;
  final int nbTournees;

  /// Médiane corrigée du taux de retour.
  final double quantiteSuggeree;
  final double stockDisponible;

  /// Ce qu'on peut réellement charger : jamais plus que le stock.
  final double quantiteRetenue;

  /// Taux de retour en pourcentage, pour l'affichage.
  double get tauxRetourPourcent => (tauxRetour * 100).clamp(0, 100);

  factory RecommandationChargement.depuisJson(Map<String, dynamic> json) {
    return RecommandationChargement(
      produitId: _entier(json['produit_id']),
      nom: _texte(json['nom']),
      unite: _texte(json['unite']),
      medianeVendue: _nombre(json['mediane_vendue']),
      tauxRetour: _nombre(json['taux_retour']),
      nbTournees: _entier(json['nb_tournees']),
      quantiteSuggeree: _nombre(json['quantite_suggeree']),
      stockDisponible: _nombre(json['stock_disponible']),
      quantiteRetenue: _nombre(json['quantite_retenue']),
    );
  }
}

/// Client qui garde des récipients depuis trop longtemps.
class ConsigneARisque {
  const ConsigneARisque({
    required this.id,
    this.clientId,
    this.clientNom = '',
    this.libelle = '',
    this.restant = 0,
    this.jours = 0,
    this.valeur = 0,
  });

  final String id;
  final int? clientId;
  final String clientNom;
  final String libelle;
  final double restant;
  final int jours;
  final double valeur;

  factory ConsigneARisque.depuisJson(Map<String, dynamic> json) {
    return ConsigneARisque(
      id: _texte(json['id']),
      clientId: _entierOuNull(json['client_id']),
      clientNom: _texte(json['client_nom']),
      libelle: _texte(json['libelle']),
      restant: _nombre(json['restant']),
      jours: _entier(json['jours']),
      valeur: _nombre(json['valeur']),
    );
  }
}

/// Radar d'une tournée : ce qui manque, quoi charger, qui relancer.
class RadarTournee {
  const RadarTournee({
    this.tourneeId,
    this.reference = '',
    this.zone = '',
    this.produits = 0,
    this.quantiteConfiee = 0,
    this.quantiteVendue = 0,
    this.quantiteRetournee = 0,
    this.quantiteBonus = 0,
    this.quantiteCasse = 0,
    this.ecart = 0,
    this.valeurEcart = 0,
    this.ecarts = const <EcartProduit>[],
    this.recommandations = const <RecommandationChargement>[],
    this.historiqueSuffisant = false,
    this.consignesRisque = const <ConsigneARisque>[],
  });

  final String? tourneeId;
  final String reference;
  final String zone;
  final int produits;
  final double quantiteConfiee;
  final double quantiteVendue;
  final double quantiteRetournee;
  final double quantiteBonus;
  final double quantiteCasse;
  final double ecart;
  final double valeurEcart;

  /// Uniquement les produits dont l'écart n'est PAS nul.
  final List<EcartProduit> ecarts;

  final List<RecommandationChargement> recommandations;

  /// `false` quand l'historique est trop mince : on ne recommande rien.
  final bool historiqueSuffisant;
  final List<ConsigneARisque> consignesRisque;

  bool get aDesEcarts => ecarts.isNotEmpty;

  /// Valeur des récipients restés chez les clients, quand elle est connue.
  double get valeurConsignesRisque => consignesRisque.fold<double>(
      0, (double total, ConsigneARisque c) => total + c.valeur);

  static const RadarTournee vide = RadarTournee();

  static RadarTournee depuisJson(Map<String, dynamic> json) {
    final Map<String, dynamic> resume =
        (json['resume'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    final Map<String, dynamic> tournee =
        (json['tournee'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};

    return RadarTournee(
      tourneeId: _texteOuNull(tournee['id']),
      reference: _texte(tournee['reference']),
      zone: _texte(json['zone']),
      produits: _entier(resume['produits']),
      quantiteConfiee: _nombre(resume['quantite_confiee']),
      quantiteVendue: _nombre(resume['quantite_vendue']),
      quantiteRetournee: _nombre(resume['quantite_retournee']),
      quantiteBonus: _nombre(resume['quantite_bonus']),
      quantiteCasse: _nombre(resume['quantite_casse']),
      ecart: _nombre(resume['ecart']),
      valeurEcart: _nombre(resume['valeur_ecart']),
      ecarts: _liste(json['ecarts'])
          .map(EcartProduit.depuisJson)
          .toList(growable: false),
      recommandations: _liste(json['recommandations'])
          .map(RecommandationChargement.depuisJson)
          .toList(growable: false),
      historiqueSuffisant: json['historique_suffisant'] == true,
      consignesRisque: _liste(json['consignes_risque'])
          .map(ConsigneARisque.depuisJson)
          .toList(growable: false),
    );
  }
}

/// Un motif de score : le radar explique toujours POURQUOI.
class MotifRadar {
  const MotifRadar({
    this.code = '',
    this.libelle = '',
    this.detail = '',
    this.valeur = 0,
  });

  final String code;
  final String libelle;
  final String detail;
  final double valeur;

  factory MotifRadar.depuisJson(Map<String, dynamic> json) {
    return MotifRadar(
      code: _texte(json['code']),
      libelle: _texte(json['libelle']),
      detail: _texte(json['detail']),
      valeur: _nombre(json['valeur']),
    );
  }
}

/// Score d'anomalie d'un agent, toujours accompagné de ses motifs.
class RadarAgent {
  const RadarAgent({
    this.agentId,
    this.agentNom = '',
    this.jours = 30,
    this.score = 0,
    this.niveau = NiveauAnomalie.normal,
    this.tournees = 0,
    this.quantiteConfiee = 0,
    this.quantiteVendue = 0,
    this.quantiteRetournee = 0,
    this.quantiteBonus = 0,
    this.quantiteCasse = 0,
    this.ecart = 0,
    this.tauxEcart = 0,
    this.chiffreAffaires = 0,
    this.creditOuvert = 0,
    this.tauxCredit = 0,
    this.motifs = const <MotifRadar>[],
  });

  final String? agentId;
  final String agentNom;
  final int jours;

  /// 0 → 100. Ce n'est pas une note morale : c'est un écart mesuré.
  final int score;
  final NiveauAnomalie niveau;
  final int tournees;

  final double quantiteConfiee;
  final double quantiteVendue;
  final double quantiteRetournee;
  final double quantiteBonus;
  final double quantiteCasse;
  final double ecart;
  final double tauxEcart;
  final double chiffreAffaires;
  final double creditOuvert;
  final double tauxCredit;
  final List<MotifRadar> motifs;

  static const RadarAgent vide = RadarAgent();

  /// Part du score expliquée par la marchandise non justifiée.
  bool get aQuelqueChoseASignaler =>
      niveau != NiveauAnomalie.normal || ecart > 0.0001 || creditOuvert > 0;

  factory RadarAgent.depuisJson(Map<String, dynamic> json) {
    return RadarAgent(
      agentId: _texteOuNull(json['agent_id']),
      agentNom: _texte(json['agent_nom']),
      jours: _entier(json['jours']),
      score: _entier(json['score']),
      niveau: NiveauAnomalie.fromCode(_texteOuNull(json['niveau'])),
      tournees: _entier(json['tournees']),
      quantiteConfiee: _nombre(json['quantite_confiee']),
      quantiteVendue: _nombre(json['quantite_vendue']),
      quantiteRetournee: _nombre(json['quantite_retournee']),
      quantiteBonus: _nombre(json['quantite_bonus']),
      quantiteCasse: _nombre(json['quantite_casse']),
      ecart: _nombre(json['ecart']),
      tauxEcart: _nombre(json['taux_ecart']),
      chiffreAffaires: _nombre(json['chiffre_affaires']),
      creditOuvert: _nombre(json['credit_ouvert']),
      tauxCredit: _nombre(json['taux_credit']),
      motifs: _liste(json['motifs'])
          .map(MotifRadar.depuisJson)
          .toList(growable: false),
    );
  }
}

/// Résultat de la clôture d'une tournée.
class ResultatCloture {
  const ResultatCloture({
    required this.tournee,
    this.lignes = const <LigneTournee>[],
    this.ecarts = const <LigneTournee>[],
  });

  final TourneeDistribution tournee;
  final List<LigneTournee> lignes;

  /// Uniquement les lignes dont l'écart n'est pas nul : nommées, jamais noyées.
  final List<LigneTournee> ecarts;

  /// Commission calculée par le serveur à la clôture.
  double get commission => tournee.commissionMontant;
}

// ---------------------------------------------------------------------------
// Conversions tolérantes (le JSON des RPC peut arriver en nombre, texte…)
// ---------------------------------------------------------------------------

String _texte(dynamic valeur) => valeur == null ? '' : valeur.toString();

String? _texteOuNull(dynamic valeur) {
  final String t = _texte(valeur).trim();
  return t.isEmpty ? null : t;
}

double _nombre(dynamic valeur) {
  if (valeur is num) return valeur.toDouble();
  return double.tryParse(_texte(valeur)) ?? 0;
}

/// Nombre facultatif : `null` reste `null` (pas d'objectif ≠ objectif à 0).
double? _nombreOuNull(dynamic valeur) {
  if (valeur == null) return null;
  if (valeur is num) return valeur.toDouble();
  final String t = _texte(valeur).trim();
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

int _entier(dynamic valeur) => _nombre(valeur).round();

int? _entierOuNull(dynamic valeur) {
  if (valeur == null) return null;
  final double n = _nombre(valeur);
  return n == 0 && _texte(valeur).isEmpty ? null : n.round();
}

DateTime? _date(dynamic valeur) {
  final String t = _texte(valeur).trim();
  if (t.isEmpty) return null;
  return DateTime.tryParse(t);
}

List<Map<String, dynamic>> _liste(dynamic valeur) {
  if (valeur is! List) return const <Map<String, dynamic>>[];
  return valeur
      .whereType<Map>()
      .map((Map m) => m.cast<String, dynamic>())
      .toList(growable: false);
}
