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
    this.ecart = 0,
    this.chiffreAffaires = 0,
    this.consignesOuvertes = 0,
    this.consignesTotal = 0,
    this.bonusTotal = 0,
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

  /// Quantité ni vendue ni rendue : la responsabilité de l'agent.
  final double ecart;
  final double chiffreAffaires;
  final int consignesOuvertes;
  final int consignesTotal;
  final double bonusTotal;

  /// Part du stock attribué réellement vendue (0 → 1).
  double get tauxVente =>
      quantiteAttribuee <= 0 ? 0 : (quantiteVendue / quantiteAttribuee).clamp(0, 1);

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
      ecart: _nombre(json['ecart']),
      chiffreAffaires: _nombre(json['chiffre_affaires']),
      consignesOuvertes: _entier(json['consignes_ouvertes']),
      consignesTotal: _entier(json['consignes_total']),
      bonusTotal: _nombre(json['bonus_total']),
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
      ecart: _nombre(json['ecart_total']),
      chiffreAffaires: _nombre(json['chiffre_affaires']),
      consignesOuvertes: modele?.consignesOuvertes ?? 0,
      consignesTotal: modele?.consignesTotal ?? 0,
      bonusTotal: modele?.bonusTotal ?? 0,
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
    this.restante = 0,
    this.prixVente = 0,
  });

  final int produitId;
  final String nom;
  final String unite;
  final double attribuee;
  final double vendue;
  final double retournee;

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
      statut: _texte(json['statut']).isEmpty ? 'chez_client' : _texte(json['statut']),
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
      nature: _texte(json['nature']).isEmpty ? 'remise' : _texte(json['nature']),
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

  bool get demarree => statut == TourneeStatut.enCours;

  int get produitsRestants => lignes.where((LigneTournee l) => !l.epuisee).length;

  double get quantiteRestante => lignes.fold<double>(
      0, (double total, LigneTournee l) => total + l.restante);

  double get chiffreAffairesPotentiel => lignes.fold<double>(
      0, (double total, LigneTournee l) => total + l.vendue * l.prixVente);

  static MaTournee? depuisJson(Map<String, dynamic> json) {
    if (json['ok'] != true) return null;
    final Map<String, dynamic> t = (json['tournee'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
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
    this.consignesOuvertes = 0,
    this.bonus = 0,
  });

  final int tournees;
  final double chiffreAffaires;
  final double quantiteVendue;
  final double ecart;
  final double consignesOuvertes;
  final double bonus;

  factory TotauxDistribution.depuisJson(Map<String, dynamic>? json) {
    final Map<String, dynamic> j = json ?? <String, dynamic>{};
    return TotauxDistribution(
      tournees: _entier(j['tournees']),
      chiffreAffaires: _nombre(j['chiffre_affaires']),
      quantiteVendue: _nombre(j['quantite_vendue']),
      ecart: _nombre(j['ecart']),
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

/// Résultat de la clôture d'une tournée.
class ResultatCloture {
  const ResultatCloture({
    required this.tournee,
    this.lignes = const <LigneTournee>[],
  });

  final TourneeDistribution tournee;
  final List<LigneTournee> lignes;
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
