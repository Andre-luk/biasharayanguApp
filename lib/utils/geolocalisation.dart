// lib/utils/geolocalisation.dart
//
// 🛒 MODULE 19 — POSITION DU VISITEUR, AVEC CONSENTEMENT ET REPLI.
//
// Règles appliquées :
//   • la position n'est demandée QUE sur une action explicite du visiteur
//     (« Autour de moi ») : jamais au chargement de la page ;
//   • elle n'est JAMAIS transmise à un serveur Biashara : elle sert seulement
//     à calculer des distances, à la volée ;
//   • elle n'est JAMAIS stockée sur l'appareil ;
//   • si l'appareil ou le navigateur refuse/ignore la géolocalisation, on
//     renvoie `null` et l'interface propose « Rechercher dans une ville ».
//
// ⚠️ Sur Linux, `geolocator` n'a pas d'implémentation : l'appel lève une
//    exception de greffon, aussitôt convertie en `null` — l'application reste
//    parfaitement utilisable et propose le choix sur la carte.

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Position obtenue, avec son origine (utile pour la traçabilité de la fiche).
class PositionUtilisateur {
  const PositionUtilisateur({
    required this.latitude,
    required this.longitude,
    this.precisionMetres,
  });

  final double latitude;
  final double longitude;
  final double? precisionMetres;

  /// Code `precision_localisation` envoyé au serveur (`gps`).
  String get origine => 'gps';

  /// Arrondi d'affichage (« ± 12 m »).
  String? get precisionLibelle => precisionMetres == null
      ? null
      : '± ${precisionMetres!.round()} m';
}

/// Résultat d'une demande de position : succès, refus ou indisponibilité.
class ResultatPosition {
  const ResultatPosition({
    this.position,
    this.message,
    this.refus = false,
  });

  final PositionUtilisateur? position;

  /// Message à afficher au visiteur quand la position n'a pas pu être obtenue.
  final String? message;

  /// `true` = le visiteur (ou son appareil) a explicitement refusé.
  final bool refus;

  bool get succes => position != null;

  const ResultatPosition.indisponible(this.message)
      : position = null,
        refus = false;
}

/// Service minimal de géolocalisation, tolérant à toutes les plateformes.
class Geolocalisation {
  Geolocalisation._();

  static final Geolocalisation instance = Geolocalisation._();

  /// Position actuelle, ou `null`.
  ///
  /// Ne lève JAMAIS : toute erreur (refus, service désactivé, plateforme non
  /// prise en charge, absence de greffon) devient un échec explicable.
  Future<ResultatPosition> positionActuelle({
    Duration delaiMax = const Duration(seconds: 12),
  }) async {
    try {
      final bool serviceActif = await Geolocator.isLocationServiceEnabled();
      if (!serviceActif) {
        return const ResultatPosition.indisponible(
          'La localisation est désactivée sur cet appareil. Activez-la, ou '
          'choisissez une ville.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const ResultatPosition(
          refus: true,
          message: 'Vous avez refusé la localisation. Aucun problème : '
              'choisissez une ville ou placez le repère sur la carte.',
        );
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: delaiMax,
        ),
      );

      return ResultatPosition(
        position: PositionUtilisateur(
          latitude: position.latitude,
          longitude: position.longitude,
          precisionMetres: position.accuracy,
        ),
      );
    } catch (e) {
      debugPrint('Geolocalisation indisponible : $e');
      return ResultatPosition(
        message: _messageIndisponible(e),
      );
    }
  }

  /// Message adapté au cas le plus fréquent : plateforme sans GPS.
  static String _messageIndisponible(Object erreur) {
    final String texte = erreur.toString().toLowerCase();
    if (texte.contains('missingpluginexception') ||
        texte.contains('unimplemented') ||
        texte.contains('no implementation')) {
      return 'Cet appareil ne fournit pas de position GPS. Utilisez la carte '
          'ou choisissez une ville : le résultat sera identique.';
    }
    if (texte.contains('timeoutexception') || texte.contains('timeout')) {
      return 'La position n\'a pas été obtenue à temps (signal GPS faible ?). '
          'Réessayez, ou placez le repère sur la carte.';
    }
    return 'Position indisponible. Placez le repère sur la carte ou choisissez '
        'une ville pour continuer.';
  }

  /// Ouvre les réglages système de localisation (utile après un refus).
  Future<void> ouvrirReglages() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (e) {
      debugPrint('Ouverture des réglages impossible : $e');
    }
  }
}
