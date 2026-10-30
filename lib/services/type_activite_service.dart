// lib/services/type_activite_service.dart
//
// REFONTE ABONNEMENTS & DISTRIBUTION — TYPE D'ACTIVITÉ (facade Dart).
//
// Facade de la RPC `rpc_entreprise_type_activite()` (migration 0083) :
// renvoie `boutique`, `distribution` ou `null` (non renseigné).
//
// L'état est exposé via [type] (ValueNotifier) ; les écrans s'y abonnent pour
// masquer les entrées qui ne concernent pas le métier de l'entreprise.
//
// ⚠️ RÈGLE D'OR (zéro régression) : tant que rien n'est chargé — hors ligne,
// migration absente, type non renseigné — [type] vaut `null` et AUCUN écran
// n'est masqué. Le service ne fait que MASQUER ; il ne bloque jamais.
//
// Le service suit [EspaceService] : changer d'entreprise recharge le type.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/type_activite.dart';
import 'package:biashara_yangu/services/espace_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';

class TypeActiviteService {
  TypeActiviteService._();

  static final TypeActiviteService instance = TypeActiviteService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Type d'activité de l'entreprise courante (`null` = non renseigné).
  final ValueNotifier<TypeActivite?> type =
      ValueNotifier<TypeActivite?>(null);

  bool _charge = false;
  bool _surveillanceActive = false;
  String? _dernierEspaceId;

  /// Un type a-t-il été reçu du serveur ?
  bool get charge => _charge;

  /// Vrai si l'entreprise est une boutique (type connu).
  bool get estBoutique => ReglesTypeActivite.estBoutique(type.value);

  /// Vrai si l'entreprise est une distribution (type connu).
  bool get estDistribution => ReglesTypeActivite.estDistribution(type.value);

  /// Une entrée réservée à [requis] doit-elle être masquée ?
  bool masque(TypeActivite? requis) =>
      ReglesTypeActivite.masque(type.value, requis);

  /// Charge le type depuis le serveur (best-effort : ne lève jamais).
  Future<void> charger() async {
    try {
      final dynamic reponse = await _client
          .rpc('rpc_entreprise_type_activite')
          .timeout(const Duration(seconds: 6));
      _appliquer(reponse);
    } catch (_) {
      // Fail-open : on conserve l'état précédent (souvent `null`).
      _charge = false;
    }
  }

  /// Force un type (tests, ou après un changement côté admin).
  void definir(TypeActivite? valeur) => _appliquer(valeur?.code);

  /// Remise à zéro (changement de compte, déconnexion).
  void reinitialiser() {
    _charge = false;
    _appliquer(null);
  }

  void _appliquer(dynamic brut) {
    final TypeActivite? valeur = brut is String
        ? TypeActivite.depuis(brut)
        : (brut == null ? null : TypeActivite.depuis(brut.toString()));
    _charge = valeur != null;
    if (type.value != valeur) type.value = valeur;
  }

  /// Démarre la surveillance des changements d'entreprise (idempotent).
  /// À appeler une seule fois au démarrage.
  void demarrerSurveillance() {
    if (_surveillanceActive) return;
    _surveillanceActive = true;
    EspaceService.instance.etat.addListener(_surEspace);
  }

  void arreterSurveillance() {
    if (!_surveillanceActive) return;
    _surveillanceActive = false;
    EspaceService.instance.etat.removeListener(_surEspace);
  }

  void _surEspace() {
    final String? id = EspaceService.instance.actif?.id;

    // Sélecteur réinitialisé (déconnexion) : plus aucun espace actif.
    if (id == null) {
      if (_dernierEspaceId != null) reinitialiser();
      return;
    }

    if (id == _dernierEspaceId) return;
    _dernierEspaceId = id;
    // Changer d'entreprise change de métier : on repart de zéro puis on
    // recharge (le `null` intermédiaire rouvre tout = fail-open).
    type.value = null;
    _charge = false;
    unawaited(charger());
  }
}
