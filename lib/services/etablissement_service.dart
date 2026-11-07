// lib/services/etablissement_service.dart
//
// MODULE 27 — QUI EST L'ÉTABLISSEMENT QUI VEND ?
//
// Une seule source pour les documents commerciaux : nom, adresse, téléphone,
// e-mail, logo, RCCM et identifiant national. Les fonctions serveur
// (`etablissement_fiche`, `etablissement_identite_enregistrer`) font le vrai
// travail ; ce service met en cache la réponse pour que la caisse n'attende
// pas le réseau avant d'imprimer.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Identité de l'établissement (lecture / écriture).
///
/// Singleton : `EtablissementService.instance`.
class EtablissementService {
  EtablissementService._();

  static final EtablissementService instance = EtablissementService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  Etablissement _courant = const Etablissement(nom: 'Établissement');
  bool _charge = false;
  DateTime? _dernierChargement;

  /// Dernière fiche connue (jamais `null`).
  Etablissement get courant => _courant;

  bool get estCharge => _charge;

  bool estFrais({Duration validite = const Duration(minutes: 30)}) {
    final DateTime? quand = _dernierChargement;
    if (quand == null) return false;
    return DateTime.now().difference(quand) < validite;
  }

  void reinitialiser() {
    _courant = const Etablissement(nom: 'Établissement');
    _charge = false;
    _dernierChargement = null;
  }

  /// Charge (ou recharge) la fiche. En cas d'échec, garde la dernière connue :
  /// une facture ne doit jamais être bloquée par le réseau.
  Future<Etablissement> charger({
    bool forcer = false,
    String? ownerId,
  }) async {
    if (_charge && !forcer && ownerId == null && estFrais()) return _courant;

    try {
      final dynamic reponse = await _client.rpc(
        'etablissement_fiche',
        params: <String, dynamic>{'p_owner': ownerId},
      );
      final Map<String, dynamic>? map = parseMap(reponse);
      if (map != null) {
        _courant = Etablissement.fromMap(map);
        _charge = true;
        _dernierChargement = DateTime.now();
      }
      return _courant;
    } catch (e) {
      debugPrint('EtablissementService.charger : $e');
      return _courant;
    }
  }

  /// Enregistre l'identité (propriétaire uniquement — vérifié côté serveur).
  Future<Etablissement> enregistrer({
    required String nom,
    String? adresse,
    String? quartier,
    String? avenue,
    String? numero,
    String? repere,
    String? telephone,
    String? email,
    String? rccm,
    String? idNational,
    String? logoUrl,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'etablissement_identite_enregistrer',
        params: <String, dynamic>{
          'p_nom': nom,
          'p_adresse': adresse,
          'p_quartier': quartier,
          'p_avenue': avenue,
          'p_numero': numero,
          'p_repere': repere,
          'p_telephone': telephone,
          'p_email': email,
          'p_rccm': rccm,
          'p_id_national': idNational,
          'p_logo_url': logoUrl,
        },
      );
      final Map<String, dynamic>? map = parseMap(reponse);
      if (map != null) {
        _courant = Etablissement.fromMap(map);
        _charge = true;
        _dernierChargement = DateTime.now();
      }
      return _courant;
    } on PostgrestException catch (e) {
      throw EtablissementException(_message(e.message));
    } catch (e) {
      debugPrint('EtablissementService.enregistrer : $e');
      throw const EtablissementException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
      );
    }
  }

  static String _message(String brut) {
    final int barre = brut.indexOf('|');
    return barre < 0 ? brut : brut.substring(barre + 1).trim();
  }
}

/// Erreur métier (message déjà en français).
class EtablissementException implements Exception {
  const EtablissementException(this.message);

  final String message;

  @override
  String toString() => message;
}
