// lib/services/geocodage_service.dart
//
// 🛒 MODULE 19 — RECHERCHE D'ADRESSE (OPTION C DU PARCOURS DE LOCALISATION).
//
// Le commerçant qui ne connaît pas ses coordonnées peut taper son adresse
// (« avenue Kasaï, Katuba, Lubumbashi ») et obtenir une proposition de point,
// qu'il CONFIRMERA ensuite sur la carte. Rien n'est enregistré sans cette
// confirmation : une adresse approximative ne doit jamais placer une boutique
// au mauvais endroit.
//
// Service utilisé : Nominatim (OpenStreetMap).
//   • AUCUNE CLÉ D'API, aucun compte, aucune facturation ;
//   • politique d'usage : un agent identifiant clair est envoyé, les requêtes
//     sont déclenchées à la demande (pas de polling), et le service est
//     appelé sur action explicite du commerçant ;
//   • en cas d'échec (réseau, service indisponible), on retombe proprement sur
//     « placer le repère sur la carte » : le parcours n'est jamais bloqué.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Une proposition d'adresse : libellé lisible + coordonnées.
class PropositionAdresse {
  const PropositionAdresse({
    required this.libelle,
    required this.latitude,
    required this.longitude,
    this.ville,
    this.quartier,
  });

  final String libelle;
  final double latitude;
  final double longitude;

  /// Composants utiles pour pré-remplir le formulaire.
  final String? ville;
  final String? quartier;

  factory PropositionAdresse.fromNominatim(Map<String, dynamic> map) {
    final Map<String, dynamic> adresse = map['address'] is Map
        ? Map<String, dynamic>.from(map['address'] as Map)
        : <String, dynamic>{};

    String? premier(List<String> cles) {
      for (final String cle in cles) {
        final String valeur = (adresse[cle] ?? '').toString().trim();
        if (valeur.isNotEmpty) return valeur;
      }
      return null;
    }

    return PropositionAdresse(
      libelle: (map['display_name'] ?? '').toString(),
      latitude: double.tryParse('${map['lat']}') ?? 0,
      longitude: double.tryParse('${map['lon']}') ?? 0,
      ville: premier(<String>['city', 'town', 'village', 'municipality', 'county']),
      quartier: premier(<String>[
        'suburb',
        'neighbourhood',
        'quarter',
        'city_district',
        'hamlet',
      ]),
    );
  }
}

class GeocodageService {
  GeocodageService._();

  static final GeocodageService instance = GeocodageService._();

  static const String _base = 'https://nominatim.openstreetmap.org/search';

  /// Agent identifiant l'application (exigé par la politique d'usage).
  static const String _userAgent =
      'BiasharaYangu/1.0 (application de gestion commerciale; '
      'contact support@biasharayangu.cd)';

  /// Recherche les adresses correspondant à [requete].
  ///
  /// Renvoie une liste vide en cas d'échec : l'interface proposera alors de
  /// placer le repère sur la carte. Ne lève jamais.
  Future<List<PropositionAdresse>> rechercher(
    String requete, {
    int limite = 6,
  }) async {
    final String texte = requete.trim();
    if (texte.length < 3) return const <PropositionAdresse>[];

    try {
      final Uri url = Uri.parse(_base).replace(queryParameters: <String, String>{
        'q': texte,
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '$limite',
        'accept-language': 'fr',
      });

      final http.Response reponse = await http
          .get(url, headers: <String, String>{'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (reponse.statusCode != 200) {
        debugPrint('Géocodage : HTTP ${reponse.statusCode}');
        return const <PropositionAdresse>[];
      }

      final dynamic corps = jsonDecode(utf8.decode(reponse.bodyBytes));
      if (corps is! List) return const <PropositionAdresse>[];

      return corps
          .whereType<Map>()
          .map((Map e) =>
              PropositionAdresse.fromNominatim(Map<String, dynamic>.from(e)))
          .where((PropositionAdresse p) => p.latitude != 0 || p.longitude != 0)
          .toList(growable: false);
    } catch (e) {
      debugPrint('Géocodage indisponible : $e');
      return const <PropositionAdresse>[];
    }
  }

  /// Message d'explication affiché quand aucune adresse n'est trouvée : on
  /// guide vers l'option qui fonctionne toujours (le repère sur la carte).
  static const String messageAucunResultat =
      'Aucune adresse trouvée. Vérifiez l\'orthographe (ex. « avenue Kasaï, '
      'Katuba, Lubumbashi ») ou placez directement le repère sur la carte.';
}
