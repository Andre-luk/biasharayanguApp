// lib/models/pressing_caisse.dart
//
// 🧺 MODULE 35 — LA CAISSE DU PRESSING (JOURNÉE).
//
// Deux idées, et elles n'en font qu'une :
//   • l'argent du pressing entre en PLUSIEURS fois (acompte au dépôt, solde à
//     la remise) : le total du jour ne dit pas COMMENT il est entré ;
//   • un encaissement annulé n'est jamais effacé : il est compté à part.
//
// Ce modèle lit `pressing_caisse_jour` : encaissement réel par mode,
// annulations, activité (dépôts, remises) et détail ligne par ligne — la
// source du rapport imprimable.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Un encaissement du jour.
class PaiementJourPressing {
  const PaiementJourPressing({
    required this.id,
    required this.numero,
    required this.montant,
    this.client = '',
    this.mode = 'especes',
    this.reference,
    this.agent = '',
    this.annule = false,
    this.motifAnnulation,
    this.encaisseLe,
  });

  final String id;

  /// Numéro du dossier (`PR-2026-000123`).
  final String numero;

  final String client;
  final double montant;

  /// Code du mode (`especes`, `mobile_money`, `carte`…).
  final String mode;

  final String? reference;
  final String agent;
  final bool annule;
  final String? motifAnnulation;
  final DateTime? encaisseLe;

  /// Libellé du mode de paiement, en français.
  String get libelleMode => libelleModePaiement(mode);

  factory PaiementJourPressing.fromMap(Map<String, dynamic> map) {
    return PaiementJourPressing(
      id: parseString(map['id']),
      numero: parseString(map['numero']),
      client: parseString(map['client']),
      montant: parseDouble(map['montant']),
      mode: parseString(map['mode'], fallback: 'especes'),
      reference: parseStringOrNull(map['reference']),
      agent: parseString(map['agent']),
      annule: parseBool(map['annule']),
      motifAnnulation: parseStringOrNull(map['motif_annulation']),
      encaisseLe: parseDateTimeOrNull(map['encaisse_le']),
    );
  }
}

/// Total d'un mode de paiement.
class TotalModeJour {
  const TotalModeJour({required this.mode, required this.montant, required this.nb});

  final String mode;
  final double montant;
  final int nb;

  String get libelle => libelleModePaiement(mode);

  factory TotalModeJour.fromMap(String mode, Map<String, dynamic> map) {
    return TotalModeJour(
      mode: mode,
      montant: parseDouble(map['montant']),
      nb: parseInt(map['nb']),
    );
  }
}

/// La caisse d'une journée de pressing.
class CaisseJourPressing {
  const CaisseJourPressing({
    this.date,
    this.encaisse = 0,
    this.nbPaiements = 0,
    this.annule = 0,
    this.nbAnnules = 0,
    this.parMode = const <String, TotalModeJour>{},
    this.paiements = const <PaiementJourPressing>[],
    this.depots = 0,
    this.montantFacture = 0,
    this.remises = 0,
    this.resteDu = 0,
  });

  final DateTime? date;

  /// Encaissement réel (paiements non annulés).
  final double encaisse;
  final int nbPaiements;

  /// Montant annulé dans la journée (compté à part, jamais déduit en silence).
  final double annule;
  final int nbAnnules;

  final Map<String, TotalModeJour> parMode;
  final List<PaiementJourPressing> paiements;

  /// Dossiers déposés ce jour et montant facturé correspondant.
  final int depots;
  final double montantFacture;

  /// Nombre de remises (retraits) effectuées ce jour.
  final int remises;

  /// Reste dû global du pressing (toutes périodes).
  final double resteDu;

  bool get estVide => nbPaiements == 0 && paiements.isEmpty;

  /// Modes triés du plus encaissé au moins encaissé.
  List<TotalModeJour> get modesTries {
    final List<TotalModeJour> liste = parMode.values.toList();
    liste.sort((TotalModeJour a, TotalModeJour b) =>
        b.montant.compareTo(a.montant));
    return liste;
  }

  factory CaisseJourPressing.fromRpc(Map<String, dynamic> map) {
    final Map<String, TotalModeJour> modes = <String, TotalModeJour>{};
    final Map<String, dynamic> bruts =
        parseMap(map['par_mode']) ?? const <String, dynamic>{};
    bruts.forEach((String mode, dynamic valeur) {
      modes[mode] = TotalModeJour.fromMap(
        mode,
        parseMap(valeur) ?? const <String, dynamic>{},
      );
    });

    return CaisseJourPressing(
      date: parseDateTimeOrNull(map['date']),
      encaisse: parseDouble(map['encaisse']),
      nbPaiements: parseInt(map['nb_paiements']),
      annule: parseDouble(map['annule']),
      nbAnnules: parseInt(map['nb_annules']),
      parMode: modes,
      paiements: parseMapList(map['paiements'])
          .map(PaiementJourPressing.fromMap)
          .toList(growable: false),
      depots: parseInt(map['depots']),
      montantFacture: parseDouble(map['montant_facture']),
      remises: parseInt(map['remises']),
      resteDu: parseDouble(map['reste_du']),
    );
  }
}

/// Libellé français d'un code de mode de paiement.
String libelleModePaiement(String? code) {
  switch ((code ?? '').trim().toLowerCase()) {
    case 'especes':
    case 'espèces':
      return 'Espèces';
    case 'mobile_money':
    case 'mobile money':
      return 'Mobile Money';
    case 'carte':
      return 'Carte';
    case 'virement':
      return 'Virement';
    case 'credit':
    case 'dette':
      return 'Crédit';
    default:
      final String propre = (code ?? '').trim();
      return propre.isEmpty ? 'Autre' : propre;
  }
}
