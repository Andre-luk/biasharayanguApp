// lib/services/peremption_service.dart
//
// 🧮 CORRECTIF 72 — LE DÉLAI D'ALERTE DE PÉREMPTION, PROPRE À LA BOUTIQUE.
//
// Avant : l'application prévenait qu'un produit allait périmer à partir d'un
// délai FIXE de 30 jours, écrit en dur ici et là. Une pharmacie veut être
// prévenue 90 jours à l'avance ; une épicerie se contente de 7. Un délai
// imposé est soit trop court — on découvre la péremption trop tard —, soit
// trop long — l'alerte devient permanente et on cesse de la lire.
//
// Ce service porte LE délai de la boutique :
//
//   • il le lit une fois (`charger`) et le garde en mémoire, parce que
//     plusieurs écrans en ont besoin (liste des articles, écran Expirations,
//     compteur d'accueil, notification de fin de journée) ;
//   • il le relit quand on le change (`definirDelai`), pour que tous les
//     écrans voient immédiatement le nouveau délai ;
//   • il ne DEVINE jamais : si la lecture échoue, il retombe sur 30 jours —
//     le comportement d'avant, jamais une valeur inventée.
//
// ⚠️ Le délai n'a AUCUN effet sur le blocage de vente des produits déjà
// expirés : ce blocage vit dans la base et ne dépend pas de ce réglage. Ne pas
// confondre les deux.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du délai de péremption.
class PeremptionException implements Exception {
  const PeremptionException(this.message, {this.type = TypeErreurPeremption.inconnu});

  final String message;
  final TypeErreurPeremption type;

  @override
  String toString() => message;
}

enum TypeErreurPeremption {
  /// La base n'a pas encore reçu la migration 72.
  nonDeploye,
  droits,
  session,
  validation,
  reseau,
  inconnu,
}

class PeremptionService {
  PeremptionService._();

  static final PeremptionService instance = PeremptionService._();

  /// Délai utilisé quand rien n'est réglé — et quand la lecture échoue.
  ///
  /// ⚠️ C'est volontairement la valeur historique (30 jours) : une boutique
  /// qui ne règle rien, ou dont la base n'est pas encore mise à jour, garde
  /// exactement le comportement d'avant. On ne change pas silencieusement le
  /// camp d'une alerte.
  static const int delaiParDefaut = 30;

  /// Bornes acceptées, identiques à la contrainte de la base (1 à 365).
  static const int delaiMinimum = 1;
  static const int delaiMaximum = 365;

  SupabaseClient get _client => Supabase.instance.client;

  int _delai = delaiParDefaut;
  bool _modifiable = false;
  bool _charge = false;

  /// Le délai en vigueur, en jours. Disponible SANS attendre après [charger].
  int get delaiJours => _delai;

  /// L'appelant peut-il modifier ce réglage ? (Sinon, l'écran se tait.)
  bool get modifiable => _modifiable;

  /// Une lecture a-t-elle abouti au moins une fois ?
  bool get estCharge => _charge;

  /// Lit le délai de la boutique. Ne lève jamais : en cas d'échec, le délai
  /// précédent (ou 30 jours) reste en place.
  ///
  /// [forcer] relit même si une lecture a déjà eu lieu.
  Future<int> charger({bool forcer = false}) async {
    if (_charge && !forcer) return _delai;

    try {
      final dynamic reponse = await _client.rpc('rpc_peremption_config');
      final Map<String, dynamic>? map = parseMap(reponse);
      if (map == null) return _delai;

      final int delai = parseInt(map['delai_jours'], fallback: delaiParDefaut);
      _delai = delai.clamp(delaiMinimum, delaiMaximum);
      _modifiable = map['modifiable'] == true;
      _charge = true;
      return _delai;
    } on PostgrestException catch (e) {
      //  PGRST202 = la fonction n'existe pas encore (migration 72 non
      //  exécutée). Ce n'est PAS une erreur pour l'utilisateur : il garde le
      //  délai par défaut, comme avant la migration.
      debugPrint('PeremptionService.charger : ${e.code} ${e.message}');
      return _delai;
    } catch (e) {
      debugPrint('PeremptionService.charger : $e');
      return _delai;
    }
  }

  /// Change le délai de la boutique.
  ///
  /// Lève une [PeremptionException] si la base refuse — le message du serveur
  /// est déjà rédigé en français et directement affichable.
  Future<int> definirDelai(int jours) async {
    if (jours < delaiMinimum || jours > delaiMaximum) {
      throw PeremptionException(
        'Le délai doit être compris entre $delaiMinimum et $delaiMaximum jours.',
        type: TypeErreurPeremption.validation,
      );
    }

    try {
      final dynamic reponse = await _client.rpc(
        'rpc_peremption_definir_delai',
        params: <String, dynamic>{'p_jours': jours},
      );

      final Map<String, dynamic>? map = parseMap(reponse);
      final int retenu = parseInt(map?['delai_jours'], fallback: jours);
      _delai = retenu.clamp(delaiMinimum, delaiMaximum);
      _charge = true;
      return _delai;
    } on PostgrestException catch (e) {
      throw PeremptionException(
        messageErreur(e.message, e.code),
        type: typeDepuisMessage(e.message, e.code),
      );
    } catch (e) {
      debugPrint('PeremptionService.definirDelai : $e');
      throw const PeremptionException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurPeremption.reseau,
      );
    }
  }

  /// Oublie ce qui a été lu (changement de compte, de boutique).
  void reinitialiser() {
    _delai = delaiParDefaut;
    _modifiable = false;
    _charge = false;
  }

  /// Extrait le texte utile d'une erreur serveur au format `CODE|texte fr`.
  static String messageErreur(String brut, [String? code]) {
    if (code == 'PGRST202') {
      return 'Cette fonction n\'est pas encore installée sur le serveur '
          '(mise à jour de la base à exécuter).';
    }
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) {
      return 'Impossible d\'enregistrer le délai d\'alerte.';
    }
    return texte.substring(separateur + 1).trim();
  }

  static TypeErreurPeremption typeDepuisMessage(String? brut, [String? code]) {
    if (code == 'PGRST202' || (brut ?? '').contains('PGRST202')) {
      return TypeErreurPeremption.nonDeploye;
    }
    final String texte = (brut ?? '').toUpperCase();
    if (texte.contains('SESSION_ABSENTE')) return TypeErreurPeremption.session;
    if (texte.contains('DROIT_REFUSE')) return TypeErreurPeremption.droits;
    if (texte.contains('DELAI_INVALIDE') ||
        texte.contains('ENTREPRISE_INTROUVABLE')) {
      return TypeErreurPeremption.validation;
    }
    return TypeErreurPeremption.inconnu;
  }
}
