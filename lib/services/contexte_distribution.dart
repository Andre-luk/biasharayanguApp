// lib/services/contexte_distribution.dart
//
// 🚚 MODULE 24 — SÉPARATION DES UNIVERS (boutique ↔ distribution).
//
// Problème résolu : un compte de distribution (gérant, production, stock,
// commercial, comptable) est rattaché, dans la matrice historique, à un rôle
// GLOBAL (VENDEUR, MAGASINIER, COMPTABLE_ENTREPRISE). Il voyait donc les
// cartes de la BOUTIQUE — Stock, Ventes, Caisse, Tournées — alors qu'il
// travaille dans le module Distribution, avec SON stock, SA caisse et SES
// écrans.
//
// Ce service répond à trois questions :
//   1. le compte appartient-il à une distribution ? (`estMembre`, lu dans
//      `utilisateurs.role_distribution`) ;
//   2. quel est son rôle fin ? (`role`, `estCollaborateur`) ;
//   3. quelles entrées doivent s'effacer devant le module 24 ?
//      (`masquerTournees`).
//
// ⚠️ Rien n'est « caché pour faire joli » : la sécurité reste côté serveur
//    (RPC `dist_*` + RLS). Ce service ne pilote que la NAVIGATION.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/type_activite_service.dart';

/// Contexte « distribution » du compte connecté.
class ContexteDistribution {
  ContexteDistribution._();

  static final ContexteDistribution instance = ContexteDistribution._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Notifié quand le contexte change (chargement terminé, déconnexion).
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  RoleDistribution _role = RoleDistribution.aucun;
  bool _charge = false;

  /// Rôle fin du compte dans la distribution (`aucun` si la colonne est vide).
  RoleDistribution get role => _role;

  /// Le serveur a-t-il répondu ?
  bool get charge => _charge;

  /// Compte rattaché à une distribution (patron inclus).
  bool get estMembre => _role != RoleDistribution.aucun;

  /// Collaborateur = membre qui n'est PAS le patron.
  bool get estCollaborateur =>
      estMembre && _role != RoleDistribution.proprietaire;

  /// Le module 24 complet est-il actif dans le profil de l'entreprise ?
  bool get moduleComplet =>
      ModulesService.instance.moduleActif(ModuleCode.distribution);

  /// Univers de travail : distribution ou boutique.
  ///
  /// Distribution si le compte a un rôle distribution, OU si l'entreprise est
  /// déclarée « distribution » **et** que le module 24 est actif (un patron de
  /// distribution sans le module garde les écrans du module 23 : aucune
  /// régression, aucun écran vide).
  bool get universDistribution => universDistributionPour(
        membre: estMembre,
        entrepriseDistribution: TypeActiviteService.instance.estDistribution,
        moduleComplet: moduleComplet,
      );

  /// Les cartes « Tournées » (module 23) s'effacent devant le module 24.
  bool get masquerTournees => masquerTourneesPour(
        membre: estMembre,
        entrepriseDistribution: TypeActiviteService.instance.estDistribution,
        moduleComplet: moduleComplet,
      );

  // ---------------------------------------------------------------------------
  // RÈGLES PURES (testables sans réseau)
  // ---------------------------------------------------------------------------

  static bool universDistributionPour({
    required bool membre,
    required bool entrepriseDistribution,
    required bool moduleComplet,
  }) {
    if (membre) return true;
    return entrepriseDistribution && moduleComplet;
  }

  static bool masquerTourneesPour({
    required bool membre,
    required bool entrepriseDistribution,
    required bool moduleComplet,
  }) {
    // Une distribution qui n'a PAS le module complet garde ses tournées.
    if (!moduleComplet) return false;
    return membre || entrepriseDistribution;
  }

  /// Chargement best-effort du rôle distribution du compte connecté.
  ///
  /// Ne lève jamais : hors ligne (ou migration 0100 non exécutée), le contexte
  /// reste `aucun` et l'application se comporte comme avant.
  Future<void> charger() async {
    try {
      final String? uid = _client.auth.currentUser?.id;
      if (uid == null) {
        _role = RoleDistribution.aucun;
        _charge = false;
        version.value++;
        return;
      }

      final dynamic reponse = await _client
          .from('utilisateurs')
          .select('role_distribution, dist_actif')
          .eq('id', uid)
          .maybeSingle();

      if (reponse is Map) {
        final Map<String, dynamic> ligne = Map<String, dynamic>.from(reponse);
        final bool actif = ligne['dist_actif'] != false;
        _role = actif
            ? RoleDistribution.depuisCode(ligne['role_distribution'] as String?)
            : RoleDistribution.aucun;
      } else {
        _role = RoleDistribution.aucun;
      }
      _charge = true;
    } catch (e) {
      // Colonne absente (migration non exécutée) ou hors ligne : on ne casse
      // rien, l'application retombe sur l'univers « boutique ».
      debugPrint('ContexteDistribution.charger : $e');
      _role = RoleDistribution.aucun;
      _charge = false;
    } finally {
      version.value++;
    }
  }

  /// Déconnexion / changement d'espace.
  void reinitialiser() {
    _role = RoleDistribution.aucun;
    _charge = false;
    version.value++;
  }
}
