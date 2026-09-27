// lib/services/vitrine_service.dart
//
// 🛒 MODULE 19 — ESPACE COMMERÇANT : VITRINE, PUBLICATIONS, VISIBILITÉ.
//
// Trois responsabilités, volontairement séparées des écrans :
//   1. VITRINE      : localisation guidée (ma position / carte / adresse),
//                     adresse détaillée, contacts publics, horaires, visuels ;
//   2. PUBLICATIONS : quels articles apparaissent dans le catalogue public ;
//   3. VISIBILITÉ   : ce que Biashara apporte réellement à la boutique
//                     (impressions, intérêt, intention, conversion) et les
//                     codes d'attribution (QR / lien / code promotionnel).
//
// ⚠️ TOUTES les RPC ci-dessous revérifient côté serveur la PROPRIÉTÉ de la
//    boutique : aucun écran ne peut lire la vitrine ou les statistiques d'une
//    autre entreprise, même en forgeant un identifiant d'espace.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/lien_attribution.dart';
import 'package:biashara_yangu/models/localisation_boutique.dart';
import 'package:biashara_yangu/models/publication_produit.dart';
import 'package:biashara_yangu/models/visibilite_biashara.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/image_locale.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Bucket public où vivent les visuels de vitrine (logo, devanture).
const String _bucketBoutiques = 'boutiques';

/// Types d'erreur de l'espace commerçant.
enum TypeErreurVitrine {
  nonDeploye,
  accesRefuse,
  positionManquante,
  validation,
  reseau,
  inconnu,
}

/// Erreur métier de l'espace commerçant.
class VitrineException implements Exception {
  const VitrineException(this.message, {this.type = TypeErreurVitrine.inconnu});

  final String message;
  final TypeErreurVitrine type;

  @override
  String toString() => message;
}

/// Résultat de l'enregistrement d'une vitrine.
class ResultatVitrine {
  const ResultatVitrine({
    required this.espaceId,
    this.slug,
    this.visible = false,
    this.statut = StatutLocalisation.nonRenseignee,
    this.cheminPublic,
  });

  final String espaceId;
  final String? slug;
  final bool visible;
  final StatutLocalisation statut;

  /// Lien à partager (`/biashara/boutique/<slug>`), `null` si non publiée.
  final String? cheminPublic;

  factory ResultatVitrine.fromMap(Map<String, dynamic> map) {
    return ResultatVitrine(
      espaceId: parseString(map['espace_id']),
      slug: parseStringOrNull(map['slug']),
      visible: map['visible_publiquement'] == true,
      statut: StatutLocalisation.fromCode(
        parseStringOrNull(map['statut_localisation']),
      ),
      cheminPublic: parseStringOrNull(map['url_publique']),
    );
  }
}

class VitrineService {
  VitrineService._();

  static final VitrineService instance = VitrineService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // 1. VITRINE & LOCALISATION
  // ---------------------------------------------------------------------------

  /// État courant de la vitrine d'une boutique du compte.
  Future<LocalisationBoutique> etat({String? espaceId}) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_biashara_boutique_etat',
          params: <String, dynamic>{'p_espace_id': espaceId},
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const VitrineException(
            'Impossible de lire l\'état de votre vitrine.',
          );
        }

        return LocalisationBoutique.fromMap(map);
      },
      'la lecture de votre vitrine',
    );
  }

  /// Enregistre la vitrine publique et la localisation.
  ///
  /// [confirmee] traduit la réponse du commerçant à la question
  /// « Cette position correspond-elle bien à l'emplacement de votre
  /// boutique ? ». Sans confirmation, la position reste « à confirmer » et
  /// l'écran public l'indique honnêtement.
  Future<ResultatVitrine> enregistrer({
    String? espaceId,
    String? adresse,
    String? quartier,
    String? avenue,
    String? numero,
    String? pointRepere,
    String? villeId,
    double? latitude,
    double? longitude,
    String? precision,
    bool confirmee = false,
    String? telephone,
    String? whatsapp,
    Map<String, dynamic>? horaires,
    String? description,
    String? logoUrl,
    String? photoUrl,
    bool visible = false,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_biashara_boutique_enregistrer',
          params: <String, dynamic>{
            'p_espace_id': espaceId,
            'p_adresse': adresse,
            'p_quartier': quartier,
            'p_avenue': avenue,
            'p_numero': numero,
            'p_point_repere': pointRepere,
            'p_ville_id': villeId,
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_precision': precision,
            'p_confirmee': confirmee,
            'p_telephone': telephone,
            'p_whatsapp': whatsapp,
            'p_horaires': horaires,
            'p_description': description,
            'p_logo_url': logoUrl,
            'p_photo_url': photoUrl,
            'p_visible': visible,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const VitrineException(
            'Votre vitrine n\'a pas pu être enregistrée. Réessayez.',
          );
        }

        return ResultatVitrine.fromMap(map);
      },
      'l\'enregistrement de votre vitrine',
    );
  }

  // ---------------------------------------------------------------------------
  // 2. PUBLICATIONS DU CATALOGUE
  // ---------------------------------------------------------------------------

  /// Liste des articles du catalogue avec leur état de publication.
  Future<EtatPublications> publications({
    String? espaceId,
    String? recherche,
    FiltrePublications filtre = FiltrePublications.tous,
    int limite = 150,
    int decalage = 0,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_biashara_publications_lister',
          params: <String, dynamic>{
            'p_espace_id': espaceId,
            'p_recherche': recherche,
            'p_filtre': filtre.code,
            'p_limite': limite,
            'p_decalage': decalage,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const VitrineException(
            'Impossible de charger vos articles.',
          );
        }

        return EtatPublications.fromMap(map);
      },
      'le chargement de vos publications',
    );
  }

  /// Publie ou retire un article du catalogue public.
  Future<void> enregistrerPublication({
    required int produitId,
    bool publie = true,
    double? prixPublic,
    String? unite,
    String? description,
    String? photo,
    String? motsCles,
    bool disponible = true,
  }) {
    return _executer(
      () async {
        await _client.rpc(
          'rpc_biashara_publication_enregistrer',
          params: <String, dynamic>{
            'p_produit_id': produitId,
            'p_publie': publie,
            'p_prix_public': prixPublic,
            'p_unite': unite,
            'p_description': description,
            'p_photo': photo,
            'p_mots_cles': motsCles,
            'p_disponible': disponible,
          },
        );
      },
      'la publication de l\'article',
    );
  }

  /// Publie ou retire PLUSIEURS articles d'un coup (sélection multiple).
  ///
  /// Renvoie le nombre d'articles traités et les erreurs éventuelles : le lot
  /// n'est jamais annulé par l'échec d'une seule ligne.
  Future<({int nbTraites, List<String> erreurs})> enregistrerPublicationLot({
    required List<Map<String, dynamic>> produits,
    bool publie = true,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_biashara_publication_lot',
          params: <String, dynamic>{
            'p_produits': produits,
            'p_publie': publie,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        final List<String> erreurs = (map?['erreurs'] is List)
            ? (map!['erreurs'] as List)
                .map((dynamic e) => e.toString())
                .toList(growable: false)
            : const <String>[];

        return (nbTraites: parseInt(map?['nb_traites']), erreurs: erreurs);
      },
      'la publication groupée',
    );
  }

  // ---------------------------------------------------------------------------
  // 3. « MA VISIBILITÉ BIASHARA »
  // ---------------------------------------------------------------------------

  /// Tableau de bord de visibilité sur une période.
  Future<VisibiliteBiashara> visibilite({
    DateTime? debut,
    DateTime? fin,
    String? espaceId,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_biashara_visibilite',
          params: <String, dynamic>{
            'p_debut': _isoJour(debut),
            'p_fin': _isoJour(fin),
            'p_espace_id': espaceId,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null) {
          throw const VitrineException(
            'Impossible de charger votre visibilité.',
          );
        }

        return VisibiliteBiashara.fromMap(map);
      },
      'le chargement de votre visibilité',
    );
  }

  /// Codes d'attribution (QR, liens, codes promotionnels).
  Future<List<LienAttribution>> attributions({String? espaceId}) async {
    try {
      final dynamic reponse = await _client.rpc(
        'rpc_biashara_attribution_lister',
        params: <String, dynamic>{'p_espace_id': espaceId},
      );
      final Map<String, dynamic>? map = parseMap(reponse);
      final List<dynamic> liste = (map?['liens'] as List?) ?? const <dynamic>[];

      return liste
          .whereType<Map>()
          .map((Map e) => LienAttribution.fromMap(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (e) {
      debugPrint('VitrineService.attributions : $e');
      return const <LienAttribution>[];
    }
  }

  /// Crée un code d'attribution (« BIA-XXXXXX »).
  Future<LienAttribution?> creerAttribution({
    String? libelle,
    TypeLienAttribution type = TypeLienAttribution.qr,
    int? produitId,
    String? espaceId,
    String? cibleUrl,
  }) async {
    final dynamic reponse = await _executer(
      () => _client.rpc('rpc_biashara_attribution_creer', params: <String, dynamic>{
        'p_libelle': libelle,
        'p_type_lien': type.code,
        'p_produit_id': produitId,
        'p_espace_id': espaceId,
        'p_cible_url': cibleUrl,
      }),
      'la création du code',
    );

    final Map<String, dynamic>? map = parseMap(reponse);
    final String? code = parseStringOrNull(map?['code']);
    if (code == null) return null;

    return LienAttribution(
      id: parseString(map?['id']),
      code: code,
      type: type,
      libelle: libelle,
      cibleUrl: cibleUrl,
      produitId: produitId,
    );
  }

  /// Supprime un code d'attribution.
  Future<void> supprimerAttribution(String id) {
    return _executer(
      () async {
        await _client.rpc(
          'rpc_biashara_attribution_supprimer',
          params: <String, dynamic>{'p_id': id},
        );
      },
      'la suppression du code',
    );
  }

  // ---------------------------------------------------------------------------
  // OUTILS INTERNES
  // ---------------------------------------------------------------------------

  /// Téléverse un logo ou une photo de devanture et renvoie son URL publique.
  ///
  /// Le fichier est rangé sous `<utilisateur>/<horodatage>.<ext>` : les
  /// policies du bucket « boutiques » n'autorisent l'écriture que dans ce
  /// dossier (mêmes règles que le bucket « articles » du module 5).
  Future<String> televerserImage(String cheminLocal) {
    return _executer(
      () async {
        final String? utilisateurId = _client.auth.currentUser?.id;
        if (utilisateurId == null) {
          throw const VitrineException(
            'Session introuvable : connectez-vous puis réessayez.',
          );
        }

        final Uint8List? octets = await lireOctetsFichierLocal(cheminLocal);
        if (octets == null) {
          throw const VitrineException(
            'Le fichier image n\'est plus accessible. Choisissez une autre '
            'photo.',
          );
        }

        final String brut = cheminLocal.split('.').last.toLowerCase();
        final String extension = cheminLocal.contains('.') &&
                brut.length <= 5 &&
                !brut.contains('/')
            ? brut
            : 'jpg';

        final String chemin = '$utilisateurId/'
            '${DateTime.now().millisecondsSinceEpoch}.$extension';

        await _client.storage.from(_bucketBoutiques).uploadBinary(
              chemin,
              octets,
              fileOptions: FileOptions(
                contentType: 'image/$extension',
                upsert: false,
              ),
            );

        return _client.storage.from(_bucketBoutiques).getPublicUrl(chemin);
      },
      'le téléversement de l\'image',
    );
  }

  /// Date « AAAA-MM-JJ » attendue par les paramètres `date` de PostgreSQL.
  static String? _isoJour(DateTime? date) {
    if (date == null) return null;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String messageErreur(String brut) {
    final String texte = brut.trim();
    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }

  Future<T> _executer<T>(Future<T> Function() action, String libelle) async {
    try {
      return await action();
    } on VitrineException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('VitrineService ($libelle) : ${e.message}');

      if (e.code == 'PGRST202' || e.code == '42883') {
        throw const VitrineException(
          'Le module « Biashara » n\'est pas installé sur la base. Exécutez '
          'supabase/migrations/20260916000040_module19_marketplace.sql.',
          type: TypeErreurVitrine.nonDeploye,
        );
      }

      final String code = e.message.split('|').first.trim().toUpperCase();
      throw VitrineException(
        messageErreur(e.message),
        type: switch (code) {
          'ACCES_REFUSE' => TypeErreurVitrine.accesRefuse,
          'POSITION_MANQUANTE' || 'POSITION_INVALIDE' =>
            TypeErreurVitrine.positionManquante,
          'PRIX_INVALIDE' || 'TITRE_MANQUANT' ||
          'DONNEES_INVALIDES' ||
          'TYPE_PUBLICITE_INCONNU' ||
          'TYPE_LIEN_INCONNU' =>
            TypeErreurVitrine.validation,
          _ => TypeErreurVitrine.inconnu,
        },
      );
    } catch (e, st) {
      debugPrint('VitrineService ($libelle) : $e\n$st');
      throw const VitrineException(
        'Impossible de contacter Biashara. Vérifiez votre connexion internet.',
        type: TypeErreurVitrine.reseau,
      );
    }
  }
}
