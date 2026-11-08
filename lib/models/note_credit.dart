// lib/models/note_credit.dart
//
// 🧾 MODULE 32 — AVOIR / NOTE DE CRÉDIT.
//
// Un avoir ne SUPPRIME jamais la vente d'origine : il émet un document séparé
// (`AV-AAAAMMJJ-NNNN`) qui vient en déduction. C'est la seule façon de rendre
// de l'argent à un client tout en gardant des comptes lisibles.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Type d'avoir : somme à valoir, ou argent réellement rendu.
enum TypeAvoir {
  avoir('AVOIR', 'Avoir (somme à valoir)'),
  remboursement('REMBOURSEMENT', 'Remboursement (argent rendu)');

  const TypeAvoir(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypeAvoir fromCode(String? code) {
    final String c = (code ?? '').trim().toUpperCase();
    for (final TypeAvoir t in values) {
      if (t.code == c) return t;
    }
    return TypeAvoir.avoir;
  }
}

/// Statut d'un avoir : émis, ou annulé (jamais supprimé).
enum StatutAvoir {
  emis('EMIS', 'Émis'),
  annule('ANNULE', 'Annulé');

  const StatutAvoir(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutAvoir fromCode(String? code) {
    final String c = (code ?? '').trim().toUpperCase();
    return c == 'ANNULE' ? StatutAvoir.annule : StatutAvoir.emis;
  }
}

/// Un avoir émis par la boutique.
class NoteCredit {
  const NoteCredit({
    required this.id,
    this.numero = '',
    this.venteId,
    this.factureNumero,
    this.clientNom,
    this.clientTelephone,
    this.montant = 0,
    this.devise = 'CDF',
    this.type = TypeAvoir.avoir,
    this.modeRemboursement,
    this.motif,
    this.statut = StatutAvoir.emis,
    this.date,
    this.annuleLe,
    this.motifAnnulation,
    this.auteur,
  });

  final String id;
  final String numero;

  /// Vente d'origine, si l'avoir en vient.
  final String? venteId;

  /// Numéro de la facture d'origine (`VTE-AAAAMMJJ-NNNN`).
  final String? factureNumero;

  final String? clientNom;
  final String? clientTelephone;
  final double montant;
  final String devise;
  final TypeAvoir type;
  final String? modeRemboursement;
  final String? motif;
  final StatutAvoir statut;
  final DateTime? date;
  final DateTime? annuleLe;
  final String? motifAnnulation;

  /// Qui a émis l'avoir.
  final String? auteur;

  bool get estAnnule => statut == StatutAvoir.annule;

  bool get estRemboursement => type == TypeAvoir.remboursement;

  /// « avoir AV-20261108-0001 du 08/11/2026 ».
  String get libelle => 'Avoir $numero';

  static const NoteCredit aucune = NoteCredit(id: '');

  static NoteCredit fromMap(Map<String, dynamic> map) {
    return NoteCredit(
      id: parseString(map['id']),
      numero: parseString(map['numero']),
      venteId: parseStringOrNull(map['vente_id']),
      factureNumero: parseStringOrNull(map['facture_numero']),
      clientNom: parseStringOrNull(map['client_nom']),
      clientTelephone: parseStringOrNull(map['client_telephone']),
      montant: parseDouble(map['montant']),
      devise: parseString(map['devise'], fallback: 'CDF'),
      type: TypeAvoir.fromCode(parseStringOrNull(map['type'])),
      modeRemboursement: parseStringOrNull(map['mode_remboursement']),
      motif: parseStringOrNull(map['motif']),
      statut: StatutAvoir.fromCode(parseStringOrNull(map['statut'])),
      date: parseDateTimeOrNull(map['date']),
      annuleLe: parseDateTimeOrNull(map['annule_le']),
      motifAnnulation: parseStringOrNull(map['motif_annulation']),
      auteur: parseStringOrNull(map['auteur']),
    );
  }
}
