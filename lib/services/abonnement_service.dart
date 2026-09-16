// lib/services/abonnement_service.dart
//
// MODULE 3 — MOTEUR D'ABONNEMENT.
//
// Cœur du système d'abonnement :
//   - calcul des soldes et des jours restants ;
//   - enregistrement des paiements (avance / solde / renouvellement) avec
//     historisation dans `paiements_abonnements_laperle` ;
//   - prolongation / réactivation calculées par la base (RPC `security
//     definer`), jamais depuis une date fournie par le client ;
//   - vérification globale au démarrage (EXPIRE / EN_ATTENTE_COMPLEMENT) ;
//   - middleware d'accès : lecture seule quand l'abonnement est échu.
//
// Les règles métier vivent dans `supabase/migrations/20260916000003_module3_abonnement.sql`.
// Les méthodes statiques « pures » de ce service (calculerStatutEffectif,
// calculerFinCycle, evaluerAcces) reproduisent ces règles côté application :
// elles servent à l'affichage immédiat et aux tests unitaires, sans réseau.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/paiement_laperle.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/models/utilisateur_entreprise.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Erreur métier du moteur d'abonnement.
///
/// [message] est toujours rédigé en français et peut être affiché tel quel
/// à l'utilisateur (SnackBar, dialogue…).
class AbonnementServiceException implements Exception {
  const AbonnementServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Résultat de [AbonnementService.calculerSolde].
class SoldeAbonnement {
  const SoldeAbonnement({
    required this.total,
    required this.paye,
    required this.solde,
    required this.joursRestants,
    required this.statut,
    this.dateExpiration,
  });

  /// Montant total dû pour le cycle en cours.
  final double total;

  /// Montant déjà encaissé sur ce cycle.
  final double paye;

  /// Reste à payer (`total - paye`, jamais négatif).
  final double solde;

  /// Jours restants avant expiration (négatif si dépassé, `null` si aucune
  /// date n'est planifiée).
  final int? joursRestants;

  /// Statut effectif (tient compte de la date d'expiration, même si la base
  /// n'a pas encore basculé la ligne).
  final StatutAbonnement statut;

  final DateTime? dateExpiration;

  bool get estSolde => solde <= 0;

  double get tauxPaiement {
    if (total <= 0) return 0;
    final double taux = paye / total;
    if (taux < 0) return 0;
    if (taux > 1) return 1;
    return taux;
  }
}

/// État d'accès calculé par le middleware d'abonnement (login / démarrage).
class EtatAccesAbonnement {
  const EtatAccesAbonnement({
    required this.bloque,
    required this.lectureSeule,
    this.message,
    this.statut,
  });

  /// Accès complet : rien à signaler.
  const EtatAccesAbonnement.ouvert()
      : bloque = false,
        lectureSeule = false,
        message = null,
        statut = null;

  /// Accès totalement refusé (entreprise suspendue par l'administrateur).
  final bool bloque;

  /// Accès en lecture seule : les fonctionnalités commerciales sont
  /// désactivées, la consultation reste possible.
  final bool lectureSeule;

  /// Message explicatif à afficher (bannière / dialogue), si nécessaire.
  final String? message;

  /// Statut de l'entreprise à l'origine de la décision, si connue.
  final StatutAbonnement? statut;

  bool get accesComplet => !bloque && !lectureSeule;
}

class AbonnementService {
  AbonnementService._();

  static final AbonnementService instance = AbonnementService._();

  static const int _dureeAbonnementParDefautJours = 30;

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Dernier état d'accès calculé par le middleware.
  ///
  /// Les écrans s'y abonnent (`ValueListenableBuilder`) pour afficher la
  /// bannière « lecture seule » ou pour bloquer une action commerciale.
  final ValueNotifier<EtatAccesAbonnement> acces =
      ValueNotifier<EtatAccesAbonnement>(
    const EtatAccesAbonnement.ouvert(),
  );

  /// Raccourci : l'application est-elle en lecture seule ?
  bool get lectureSeule => acces.value.lectureSeule;

  // ---------------------------------------------------------------------------
  // RÈGLES MÉTIER PURES (testables sans réseau)
  // ---------------------------------------------------------------------------

  /// Statut effectif d'une entreprise au regard de sa date d'expiration.
  ///
  /// - `ESSAI_7J` / `ACTIF` non échus → statut inchangé ;
  /// - échu avec un paiement partiel → `EN_ATTENTE_COMPLEMENT` ;
  /// - échu sans paiement → `EXPIRE` ;
  /// - les autres statuts (`SUSPENDU`, `EN_ATTENTE_COMPLEMENT`) ne sont
  ///   jamais recalculés côté application.
  static StatutAbonnement calculerStatutEffectif({
    required StatutAbonnement statut,
    required DateTime? dateExpiration,
    required double montantDejaPaye,
    required double soldeRestant,
    DateTime? maintenant,
  }) {
    final bool soumisAExpiration =
        statut == StatutAbonnement.essai7j || statut == StatutAbonnement.actif;
    if (!soumisAExpiration) return statut;

    final DateTime reference = maintenant ?? DateTime.now();
    final DateTime? expiration = dateExpiration;
    if (expiration == null || !expiration.isBefore(reference)) return statut;

    if (montantDejaPaye > 0 && soldeRestant > 0) {
      return StatutAbonnement.enAttenteComplement;
    }
    return StatutAbonnement.expire;
  }

  /// Date de fin du nouveau cycle après un paiement complet.
  ///
  /// Renouvellement anticipé (abonnement `ACTIF` encore valide) : on repart
  /// de la date d'expiration pour ne perdre aucun jour payé. Dans tous les
  /// autres cas (essai, abonnement échu, attente de complément), on repart de
  /// maintenant.
  static DateTime calculerFinCycle({
    required StatutAbonnement statut,
    required DateTime? dateExpiration,
    required int dureeJours,
    DateTime? maintenant,
  }) {
    final DateTime reference = maintenant ?? DateTime.now();
    final bool encoreValide = statut == StatutAbonnement.actif &&
        dateExpiration != null &&
        dateExpiration.isAfter(reference);

    final DateTime base = encoreValide ? dateExpiration : reference;
    return base.add(Duration(days: dureeJours));
  }

  /// Décision d'accès à partir des entreprises rattachées à un utilisateur
  /// (`rpc_entreprises_de_utilisateur`).
  ///
  /// - Aucune entreprise rattachée → accès ouvert (fail-open) ;
  /// - au moins une entreprise valide → accès complet ;
  /// - sinon : suspendue → bloqué ; échue → lecture seule.
  static EtatAccesAbonnement evaluerAcces(
    List<Map<String, dynamic>> lignes, {
    DateTime? maintenant,
  }) {
    if (lignes.isEmpty) return const EtatAccesAbonnement.ouvert();

    final DateTime reference = maintenant ?? DateTime.now();

    bool aSuspendu = false;
    bool aAttente = false;
    bool aExpire = false;

    for (final Map<String, dynamic> ligne in lignes) {
      final StatutAbonnement statut =
          StatutAbonnement.fromCode(parseStringOrNull(ligne['statut']));

      if (statut == StatutAbonnement.suspendu) {
        aSuspendu = true;
        continue;
      }

      final StatutAbonnement effectif = calculerStatutEffectif(
        statut: statut,
        dateExpiration: parseDateTimeOrNull(ligne['date_expiration']),
        montantDejaPaye: parseDouble(ligne['montant_deja_paye']),
        soldeRestant: parseDouble(ligne['solde_restant']),
        maintenant: reference,
      );

      if (effectif == StatutAbonnement.essai7j ||
          effectif == StatutAbonnement.actif) {
        return const EtatAccesAbonnement.ouvert();
      }

      if (effectif == StatutAbonnement.enAttenteComplement) {
        aAttente = true;
      } else {
        aExpire = true;
      }
    }

    if (aSuspendu) {
      return const EtatAccesAbonnement(
        bloque: true,
        lectureSeule: false,
        message:
            "L'accès de votre entreprise a été suspendu par l'administrateur. "
            'Contactez-le pour le réactiver.',
        statut: StatutAbonnement.suspendu,
      );
    }

    if (aAttente) {
      return const EtatAccesAbonnement(
        bloque: false,
        lectureSeule: true,
        message: "L'abonnement de votre entreprise est arrivé à échéance : un "
            'complément de paiement est attendu. La consultation reste '
            'possible, mais les ventes et les opérations sont suspendues '
            "jusqu'au règlement du solde.",
        statut: StatutAbonnement.enAttenteComplement,
      );
    }

    if (aExpire) {
      return const EtatAccesAbonnement(
        bloque: false,
        lectureSeule: true,
        message:
            "L'abonnement de votre entreprise a expiré. La consultation reste "
            'possible en lecture seule ; contactez votre administrateur pour '
            'le renouveler.',
        statut: StatutAbonnement.expire,
      );
    }

    return const EtatAccesAbonnement.ouvert();
  }

  // ---------------------------------------------------------------------------
  // LECTURE
  // ---------------------------------------------------------------------------

  /// Entreprise brute (sans jointure), ou `null` si elle n'existe plus.
  Future<Entreprise?> getEntreprise(String entrepriseId) {
    return _executer(
      () => _lireEntreprise(entrepriseId),
      actionLibelle: "le chargement de l'entreprise",
      messageEchec:
          'Impossible de charger cette entreprise. Vérifiez votre connexion internet.',
    );
  }

  /// Calcule l'état complet de l'abonnement d'une entreprise :
  /// total dû, déjà payé, solde, jours restants et statut effectif.
  Future<SoldeAbonnement> calculerSolde(String entrepriseId) {
    return _executer(
      () async {
        final Entreprise? entreprise = await _lireEntreprise(entrepriseId);
        if (entreprise == null) {
          throw const AbonnementServiceException(
            "Cette entreprise est introuvable. Elle a peut-être été supprimée.",
          );
        }

        return soldeDepuisEntreprise(entreprise);
      },
      actionLibelle: "le calcul du solde d'abonnement",
      messageEchec:
          'Impossible de calculer le solde de cet abonnement. Vérifiez votre connexion internet.',
    );
  }

  /// Raccourci pur : construit [SoldeAbonnement] depuis un modèle déjà chargé.
  static SoldeAbonnement soldeDepuisEntreprise(
    Entreprise entreprise, {
    DateTime? maintenant,
  }) {
    final StatutAbonnement effectif = calculerStatutEffectif(
      statut: entreprise.statut,
      dateExpiration: entreprise.dateExpiration,
      montantDejaPaye: entreprise.montantDejaPaye,
      soldeRestant: entreprise.soldeRestant,
      maintenant: maintenant,
    );

    return SoldeAbonnement(
      total: entreprise.montantTotalDu,
      paye: entreprise.montantDejaPaye,
      solde: entreprise.soldeRestant,
      joursRestants: entreprise.joursRestants,
      statut: effectif,
      dateExpiration: entreprise.dateExpiration,
    );
  }

  /// Statut effectif de l'abonnement d'une entreprise.
  Future<StatutAbonnement> verifierStatut(String entrepriseId) {
    return _executer(
      () async {
        final Entreprise? entreprise = await _lireEntreprise(entrepriseId);
        if (entreprise == null) {
          throw const AbonnementServiceException(
            "Cette entreprise est introuvable. Elle a peut-être été supprimée.",
          );
        }

        return capturerStatutEffectif(entreprise);
      },
      actionLibelle: "la vérification du statut d'abonnement",
      messageEchec:
          "Impossible de vérifier le statut de l'abonnement. Vérifiez votre connexion internet.",
    );
  }

  /// Version pure de [verifierStatut] pour un modèle déjà chargé.
  static StatutAbonnement capturerStatutEffectif(Entreprise entreprise) {
    return calculerStatutEffectif(
      statut: entreprise.statut,
      dateExpiration: entreprise.dateExpiration,
      montantDejaPaye: entreprise.montantDejaPaye,
      soldeRestant: entreprise.soldeRestant,
    );
  }

  /// Historique des paiements du moteur (table La Perle), du plus récent au
  /// plus ancien. Best-effort : renvoie une liste vide si la table n'est pas
  /// encore accessible, pour ne jamais bloquer l'affichage de la fiche.
  Future<List<PaiementLaperle>> getHistorique(String entrepriseId) async {
    try {
      final List<dynamic> data = await _client
          .from('paiements_abonnements_laperle')
          .select()
          .eq('entreprise_id', entrepriseId)
          .order('created_at', ascending: false);

      final List<PaiementLaperle> paiements =
          parseMapList(data).map(PaiementLaperle.fromMap).toList();

      final Map<String, String> noms = await _chargerNomsUtilisateurs();

      return paiements
          .map(
            (PaiementLaperle paiement) => paiement.copyWith(
              enregistreParNom: noms[paiement.enregistrePar],
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('AbonnementService.getHistorique (ignoré): $e');
      return const <PaiementLaperle>[];
    }
  }

  /// Durée d'abonnement de la grille tarifaire d'une entreprise (30 jours par
  /// défaut). Sert à l'aperçu du formulaire de paiement.
  Future<int> getDureeAbonnement(String? groupeTarifaireId) async {
    if (groupeTarifaireId == null) return _dureeAbonnementParDefautJours;

    try {
      final dynamic ligne = await _client
          .from('groupes_tarifaires')
          .select('duree_abonnement_jours, duree_essai_jours')
          .eq('id', groupeTarifaireId)
          .maybeSingle();

      final Map<String, dynamic>? map = parseMap(ligne);
      if (map == null) return _dureeAbonnementParDefautJours;

      final int duree = parseInt(map['duree_abonnement_jours']);
      return duree > 0 ? duree : _dureeAbonnementParDefautJours;
    } catch (e) {
      debugPrint('AbonnementService.getDureeAbonnement (ignoré): $e');
      return _dureeAbonnementParDefautJours;
    }
  }

  // ---------------------------------------------------------------------------
  // ÉCRITURE — MOTEUR
  // ---------------------------------------------------------------------------

  /// Enregistre un paiement d'abonnement et met à jour l'entreprise.
  ///
  /// Toute la logique (nouveau cycle, statut, dates) est appliquée par la
  /// fonction SQL `rpc_abonnement_enregistrer_paiement` : l'opération est
  /// atomique et l'historique est écrit dans `paiements_abonnements_laperle`.
  Future<Entreprise> enregistrerPaiement({
    required String entrepriseId,
    required double montant,
    required TypePaiement type,
    String? modePaiement,
    String? note,
  }) {
    return _executer(
      () async {
        if (montant <= 0) {
          throw const AbonnementServiceException(
            'Le montant encaissé doit être supérieur à zéro.',
          );
        }

        try {
          final dynamic reponse = await _client.rpc(
            'rpc_abonnement_enregistrer_paiement',
            params: {
              'p_entreprise_id': entrepriseId,
              'p_montant': montant,
              'p_type_paiement': type.code,
              'p_mode_paiement': modePaiement,
              'p_note': note,
            },
          );

          final Map<String, dynamic>? ligne = reponse is List
              ? (reponse.isEmpty ? null : parseMap(reponse.first))
              : parseMap(reponse);

          if (ligne == null) {
            throw const AbonnementServiceException(
              "Le moteur d'abonnement a renvoyé une réponse inattendue.",
            );
          }

          return Entreprise.fromMap(ligne);
        } on PostgrestException catch (e) {
          throw AbonnementServiceException(_traduireErreurMoteur(e));
        }
      },
      actionLibelle: "l'enregistrement du paiement d'abonnement",
      messageEchec:
          "Impossible d'enregistrer le paiement. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  /// Réactive un abonnement intégralement réglé et calcule sa nouvelle date
  /// d'expiration (`base + duree_abonnement_jours`, base = max(now, expiration
  /// encore future)).
  Future<Entreprise> reactiverApresPaiement(String entrepriseId) {
    return _executer(
      () async {
        try {
          final dynamic reponse = await _client.rpc(
            'rpc_abonnement_reactiver',
            params: {'p_entreprise_id': entrepriseId},
          );

          final Map<String, dynamic>? ligne = reponse is List
              ? (reponse.isEmpty ? null : parseMap(reponse.first))
              : parseMap(reponse);

          if (ligne == null) {
            throw const AbonnementServiceException(
              "Le moteur d'abonnement a renvoyé une réponse inattendue.",
            );
          }

          return Entreprise.fromMap(ligne);
        } on PostgrestException catch (e) {
          throw AbonnementServiceException(_traduireErreurMoteur(e));
        }
      },
      actionLibelle: "la réactivation de l'abonnement",
      messageEchec:
          "Impossible de réactiver l'abonnement. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  /// Vérifie toutes les entreprises et bascule en `EXPIRE` (aucun paiement)
  /// ou `EN_ATTENTE_COMPLEMENT` (paiement partiel) celles dont la date
  /// d'expiration est dépassée.
  ///
  /// Renvoie le nombre d'abonnements mis à jour. À appeler au démarrage de
  /// l'application et après une connexion réussie.
  Future<int> executerVerificationGlobale() {
    return _executer(
      () async {
        final dynamic reponse =
            await _client.rpc('rpc_abonnement_verification_globale');

        if (reponse is int) return reponse;
        if (reponse is List && reponse.isNotEmpty) {
          return parseInt(reponse.first);
        }
        return 0;
      },
      actionLibelle: 'la vérification globale des abonnements',
      messageEchec:
          "Impossible de vérifier les abonnements. Vérifiez votre connexion internet.",
    );
  }

  /// Variante silencieuse de [executerVerificationGlobale] : utilisée au
  /// démarrage, où un échec ne doit jamais bloquer l'application.
  Future<void> executerVerificationGlobaleSilencieuse() async {
    try {
      await executerVerificationGlobale();
    } catch (e) {
      debugPrint('AbonnementService.verification globale (ignorée): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // MIDDLEWARE D'ACCÈS (LOGIN / DÉMARRAGE)
  // ---------------------------------------------------------------------------

  /// Vérifie le statut de l'entreprise de l'utilisateur et met à jour
  /// [acces].
  ///
  /// Fail-open : toute erreur (réseau, fonction absente…) laisse l'accès
  /// complet — on ne bloque jamais un utilisateur à cause d'un incident
  /// technique.
  Future<EtatAccesAbonnement> verifierAccesUtilisateur(String userId) async {
    EtatAccesAbonnement etat;

    try {
      final List<Map<String, dynamic>> lignes = parseMapList(
        await _client.rpc(
          'rpc_entreprises_de_utilisateur',
          params: {'p_user_id': userId},
        ),
      );

      etat = evaluerAcces(lignes);
    } catch (e) {
      debugPrint('AbonnementService.verifierAccesUtilisateur (fail-open): $e');
      etat = const EtatAccesAbonnement.ouvert();
    }

    acces.value = etat;
    return etat;
  }

  /// Réinitialise l'état d'accès (déconnexion).
  void reinitialiserAcces() {
    acces.value = const EtatAccesAbonnement.ouvert();
  }

  // ---------------------------------------------------------------------------
  // OUTILS INTERNES
  // ---------------------------------------------------------------------------

  Future<Entreprise?> _lireEntreprise(String entrepriseId) async {
    final dynamic ligne = await _client
        .from('entreprises')
        .select()
        .eq('id', entrepriseId)
        .maybeSingle();

    final Map<String, dynamic>? map = parseMap(ligne);
    return map == null ? null : Entreprise.fromMap(map);
  }

  /// Noms des utilisateurs, pour afficher l'auteur d'un encaissement.
  /// Best-effort : renvoie une table vide en cas d'échec.
  Future<Map<String, String>> _chargerNomsUtilisateurs() async {
    try {
      final List<dynamic> data =
          await _client.from('utilisateurs').select('id, prenom, nom, email');

      return <String, String>{
        for (final UtilisateurEntreprise utilisateur
            in parseMapList(data).map(UtilisateurEntreprise.fromMap))
          if (utilisateur.id.isNotEmpty) utilisateur.id: utilisateur.nomComplet,
      };
    } catch (e) {
      debugPrint('AbonnementService._chargerNomsUtilisateurs (ignoré): $e');
      return const <String, String>{};
    }
  }

  /// Traduit les erreurs explicites du moteur SQL en messages utilisateur.
  String _traduireErreurMoteur(PostgrestException e) {
    // Fonction absente de la base : la migration Module 3 n'est pas installée.
    if (e.code == 'PGRST202' || e.code == '42883') {
      return "Le moteur d'abonnement n'est pas installé sur la base. "
          'Exécutez le script '
          'supabase/migrations/20260916000003_module3_abonnement.sql '
          'puis réessayez.';
    }

    final String brut = '${e.code} ${e.message}';

    if (brut.contains('ACCES_REFUSE')) {
      return "Seul un administrateur peut effectuer cette opération sur "
          "l'abonnement.";
    }
    if (brut.contains('MONTANT_INVALIDE')) {
      return 'Le montant doit être supérieur à zéro.';
    }
    if (brut.contains('TYPE_PAIEMENT_INVALIDE')) {
      return 'Type de paiement invalide : choisissez Avance, Solde ou '
          'Renouvellement.';
    }
    if (brut.contains('ENTREPRISE_INTROUVABLE')) {
      return "Cette entreprise n'existe plus dans la base de données.";
    }
    if (brut.contains('MONTANT_TOTAL_INCONNU')) {
      return "Impossible de déterminer le montant de l'abonnement : la "
          'grille tarifaire de cette entreprise est manquante.';
    }
    if (brut.contains('MONTANT_SUPERIEUR')) {
      return "Le montant dépasse le solde restant de l'abonnement.";
    }
    if (brut.contains('SOLDE_RESTANT')) {
      return "L'abonnement n'est pas intégralement réglé : la réactivation "
          'est impossible.';
    }

    return "Le moteur d'abonnement a refusé l'opération. Réessayez ou "
        'contactez le support technique.';
  }

  /// Exécute [action] en convertissant toute erreur technique en
  /// [AbonnementServiceException] rédigée en français.
  Future<T> _executer<T>(
    Future<T> Function() action, {
    required String actionLibelle,
    required String messageEchec,
  }) async {
    try {
      return await action();
    } on AbonnementServiceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint(
          'AbonnementService ($actionLibelle) : ${e.code} — ${e.message}');
      throw AbonnementServiceException(messageEchec);
    } catch (e, st) {
      debugPrint('AbonnementService ($actionLibelle) : $e\n$st');
      throw AbonnementServiceException(messageEchec);
    }
  }
}
