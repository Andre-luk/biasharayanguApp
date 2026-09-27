// lib/services/publicite_service.dart
//
// 🛒 MODULE 19 — « PUBLICITÉS BIASHARA ».
//
// Espace PRÉPARATOIRE : le commerçant compose sa campagne (produit, boutique,
// promotion ou offre spéciale), choisit un ciblage (ville, quartier, rayon,
// catégorie) et la SOUMET. La plateforme l'active ensuite.
//
// Règles d'éthique portées par l'architecture :
//   • une annonce porte TOUJOURS la mention « PUBLICITÉ » (le serveur la
//     renvoie et l'interface l'affiche en clair) ;
//   • une annonce n'est JAMAIS insérée dans la liste des résultats organiques :
//     elle est servie dans un tableau séparé et affichée dans un emplacement
//     dédié, non intrusif ;
//   • le ciblage utilise la ville choisie, la catégorie consultée ou un rayon
//     demandé : jamais la position d'une personne.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Types d'erreur de l'espace publicitaire.
enum TypeErreurPublicite {
  nonDeploye,
  accesRefuse,
  validation,
  reseau,
  inconnu,
}

/// Erreur métier des publicités.
class PubliciteException implements Exception {
  const PubliciteException(this.message, {this.type = TypeErreurPublicite.inconnu});

  final String message;
  final TypeErreurPublicite type;

  @override
  String toString() => message;
}

class PubliciteService {
  PubliciteService._();

  static final PubliciteService instance = PubliciteService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Campagnes de la boutique (tous statuts).
  Future<List<PubliciteBiashara>> lister({String? espaceId}) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_biashara_publicites_lister',
          params: <String, dynamic>{'p_espace_id': espaceId}),
      'le chargement de vos publicités',
    );

    final Map<String, dynamic>? map = parseMap(reponse);
    final List<dynamic> liste =
        (map?['publicites'] as List?) ?? const <dynamic>[];

    return liste
        .whereType<Map>()
        .map((Map e) => PubliciteBiashara.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Crée ou met à jour une campagne.
  ///
  /// [soumettre] : `true` pour demander la validation à la plateforme
  /// (statut « soumise »), `false` pour rester en brouillon.
  Future<PubliciteBiashara?> enregistrer({
    String? id,
    String? titre,
    String? message,
    TypeContenuPublicite typeContenu = TypeContenuPublicite.produit,
    int? produitId,
    String? imageUrl,
    double? prixPromo,
    DateTime? dateDebut,
    DateTime? dateFin,
    double? budget,
    int? plafondImpressions,
    String? espaceId,
    List<CiblePublicite> cibles = const <CiblePublicite>[],
    bool soumettre = false,
  }) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_biashara_publicite_enregistrer', params: <String, dynamic>{
        'p_id': id,
        'p_titre': titre,
        'p_message': message,
        'p_type_contenu': typeContenu.code,
        'p_produit_id': produitId,
        'p_image_url': imageUrl,
        'p_prix_promo': prixPromo,
        'p_date_debut': dateDebut?.toUtc().toIso8601String(),
        'p_date_fin': dateFin?.toUtc().toIso8601String(),
        'p_budget': budget,
        'p_plafond_impressions': plafondImpressions,
        'p_espace_id': espaceId,
        'p_cibles': cibles.map((CiblePublicite c) => c.toMap()).toList(),
        'p_soumettre': soumettre,
      }),
      'l\'enregistrement de la campagne',
    );

    final Map<String, dynamic>? map = parseMap(reponse);
    final String? idCree = parseStringOrNull(map?['id']);
    if (idCree == null) return null;

    return PubliciteBiashara(
      id: idCree,
      titre: titre ?? '',
      message: message,
      typeContenu: typeContenu,
      produitId: produitId,
      imageUrl: imageUrl,
      prixPromo: prixPromo,
      dateDebut: dateDebut,
      dateFin: dateFin,
      budget: budget,
      plafondImpressions: plafondImpressions,
      statut: StatutPublicite.fromCode(parseStringOrNull(map?['statut'])),
      espaceId: espaceId,
      cibles: cibles,
    );
  }

  /// Change le statut d'une campagne.
  ///
  /// Le commerçant peut : brouillon, soumise, pause, terminee.
  /// La plateforme (Super Admin) peut en plus : active, refusee.
  Future<void> changerStatut({
    required String id,
    required StatutPublicite statut,
    String? note,
  }) {
    return _executer(
      () async {
        await _client.rpc('rpc_biashara_publicite_statut', params: <String, dynamic>{
          'p_id': id,
          'p_statut': statut.code,
          'p_note': note,
        });
      },
      'le changement de statut',
    );
  }

  /// Modération (personnel plateforme) : campagnes à valider.
  Future<List<PubliciteBiashara>> moderation({String? statut}) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_biashara_publicites_moderation',
          params: <String, dynamic>{'p_statut': statut}),
      'le chargement de la modération',
    );

    final Map<String, dynamic>? map = parseMap(reponse);
    final List<dynamic> liste =
        (map?['publicites'] as List?) ?? const <dynamic>[];

    return liste
        .whereType<Map>()
        .map((Map e) => PubliciteBiashara.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // OUTILS INTERNES
  // ---------------------------------------------------------------------------

  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  Future<T> _executer<T>(Future<T> Function() action, String libelle) async {
    try {
      return await action();
    } on PubliciteException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('PubliciteService ($libelle) : ${e.message}');

      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const PubliciteException(
          'Le module « Publicités Biashara » n\'est pas installé sur la base. '
          'Exécutez '
          'supabase/migrations/20260916000040_module19_marketplace.sql.',
          type: TypeErreurPublicite.nonDeploye,
        );
      }

      final String code = e.message.split('|').first.trim().toUpperCase();
      throw PubliciteException(
        messageErreur(e.message),
        type: switch (code) {
          'ACCES_REFUSE' || 'STATUT_REFUSE' => TypeErreurPublicite.accesRefuse,
          'TYPE_PUBLICITE_INCONNU' ||
          'TITRE_MANQUANT' ||
          'STATUT_INCONNU' ||
          'PUBLICITE_INCONNUE' =>
            TypeErreurPublicite.validation,
          _ => TypeErreurPublicite.inconnu,
        },
      );
    } catch (e, st) {
      debugPrint('PubliciteService ($libelle) : $e\n$st');
      throw const PubliciteException(
        'Impossible de contacter Biashara. Vérifiez votre connexion internet.',
        type: TypeErreurPublicite.reseau,
      );
    }
  }
}
