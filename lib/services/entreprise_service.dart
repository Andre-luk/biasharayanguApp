// lib/services/entreprise_service.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:biashara_yangu/models/activite.dart';
import 'package:biashara_yangu/models/boutique_agent.dart';
import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/fiche_entreprise.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/models/type_activite.dart';
import 'package:biashara_yangu/models/paiement_abonnement.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/models/utilisateur_entreprise.dart';
import 'package:biashara_yangu/services/espace_service.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/services/type_activite_service.dart';
import 'package:biashara_yangu/models/ville.dart';
import 'package:biashara_yangu/services/cache_lecture.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du module « Gestion des entreprises ».
///
/// [message] est toujours rédigé en français et peut être affiché tel quel
/// à l'utilisateur (SnackBar, écran d'erreur…).
class EntrepriseServiceException implements Exception {
  const EntrepriseServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Accès Supabase aux référentiels (villes, activités, groupes tarifaires)
/// et à la table `public.entreprises`.
///
/// Toutes les méthodes publiques renvoient des exceptions
/// [EntrepriseServiceException] : les écrans n'ont donc jamais à manipuler
/// une `PostgrestException`.
class EntrepriseService {
  EntrepriseService._();

  static final EntrepriseService instance = EntrepriseService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  static const Uuid _uuid = Uuid();

  // ---------------------------------------------------------------------------
  // MÉTHODES PUBLIQUES — RÉFÉRENTIELS
  // ---------------------------------------------------------------------------

  /// Toutes les villes, triées par nom.
  Future<List<Ville>> getVilles() {
    return _executer(
      () async {
        final List<dynamic> data =
            await _client.from('villes').select().order('nom', ascending: true);
        return parseMapList(data).map(Ville.fromMap).toList();
      },
      actionLibelle: 'le chargement des villes',
      messageEchec:
          'Impossible de charger la liste des villes. Vérifiez votre connexion internet.',
    );
  }

  /// Toutes les activités commerciales, triées par nom.
  Future<List<Activite>> getActivites() {
    return _executer(
      () async {
        final List<dynamic> data = await _client
            .from('activites')
            .select()
            .order('nom', ascending: true);
        return parseMapList(data).map(Activite.fromMap).toList();
      },
      actionLibelle: 'le chargement des activités',
      messageEchec:
          'Impossible de charger la liste des activités. Vérifiez votre connexion internet.',
    );
  }

  /// Groupes tarifaires d'une activité (tous si [activiteId] est `null`).
  ///
  /// [typeActivite] filtre ensuite sur le TYPE D'ACTIVITÉ du pack : une
  /// boutique ne se voit pas proposer les grilles de distribution, et
  /// inversement. Le filtrage se fait ici (et non en SQL) pour rester
  /// **fail-open** : colonne absente ou valeur inconnue → rien n'est masqué.
  Future<List<GroupeTarifaire>> getGroupesTarifaires({
    String? activiteId,
    TypeActivite? typeActivite,
  }) {
    return _executer(
      () async {
        var requete = _client.from('groupes_tarifaires').select();
        if (activiteId != null && activiteId.isNotEmpty) {
          requete = requete.eq('activite_id', activiteId);
        }

        final List<dynamic> data = await requete.order('nom', ascending: true);
        final List<GroupeTarifaire> tous =
            parseMapList(data).map(GroupeTarifaire.fromMap).toList();
        if (typeActivite == null) return tous;
        return tous
            .where((GroupeTarifaire g) => g.proposableA(typeActivite))
            .toList(growable: false);
      },
      actionLibelle: 'le chargement des groupes tarifaires',
      messageEchec:
          'Impossible de charger les groupes tarifaires. Vérifiez votre connexion internet.',
    );
  }

  // ---------------------------------------------------------------------------
  // MÉTHODES PUBLIQUES — ENTREPRISES
  // ---------------------------------------------------------------------------

  /// Toutes les entreprises, triées par nom, enrichies du nom de leur ville,
  /// de leur activité et de leur groupe tarifaire.
  ///
  /// La jointure est faite côté application (4 requêtes puis mise en
  /// correspondance en mémoire) : elle ne dépend donc d'aucune contrainte de
  /// clé étrangère détectée par PostgREST.
  Future<List<Entreprise>> getEntreprises() {
    return _executer(
      () async {
        // Les statuts ESSAI_7J / ACTIF dépassés ne basculent pas tout seuls
        // vers EXPIRE en base : on le demande au serveur avant de lire
        // (best-effort, l'échec est ignoré).
        await _actualiserStatutsExpires();

        // 🔌 HORS LIGNE — la liste des entreprises (et ses tables de
        // référence) est la PREMIÈRE chose lue à l'ouverture : sans elle,
        // l'application paraît vide alors que tout est déjà sur l'appareil.
        // On garde donc les cinq réponses et on les rejoue si le réseau
        // manque. Une entreprise créée hors ligne arrivera au prochain
        // passage : elle n'est jamais inventée ici.
        const String cleListe = 'entreprises_liste';
        List<dynamic> reponses;
        try {
          reponses = await Future.wait<dynamic>([
            _client.from('entreprises').select().order('nom', ascending: true),
            _client.from('villes').select(),
            _client.from('activites').select(),
            _client.from('groupes_tarifaires').select(),
            // Responsable + téléphone (correctif 21). `select()` sans liste de
            // colonnes : reste compatible même si la colonne `telephone` n'a
            // pas encore été créée en base.
            _client.from('utilisateurs').select(),
          ]).timeout(CacheLecture.delaiReseau);
          await CacheLecture.instance.memoriser(
            CacheLecture.cleRpc(cleListe),
            reponses,
          );
        } catch (e) {
          final dynamic cache =
              await CacheLecture.instance.relire(CacheLecture.cleRpc(cleListe));
          if (cache is! List || cache.length < 5) {
            debugPrint('EntrepriseService.getEntreprises hors ligne : $e');
            rethrow;
          }
          debugPrint('EntrepriseService.getEntreprises : liste locale ($e)');
          reponses = cache;
        }

        final Map<String, String> villes = {
          for (final Ville ville
              in parseMapList(reponses[1]).map(Ville.fromMap))
            ville.id: ville.nom,
        };
        final Map<String, String> activites = {
          for (final Activite activite
              in parseMapList(reponses[2]).map(Activite.fromMap))
            activite.id: activite.nom,
        };
        final Map<String, GroupeTarifaire> groupes = {
          for (final GroupeTarifaire groupe
              in parseMapList(reponses[3]).map(GroupeTarifaire.fromMap))
            groupe.id: groupe,
        };

        // Responsable de chaque entreprise : on privilégie le patron
        // (sans parent_id), sinon le premier utilisateur rattaché.
        final Map<String, Map<String, dynamic>> responsables =
            <String, Map<String, dynamic>>{};
        for (final Map<String, dynamic> utilisateur
            in parseMapList(reponses[4])) {
          final String? entrepriseId =
              parseStringOrNull(utilisateur['entreprise_id']);
          if (entrepriseId == null || entrepriseId.isEmpty) continue;

          final bool estPatron =
              parseStringOrNull(utilisateur['parent_id']) == null;
          final Map<String, dynamic>? existant = responsables[entrepriseId];
          final bool existantEstPatron = existant != null &&
              parseStringOrNull(existant['parent_id']) == null;

          if (existant == null || (estPatron && !existantEstPatron)) {
            responsables[entrepriseId] = utilisateur;
          }
        }

        String? nomResponsable(Map<String, dynamic>? utilisateur) {
          if (utilisateur == null) return null;
          final String prenom =
              (parseStringOrNull(utilisateur['prenom']) ?? '').trim();
          final String nom =
              (parseStringOrNull(utilisateur['nom']) ?? '').trim();
          final String complet = <String>[
            if (prenom.isNotEmpty) prenom,
            if (nom.isNotEmpty) nom
          ].join(' ');
          if (complet.isNotEmpty) return complet;
          final String? email = parseStringOrNull(utilisateur['email']);
          return (email == null || email.isEmpty) ? null : email;
        }

        return parseMapList(reponses[0]).map((Map<String, dynamic> map) {
          final Entreprise entreprise = Entreprise.fromMap(map);
          final GroupeTarifaire? groupe = groupes[entreprise.groupeTarifaireId];
          final Map<String, dynamic>? responsable = responsables[entreprise.id];

          return entreprise.copyWith(
            villeNom: villes[entreprise.villeId],
            activiteNom: activites[entreprise.activiteId],
            groupeTarifaireNom: groupe?.nom,
            groupeTarifaireDureeJours: groupe?.dureeAbonnementJours,
            responsableNom: nomResponsable(responsable),
            telephone: responsable == null
                ? null
                : parseStringOrNull(responsable['telephone']),
          );
        }).toList();
      },
      actionLibelle: 'le chargement des entreprises',
      messageEchec:
          'Impossible de charger la liste des entreprises. Vérifiez votre connexion internet.',
    );
  }

  /// 🏪 AUTO-RÉPARATION (correctifs 20/21) — garantit qu'un PATRON possède
  /// son entreprise.
  ///
  /// Idempotent : côté serveur, `rpc_entreprise_creer` ne fait rien si
  /// l'entreprise existe déjà (`deja: true`). Utilisé après la connexion
  /// pour réparer les inscriptions dont la création avait été bloquée.
  Future<void> assurerEntreprise() async {
    try {
      await _client.rpc('rpc_entreprise_creer');
    } catch (e) {
      // Best-effort : ne doit jamais empêcher une connexion.
      debugPrint('assurerEntreprise ignoré : $e');
    }
  }

  /// Recherche une entreprise par son identifiant, ou `null` si elle n'existe
  /// plus.
  ///
  /// L'implémentation réutilise [getEntreprises] afin de bénéficier de la même
  /// jointure (villes / activités / groupes tarifaires) : le volume de données
  /// d'un espace administrateur reste faible, la cohérence prime sur
  /// l'optimisation.
  Future<Entreprise?> getEntrepriseById(String id) async {
    final List<Entreprise> entreprises = await getEntreprises();

    for (final Entreprise entreprise in entreprises) {
      if (entreprise.id == id) return entreprise;
    }
    return null;
  }

  /// Crée une entreprise avec les règles métier du Module 1 :
  ///
  /// - `statut` = `ESSAI_7J`
  /// - `montant_total_du` = montant de l'abonnement du groupe tarifaire
  /// - `montant_deja_paye` = 0
  /// - `solde_restant` = `montant_total_du`
  /// - `date_activation` = maintenant (UTC)
  /// - `date_expiration` = maintenant + `duree_essai_jours`
  Future<Entreprise> createEntreprise({
    required String nom,
    required String villeId,
    required String activiteId,
    required GroupeTarifaire groupeTarifaire,
  }) {
    return _executer(
      () async {
        final DateTime maintenant = DateTime.now().toUtc();
        final double montantTotalDu = calculerMontantTotalDu(groupeTarifaire);
        final DateTime dateExpiration =
            maintenant.add(Duration(days: groupeTarifaire.dureeEssaiJours));

        final Map<String, dynamic> reponse = await _client
            .from('entreprises')
            .insert({
              // Identifiant généré côté application : la colonne `id` peut ne
              // pas avoir de valeur par défaut côté Supabase, et l'insertion
              // échouerait alors silencieusement.
              'id': _uuid.v4(),
              'nom': nom.trim(),
              'ville_id': villeId,
              'activite_id': activiteId,
              'groupe_tarifaire_id': groupeTarifaire.id,
              'statut': StatutAbonnement.essai7j.code,
              'montant_total_du': montantTotalDu,
              'montant_deja_paye': 0,
              // ⚠️ `solde_restant` est une colonne GÉNÉRÉE en base : jamais
              // dans un insert/update (« can only be updated to default »).
              'date_activation': maintenant.toIso8601String(),
              'date_expiration': dateExpiration.toIso8601String(),
              'created_at': maintenant.toIso8601String(),
              'updated_at': maintenant.toIso8601String(),
            })
            .select()
            .single();

        return Entreprise.fromMap(reponse);
      },
      actionLibelle: "la création de l'entreprise",
      messageEchec:
          "Impossible de créer l'entreprise. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  /// Met à jour les informations d'une entreprise.
  ///
  /// Si le groupe tarifaire change, la facturation suit : `montant_total_du`
  /// est recalculé et `solde_restant` est réajusté en conservant le montant
  /// déjà payé. Sinon, les montants existants sont laissés intacts.
  Future<void> updateEntreprise({
    required Entreprise entreprise,
    required String nom,
    required String villeId,
    required String activiteId,
    required GroupeTarifaire groupeTarifaire,
  }) {
    return _executer(
      () async {
        final Map<String, dynamic> payload = <String, dynamic>{
          'nom': nom.trim(),
          'ville_id': villeId,
          'activite_id': activiteId,
          'groupe_tarifaire_id': groupeTarifaire.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };

        if (entreprise.groupeTarifaireId != groupeTarifaire.id) {
          // ⚠️ Le solde est recalculé par la BASE (colonne générée) : on ne
          // met à jour que le montant total dû — sinon erreur
          // « column "solde_restant" can only be updated to default ».
          payload['montant_total_du'] = calculerMontantTotalDu(groupeTarifaire);
        }

        await _client
            .from('entreprises')
            .update(payload)
            .eq('id', entreprise.id);
      },
      actionLibelle: "la mise à jour de l'entreprise",
      messageEchec:
          "Impossible d'enregistrer les modifications. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  /// Change le statut d'une entreprise (suspension / réactivation).
  ///
  /// Les dates d'activation et d'expiration ne sont volontairement pas
  /// modifiées : une réactivation ne prolonge pas l'abonnement.
  Future<void> changerStatut({
    required String id,
    required StatutAbonnement statut,
  }) {
    return _executer(
      () async {
        await _client.from('entreprises').update({
          'statut': statut.code,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);
      },
      actionLibelle: 'le changement de statut',
      messageEchec:
          "Impossible de modifier le statut de l'entreprise. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  /// Montant total dû à la création d'une entreprise.
  ///
  /// Règle métier : **frais d'ouverture + montant de l'abonnement**.
  ///
  /// Pour ne facturer que l'abonnement, remplacer le corps de cette méthode
  /// par : `return groupe.montantAbonnement;`
  double calculerMontantTotalDu(GroupeTarifaire groupe) {
    return groupe.fraisOuverture + groupe.montantAbonnement;
  }

  // ---------------------------------------------------------------------------
  // 🆕 CORRECTIF 73 — CRÉATION COMPLÈTE ET FICHE UNIQUE
  // ---------------------------------------------------------------------------

  /// Crée l'entreprise **et** le compte de son propriétaire, en une fois.
  ///
  /// Côté serveur (`rpc_admin_entreprise_creer`), tout se passe dans la même
  /// opération : compte Auth + profil PROPRIÉTAIRE, entreprise, espace typé,
  /// dossier d'activation, les deux prix et la durée d'essai. Si une seule
  /// validation échoue, **rien** n'est créé : jamais d'entreprise orpheline.
  ///
  /// Le créateur (`cree_par`) est enregistré automatiquement : c'est
  /// l'utilisateur connecté.
  Future<ResultatCreationEntreprise> creerEntrepriseAvecProprietaire({
    required String nom,
    required String proprietaireNom,
    required String proprietaireEmail,
    required String motDePasse,
    String? proprietairePrenom,
    String? proprietaireTelephone,
    String? villeId,
    String? activiteId,
    String? groupeTarifaireId,
    String typeEspace = 'boutique',
    double? prixInstallation,
    double? prixMensuel,
    String? note,
  }) {
    return _executer(
      () async {
        final dynamic reponse = await _client.rpc(
          'rpc_admin_entreprise_creer',
          params: <String, dynamic>{
            'p_nom': nom.trim(),
            'p_ville_id': villeId,
            'p_activite_id': activiteId,
            'p_groupe_tarifaire_id': groupeTarifaireId,
            'p_type_espace': typeEspace,
            'p_proprietaire_nom': proprietaireNom.trim(),
            'p_proprietaire_prenom': (proprietairePrenom ?? '').trim().isEmpty
                ? null
                : proprietairePrenom!.trim(),
            'p_proprietaire_email': proprietaireEmail.trim().toLowerCase(),
            'p_proprietaire_telephone':
                (proprietaireTelephone ?? '').trim().isEmpty
                    ? null
                    : proprietaireTelephone!.trim(),
            'p_mot_de_passe': motDePasse,
            'p_prix_installation': prixInstallation,
            'p_prix_mensuel': prixMensuel,
            'p_note': note,
          },
        );

        final Map<String, dynamic>? map = parseMap(reponse);
        if (map == null || parseString(map['entreprise_id']).isEmpty) {
          throw const EntrepriseServiceException(
            'Le serveur a r\u00e9pondu de fa\u00e7on inattendue. '
            'V\u00e9rifiez la liste des entreprises avant de recommencer.',
          );
        }

        return ResultatCreationEntreprise.depuisJson(map);
      },
      actionLibelle: "la cr\u00e9ation du compte",
      messageEchec:
          'Impossible de cr\u00e9er le compte. V\u00e9rifiez votre connexion internet puis r\u00e9essayez.',
    );
  }

  /// LA FICHE UNIQUE : abonnement, installation, suivi et avance.
  ///
  /// Renvoie `null` si la réponse est illisible ; lève une exception métier
  /// explicite si la migration n'est pas encore exécutée.
  Future<FicheEntreprise?> chargerFiche(String entrepriseId) async {
    try {
      final dynamic reponse = await _client.rpc(
        'rpc_entreprise_fiche',
        params: <String, dynamic>{'p_entreprise_id': entrepriseId},
      );
      return FicheEntreprise.depuisJson(reponse);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' ||
          e.message.toLowerCase().contains('schema cache')) {
        throw const EntrepriseServiceException(
          'La fiche compl\u00e8te n\u2019est pas encore install\u00e9e en base. '
          'Ex\u00e9cutez la migration 73, puis r\u00e9essayez.',
        );
      }
      throw EntrepriseServiceException(
          _messagePostgrest(e, 'le chargement de la fiche'));
    }
  }

  // ------------------------------------------------------------------------
  // LES BOUTIQUES DE L'AGENT (correctif 76)
  // ------------------------------------------------------------------------

  /// Les boutiques de l'agent connecté, avec le suivi de leur abonnement.
  ///
  /// Renvoie les comptes dont il est le référent (`agent_id`), qu'il a créés
  /// (`cree_par`) ou dont il a traité un dossier — avec l'étape d'activation,
  /// l'échéance, les jours restants, les montants et le solde.
  ///
  /// LECTURE SEULE : encaisser et activer restent l'affaire de la Finance.
  Future<MesBoutiquesAgent> mesBoutiquesAgent() async {
    try {
      final dynamic reponse = await _client.rpc('rpc_agent_mes_boutiques');
      final MesBoutiquesAgent? resultat = MesBoutiquesAgent.depuisJson(reponse);
      if (resultat == null) {
        throw const EntrepriseServiceException(
            'Réponse du serveur illisible pour vos boutiques.');
      }
      return resultat;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' ||
          e.message.toLowerCase().contains('schema cache')) {
        throw const EntrepriseServiceException(
          'Le suivi des boutiques n\u2019est pas encore installé en base. '
          'Exécutez la migration 76, puis réessayez.',
        );
      }
      throw EntrepriseServiceException(
          _messagePostgrest(e, 'le chargement de vos boutiques'));
    }
  }

  /// Fixe les DEUX prix d'une entreprise (correctif 60).
  ///
  /// Un param\u00e8tre laiss\u00e9 \u00e0 `null` n'est pas modifi\u00e9.
  Future<void> definirPrix({
    required String entrepriseId,
    double? installation,
    double? mensuel,
    String? note,
  }) {
    return _executer(
      () async {
        await _client.rpc(
          'rpc_abonnement_definir_prix',
          params: <String, dynamic>{
            'p_entreprise_id': entrepriseId,
            'p_installation': installation,
            'p_mensuel': mensuel,
            'p_note': note,
          },
        );
      },
      actionLibelle: 'la mise \u00e0 jour des prix',
      messageEchec:
          'Impossible d\u2019enregistrer les prix. V\u00e9rifiez votre connexion internet puis r\u00e9essayez.',
    );
  }

  /// 🏪 Définit le TYPE D'ACTIVITÉ d'une entreprise (boutique / distribution).
  ///
  /// `null` remet le type à « non renseigné » : l'application retrouve alors
  /// son comportement historique (toutes les cartes visibles).
  Future<void> definirTypeActivite(String entrepriseId, TypeActivite? type) {
    return _executer(
      () async {
        await _client.rpc(
          'rpc_entreprise_definir_type_activite',
          params: <String, dynamic>{
            'p_entreprise_id': entrepriseId,
            'p_type': type?.code,
          },
        );

        // ⚙️ CORRECTIF 96 — l'ENVIRONNEMENT suit immédiatement le type.
        // Sans ce rafraîchissement, passer une entreprise en distribution
        // n'affichait Tournées / Ma tournée / Récipients qu'après redémarrage.
        try {
          await EspaceService.instance.chargerSilencieux();

          if (EspaceService.instance.actif?.id == entrepriseId) {
            await ModulesService.instance.chargerSilencieux();
            await TypeActiviteService.instance.charger();
          }
        } catch (e) {
          debugPrint('definirTypeActivite : rafraîchissement ignoré ($e)');
        }
      },
      actionLibelle: "la définition du type d'activité",
      messageEchec:
          "Impossible d'enregistrer le type d'activité. Vérifiez votre connexion internet.",
    );
  }

  /// 🪙 Fixe les quotas IA mensuels d'une entreprise (`null` = valeur du pack).
  ///
  /// Ces quotas sont crédités automatiquement à chaque cycle d'abonnement
  /// payé : le client n'a rien à réclamer.
  Future<void> definirQuotasIa({
    required String entrepriseId,
    int? quotas,
    String? note,
  }) {
    return _executer(
      () async {
        await _client.rpc(
          'rpc_abonnement_definir_quotas_ia',
          params: <String, dynamic>{
            'p_entreprise_id': entrepriseId,
            'p_quotas': quotas,
            'p_note': note,
          },
        );
      },
      actionLibelle: 'la mise à jour des quotas IA',
      messageEchec:
          'Impossible d\'enregistrer les quotas IA. Vérifiez votre connexion internet.',
    );
  }

  /// 🗑️ Supprime une entreprise, ses données et ses comptes.
  ///
  /// Réservé au Super Administrateur côté serveur ; [confirmation] doit
  /// valoir « SUPPRIMER ». Lève une erreur explicite si des données liées
  /// bloquent la suppression.
  Future<Map<String, dynamic>> supprimerEntreprise({
    required String entrepriseId,
    required String confirmation,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'rpc_entreprise_supprimer',
        params: <String, dynamic>{
          'p_entreprise': entrepriseId,
          'p_confirmation': confirmation,
        },
      );
      final Map<String, dynamic>? json = parseMap(reponse);
      if (json == null || json['ok'] != true) {
        throw const EntrepriseServiceException(
          "La suppression n'a pas été confirmée par le serveur.",
        );
      }
      return json;
    } on PostgrestException catch (e) {
      final String brut = e.message;
      final int barre = brut.indexOf('|');
      throw EntrepriseServiceException(
        barre >= 0 ? brut.substring(barre + 1).trim() : brut,
      );
    } catch (e) {
      if (e is EntrepriseServiceException) rethrow;
      debugPrint('EntrepriseService.supprimerEntreprise : $e');
      throw const EntrepriseServiceException(
        'Suppression impossible : vérifiez votre connexion internet.',
      );
    }
  }

  /// Enregistre un encaissement sur l'abonnement d'une entreprise.
  ///
  /// Impacte `montant_deja_paye` (augmenté) et `solde_restant` (diminué), et
  /// ajoute une ligne d'historique dans `paiements_abonnement`.
  ///
  /// Si [prolonger] vaut `true`, l'abonnement est en outre prolongé de
  /// `duree_abonnement_jours` (durée de la grille tarifaire), son statut passe
  /// à `ACTIF` et `date_activation` est renseignée si elle était vide. La
  /// prolongation repart de la date d'expiration si elle est encore future,
  /// de maintenant sinon : un abonnement échu ne cumule pas de retard.
  ///
  /// [montant] doit être strictement positif et ne peut pas dépasser le solde
  /// restant.
  Future<Entreprise> enregistrerPaiement({
    required Entreprise entreprise,
    required double montant,
    bool prolonger = false,
  }) {
    return _executer(
      () async {
        if (montant <= 0) {
          throw const EntrepriseServiceException(
            'Le montant encaissé doit être supérieur à zéro.',
          );
        }

        final Entreprise? resultatRpc = await _tenterEncaissementRpc(
          entrepriseId: entreprise.id,
          montant: montant,
          prolonger: prolonger,
        );

        final Entreprise resultat = resultatRpc ??
            await _encaisserEnApplicatif(
              entreprise: entreprise,
              montant: montant,
              prolonger: prolonger,
            );

        // On conserve les libellés de jointure déjà chargés : ils ne sont pas
        // renvoyés par l'insertion / la mise à jour.
        return resultat.copyWith(
          villeNom: entreprise.villeNom,
          activiteNom: entreprise.activiteNom,
          groupeTarifaireNom: entreprise.groupeTarifaireNom,
          groupeTarifaireDureeJours: entreprise.groupeTarifaireDureeJours,
        );
      },
      actionLibelle: "l'enregistrement du paiement",
      messageEchec:
          "Impossible d'enregistrer le paiement. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  // ---------------------------------------------------------------------------
  // HISTORIQUE DES PAIEMENTS
  // ---------------------------------------------------------------------------

  /// Historique des encaissements d'une entreprise, du plus récent au plus
  /// ancien.
  ///
  /// Renvoie une liste vide si la table n'est pas encore installée : l'absence
  /// d'historique ne doit pas empêcher l'affichage de la fiche entreprise.
  Future<List<PaiementAbonnement>> getPaiements(String entrepriseId) async {
    try {
      final List<dynamic> data = await _client
          .from('paiements_abonnement')
          .select()
          .eq('entreprise_id', entrepriseId)
          .order('created_at', ascending: false);

      final List<PaiementAbonnement> paiements =
          parseMapList(data).map(PaiementAbonnement.fromMap).toList();

      final Map<String, String> noms = await _chargerNomsUtilisateurs();

      return paiements
          .map(
            (PaiementAbonnement paiement) => paiement.copyWith(
              enregistreParNom: noms[paiement.enregistrePar],
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('EntrepriseService.getPaiements (ignoré): $e');
      return const <PaiementAbonnement>[];
    }
  }

  /// Noms des utilisateurs, pour afficher l'auteur d'un encaissement.
  /// Best-effort : renvoie une table vide en cas d'échec.
  Future<Map<String, String>> _chargerNomsUtilisateurs() async {
    try {
      final List<UtilisateurEntreprise> utilisateurs = await getUtilisateurs();

      return <String, String>{
        for (final UtilisateurEntreprise utilisateur in utilisateurs)
          if (utilisateur.id.isNotEmpty) utilisateur.id: utilisateur.nomComplet,
      };
    } catch (e) {
      debugPrint('EntrepriseService._chargerNomsUtilisateurs (ignoré): $e');
      return const <String, String>{};
    }
  }

  // ---------------------------------------------------------------------------
  // RATTACHEMENT UTILISATEURS <-> ENTREPRISES
  // ---------------------------------------------------------------------------

  /// Identifiants des utilisateurs rattachés à une entreprise.
  ///
  /// Best-effort : en cas d'échec, l'écran de détail doit continuer à
  /// s'afficher (le rattachement est un confort, pas une donnée vitale).
  Future<Set<String>> getUtilisateursRattaches(String entrepriseId) async {
    try {
      final List<dynamic> data = await _client
          .from('utilisateurs')
          .select('id')
          .eq('entreprise_id', entrepriseId);

      return <String>{
        for (final Map<String, dynamic> ligne in parseMapList(data))
          if (parseStringOrNull(ligne['id']) != null) parseString(ligne['id']),
      };
    } catch (e) {
      debugPrint('EntrepriseService.getUtilisateursRattaches (ignoré): $e');
      return <String>{};
    }
  }

  /// Tous les utilisateurs, avec leur éventuel rattachement à une entreprise.
  ///
  /// Utilisé par la feuille de rattachement : une seule requête, puis la mise
  /// en correspondance se fait en mémoire.
  Future<List<UtilisateurEntreprise>> getUtilisateurs() {
    return _executer(
      () async {
        final List<dynamic> data = await _client
            .from('utilisateurs')
            .select(
                'id, prenom, nom, email, role, new_role, parent_id, entreprise_id')
            .order('nom', ascending: true);

        return parseMapList(data).map(UtilisateurEntreprise.fromMap).toList();
      },
      actionLibelle: 'le chargement des utilisateurs',
      messageEchec:
          'Impossible de charger la liste des utilisateurs. Vérifiez votre connexion internet.',
    );
  }

  /// Rattache un utilisateur à une entreprise.
  ///
  /// S'appuie sur la colonne existante `public.utilisateurs.entreprise_id`.
  /// Un utilisateur n'appartient qu'à une seule entreprise : le rattachement
  /// remplace donc un éventuel rattachement précédent.
  Future<void> rattacherUtilisateur({
    required String entrepriseId,
    required String userId,
  }) {
    return _executer(
      () async {
        await _client
            .from('utilisateurs')
            .update({'entreprise_id': entrepriseId}).eq('id', userId);
      },
      actionLibelle: "le rattachement de l'utilisateur",
      messageEchec: "Impossible de rattacher cet utilisateur à l'entreprise.",
    );
  }

  /// Détache un utilisateur de son entreprise.
  Future<void> detacherUtilisateur({required String userId}) {
    return _executer(
      () async {
        await _client
            .from('utilisateurs')
            .update({'entreprise_id': null}).eq('id', userId);
      },
      actionLibelle: "le détachement de l'utilisateur",
      messageEchec: "Impossible de détacher cet utilisateur de l'entreprise.",
    );
  }

  // ---------------------------------------------------------------------------
  // CONTRÔLE D'ACCÈS (CONNEXION)
  // ---------------------------------------------------------------------------

  /// Vérifie si un utilisateur peut accéder à l'application au regard des
  /// entreprises auxquelles il est rattaché.
  ///
  /// Renvoie `null` si l'accès est autorisé, sinon le message à afficher.
  ///
  /// ⚠️ La méthode est **fail-open** : toute erreur (fonction SQL absente,
  /// réseau, droits insuffisants) laisse l'accès ouvert. Il vaut mieux laisser
  /// entrer un utilisateur dont l'entreprise est suspendue que bloquer toute
  /// la base. De même, un utilisateur rattaché à **aucune** entreprise n'est
  /// jamais bloqué — sinon tous les comptes existants seraient bloqués tant que
  /// le rattachement n'a pas été fait.
  Future<String?> verifierAccesUtilisateur(String userId) async {
    try {
      final List<Map<String, dynamic>> lignes = parseMapList(
        await _client.rpc(
          'rpc_entreprises_de_utilisateur',
          params: {'p_user_id': userId},
        ),
      );

      return evaluerAcces(lignes);
    } catch (e) {
      debugPrint('EntrepriseService.verifierAccesUtilisateur (fail-open): $e');
      return null;
    }
  }

  /// Décision d'accès à partir des entreprises rattachées à un utilisateur.
  ///
  /// Fonction **pure**, sans accès réseau : directement testable.
  ///
  /// Renvoie `null` si l'accès est autorisé, sinon le message à afficher.
  static String? evaluerAcces(
    List<Map<String, dynamic>> lignes, {
    DateTime? maintenant,
  }) {
    // Aucune entreprise rattachée : on ne bloque pas (voir
    // [verifierAccesUtilisateur]).
    if (lignes.isEmpty) return null;

    final DateTime reference = maintenant ?? DateTime.now();

    bool auMoinsUneActive = false;
    bool aSuspendu = false;
    bool aExpire = false;

    for (final Map<String, dynamic> ligne in lignes) {
      final StatutAbonnement statut = StatutAbonnement.fromCode(
        parseStringOrNull(ligne['statut']),
      );
      final DateTime? expiration =
          parseDateTimeOrNull(ligne['date_expiration']);

      if (statut == StatutAbonnement.suspendu) {
        aSuspendu = true;
        continue;
      }

      // La base peut ne pas avoir encore basculé un abonnement échu en
      // EXPIRE : on applique la même règle que [Entreprise.statutEffectif].
      final bool echu = statut == StatutAbonnement.expire ||
          ((statut == StatutAbonnement.essai7j ||
                  statut == StatutAbonnement.actif) &&
              expiration != null &&
              expiration.isBefore(reference));

      if (!echu) {
        auMoinsUneActive = true;
        break;
      }

      aExpire = true;
    }

    if (auMoinsUneActive) return null;

    if (aSuspendu) {
      return "L'accès de votre entreprise a été suspendu par l'administrateur. "
          'Contactez-le pour le réactiver.';
    }

    if (aExpire) {
      return "L'abonnement de votre entreprise a expiré. "
          'Contactez votre administrateur pour le renouveler.';
    }

    return 'Votre accès est bloqué. Contactez votre administrateur.';
  }

  // ---------------------------------------------------------------------------
  // TEMPS RÉEL
  // ---------------------------------------------------------------------------

  /// S'abonne aux modifications de `public.entreprises`.
  ///
  /// Renvoie le canal créé : l'appelant **doit** le libérer avec
  /// [arreterEcoute], en général dans `dispose()`.
  ///
  /// Si la table n'est pas publiée dans `supabase_realtime`, aucun événement
  /// n'arrive — l'abonnement reste simplement inactif, sans lever d'erreur.
  RealtimeChannel ecouterChangements(void Function() onChange) {
    // Nom unique : évite tout conflit si l'écran est ouvert plusieurs fois
    // d'affilée avant que le canal précédent ne soit libéré.
    final RealtimeChannel canal = _client.channel(
      'entreprises-admin-${DateTime.now().microsecondsSinceEpoch}',
    );

    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'entreprises',
          callback: (PostgresChangePayload payload) {
            try {
              onChange();
            } catch (e) {
              debugPrint('EntrepriseService temps réel (callback): $e');
            }
          },
        )
        .subscribe();

    return canal;
  }

  /// Libère un canal créé par [ecouterChangements].
  Future<void> arreterEcoute(RealtimeChannel canal) async {
    try {
      await _client.removeChannel(canal);
    } catch (e) {
      debugPrint('EntrepriseService.arreterEcoute: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // OUTILS INTERNES — PAIEMENT
  // ---------------------------------------------------------------------------

  /// Tentative d'encaissement via la fonction SQL `rpc_enregistrer_paiement`
  /// (fournie dans `supabase/migrations/`).
  ///
  /// Renvoie `null` si la fonction n'est pas installée sur la base, afin de
  /// laisser la main au repli applicatif.
  Future<Entreprise?> _tenterEncaissementRpc({
    required String entrepriseId,
    required double montant,
    required bool prolonger,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'rpc_enregistrer_paiement',
        params: {
          'p_entreprise_id': entrepriseId,
          'p_montant': montant,
          'p_prolonger': prolonger,
        },
      );

      final Map<String, dynamic>? ligne = reponse is List
          ? (reponse.isEmpty ? null : parseMap(reponse.first))
          : parseMap(reponse);

      return ligne == null ? null : Entreprise.fromMap(ligne);
    } on PostgrestException catch (e) {
      if (!_rpcIndisponible(e)) rethrow;

      debugPrint(
        'rpc_enregistrer_paiement absente de la base (${e.code}) : repli applicatif.',
      );
      return null;
    }
  }

  /// Repli utilisé lorsque la fonction SQL n'est pas installée : lecture puis
  /// mise à jour depuis l'application.
  ///
  /// Suffisant pour un espace administrateur, mais deux encaissements
  /// strictement simultanés peuvent se chevaucher. Le RPC supprime ce risque :
  /// pensez à exécuter `supabase/migrations/20260916000000_module1_entreprises.sql`.
  Future<Entreprise> _encaisserEnApplicatif({
    required Entreprise entreprise,
    required double montant,
    required bool prolonger,
  }) async {
    final dynamic ligneBrute = await _client
        .from('entreprises')
        .select('montant_total_du, montant_deja_paye')
        .eq('id', entreprise.id)
        .maybeSingle();

    final Map<String, dynamic>? ligne = parseMap(ligneBrute);
    if (ligne == null) {
      throw const EntrepriseServiceException(
        "Cette entreprise n'existe plus dans la base de données.",
      );
    }

    final DateTime maintenant = DateTime.now();
    final double dejaPaye = parseDouble(ligne['montant_deja_paye']);
    final double nouveauPaye = dejaPaye + montant;

    int prolongationJours = 0;

    final Map<String, dynamic> nouvellesValeurs = <String, dynamic>{
      // ⚠️ `solde_restant` est généré par la base : jamais écrasé ici.
      'montant_deja_paye': nouveauPaye,
      'updated_at': maintenant.toUtc().toIso8601String(),
    };

    if (prolonger) {
      prolongationJours = entreprise.groupeTarifaireDureeJours ?? 0;

      final DateTime? expiration = entreprise.dateExpiration;
      final DateTime base =
          (expiration == null || expiration.isBefore(maintenant))
              ? maintenant
              : expiration;

      nouvellesValeurs['date_expiration'] =
          base.add(Duration(days: prolongationJours)).toUtc().toIso8601String();
      nouvellesValeurs['date_activation'] =
          (entreprise.dateActivation ?? maintenant).toUtc().toIso8601String();
      nouvellesValeurs['statut'] = StatutAbonnement.actif.code;
    }

    final dynamic misAJourBrut = await _client
        .from('entreprises')
        .update(nouvellesValeurs)
        .eq('id', entreprise.id)
        .select()
        .single();

    final Map<String, dynamic>? misAJour = parseMap(misAJourBrut);
    if (misAJour == null) {
      throw const EntrepriseServiceException(
        "Impossible de relire l'entreprise après l'encaissement.",
      );
    }

    final Entreprise resultat = Entreprise.fromMap(misAJour);

    // Historique : best-effort. Si la table n'est pas encore installée,
    // l'encaissement lui-même reste valide.
    try {
      await _client.from('paiements_abonnement').insert({
        'entreprise_id': entreprise.id,
        'montant': montant,
        'total_apres': resultat.montantDejaPaye,
        'solde_apres': resultat.soldeRestant,
        'prolongation_jours': prolongationJours,
      });
    } catch (e) {
      debugPrint('Historique du paiement non enregistré (ignoré): $e');
    }

    return resultat;
  }

  /// Vrai si l'erreur PostgREST signifie « cette fonction n'existe pas ».
  bool _rpcIndisponible(PostgrestException e) {
    const Set<String> codes = <String>{
      'PGRST202', // introuvable dans le cache de schéma de PostgREST
      '42883', // undefined_function (PostgreSQL)
    };

    if (codes.contains(e.code)) return true;

    final String brut = e.message.toLowerCase();
    return brut.contains('could not find the function') ||
        brut.contains('does not exist');
  }

  /// Demande à Supabase de passer en `EXPIRE` les abonnements dont la date
  /// d'expiration est dépassée.
  ///
  /// Best-effort : si la fonction SQL n'est pas installée, ou si les droits
  /// manquent, l'erreur est ignorée — l'affichage reste correct grâce à
  /// [Entreprise.statutEffectif].
  Future<void> _actualiserStatutsExpires() async {
    try {
      await _client.rpc('rpc_actualiser_statuts_abonnements');
    } catch (e) {
      debugPrint('EntrepriseService._actualiserStatutsExpires (ignoré): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // OUTILS INTERNES — ERREURS
  // ---------------------------------------------------------------------------

  /// Exécute [action] en traduisant toute erreur en
  /// [EntrepriseServiceException] dont le message est prêt à être affiché.
  Future<T> _executer<T>(
    Future<T> Function() action, {
    required String actionLibelle,
    required String messageEchec,
  }) async {
    try {
      return await action();
    } on EntrepriseServiceException {
      // Message déjà propre : on ne le remballe pas.
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint(
          'EntrepriseService ($actionLibelle) PostgrestException: ${e.code} ${e.message}');
      throw EntrepriseServiceException(_messagePostgrest(e, actionLibelle));
    } on AuthException catch (e) {
      debugPrint(
          'EntrepriseService ($actionLibelle) AuthException: ${e.message}');
      throw const EntrepriseServiceException(
        'Votre session a expiré. Veuillez vous reconnecter.',
      );
    } catch (e, st) {
      debugPrint('EntrepriseService ($actionLibelle): $e\n$st');
      throw EntrepriseServiceException(messageEchec);
    }
  }

  /// Traduit une erreur PostgREST en message français compréhensible.
  String _messagePostgrest(PostgrestException e, String actionLibelle) {
    final String? code = e.code;
    final String brut = e.message.toLowerCase();

    switch (code) {
      case '23505':
        return 'Cet enregistrement existe déjà dans la base de données.';
      case '23503':
        return "La ville, l'activité ou le groupe tarifaire sélectionné n'existe pas dans la base de données.";
      case '23502':
        return 'Un champ obligatoire est manquant. Vérifiez le formulaire.';
      case '22P02':
        return "La valeur transmise n'est pas valide pour la base de données.";
      case 'PGRST116':
        return "L'entreprise demandée est introuvable.";
    }

    if (code == '42501' ||
        brut.contains('permission') ||
        brut.contains('policy')) {
      return "Accès refusé : votre compte n'a pas les droits nécessaires pour $actionLibelle.";
    }
    if (code == '42P01' ||
        brut.contains('does not exist') ||
        brut.contains('could not find the table')) {
      return "La base de données est incomplète : une table nécessaire au module Entreprises est introuvable.";
    }
    if (brut.contains('failed host lookup') ||
        brut.contains('socket') ||
        brut.contains('network') ||
        brut.contains('connection')) {
      return 'Connexion impossible. Vérifiez votre accès internet puis réessayez.';
    }

    // Messages levés explicitement par les fonctions SQL du module.
    if (brut.contains('montant_superieur')) {
      return 'Le montant saisi dépasse le solde restant de cette entreprise.';
    }
    if (brut.contains('montant_invalide')) {
      return 'Le montant encaissé doit être supérieur à zéro.';
    }
    if (brut.contains('entreprise_introuvable')) {
      return "Cette entreprise n'existe plus dans la base de données.";
    }
    if (brut.contains('acces_refuse')) {
      return "Accès refusé : seul un administrateur peut effectuer cette action.";
    }

    return 'Erreur lors de $actionLibelle : ${e.message}';
  }
}
