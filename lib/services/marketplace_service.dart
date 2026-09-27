// lib/services/marketplace_service.dart
//
// 🛒 MODULE 19 — CATALOGUE PUBLIC « BIASHARA » (SANS COMPTE).
//
// Ce service est le SEUL point d'entrée du catalogue public. Il appelle
// exclusivement les RPC `security definer` de la migration 40, qui
// n'exposent qu'une liste blanche de colonnes : le visiteur ne peut jamais
// atteindre `prix_achat`, le stock exact, les clients, les dettes ou les
// dépenses.
//
// Confidentialité de la position :
//   • les coordonnées du visiteur sont transmises en paramètre pour le CALCUL
//     de la distance, jamais enregistrées ;
//   • si le visiteur refuse la géolocalisation, on passe `p_ville_id` : la
//     recherche fonctionne exactement de la même façon.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/accueil_public.dart';
import 'package:biashara_yangu/models/boutique_publique.dart';
import 'package:biashara_yangu/models/produit_public.dart';
import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Types d'erreur du catalogue public.
enum TypeErreurMarketplace {
  nonDeploye,
  introuvable,
  reseau,
  inconnu,
}

/// Erreur métier du catalogue public.
class MarketplaceException implements Exception {
  const MarketplaceException(this.message, {this.type = TypeErreurMarketplace.inconnu});

  final String message;
  final TypeErreurMarketplace type;

  bool get estNonDeploye => type == TypeErreurMarketplace.nonDeploye;

  @override
  String toString() => message;
}

/// Une ville proposée au visiteur qui refuse la géolocalisation.
class VillePublique {
  const VillePublique({
    required this.id,
    required this.nom,
    this.pays,
    this.nbBoutiques = 0,
  });

  final String id;
  final String nom;
  final String? pays;
  final int nbBoutiques;

  /// « Lubumbashi (12 boutiques) ».
  String get libelleAffiche =>
      nbBoutiques > 0 ? '$nom ($nbBoutiques)' : nom;

  factory VillePublique.fromMap(Map<String, dynamic> map) {
    return VillePublique(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      pays: parseStringOrNull(map['pays']),
      nbBoutiques: parseInt(map['nb_boutiques']),
    );
  }
}

class MarketplaceService {
  MarketplaceService._();

  static final MarketplaceService instance = MarketplaceService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Dernier contexte géographique utilisé (ville choisie par le visiteur).
  ///
  /// Conservé UNIQUEMENT en mémoire, pour que les écrans suivants (recherche,
  /// carte) restent cohérents quand le visiteur a choisi une ville au lieu
  /// d'autoriser la géolocalisation. Effacé à la fermeture de l'application.
  String? villeIdCourante;
  String? villeNomCourante;

  /// Position du visiteur, en mémoire seulement (jamais persistée).
  double? latitudeCourante;
  double? longitudeCourante;

  bool get aPosition => latitudeCourante != null && longitudeCourante != null;

  /// Mémorise la ville choisie (« Rechercher dans une ville »).
  void definirVille(String? id, String? nom) {
    villeIdCourante = id;
    villeNomCourante = nom;
    if (id != null) {
      latitudeCourante = null;
      longitudeCourante = null;
    }
  }

  /// Mémorise la position obtenue avec le consentement du visiteur.
  void definirPosition(double lat, double lng) {
    latitudeCourante = lat;
    longitudeCourante = lng;
  }

  /// Réinitialise le contexte (quitter le catalogue public).
  void reinitialiserContexte() {
    villeIdCourante = null;
    villeNomCourante = null;
    latitudeCourante = null;
    longitudeCourante = null;
  }

  // ---------------------------------------------------------------------------
  // LECTURES PUBLIQUES
  // ---------------------------------------------------------------------------

  /// Page d'accueil publique (catégories, produits autour de vous, boutiques).
  Future<AccueilPublic> accueil({
    double? latitude,
    double? longitude,
    String? villeId,
    int limite = 8,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_biashara_accueil',
          params: <String, dynamic>{
            'p_lat': latitude ?? latitudeCourante,
            'p_lng': longitude ?? longitudeCourante,
            'p_ville_id': villeId ?? villeIdCourante,
            'p_limite': limite,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const MarketplaceException(
            'Le catalogue Biashara est momentanément indisponible.',
          );
        }

        return AccueilPublic.fromMap(map);
      },
      'le chargement du catalogue public',
    );
  }

  /// Recherche publique de produits.
  ///
  /// [enregistrer] : `true` pour les recherches RÉELLEMENT lancées par un
  /// visiteur (mesure du volume de recherches) ; `false` pour les
  /// rafraîchissements automatiques.
  Future<ResultatRecherchePublic> rechercher({
    String? texte,
    double? latitude,
    double? longitude,
    String? villeId,
    TriRecherche tri = TriRecherche.pertinence,
    String? categorie,
    int limite = 20,
    int decalage = 0,
    bool enregistrer = true,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_biashara_rechercher',
          params: <String, dynamic>{
            'p_texte': texte,
            'p_lat': latitude ?? latitudeCourante,
            'p_lng': longitude ?? longitudeCourante,
            'p_ville_id': villeId ?? villeIdCourante,
            'p_tri': tri.code,
            'p_categorie': categorie,
            'p_limite': limite,
            'p_decalage': decalage,
            'p_enregistrer': enregistrer,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const MarketplaceException(
            'La recherche n\'a pas pu aboutir. Réessayez.',
          );
        }

        return ResultatRecherchePublic.fromMap(map);
      },
      'la recherche de produits',
    );
  }

  /// Boutiques les plus proches (page d'accueil, carte, « Autour de moi »).
  Future<List<ResumeBoutique>> boutiquesProches({
    double? latitude,
    double? longitude,
    String? villeId,
    int limite = 12,
    double? rayonKm,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_biashara_boutiques_proches',
          params: <String, dynamic>{
            'p_lat': latitude ?? latitudeCourante,
            'p_lng': longitude ?? longitudeCourante,
            'p_ville_id': villeId ?? villeIdCourante,
            'p_limite': limite,
            'p_rayon_km': rayonKm,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        final List<dynamic> liste = (map?['boutiques'] as List?) ?? const <dynamic>[];

        return liste
            .whereType<Map>()
            .map((Map e) => ResumeBoutique.fromMap(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      },
      'le chargement des boutiques proches',
    );
  }

  /// Fiche publique d'une boutique (partageable par lien).
  Future<BoutiquePublique> boutique(
    String slugOuId, {
    double? latitude,
    double? longitude,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_biashara_boutique',
          params: <String, dynamic>{
            'p_slug': slugOuId,
            'p_lat': latitude ?? latitudeCourante,
            'p_lng': longitude ?? longitudeCourante,
            'p_limite': 60,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const MarketplaceException(
            'Cette boutique est introuvable sur Biashara.',
            type: TypeErreurMarketplace.introuvable,
          );
        }

        return BoutiquePublique.fromMap(map);
      },
      'le chargement de la boutique',
    );
  }

  /// Fiche publique d'un produit + comparaison des prix.
  Future<FicheProduitPublic> produit(
    String publicationId, {
    double? latitude,
    double? longitude,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_biashara_produit',
          params: <String, dynamic>{
            'p_publication_id': publicationId,
            'p_lat': latitude ?? latitudeCourante,
            'p_lng': longitude ?? longitudeCourante,
            'p_limite': 12,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const MarketplaceException(
            'Ce produit est introuvable sur Biashara.',
            type: TypeErreurMarketplace.introuvable,
          );
        }

        return FicheProduitPublic.fromMap(map);
      },
      'le chargement du produit',
    );
  }

  /// Villes où des boutiques sont publiées (repli sans géolocalisation).
  Future<List<VillePublique>> villes() async {
    try {
      final dynamic reponse = await _client.rpc('rpc_biashara_villes');
      final Map<String, dynamic>? map = parseMap(reponse);
      final List<dynamic> liste = (map?['villes'] as List?) ?? const <dynamic>[];

      return liste
          .whereType<Map>()
          .map((Map e) => VillePublique.fromMap(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (e) {
      debugPrint('MarketplaceService.villes : $e');
      return const <VillePublique>[];
    }
  }

  /// Catégories populaires (accueil + filtres de recherche).
  Future<List<CategoriePublique>> categories({
    String? villeId,
    int limite = 12,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'rpc_biashara_categories',
        params: <String, dynamic>{
          'p_ville_id': villeId ?? villeIdCourante,
          'p_limite': limite,
        },
      );
      final Map<String, dynamic>? map = parseMap(reponse);
      final List<dynamic> liste =
          (map?['categories'] as List?) ?? const <dynamic>[];

      return liste
          .whereType<Map>()
          .map((Map e) => CategoriePublique.fromMap(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (e) {
      debugPrint('MarketplaceService.categories : $e');
      return const <CategoriePublique>[];
    }
  }

  // ---------------------------------------------------------------------------
  // MESURE DE VISIBILITÉ (appelée par les écrans publics)
  // ---------------------------------------------------------------------------

  /// Enregistre un événement de visibilité.
  ///
  /// Best-effort : un échec ne doit JAMAIS gêner le visiteur. La distance est
  /// convertie en TRANCHE côté serveur : la position exacte n'est jamais
  /// enregistrée.
  ///
  /// [type] : `impression_produit`, `vue_produit`, `vue_boutique`,
  /// `clic_itineraire`, `clic_telephone`, `clic_whatsapp`, `clic_site`,
  /// `partage`, `recherche`, `conversion`.
  Future<void> evenement({
    required String type,
    String? entiteType,
    String? entiteId,
    String? publiciteId,
    String? villeId,
    String? quartier,
    double? distanceKm,
    int? rechercheId,
  }) async {
    try {
      await _client.rpc('rpc_biashara_evenement', params: <String, dynamic>{
        'p_type_evenement': type,
        'p_entite_type': entiteType,
        'p_entite_id': entiteId,
        'p_publicite_id': publiciteId,
        'p_ville_id': villeId ?? villeIdCourante,
        'p_quartier': quartier,
        'p_distance_km': distanceKm ?? 0,
        'p_recherche_id': rechercheId,
      });
    } catch (e) {
      // Les statistiques ne doivent jamais casser l'expérience d'achat.
      debugPrint('MarketplaceService.evenement($type) ignoré : $e');
    }
  }

  /// Enregistre une IMPRESSION pour chaque résultat affiché.
  ///
  /// C'est la mesure de VISIBILITÉ (niveau 1) : elle est appelée après
  /// l'affichage effectif de la liste, jamais avant.
  Future<void> impressionsResultats(
    List<ProduitPublic> produits, {
    int? rechercheId,
  }) async {
    for (final ProduitPublic produit in produits.take(20)) {
      await evenement(
        type: 'impression_produit',
        entiteType: 'produit',
        entiteId: produit.publicationId,
        villeId: produit.boutique.ville == null ? null : villeIdCourante,
        quartier: produit.boutique.quartier,
        distanceKm: produit.distanceKm,
        rechercheId: rechercheId,
      );
    }
  }

  /// Enregistre l'impression d'un emplacement publicitaire.
  Future<void> impressionPublicite(
    PubliciteBiashara publicite, {
    double? distanceKm,
  }) {
    return evenement(
      type: 'impression_publicite',
      entiteType: 'publicite',
      publiciteId: publicite.id,
      distanceKm: distanceKm,
    );
  }

  // ---------------------------------------------------------------------------
  // OUTILS INTERNES
  // ---------------------------------------------------------------------------

  /// Extrait le message utilisateur d'une erreur serveur préfixée (`CODE|texte`).
  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  Future<T> _executer<T>(Future<T> Function() action, String libelle) async {
    try {
      return await action();
    } on MarketplaceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('MarketplaceService ($libelle) : ${e.message}');

      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const MarketplaceException(
          'Le catalogue public « Biashara » n\'est pas encore installé sur la '
          'base. Exécutez le script '
          'supabase/migrations/20260916000040_module19_marketplace.sql '
          'puis réessayez.',
          type: TypeErreurMarketplace.nonDeploye,
        );
      }

      final String code = e.message.split('|').first.trim().toUpperCase();
      throw MarketplaceException(
        messageErreur(e.message),
        type: code == 'BOUTIQUE_INCONNUE' || code == 'PRODUIT_INCONNU'
            ? TypeErreurMarketplace.introuvable
            : TypeErreurMarketplace.inconnu,
      );
    } catch (e, st) {
      debugPrint('MarketplaceService ($libelle) : $e\n$st');
      throw const MarketplaceException(
        'Impossible de contacter le catalogue Biashara. '
        'Vérifiez votre connexion internet.',
        type: TypeErreurMarketplace.reseau,
      );
    }
  }
}
