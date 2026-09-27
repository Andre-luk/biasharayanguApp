// lib/models/lien_attribution.dart
//
// 🛒 MODULE 19 — CODES D'ATTRIBUTION (« BIA-XXXXXX »).
//
// Objectif : pouvoir dire, un jour, « cette vente a été apportée par Biashara »
// SANS jamais prétendre qu'une simple consultation est un achat.
//
// Cas d'usage prévus (architecture prête, exploitation progressive) :
//   • QR affiché sur la vitrine ou le ticket : le client le présente en caisse ;
//   • lien de suivi partagé (réseaux sociaux, WhatsApp) ;
//   • code promotionnel annoncé dans une campagne publicitaire.
//
// ⚠️ Le module 8 (`rpc_vente_valider`) n'est PAS modifié : l'exploitation du
//    code en caisse fera l'objet d'une évolution dédiée, qui enregistrera un
//    événement `conversion`.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature du support d'attribution.
enum TypeLienAttribution {
  qr('qr', 'QR code'),
  lien('lien', 'Lien de suivi'),
  // ⚠️ La valeur d'énuméré ne peut pas s'appeler `code` : elle entrerait en
  // conflit avec le champ `code` (le code d'attribution lui-même).
  promotionnel('code', 'Code promotionnel');

  const TypeLienAttribution(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypeLienAttribution fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final TypeLienAttribution t in values) {
      if (t.code == normalise) return t;
    }
    return TypeLienAttribution.qr;
  }
}

/// Un code d'attribution appartenant à une boutique.
class LienAttribution {
  const LienAttribution({
    required this.id,
    required this.code,
    this.type = TypeLienAttribution.qr,
    this.libelle,
    this.cibleUrl,
    this.produitId,
    this.actif = true,
    this.utilisations = 0,
    this.createdAt,
  });

  final String id;
  final String code;
  final TypeLienAttribution type;
  final String? libelle;
  final String? cibleUrl;
  final int? produitId;
  final bool actif;
  final int utilisations;
  final DateTime? createdAt;

  factory LienAttribution.fromMap(Map<String, dynamic> map) {
    return LienAttribution(
      id: parseString(map['id']),
      code: parseString(map['code']),
      type: TypeLienAttribution.fromCode(parseStringOrNull(map['type_lien'])),
      libelle: parseStringOrNull(map['libelle']),
      cibleUrl: parseStringOrNull(map['cible_url']),
      produitId: map['produit_id'] == null ? null : parseInt(map['produit_id']),
      actif: map['actif'] == true,
      utilisations: parseInt(map['utilisations']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }

  /// Texte à communiquer au client (« Présentez ce code en caisse »).
  String get messageClient =>
      'Présentez le code $code en caisse pour que votre achat soit rattaché '
      'à Biashara.';
}
