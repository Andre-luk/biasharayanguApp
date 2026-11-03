// lib/services/paiement_platforme_service.dart
//
// 💳 POINT D'ENTRÉE UNIQUE DES PAIEMENTS DE LA PLATEFORME.
//
// Règle métier (audit des paiements) :
//
//   • ESPÈCES / virement / autre  → encaissement classique : le moteur
//     d'abonnement (`rpc_abonnement_enregistrer_paiement`) est appelé par
//     l'écran qui a le droit d'encaisser ;
//   • MOBILE MONEY                → OBLIGATOIREMENT SerdiPay : on ouvre
//     `PaiementSerdipayPage`, le montant est calculé en base, et le crédit
//     n'arrive qu'après confirmation du webhook ;
//   • CARTE BANCAIRE              → aucun contrat d'acquisition n'existe :
//     le mode est refusé explicitement (jamais encaissé comme des espèces).
//
// Pourquoi centraliser : les écrans (abonnement commerçant, validation
// finance, agent, quotas IA) ne doivent pas réimplémenter la règle — une
// seule fonction décide, et le serveur la re-vérifie de toute façon
// (trigger `trg_paiement_mm_serdipay`, migration 0102).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/pages/paiement_serdipay_page.dart';

/// Issue d'un paiement de plateforme.
enum IssuePaiementPlateforme {
  /// Encaissement classique enregistré par l'écran appelant.
  encaisse,

  /// Paiement Mobile Money confirmé par SerdiPay.
  payeSerdipay,

  /// L'utilisateur a abandonné ou le paiement n'est pas confirmé.
  nonAbouti,
}

/// Décisions et navigation des paiements de plateforme.
class PaiementPlatformeService {
  PaiementPlatformeService._();

  /// Reconnaît « Mobile Money » et ses variantes (accents, tirets, casse).
  static bool estMobileMoney(String? mode) {
    final String valeur = _normaliser(mode);
    if (valeur.isEmpty) return false;
    return <String>{
      'MOBILE_MONEY',
      'MOBILEMONEY',
      'M_PESA',
      'MPESA',
      'ORANGE_MONEY',
      'ORANGEMONEY',
      'AIRTEL_MONEY',
      'AIRTELMONEY',
      'MM',
      'MONEY',
      'MOBILE',
    }.contains(valeur);
  }

  /// Reconnaît les espèces (seul mode qui autorise un encaissement manuel).
  static bool estEspeces(String? mode) {
    final String valeur = _normaliser(mode);
    return valeur.isEmpty ||
        valeur == 'ESPECES' ||
        valeur == 'ESPECE' ||
        valeur == 'CASH' ||
        valeur == 'LIQUIDE';
  }

  /// Ramène un libellé de mode à sa forme comparable :
  /// `« Mobile Money »`, `mobile-money`, `ESPÈCES ` → `MOBILE_MONEY`, `ESPECES`.
  static String _normaliser(String? mode) {
    return (mode ?? '')
        .toUpperCase()
        .replaceAll('È', 'E')
        .replaceAll('É', 'E')
        .replaceAll(RegExp(r'[\s\-/]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Ouvre le parcours SerdiPay. Renvoie `true` si le paiement est confirmé.
  ///
  /// [entrepriseId] : payer POUR une autre entreprise (plateforme, agent).
  /// Le serveur vérifie le droit : ce paramètre n'en donne aucun.
  static Future<bool> payerParMobileMoney(
    BuildContext context, {
    required String? entrepriseId,
    String? libelleEntreprise,
    String objet = 'abonnement',
    String? objetId,
  }) async {
    final bool? paye = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PaiementSerdipayPage(
          objet: objet,
          objetId: objetId,
          entrepriseId: entrepriseId,
          libelleEntreprise: libelleEntreprise,
        ),
      ),
    );
    return paye == true;
  }

  /// Message à afficher quand un mode n'est pas disponible.
  static String messageModeIndisponible(String? mode) {
    if (estMobileMoney(mode)) {
      return 'Les paiements Mobile Money passent par SerdiPay : utilisez le '
          'bouton « Payer par Mobile Money ».';
    }
    return 'Ce moyen de paiement n\'est pas encore disponible. '
        'Utilisez les espèces ou Mobile Money (SerdiPay).';
  }
}
