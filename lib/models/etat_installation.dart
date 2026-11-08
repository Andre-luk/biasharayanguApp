// lib/models/etat_installation.dart
//
// PHASE 2 — L'INSTALLATION NE SE PAIE QU'UNE FOIS.
//
// Une entreprise paie une installation (qui comprend son premier mois), puis
// un abonnement mensuel. La question « faut-il encore facturer l'installation
// ? » ne doit JAMAIS être répondue par une case cochée à la main : elle se lit
// dans l'historique réel des versements (`rpc_abonnement_installation_etat`).
//
// Ce modèle ne calcule rien : il transporte la réponse du serveur et
// n'invente aucune valeur quand un champ manque (`null` → 0 / faux).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Ce que le PROCHAIN encaissement doit demander.
enum ProchainCycle {
  installation('installation', 'Installation'),
  abonnement('abonnement', 'Abonnement mensuel');

  const ProchainCycle(this.code, this.libelle);

  final String code;
  final String libelle;

  static ProchainCycle fromCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    return valeur == 'abonnement'
        ? ProchainCycle.abonnement
        : ProchainCycle.installation;
  }
}

/// État de l'installation et du prochain cycle d'une entreprise.
class EtatInstallation {
  const EtatInstallation({
    this.entrepriseId = '',
    this.devise = 'CDF',
    this.prixInstallation = 0,
    this.prixMensuel = 0,
    this.montantTotalDu = 0,
    this.montantDejaPaye = 0,
    this.soldeRestant = 0,
    this.statut = '',
    this.dateActivation,
    this.dateExpiration,
    this.installationDejaReglee = false,
    this.installationRegleeMontant = 0,
    this.cyclesSoldes = 0,
    this.prochainCycle = ProchainCycle.installation,
    this.prochainMontant = 0,
  });

  final String entrepriseId;
  final String devise;

  /// Prix de l'installation (premier cycle, premier mois inclus).
  final double prixInstallation;

  /// Prix d'un mois d'abonnement, appliqué aux renouvellements.
  final double prixMensuel;

  final double montantTotalDu;
  final double montantDejaPaye;
  final double soldeRestant;
  final String statut;
  final DateTime? dateActivation;
  final DateTime? dateExpiration;

  /// VRAI si l'installation a déjà été réglée un jour (activation, versement
  /// de nature installation, ou cycle soldé). Lu dans les faits, pas déclaré.
  final bool installationDejaReglee;

  /// Ce qui a été encaissé au titre de l'installation / de l'ouverture.
  final double installationRegleeMontant;

  /// Nombre de cycles entièrement réglés.
  final int cyclesSoldes;

  final ProchainCycle prochainCycle;
  final double prochainMontant;

  /// Vrai si le dossier doit d'abord être complété avant toute activation.
  bool get complementAttendu => soldeRestant > 0.0001;

  static const EtatInstallation inconnu = EtatInstallation();

  /// Message prêt à afficher : ce que le prochain encaissement demande.
  String get libelleProchainEncaissement =>
      '${prochainCycle.libelle} — ${_montant(prochainMontant)} $devise';

  /// Phrase d'explication sur l'installation, sans ambiguïté.
  String get libelleInstallation => installationDejaReglee
      ? 'Installation déjà réglée : elle ne sera pas refacturée.'
      : 'Installation à régler une seule fois (le premier mois est inclus).';

  static String _montant(double valeur) {
    final String brut = valeur.toStringAsFixed(2);
    return brut.endsWith('.00') ? brut.substring(0, brut.length - 3) : brut;
  }

  factory EtatInstallation.depuisJson(Map<String, dynamic> json) {
    return EtatInstallation(
      entrepriseId: parseString(json['entreprise_id']),
      devise: parseString(json['devise'], fallback: 'CDF'),
      prixInstallation: parseDouble(json['prix_installation']),
      prixMensuel: parseDouble(json['prix_mensuel']),
      montantTotalDu: parseDouble(json['montant_total_du']),
      montantDejaPaye: parseDouble(json['montant_deja_paye']),
      soldeRestant: parseDouble(json['solde_restant']),
      statut: parseString(json['statut']),
      dateActivation: parseDateTimeOrNull(json['date_activation']),
      dateExpiration: parseDateTimeOrNull(json['date_expiration']),
      installationDejaReglee: json['installation_deja_reglee'] == true,
      installationRegleeMontant:
          parseDouble(json['installation_reglee_montant']),
      cyclesSoldes: parseInt(json['cycles_soldes']),
      prochainCycle:
          ProchainCycle.fromCode(parseStringOrNull(json['prochain_cycle'])),
      prochainMontant: parseDouble(json['prochain_montant']),
    );
  }
}

/// Résultat de `rpc_abonnement_preparer_renouvellement`.
///
/// Ce que le client doit comprendre en une ligne : « un nouveau mois est
/// ouvert, voici ce qu'il reste à payer ». Le serveur refuse d'ouvrir un
/// cycle si l'abonnement court encore (pas de double facturation).
class PreparationRenouvellement {
  const PreparationRenouvellement({
    this.cycleOuvert = false,
    this.motif = '',
    this.soldeRestant = 0,
    this.prixMensuel = 0,
    this.devise = 'CDF',
    this.typeCycle = 'abonnement',
  });

  /// `true` si un nouveau cycle vient d'être ouvert par cet appel.
  final bool cycleOuvert;

  /// `CYCLE_OUVERT`, `DEJA_OUVERT` ou `CYCLE_EN_COURS`.
  final String motif;

  final double soldeRestant;
  final double prixMensuel;
  final String devise;

  /// `installation` (premier cycle payant) ou `abonnement` (mensuel).
  final String typeCycle;

  bool get aPayer => soldeRestant > 0.0001;

  /// Vrai quand le cycle ouvert est le PREMIER paiement (installation).
  bool get estInstallation => typeCycle == 'installation';

  /// Libellé à afficher : l'installation comprend le premier mois.
  String get libelleCycle => estInstallation
      ? 'Installation (premier mois inclus)'
      : 'Abonnement du mois';

  static const PreparationRenouvellement aucune = PreparationRenouvellement();

  factory PreparationRenouvellement.depuisJson(Map<String, dynamic> json) {
    return PreparationRenouvellement(
      cycleOuvert: json['cycle_ouvert'] == true,
      motif: parseString(json['motif']),
      soldeRestant: parseDouble(json['solde_restant']),
      prixMensuel: parseDouble(json['prix_mensuel']),
      devise: parseString(json['devise'], fallback: 'CDF'),
      typeCycle: parseString(json['type_cycle'], fallback: 'abonnement'),
    );
  }
}

/// Résultat de `abonnement_ouvrir_avance` — **correctif 112**.
///
/// Pendant l'essai de 7 jours (ou avant l'échéance), le compte n'a **aucun
/// solde dû** : la passerelle Mobile Money refusait donc le paiement
/// (« rien à payer »). Cette fonction ouvre le cycle suivant au prix réel
/// (base + collaborateurs) **sans toucher au statut ni aux dates**, pour que
/// le client puisse payer immédiatement, essai compris.
///
/// Rien n'est perdu : au paiement, le moteur prolonge l'abonnement à partir
/// de la date d'expiration existante.
class AvanceCycle {
  const AvanceCycle({
    this.ouvert = false,
    this.motif = '',
    this.montant = 0,
    this.base = 0,
    this.supplementCollaborateurs = 0,
    this.joursRestants,
    this.devise = 'CDF',
    this.echeance,
    this.mois = 1,
    this.prixCycle = 0,
  });

  /// `true` si cet appel vient d'ouvrir le cycle anticipé.
  final bool ouvert;

  /// `CYCLE_ANTICIPE` (cycle ouvert) ou `DEJA_DU` (un solde était déjà dû).
  final String motif;

  /// Montant à encaisser (prix de base + supplément collaborateurs).
  final double montant;

  /// Part « prix de base » de [montant].
  final double base;

  /// Part « collaborateurs actifs » de [montant].
  final double supplementCollaborateurs;

  /// Jours restants sur l'accès en cours (essai ou abonnement).
  final int? joursRestants;

  final String devise;

  /// Échéance actuelle — conservée telle quelle par le serveur.
  final DateTime? echeance;

  /// 🗓️ MODULE 30 — nombre de mois réglés d'un coup (1 par défaut).
  final int mois;

  /// Prix d'UN cycle (base + collaborateurs), pour afficher le détail.
  final double prixCycle;

  static const AvanceCycle aucune = AvanceCycle();

  /// « 3 mois » — libellé de la durée choisie.
  String get libelleDuree => mois <= 1 ? '1 mois' : '$mois mois';

  /// 🗓️ Combien de jours ce paiement va-t-il ajouter ?
  int get joursAjoutes => 30 * (mois <= 0 ? 1 : mois);

  /// Échéance qui résultera du paiement (estimation locale).
  ///
  /// On part de l'échéance actuelle si elle est future (aucun jour payé n'est
  /// perdu), sinon de maintenant — exactement la règle du serveur.
  DateTime get echeanceEstimee {
    final DateTime base = (echeance != null && echeance!.isAfter(DateTime.now()))
        ? echeance!
        : DateTime.now();
    return base.add(Duration(days: joursAjoutes));
  }

  bool get aPayer => montant > 0.0001;

  /// Vrai si l'accès en cours n'est pas encore terminé (essai ou abonnement
  /// actif) : le client paie alors « par anticipation ».
  bool get anticipe => motif == 'CYCLE_ANTICIPE';

  factory AvanceCycle.depuisJson(Map<String, dynamic> json) {
    return AvanceCycle(
      ouvert: json['ouvert'] == true,
      motif: parseString(json['motif']),
      montant: parseDouble(json['montant']),
      base: parseDouble(json['base']),
      supplementCollaborateurs: parseDouble(json['supplement_collaborateurs']),
      joursRestants: json['jours_restants'] == null
          ? null
          : parseInt(json['jours_restants']),
      devise: parseString(json['devise'], fallback: 'CDF'),
      echeance: parseDateTimeOrNull(json['echeance']),
      mois: json['mois'] == null ? 1 : parseInt(json['mois'], fallback: 1),
      prixCycle: parseDouble(json['prix_cycle']),
    );
  }
}

/// Résultat de `rpc_abonnement_simulation_avance` — « l'avance intelligente ».
///
/// Question du client : « je verse 5 000 maintenant, ça me donne quoi ? »
/// Réponse : le prix du cycle divisé par 30 donne un prix par jour, donc
/// 5 000 sur un mois à 30 000 = environ 5 jours.
///
/// Le même calcul existe en LOCAL ([SimulationAvance.calculer]) pour répondre
/// instantanément à l'écran et **hors ligne**, sans attendre le serveur.
class SimulationAvance {
  const SimulationAvance({
    this.montantSaisi = 0,
    this.resteAPayer = 0,
    this.prixCycle = 0,
    this.prixJour = 0,
    this.joursObtenus = 0,
    this.cycleComplet = false,
    this.devise = 'CDF',
    this.dateFinEstimee,
  });

  final double montantSaisi;
  final double resteAPayer;
  final double prixCycle;
  final double prixJour;

  /// Nombre de jours que ce montant achète (0 si insuffisant).
  final int joursObtenus;

  /// `true` si le montant solde tout le cycle (un mois entier).
  final bool cycleComplet;

  final String devise;
  final DateTime? dateFinEstimee;

  static const SimulationAvance vide = SimulationAvance();

  bool get exploitable => montantSaisi > 0 && (prixJour > 0 || cycleComplet);

  bool get insuffisant => montantSaisi > 0 && !cycleComplet && joursObtenus <= 0;

  /// Phrase affichée sous le champ de montant.
  String get libelle {
    if (montantSaisi <= 0) {
      return 'Saisissez un montant : nous vous dirons combien de jours il couvre.';
    }
    if (cycleComplet) {
      return 'Mois complet réglé : l\'abonnement repart pour 30 jours.';
    }
    if (joursObtenus <= 0) {
      return 'Montant inférieur au prix d\'une journée '
          '(${prixJour.toStringAsFixed(0)} $devise).';
    }
    return 'Ce versement couvre environ $joursObtenus jour(s) '
        '(${prixJour.toStringAsFixed(0)} $devise/jour).';
  }

  factory SimulationAvance.depuisJson(Map<String, dynamic> json) {
    final String? fin = parseStringOrNull(json['date_fin_estimee']);
    return SimulationAvance(
      montantSaisi: parseDouble(json['montant_saisi']),
      resteAPayer: parseDouble(json['reste_a_payer']),
      prixCycle: parseDouble(json['prix_cycle']),
      prixJour: parseDouble(json['prix_jour']),
      joursObtenus: parseInt(json['jours_obtenus']),
      cycleComplet: json['cycle_complet'] == true,
      devise: parseString(json['devise'], fallback: 'CDF'),
      dateFinEstimee: fin == null ? null : DateTime.tryParse(fin),
    );
  }

  /// Calcul **hors ligne**, identique à la règle serveur :
  /// `prix_jour = prix_du_cycle / 30`, jours plafonnés à 30.
  ///
  /// [resteAPayer] à 0 ou inconnu → on prend [prixCycle] comme référence.
  factory SimulationAvance.calculer({
    required double montant,
    required double resteAPayer,
    required double prixCycle,
    String devise = 'CDF',
    DateTime? maintenant,
  }) {
    // Le prix d'une journée se lit sur le PRIX DU CYCLE (30 000 ⇒ 1 000/jour),
    // pas sur le reste : une avance garde la même valeur en jours.
    final double reference = prixCycle > 0.0001 ? prixCycle : resteAPayer;
    final double jour = reference > 0 ? reference / 30.0 : 0;
    final bool complet = montant > 0 &&
        resteAPayer > 0.0001 &&
        montant + 0.01 >= resteAPayer;
    int jours = 0;
    if (!complet && jour > 0 && montant > 0) {
      jours = (montant / jour).floor();
      if (jours > 30) jours = 30;
    }
    final DateTime base = maintenant ?? DateTime.now();
    return SimulationAvance(
      montantSaisi: montant,
      resteAPayer: resteAPayer,
      prixCycle: prixCycle,
      prixJour: jour,
      joursObtenus: complet ? 30 : jours,
      cycleComplet: complet,
      devise: devise,
      dateFinEstimee:
          base.add(Duration(days: complet ? 30 : jours)),
    );
  }
}
