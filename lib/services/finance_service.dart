// lib/services/finance_service.dart
//
// MODULE 10 — FINANCE DE L'ENTREPRISE : caisse, dépenses, rapports.
//
// Toutes les opérations passent par les transactions serveur de la migration
// `20260916000011_module10_finance.sql` :
//
//   • `rpc_depense_creer` / `_supprimer` / `_liste`   — dépenses (sorties) ;
//   • `rpc_caisse_resume` / `_journal` / `_cloturer`  — caisse calculée ;
//   • `rpc_finance_tableau_bord` / `rpc_finance_rapport` — rapports.
//
// Rappels de conception :
//   • la CAISSE n'est PAS stockée : le serveur la recalcule à chaque appel
//     (ventes encaissées + règlements de dettes − dépenses) ;
//   • l'ISOLATION est garantie côté serveur : seule l'entreprise voit sa
//     finance (aucun rôle plateforme, sauf Super Admin explicitement
//     autorisé par réglage) ;
//   • un vendeur sans droit `depenses/voir` reçoit `solde = null` et
//     `decaissements = null` : l'interface masque ces montants.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/depense_finance.dart';
import 'package:biashara_yangu/models/finance_stats.dart';
import 'package:biashara_yangu/models/mouvement_caisse.dart';
import 'package:biashara_yangu/models/rapport_finance.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart' show reponseRpcEnMap;
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';

/// Nature d'une erreur de finance (pour adapter l'interface).
enum TypeErreurFinance { droits, validation, reseau, inconnu }

/// Erreur métier du module Finance (message déjà rédigé en français).
class FinanceServiceException implements Exception {
  const FinanceServiceException(
    this.message, {
    this.type = TypeErreurFinance.inconnu,
  });

  final String message;
  final TypeErreurFinance type;

  @override
  String toString() => message;
}

/// Caisse, dépenses et rapports financiers d'une entreprise.
///
/// Singleton : `FinanceService.instance`.
class FinanceService {
  FinanceService._();

  static final FinanceService instance = FinanceService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Modes de paiement acceptés (mêmes codes que le Module 8).
  static const Map<String, String> modesPaiement = VenteService.modesPaiement;

  /// Libellé affichable d'un code de paiement.
  static String libelleMode(String code) => modesPaiement[code] ?? code;

  /// Catégories de dépenses proposées par défaut (le serveur accepte aussi
  /// toute catégorie personnalisée).
  static const List<String> categoriesParDefaut = <String>[
    'achat',
    'transport',
    'loyer',
    'salaires',
    'electricite',
    'eau',
    'internet',
    'taxes',
    'entretien',
    'autre',
  ];

  // ---------------------------------------------------------------------------
  // DÉPENSES
  // ---------------------------------------------------------------------------

  /// Enregistre une dépense (sortie de caisse).
  ///
  /// Le serveur vérifie le droit `depenses/creer`, l'entreprise et les
  /// valeurs, puis journalise l'opération (`journal_audit` → `DEPENSE`).
  Future<DepenseFinance> creerDepense({
    required String motif,
    required double montant,
    DateTime? date,
    String? categorie,
  }) async {
    final String motifPropre = motif.trim();
    if (motifPropre.length < 2) {
      throw const FinanceServiceException(
        'Indiquez le motif de la dépense (2 caractères minimum).',
        type: TypeErreurFinance.validation,
      );
    }
    if (montant <= 0) {
      throw const FinanceServiceException(
        'Le montant de la dépense doit être supérieur à zéro.',
        type: TypeErreurFinance.validation,
      );
    }

    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_depense_creer',
      params: <String, dynamic>{
        'p_motif': motifPropre,
        'p_montant': montant,
        if (date != null) 'p_date': date.toUtc().toIso8601String(),
        if (categorie != null && categorie.trim().isNotEmpty)
          'p_categorie': categorie.trim(),
      },
      actionLibelle: "l'enregistrement de la dépense",
    );

    if (map == null) {
      throw const FinanceServiceException(
        "Réponse inattendue du serveur : la dépense n'est pas confirmée.",
      );
    }
    return DepenseFinance.depuisRpc(map);
  }

  /// Supprime une dépense (erreur de saisie) — droit `depenses/supprimer`.
  Future<void> supprimerDepense(int depenseId) async {
    await _appelerRpc(
      'rpc_depense_supprimer',
      params: <String, dynamic>{'p_depense_id': depenseId},
      actionLibelle: 'la suppression de la dépense',
    );
  }

  /// Liste les dépenses d'une période, avec totaux et catégories connues.
  Future<ResultatListeDepenses> listerDepenses({
    DateTime? debut,
    DateTime? fin,
    String? categorie,
    int limit = 200,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_depenses_liste',
      params: <String, dynamic>{
        if (debut != null) 'p_debut': _dateSeule(debut),
        if (fin != null) 'p_fin': _dateSeule(fin),
        if (categorie != null && categorie.trim().isNotEmpty)
          'p_categorie': categorie.trim(),
        'p_limit': limit,
      },
      actionLibelle: 'la lecture des dépenses',
    );

    return ResultatListeDepenses.depuisRpc(map ?? <String, dynamic>{});
  }

  // ---------------------------------------------------------------------------
  // CAISSE
  // ---------------------------------------------------------------------------

  /// Résumé de caisse d'une journée (par défaut : aujourd'hui) + solde global
  /// + dernière clôture. Recalculé en temps réel par le serveur.
  Future<ResumeCaisse> resumeCaisse({DateTime? date}) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_caisse_resume',
      params: <String, dynamic>{
        if (date != null) 'p_date': _dateSeule(date),
      },
      actionLibelle: 'la lecture de la caisse',
    );

    return ResumeCaisse.depuisRpc(map ?? <String, dynamic>{});
  }

  /// Historique unifié de la caisse (ventes, règlements de dettes, dépenses).
  ///
  /// [sens] : `entree` / `sortie` (ou `null` pour tout) ;
  /// [mode] : code de paiement (`especes`, `mobile_money`…).
  Future<ResultatJournalCaisse> journalCaisse({
    DateTime? debut,
    DateTime? fin,
    String? sens,
    String? mode,
    int limit = 200,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_caisse_journal',
      params: <String, dynamic>{
        if (debut != null) 'p_debut': _dateSeule(debut),
        if (fin != null) 'p_fin': _dateSeule(fin),
        if (sens != null) 'p_sens': sens,
        if (mode != null) 'p_mode': mode,
        'p_limit': limit,
      },
      actionLibelle: "la lecture de l'historique de caisse",
    );

    return ResultatJournalCaisse.depuisRpc(map ?? <String, dynamic>{});
  }

  /// Clôture la caisse d'une journée : le serveur fige les totaux dans
  /// `clotures_caisse`, calcule l'écart espèces et journalise l'opération.
  Future<ResultatClotureCaisse> cloturerCaisse({
    DateTime? date,
    double fondInitial = 0,
    double? especeComptee,
    String? commentaire,
  }) async {
    if (fondInitial < 0) {
      throw const FinanceServiceException(
        'Le fond de caisse ne peut pas être négatif.',
        type: TypeErreurFinance.validation,
      );
    }
    if (especeComptee != null && especeComptee < 0) {
      throw const FinanceServiceException(
        "L'espèce comptée ne peut pas être négative.",
        type: TypeErreurFinance.validation,
      );
    }

    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_caisse_cloturer',
      params: <String, dynamic>{
        if (date != null) 'p_date': _dateSeule(date),
        'p_fond_initial': fondInitial,
        if (especeComptee != null) 'p_espece_comptee': especeComptee,
        if (commentaire != null && commentaire.trim().isNotEmpty)
          'p_commentaire': commentaire.trim(),
      },
      actionLibelle: 'la clôture de la caisse',
    );

    if (map == null) {
      throw const FinanceServiceException(
        "Réponse inattendue du serveur : la clôture n'est pas confirmée.",
      );
    }
    return ResultatClotureCaisse.depuisRpc(map);
  }

  // ---------------------------------------------------------------------------
  // RAPPORTS
  // ---------------------------------------------------------------------------

  /// Tableau de bord : jour / semaine / mois, séries 7 et 30 jours,
  /// top articles (droit `finance/voir`).
  Future<TableauBordFinance> tableauBord({DateTime? reference}) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_finance_tableau_bord',
      params: <String, dynamic>{
        if (reference != null) 'p_ref': _dateSeule(reference),
      },
      actionLibelle: 'la lecture du tableau de bord',
    );

    return TableauBordFinance.depuisRpc(map ?? <String, dynamic>{});
  }

  /// Rapport détaillé (`rapports/voir` ou `finance/voir`).
  Future<RapportFinance> rapport({
    required GroupeRapportFinance groupe,
    DateTime? debut,
    DateTime? fin,
  }) async {
    final Map<String, dynamic>? map = await _appelerRpc(
      'rpc_finance_rapport',
      params: <String, dynamic>{
        'p_groupe': groupe.code,
        if (debut != null) 'p_debut': _dateSeule(debut),
        if (fin != null) 'p_fin': _dateSeule(fin),
      },
      actionLibelle: 'la lecture du rapport',
    );

    return RapportFinance.depuisRpc(groupe, map ?? <String, dynamic>{});
  }

  // ---------------------------------------------------------------------------
  // OUTILS PARTAGÉS
  // ---------------------------------------------------------------------------

  /// Extrait le message utilisateur d'une erreur du serveur (le code est
  /// séparé du texte par « | »).
  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  static TypeErreurFinance _typeDepuisMessage(String brut) {
    final String code = brut.trim().split('|').first.trim().toUpperCase();
    switch (code) {
      case 'SESSION_ABSENTE':
      case 'ACCES_REFUSE':
      case 'DROIT_REFUSE':
      case 'HORS_ENTREPRISE':
        return TypeErreurFinance.droits;
      case 'PERIODE_INVALIDE':
      case 'MONTANT_INVALIDE':
      case 'MONTANT_EXCESSIF':
      case 'MOTIF_OBLIGATOIRE':
      case 'DATE_INVALIDE':
      case 'SENS_INVALIDE':
      case 'STATUT_INVALIDE':
      case 'GROUPE_INVALIDE':
      case 'MODE_INVALIDE':
      case 'CANAL_INVALIDE':
      case 'DEPENSE_INTROUVABLE':
      case 'DETTE_INTROUVABLE':
      case 'CLIENT_INTROUVABLE':
      case 'DEJA_SOLDEE':
      case 'SANS_TELEPHONE':
        return TypeErreurFinance.validation;
      default:
        return TypeErreurFinance.inconnu;
    }
  }

  /// Appelle une RPC du module et renvoie sa réponse en `Map` (ou `null`).
  Future<Map<String, dynamic>?> _appelerRpc(
    String fonction, {
    required Map<String, dynamic> params,
    required String actionLibelle,
  }) async {
    dynamic reponse;
    try {
      reponse = await _client.rpc(fonction, params: params);
    } on PostgrestException catch (e) {
      debugPrint(
          'FinanceService ($actionLibelle) PostgrestException: ${e.code} ${e.message}');
      throw FinanceServiceException(
        messageErreur(e.message),
        type: _typeDepuisMessage(e.message),
      );
    } catch (e, st) {
      debugPrint('FinanceService ($actionLibelle): $e\n$st');
      throw const FinanceServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurFinance.reseau,
      );
    }

    return reponseRpcEnMap(reponse);
  }

  /// `AAAA-MM-JJ` — les bornes de période sont interprétées en UTC par le
  /// serveur (même convention que le Module 8).
  static String _dateSeule(DateTime date) {
    final String mois = date.month.toString().padLeft(2, '0');
    final String jour = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mois-$jour';
  }
}
