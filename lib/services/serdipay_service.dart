// lib/services/serdipay_service.dart
//
// PASSERELLE DE PAIEMENT SERDIPAY (migration 79 + Edge Function `serdipay`).
//
//   • `initier`              → ouvre un paiement et renvoie le lien / l'USSD ;
//   • `statut`               → relit l'état d'une tentative ;
//   • `attendreConfirmation` → sondage toutes les 3 s (max 3 min) ;
//   • `ouvrirLien`           → ouvre la page de paiement dans le navigateur.
//
// ⚠️ Le MONTANT n'est jamais envoyé par l'application : il est calculé par la
// base (`rpc_serdipay_ouvrir`) à partir du solde réel de l'abonnement ou de
// la facture. Un client modifié ne peut donc pas payer moins cher.
//
// ⚠️ Le webhook reste la source de vérité côté serveur. Le sondage ne fait
// qu'accélérer l'affichage : même si l'utilisateur ferme l'application, la
// confirmation reçue par SerdiPay crédite l'abonnement.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:biashara_yangu/models/paiement_serdipay.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature d'une erreur de la passerelle (pour adapter l'interface).
enum TypeErreurSerdipay {
  /// La fonction n'est pas déployée, ou ses secrets manquent.
  nonConfigure,

  /// Session expirée / absente.
  session,

  /// Rien à payer, montant incorrect, téléphone invalide…
  demande,

  /// SerdiPay a refusé ou est injoignable.
  fournisseur,

  /// Problème réseau côté application.
  reseau,

  inconnu,
}

/// Erreur métier de la passerelle (message déjà rédigé en français).
class SerdipayException implements Exception {
  const SerdipayException(
    this.message, {
    this.code = '',
    this.type = TypeErreurSerdipay.inconnu,
  });

  final String message;
  final String code;
  final TypeErreurSerdipay type;

  @override
  String toString() => message;
}

/// Appels à la passerelle SerdiPay.
/// Singleton : `SerdipayService.instance`.
class SerdipayService {
  SerdipayService._();

  static final SerdipayService instance = SerdipayService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Nom de l'Edge Function (voir `supabase/functions/serdipay/index.ts`).
  static const String fonction = 'serdipay';

  /// Intervalle et durée maximale du sondage par défaut.
  static const Duration intervalleSondage = Duration(seconds: 3);
  static const Duration delaiMaxSondage = Duration(minutes: 3);

  /// Délai maximal d'un appel à la passerelle.
  ///
  /// ⚠️ SANS CE GARDE-FOU, un appel qui ne répond jamais bloquait l'écran
  ///    indéfiniment : « Vérifier maintenant » tournait sans fin, l'utilisateur
  ///    n'avait aucun retour et ne pouvait plus réessayer.
  static const Duration delaiAppelMax = Duration(seconds: 45);

  /// Délai d'une simple lecture de statut : elle doit être rapide.
  static const Duration delaiStatutMax = Duration(seconds: 15);

  // -------------------------------------------------------------------------
  // 1. INITIER UN PAIEMENT
  // -------------------------------------------------------------------------

  /// Ouvre un paiement.
  ///
  /// [objet] : `abonnement` (cycle en cours) ou `facture` (avec [objetId]).
  /// [telephone] : numéro Mobile Money, chiffres et indicatif acceptés.
  /// [entrepriseId] : facultatif — utile aux comptes multi-entreprises et à
  /// la plateforme ; sinon l'entreprise active est utilisée.
  ///
  /// ⚠️ Aucun montant n'est transmis : le serveur le calcule.
  /// [montant] : montant d'une AVANCE. `null` = la totalité de ce qui est dû.
  ///
  /// Le montant reste vérifié en base (`rpc_serdipay_ouvrir`) : il ne peut
  /// jamais dépasser le solde réel. Une avance laisse donc la place à un
  /// complément, et le compte s'active dès que le cycle est soldé.
  Future<PaiementSerdipay> initier({
    required String telephone,
    required OperateurSerdipay operateur,
    String objet = 'abonnement',
    String? objetId,
    String? entrepriseId,
    double? montant,
  }) async {
    final String numero = telephone.replaceAll(RegExp(r'[^0-9]'), '');
    if (numero.length < 9) {
      throw const SerdipayException(
        'Indiquez un numéro Mobile Money valide (au moins 9 chiffres).',
        code: 'TELEPHONE_INVALIDE',
        type: TypeErreurSerdipay.demande,
      );
    }

    final dynamic donnees = await _invoquer(
      '/initier',
      <String, dynamic>{
        'objet': objet,
        'objetId': objetId,
        'telephone': numero,
        'operateur': operateur.code,
        if (entrepriseId != null) 'entrepriseId': entrepriseId,
        if (montant != null) 'montant': montant,
      },
    );

    final Map<String, dynamic>? map = parseMap(donnees);
    if (map == null) {
      throw const SerdipayException(
        'Réponse inattendue de la passerelle de paiement.',
        code: 'REPONSE_INVALIDE',
      );
    }

    final PaiementSerdipay paiement = PaiementSerdipay.depuisEnveloppe(map);
    if (paiement.reference.isEmpty) {
      throw const SerdipayException(
        'La passerelle n\'a pas renvoyé de référence de paiement.',
        code: 'REFERENCE_ABSENTE',
      );
    }

    return paiement;
  }

  // -------------------------------------------------------------------------
  // 2. LIRE L'ÉTAT D'UN PAIEMENT
  // -------------------------------------------------------------------------

  Future<PaiementSerdipay> statut(String reference) async {
    final dynamic donnees = await _invoquer(
      '/statut',
      <String, dynamic>{'reference': reference},
      delai: delaiStatutMax,
    );

    final Map<String, dynamic>? map = parseMap(donnees);
    if (map == null) {
      throw const SerdipayException(
        'Réponse inattendue de la passerelle de paiement.',
        code: 'REPONSE_INVALIDE',
      );
    }

    return PaiementSerdipay.depuisEnveloppe(map);
  }

  // -------------------------------------------------------------------------
  // 3. ATTENDRE LA CONFIRMATION (sondage)
  // -------------------------------------------------------------------------

  /// Interroge la passerelle jusqu'à ce que le paiement quitte l'état
  /// « en attente », ou jusqu'à [delaiMax].
  ///
  /// [onChangement] est appelé à chaque état relu (utile pour rafraîchir
  /// l'écran). Aucune exception réseau n'est propagée pendant l'attente :
  /// on retente au tour suivant, le webhook reste la source de vérité.
  Future<PaiementSerdipay> attendreConfirmation(
    PaiementSerdipay depart, {
    Duration intervalle = intervalleSondage,
    Duration delaiMax = delaiMaxSondage,
    void Function(PaiementSerdipay)? onChangement,
  }) async {
    PaiementSerdipay courant = depart;
    final DateTime limite = DateTime.now().add(delaiMax);

    while (courant.estEnAttente && DateTime.now().isBefore(limite)) {
      // ⚡ On interroge TOUT DE SUITE, puis on attend : après avoir saisi son
      //    code PIN, le client doit voir une réponse immédiate et non un
      //    premier silence de 3 secondes.
      try {
        final PaiementSerdipay relu = await statut(courant.reference);
        if (relu.statut != courant.statut ||
            relu.urlPaiement != courant.urlPaiement) {
          courant = relu;
          onChangement?.call(courant);
        } else {
          courant = relu;
        }
      } catch (e) {
        debugPrint('SerdipayService.attendreConfirmation (ignoré) : $e');
      }

      if (!courant.estEnAttente || !DateTime.now().isBefore(limite)) {
        break;
      }

      await Future<void>.delayed(intervalle);
    }

    return courant;
  }

  // -------------------------------------------------------------------------
  // 4. OUVRIR LA PAGE DE PAIEMENT
  // -------------------------------------------------------------------------

  /// Ouvre le lien de paiement hébergé par SerdiPay.
  /// Renvoie `false` si aucun lien n'est disponible ou si l'ouverture échoue.
  Future<bool> ouvrirLien(String? url) async {
    if (url == null || url.trim().isEmpty) return false;

    try {
      final Uri? uri = Uri.tryParse(url.trim());
      if (uri == null) return false;

      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('SerdipayService.ouvrirLien (ignoré) : $e');
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // 5. APPEL DE L'EDGE FUNCTION
  // -------------------------------------------------------------------------

  Future<dynamic> _invoquer(
    String route,
    Map<String, dynamic> corps, {
    Duration delai = delaiAppelMax,
  }) async {
    try {
      final FunctionResponse reponse = await _client.functions
          .invoke('$fonction$route', body: corps)
          .timeout(delai);

      return reponse.data;
    } on FunctionException catch (e) {
      final Map<String, dynamic>? details = _mapDepuis(e.details);

      if (details != null && details['erreur'] != null) {
        throw _exceptionDepuis(details, statutHttp: e.status);
      }

      // 404 = fonction non publiée (passerelle Supabase, corps NOT_FOUND).
      if (e.status == 404) {
        throw const SerdipayException(
          "Le paiement en ligne n'est pas encore publié sur le serveur : "
          "l'administrateur doit déployer la fonction « serdipay » "
          '(Supabase → Edge Functions → serdipay → Deploy).',
          code: 'NON_DEPLOYE',
          type: TypeErreurSerdipay.nonConfigure,
        );
      }

      if (e.status == 503) {
        throw const SerdipayException(
          "Le paiement en ligne n'est pas configuré : renseignez les secrets "
          'SerdiPay (SERDIPAY_BASE_URL, SERDIPAY_API_KEY ou '
          'SERDIPAY_CLIENT_ID/SECRET, SERDIPAY_WEBHOOK_SECRET) dans Supabase, '
          'puis redéployez la fonction.',
          code: 'NON_CONFIGURE',
          type: TypeErreurSerdipay.nonConfigure,
        );
      }

      if (e.status == 401) {
        throw const SerdipayException(
          'Session expirée : reconnectez-vous pour payer.',
          code: 'SESSION_ABSENTE',
          type: TypeErreurSerdipay.session,
        );
      }

      throw SerdipayException(
        'La passerelle de paiement a renvoyé une erreur '
        '(HTTP ${e.status}). Réessayez dans quelques instants.',
        code: 'HTTP_${e.status}',
        type: TypeErreurSerdipay.fournisseur,
      );
    } catch (e) {
      if (e is SerdipayException) rethrow;

      if (e is TimeoutException) {
        throw const SerdipayException(
          'Le serveur de paiement ne répond pas. Vérifiez votre connexion '
          'internet puis réessayez.',
          code: 'DELAI_DEPASSE',
          type: TypeErreurSerdipay.reseau,
        );
      }

      throw SerdipayException(
        'Impossible de joindre le serveur de paiement. Vérifiez votre '
        'connexion internet puis réessayez. ($e)',
        code: 'RESEAU',
        type: TypeErreurSerdipay.reseau,
      );
    }
  }

  // -------------------------------------------------------------------------
  // 6. OUTILS DE LECTURE DES ERREURS
  // -------------------------------------------------------------------------

  static Map<String, dynamic>? _mapDepuis(dynamic details) {
    if (details == null) return null;
    if (details is Map) return Map<String, dynamic>.from(details);

    if (details is String && details.trim().startsWith('{')) {
      try {
        final dynamic decode = jsonDecode(details);
        if (decode is Map) return Map<String, dynamic>.from(decode);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  static SerdipayException _exceptionDepuis(
    Map<String, dynamic> details, {
    int? statutHttp,
  }) {
    final String code = parseString(details['erreur']);
    final String message = parseString(
      details['message'],
      fallback: 'La passerelle de paiement a refusé la demande.',
    );

    final TypeErreurSerdipay type;
    switch (code) {
      case 'SESSION_ABSENTE':
        type = TypeErreurSerdipay.session;
        break;
      case 'SERDIPAY_NON_CONFIGURE':
      case 'WEBHOOK_NON_CONFIGURE':
        type = TypeErreurSerdipay.nonConfigure;
        break;
      case 'FOURNISSEUR_INJOIGNABLE':
      case 'PAIEMENT_REFUSE_FOURNISSEUR':
        type = TypeErreurSerdipay.fournisseur;
        break;
      case 'SOLDE_NUL':
      case 'TELEPHONE_INVALIDE':
      case 'OBJET_INVALIDE':
      case 'OBJET_REQUIS':
      case 'FACTURE_INTROUVABLE':
      case 'MONTANT_INCORRECT':
        type = TypeErreurSerdipay.demande;
        break;
      default:
        type = statutHttp == 401
            ? TypeErreurSerdipay.session
            : TypeErreurSerdipay.inconnu;
    }

    return SerdipayException(message, code: code, type: type);
  }
}
