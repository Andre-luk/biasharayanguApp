// lib/services/reinitialisation_session.dart
//
// 🧹 CORRECTIF 178 — UNE SEULE DÉCONNEXION, UN SEUL NETTOYAGE.
//
// POURQUOI CE FICHIER
// -------------------
// La déconnexion était recopiée dans SIX écrans, chacun oubliant une partie
// de l'état. Conséquences constatées sur le terrain :
//   • un SUPER ADMIN arrivait sur la coquille entreprise (tableau de bord,
//     rapports, paramètres) parce que `PermissionService` gardait le rôle
//     précédent ;
//   • une BOUTIQUE affichait les trois menus du pressing parce que
//     `ModulesService` et `EspaceService` gardaient l'espace précédent ;
//   • le panier, la devise, l'abonnement et le cache de lecture survivaient
//     au changement de compte.
//
// Chaque oubli produisait un mélange d'interfaces entre deux comptes
// successifs sur le même appareil. Ce service est désormais le SEUL endroit
// qui ferme une session : tout écran de déconnexion l'appelle.
//
// ⚠️ Ordre imposé :
//   1. tracer la déconnexion (avant de perdre le jeton) ;
//   2. fermer Supabase Auth ;
//   3. vider les états MÉTIER (permissions, modules, espace, devise…) ;
//   4. vider la session locale (SharedPreferences) ;
//   5. vider les caches persistés (SQLite) — best-effort.

import 'package:flutter/foundation.dart';

import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/audit_service.dart';
import 'package:biashara_yangu/services/cache_lecture.dart';
import 'package:biashara_yangu/services/contexte_distribution.dart';
import 'package:biashara_yangu/services/devise_service.dart';
import 'package:biashara_yangu/services/espace_service.dart';
import 'package:biashara_yangu/services/etablissement_service.dart';
import 'package:biashara_yangu/services/marketplace_service.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/peremption_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/scanner_service.dart';
import 'package:biashara_yangu/services/scope_donnees.dart';
// 📅 CORRECTIF 179 — date de référence serveur (Lubumbashi).
import 'package:biashara_yangu/services/date_locale_service.dart';import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/type_activite_service.dart';
import 'package:biashara_yangu/services/ventes_commerciales_service.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

/// Fermeture de session unique de l'application.
class ReinitialisationSession {
  ReinitialisationSession._();

  /// Ferme la session du compte courant et remet l'application à zéro.
  ///
  /// [email] : adresse utilisée pour la trace d'audit quand elle est connue
  /// (écran de connexion). [tracerAudit] : `false` pour un nettoyage technique
  /// sans déconnexion réelle (tests).
  static Future<void> tout({
    String? email,
    bool tracerAudit = true,
  }) async {
    // 0. Identifiant du compte SORTANT, capturé avant la fermeture : il sert
    //    à purger le cache d'espace cloisonné par compte (correctif 178).
    String? uidSortant;
    try {
      uidSortant = await SessionManager.getUserId();
    } catch (e) {
      debugPrint('ReinitialisationSession : userId (ignoré) $e');
    }

    // 1. Trace AVANT de fermer le jeton (best-effort, jamais bloquant).
    if (tracerAudit) {
      try {
        await AuditService.instance.deconnexion(email: email);
      } catch (e) {
        debugPrint('ReinitialisationSession : audit (ignoré) $e');
      }
    }

    // 2. Fermeture de Supabase Auth (le jeton ne doit plus être utilisable).
    try {
      await SupabaseService.instance.signOut();
    } catch (e) {
      debugPrint('ReinitialisationSession : signOut (ignoré) $e');
    }

    // 3. États métier en mémoire. L'ORDRE compte : les modules se vident
    //    quand l'espace disparaît, donc on vide l'espace d'abord.
    _viderEtatsMetier(userId: uidSortant);

    // 4. Session locale (c'est elle qui « reconnectait » l'ancien compte).
    try {
      await SessionManager.clearSession();
    } catch (e) {
      debugPrint('ReinitialisationSession : session locale (ignoré) $e');
    }

    // 5. Caches persistés : le compte suivant ne doit jamais revoir les
    //    chiffres du précédent (best-effort : base absente sur le web).
    try {
      await CacheLecture.instance.vider();
    } catch (e) {
      debugPrint('ReinitialisationSession : cache de lecture (ignoré) $e');
    }
  }

  /// Vide tout l'état métier en mémoire, sans toucher au réseau ni au disque.
  ///
  /// Exposé séparément pour les tests et pour la connexion : avant de charger
  /// un nouveau compte, on repart d'un état vierge.
  static void viderEtats() => _viderEtatsMetier();

  static void _viderEtatsMetier({String? userId}) {
    // 🔐 Rôle + matrice de permissions (cause du Super Admin « en boutique »).
    PermissionService.instance.reinitialiser();

    // 🏢 Espaces/entreprises : plus aucune boutique active.
    EspaceService.instance.reinitialiser(userId: userId);
    ScopeDonnees.reinitialiser();

    // 🧩 Profil de modules (cause des « 3 menus pressing » sur une boutique).
    ModulesService.instance.reinitialiser();
    TypeActiviteService.instance.reinitialiser();

    // 💳 Abonnement, distribution, marketplace, réglages métier.
    AbonnementService.instance.reinitialiserAcces();
    ContexteDistribution.instance.reinitialiser();
    MarketplaceService.instance.reinitialiserContexte();
    DeviseService.instance.reinitialiser();
    PeremptionService.instance.reinitialiser();
    EtablissementService.instance.reinitialiser();

    // 🛒 Session de vente : panier, scans, droits de négociation.
    PanierService.instance.vider();
    ScannerService.instance.viderHistorique();
    VentesCommercialesService.instance.reinitialiser();
    // 📅 Date de référence serveur : redemandée pour le prochain compte.
    DateLocaleService.instance.reinitialiser();  }
}
