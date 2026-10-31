// lib/models/fiche_entreprise.dart
//
// CORRECTIF 73 — LA FICHE UNIQUE D'UNE ENTREPRISE.
//
// Tout ce qui concerne l'abonnement, l'installation, le suivi et l'avance est
// rassemblé ici, en un seul objet alimenté par UN SEUL appel serveur :
// `rpc_entreprise_fiche(id)`.
//
// Aucun calcul financier n'est refait côté application : les montants
// viennent de la base (c'est elle qui applique la règle des deux prix —
// installation au premier cycle, mensuel ensuite).

import 'dart:convert';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Réponse de `rpc_admin_entreprise_creer`.
class ResultatCreationEntreprise {
  final String entrepriseId;
  final String nom;
  final String type;
  final String proprietaireId;
  final String proprietaireEmail;
  final double prixInstallation;
  final double? prixMensuel;
  final int essaiJours;

  /// `true` quand l'adresse e-mail avait déjà un compte : le mot de passe a
  /// été réaligné et le compte rattaché à la nouvelle entreprise.
  final bool compteReutilise;

  const ResultatCreationEntreprise({
    required this.entrepriseId,
    required this.nom,
    required this.type,
    required this.proprietaireId,
    required this.proprietaireEmail,
    required this.prixInstallation,
    this.prixMensuel,
    this.essaiJours = 7,
    this.compteReutilise = false,
  });

  factory ResultatCreationEntreprise.depuisJson(Map<String, dynamic> map) {
    return ResultatCreationEntreprise(
      entrepriseId: parseString(map['entreprise_id']),
      nom: parseString(map['nom']),
      type: parseString(map['type'], fallback: 'boutique'),
      proprietaireId: parseString(map['proprietaire_id']),
      proprietaireEmail: parseString(map['proprietaire_email']),
      prixInstallation: parseDouble(map['prix_installation']),
      prixMensuel: parseDoubleOrNull(map['prix_abonnement_mensuel']),
      essaiJours: parseInt(map['essai_jours'], fallback: 7),
      compteReutilise: map['compte_reutilise'] == true,
    );
  }
}

/// Personne citée dans la fiche : le propriétaire ou celui qui a créé le compte.
class PersonneFiche {
  final String id;
  final String nom;
  final String? prenom;
  final String? email;
  final String? telephone;
  final String? role;

  const PersonneFiche({
    required this.id,
    required this.nom,
    this.prenom,
    this.email,
    this.telephone,
    this.role,
  });

  /// « Prénom Nom », ou le nom seul.
  String get nomComplet {
    final String p = (prenom ?? '').trim();
    final String n = nom.trim();
    if (p.isEmpty) return n;
    if (n.isEmpty) return p;
    return '$p $n';
  }

  static PersonneFiche? depuisJson(dynamic data) {
    final Map<String, dynamic>? map = parseMap(data);
    if (map == null || parseString(map['id']).isEmpty) return null;
    return PersonneFiche(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      prenom: parseStringOrNull(map['prenom']),
      email: parseStringOrNull(map['email']),
      telephone: parseStringOrNull(map['telephone']),
      role: parseStringOrNull(map['role']),
    );
  }
}

/// Grille tarifaire (le « pack ») de l'entreprise.
class GrilleFiche {
  final String id;
  final String nom;
  final double fraisOuverture;
  final double montantAbonnement;
  final int dureeEssaiJours;
  final int dureeAbonnementJours;
  final double prixParCollaborateur;
  final int maxEspaces;

  const GrilleFiche({
    required this.id,
    required this.nom,
    this.fraisOuverture = 0,
    this.montantAbonnement = 0,
    this.dureeEssaiJours = 0,
    this.dureeAbonnementJours = 0,
    this.prixParCollaborateur = 0,
    this.maxEspaces = 1,
  });

  static GrilleFiche? depuisJson(dynamic data) {
    final Map<String, dynamic>? map = parseMap(data);
    if (map == null || parseString(map['id']).isEmpty) return null;
    return GrilleFiche(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      fraisOuverture: parseDouble(map['frais_ouverture']),
      montantAbonnement: parseDouble(map['montant_abonnement']),
      dureeEssaiJours: parseInt(map['duree_essai_jours']),
      dureeAbonnementJours: parseInt(map['duree_abonnement_jours']),
      prixParCollaborateur: parseDouble(map['prix_par_collaborateur']),
      maxEspaces: parseInt(map['max_espaces'], fallback: 1),
    );
  }
}

/// Les montants de la fiche : abonnement, installation, avance déjà versée.
class PrixFiche {
  /// Prix du PREMIER cycle — il comprend le premier mois d'abonnement.
  final double? installation;

  /// Prix des cycles SUIVANTS (renouvellements).
  final double? mensuel;

  /// Dû du cycle en cours (réécrit par le moteur d'abonnement).
  final double totalDu;
  final double dejaPaye;
  final double solde;

  /// Somme réellement encaissée d'après l'historique des paiements.
  final double paiementsCumules;

  /// Ce qui sera réclamé au prochain encaissement.
  final double? prochainMontant;

  const PrixFiche({
    this.installation,
    this.mensuel,
    this.totalDu = 0,
    this.dejaPaye = 0,
    this.solde = 0,
    this.paiementsCumules = 0,
    this.prochainMontant,
  });

  static PrixFiche depuisJson(dynamic data) {
    final map = parseMap(data) ?? const <String, dynamic>{};
    return PrixFiche(
      installation: parseDoubleOrNull(map['installation']),
      mensuel: parseDoubleOrNull(map['mensuel']),
      totalDu: parseDouble(map['total_du']),
      dejaPaye: parseDouble(map['deja_paye']),
      solde: parseDouble(map['solde']),
      paiementsCumules: parseDouble(map['paiements_cumules']),
      prochainMontant: parseDoubleOrNull(map['prochain_montant']),
    );
  }

  /// Part déjà réglée du dû, entre 0 et 1.
  double get progression {
    if (totalDu <= 0) return 0;
    final double p = dejaPaye / totalDu;
    if (p < 0) return 0;
    if (p > 1) return 1;
    return p;
  }

  /// Vrai quand tout le cycle en cours est réglé.
  bool get estSolde => totalDu > 0 && solde <= 0;
}

/// Suivi du dossier : étape, statut, dates, qui a validé quoi.
class SuiviFiche {
  final String? statut;
  final String? activationEtape;
  final int? joursRestants;
  final DateTime? dateActivation;
  final DateTime? dateExpiration;
  final String? verifiePar;
  final DateTime? verifieLe;
  final String? valideParFinance;
  final DateTime? valideLeFinance;

  const SuiviFiche({
    this.statut,
    this.activationEtape,
    this.joursRestants,
    this.dateActivation,
    this.dateExpiration,
    this.verifiePar,
    this.verifieLe,
    this.valideParFinance,
    this.valideLeFinance,
  });

  static SuiviFiche depuisJson(dynamic data) {
    final map = parseMap(data) ?? const <String, dynamic>{};
    return SuiviFiche(
      statut: parseStringOrNull(map['statut']),
      activationEtape: parseStringOrNull(map['activation_etape']),
      joursRestants: map['jours_restants'] == null
          ? null
          : parseInt(map['jours_restants']),
      dateActivation: parseDateTimeOrNull(map['date_activation']),
      dateExpiration: parseDateTimeOrNull(map['date_expiration']),
      verifiePar: parseStringOrNull(map['verifie_par']),
      verifieLe: parseDateTimeOrNull(map['verifie_le']),
      valideParFinance: parseStringOrNull(map['valide_par_finance']),
      valideLeFinance: parseDateTimeOrNull(map['valide_le_finance']),
    );
  }

  /// Libellé lisible de l'étape d'activation.
  String get libelleEtape {
    switch (activationEtape) {
      case 'en_attente_verification':
        return 'En attente de vérification';
      case 'verifie':
        return 'Vérifié — en attente de la finance';
      case 'actif':
        return 'Actif';
      case 'restreint':
        return 'Restreint (paiement incomplet)';
      case 'rejete':
        return 'Rejeté';
      default:
        return '—';
    }
  }

  /// Libellé lisible du statut d'abonnement.
  String get libelleStatut {
    switch (statut) {
      case 'ESSAI_7J':
        return 'Essai';
      case 'ACTIF':
        return 'Actif';
      case 'EXPIRE':
        return 'Expiré';
      case 'SUSPENDU':
        return 'Suspendu';
      case 'EN_ATTENTE_COMPLEMENT':
        return 'Attente de complément';
      default:
        return statut ?? '—';
    }
  }

  /// Vrai quand le compte n'est pas encore opérationnel.
  bool get enAttente =>
      activationEtape == 'en_attente_verification' ||
      activationEtape == 'verifie' ||
      activationEtape == 'rejete';

  /// Phrase courte sur l'échéance.
  String get libelleEcheance {
    final int? jours = joursRestants;
    if (jours == null) return 'Aucune échéance enregistrée';
    if (jours < 0) return 'Échu depuis ${-jours} jour(s)';
    if (jours == 0) return 'Expire aujourd\'hui';
    return '$jours jour(s) restant(s)';
  }
}

/// Ce que l'utilisateur connecté a le droit de faire depuis la fiche.
class DroitsFiche {
  final bool peutGererPrix;
  final bool peutVerifier;
  final bool peutValider;
  final bool peutCreer;

  const DroitsFiche({
    this.peutGererPrix = false,
    this.peutVerifier = false,
    this.peutValider = false,
    this.peutCreer = false,
  });

  static DroitsFiche depuisJson(dynamic data) {
    final map = parseMap(data) ?? const <String, dynamic>{};
    return DroitsFiche(
      peutGererPrix: map['peut_gerer_prix'] == true,
      peutVerifier: map['peut_verifier'] == true,
      peutValider: map['peut_valider'] == true,
      peutCreer: map['peut_creer'] == true,
    );
  }
}

/// Une étape du dossier (création, vérification, validation, restriction…).
class EtapeFiche {
  final String etape;
  final double? montant;
  final String? modePaiement;
  final String? reference;
  final String? note;
  final String? acteurRole;
  final DateTime? createdAt;

  const EtapeFiche({
    required this.etape,
    this.montant,
    this.modePaiement,
    this.reference,
    this.note,
    this.acteurRole,
    this.createdAt,
  });

  static EtapeFiche depuisJson(Map<String, dynamic> map) {
    return EtapeFiche(
      etape: parseString(map['etape']),
      montant: parseDoubleOrNull(map['montant']),
      modePaiement: parseStringOrNull(map['mode_paiement']),
      reference: parseStringOrNull(map['reference']),
      note: parseStringOrNull(map['note']),
      acteurRole: parseStringOrNull(map['acteur_role']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }

  /// Libellé lisible de l'étape.
  String get libelle {
    switch (etape) {
      case 'soumission':
        return 'Dossier soumis';
      case 'verification':
        return 'Vérifié';
      case 'rejet_verification':
        return 'Rejeté (vérification)';
      case 'paiement_finance':
        return 'Paiement validé (finance)';
      case 'rejet_finance':
        return 'Paiement rejeté (finance)';
      case 'restriction':
        return 'Compte restreint';
      default:
        return etape;
    }
  }
}

/// Un encaissement d'abonnement (= une avance, un solde ou un renouvellement).
class PaiementFiche {
  final String id;
  final double montant;
  final String? typePaiement;
  final String? modePaiement;
  final String? note;
  final double? totalApres;
  final double? soldeApres;
  final int prolongationJours;
  final DateTime? createdAt;

  const PaiementFiche({
    required this.id,
    this.montant = 0,
    this.typePaiement,
    this.modePaiement,
    this.note,
    this.totalApres,
    this.soldeApres,
    this.prolongationJours = 0,
    this.createdAt,
  });

  static PaiementFiche depuisJson(Map<String, dynamic> map) {
    return PaiementFiche(
      id: parseString(map['id']),
      montant: parseDouble(map['montant']),
      typePaiement: parseStringOrNull(map['type_paiement']),
      modePaiement: parseStringOrNull(map['mode_paiement']),
      note: parseStringOrNull(map['note']),
      totalApres: parseDoubleOrNull(map['total_apres']),
      soldeApres: parseDoubleOrNull(map['solde_apres']),
      prolongationJours: parseInt(map['prolongation_jours']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }

  /// Libellé du type : Avance, Solde, Renouvellement.
  String get libelleType {
    switch (typePaiement) {
      case 'AVANCE':
        return 'Avance';
      case 'SOLDE':
        return 'Solde';
      case 'RENOUVELLEMENT':
        return 'Renouvellement';
      default:
        return 'Paiement';
    }
  }
}

/// LA FICHE UNIQUE : abonnement, installation, suivi et avance.
class FicheEntreprise {
  final Entreprise entreprise;
  final PersonneFiche? proprietaire;
  final PersonneFiche? createur;
  final GrilleFiche? grille;
  final PrixFiche prix;
  final SuiviFiche suivi;
  final DroitsFiche droits;
  final List<EtapeFiche> historique;
  final List<PaiementFiche> paiements;

  /// 🪙 Quotas de l'assistant IA inclus dans l'abonnement (null = valeur du
  /// pack). Crédités automatiquement à chaque cycle payé.
  final int? quotasIaMensuels;

  const FicheEntreprise({
    required this.entreprise,
    this.proprietaire,
    this.createur,
    this.grille,
    this.prix = const PrixFiche(),
    this.suivi = const SuiviFiche(),
    this.droits = const DroitsFiche(),
    this.historique = const <EtapeFiche>[],
    this.paiements = const <PaiementFiche>[],
    this.quotasIaMensuels,
  });

  /// Construit la fiche depuis la réponse de `rpc_entreprise_fiche`.
  ///
  /// Renvoie `null` si la réponse n'a pas la forme attendue : l'appelant
  /// décide quoi afficher (jamais de plantage).
  static FicheEntreprise? depuisJson(dynamic reponse) {
    Map<String, dynamic>? map = parseMap(reponse);
    if (map == null && reponse is String) {
      try {
        map = parseMap(jsonDecode(reponse));
      } catch (_) {
        map = null;
      }
    }
    if (map == null) return null;

    final Map<String, dynamic>? ent = parseMap(map['entreprise']);
    if (ent == null) return null;

    return FicheEntreprise(
      entreprise: Entreprise.fromMap(ent),
      proprietaire: PersonneFiche.depuisJson(map['proprietaire']),
      createur: PersonneFiche.depuisJson(map['cree_par']),
      grille: GrilleFiche.depuisJson(map['grille']),
      prix: PrixFiche.depuisJson(map['prix']),
      suivi: SuiviFiche.depuisJson(map['suivi']),
      droits: DroitsFiche.depuisJson(map['droits']),
      historique:
          parseMapList(map['historique']).map(EtapeFiche.depuisJson).toList(),
      paiements:
          parseMapList(map['paiements']).map(PaiementFiche.depuisJson).toList(),
      quotasIaMensuels: ent['quotas_ia_mensuels'] == null
          ? null
          : parseInt(ent['quotas_ia_mensuels']),
    );
  }

  /// Vrai quand le compte est créé mais pas encore opérationnel.
  bool get enAttenteActivation => suivi.enAttente;
}
