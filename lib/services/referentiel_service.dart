// lib/services/referentiel_service.dart
//
// MODULE 2 — « Activités & groupes tarifaires ».
//
// Accès Supabase aux référentiels `public.activites` et
// `public.groupes_tarifaires` : lecture, création, modification, suppression,
// et comptage des entreprises rattachées.
//
// Ces deux tables existaient déjà (le Module 1 les lit pour alimenter les
// listes déroulantes du formulaire d'entreprise) ; ce service ajoute la
// gestion complète demandée par le Module 2.
//
// Comme pour le Module 1, aucune méthode publique ne laisse échapper de
// `PostgrestException` : elles lèvent une [ReferentielServiceException] dont
// le message est rédigé en français et peut être affiché tel quel à
// l'utilisateur (SnackBar, dialogue…).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:biashara_yangu/models/activite.dart';
import 'package:biashara_yangu/models/groupe_tarifaire.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du module « Activités & groupes tarifaires ».
class ReferentielServiceException implements Exception {
  const ReferentielServiceException(this.message);

  /// Message rédigé en français, affichable tel quel à l'utilisateur.
  final String message;

  @override
  String toString() => message;
}

/// Nombre d'entreprises rattachées à chaque activité et à chaque groupe
/// tarifaire.
///
/// Sert aux écrans du Module 2 : affichage « N entreprises » sur les listes,
/// et blocage de la suppression d'un élément encore utilisé.
class CompteursEntreprises {
  const CompteursEntreprises({
    required this.parActivite,
    required this.parGroupe,
  });

  const CompteursEntreprises.vide()
      : parActivite = const <String, int>{},
        parGroupe = const <String, int>{};

  /// Nombre d'entreprises par `activite_id`.
  final Map<String, int> parActivite;

  /// Nombre d'entreprises par `groupe_tarifaire_id`.
  final Map<String, int> parGroupe;

  int pourActivite(String? activiteId) =>
      activiteId == null ? 0 : (parActivite[activiteId] ?? 0);

  int pourGroupe(String? groupeId) =>
      groupeId == null ? 0 : (parGroupe[groupeId] ?? 0);
}

class ReferentielService {
  ReferentielService._();

  static final ReferentielService instance = ReferentielService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  static const Uuid _uuid = Uuid();

  // ---------------------------------------------------------------------------
  // MÉTHODES PUBLIQUES — LECTURE
  // ---------------------------------------------------------------------------

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

  /// Recherche une activité par son identifiant, ou `null` si elle a été
  /// supprimée entre-temps.
  Future<Activite?> getActiviteById(String id) {
    return _executer(
      () async {
        final dynamic data =
            await _client.from('activites').select().eq('id', id).maybeSingle();

        final Map<String, dynamic>? map = parseMap(data);
        return map == null ? null : Activite.fromMap(map);
      },
      actionLibelle: "le chargement de l'activité",
      messageEchec:
          'Impossible de charger cette activité. Vérifiez votre connexion internet.',
    );
  }

  /// Groupes tarifaires d'une activité (tous si [activiteId] est `null`),
  /// triés par nom.
  Future<List<GroupeTarifaire>> getGroupesTarifaires({String? activiteId}) {
    return _executer(
      () async {
        var requete = _client.from('groupes_tarifaires').select();
        if (activiteId != null && activiteId.isNotEmpty) {
          requete = requete.eq('activite_id', activiteId);
        }

        final List<dynamic> data = await requete.order('nom', ascending: true);
        return parseMapList(data).map(GroupeTarifaire.fromMap).toList();
      },
      actionLibelle: 'le chargement des groupes tarifaires',
      messageEchec:
          'Impossible de charger les groupes tarifaires. Vérifiez votre connexion internet.',
    );
  }

  /// Recherche un groupe tarifaire par son identifiant, ou `null` s'il a été
  /// supprimé entre-temps.
  Future<GroupeTarifaire?> getGroupeTarifaireById(String id) {
    return _executer(
      () async {
        final dynamic data = await _client
            .from('groupes_tarifaires')
            .select()
            .eq('id', id)
            .maybeSingle();

        final Map<String, dynamic>? map = parseMap(data);
        return map == null ? null : GroupeTarifaire.fromMap(map);
      },
      actionLibelle: 'le chargement du groupe tarifaire',
      messageEchec:
          'Impossible de charger ce groupe tarifaire. Vérifiez votre connexion internet.',
    );
  }

  /// Compte les entreprises rattachées à chaque activité et à chaque groupe
  /// tarifaire.
  ///
  /// Une seule requête suffit : les compteurs sont calculés en mémoire à
  /// partir des colonnes `activite_id` et `groupe_tarifaire_id`. Le volume
  /// d'un espace administrateur reste faible, la cohérence prime sur
  /// l'optimisation.
  Future<CompteursEntreprises> getCompteursEntreprises() {
    return _executer(
      () async {
        final List<dynamic> data = await _client
            .from('entreprises')
            .select('activite_id, groupe_tarifaire_id');

        final Map<String, int> parActivite = <String, int>{};
        final Map<String, int> parGroupe = <String, int>{};

        for (final Map<String, dynamic> ligne in parseMapList(data)) {
          final String? activiteId = parseStringOrNull(ligne['activite_id']);
          if (activiteId != null) {
            parActivite[activiteId] = (parActivite[activiteId] ?? 0) + 1;
          }

          final String? groupeId =
              parseStringOrNull(ligne['groupe_tarifaire_id']);
          if (groupeId != null) {
            parGroupe[groupeId] = (parGroupe[groupeId] ?? 0) + 1;
          }
        }

        return CompteursEntreprises(
          parActivite: parActivite,
          parGroupe: parGroupe,
        );
      },
      actionLibelle: 'le comptage des entreprises',
      messageEchec:
          'Impossible de compter les entreprises rattachées. Vérifiez votre connexion internet.',
    );
  }

  // ---------------------------------------------------------------------------
  // MÉTHODES PUBLIQUES — ACTIVITÉS
  // ---------------------------------------------------------------------------

  /// Crée une activité. Le nom est obligatoire et unique (l'unicité est
  /// garantie côté base par la contrainte `nom` et l'index insensible à la
  /// casse).
  Future<Activite> creerActivite({
    required String nom,
    String? description,
  }) {
    return _executer(
      () async {
        final String nomNettoye = _validerNomActivite(nom);
        final DateTime maintenant = DateTime.now().toUtc();

        try {
          final Map<String, dynamic> reponse = await _client
              .from('activites')
              .insert(<String, dynamic>{
                // Identifiant généré côté application : cohérent avec le
                // Module 1, et indépendant d'une éventuelle valeur par défaut
                // absente côté Supabase.
                'id': _uuid.v4(),
                'nom': nomNettoye,
                'description': _nettoyerDescription(description),
                'created_at': maintenant.toIso8601String(),
              })
              .select()
              .single();
          return Activite.fromMap(reponse);
        } on PostgrestException catch (e) {
          if (e.code == '23505') {
            throw const ReferentielServiceException(
              'Une activité portant ce nom existe déjà. Choisissez un autre nom.',
            );
          }
          rethrow;
        }
      },
      actionLibelle: "la création de l'activité",
      messageEchec:
          "Impossible de créer l'activité. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  /// Met à jour le nom et la description d'une activité.
  Future<Activite> modifierActivite({
    required String id,
    required String nom,
    String? description,
  }) {
    return _executer(
      () async {
        final String nomNettoye = _validerNomActivite(nom);

        try {
          final dynamic data = await _client
              .from('activites')
              .update(<String, dynamic>{
                'nom': nomNettoye,
                'description': _nettoyerDescription(description),
              })
              .eq('id', id)
              .select()
              .maybeSingle();

          final Map<String, dynamic>? map = parseMap(data);
          if (map == null) {
            throw const ReferentielServiceException(
              "Cette activité est introuvable. Elle a peut-être été supprimée.",
            );
          }
          return Activite.fromMap(map);
        } on PostgrestException catch (e) {
          if (e.code == '23505') {
            throw const ReferentielServiceException(
              'Une activité portant ce nom existe déjà. Choisissez un autre nom.',
            );
          }
          rethrow;
        }
      },
      actionLibelle: "la mise à jour de l'activité",
      messageEchec:
          "Impossible d'enregistrer les modifications. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  /// Supprime une activité.
  ///
  /// Refusé tant que des groupes tarifaires ou des entreprises y sont
  /// rattachés : la vérification est faite ici pour afficher un message
  /// précis, et rejouée en base par un trigger de protection.
  Future<void> supprimerActivite(String id) {
    return _executer(
      () async {
        final int nbGroupes =
            await _compterReferences('groupes_tarifaires', 'activite_id', id);

        if (nbGroupes > 0) {
          throw ReferentielServiceException(
            'Suppression impossible : $nbGroupes groupe'
            '${nbGroupes > 1 ? 's' : ''} tarifaire'
            '${nbGroupes > 1 ? 's' : ''} '
            '${nbGroupes > 1 ? 'sont rattachés' : 'est rattaché'} à cette '
            'activité. Supprimez-les ou rattachez-les à une autre activité.',
          );
        }

        final int nbEntreprises =
            await _compterReferences('entreprises', 'activite_id', id);

        if (nbEntreprises > 0) {
          throw ReferentielServiceException(
            'Suppression impossible : $nbEntreprises entreprise'
            '${nbEntreprises > 1 ? 's utilisent' : ' utilise'} encore cette '
            'activité. Modifiez d\'abord leur activité.',
          );
        }

        try {
          await _client.from('activites').delete().eq('id', id);
        } on PostgrestException catch (e) {
          if (e.code == '23503' || e.code == 'P0001') {
            throw const ReferentielServiceException(
              'Suppression impossible : cette activité est encore utilisée '
              'par des entreprises ou des groupes tarifaires.',
            );
          }
          rethrow;
        }
      },
      actionLibelle: "la suppression de l'activité",
      messageEchec:
          "Impossible de supprimer l'activité. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  // ---------------------------------------------------------------------------
  // MÉTHODES PUBLIQUES — GROUPES TARIFAIRES
  // ---------------------------------------------------------------------------

  /// Crée un groupe tarifaire.
  ///
  /// Validation stricte : nom et activité obligatoires, montant de
  /// l'abonnement strictement positif, aucune valeur négative.
  Future<GroupeTarifaire> creerGroupeTarifaire({
    required String nom,
    required String activiteId,
    required double fraisOuverture,
    required double montantAbonnement,
    required int dureeEssaiJours,
    required int dureeAbonnementJours,
    required double prixParCollaborateur,
    int maxEspaces = 1,
    Set<String> modules = const <String>{},
  }) {
    return _executer(
      () async {
        _validerGroupeTarifaire(
          nom: nom,
          activiteId: activiteId,
          fraisOuverture: fraisOuverture,
          montantAbonnement: montantAbonnement,
          dureeEssaiJours: dureeEssaiJours,
          dureeAbonnementJours: dureeAbonnementJours,
          prixParCollaborateur: prixParCollaborateur,
          maxEspaces: maxEspaces,
        );

        final DateTime maintenant = DateTime.now().toUtc();

        try {
          final Map<String, dynamic> reponse = await _client
              .from('groupes_tarifaires')
              .insert(<String, dynamic>{
                'id': _uuid.v4(),
                'activite_id': activiteId,
                'nom': nom.trim(),
                'frais_ouverture': fraisOuverture,
                'montant_abonnement': montantAbonnement,
                'duree_essai_jours': dureeEssaiJours,
                'duree_abonnement_jours': dureeAbonnementJours,
                'prix_par_collaborateur': prixParCollaborateur,
                // 🏢 MODULE 15 — pack multi-entreprises (1 par défaut).
                'max_espaces': maxEspaces,
                // 🧩 MODULE 16 E — modules autorisés ([] = aucun filtre).
                'modules': modules.toList(growable: false),
                'created_at': maintenant.toIso8601String(),
              })
              .select()
              .single();
          return GroupeTarifaire.fromMap(reponse);
        } on PostgrestException catch (e) {
          if (e.code == '23503') {
            throw const ReferentielServiceException(
              "L'activité sélectionnée est introuvable. Rechargez la liste "
              'des activités puis réessayez.',
            );
          }
          rethrow;
        }
      },
      actionLibelle: 'la création du groupe tarifaire',
      messageEchec:
          'Impossible de créer le groupe tarifaire. Vérifiez votre connexion internet puis réessayez.',
    );
  }

  /// Met à jour un groupe tarifaire (même validation que la création).
  Future<GroupeTarifaire> modifierGroupeTarifaire({
    required String id,
    required String nom,
    required String activiteId,
    required double fraisOuverture,
    required double montantAbonnement,
    required int dureeEssaiJours,
    required int dureeAbonnementJours,
    required double prixParCollaborateur,
    int maxEspaces = 1,
    Set<String> modules = const <String>{},
  }) {
    return _executer(
      () async {
        _validerGroupeTarifaire(
          nom: nom,
          activiteId: activiteId,
          fraisOuverture: fraisOuverture,
          montantAbonnement: montantAbonnement,
          dureeEssaiJours: dureeEssaiJours,
          dureeAbonnementJours: dureeAbonnementJours,
          prixParCollaborateur: prixParCollaborateur,
          maxEspaces: maxEspaces,
        );

        try {
          final dynamic data = await _client
              .from('groupes_tarifaires')
              .update(<String, dynamic>{
                'activite_id': activiteId,
                'nom': nom.trim(),
                'frais_ouverture': fraisOuverture,
                'montant_abonnement': montantAbonnement,
                'duree_essai_jours': dureeEssaiJours,
                'duree_abonnement_jours': dureeAbonnementJours,
                'prix_par_collaborateur': prixParCollaborateur,
                // 🏢 MODULE 15 — pack multi-entreprises.
                'max_espaces': maxEspaces,
                // 🧩 MODULE 16 E — modules autorisés ([] = aucun filtre).
                'modules': modules.toList(growable: false),
              })
              .eq('id', id)
              .select()
              .maybeSingle();

          final Map<String, dynamic>? map = parseMap(data);
          if (map == null) {
            throw const ReferentielServiceException(
              'Ce groupe tarifaire est introuvable. Il a peut-être été supprimé.',
            );
          }
          return GroupeTarifaire.fromMap(map);
        } on PostgrestException catch (e) {
          if (e.code == '23503') {
            throw const ReferentielServiceException(
              "L'activité sélectionnée est introuvable. Rechargez la liste "
              'des activités puis réessayez.',
            );
          }
          rethrow;
        }
      },
      actionLibelle: 'la mise à jour du groupe tarifaire',
      messageEchec:
          "Impossible d'enregistrer les modifications. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  /// Supprime un groupe tarifaire.
  ///
  /// Refusé tant qu'une entreprise l'utilise : vérification applicative pour
  /// un message précis, puis trigger de protection côté base.
  Future<void> supprimerGroupeTarifaire(String id) {
    return _executer(
      () async {
        final int nbEntreprises =
            await _compterReferences('entreprises', 'groupe_tarifaire_id', id);

        if (nbEntreprises > 0) {
          throw ReferentielServiceException(
            'Suppression impossible : $nbEntreprises entreprise'
            '${nbEntreprises > 1 ? 's utilisent' : ' utilise'} encore ce '
            'groupe tarifaire. Changez d\'abord leur abonnement.',
          );
        }

        try {
          await _client.from('groupes_tarifaires').delete().eq('id', id);
        } on PostgrestException catch (e) {
          if (e.code == '23503' || e.code == 'P0001') {
            throw const ReferentielServiceException(
              'Suppression impossible : ce groupe tarifaire est utilisé par '
              'au moins une entreprise.',
            );
          }
          rethrow;
        }
      },
      actionLibelle: 'la suppression du groupe tarifaire',
      messageEchec:
          'Impossible de supprimer le groupe tarifaire. Vérifiez votre connexion internet puis réessayez.',
    );
  }

  // ---------------------------------------------------------------------------
  // OUTILS INTERNES
  // ---------------------------------------------------------------------------

  /// Nombre de lignes de [table] dont [colonne] vaut [valeur].
  Future<int> _compterReferences(
    String table,
    String colonne,
    String valeur,
  ) async {
    final List<dynamic> data =
        await _client.from(table).select('id').eq(colonne, valeur);
    return parseMapList(data).length;
  }

  String _validerNomActivite(String nom) {
    final String nomNettoye = nom.trim();
    if (nomNettoye.isEmpty) {
      throw const ReferentielServiceException(
        "Le nom de l'activité est obligatoire.",
      );
    }
    if (nomNettoye.length < 2) {
      throw const ReferentielServiceException(
        "Le nom de l'activité doit contenir au moins 2 caractères.",
      );
    }
    return nomNettoye;
  }

  /// Validation stricte des montants et durées d'un groupe tarifaire.
  ///
  /// Les formulaires valident déjà leurs champs : ce contrôle est une seconde
  /// barrière, pour qu'aucune donnée invalide ne puisse atteindre la base.
  void _validerGroupeTarifaire({
    required String nom,
    required String activiteId,
    required double fraisOuverture,
    required double montantAbonnement,
    required int dureeEssaiJours,
    required int dureeAbonnementJours,
    required double prixParCollaborateur,
    required int maxEspaces,
  }) {
    if (nom.trim().isEmpty) {
      throw const ReferentielServiceException(
        'Le nom du groupe tarifaire est obligatoire.',
      );
    }
    if (activiteId.trim().isEmpty) {
      throw const ReferentielServiceException(
        "Veuillez sélectionner l'activité du groupe tarifaire.",
      );
    }
    if (fraisOuverture < 0) {
      throw const ReferentielServiceException(
        "Les frais d'ouverture ne peuvent pas être négatifs.",
      );
    }
    if (montantAbonnement <= 0) {
      throw const ReferentielServiceException(
        "Le montant de l'abonnement est obligatoire et doit être supérieur à zéro.",
      );
    }
    if (dureeEssaiJours < 0) {
      throw const ReferentielServiceException(
        "La durée d'essai ne peut pas être négative.",
      );
    }
    if (dureeAbonnementJours <= 0) {
      throw const ReferentielServiceException(
        "La durée de l'abonnement doit être supérieure à zéro.",
      );
    }
    if (prixParCollaborateur < 0) {
      throw const ReferentielServiceException(
        'Le prix par collaborateur ne peut pas être négatif.',
      );
    }
    // 🏢 MODULE 15 — pack multi-entreprises : entre 1 et 20 entreprises.
    if (maxEspaces < 1 || maxEspaces > 20) {
      throw const ReferentielServiceException(
        'Le nombre d\'entreprises autorisées doit être compris entre 1 et 20.',
      );
    }
  }

  String? _nettoyerDescription(String? description) {
    final String texte = (description ?? '').trim();
    return texte.isEmpty ? null : texte;
  }

  /// Exécute [action] en convertissant toute erreur technique en
  /// [ReferentielServiceException] rédigée en français.
  Future<T> _executer<T>(
    Future<T> Function() action, {
    required String actionLibelle,
    required String messageEchec,
  }) async {
    try {
      return await action();
    } on ReferentielServiceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint(
        'ReferentielService ($actionLibelle) : ${e.code} — ${e.message}',
      );
      throw ReferentielServiceException(messageEchec);
    } catch (e, st) {
      debugPrint('ReferentielService ($actionLibelle) : $e\n$st');
      throw ReferentielServiceException(messageEchec);
    }
  }
}
