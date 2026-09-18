// lib/services/vente_service.dart
//
// MODULE 8 — VALIDATION DE VENTE ET HISTORIQUE DU VENDEUR.
//
// La validation s'appuie sur la transaction serveur `rpc_vente_valider`
// (migration `20260916000009_module8_ventes.sql`) : lignes de vente, sortie de
// stock, encaissement en caisse, numéro unique et journal d'audit sont écrits
// dans UNE SEULE transaction Postgres. Si le stock a bougé entre le scan et
// l'encaissement, TOUTE la vente est refusée — jamais de vente à moitié.
//
// Règles appliquées côté application (et revérifiées côté serveur) :
//   • le VENDEUR ne transmet AUCUN prix : le serveur relit ceux de la base ;
//   • un abonnement échu (Module 3) bloque l'encaissement ;
//   • le panier se vide uniquement après confirmation du serveur.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/ligne_panier.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/notification_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/sync_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature d'une erreur de validation (pour adapter l'interface).
enum TypeErreurVente {
  panierVide,
  stock,
  droits,
  abonnement,
  validation,
  dette,
  reseau,
  inconnu,
}

/// Erreur métier de la validation de vente (message déjà en français).
class VenteServiceException implements Exception {
  const VenteServiceException(
    this.message, {
    this.type = TypeErreurVente.inconnu,
  });

  final String message;
  final TypeErreurVente type;

  @override
  String toString() => message;
}

/// Validation des ventes et lecture de l'historique.
///
/// Singleton : `VenteService.instance`.
class VenteService {
  VenteService._();

  static final VenteService instance = VenteService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Modes de paiement proposés à l'encaissement (codes stockés en base).
  static const Map<String, String> modesPaiement = <String, String>{
    'especes': 'Espèces',
    'mobile_money': 'Mobile Money',
    'carte': 'Carte',
    'virement': 'Virement',
    'autre': 'Autre',
  };

  /// Libellé affichable d'un code de paiement.
  static String libelleMode(String code) => modesPaiement[code] ?? code;

  // ---------------------------------------------------------------------------
  // CALCULS PURS (testables sans réseau)
  // ---------------------------------------------------------------------------

  /// Rendu (monnaie) pour un montant reçu : jamais négatif.
  static double calculerRendu(double total, double? montantRecu) {
    if (montantRecu == null) return 0;
    final double rendu = montantRecu - total;
    return rendu > 0 ? rendu : 0;
  }

  /// Le montant reçu couvre-t-il le total ? (`true` si non renseigné :
  /// le contrôle ne s'applique qu'aux paiements en espèces.)
  static bool montantSuffisant(double total, double? montantRecu) {
    if (montantRecu == null) return true;
    return montantRecu + 0.0001 >= total;
  }

  /// Extrait le message utilisateur d'une erreur du serveur.
  ///
  /// La fonction SQL préfixe ses messages d'un code (`STOCK_INSUFFISANT|…`) :
  /// l'application n'affiche que la partie française.
  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  static TypeErreurVente _typeDepuisMessage(String brut) {
    final String code = brut.trim().split('|').first.trim().toUpperCase();
    switch (code) {
      case 'STOCK_INSUFFISANT':
      case 'PRODUIT_INTROUVABLE':
      case 'CONDITIONNEMENT_INVALIDE':
        return TypeErreurVente.stock;
      case 'DROIT_REFUSE':
      case 'SESSION_ABSENTE':
      case 'HORS_BOUTIQUE':
        return TypeErreurVente.droits;
      case 'PANIER_VIDE':
      case 'LIGNE_INVALIDE':
        return TypeErreurVente.panierVide;
      case 'MONTANT_INSUFFISANT':
        return TypeErreurVente.inconnu;
      // 🔐 MODULE 12 — annulation de vente.
      case 'RAISON_OBLIGATOIRE':
      case 'VENTE_INVALIDE':
      case 'VENTE_INTROUVABLE':
        return TypeErreurVente.validation;
      case 'DETTE_LIEE':
        return TypeErreurVente.dette;
      case 'ABONNEMENT_BLOQUE':
      case 'ABONNEMENT_EXPIRE':
        return TypeErreurVente.abonnement;
      default:
        return TypeErreurVente.inconnu;
    }
  }

  // ---------------------------------------------------------------------------
  // VALIDATION DE LA VENTE (TRANSACTION SERVEUR)
  // ---------------------------------------------------------------------------

  /// Valide le panier partagé : lignes + stock + encaissement + numéro +
  /// journal, en une seule transaction.
  ///
  /// Renvoie le récapitulatif officiel (numéro de vente, total, lignes), et
  /// vide le panier une fois la vente confirmée par le serveur.
  Future<VenteEnregistree> validerVente({
    required String modePaiement,
    double? montantRecu,
    String? numeroTransaction,
    int? clientId,
  }) async {
    final PanierService panier = PanierService.instance;

    if (panier.estVide) {
      throw const VenteServiceException(
        'Le panier est vide : ajoutez au moins un article.',
        type: TypeErreurVente.panierVide,
      );
    }
    if (AbonnementService.instance.lectureSeule) {
      throw const VenteServiceException(
        'L\'abonnement de votre entreprise est échu : les ventes sont '
        'bloquées jusqu\'au renouvellement.',
        type: TypeErreurVente.abonnement,
      );
    }
    if (!PermissionService.instance.peut(PageAccess.caisse, ActionAccess.creer)) {
      throw const VenteServiceException(
        'Votre rôle ne permet pas d\'encaisser une vente.',
        type: TypeErreurVente.droits,
      );
    }

    // Copie des lignes AVANT l'appel : le panier sera vidé après succès.
    final List<LignePanier> lignesPanier = panier.lignes;

    final List<Map<String, dynamic>> lignesPayload =
        lignesPanier.map((LignePanier ligne) {
      return <String, dynamic>{
        'produit_id': ligne.produitId,
        // Unités de BASE retirées du stock (3 fardes de 12 → 36).
        'quantite': ligne.unitesBase,
        // Unités VENDUES (3 fardes) — pour le reçu et le retour du serveur.
        'quantite_vendue': ligne.quantite,
        'conditionnement_id': ligne.conditionnementId,
        // Aucun prix n'est transmis : le serveur relit celui de la base.
      };
    }).toList(growable: false);

    final String? transaction =
        (numeroTransaction ?? '').trim().isEmpty ? null : numeroTransaction!.trim();

    dynamic reponse;
    try {
      reponse = await _client.rpc(
        'rpc_vente_valider',
        params: <String, dynamic>{
          'p_lignes': lignesPayload,
          'p_mode_paiement': modePaiement,
          'p_montant_recu': montantRecu,
          'p_numero_transaction': transaction,
          'p_client_id': clientId,
        },
      );
    } on PostgrestException catch (e) {
      throw VenteServiceException(
        messageErreur(e.message),
        type: _typeDepuisMessage(e.message),
      );
    } catch (e) {
      debugPrint('VenteService.validerVente : $e');
      throw const VenteServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurVente.reseau,
      );
    }

    final Map<String, dynamic>? map = reponseRpcEnMap(reponse);
    if (map == null) {
      throw const VenteServiceException(
        'Réponse inattendue du serveur : la vente n\'est pas confirmée. '
        'Vérifiez l\'historique avant de recommencer.',
      );
    }

    final VenteEnregistree vente = VenteEnregistree.fromRpc(map);

    // Vente confirmée : on aligne la copie locale du stock (best effort —
    // un échec local ne remet pas en cause la vente), puis on vide le panier.
    await _appliquerSortieStockLocale(lignesPanier);
    panier.vider();
    unawaited(_resynchroniser());

    // 🔔 NOTIFICATIONS — « chaque vente » (best-effort : un échec de
    // notification ne remet jamais en cause la vente confirmée).
    unawaited(NotificationService.instance.notifierVente(
      numero: vente.numeroVente,
      total: vente.total,
      nbArticles: vente.lignes.length,
      modePaiement: vente.modePaiement,
    ));

    return vente;
  }

  /// Décrémente le stock de la copie locale (SQLite) pour que la caisse
  /// classique affiche le bon stock sans attendre la prochaine synchronisation.
  Future<void> _appliquerSortieStockLocale(List<LignePanier> lignes) async {
    try {
      for (final LignePanier ligne in lignes) {
        await DBHelper.instance.appliquerSortieStockParSupabaseId(
          ligne.produitId.toString(),
          ligne.unitesBase,
        );
      }
    } catch (e) {
      debugPrint('VenteService : stock local non mis à jour ($e)');
    }
  }

  Future<void> _resynchroniser() async {
    try {
      await SyncService.instance.syncAll();
    } catch (e) {
      debugPrint('VenteService : synchronisation post-vente ignorée ($e)');
    }
  }

  // ---------------------------------------------------------------------------
  // ANNULATION DE VENTE (MODULE 12 — ACTION CRITIQUE)
  // ---------------------------------------------------------------------------

  /// Annule une vente enregistrée — réservé au PROPRIÉTAIRE (ou Super Admin
  /// autorisé par la finance) :
  ///   • TRACE CRITIQUE (`ANNULATION_VENTE`) écrite AVANT la modification ;
  ///   • encaissement retiré de la caisse, stock restitué par un ajustement,
  ///     lignes de vente supprimées — dans UNE transaction serveur ;
  ///   • refusée si une dette client non soldée est liée à la vente.
  ///
  /// [venteUuid] OU [venteId] — jamais les deux. [raison] obligatoire (3 car.).
  Future<void> annulerVente({
    String? venteUuid,
    int? venteId,
    required String raison,
  }) async {
    if (AbonnementService.instance.lectureSeule) {
      throw const VenteServiceException(
        'L\'abonnement de votre entreprise est échu : l\'annulation est '
        'bloquée jusqu\'au renouvellement.',
        type: TypeErreurVente.abonnement,
      );
    }

    final RoleUtilisateur role = PermissionService.instance.roleCourant;
    if (role != RoleUtilisateur.proprietaire &&
        role != RoleUtilisateur.superAdmin) {
      throw const VenteServiceException(
        'Seul le propriétaire peut annuler une vente.',
        type: TypeErreurVente.droits,
      );
    }

    if ((venteUuid == null) == (venteId == null)) {
      throw const VenteServiceException(
        'Précisez la vente à annuler (uuid OU identifiant de ligne).',
        type: TypeErreurVente.validation,
      );
    }

    final String motif = raison.trim();
    if (motif.length < 3) {
      throw const VenteServiceException(
        'Indiquez la raison de l\'annulation (3 caractères minimum).',
        type: TypeErreurVente.validation,
      );
    }

    try {
      await _client.rpc(
        'rpc_vente_annuler',
        params: <String, dynamic>{
          if (venteUuid != null) 'p_vente_uuid': venteUuid,
          if (venteId != null) 'p_vente_id': venteId,
          'p_raison': motif,
        },
      );
    } on PostgrestException catch (e) {
      throw VenteServiceException(
        messageErreur(e.message),
        type: _typeDepuisMessage(e.message),
      );
    } catch (e) {
      debugPrint('VenteService.annulerVente : $e');
      throw const VenteServiceException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurVente.reseau,
      );
    }

    // Le stock serveur a bougé (restitution) : on rafraîchit la copie locale
    // en arrière-plan, sans bloquer l'utilisateur.
    unawaited(_resynchroniser());
  }

  // ---------------------------------------------------------------------------
  // HISTORIQUE DU VENDEUR
  // ---------------------------------------------------------------------------

  /// Ventes d'un vendeur pour un jour donné, regroupées par vente.
  ///
  /// [modePaiement] filtre sur un code (`especes`, `mobile_money`…) ;
  /// [sellerId] permet au patron de consulter les ventes d'un collaborateur.
  Future<List<VenteHistorique>> historiqueVendeur({
    required DateTime jour,
    String? modePaiement,
    String? sellerId,
  }) {
    return _executer(
      () async {
        final String? uid = _client.auth.currentUser?.id;
        final String vendeur = sellerId ?? uid ?? '';
        if (vendeur.isEmpty) {
          throw const VenteServiceException(
            'Session introuvable : reconnectez-vous pour consulter vos ventes.',
            type: TypeErreurVente.droits,
          );
        }

        // ⚠️ `ventes.date` est un `timestamptz` : les bornes du jour sont
        // envoyées en UTC pour un filtrage exact (l'affichage repasse ensuite
        // en heure locale).
        final DateTime debut = DateTime(jour.year, jour.month, jour.day);
        final DateTime fin = debut.add(const Duration(days: 1));
        final String debutIso = debut.toUtc().toIso8601String();
        final String finIso = fin.toUtc().toIso8601String();

        dynamic requete = _client
            .from('ventes')
            .select(
              'id, produit_id, quantite, prix, mode_paiement, date, '
              'vente_uuid, numero_vente, conditionnement_id',
            )
            .eq('seller_id', vendeur)
            .gte('date', debutIso)
            .lt('date', finIso);

        if (modePaiement != null && modePaiement.isNotEmpty) {
          requete = requete.eq('mode_paiement', modePaiement);
        }

        final dynamic reponse = await requete.order('date', ascending: false);
        final List<Map<String, dynamic>> lignes = parseMapList(reponse);
        if (lignes.isEmpty) return const <VenteHistorique>[];

        final Map<int, Map<String, dynamic>> produits =
            await _chargerProduits(lignes);
        final Map<String, Map<String, dynamic>> conditionnements =
            await _chargerConditionnements(lignes);

        // Regroupement des lignes : une vente = un `vente_uuid`.
        // Les ventes historiques (sans vente_uuid, avant le Module 8) sont
        // considérées comme des ventes d'une ligne.
        final Map<String, List<Map<String, dynamic>>> groupes =
            <String, List<Map<String, dynamic>>>{};
        for (final Map<String, dynamic> ligne in lignes) {
          final String cle = parseStringOrNull(ligne['vente_uuid']) ??
              'ligne:${parseInt(ligne['id'])}';
          groupes.putIfAbsent(cle, () => <Map<String, dynamic>>[]).add(ligne);
        }

        final List<VenteHistorique> ventes = <VenteHistorique>[];
        groupes.forEach((String cle, List<Map<String, dynamic>> lignesVente) {
          double total = 0;
          final List<LigneVenteHistorique> details = <LigneVenteHistorique>[];

          for (final Map<String, dynamic> ligne in lignesVente) {
            final int produitId = parseInt(ligne['produit_id']);
            final Map<String, dynamic>? produit = produits[produitId];
            final String? condId =
                parseStringOrNull(ligne['conditionnement_id']);
            final Map<String, dynamic>? cond =
                condId == null ? null : conditionnements[condId];
            final double prix = parseDouble(ligne['prix']);
            total += prix;

            details.add(
              LigneVenteHistorique(
                id: parseInt(ligne['id']),
                produitId: produitId,
                nom: parseString(produit?['nom'],
                    fallback: 'Article #$produitId'),
                uniteBase:
                    parseString(produit?['unite_mesure'], fallback: 'unité'),
                conditionnementId: condId,
                conditionnementLibelle: parseStringOrNull(cond?['libelle']),
                conditionnementUnitesBase:
                    parseDoubleOrNull(cond?['quantite_unites_base']),
                quantiteBase: parseDouble(ligne['quantite']),
                total: prix,
              ),
            );
          }

          ventes.add(
            VenteHistorique(
              cle: cle,
              numeroVente: parseStringOrNull(lignesVente.first['numero_vente']),
              date: parseDateTimeOrNull(lignesVente.first['date']),
              modePaiement: parseString(
                lignesVente.first['mode_paiement'],
                fallback: 'especes',
              ),
              total: total,
              lignes: details,
            ),
          );
        });

        ventes.sort((VenteHistorique a, VenteHistorique b) {
          final DateTime da = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
          final DateTime db = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
        return ventes;
      },
      actionLibelle: 'le chargement de l\'historique',
      messageEchec:
          'Impossible de charger l\'historique des ventes. Vérifiez votre connexion internet.',
    );
  }

  Future<Map<int, Map<String, dynamic>>> _chargerProduits(
    List<Map<String, dynamic>> lignes,
  ) async {
    final Set<int> ids = <int>{};
    for (final Map<String, dynamic> ligne in lignes) {
      final int id = parseInt(ligne['produit_id']);
      if (id > 0) ids.add(id);
    }
    if (ids.isEmpty) return <int, Map<String, dynamic>>{};

    final dynamic reponse = await _client
        .from('produits')
        .select('id, nom, unite_mesure')
        .inFilter('id', ids.toList(growable: false));

    final Map<int, Map<String, dynamic>> resultat =
        <int, Map<String, dynamic>>{};
    for (final Map<String, dynamic> produit in parseMapList(reponse)) {
      resultat[parseInt(produit['id'])] = produit;
    }
    return resultat;
  }

  Future<Map<String, Map<String, dynamic>>> _chargerConditionnements(
    List<Map<String, dynamic>> lignes,
  ) async {
    final Set<String> ids = <String>{};
    for (final Map<String, dynamic> ligne in lignes) {
      final String? id = parseStringOrNull(ligne['conditionnement_id']);
      if (id != null) ids.add(id);
    }
    if (ids.isEmpty) return <String, Map<String, dynamic>>{};

    final dynamic reponse = await _client
        .from('conditionnements')
        .select('id, libelle, quantite_unites_base')
        .inFilter('id', ids.toList(growable: false));

    final Map<String, Map<String, dynamic>> resultat =
        <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> cond in parseMapList(reponse)) {
      resultat[parseString(cond['id'])] = cond;
    }
    return resultat;
  }

  /// Exécute une action en convertissant les erreurs techniques en
  /// [VenteServiceException] (même politique que les autres modules).
  Future<T> _executer<T>(
    Future<T> Function() action, {
    required String actionLibelle,
    required String messageEchec,
  }) async {
    try {
      return await action();
    } on VenteServiceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('VenteService ($actionLibelle) : ${e.message}');
      throw VenteServiceException(messageErreur(e.message));
    } catch (e) {
      debugPrint('VenteService ($actionLibelle) : $e');
      throw VenteServiceException(messageEchec, type: TypeErreurVente.reseau);
    }
  }
}
