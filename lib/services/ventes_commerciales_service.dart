// lib/services/ventes_commerciales_service.dart
//
// MODULE 25 — LA FLEXIBILITÉ COMMERCIALE CÔTÉ APPLICATION.
//
// Un seul endroit pour :
//   • lire les réglages du propriétaire (`boutique_parametres_vente_lire`) ;
//   • les enregistrer (`boutique_parametres_vente_enregistrer`) ;
//   • lire les rapports (`boutique_ventes_flexibilite_resume`) ;
//   • lire l'historique des négociations (`..._lister`).
//
// ⚠️ FAIL-CLOSED MAIS SILENCIEUX : si les réglages ne peuvent pas être lus
//    (hors ligne, réseau coupé), le service renvoie [ParametresVente.aucun] —
//    négociation, réduction et cadeaux sont donc MASQUÉS, jamais accordés par
//    erreur. Une vente normale reste parfaitement possible.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/parametres_vente.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Réglages et rapports de la flexibilité commerciale.
///
/// Singleton : `VentesCommercialesService.instance`.
class VentesCommercialesService {
  VentesCommercialesService._();

  static final VentesCommercialesService instance =
      VentesCommercialesService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  ParametresVente _courant = ParametresVente.aucun;
  bool _charge = false;
  DateTime? _dernierChargement;

  /// Derniers réglages connus (jamais `null`).
  ParametresVente get courant => _courant;

  bool get estCharge => _charge;

  /// Les réglages ont-ils été lus il y a moins de [validite] ?
  bool estFrais({Duration validite = const Duration(minutes: 10)}) {
    final DateTime? quand = _dernierChargement;
    if (quand == null) return false;
    return DateTime.now().difference(quand) < validite;
  }

  /// Force la relecture au prochain [charger].
  void invalider() {
    _charge = false;
    _dernierChargement = null;
  }

  /// Réinitialise complètement (déconnexion, changement de boutique).
  void reinitialiser() {
    _courant = ParametresVente.aucun;
    _charge = false;
    _dernierChargement = null;
  }

  // ---------------------------------------------------------------------------
  // LECTURE / ÉCRITURE DES RÉGLAGES
  // ---------------------------------------------------------------------------

  /// Lit les réglages de la boutique et les droits du vendeur connecté.
  ///
  /// [forcer] ignore le cache. En cas d'erreur, les réglages restent ceux du
  /// dernier chargement réussi (ou « tout désactivé »).
  Future<ParametresVente> charger({bool forcer = false}) async {
    if (_charge && !forcer && estFrais()) return _courant;

    try {
      final dynamic reponse =
          await _client.rpc('boutique_parametres_vente_lire');
      final Map<String, dynamic>? map = parseMap(reponse);
      if (map == null) return _courant;

      _courant = ParametresVente.fromMap(map);
      _charge = true;
      _dernierChargement = DateTime.now();
      return _courant;
    } catch (e) {
      debugPrint('VentesCommercialesService.charger : $e');
      return _courant;
    }
  }

  /// Enregistre les réglages (propriétaire uniquement — le serveur le vérifie).
  Future<ParametresVente> enregistrer(ParametresVente parametres) async {
    try {
      final dynamic reponse = await _client.rpc(
        'boutique_parametres_vente_enregistrer',
        params: parametres.versRpc(),
      );
      final Map<String, dynamic>? map = parseMap(reponse);
      if (map != null) {
        _courant = ParametresVente.fromMap(map);
        _charge = true;
        _dernierChargement = DateTime.now();
      }
      return _courant;
    } on PostgrestException catch (e) {
      throw VentesCommercialesException(_message(e.message));
    } catch (e) {
      debugPrint('VentesCommercialesService.enregistrer : $e');
      throw const VentesCommercialesException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // RAPPORTS
  // ---------------------------------------------------------------------------

  /// Résumé commercial : CA brut, négociations, réductions, cadeaux, marges.
  ///
  /// Les dates sont incluses. En cas d'échec, renvoie une carte vide : un
  /// rapport indisponible ne doit jamais faire tomber l'écran.
  Future<Map<String, dynamic>> resume({
    DateTime? debut,
    DateTime? fin,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'boutique_ventes_flexibilite_resume',
        params: <String, dynamic>{
          'p_debut': _dateIso(debut),
          'p_fin': _dateIso(fin),
        },
      );
      return parseMap(reponse) ?? <String, dynamic>{};
    } catch (e) {
      debugPrint('VentesCommercialesService.resume : $e');
      return <String, dynamic>{};
    }
  }

  /// Historique des ventes négociées, réduites ou avec cadeau.
  Future<List<Map<String, dynamic>>> historique({int limite = 50}) async {
    try {
      final dynamic reponse = await _client.rpc(
        'boutique_ventes_flexibilite_lister',
        params: <String, dynamic>{'p_limite': limite},
      );
      if (reponse is List) return parseMapList(reponse);
      if (reponse is Map) return parseMapList(reponse['result']);
      return const <Map<String, dynamic>>[];
    } catch (e) {
      debugPrint('VentesCommercialesService.historique : $e');
      return const <Map<String, dynamic>>[];
    }
  }

  /// `YYYY-MM-DD` (les fonctions SQL attendent une `date`).
  static String? _dateIso(DateTime? valeur) {
    if (valeur == null) return null;
    final String mois = valeur.month.toString().padLeft(2, '0');
    final String jour = valeur.day.toString().padLeft(2, '0');
    return '${valeur.year}-$mois-$jour';
  }

  /// Message utilisateur d'une erreur serveur (`CODE|texte`).
  static String _message(String brut) {
    final int barre = brut.indexOf('|');
    if (barre < 0) return brut;
    return brut.substring(barre + 1).trim();
  }
}

/// Erreur métier de la flexibilité commerciale (message en français).
class VentesCommercialesException implements Exception {
  const VentesCommercialesException(this.message);

  final String message;

  @override
  String toString() => message;
}
