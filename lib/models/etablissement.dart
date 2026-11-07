// lib/models/etablissement.dart
//
// MODULE 27 — L'IDENTITÉ DE L'ÉTABLISSEMENT, TELLE QU'ELLE APPARAÎT SUR LES
// DOCUMENTS COMMERCIAUX.
//
// ⚠️ RÈGLE ABSOLUE : rien n'est inventé. Un champ absent vaut `null` et la
//    facture MASQUE la ligne (pas de « RCCM : — », pas d'adresse fabriquée).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Fiche de l'établissement vendeur (source : `etablissement_fiche()`).
class Etablissement {
  const Etablissement({
    this.ownerId,
    this.espaceId,
    this.nom = '',
    this.adresse,
    this.quartier,
    this.avenue,
    this.numero,
    this.repere,
    this.ville,
    this.telephone,
    this.whatsapp,
    this.email,
    this.logoUrl,
    this.rccm,
    this.idNational,
    this.devise = 'CDF',
  });

  final String? ownerId;
  final String? espaceId;
  final String nom;
  final String? adresse;
  final String? quartier;
  final String? avenue;
  final String? numero;
  final String? repere;
  final String? ville;
  final String? telephone;
  final String? whatsapp;
  final String? email;
  final String? logoUrl;

  /// Numéro RCCM — FACULTATIF.
  final String? rccm;

  /// Identifiant national / fiscal — FACULTATIF.
  final String? idNational;

  final String devise;

  /// Nom affichable (jamais vide).
  String get nomAffiche => nom.trim().isEmpty ? 'Établissement' : nom.trim();

  /// Adresse sur deux lignes maximum : rue, puis ville.
  List<String> get lignesAdresse {
    final List<String> lignes = <String>[];
    final String? rue = adresse;
    if (rue != null && rue.trim().isNotEmpty) lignes.add(rue.trim());
    if (ville != null && ville!.trim().isNotEmpty) {
      lignes.add(ville!.trim());
    } else if (quartier != null && quartier!.trim().isNotEmpty) {
      lignes.add(quartier!.trim());
    }
    return lignes;
  }

  bool get aMentionsLegales =>
      (rccm != null && rccm!.trim().isNotEmpty) ||
      (idNational != null && idNational!.trim().isNotEmpty);

  factory Etablissement.fromMap(Map<String, dynamic> map) {
    return Etablissement(
      ownerId: parseStringOrNull(map['owner_id']),
      espaceId: parseStringOrNull(map['espace_id']),
      nom: parseString(map['nom']),
      adresse: parseStringOrNull(map['adresse']),
      quartier: parseStringOrNull(map['quartier']),
      avenue: parseStringOrNull(map['avenue']),
      numero: parseStringOrNull(map['numero']),
      repere: parseStringOrNull(map['repere']),
      ville: parseStringOrNull(map['ville']),
      telephone: parseStringOrNull(map['telephone']),
      whatsapp: parseStringOrNull(map['whatsapp']),
      email: parseStringOrNull(map['email']),
      logoUrl: parseStringOrNull(map['logo_url']),
      rccm: parseStringOrNull(map['rccm']),
      idNational: parseStringOrNull(map['id_national']),
      devise: parseString(map['devise'], fallback: 'CDF'),
    );
  }

  Etablissement copyWith({
    String? nom,
    String? adresse,
    String? quartier,
    String? avenue,
    String? numero,
    String? repere,
    String? telephone,
    String? email,
    String? rccm,
    String? idNational,
    String? logoUrl,
  }) {
    return Etablissement(
      ownerId: ownerId,
      espaceId: espaceId,
      nom: nom ?? this.nom,
      adresse: adresse ?? this.adresse,
      quartier: quartier ?? this.quartier,
      avenue: avenue ?? this.avenue,
      numero: numero ?? this.numero,
      repere: repere ?? this.repere,
      ville: ville,
      telephone: telephone ?? this.telephone,
      whatsapp: whatsapp,
      email: email ?? this.email,
      logoUrl: logoUrl ?? this.logoUrl,
      rccm: rccm ?? this.rccm,
      idNational: idNational ?? this.idNational,
      devise: devise,
    );
  }
}
