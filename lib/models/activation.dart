// lib/models/activation.dart
//
// MODULE 14 — WORKFLOW D'ACTIVATION À DOUBLE VALIDATION.
//
// Cycle de vie d'une entreprise (boutique) :
//
//   création → EN ATTENTE DE VÉRIFICATION
//            → GESTIONNAIRE DES COMPTES (vérifie / rejette)
//            → FINANCE (valide le paiement : partiel = 7 jours d'essai,
//              total = 30 jours immédiats)
//            → ACTIF
//            → (solde impayé à l'échéance) RESTREINT
//            → (régularisation) ACTIF.
//
// Ces structures reproduisent le JSON renvoyé par les RPC SQL de la
// migration `20260916000018_module14_activation.sql` :
//   - `rpc_activation_etat`        → [EtatActivation]  (tableau de bord client)
//   - `rpc_activation_lister`      → [DossierActivation] (écrans admin)
//   - `rpc_activation_verifier`    → vérification gestionnaire
//   - `rpc_activation_valider_finance` → validation finale + activation.

import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Étape du dossier d'activation d'une entreprise.
///
/// ⚠️ [code] est la valeur stockée dans `public.entreprises.activation_etape`.
enum EtapeActivation {
  aucune('aucune', 'Aucun dossier'),
  enAttenteVerification(
      'en_attente_verification', 'En attente de vérification'),
  verifie('verifie', 'Vérifié — en attente de la finance'),
  actif('actif', 'Actif'),
  restreint('restreint', 'Restreint (solde impayé)'),
  rejete('rejete', 'Rejeté');

  const EtapeActivation(this.code, this.libelle);

  /// Valeur enregistrée en base.
  final String code;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// `true` si le dossier attend une action du gestionnaire des comptes.
  bool get attendGestionnaire => this == EtapeActivation.enAttenteVerification;

  /// `true` si le dossier attend une action de la finance.
  bool get attendFinance =>
      this == EtapeActivation.verifie || this == EtapeActivation.restreint;

  /// Convertit un code SQL en étape applicative ([aucune] si inconnu).
  static EtapeActivation fromCode(String? code) {
    if (code == null) return EtapeActivation.aucune;

    final String normalise = code.trim().toLowerCase();
    for (final EtapeActivation etape in values) {
      if (etape.code == normalise) return etape;
    }
    return EtapeActivation.aucune;
  }
}

/// Ligne d'historique du dossier (`public.activations_entreprise`).
///
/// ⚠️ [code] est la valeur stockée dans `activations_entreprise.etape`.
enum EtapeHistoriqueActivation {
  soumission('soumission', 'Dossier créé'),
  verification('verification', 'Vérifié par le gestionnaire'),
  rejetVerification('rejet_verification', 'Rejeté (gestionnaire)'),
  paiementFinance('paiement_finance', 'Paiement validé (finance)'),
  rejetFinance('rejet_finance', 'Paiement rejeté (finance)'),
  restriction('restriction', 'Accès restreint (solde impayé)');

  const EtapeHistoriqueActivation(this.code, this.libelle);

  final String code;
  final String libelle;

  /// Convertit un code SQL en étape d'historique, ou `null` si inconnu.
  static EtapeHistoriqueActivation? fromCode(String? code) {
    if (code == null) return null;

    for (final EtapeHistoriqueActivation etape in values) {
      if (etape.code == code) return etape;
    }
    return null;
  }
}

/// Nature du paiement sur le dossier (tableau de bord client).
enum TypePaiementActivation {
  total('total', 'Paiement total'),
  partiel('partiel', 'Paiement partiel'),
  aucun('aucun', 'Aucun paiement');

  const TypePaiementActivation(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypePaiementActivation fromCode(String? code) {
    if (code == null) return TypePaiementActivation.aucun;

    for (final TypePaiementActivation type in values) {
      if (type.code == code) return type;
    }
    return TypePaiementActivation.aucun;
  }
}

/// Entrée de l'historique d'un dossier d'activation.
class EntreeActivation {
  const EntreeActivation({
    required this.etape,
    this.role,
    this.montant,
    this.modePaiement,
    this.reference,
    this.note,
    this.le,
  });

  /// Étape enregistrée (soumission, vérification, paiement, rejet…).
  final EtapeHistoriqueActivation? etape;

  /// Rôle de l'auteur de l'action (`GESTIONNAIRE_COMPTES`, `FINANCE_LAPERLE`).
  final String? role;

  /// Montant encaissé, pour les étapes de paiement.
  final double? montant;

  /// Mode de paiement (Espèces, Mobile Money…).
  final String? modePaiement;

  /// Référence de transaction, si fournie.
  final String? reference;

  /// Note / motif laissé par l'acteur.
  final String? note;

  /// Date de l'action.
  final DateTime? le;

  factory EntreeActivation.fromMap(Map<String, dynamic> map) {
    return EntreeActivation(
      etape:
          EtapeHistoriqueActivation.fromCode(parseStringOrNull(map['etape'])),
      role: parseStringOrNull(map['role']),
      montant: parseDoubleOrNull(map['montant']),
      modePaiement: parseStringOrNull(map['mode_paiement']),
      reference: parseStringOrNull(map['reference']),
      note: parseStringOrNull(map['note']),
      le: parseDateTimeOrNull(map['le']),
    );
  }

  /// `true` si l'entrée correspond à un encaissement enregistré.
  bool get estPaiement => etape == EtapeHistoriqueActivation.paiementFinance;

  /// `true` si l'entrée correspond à un rejet.
  bool get estRejet =>
      etape == EtapeHistoriqueActivation.rejetVerification ||
      etape == EtapeHistoriqueActivation.rejetFinance;
}

/// Tableau de bord du dossier d'activation (écran client).
///
/// Renvoyé par `rpc_activation_etat`. Quand l'utilisateur n'a pas encore
/// d'entreprise, l'étape vaut [EtapeActivation.aucune] et tous les autres
/// champs sont vides.
class EtatActivation {
  const EtatActivation({
    this.entrepriseId,
    this.nom,
    this.etape = EtapeActivation.aucune,
    this.statut,
    this.typePaiement = TypePaiementActivation.aucun,
    this.montantTotalDu = 0,
    this.montantDejaPaye = 0,
    this.soldeRestant = 0,
    this.dateActivation,
    this.dateExpiration,
    this.joursRestants,
    this.verifieLe,
    this.valideLeFinance,
    this.historique = const <EntreeActivation>[],
  });

  final String? entrepriseId;
  final String? nom;

  /// Étape du workflow d'activation.
  final EtapeActivation etape;

  /// Statut de l'abonnement Module 3 (ESSAI_7J, ACTIF, EXPIRE…).
  final StatutAbonnement? statut;

  /// Nature du paiement enregistré sur le dossier.
  final TypePaiementActivation typePaiement;

  final double montantTotalDu;
  final double montantDejaPaye;
  final double soldeRestant;

  final DateTime? dateActivation;
  final DateTime? dateExpiration;

  /// Jours restants avant l'échéance (`null` si aucune date).
  final int? joursRestants;

  /// Date de la vérification par le gestionnaire des comptes.
  final DateTime? verifieLe;

  /// Date de la validation finale par la finance.
  final DateTime? valideLeFinance;

  /// Historique complet (du plus récent au plus ancien).
  final List<EntreeActivation> historique;

  /// `true` si l'utilisateur possède une entreprise avec un dossier suivi.
  bool get aUnDossier => etape != EtapeActivation.aucune;

  /// `true` si l'abonnement est intégralement réglé.
  bool get estSolde => soldeRestant <= 0;

  /// `true` si l'abonnement est échu (statut ou date dépassée).
  bool get abonnementEchu {
    if (statut == StatutAbonnement.expire ||
        statut == StatutAbonnement.enAttenteComplement) {
      return true;
    }
    final DateTime? echeance = dateExpiration;
    return echeance != null && echeance.isBefore(DateTime.now());
  }

  /// `true` si le client doit ouvrir un nouveau cycle avant de pouvoir payer :
  /// abonnement échu ET rien à régler sur le cycle précédent.
  ///
  /// C'est exactement le cas qui bloquait le renouvellement en autonomie.
  bool get doitRenouveler => abonnementEchu && estSolde;

  /// `true` si AUCUN franc n'a encore été encaissé sur ce compte.
  ///
  /// C'est le cas d'un compte en essai de 7 jours : il utilise l'application
  /// sans avoir payé. Il doit donc voir un bouton de paiement, même si son
  /// `solde_restant` vaut 0 (le prix du cycle n'est pas encore réclamé).
  bool get jamaisPaye => montantDejaPaye <= 0.009;

  /// `true` si le compte est encore dans son essai de 7 jours (non échu).
  bool get enEssai =>
      statut == StatutAbonnement.essai7j && !abonnementEchu;

  /// Le compte est-il « à payer » ?
  ///
  /// Règle unique utilisée par les écrans pour décider d'afficher le bouton
  /// de paiement. Elle couvre **tous** les cas demandés :
  ///   • essai de 7 jours jamais payé   → [jamaisPaye] ;
  ///   • solde partiel ou avance        → `soldeRestant > 0` ;
  ///   • abonnement échu                → [abonnementEchu] ;
  ///   • renouvellement anticipé        → jamais payé / essai en cours.
  /// C'est le drapeau des ALERTES (bandeaux, badges rouges) : il ne vaut
  /// `true` que si quelque chose cloche vraiment (impayé, partiel, échu).
  bool get aPayer {
    if (!aUnDossier) return false;
    if (soldeRestant > 0.009) return true;
    if (jamaisPaye) return true;
    if (abonnementEchu) return true;
    return enEssai;
  }

  /// Un compte à jour peut malgré tout régler le mois suivant : le bouton
  /// reste donc accessible, mais sans alerte (« payer par anticipation »).
  bool get peutPayerAnticipe => aUnDossier && !aPayer;

  /// Libellé du bouton de paiement, adapté à la situation réelle.
  String get libellePaiement {
    if (soldeRestant > 0.009) return 'Payer le solde de mon abonnement';
    if (abonnementEchu) return 'Renouveler mon abonnement';
    if (enEssai) return 'Payer mon abonnement';
    return 'Payer mon prochain mois';
  }

  /// Phrase d'explication affichée au-dessus du bouton.
  String get explicationPaiement {
    final String jours = joursRestants == null
        ? ''
        : ' (${joursRestants!} jour${joursRestants == 1 ? '' : 's'} restant'
            '${joursRestants == 1 ? '' : 's'})';

    if (soldeRestant > 0.009) {
      return 'Il reste un montant à régler pour que votre compte soit à jour. '
          'Vous pouvez payer maintenant par Mobile Money ou carte.';
    }
    if (abonnementEchu) {
      return 'Votre abonnement est arrivé à échéance. Réglez le mois suivant '
          'pour réactiver immédiatement toutes les fonctions.';
    }
    if (enEssai) {
      return 'Vous êtes en période d\'essai$jours et vous n\'avez pas encore '
          'payé. Vous pouvez régler votre abonnement dès maintenant : les '
          'jours déjà acquis ne sont pas perdus.';
    }
    if (jamaisPaye) {
      return 'Aucun paiement n\'a encore été enregistré sur ce compte. '
          'Réglez votre abonnement dès maintenant.';
    }
    return 'Votre compte est à jour. Vous pouvez régler le mois suivant par '
        'anticipation : la nouvelle période s\'ajoute à votre échéance '
        'actuelle$jours.';
  }

  /// Taux de règlement (0 → 1), pour la barre de progression.
  double get tauxPaiement {
    if (montantTotalDu <= 0) return 0;
    final double taux = montantDejaPaye / montantTotalDu;
    if (taux < 0) return 0;
    if (taux > 1) return 1;
    return taux;
  }

  /// Message court expliquant où en est le dossier.
  String get messageEtape {
    switch (etape) {
      case EtapeActivation.enAttenteVerification:
        return 'Votre compte est en attente de vérification par le '
            'gestionnaire des comptes.';
      case EtapeActivation.verifie:
        return 'Votre dossier a été vérifié. La finance va confirmer votre '
            'paiement pour activer votre compte.';
      case EtapeActivation.actif:
        return estSolde
            ? 'Votre compte est actif.'
            : 'Votre compte est actif avec un solde à régler avant '
                "l'échéance.";
      case EtapeActivation.restreint:
        return 'Votre accès est restreint : un solde reste à régler. Vos '
            'données sont conservées.';
      case EtapeActivation.rejete:
        return 'Votre dossier a été rejeté. Contactez l\'assistance.';
      case EtapeActivation.aucune:
        return 'Aucun dossier d\'activation pour le moment.';
    }
  }

  factory EtatActivation.fromMap(Map<String, dynamic> map) {
    final String? codeStatut = parseStringOrNull(map['statut']);

    return EtatActivation(
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      nom: parseStringOrNull(map['nom']),
      etape: EtapeActivation.fromCode(parseStringOrNull(map['etape'])),
      statut: codeStatut == null ? null : StatutAbonnement.fromCode(codeStatut),
      typePaiement: TypePaiementActivation.fromCode(
          parseStringOrNull(map['type_paiement'])),
      montantTotalDu: parseDouble(map['montant_total_du']),
      montantDejaPaye: parseDouble(map['montant_deja_paye']),
      soldeRestant: parseDouble(map['solde_restant']),
      dateActivation: parseDateTimeOrNull(map['date_activation']),
      dateExpiration: parseDateTimeOrNull(map['date_expiration']),
      joursRestants: map['jours_restants'] == null
          ? null
          : parseInt(map['jours_restants']),
      verifieLe: parseDateTimeOrNull(map['verifie_le']),
      valideLeFinance: parseDateTimeOrNull(map['valide_le_finance']),
      historique: (map['historique'] is List)
          ? (map['historique'] as List)
              .whereType<Map>()
              .map((Map element) =>
                  EntreeActivation.fromMap(Map<String, dynamic>.from(element)))
              .toList(growable: false)
          : const <EntreeActivation>[],
    );
  }
}

/// Dossier d'activation vu par les écrans admin (gestionnaire / finance).
///
/// Renvoyé par `rpc_activation_lister` : entreprise + coordonnées du
/// responsable + dernière motif de rejet éventuel.
class DossierActivation {
  const DossierActivation({
    required this.id,
    required this.nom,
    this.etape = EtapeActivation.aucune,
    this.statut,
    this.ville,
    this.activite,
    this.montantTotalDu = 0,
    this.montantDejaPaye = 0,
    this.soldeRestant = 0,
    this.dateActivation,
    this.dateExpiration,
    this.createdAt,
    this.verifieLe,
    this.valideLeFinance,
    this.responsable,
    this.contact,
    this.telephone,
    this.dernierMotif,
  });

  /// Identifiant de l'entreprise (public.entreprises.id).
  final String id;
  final String nom;

  final EtapeActivation etape;
  final StatutAbonnement? statut;

  final String? ville;
  final String? activite;

  final double montantTotalDu;
  final double montantDejaPaye;
  final double soldeRestant;

  final DateTime? dateActivation;
  final DateTime? dateExpiration;

  /// Date de création de l'entreprise (dépôt du dossier).
  final DateTime? createdAt;

  final DateTime? verifieLe;
  final DateTime? valideLeFinance;

  /// Nom du responsable (compte principal de la boutique).
  final String? responsable;

  /// Email de contact du responsable.
  final String? contact;

  /// Téléphone du responsable, si renseigné.
  final String? telephone;

  /// Motif du dernier rejet (gestionnaire ou finance), si applicable.
  final String? dernierMotif;

  /// `true` si l'abonnement est intégralement réglé.
  bool get estSolde => soldeRestant <= 0;

  factory DossierActivation.fromMap(Map<String, dynamic> map) {
    final String? codeStatut = parseStringOrNull(map['statut']);

    return DossierActivation(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      etape: EtapeActivation.fromCode(parseStringOrNull(map['etape'])),
      statut: codeStatut == null ? null : StatutAbonnement.fromCode(codeStatut),
      ville: parseStringOrNull(map['ville']),
      activite: parseStringOrNull(map['activite']),
      montantTotalDu: parseDouble(map['montant_total_du']),
      montantDejaPaye: parseDouble(map['montant_deja_paye']),
      soldeRestant: parseDouble(map['solde_restant']),
      dateActivation: parseDateTimeOrNull(map['date_activation']),
      dateExpiration: parseDateTimeOrNull(map['date_expiration']),
      createdAt: parseDateTimeOrNull(map['created_at']),
      verifieLe: parseDateTimeOrNull(map['verifie_le']),
      valideLeFinance: parseDateTimeOrNull(map['valide_le_finance']),
      responsable: parseStringOrNull(map['responsable']),
      contact: parseStringOrNull(map['contact']),
      telephone: parseStringOrNull(map['telephone']),
      dernierMotif: parseStringOrNull(map['dernier_motif']),
    );
  }
}
