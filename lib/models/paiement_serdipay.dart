// lib/models/paiement_serdipay.dart
//
// PASSERELLE DE PAIEMENT SERDIPAY (migration 79).
//
// Un « paiement SerdiPay » est une TENTATIVE de règlement d'un abonnement
// (ou d'une facture d'abonnement) par Mobile Money / carte. Son montant est
// calculé par le serveur : ce modèle ne fait que LIRE ce que la base a décidé.
//
// Les valeurs de [StatutPaiementSerdipay.code] sont celles de la colonne
// `paiements_serdipay.statut` — ne pas les renommer.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Statut d'une tentative de paiement SerdiPay.
enum StatutPaiementSerdipay {
  enAttente('en_attente', 'En attente'),
  paye('paye', 'Payé'),
  echoue('echoue', 'Échoué'),
  annule('annule', 'Annulé'),
  expire('expire', 'Expiré'),
  inconnu('inconnu', 'Inconnu');

  const StatutPaiementSerdipay(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutPaiementSerdipay fromCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    for (final StatutPaiementSerdipay statut in values) {
      if (statut.code == valeur) return statut;
    }
    return StatutPaiementSerdipay.inconnu;
  }
}

/// Opérateurs proposés à l'écran de paiement.
///
/// [code] est envoyé tel quel à la passerelle ; l'adaptateur de l'Edge
/// Function le traduit vers le vocabulaire attendu par SerdiPay.
enum OperateurSerdipay {
  orange('orange', 'Orange Money'),
  airtel('airtel', 'Airtel Money'),
  mpesa('mpesa', 'M-Pesa'),
  afrimoney('afrimoney', 'Afrimoney'),
  carte('carte', 'Carte bancaire');

  const OperateurSerdipay(this.code, this.libelle);

  final String code;
  final String libelle;

  static OperateurSerdipay? fromCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    for (final OperateurSerdipay operateur in values) {
      if (operateur.code == valeur) return operateur;
    }
    return null;
  }
}

/// Objet réglé par le paiement.
enum ObjetPaiementSerdipay {
  abonnement('abonnement', 'Abonnement'),
  facture('facture', 'Facture'),
  inconnu('inconnu', 'Autre');

  const ObjetPaiementSerdipay(this.code, this.libelle);

  final String code;
  final String libelle;

  static ObjetPaiementSerdipay fromCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    for (final ObjetPaiementSerdipay objet in values) {
      if (objet.code == valeur) return objet;
    }
    return ObjetPaiementSerdipay.inconnu;
  }
}

/// Une tentative de paiement telle que renvoyée par l'Edge Function.
class PaiementSerdipay {
  const PaiementSerdipay({
    this.id,
    required this.reference,
    this.entrepriseId,
    this.objet = ObjetPaiementSerdipay.abonnement,
    this.objetId,
    this.montant = 0,
    this.devise = 'CDF',
    this.statut = StatutPaiementSerdipay.enAttente,
    this.operateur,
    this.telephone,
    this.urlPaiement,
    this.providerReference,
    this.motifEchec,
    this.message,
    this.expireLe,
    this.payeLe,
    this.createdAt,
  });

  final String? id;

  /// Référence INTERNE `SER-AAAAMMJJ-XXXXXXXX` (à citer au support).
  final String reference;

  final String? entrepriseId;
  final ObjetPaiementSerdipay objet;
  final String? objetId;

  final double montant;
  final String devise;

  final StatutPaiementSerdipay statut;

  final OperateurSerdipay? operateur;
  final String? telephone;

  /// Lien de paiement hébergé (peut être `null` : validation USSD).
  final String? urlPaiement;

  final String? providerReference;
  final String? motifEchec;

  /// Message d'information renvoyé par la passerelle.
  final String? message;

  final DateTime? expireLe;
  final DateTime? payeLe;
  final DateTime? createdAt;

  bool get estEnAttente => statut == StatutPaiementSerdipay.enAttente;
  bool get estPaye => statut == StatutPaiementSerdipay.paye;
  bool get estTermine => !estEnAttente;

  /// `true` si l'utilisateur doit ouvrir une page de paiement.
  bool get demandeOuvertureNavigateur =>
      estEnAttente && (urlPaiement?.startsWith('http') ?? false);

  /// Libellé prêt à afficher (montant + devise).
  String get montantLibelle {
    final String valeur = montant == montant.roundToDouble()
        ? montant.toStringAsFixed(0)
        : montant.toStringAsFixed(2).replaceAll('.', ',');
    return '$valeur $devise';
  }

  factory PaiementSerdipay.fromMap(Map<String, dynamic> map) {
    return PaiementSerdipay(
      id: parseStringOrNull(map['id']),
      reference: parseString(map['reference']),
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      objet: ObjetPaiementSerdipay.fromCode(parseStringOrNull(map['objet'])),
      objetId: parseStringOrNull(map['objet_id']),
      montant: parseDouble(map['montant']),
      devise: parseString(map['devise'], fallback: 'CDF'),
      statut: StatutPaiementSerdipay.fromCode(
        parseStringOrNull(map['statut']),
      ),
      operateur: OperateurSerdipay.fromCode(parseStringOrNull(map['operateur'])),
      telephone: parseStringOrNull(map['telephone']),
      urlPaiement: parseStringOrNull(map['url_paiement']),
      providerReference: parseStringOrNull(map['provider_reference']),
      motifEchec: parseStringOrNull(map['motif_echec']),
      message: parseStringOrNull(map['message']),
      expireLe: parseDateTimeOrNull(map['expire_le']),
      payeLe: parseDateTimeOrNull(map['paye_le']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }

  /// Construit le paiement depuis l'enveloppe `{ok:true, paiement:{…}}`.
  factory PaiementSerdipay.depuisEnveloppe(Map<String, dynamic> map) {
    final Map<String, dynamic>? paiement = parseMap(map['paiement']);
    if (paiement == null) {
      return PaiementSerdipay.fromMap(map);
    }
    return PaiementSerdipay.fromMap(<String, dynamic>{
      ...paiement,
      if (map['message'] != null) 'message': map['message'],
    });
  }

  PaiementSerdipay copyWith({
    StatutPaiementSerdipay? statut,
    String? urlPaiement,
    String? motifEchec,
    String? message,
    DateTime? payeLe,
  }) {
    return PaiementSerdipay(
      id: id,
      reference: reference,
      entrepriseId: entrepriseId,
      objet: objet,
      objetId: objetId,
      montant: montant,
      devise: devise,
      statut: statut ?? this.statut,
      operateur: operateur,
      telephone: telephone,
      urlPaiement: urlPaiement ?? this.urlPaiement,
      providerReference: providerReference,
      motifEchec: motifEchec ?? this.motifEchec,
      message: message ?? this.message,
      expireLe: expireLe,
      payeLe: payeLe ?? this.payeLe,
      createdAt: createdAt,
    );
  }
}
