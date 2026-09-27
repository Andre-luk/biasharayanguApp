// lib/utils/geo_utils.dart
//
// 🛒 MODULE 19 — OUTILS GÉOGRAPHIQUES & LIENS EXTERNES (PURS, TESTABLES).
//
// Ce fichier ne dépend d'aucun service : il peut être testé sans binding.
// Il regroupe tout ce qui touche à l'affichage d'une distance, aux liens
// « Voir l'itinéraire » / WhatsApp, et à la normalisation de recherche.
//
// ⚠️ MIROIR de `public.biashara_normaliser(text)` (migration 40) : les deux
//    normalisations doivent rester IDENTIQUES, sinon la recherche serveur et
//    les filtres locaux ne donnent pas les mêmes résultats.

/// Distance affichable à partir d'un nombre de kilomètres.
///
/// • `null`         → `null` (aucune position connue : on n'affiche rien) ;
/// • `< 1 km`       → mètres arrondis à la dizaine (« 850 m ») ;
/// • `>= 1 km`      → kilomètres avec décimales françaises (« 1,2 km ») ;
/// • `>= 10 km`     → kilomètres entiers (« 24 km ») : au-delà, la précision
///                    au mètre près n'a plus de sens pour un client.
String? formatDistance(double? km) {
  if (km == null) return null;

  final double valeur = km.abs();

  if (valeur < 1) {
    final int metres = ((valeur * 1000) / 10).round() * 10;
    return '$metres m';
  }

  if (valeur < 10) {
    return '${valeur.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  return '${valeur.round()} km';
}

/// Tranche de distance (miroir de `public.biashara_tranche_distance`).
///
/// Utilisée pour les statistiques : on n'enregistre jamais la position exacte
/// d'un visiteur, seulement une tranche.
String trancheDistance(double? km) {
  if (km == null) return 'inconnue';
  final double v = km.abs();
  if (v < 1) return '<1';
  if (v < 3) return '1-3';
  if (v < 10) return '3-10';
  return '>10';
}

/// Normalisation de recherche : minuscules, accents retirés, espaces
/// compactés. Miroir exact de `public.biashara_normaliser`.
String normaliserRecherche(String texte) {
  final String minuscule = texte.toLowerCase();
  final StringBuffer buffer = StringBuffer();

  for (final int rune in minuscule.runes) {
    final String caractere = String.fromCharCode(rune);
    buffer.write(_sansAccent[caractere] ?? caractere);
  }

  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

const Map<String, String> _sansAccent = <String, String>{
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y',
};

/// Lien « Voir l'itinéraire » vers un point.
///
/// ⚠️ AUCUNE CLÉ D'API : on utilise les liens universels publics des
/// services de cartographie. Sur téléphone, Android/iOS ouvrent l'application
/// installée si elle existe — sinon le navigateur.
///
/// [depuisLat]/[depuisLng] : position du visiteur, quand elle est connue
/// (elle n'est jamais transmise à un serveur Biashara).
String lienItineraire({
  required double latitude,
  required double longitude,
  double? depuisLat,
  double? depuisLng,
  String? libelle,
}) {
  final String destination =
      '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

  final StringBuffer url = StringBuffer(
    'https://www.google.com/maps/dir/?api=1&destination=$destination'
    '&travelmode=driving',
  );

  if (depuisLat != null && depuisLng != null) {
    url.write('&origin=${depuisLat.toStringAsFixed(6)},'
        '${depuisLng.toStringAsFixed(6)}');
  }

  if (libelle != null && libelle.trim().isNotEmpty) {
    url.write('&destination_place_id=&query=${Uri.encodeComponent(libelle.trim())}');
  }

  return url.toString();
}

/// Lien de recherche cartographique (alternative sans itinéraire).
String lienCarte({required double latitude, required double longitude}) {
  return 'https://www.openstreetmap.org/?mlat=${latitude.toStringAsFixed(6)}'
      '&mlon=${longitude.toStringAsFixed(6)}#map=17/'
      '${latitude.toStringAsFixed(6)}/${longitude.toStringAsFixed(6)}';
}

/// Numéro WhatsApp nettoyable (chiffres internationaux, sans `+` ni espaces).
///
/// Renvoie `null` si le numéro ne contient pas assez de chiffres : mieux vaut
/// ne pas afficher de bouton WhatsApp que d'ouvrir un lien invalide.
String? numeroWhatsApp(String? telephone) {
  if (telephone == null) return null;

  final String chiffres = telephone.replaceAll(RegExp(r'[^0-9]'), '');
  if (chiffres.length < 8) return null;

  return chiffres;
}

/// Lien `wa.me` (fonctionne sur mobile, bureau et web).
String? lienWhatsApp(String? telephone, {String? message}) {
  final String? numero = numeroWhatsApp(telephone);
  if (numero == null) return null;

  final String base = 'https://wa.me/$numero';
  if (message == null || message.trim().isEmpty) return base;

  return '$base?text=${Uri.encodeComponent(message.trim())}';
}

/// Lien téléphonique (`tel:`), ou `null` si le numéro est inutilisable.
String? lienTelephone(String? telephone) {
  if (telephone == null) return null;
  final String nettoye = telephone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (nettoye.replaceAll('+', '').length < 6) return null;
  return 'tel:$nettoye';
}

/// Adresse lisible par une personne qui ne connaît pas la ville.
///
/// Ordre d'assemblage pensé pour un visiteur ÉTRANGER : on part du repère le
/// plus utile (« en face de la poste ») pour finir par la ville, afin qu'une
/// adresse congolaise sans numéro de rue reste exploitable.
String adresseComplete({
  String? numero,
  String? avenue,
  String? quartier,
  String? adresse,
  String? pointRepere,
  String? ville,
  String? pays,
}) {
  final List<String> morceaux = <String>[];

  if (adresse != null && adresse.trim().isNotEmpty) {
    morceaux.add(adresse.trim());
  } else {
    final String voie = <String?>[numero, avenue]
        .where((String? e) => e != null && e.trim().isNotEmpty)
        .map((String? e) => e!.trim())
        .join(' ');
    if (voie.isNotEmpty) morceaux.add(voie);
  }

  if (quartier != null && quartier.trim().isNotEmpty) {
    morceaux.add(quartier.trim());
  }
  if (pointRepere != null && pointRepere.trim().isNotEmpty) {
    morceaux.add('repère : ${pointRepere.trim()}');
  }
  if (ville != null && ville.trim().isNotEmpty) {
    morceaux.add(ville.trim());
  }
  if (pays != null && pays.trim().isNotEmpty) {
    morceaux.add(pays.trim());
  }

  return morceaux.join(' · ');
}
