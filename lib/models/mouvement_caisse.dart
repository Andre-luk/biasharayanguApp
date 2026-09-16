// lib/models/mouvement_caisse.dart
//
// MODULE 10 — CAISSE : mouvements et résumés.
//
// La caisse est CALCULÉE en temps réel par le serveur à partir de trois
// sources : les ventes encaissées (`caisse`, Module 8, et l'historique de
// l'ancienne caisse), les règlements de dettes (`paiements_dette`) et les
// dépenses (`depenses`). Ces objets ne font que transporter la réponse des
// RPC `rpc_caisse_resume`, `rpc_caisse_journal` et `rpc_caisse_cloturer`.

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature d'un mouvement de caisse.
enum TypeMouvementCaisse {
  vente('vente', 'Vente encaissée'),
  venteAncienne('vente_ancienne', 'Vente (ancienne caisse)'),
  reglementDette('dette', 'Règlement de dette'),
  depense('depense', 'Dépense'),
  inconnu('', 'Opération');

  const TypeMouvementCaisse(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypeMouvementCaisse depuisCode(String? code) {
    final String valeur = (code ?? '').trim().toLowerCase();
    for (final TypeMouvementCaisse type in TypeMouvementCaisse.values) {
      if (type.code == valeur) return type;
    }
    return TypeMouvementCaisse.inconnu;
  }
}

/// Sens d'un mouvement : l'argent entre ou sort.
enum SensMouvement {
  entree('entree', 'Entrée'),
  sortie('sortie', 'Sortie');

  const SensMouvement(this.code, this.libelle);

  final String code;
  final String libelle;

  static SensMouvement depuisCode(String? code) =>
      (code ?? '').trim().toLowerCase() == 'sortie'
          ? SensMouvement.sortie
          : SensMouvement.entree;
}

/// Une ligne de l'historique de caisse.
class MouvementCaisse {
  const MouvementCaisse({
    required this.type,
    required this.libelle,
    required this.sens,
    required this.mode,
    required this.montant,
    this.reference,
    this.date,
  });

  final TypeMouvementCaisse type;
  final String? reference;
  final String libelle;
  final SensMouvement sens;

  /// Code du mode de paiement (`especes`, `mobile_money`…).
  final String mode;
  final double montant;
  final DateTime? date;

  bool get estEntree => sens == SensMouvement.entree;

  factory MouvementCaisse.depuisRpc(Map<String, dynamic> map) {
    return MouvementCaisse(
      type: TypeMouvementCaisse.depuisCode(parseStringOrNull(map['type'])),
      reference: parseStringOrNull(map['reference']),
      libelle: parseString(map['libelle'], fallback: 'Opération'),
      sens: SensMouvement.depuisCode(parseStringOrNull(map['sens'])),
      mode: parseString(map['mode'], fallback: 'especes'),
      montant: parseDouble(map['montant']),
      date: parseDateTimeOrNull(map['date']),
    );
  }
}

/// Totaux d'un journal de caisse.
class TotauxJournalCaisse {
  const TotauxJournalCaisse({
    this.entrees = 0,
    this.sorties = 0,
    this.nb = 0,
  });

  final double entrees;
  final double sorties;
  final int nb;

  /// Solde de la période filtrée (`entrees − sorties`).
  double get solde => entrees - sorties;

  factory TotauxJournalCaisse.depuisRpc(Map<String, dynamic> map) {
    return TotauxJournalCaisse(
      entrees: parseDouble(map['entrees']),
      sorties: parseDouble(map['sorties']),
      nb: parseInt(map['nb']),
    );
  }
}

/// Résultat de `rpc_caisse_journal`.
class ResultatJournalCaisse {
  const ResultatJournalCaisse({
    this.debut,
    this.fin,
    this.sens,
    this.mode,
    this.lignes = const <MouvementCaisse>[],
    this.totaux = const TotauxJournalCaisse(),
  });

  final DateTime? debut;
  final DateTime? fin;
  final String? sens;
  final String? mode;
  final List<MouvementCaisse> lignes;
  final TotauxJournalCaisse totaux;

  factory ResultatJournalCaisse.depuisRpc(Map<String, dynamic> map) {
    return ResultatJournalCaisse(
      debut: parseDateTimeOrNull(map['debut']),
      fin: parseDateTimeOrNull(map['fin']),
      sens: parseStringOrNull(map['sens']),
      mode: parseStringOrNull(map['mode']),
      lignes: parseMapList(map['lignes'])
          .map(MouvementCaisse.depuisRpc)
          .toList(growable: false),
      totaux: TotauxJournalCaisse.depuisRpc(
          parseMap(map['totaux']) ?? <String, dynamic>{}),
    );
  }
}

/// Encaissements / décaissements cumulés d'un mode de paiement (jour).
class MouvementParMode {
  const MouvementParMode({
    required this.mode,
    this.encaissements = 0,
    this.decaissements = 0,
  });

  final String mode;
  final double encaissements;
  final double decaissements;

  double get net => encaissements - decaissements;

  factory MouvementParMode.depuisRpc(String mode, Map<String, dynamic> map) {
    return MouvementParMode(
      mode: mode,
      encaissements: parseDouble(map['encaissements']),
      decaissements: parseDouble(map['decaissements']),
    );
  }
}

/// Activité du jour affichée sur l'écran Caisse.
class ResumeCaisseJour {
  const ResumeCaisseJour({
    this.encaissementsVentes = 0,
    this.encaissementsDettes = 0,
    this.encaissements = 0,
    this.decaissements,
    this.net = 0,
    this.nbVentes = 0,
    this.nbPaiementsDettes = 0,
    this.nbDepenses = 0,
  });

  final double encaissementsVentes;
  final double encaissementsDettes;
  final double encaissements;

  /// `null` lorsque le rôle n'a pas le droit de voir les dépenses.
  final double? decaissements;
  final double net;
  final int nbVentes;
  final int nbPaiementsDettes;
  final int nbDepenses;

  factory ResumeCaisseJour.depuisRpc(Map<String, dynamic> map) {
    return ResumeCaisseJour(
      encaissementsVentes: parseDouble(map['encaissements_ventes']),
      encaissementsDettes: parseDouble(map['encaissements_dettes']),
      encaissements: parseDouble(map['encaissements']),
      decaissements: parseDoubleOrNull(map['decaissements']),
      net: parseDouble(map['net']),
      nbVentes: parseInt(map['nb_ventes']),
      nbPaiementsDettes: parseInt(map['nb_paiements_dettes']),
      nbDepenses: parseInt(map['nb_depenses']),
    );
  }
}

/// Dernière clôture de caisse connue (affichée sur l'écran Caisse).
class ClotureCaisseInfo {
  const ClotureCaisseInfo({
    this.dateCloture,
    this.soldeTheorique = 0,
    this.especeComptee,
    this.ecart,
    this.commentaire,
    this.createdAt,
  });

  final DateTime? dateCloture;
  final double soldeTheorique;
  final double? especeComptee;
  final double? ecart;
  final String? commentaire;
  final DateTime? createdAt;

  factory ClotureCaisseInfo.depuisRpc(Map<String, dynamic> map) {
    return ClotureCaisseInfo(
      dateCloture: parseDateTimeOrNull(map['date_cloture']),
      soldeTheorique: parseDouble(map['solde_theorique']),
      especeComptee: parseDoubleOrNull(map['espece_comptee']),
      ecart: parseDoubleOrNull(map['ecart']),
      commentaire: parseStringOrNull(map['commentaire']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }
}

/// Résumé complet renvoyé par `rpc_caisse_resume`.
class ResumeCaisse {
  const ResumeCaisse({
    this.date,
    this.solde,
    this.depensesVisibles = true,
    this.jour = const ResumeCaisseJour(),
    this.parMode = const <String, MouvementParMode>{},
    this.derniereCloture,
  });

  final DateTime? date;

  /// Solde global (tout l'historique) — `null` si le rôle ne voit pas les
  /// dépenses (les décaissements lui sont masqués par le serveur).
  final double? solde;
  final bool depensesVisibles;
  final ResumeCaisseJour jour;
  final Map<String, MouvementParMode> parMode;
  final ClotureCaisseInfo? derniereCloture;

  factory ResumeCaisse.depuisRpc(Map<String, dynamic> map) {
    final Map<String, dynamic> modesBrut =
        parseMap(map['par_mode']) ?? <String, dynamic>{};
    final Map<String, MouvementParMode> modes = <String, MouvementParMode>{};
    modesBrut.forEach((String cle, dynamic valeur) {
      final Map<String, dynamic>? contenu = parseMap(valeur);
      if (contenu != null) {
        modes[cle] = MouvementParMode.depuisRpc(cle, contenu);
      }
    });

    final Map<String, dynamic>? derniere = parseMap(map['derniere_cloture']);

    return ResumeCaisse(
      date: parseDateTimeOrNull(map['date']),
      solde: parseDoubleOrNull(map['solde']),
      depensesVisibles: map['depenses_visibles'] == true,
      jour: ResumeCaisseJour.depuisRpc(
          parseMap(map['jour']) ?? <String, dynamic>{}),
      parMode: modes,
      derniereCloture:
          derniere == null ? null : ClotureCaisseInfo.depuisRpc(derniere),
    );
  }
}

/// Résultat d'une clôture de caisse (`rpc_caisse_cloturer`).
class ResultatClotureCaisse {
  const ResultatClotureCaisse({
    required this.clotureId,
    this.dateCloture,
    this.fondInitial = 0,
    this.encaissementsTotal = 0,
    this.decaissementsTotal = 0,
    this.soldeTheorique = 0,
    this.especeComptee,
    this.ecart,
    this.commentaire,
    this.details = const <String, dynamic>{},
    this.createdAt,
  });

  final int clotureId;
  final DateTime? dateCloture;
  final double fondInitial;
  final double encaissementsTotal;
  final double decaissementsTotal;
  final double soldeTheorique;
  final double? especeComptee;
  final double? ecart;
  final String? commentaire;
  final Map<String, dynamic> details;
  final DateTime? createdAt;

  factory ResultatClotureCaisse.depuisRpc(Map<String, dynamic> map) {
    return ResultatClotureCaisse(
      clotureId: parseInt(map['cloture_id']),
      dateCloture: parseDateTimeOrNull(map['date_cloture']),
      fondInitial: parseDouble(map['fond_initial']),
      encaissementsTotal: parseDouble(map['encaissements_total']),
      decaissementsTotal: parseDouble(map['decaissements_total']),
      soldeTheorique: parseDouble(map['solde_theorique']),
      especeComptee: parseDoubleOrNull(map['espece_comptee']),
      ecart: parseDoubleOrNull(map['ecart']),
      commentaire: parseStringOrNull(map['commentaire']),
      details: parseMap(map['details']) ?? <String, dynamic>{},
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }
}
