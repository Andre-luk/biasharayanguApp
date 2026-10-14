// lib/models/boutique_agent.dart
//
// CORRECTIF 76 — LES BOUTIQUES DE L'AGENT, AVEC LEUR ABONNEMENT.
//
// Un agent terrain apporte un client, crée son compte, puis suit son
// abonnement : c'est tout l'objet de ce modèle, alimenté par
// `rpc_agent_mes_boutiques()`.
//
// Aucun montant n'est calculé ici : la base renvoie le dû, l'encaissé et le
// solde. L'application ne fait que les présenter — et elle ne peut RIEN
// modifier sur cette liste (lecture seule côté serveur).

import 'dart:convert';

import 'package:biashara_yangu/models/fiche_entreprise.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Une boutique créée ou suivie par l'agent connecté.
class BoutiqueAgent {
  final String entrepriseId;
  final String nom;

  /// Type de l'espace de travail (« boutique », « pharmacie »…).
  final String? type;

  final String? statut;
  final String? activationEtape;
  final DateTime? creeLe;
  final DateTime? dateActivation;
  final DateTime? dateExpiration;

  /// Jours restants **calculés par la base** (négatif = échu).
  final int? joursRestants;

  final double? prixInstallation;
  final double? prixMensuel;
  final double? totalDu;
  final double? dejaPaye;
  final double? solde;

  final String? proprietaireNom;
  final String? proprietaireEmail;
  final String? proprietaireTelephone;

  /// Nombre de dossiers (demandes de code) encore ouverts sur ce compte.
  final int dossiersEnAttente;

  const BoutiqueAgent({
    required this.entrepriseId,
    required this.nom,
    this.type,
    this.statut,
    this.activationEtape,
    this.creeLe,
    this.dateActivation,
    this.dateExpiration,
    this.joursRestants,
    this.prixInstallation,
    this.prixMensuel,
    this.totalDu,
    this.dejaPaye,
    this.solde,
    this.proprietaireNom,
    this.proprietaireEmail,
    this.proprietaireTelephone,
    this.dossiersEnAttente = 0,
  });

  factory BoutiqueAgent.depuisJson(Map<String, dynamic> map) {
    return BoutiqueAgent(
      entrepriseId: parseString(map['entreprise_id']),
      nom: parseString(map['nom']),
      type: parseStringOrNull(map['type']),
      statut: parseStringOrNull(map['statut']),
      activationEtape: parseStringOrNull(map['activation_etape']),
      creeLe: parseDateTimeOrNull(map['cree_le']),
      dateActivation: parseDateTimeOrNull(map['date_activation']),
      dateExpiration: parseDateTimeOrNull(map['date_expiration']),
      joursRestants: map['jours_restants'] == null
          ? null
          : parseInt(map['jours_restants']),
      prixInstallation: parseDoubleOrNull(map['prix_installation']),
      prixMensuel: parseDoubleOrNull(map['prix_abonnement_mensuel']),
      totalDu: parseDoubleOrNull(map['total_du']),
      dejaPaye: parseDoubleOrNull(map['deja_paye']),
      solde: parseDoubleOrNull(map['solde']),
      proprietaireNom: parseStringOrNull(map['proprietaire_nom']),
      proprietaireEmail: parseStringOrNull(map['proprietaire_email']),
      proprietaireTelephone: parseStringOrNull(map['proprietaire_telephone']),
      dossiersEnAttente: parseInt(map['dossiers_en_attente'] ?? 0),
    );
  }

  /// Remplit [SuiviFiche] : mêmes libellés partout dans l'application, une
  /// seule règle d'affichage (aucune seconde implémentation à maintenir).
  SuiviFiche get suivi => SuiviFiche(
        statut: statut,
        activationEtape: activationEtape,
        joursRestants: joursRestants,
        dateActivation: dateActivation,
        dateExpiration: dateExpiration,
      );

  /// Le compte est-il opérationnel ?
  bool get actif => activationEtape == 'actif' && !echu;

  /// L'échéance est-elle dépassée ?
  bool get echu => joursRestants != null && joursRestants! < 0;

  /// L'échéance approche-t-elle (7 jours ou moins) ?
  bool get echeanceProcha =>
      joursRestants != null && joursRestants! >= 0 && joursRestants! <= 7;

  /// Reste-t-il de l'argent à encaisser sur ce compte ?
  bool get soldeRestant => (solde ?? 0) > 0;

  /// Un dossier est-il en attente côté Finance ?
  bool get enAttenteFinance => dossiersEnAttente > 0;
}

/// Réponse complète de `rpc_agent_mes_boutiques()`.
class MesBoutiquesAgent {
  final String? role;
  final List<BoutiqueAgent> boutiques;

  const MesBoutiquesAgent({this.role, this.boutiques = const <BoutiqueAgent>[]});

  static MesBoutiquesAgent? depuisJson(dynamic reponse) {
    // PostgREST renvoie normalement un objet JSON, mais certaines versions
    // (ou un proxy) le renvoient encodé en texte : on accepte les deux formes,
    // comme la fiche d'entreprise — jamais de plantage.
    Map<String, dynamic>? map = parseMap(reponse);
    if (map == null && reponse is String) {
      try {
        map = parseMap(jsonDecode(reponse));
      } catch (_) {
        map = null;
      }
    }
    if (map == null || map['ok'] != true) return null;

    final List<dynamic> brutes = map['boutiques'] is List
        ? map['boutiques'] as List<dynamic>
        : const <dynamic>[];

    return MesBoutiquesAgent(
      role: parseStringOrNull(map['role']),
      boutiques: <BoutiqueAgent>[
        for (final dynamic ligne in brutes)
          if (parseMap(ligne) != null)
            BoutiqueAgent.depuisJson(parseMap(ligne)!),
      ],
    );
  }

  int get nbActives =>
      boutiques.where((BoutiqueAgent b) => b.actif).length;

  int get nbEchues => boutiques.where((BoutiqueAgent b) => b.echu).length;

  int get nbEnAttente =>
      boutiques.where((BoutiqueAgent b) => b.suivi.enAttente).length;

  /// Somme des soldes encore dus (ce que la Finance doit encaisser).
  double get soldeTotal => boutiques.fold<double>(
      0, (double total, BoutiqueAgent b) => total + (b.solde ?? 0));

  /// Le portefeuille est-il vide ?
  bool get vide => boutiques.isEmpty;
}
