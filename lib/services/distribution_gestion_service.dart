// lib/services/distribution_gestion_service.dart
//
// 🚚 MODULE 24 — SERVICE DE GESTION DE LA DISTRIBUTION.
//
// Toutes les écritures passent par les RPC `dist_*` (les tables n'ont AUCUNE
// policy d'écriture). Le service ne lève que
// [DistributionGestionException], dont le message est toujours en français.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du module Distribution (gestion).
class DistributionGestionException implements Exception {
  const DistributionGestionException(this.message, {this.code = ''});

  final String message;
  final String code;

  @override
  String toString() => message;
}

/// Accès Supabase au module Distribution complet.
class DistributionGestionService {
  DistributionGestionService._();

  static final DistributionGestionService instance =
      DistributionGestionService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // OUTILS
  // ---------------------------------------------------------------------------

  /// Traduit un message serveur « CODE|texte » en message lisible.
  static String messageErreur(String? brut) {
    final String texte = (brut ?? '').trim();
    if (texte.isEmpty) {
      return 'Opération impossible : réessayez dans quelques instants.';
    }

    final int separateur = texte.indexOf('|');
    final String message =
        separateur >= 0 ? texte.substring(separateur + 1).trim() : texte;

    const Map<String, String> complements = <String, String>{
      'PGRST202':
          'Le module Distribution n\'est pas installé sur le serveur. '
              'Exécutez la migration 20260916000100_module24_distribution_gestion.sql.',
      'SESSION_ABSENTE': 'Session expirée : reconnectez-vous.',
      'DROIT_REFUSE': 'Votre rôle ne permet pas cette opération.',
      'LOGIQUE':
          'Le serveur a refusé une incohérence : vérifiez les quantités.',
      'INTRANT_INCONNU': 'Cet intrant n\'existe pas.',
      'PRODUIT_INCONNU': 'Ce produit fini n\'existe pas.',
      'INTRANT_NON_RECU': 'Cet intrant ne figure pas dans la demande reçue.',
      'STOCK_INSUFFISANT': 'Stock insuffisant pour cette opération.',
      'STOCK_COMMERCIAL_INSUFFISANT':
          'Le commercial ne détient pas assez de ce produit.',
      'LIGNES_VIDES': 'Ajoutez au moins une ligne.',
      'SORTIES_VIDES': 'Déclarez au moins un produit fabriqué.',
      'INTRANTS_VIDES': 'Déclarez les intrants utilisés.',
      'QUANTITE_INVALIDE': 'Quantité invalide.',
      'NOM_REQUIS': 'Indiquez un nom.',
      'MOTIF_REQUIS': 'Un motif est obligatoire pour cette opération.',
      'ECART_SANS_MOTIF':
          'Les quantités ne correspondent pas : indiquez un motif.',
      'PERTE_SANS_MOTIF': 'Expliquez la perte constatée.',
      'MONTANT_INVALIDE': 'Montant invalide.',
      'MONTANT_SUPERIEUR': 'Le montant dépasse ce que vous détenez.',
      'SOLDE_INSUFFISANT': 'Le solde de la caisse est insuffisant.',
      'SOLDE_INITIAL_VERROUILLE':
          'La caisse a déjà des mouvements : utilisez un apport pour '
              'ajouter de l\'argent.',
      'DOUBLON_CLIENT': 'Ce client existe déjà dans votre liste.',
      'DOUBLON_ENTREPRISE':
          'Un client avec ce numéro existe déjà dans l\'entreprise. '
              'Contactez le gérant.',
      'CLIENT_INTROUVABLE': 'Ce client n\'existe pas ou ne vous appartient pas.',
      'DEMANDE_INTROUVABLE': 'Cette demande n\'existe pas.',
      'RECEPTION_INTROUVABLE': 'Cette réception n\'existe pas.',
      'PRODUCTION_INTROUVABLE': 'Cette production n\'existe pas.',
      'RETOUR_INTROUVABLE': 'Ce retour n\'existe pas.',
      'REMISE_INTROUVABLE': 'Cette remise n\'existe pas.',
      'DEPENSE_INTROUVABLE': 'Cette dépense n\'existe pas.',
      'ANOMALIE_INTROUVABLE': 'Cette anomalie n\'existe pas.',
      'VENTE_INTROUVABLE': 'Cette vente n\'existe pas.',
      'STATUT_INVALIDE':
          'Cette opération n\'est plus dans un état modifiable.',
      'ROLE_INVALIDE': 'Rôle distribution inconnu.',
      'EMAIL_INVALIDE': 'Adresse e-mail invalide.',
      'MOT_DE_PASSE_TROP_COURT':
          'Le mot de passe doit comporter au moins 8 caractères.',
      'COMPTE_EXISTANT':
          'Cette adresse appartient déjà à un collaborateur d\'une autre entreprise.',
      'COLLABORATEUR_INTROUVABLE': 'Ce collaborateur n\'existe pas.',
      'COMMERCIAL_INVALIDE': 'Choisissez un commercial de votre entreprise.',
      'DECISION_REQUISE': 'Indiquez la décision prise.',
      'RECEPTION_DEJA_TRAITEE': 'Cette réception a déjà été traitée.',
    };

    for (final MapEntry<String, String> e in complements.entries) {
      if (texte.contains(e.key)) return e.value;
    }

    return message.isEmpty ? 'Opération impossible.' : message;
  }

  Future<dynamic> _rpcAppel(String nom, [Map<String, dynamic>? params]) async {
    try {
      return await _client.rpc(nom, params: params ?? const <String, dynamic>{});
    } on PostgrestException catch (e) {
      final String codeBrut = (e.message.split('|').first).trim().toUpperCase();
      final bool nonDeploye = (e.code ?? '').toUpperCase() == 'PGRST202' ||
          codeBrut == 'PGRST202' ||
          e.message.contains('Could not find the function');
      throw DistributionGestionException(
        nonDeploye ? messageErreur('PGRST202|') : messageErreur(e.message),
        code: nonDeploye ? 'NON_DEPLOYE' : codeBrut,
      );
    } catch (e) {
      debugPrint('DistributionGestionService.$nom : $e');
      throw const DistributionGestionException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        code: 'RESEAU',
      );
    }
  }

  Future<Map<String, dynamic>?> _rpcMap(String nom,
      [Map<String, dynamic>? params]) async {
    return parseMap(await _rpcAppel(nom, params));
  }

  Future<List<Map<String, dynamic>>> _items(String nom,
      [Map<String, dynamic>? params]) async {
    final Map<String, dynamic>? json = await _rpcMap(nom, params);
    return parseMapList(json?['items']);
  }

  // ---------------------------------------------------------------------------
  // TABLEAU DE BORD
  // ---------------------------------------------------------------------------

  Future<TableauBordDistribution> tableauBord() async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_tableau_bord');
    if (json == null) {
      throw const DistributionGestionException(
        'Le serveur n\'a pas renvoyé le tableau de bord Distribution.',
      );
    }
    return TableauBordDistribution.depuisJson(json);
  }

  Future<List<OperationAttente>> validations() async {
    final dynamic brut = await _rpcAppel('dist_validations');
    return parseMapList(brut).map(OperationAttente.depuisJson).toList();
  }

  Future<RoleDistribution> role() async {
    final Map<String, dynamic>? json = await _rpcMap('dist_tableau_bord');
    return RoleDistribution.depuisCode(parseString(json?['role']));
  }

  // ---------------------------------------------------------------------------
  // STOCK
  // ---------------------------------------------------------------------------

  Future<StockDistribution> stock() async {
    final Map<String, dynamic>? json = await _rpcMap('dist_stock_resume');
    if (json == null) return const StockDistribution();
    return StockDistribution.depuisJson(json);
  }

  Future<List<Map<String, dynamic>>> mouvements({
    String? intrantId,
    String? produitId,
    int limit = 150,
  }) async {
    return _items('dist_mouvements_lister', <String, dynamic>{
      'p_intrant_id': intrantId,
      'p_produit_id': produitId,
      'p_limit': limit,
    });
  }

  Future<Map<String, dynamic>> enregistrerIntrant({
    String? id,
    required String nom,
    String unite = 'unité',
    double seuil = 0,
    double prix = 0,
    bool actif = true,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_intrant_enregistrer', <String, dynamic>{
      'p_id': id,
      'p_nom': nom,
      'p_unite': unite,
      'p_seuil': seuil,
      'p_prix': prix,
      'p_actif': actif,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> enregistrerProduit({
    String? id,
    required String nom,
    String format = 'farde',
    String unite = 'unité',
    double prixVente = 0,
    double prixAchat = 0,
    bool actif = true,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_produit_enregistrer', <String, dynamic>{
      'p_id': id,
      'p_nom': nom,
      'p_format': format,
      'p_unite': unite,
      'p_prix_vente': prixVente,
      'p_prix_achat': prixAchat,
      'p_actif': actif,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<void> ajusterStock({
    String? intrantId,
    String? produitId,
    required double nouvelleQuantite,
    required String motif,
  }) async {
    await _rpcAppel('dist_stock_ajuster', <String, dynamic>{
      'p_intrant_id': intrantId,
      'p_produit_id': produitId,
      'p_nouvelle_quantite': nouvelleQuantite,
      'p_motif': motif,
    });
  }

  // ---------------------------------------------------------------------------
  // RÉCEPTIONS D'INTRANTS
  // ---------------------------------------------------------------------------

  Future<List<ReceptionIntrants>> receptions({String? statut}) async {
    final List<Map<String, dynamic>> items = await _items(
      'dist_receptions_lister',
      <String, dynamic>{'p_statut': statut},
    );
    return items.map(ReceptionIntrants.depuisJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> enregistrerReception({
    required List<Map<String, dynamic>> lignes,
    String? fournisseur,
    String? note,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_reception_intrants_enregistrer', <String, dynamic>{
      'p_lignes': lignes,
      'p_fournisseur': fournisseur,
      'p_note': note,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> confirmerReception(
    String receptionId, {
    List<Map<String, dynamic>>? lignes,
    String? motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_reception_intrants_confirmer', <String, dynamic>{
      'p_reception': receptionId,
      'p_lignes': lignes,
      'p_motif': motif,
    });
    return json ?? const <String, dynamic>{};
  }

  /// Refuse une réception en attente (gérant / propriétaire).
  ///
  /// Aucun stock n'est touché : la réception n'a jamais été validée.
  Future<void> refuserReception(String receptionId, String motif) async {
    if (motif.trim().length < 3) {
      throw const DistributionGestionException(
        'Indiquez pourquoi cette réception est refusée (3 caractères minimum).',
        code: 'MOTIF_REQUIS',
      );
    }
    await _rpcAppel('dist_reception_intrants_refuser', <String, dynamic>{
      'p_reception': receptionId,
      'p_motif': motif.trim(),
    });
  }

  // ---------------------------------------------------------------------------
  // DEMANDES D'INTRANTS
  // ---------------------------------------------------------------------------

  Future<List<DemandeIntrant>> demandesIntrants() async {
    final List<Map<String, dynamic>> items =
        await _items('dist_demandes_intrants_lister');
    return items.map(DemandeIntrant.depuisJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> creerDemandeIntrants(
    List<Map<String, dynamic>> lignes, {
    String? note,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_demande_intrants_creer', <String, dynamic>{
      'p_lignes': lignes,
      'p_note': note,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> traiterDemandeIntrants(
    String id, {
    List<Map<String, dynamic>>? lignes,
    bool refuser = false,
    String? motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_demande_intrants_traiter', <String, dynamic>{
      'p_demande': id,
      'p_lignes': lignes,
      'p_refuser': refuser,
      'p_motif': motif,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> receptionnerDemandeIntrants(
    String id, {
    List<Map<String, dynamic>>? lignes,
    String? motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_demande_intrants_receptionner', <String, dynamic>{
      'p_demande': id,
      'p_lignes': lignes,
      'p_motif': motif,
    });
    return json ?? const <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // PRODUCTIONS
  // ---------------------------------------------------------------------------

  Future<List<ProductionDistribution>> productions() async {
    final List<Map<String, dynamic>> items =
        await _items('dist_productions_lister');
    return items.map(ProductionDistribution.depuisJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> enregistrerProduction({
    String? demandeId,
    required List<Map<String, dynamic>> intrants,
    required List<Map<String, dynamic>> sorties,
    String? motifPertes,
    String? note,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_production_enregistrer', <String, dynamic>{
      'p_demande_id': demandeId,
      'p_intrants': intrants,
      'p_sorties': sorties,
      'p_motif_pertes': motifPertes,
      'p_note': note,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> receptionnerProduction(
    String productionId, {
    List<Map<String, dynamic>>? lignes,
    String? motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_production_receptionner', <String, dynamic>{
      'p_production': productionId,
      'p_lignes': lignes,
      'p_motif': motif,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<void> reintegrerIntrants(
    String productionId, {
    required String intrantId,
    required double quantite,
    String? motif,
  }) async {
    await _rpcAppel('dist_production_reintegrer', <String, dynamic>{
      'p_production': productionId,
      'p_intrant': intrantId,
      'p_quantite': quantite,
      'p_motif': motif,
    });
  }

  // ---------------------------------------------------------------------------
  // DEMANDES COMMERCIALES
  // ---------------------------------------------------------------------------

  Future<List<DemandeCommercial>> demandesCommerciales() async {
    final List<Map<String, dynamic>> items =
        await _items('dist_demandes_commercial_lister');
    return items.map(DemandeCommercial.depuisJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> creerDemandeCommerciale(
    List<Map<String, dynamic>> lignes, {
    String? note,
    String? commercialId,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_demande_commercial_creer', <String, dynamic>{
      'p_lignes': lignes,
      'p_note': note,
      'p_commercial_id': commercialId,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> confirmerDemandeCommerciale(
    String id, {
    List<Map<String, dynamic>>? lignes,
    bool refuser = false,
    String? motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_demande_commercial_confirmer', <String, dynamic>{
      'p_demande': id,
      'p_lignes': lignes,
      'p_refuser': refuser,
      'p_motif': motif,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> autoriserDemandeCommerciale(
    String id, {
    List<Map<String, dynamic>>? lignes,
    bool refuser = false,
    String? motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_demande_commercial_autoriser', <String, dynamic>{
      'p_demande': id,
      'p_lignes': lignes,
      'p_refuser': refuser,
      'p_motif': motif,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> receptionnerDemandeCommerciale(
    String id, {
    List<Map<String, dynamic>>? lignes,
    String? motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_demande_commercial_receptionner', <String, dynamic>{
      'p_demande': id,
      'p_lignes': lignes,
      'p_motif': motif,
    });
    return json ?? const <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // CLIENTS ET VENTES
  // ---------------------------------------------------------------------------

  Future<List<ClientDistribution>> clients({String? commercialId}) async {
    final List<Map<String, dynamic>> items = await _items(
      'dist_clients_lister',
      <String, dynamic>{'p_commercial_id': commercialId},
    );
    return items.map(ClientDistribution.depuisJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> enregistrerClient({
    String? id,
    required String nom,
    String? telephone,
    String? adresse,
    String? zone,
    String? note,
    String? commercialId,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_client_enregistrer', <String, dynamic>{
      'p_id': id,
      'p_nom': nom,
      'p_telephone': telephone,
      'p_adresse': adresse,
      'p_zone': zone,
      'p_note': note,
      'p_commercial_id': commercialId,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<List<ProduitCommercial>> mesProduits() async {
    final List<Map<String, dynamic>> items =
        await _items('dist_mes_produits');
    return items.map(ProduitCommercial.depuisJson).toList(growable: false);
  }

  /// Catalogue des produits finis (pour demander une dotation).
  Future<List<ProduitCommercial>> catalogueProduits() async {
    final List<Map<String, dynamic>> items =
        await _items('dist_produits_catalogue');
    return items
        .map((Map<String, dynamic> m) => ProduitCommercial(
              produitId: parseString(m['id']),
              nom: parseString(m['nom']),
              unite: parseString(m['unite']),
              quantite: parseDouble(m['stock_central']),
              prixVente: parseDouble(m['prix_vente']),
            ))
        .toList(growable: false);
  }

  /// Ce que le commercial détient encore et doit remettre au comptable.
  Future<double> soldeARemettre() async {
    final Map<String, dynamic>? json = await _rpcMap('dist_remises_lister');
    return parseDouble(json?['solde_commercial']);
  }

  Future<List<VenteDistribution>> ventes({DateTime? debut, DateTime? fin}) async {
    final List<Map<String, dynamic>> items = await _items(
      'dist_ventes_lister',
      <String, dynamic>{
        'p_debut': debut == null ? null : _isoJour(debut),
        'p_fin': fin == null ? null : _isoJour(fin),
      },
    );
    return items.map(VenteDistribution.depuisJson).toList(growable: false);
  }

  Future<FactureDistribution> enregistrerVente({
    String? clientId,
    required List<Map<String, dynamic>> lignes,
    double? montantPaye,
    String mode = 'especes',
    String? note,
    TypeOperationTarif typeOperation = TypeOperationTarif.standard,
    String? referenceLocale,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_vente_enregistrer', <String, dynamic>{
      'p_client_id': clientId,
      'p_lignes': lignes,
      'p_montant_paye': montantPaye,
      'p_mode': mode,
      'p_note': note,
      // 🏷️ MODULE 24 §9 — le serveur applique la grille tarifaire.
      'p_type_operation': typeOperation.code,
      // ♻️ §12 — identifiant unique : une vente hors ligne n'est jamais doublée.
      'p_reference_locale': referenceLocale,
    });
    if (json == null) {
      throw const DistributionGestionException(
        'Le serveur n\'a pas confirmé la vente.',
      );
    }
    return FactureDistribution.depuisJson(json);
  }

  Future<FactureDistribution?> facture(String venteId) async {
    final Map<String, dynamic>? json = await _rpcMap(
      'dist_facture',
      <String, dynamic>{'p_vente': venteId},
    );
    if (json == null) return null;
    return FactureDistribution.depuisJson(json);
  }

  // ---------------------------------------------------------------------------
  // RETOURS
  // ---------------------------------------------------------------------------

  Future<List<RetourCommercial>> retours() async {
    final List<Map<String, dynamic>> items =
        await _items('dist_retours_lister');
    return items.map(RetourCommercial.depuisJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> declarerRetour(
    List<Map<String, dynamic>> lignes, {
    String? note,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_retour_declarer', <String, dynamic>{
      'p_lignes': lignes,
      'p_note': note,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> receptionnerRetour(
    String id, {
    List<Map<String, dynamic>>? lignes,
    String? motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_retour_receptionner', <String, dynamic>{
      'p_retour': id,
      'p_lignes': lignes,
      'p_motif': motif,
    });
    return json ?? const <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // REMISES D'ARGENT
  // ---------------------------------------------------------------------------

  Future<List<RemiseArgent>> remises() async {
    final List<Map<String, dynamic>> items =
        await _items('dist_remises_lister');
    return items.map(RemiseArgent.depuisJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> declarerRemise({
    required double montant,
    String mode = 'especes',
    String? note,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_remise_declarer', <String, dynamic>{
      'p_montant': montant,
      'p_mode': mode,
      'p_note': note,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> receptionnerRemise(
    String id, {
    required double montantRecu,
    String? motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_remise_receptionner', <String, dynamic>{
      'p_remise': id,
      'p_montant_recu': montantRecu,
      'p_motif': motif,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> validerRemise(
    String id, {
    double? montantValide,
    String? motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_remise_valider', <String, dynamic>{
      'p_remise': id,
      'p_montant_valide': montantValide,
      'p_motif': motif,
    });
    return json ?? const <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // CAISSE ET DÉPENSES
  // ---------------------------------------------------------------------------

  Future<ResumeCaisseDistribution> caisse() async {
    final Map<String, dynamic>? json = await _rpcMap('dist_caisse_resume');
    if (json == null) return const ResumeCaisseDistribution();
    return ResumeCaisseDistribution.depuisJson(json);
  }

  Future<double> apportCaisse({
    required double montant,
    required String motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_caisse_apport', <String, dynamic>{
      'p_montant': montant,
      'p_motif': motif,
    });
    return parseDouble(json?['solde']);
  }

  Future<List<DepenseDistribution>> depenses() async {
    final List<Map<String, dynamic>> items =
        await _items('dist_depenses_lister');
    return items.map(DepenseDistribution.depuisJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> creerDepense({
    required String categorie,
    required double montant,
    required String motif,
    DateTime? date,
    String? justificatif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_depense_creer', <String, dynamic>{
      'p_categorie': categorie,
      'p_montant': montant,
      'p_motif': motif,
      'p_date': date == null ? null : _isoJour(date),
      'p_justificatif': justificatif,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> validerDepense(
    String id, {
    required bool accepter,
    String? motif,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_depense_valider', <String, dynamic>{
      'p_depense': id,
      'p_accepter': accepter,
      'p_motif': motif,
    });
    return json ?? const <String, dynamic>{};
  }

  // ---------------------------------------------------------------------------
  // ANOMALIES ET PARAMÈTRES
  // ---------------------------------------------------------------------------

  Future<List<AnomalieDistribution>> anomalies() async {
    final List<Map<String, dynamic>> items =
        await _items('dist_anomalies_lister');
    return items.map(AnomalieDistribution.depuisJson).toList(growable: false);
  }

  Future<void> resoudreAnomalie(
    String id, {
    required String decision,
    String? motif,
  }) async {
    await _rpcAppel('dist_anomalie_resoudre', <String, dynamic>{
      'p_anomalie': id,
      'p_decision': decision,
      'p_motif': motif,
    });
  }

  Future<void> definirParametres({
    String? devise,
    double? soldeInitial,
    bool? autoriserSoldeNegatif,
  }) async {
    await _rpcAppel('dist_parametres_definir', <String, dynamic>{
      'p_devise': devise,
      'p_solde_initial': soldeInitial,
      'p_autoriser_solde_negatif': autoriserSoldeNegatif,
    });
  }

  // ---------------------------------------------------------------------------
  // COLLABORATEURS
  // ---------------------------------------------------------------------------

  Future<List<CollaborateurDistribution>> collaborateurs() async {
    final List<Map<String, dynamic>> items =
        await _items('dist_collaborateurs_lister');
    return items
        .map(CollaborateurDistribution.depuisJson)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> creerCollaborateur({
    required String nom,
    String prenom = '',
    required String email,
    String telephone = '',
    required String motDePasse,
    required RoleDistribution role,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_collaborateur_creer', <String, dynamic>{
      'p_nom': nom,
      'p_prenom': prenom,
      'p_email': email,
      'p_telephone': telephone,
      'p_mot_de_passe': motDePasse,
      'p_role': role.code,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<void> majCollaborateur({
    required String id,
    required String nom,
    String prenom = '',
    String telephone = '',
    required RoleDistribution role,
    bool actif = true,
    String? motDePasse,
  }) async {
    await _rpcAppel('dist_collaborateur_maj', <String, dynamic>{
      'p_id': id,
      'p_nom': nom,
      'p_prenom': prenom,
      'p_telephone': telephone,
      'p_role': role.code,
      'p_actif': actif,
      'p_mot_de_passe': motDePasse,
    });
  }

  static String _isoJour(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // TARIFS (grille multi-tarifs des bidons)
  // ---------------------------------------------------------------------------

  Future<List<TarifBidon>> tarifs({String? produitId}) async {
    final List<Map<String, dynamic>> items = await _items(
      'dist_tarifs_lister',
      <String, dynamic>{'p_produit': produitId},
    );
    return items.map(TarifBidon.depuisJson).toList(growable: false);
  }

  Future<void> enregistrerTarif({
    required String produitId,
    required TypeOperationTarif type,
    required double prix,
    String? libelle,
    bool actif = true,
  }) async {
    if (prix < 0) {
      throw const DistributionGestionException(
        'Le prix ne peut pas être négatif.',
        code: 'MONTANT_INVALIDE',
      );
    }
    await _rpcAppel('dist_tarif_enregistrer', <String, dynamic>{
      'p_produit': produitId,
      'p_type_operation': type.code,
      'p_prix': prix,
      'p_libelle': libelle,
      'p_actif': actif,
    });
  }

  // ---------------------------------------------------------------------------
  // BONUS ET PRODUITS ENDOMMAGÉS
  // ---------------------------------------------------------------------------

  Future<List<BonusDommage>> bonus({
    String? commercialId,
    String? statut,
  }) async {
    final List<Map<String, dynamic>> items = await _items(
      'dist_bonus_lister',
      <String, dynamic>{
        'p_commercial': commercialId,
        'p_statut': statut,
      },
    );
    return items.map(BonusDommage.depuisJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> declarerBonus({
    required String produitId,
    required NatureBonus nature,
    required double quantite,
    required String motif,
    String? justificatif,
    String? commercialId,
    String? referenceLocale,
  }) async {
    if (quantite <= 0) {
      throw const DistributionGestionException(
        'La quantité doit être supérieure à zéro.',
        code: 'QUANTITE_INVALIDE',
      );
    }
    if (motif.trim().length < 3) {
      throw const DistributionGestionException(
        'Indiquez le motif (3 caractères minimum).',
        code: 'MOTIF_REQUIS',
      );
    }
    final Map<String, dynamic>? json =
        await _rpcMap('dist_bonus_declarer', <String, dynamic>{
      'p_produit': produitId,
      'p_nature': nature.code,
      'p_quantite': quantite,
      'p_motif': motif.trim(),
      'p_justificatif': justificatif,
      'p_commercial': commercialId,
      'p_reference_locale': referenceLocale,
    });
    return json ?? const <String, dynamic>{};
  }

  Future<void> validerBonus(
    String id, {
    bool valider = true,
    String? motif,
  }) async {
    await _rpcAppel('dist_bonus_valider', <String, dynamic>{
      'p_id': id,
      'p_valider': valider,
      'p_motif': motif,
    });
  }

  Future<List<ResumeBonusCommercial>> resumeBonus({
    DateTime? debut,
    DateTime? fin,
  }) async {
    final List<Map<String, dynamic>> items = await _items(
      'dist_bonus_resume',
      <String, dynamic>{'p_debut': debut?.toIso8601String(), 'p_fin': fin?.toIso8601String()},
    );
    return items.map(ResumeBonusCommercial.depuisJson).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // COÛT DE REVIENT ET MARGES
  // ---------------------------------------------------------------------------

  Future<List<CoutRevientProduit>> coutsRevient({String? produitId}) async {
    final List<Map<String, dynamic>> items = await _items(
      'dist_cout_revient',
      <String, dynamic>{'p_produit': produitId},
    );
    return items.map(CoutRevientProduit.depuisJson).toList(growable: false);
  }

  Future<RentabiliteDistribution> rentabilite({
    DateTime? debut,
    DateTime? fin,
  }) async {
    final Map<String, dynamic>? json =
        await _rpcMap('dist_rentabilite', <String, dynamic>{
      'p_debut': debut?.toIso8601String(),
      'p_fin': fin?.toIso8601String(),
    });
    return RentabiliteDistribution.depuisJson(json ?? const <String, dynamic>{});
  }

  // ---------------------------------------------------------------------------
  // TRAÇABILITÉ
  // ---------------------------------------------------------------------------
  /// Journal de traçabilité de la distribution (lecture seule).
  ///
  /// [action] filtre sur un code d'action (ex. `VENTE_ENREGISTREE`).
  Future<List<EntreeJournalDistribution>> journal({
    String? action,
    int limite = 150,
  }) async {
    final List<Map<String, dynamic>> items = await _items(
      'dist_journal_lister',
      <String, dynamic>{'p_action': action, 'p_limite': limite},
    );
    return items
        .map(EntreeJournalDistribution.depuisJson)
        .toList(growable: false);
  }
}
