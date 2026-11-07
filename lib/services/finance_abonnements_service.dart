// lib/services/finance_abonnements_service.dart
//
// MODULE 27 — VISION FINANCE / SUPER ADMIN DES ABONNEMENTS
//
// Trois lectures, une seule vérité :
//   • `resume()`      → facturé, encaissé, dû, répartition par moyen de paiement ;
//   • `entreprises()` → la situation de chaque boutique ;
//   • `transactions()`→ la traçabilité Mobile Money / SerdiPay.
//
// ⚠️ Aucun montant n'est calculé ici : tout vient du serveur. L'écran ne fait
//    que présenter et formater ; c'est ce qui garantit que la caisse, la vente
//    et le tableau de bord affichent toujours les mêmes chiffres.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier lisible (le message serveur est déjà en français).
class FinanceAbonnementsException implements Exception {
  const FinanceAbonnementsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Point de la courbe « encaissé par jour ».
class PointEncaissement {
  const PointEncaissement({
    required this.jour,
    required this.montant,
    required this.nombre,
  });

  final DateTime? jour;
  final double montant;
  final int nombre;

  static PointEncaissement fromMap(Map<String, dynamic> map) {
    return PointEncaissement(
      jour: parseDateTimeOrNull(map['jour']),
      montant: parseDouble(map['montant']),
      nombre: parseInt(map['nb']),
    );
  }
}

/// Synthèse financière de la plateforme sur une période.
class ResumeFinance {
  const ResumeFinance({
    this.debut,
    this.fin,
    this.entreprisesTotal = 0,
    this.abonnementsActifs = 0,
    this.abonnementsExpires = 0,
    this.abonnementsEnAttente = 0,
    this.abonnementsPartiels = 0,
    this.montantFacture = 0,
    this.montantEncaisseCumule = 0,
    this.soldeARecouvrer = 0,
    this.supplementsCollaborateurs = 0,
    this.paiementsPeriode = 0,
    this.encaissePeriode = 0,
    this.encaisseEspeces = 0,
    this.encaisseMobileMoney = 0,
    this.encaisseCarte = 0,
    this.encaisseAutres = 0,
    this.parJour = const <PointEncaissement>[],
  });

  final DateTime? debut;
  final DateTime? fin;
  final int entreprisesTotal;
  final int abonnementsActifs;
  final int abonnementsExpires;
  final int abonnementsEnAttente;
  final int abonnementsPartiels;
  final double montantFacture;
  final double montantEncaisseCumule;
  final double soldeARecouvrer;
  final double supplementsCollaborateurs;
  final int paiementsPeriode;
  final double encaissePeriode;
  final double encaisseEspeces;
  final double encaisseMobileMoney;
  final double encaisseCarte;
  final double encaisseAutres;
  final List<PointEncaissement> parJour;

  static const ResumeFinance vide = ResumeFinance();

  /// Taux de recouvrement en pourcentage (0 quand rien n'est facturé).
  double get tauxRecouvrement {
    if (montantFacture <= 0.009) return 0;
    final double taux = montantEncaisseCumule / montantFacture * 100;
    return taux.isFinite ? taux.clamp(0, 100) : 0;
  }

  bool get estVide => entreprisesTotal == 0 && paiementsPeriode == 0;

  static ResumeFinance fromMap(Map<String, dynamic> map) {
    return ResumeFinance(
      debut: parseDateTimeOrNull(map['debut']),
      fin: parseDateTimeOrNull(map['fin']),
      entreprisesTotal: parseInt(map['entreprises_total']),
      abonnementsActifs: parseInt(map['abonnements_actifs']),
      abonnementsExpires: parseInt(map['abonnements_expires']),
      abonnementsEnAttente: parseInt(map['abonnements_en_attente']),
      abonnementsPartiels: parseInt(map['abonnements_partiels']),
      montantFacture: parseDouble(map['montant_facture']),
      montantEncaisseCumule: parseDouble(map['montant_encaisse_cumule']),
      soldeARecouvrer: parseDouble(map['solde_a_recouvrer']),
      supplementsCollaborateurs:
          parseDouble(map['supplements_collaborateurs']),
      paiementsPeriode: parseInt(map['paiements_periode']),
      encaissePeriode: parseDouble(map['encaisse_periode']),
      encaisseEspeces: parseDouble(map['encaisse_especes']),
      encaisseMobileMoney: parseDouble(map['encaisse_mobile_money']),
      encaisseCarte: parseDouble(map['encaisse_carte']),
      encaisseAutres: parseDouble(map['encaisse_autres']),
      parJour: parseMapList(map['par_jour'])
          .map(PointEncaissement.fromMap)
          .toList(growable: false),
    );
  }
}

/// Situation financière d'une entreprise.
class LigneFinanceEntreprise {
  const LigneFinanceEntreprise({
    required this.entrepriseId,
    this.nom = '—',
    this.statut = '',
    this.devise = 'CDF',
    this.echeance,
    this.joursRestants,
    this.montantFacture = 0,
    this.montantEncaisse = 0,
    this.soldeDu = 0,
    this.supplementCollaborateurs = 0,
    this.collaborateurs = 0,
    this.dernierPaiement,
    this.totalPaiements = 0,
    this.serdipayEnAttente = 0,
  });

  final String entrepriseId;
  final String nom;
  final String statut;
  final String devise;
  final DateTime? echeance;
  final int? joursRestants;
  final double montantFacture;
  final double montantEncaisse;
  final double soldeDu;
  final double supplementCollaborateurs;
  final int collaborateurs;
  final DateTime? dernierPaiement;
  final int totalPaiements;
  final int serdipayEnAttente;

  bool get enRetard => soldeDu > 0.009;

  double get tauxPaiement {
    if (montantFacture <= 0.009) return 0;
    final double taux = montantEncaisse / montantFacture * 100;
    return taux.isFinite ? taux.clamp(0, 100) : 0;
  }

  static LigneFinanceEntreprise fromMap(Map<String, dynamic> map) {
    return LigneFinanceEntreprise(
      entrepriseId: parseString(map['entreprise_id']),
      nom: parseString(map['nom'], fallback: '—'),
      statut: parseString(map['statut']),
      devise: parseString(map['devise'], fallback: 'CDF'),
      echeance: parseDateTimeOrNull(map['echeance']),
      joursRestants: map['jours_restants'] == null
          ? null
          : parseInt(map['jours_restants']),
      montantFacture: parseDouble(map['montant_facture']),
      montantEncaisse: parseDouble(map['montant_encaisse']),
      soldeDu: parseDouble(map['solde_du']),
      supplementCollaborateurs: parseDouble(map['supplement_collaborateurs']),
      collaborateurs: parseInt(map['collaborateurs']),
      dernierPaiement: parseDateTimeOrNull(map['dernier_paiement']),
      totalPaiements: parseInt(map['total_paiements']),
      serdipayEnAttente: parseInt(map['serdipay_en_attente']),
    );
  }
}

/// Une transaction Mobile Money, telle que le prestataire l'a renvoyée.
class TransactionSerdipay {
  const TransactionSerdipay({
    required this.id,
    this.entrepriseId,
    this.entreprise,
    this.reference,
    this.referenceFournisseur,
    this.montant = 0,
    this.devise = 'CDF',
    this.operateur,
    this.telephone,
    this.nomPayeur,
    this.statut = '',
    this.objet,
    this.initieParNom,
    this.date,
    this.confirmeLe,
    this.motifEchec,
    this.frais,
    this.montantNet,
    this.rapproche = false,
    this.rapprocheLe,
  });

  final String id;
  final String? entrepriseId;
  final String? entreprise;
  final String? reference;
  final String? referenceFournisseur;
  final double montant;
  final String devise;
  final String? operateur;
  final String? telephone;
  final String? nomPayeur;
  final String statut;
  final String? objet;
  final String? initieParNom;
  final DateTime? date;
  final DateTime? confirmeLe;
  final String? motifEchec;
  final double? frais;
  final double? montantNet;
  final bool rapproche;
  final DateTime? rapprocheLe;

  bool get estPayee => statut.toLowerCase() == 'paye';

  bool get estEnAttente => statut.toLowerCase() == 'en_attente';

  bool get estEchouee {
    final String s = statut.toLowerCase();
    return s == 'echoue' || s == 'annule' || s == 'expire';
  }

  /// Libellé français du statut — les valeurs du prestataire restent lisibles.
  String get libelleStatut {
    switch (statut.toLowerCase()) {
      case 'paye':
        return 'Payée';
      case 'en_attente':
        return 'En attente';
      case 'echoue':
        return 'Échouée';
      case 'annule':
        return 'Annulée';
      case 'expire':
        return 'Expirée';
      default:
        return statut.isEmpty ? 'Inconnu' : statut;
    }
  }

  static TransactionSerdipay fromMap(Map<String, dynamic> map) {
    return TransactionSerdipay(
      id: parseString(map['id']),
      entrepriseId: parseStringOrNull(map['entreprise_id']),
      entreprise: parseStringOrNull(map['entreprise']),
      reference: parseStringOrNull(map['reference']),
      referenceFournisseur: parseStringOrNull(map['reference_fournisseur']),
      montant: parseDouble(map['montant']),
      devise: parseString(map['devise'], fallback: 'CDF'),
      operateur: parseStringOrNull(map['operateur']),
      telephone: parseStringOrNull(map['telephone']),
      nomPayeur: parseStringOrNull(map['nom_payeur']),
      statut: parseString(map['statut']),
      objet: parseStringOrNull(map['objet']),
      initieParNom: parseStringOrNull(map['initie_par_nom']),
      date: parseDateTimeOrNull(map['date']),
      confirmeLe: parseDateTimeOrNull(map['confirme_le']),
      motifEchec: parseStringOrNull(map['motif_echec']),
      frais: parseDoubleOrNull(map['frais']),
      montantNet: parseDoubleOrNull(map['montant_net']),
      rapproche: parseBool(map['rapproche']),
      rapprocheLe: parseDateTimeOrNull(map['rapproche_le']),
    );
  }
}

/// Accès unique aux données financières de la plateforme.
///
/// Singleton : `FinanceAbonnementsService.instance`.
class FinanceAbonnementsService {
  FinanceAbonnementsService._();

  static final FinanceAbonnementsService instance =
      FinanceAbonnementsService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Synthèse « facturé / encaissé / dû » sur une période.
  Future<ResumeFinance> resume({DateTime? debut, DateTime? fin}) async {
    try {
      final dynamic reponse = await _client.rpc(
        'finance_abonnements_resume',
        params: <String, dynamic>{
          'p_debut': _date(debut),
          'p_fin': _date(fin),
        },
      );
      final Map<String, dynamic>? map = parseMap(reponse);
      if (map == null) return ResumeFinance.vide;
      return ResumeFinance.fromMap(map);
    } on PostgrestException catch (e) {
      throw FinanceAbonnementsException(_message(e.message));
    } catch (e) {
      debugPrint('FinanceAbonnementsService.resume : $e');
      throw const FinanceAbonnementsException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
      );
    }
  }

  /// Dossier financier de chaque entreprise.
  Future<List<LigneFinanceEntreprise>> entreprises({
    String? recherche,
    String? statut,
    int limite = 200,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'finance_abonnements_entreprises',
        params: <String, dynamic>{
          'p_recherche': _texte(recherche),
          'p_statut': _texte(statut),
          'p_limite': limite,
        },
      );
      return parseMapList(reponse)
          .map(LigneFinanceEntreprise.fromMap)
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw FinanceAbonnementsException(_message(e.message));
    } catch (e) {
      debugPrint('FinanceAbonnementsService.entreprises : $e');
      throw const FinanceAbonnementsException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
      );
    }
  }

  /// Traçabilité des transactions Mobile Money.
  Future<List<TransactionSerdipay>> transactions({
    String? recherche,
    String? statut,
    int limite = 100,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'finance_serdipay_transactions',
        params: <String, dynamic>{
          'p_recherche': _texte(recherche),
          'p_statut': _texte(statut),
          'p_limite': limite,
        },
      );
      return parseMapList(reponse)
          .map(TransactionSerdipay.fromMap)
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw FinanceAbonnementsException(_message(e.message));
    } catch (e) {
      debugPrint('FinanceAbonnementsService.transactions : $e');
      throw const FinanceAbonnementsException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
      );
    }
  }

  /// Pointe (ou dé-pointe) une transaction par rapport au relevé SerdiPay.
  ///
  /// Ne modifie AUCUN montant : c'est une coche de contrôle.
  Future<bool> rapprocher(String id, bool rapproche) async {
    if (id.trim().isEmpty) {
      throw const FinanceAbonnementsException('Transaction inconnue.');
    }
    try {
      final dynamic reponse = await _client.rpc(
        'finance_serdipay_rapprocher',
        params: <String, dynamic>{
          'p_id': id,
          'p_rapproche': rapproche,
        },
      );
      final Map<String, dynamic>? map = parseMap(reponse);
      return parseBool(map?['rapproche'], fallback: rapproche);
    } on PostgrestException catch (e) {
      throw FinanceAbonnementsException(_message(e.message));
    } catch (e) {
      debugPrint('FinanceAbonnementsService.rapprocher : $e');
      throw const FinanceAbonnementsException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// `AAAA-MM-JJ` ou `null` — le serveur applique sa période par défaut.
  String? _date(DateTime? valeur) {
    if (valeur == null) return null;
    final String mois = valeur.month.toString().padLeft(2, '0');
    final String jour = valeur.day.toString().padLeft(2, '0');
    return '${valeur.year}-$mois-$jour';
  }

  String? _texte(String? valeur) {
    final String? propre = parseStringOrNull(valeur);
    return propre;
  }

  /// Extrait le texte après `CODE|` (convention de l'application).
  String _message(String brut) {
    final int barre = brut.indexOf('|');
    if (barre == -1) return brut;
    final String texte = brut.substring(barre + 1).trim();
    return texte.isEmpty ? brut : texte;
  }
}
