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
