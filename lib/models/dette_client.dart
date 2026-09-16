// lib/models/dette_client.dart
//
// MODULE 10 — DETTES CLIENTS.
//
// `public.dettes` + `public.paiements_dette` (source de vérité des règlements :
// le trigger serveur recalcule `montant_paye` et le statut à chaque paiement).
// Ces objets transportent les réponses des RPC du module ; aucun accès réseau.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Statut d'une dette — mêmes valeurs que la base.
enum StatutDette {
  nonPaye('non_paye', 'Non payée'),
  partiel('partiel', 'Partielle'),
  paye('paye', 'Payée'),
  inconnu('', 'Inconnu');

  const StatutDette(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutDette depuisCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    for (final StatutDette statut in StatutDette.values) {
      if (statut.code == valeur) return statut;
    }
    return StatutDette.inconnu;
  }
}

/// Une dette client (avec le restant dû et l'ancienneté calculés par le
/// serveur).
class DetteClient {
  const DetteClient({
    required this.id,
    required this.clientId,
    required this.client,
    this.telephone,
    this.email,
    this.venteUuid,
    this.montantTotal = 0,
    this.montantPaye = 0,
    this.restant = 0,
    this.statut = StatutDette.nonPaye,
    this.dateCreation,
    this.dateEcheance,
    this.jours = 0,
    this.dernierPaiement,
    this.nbPaiements = 0,
  });

  final int id;
  final int clientId;
  final String client;
  final String? telephone;
  final String? email;

  /// Vente du Module 8 à l'origine de la dette (si vente à crédit).
  final String? venteUuid;

  final double montantTotal;
  final double montantPaye;
  final double restant;
  final StatutDette statut;
  final DateTime? dateCreation;
  final DateTime? dateEcheance;

  /// Ancienneté en jours (calculée par le serveur).
  final int jours;
  final DateTime? dernierPaiement;
  final int nbPaiements;

  bool get estSoldee => restant <= 0.005 || statut == StatutDette.paye;

  /// La dette dépasse-t-elle son échéance ? ([reference] permet de tester
  /// sans dépendre de l'horloge réelle.)
  bool enRetard({DateTime? reference}) {
    final DateTime? echeance = dateEcheance;
    if (echeance == null || estSoldee) return false;
    final DateTime jour = reference ?? DateTime.now();
    final DateTime finEcheance =
        DateTime(echeance.year, echeance.month, echeance.day, 23, 59, 59);
    return jour.isAfter(finEcheance);
  }

  /// Copie après un paiement (mise à jour locale, sans recharger la liste).
  DetteClient apresPaiement({
    required double montantPaye,
    required double restant,
    required StatutDette statut,
    DateTime? dernierPaiement,
    int? nbPaiements,
  }) {
    return DetteClient(
      id: id,
      clientId: clientId,
      client: client,
      telephone: telephone,
      email: email,
      venteUuid: venteUuid,
      montantTotal: montantTotal,
      montantPaye: montantPaye,
      restant: restant,
      statut: statut,
      dateCreation: dateCreation,
      dateEcheance: dateEcheance,
      jours: jours,
      dernierPaiement: dernierPaiement ?? this.dernierPaiement,
      nbPaiements: nbPaiements ?? this.nbPaiements,
    );
  }

  factory DetteClient.depuisRpc(Map<String, dynamic> map) {
    return DetteClient(
      id: parseInt(map['dette_id']),
      clientId: parseInt(map['client_id']),
      client: parseString(map['client'], fallback: 'Client'),
      telephone: parseStringOrNull(map['telephone']),
      email: parseStringOrNull(map['email']),
      venteUuid: parseStringOrNull(map['vente_uuid']),
      montantTotal: parseDouble(map['montant_total']),
      montantPaye: parseDouble(map['montant_paye']),
      restant: parseDouble(map['restant']),
      statut: StatutDette.depuisCode(parseStringOrNull(map['statut'])),
      dateCreation: parseDateTimeOrNull(map['date_creation']),
      dateEcheance: parseDateTimeOrNull(map['date_echeance']),
      jours: parseInt(map['jours']),
      dernierPaiement: parseDateTimeOrNull(map['dernier_paiement']),
      nbPaiements: parseInt(map['nb_paiements']),
    );
  }
}

/// Synthèse des dettes d'une boutique (en-tête de l'écran).
class ResumeDettes {
  const ResumeDettes({
    this.nb = 0,
    this.nbNonPaye = 0,
    this.nbPartiel = 0,
    this.nbPaye = 0,
    this.totalDettes = 0,
    this.totalRestant = 0,
  });

  final int nb;
  final int nbNonPaye;
  final int nbPartiel;
  final int nbPaye;
  final double totalDettes;
  final double totalRestant;

  factory ResumeDettes.depuisRpc(Map<String, dynamic> map) {
    return ResumeDettes(
      nb: parseInt(map['nb']),
      nbNonPaye: parseInt(map['nb_non_paye']),
      nbPartiel: parseInt(map['nb_partiel']),
      nbPaye: parseInt(map['nb_paye']),
      totalDettes: parseDouble(map['total_dettes']),
      totalRestant: parseDouble(map['total_restant']),
    );
  }
}

/// Résultat de `rpc_dettes_liste`.
class ResultatListeDettes {
  const ResultatListeDettes({
    this.statut,
    this.recherche,
    this.lignes = const <DetteClient>[],
    this.resume = const ResumeDettes(),
  });

  final String? statut;
  final String? recherche;
  final List<DetteClient> lignes;
  final ResumeDettes resume;

  factory ResultatListeDettes.depuisRpc(Map<String, dynamic> map) {
    return ResultatListeDettes(
      statut: parseStringOrNull(map['statut']),
      recherche: parseStringOrNull(map['recherche']),
      lignes: parseMapList(map['lignes'])
          .map(DetteClient.depuisRpc)
          .toList(growable: false),
      resume: ResumeDettes.depuisRpc(
          parseMap(map['resume']) ?? <String, dynamic>{}),
    );
  }
}

/// Résultat de `rpc_dette_paiement`.
class ResultatPaiementDette {
  const ResultatPaiementDette({
    required this.detteId,
    required this.client,
    required this.montant,
    required this.modePaiement,
    this.datePaiement,
    this.montantPaye = 0,
    this.restant = 0,
    this.statut = StatutDette.nonPaye,
  });

  final int detteId;
  final String client;
  final double montant;
  final String modePaiement;
  final DateTime? datePaiement;
  final double montantPaye;
  final double restant;
  final StatutDette statut;

  factory ResultatPaiementDette.depuisRpc(Map<String, dynamic> map) {
    return ResultatPaiementDette(
      detteId: parseInt(map['dette_id']),
      client: parseString(map['client'], fallback: 'Client'),
      montant: parseDouble(map['montant']),
      modePaiement: parseString(map['mode_paiement'], fallback: 'especes'),
      datePaiement: parseDateTimeOrNull(map['date_paiement']),
      montantPaye: parseDouble(map['montant_paye']),
      restant: parseDouble(map['restant']),
      statut: StatutDette.depuisCode(parseStringOrNull(map['statut'])),
    );
  }
}

/// Résultat de `rpc_dette_relancer` — le message est pré-rédigé par le serveur.
class RelanceDette {
  const RelanceDette({
    required this.detteId,
    required this.client,
    required this.telephone,
    required this.canal,
    this.restant = 0,
    this.jours = 0,
    this.message = '',
  });

  final int detteId;
  final String client;
  final String telephone;
  final String canal;
  final double restant;
  final int jours;
  final String message;

  factory RelanceDette.depuisRpc(Map<String, dynamic> map) {
    return RelanceDette(
      detteId: parseInt(map['dette_id']),
      client: parseString(map['client'], fallback: 'Client'),
      telephone: parseString(map['telephone']),
      canal: parseString(map['canal'], fallback: 'whatsapp'),
      restant: parseDouble(map['restant']),
      jours: parseInt(map['jours']),
      message: parseString(map['message']),
    );
  }
}

/// Client proposé dans le formulaire de création de dette.
class ClientDetteOption {
  const ClientDetteOption({
    required this.id,
    required this.nom,
    this.telephone,
  });

  final int id;
  final String nom;
  final String? telephone;

  factory ClientDetteOption.depuisRpc(Map<String, dynamic> map) {
    return ClientDetteOption(
      id: parseInt(map['id']),
      nom: parseString(map['nom'], fallback: 'Client'),
      telephone: parseStringOrNull(map['telephone']),
    );
  }
}
