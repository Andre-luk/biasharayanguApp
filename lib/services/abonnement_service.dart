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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/etat_installation.dart';
import 'package:biashara_yangu/models/paiement_laperle.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/models/utilisateur_entreprise.dart';
import 'package:biashara_yangu/services/cache_lecture.dart';
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
    this.enAttenteActivation = false,
    this.message,
    this.statut,
    this.joursRestants,
  });

  /// Accès complet : rien à signaler.
  const EtatAccesAbonnement.ouvert()
      : bloque = false,
        lectureSeule = false,
        enAttenteActivation = false,
        message = null,
        statut = null,
        joursRestants = null;

  /// Accès totalement refusé (entreprise suspendue par l'administrateur).
  final bool bloque;

  /// Accès en lecture seule : les fonctionnalités commerciales sont
  /// désactivées, la consultation reste possible.
  final bool lectureSeule;

  /// 🧾 MODULE 17 — `true` quand le dossier d'activation n'est pas encore
  /// ACTIF (en attente de vérification, de la finance, ou rejeté) : le
  /// compte n'est PAS opérationnel — toutes les opérations commerciales
  /// sont verrouillées (cadenas) jusqu'à la validation.
  ///
  /// Implique [lectureSeule] : les écrans qui bloquent déjà les écritures
  /// en lecture seule protègent aussi ce cas, avec un message dédié.
  final bool enAttenteActivation;

  /// Message explicatif à afficher (bannière / dialogue), si nécessaire.
  final String? message;

  /// Statut de l'entreprise à l'origine de la décision, si connue.
  final StatutAbonnement? statut;

  /// 🩹 MODULE 27 — jours restants avant l'échéance du cycle en cours.
  ///
  /// Permet d'avertir le client AVANT la coupure (essai de 7 jours comme
  /// abonnement payé), au lieu de le laisser découvrir l'échéance le jour où
  /// les ventes se bloquent.
  final int? joursRestants;

  /// Vrai quand l'accès est encore normal mais que l'échéance approche.
  bool get echeanceProche {
    final int? jours = joursRestants;
    return accesComplet && jours != null && jours >= 0 && jours <= 5;
  }

  bool get accesComplet => !bloque && !lectureSeule && !enAttenteActivation;
}

class AbonnementService {
  AbonnementService._();

  static final AbonnementService instance = AbonnementService._();

  static const int _dureeAbonnementParDefautJours = 30;

  /// ⚡ DÉMARRAGE RAPIDE, MÊME SANS INTERNET.
  ///
  /// Sans délai maximal, un contrôle réseau sur un appareil hors ligne peut
  /// attendre longtemps avant d'échouer : l'application restait bloquée sur
  /// l'écran de lancement. Au-delà de ce délai, on utilise la dernière
  /// décision connue du serveur (voir [_etatMemorise]).
  static const Duration delaiReseau = Duration(seconds: 4);

  /// Clé du cache : dernière décision d'accès rendue par le serveur.
  static const String cleCacheAcces = 'acces_abonnement_dernier';

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

  /// 🧾 MODULE 17 — les opérations commerciales sont-elles verrouillées ?
  /// (`true` quand le compte attend son activation, est échu ou suspendu.)
  bool get operationsVerrouillees => !acces.value.accesComplet;

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
  /// - dossier d'activation non ACTIF (module 17) → lecture seule avec le
  ///   message « compte en attente de validation » ;
  /// - sinon : suspendue → bloqué ; échue → lecture seule.
  ///
  /// ⚠️ `activation_etape` (colonne renvoyée par la RPC depuis le module 17)
  /// est ignorée si absente : comportement historique conservé.
  static EtatAccesAbonnement evaluerAcces(
    List<Map<String, dynamic>> lignes, {
    DateTime? maintenant,
  }) {
    if (lignes.isEmpty) return const EtatAccesAbonnement.ouvert();

    final DateTime reference = maintenant ?? DateTime.now();

    bool aSuspendu = false;
    bool aAttente = false;
    bool aExpire = false;
    bool aActivation = false;
    bool aOuvert = false;
    // 🩹 MODULE 27 — le plus petit nombre de jours restants parmi les accès
    // encore valides : c'est la date à laquelle le client perdra l'usage.
    int? joursProches;

    for (final Map<String, dynamic> ligne in lignes) {
      // 🧾 MODULE 17 — double validation : tant que le gestionnaire n'a pas
      // vérifié ET que la finance n'a pas validé le paiement, le compte
      // n'est pas opérationnel (cadenas sur les opérations commerciales).
      final String etape =
          (parseStringOrNull(ligne['activation_etape']) ?? '').toLowerCase();

      if (etape == 'en_attente_verification' ||
          etape == 'verifie' ||
          etape == 'rejete') {
        aActivation = true;
        continue;
      }

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

      // Compte restreint (solde impayé à l'échéance, module 14) : même
      // verrouillage que l'abonnement échu.
      if (etape == 'restreint') {
        aExpire = true;
        continue;
      }

      if (effectif == StatutAbonnement.essai7j ||
          effectif == StatutAbonnement.actif) {
        final DateTime? expiration = parseDateTimeOrNull(
          ligne['date_expiration'],
        );
        final int? jours = expiration == null
            ? null
            : expiration.difference(reference).inDays;
        if (jours != null && (joursProches == null || jours < joursProches)) {
          joursProches = jours;
        }
        aOuvert = true;
        continue;
      }

      if (effectif == StatutAbonnement.enAttenteComplement) {
        aAttente = true;
      } else {
        aExpire = true;
      }
    }

    // ⚠️ Un accès valide l'emporte TOUJOURS sur un autre accès échu : un client
    // qui possède une entreprise active garde l'application ouverte, même si
    // une autre de ses boutiques est échue.
    if (aOuvert) {
      return EtatAccesAbonnement(
        bloque: false,
        lectureSeule: false,
        statut: StatutAbonnement.actif,
        joursRestants: joursProches,
      );
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

    if (aActivation) {
      return const EtatAccesAbonnement(
        bloque: false,
        lectureSeule: true,
        enAttenteActivation: true,
        message:
            'Votre compte est en attente de validation. Votre paiement doit '
            'être vérifié et votre compte approuvé par notre équipe avant de '
            'pouvoir utiliser les fonctionnalités de votre entreprise.',
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

    // Accès normal : on retient l'échéance pour prévenir avant la coupure.
    return EtatAccesAbonnement(
      bloque: false,
      lectureSeule: false,
      joursRestants: joursProches,
    );
  }

  // ---------------------------------------------------------------------------
  // 🧾 MODULE 17 — CHEMINS RÉSERVÉS AUX OPÉRATIONS COMMERCIALES
  // ---------------------------------------------------------------------------
  //  Tant que le compte n'est pas OPÉRATIONNEL (activation en attente,
  //  abonnement échu ou compte restreint), ces écrans sont inaccessibles —
  //  y compris par lien direct (le middleware du routeur s'appuie dessus).
  //  Les écrans de CONSULTATION (accueil, rapports, stock, caisse, finance,
  //  ventes, dossier d'activation…) restent, eux, toujours accessibles.
  static const List<String> prefixesVerrouilles = <String>[
    // Ventes & encaissement.
    '/main/new-sale',
    '/main/panier',
    '/scanner',
    '/main/commercial',
    // Catalogue (écritures ; la consultation reste ouverte).
    '/main/add-product',
    '/main/edit-product',
    '/main/articles/new',
    '/main/articles/categories',
    '/import-produits',
    '/settings/manage-categories',
    // Équipe / configuration.
    '/settings/manage-users',
    // Stock (écritures ; l'écran de consultation reste ouvert).
    '/main/stock/approvisionnement',
    '/main/stock/ajustement',
    '/main/stock/inventaire',
    '/main/inventaires',
    // Finance (écritures ; caisse et rapports restent consultables).
    '/main/caisse/cloture',
    '/main/depenses/new',
    '/main/dettes/new',
    // Clients.
    '/main/clients',
    // Hôtel.
    '/main/hotel/chambres',
    '/main/hotel/reservations',
    '/main/hotel/reception',
    // Restaurant.
    '/main/restaurant/tables',
    '/main/restaurant/commandes',
    '/main/restaurant/cuisine',
    // Salle des fêtes.
    '/main/evenements',
    '/main/evenements/salles',
    // Boulangerie.
    '/main/production',
    '/main/production/matieres',
  ];

  /// Écritures « dynamiques » : `/…/:id/edit`, `/…/new`, etc.
  static final RegExp _motifEcriture = RegExp(r'/(new|edit)(/|$)');

  /// L'écran [location] est-il réservé aux comptes opérationnels ?
  ///
  /// Fonction PURE (testable sans réseau).
  static bool cheminVerrouille(String location) {
    final String chemin = location.trim();
    if (chemin.isEmpty) return false;

    for (final String prefixe in prefixesVerrouilles) {
      if (chemin == prefixe || chemin.startsWith('$prefixe/')) return true;
    }

    // Écritures à identifiant : /main/articles/:id/edit,
    // /main/articles/:id/conditionnements/new, …
    if (chemin.startsWith('/main/articles/') &&
        _motifEcriture.hasMatch(chemin)) {
      return true;
    }

    return false;
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

  /// État de l'INSTALLATION : déjà réglée ou non, et ce que le prochain
  /// encaissement doit demander.
  ///
  /// La réponse vient du serveur, qui la lit dans l'historique réel des
  /// versements. Côté application, un échec ne lève pas d'exception : on
  /// renvoie [EtatInstallation.inconnu] et l'écran n'affiche simplement pas
  /// l'encart (on ne bloque jamais une consultation pour un bandeau).
  Future<EtatInstallation> etatInstallation({String? entrepriseId}) async {
    try {
      // 🔌 HORS LIGNE : l'état de l'abonnement est relu dans le cache local.
      final dynamic reponse = await CacheLecture.instance.rpc(
        'rpc_abonnement_installation_etat',
        params: <String, dynamic>{'p_entreprise': entrepriseId},
      );
      final Map<String, dynamic>? json = parseMap(reponse);
      if (json == null) return EtatInstallation.inconnu;
      return EtatInstallation.depuisJson(json);
    } catch (e) {
      debugPrint('AbonnementService.etatInstallation : $e');
      return EtatInstallation.inconnu;
    }
  }

  /// 💰 MONTANT À ENCAISSER — la règle, en un seul endroit.
  ///
  /// C'est LA correction du 31/10 : l'écran admin proposait le montant du
  /// cycle PRÉCÉDENT (ex. 15 000) alors que le moteur, pour un abonnement
  /// échu, ouvre un NOUVEAU cycle au prix mensuel actuel (ex. 10 000). Le
  /// paiement était donc refusé (« le montant dépasse le solde restant »).
  ///
  /// Règles :
  ///   • abonnement échu ou cycle soldé → le prix du **prochain** cycle ;
  ///   • sinon → le solde restant du cycle en cours.
  static double montantAEncaisser({
    required SoldeAbonnement solde,
    required double prixCycle,
  }) {
    final bool nouveauCycle =
        solde.solde <= 0 || solde.statut == StatutAbonnement.expire;
    if (nouveauCycle) {
      return prixCycle > 0 ? prixCycle : solde.total;
    }
    return solde.solde;
  }

  /// Vrai quand le prochain paiement ouvre un NOUVEAU cycle.
  static bool ouvreNouveauCycle(SoldeAbonnement solde) =>
      solde.solde <= 0 || solde.statut == StatutAbonnement.expire;

  /// Prix que le moteur demandera pour le **prochain** cycle.
  ///
  /// ⚠️ Différence capitale avec `entreprises.montant_total_du` : ce dernier
  /// décrit le cycle PRÉCÉDENT. Quand l'abonnement est échu, le moteur en
  /// ouvre un nouveau au prix mensuel actuel — payer l'ancien montant est donc
  /// refusé (« le montant dépasse le solde restant »). Cet appel donne le bon
  /// chiffre, celui que la base facturera vraiment.
  ///
  /// Renvoie 0 si le serveur ne répond pas : l'appelant garde alors son
  /// estimation locale.
  Future<double> prixDuCycle(String entrepriseId) async {
    try {
      final dynamic reponse = await _client.rpc(
        'rpc_abonnement_prix_du_cycle',
        params: <String, dynamic>{'p_entreprise': entrepriseId},
      );
      if (reponse is num) return reponse.toDouble();
      return double.tryParse('$reponse') ?? 0;
    } catch (e) {
      debugPrint('AbonnementService.prixDuCycle : $e');
      return 0;
    }
  }

  /// 🧮 MODULE 26 — DÉTAIL DE FACTURATION PAR COLLABORATEUR.
  ///
  /// Renvoie : prix de base, nombre de collaborateurs ACTIFS facturés, prix
  /// unitaire, supplément, total du prochain cycle, échéance.
  ///
  /// `null` si le serveur ne répond pas : l'écran masque simplement le détail
  /// (il n'invente jamais un supplément).
  Future<Map<String, dynamic>?> detailCollaborateurs({
    String? entrepriseId,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'abonnement_detail_collaborateurs',
        params: <String, dynamic>{'p_entreprise': entrepriseId},
      );
      if (reponse is Map) return Map<String, dynamic>.from(reponse);
      return null;
    } catch (e) {
      debugPrint('AbonnementService.detailCollaborateurs : $e');
      return null;
    }
  }

  /// 🧾 MODULE 33 — CHANGE LE FORFAIT AU PRORATA DES JOURS RESTANTS.
  ///
  /// Le serveur seul calcule : complément à payer en cas de hausse, crédit
  /// journalisé en cas de baisse. Les dates d'échéance ne bougent pas.
  Future<ChangementForfait> changerForfait({
    required double nouveauPrix,
    String? motif,
    String? entrepriseId,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'abonnement_changer_forfait',
        params: <String, dynamic>{
          'p_entreprise': entrepriseId,
          'p_prix_mensuel': nouveauPrix,
          'p_motif': motif,
        },
      );
      final Map<String, dynamic>? json = parseMap(reponse);
      if (json == null) return ChangementForfait.aucun;
      return ChangementForfait.depuisJson(json);
    } on PostgrestException catch (e) {
      final String brut = e.message;
      final int barre = brut.indexOf('|');
      final String message = barre >= 0 ? brut.substring(barre + 1) : brut;
      throw AbonnementServiceException(message);
    } catch (e) {
      debugPrint('AbonnementService.changerForfait : $e');
      throw const AbonnementServiceException(
        'Impossible de changer le forfait : vérifiez votre connexion.',
      );
    }
  }

  /// Ouvre le cycle suivant au prix mensuel négocié, si l'abonnement est échu.
  ///
  /// ⚠️ Contrairement à [etatInstallation], cette méthode LÈVE une erreur :
  /// le client doit savoir pourquoi il ne peut pas payer (prix absent,
  /// compte jamais activé…).
  Future<PreparationRenouvellement> preparerRenouvellement({
    String? entrepriseId,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'rpc_abonnement_preparer_renouvellement',
        params: <String, dynamic>{'p_entreprise': entrepriseId},
      );
      final Map<String, dynamic>? json = parseMap(reponse);
      if (json == null) return PreparationRenouvellement.aucune;
      return PreparationRenouvellement.depuisJson(json);
    } on PostgrestException catch (e) {
      final String brut = e.message;
      final int barre = brut.indexOf('|');
      final String message = barre >= 0 ? brut.substring(barre + 1) : brut;
      throw AbonnementServiceException(message);
    } catch (e) {
      debugPrint('AbonnementService.preparerRenouvellement : $e');
      throw const AbonnementServiceException(
        'Impossible de préparer le renouvellement : vérifiez votre connexion.',
      );
    }
  }

  /// 🩹 CORRECTIF 112 — PAYER MÊME PENDANT L'ESSAI.
  ///
  /// Un compte en essai (ou actif, et pas encore échu) a `solde_restant = 0`.
  /// La passerelle Mobile Money refuse alors le paiement : elle n'encaisse
  /// qu'un montant **dû**. Cette méthode ouvre le cycle suivant au prix réel
  /// (base + collaborateurs actifs) **sans toucher au statut ni aux dates**,
  /// puis l'écran lance le paiement SerdiPay normalement.
  ///
  /// Le serveur reste seul juge du montant : si un solde est déjà dû, il ne
  /// rouvre rien (`motif = DEJA_DU`) et renvoie le montant existant.
  /// 🗓️ MODULE 30 — [mois] permet de régler plusieurs mois d'un coup
  /// (3, 6, 12). Le montant est TOUJOURS calculé par le serveur
  /// (`prix du cycle × mois`) : le téléphone ne propose jamais un prix.
  Future<AvanceCycle> ouvrirAvance({
    String? entrepriseId,
    int mois = 1,
  }) async {
    final int duree = mois < 1 ? 1 : (mois > 12 ? 12 : mois);
    try {
      final dynamic reponse = await _client.rpc(
        // Un seul mois garde la fonction d'origine : la caisse fonctionne
        // même si la migration 0115 n'a pas encore été exécutée.
        duree == 1
            ? 'abonnement_ouvrir_avance'
            : 'abonnement_ouvrir_avance_multi',
        params: duree == 1
            ? <String, dynamic>{'p_entreprise': entrepriseId}
            : <String, dynamic>{
                'p_entreprise': entrepriseId,
                'p_mois': duree,
              },
      );
      final Map<String, dynamic>? json = parseMap(reponse);
      if (json == null) return AvanceCycle.aucune;
      return AvanceCycle.depuisJson(json);
    } on PostgrestException catch (e) {
      final String brut = e.message;
      final int barre = brut.indexOf('|');
      final String message = barre >= 0 ? brut.substring(barre + 1) : brut;
      throw AbonnementServiceException(message);
    } catch (e) {
      debugPrint('AbonnementService.ouvrirAvance : $e');
      throw const AbonnementServiceException(
        'Impossible de préparer le paiement : vérifiez votre connexion.',
      );
    }
  }

  /// « L'avance intelligente » : combien de jours ce montant achète-t-il ?
  ///
  /// Le serveur reste la référence (`rpc_abonnement_simulation_avance`), mais
  /// l'écran de paiement utilise [SimulationAvance.calculer] en local pour
  /// répondre immédiatement et **même hors ligne**.
  Future<SimulationAvance?> simulerAvance(
    double montant, {
    String? entrepriseId,
  }) async {
    try {
      final dynamic reponse = await _client.rpc(
        'rpc_abonnement_simulation_avance',
        params: <String, dynamic>{
          'p_entreprise': entrepriseId,
          'p_montant': montant,
        },
      );
      final Map<String, dynamic>? json = parseMap(reponse);
      if (json == null) return null;
      return SimulationAvance.depuisJson(json);
    } catch (e) {
      debugPrint('AbonnementService.simulerAvance : $e');
      return null;
    }
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
  ///
  /// ⚠️ MIGRATION 126 : le serveur REFUSE désormais cette réactivation tant
  /// qu'aucun paiement réel (SerdiPay / versement postérieur à l'échéance)
  /// n'est enregistré — plus aucun mois gratuit. Conservée pour compatibilité :
  /// les écrans passent par la passerelle Mobile Money ou par « Enregistrer un
  /// paiement ».
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
      List<Map<String, dynamic>> lignes = parseMapList(
        await _client.rpc(
          'rpc_entreprises_de_utilisateur',
          params: {'p_user_id': userId},
        ).timeout(delaiReseau),
      );

      // 🧾 MODULE 17 — filet de sécurité : sur certaines bases, la RPC
      // historique ne renvoie AUCUNE ligne alors que le compte possède bien
      // une entreprise (vérifié en production) → l'application restait
      // « fail-open » et laissait commercer un compte non validé. On déduit
      // alors l'état du DOSSIER D'ACTIVATION (module 14), qui répond
      // toujours pour le compte connecté.
      if (lignes.isEmpty) {
        lignes = await _lignesDepuisDossierActivation().timeout(delaiReseau);
      }

      etat = evaluerAcces(lignes);
      // Le serveur a répondu : on garde sa décision pour les démarrages
      // hors ligne (une seule écriture locale, non bloquante).
      await _memoriserEtat(etat);
    } catch (e) {
      debugPrint(
          'AbonnementService.verifierAccesUtilisateur (hors ligne ?): $e');
      // 🔌 HORS LIGNE : on reprend la dernière décision connue du serveur.
      // Sans cache (premier lancement), on laisse l'accès complet : on ne
      // bloque jamais un commerçant à cause d'un incident réseau.
      etat = await _etatMemorise() ?? const EtatAccesAbonnement.ouvert();
    }

    acces.value = etat;
    return etat;
  }

  // ---------------------------------------------------------------------------
  // CACHE LOCAL DE LA DÉCISION D'ACCÈS (démarrage hors ligne)
  // ---------------------------------------------------------------------------

  /// Mémorise la décision du serveur (JSON minimal).
  Future<void> _memoriserEtat(EtatAccesAbonnement etat) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        cleCacheAcces,
        jsonEncode(<String, dynamic>{
          'bloque': etat.bloque,
          'lecture_seule': etat.lectureSeule,
          'en_attente_activation': etat.enAttenteActivation,
          'message': etat.message,
          'statut': etat.statut?.code,
          'jours_restants': etat.joursRestants,
          'le': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('AbonnementService._memoriserEtat : $e');
    }
  }

  /// Relit la dernière décision connue (`null` si aucune).
  Future<EtatAccesAbonnement?> _etatMemorise() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? brut = prefs.getString(cleCacheAcces);
      if (brut == null || brut.isEmpty) return null;

      final dynamic decode = jsonDecode(brut);
      final Map<String, dynamic>? map = parseMap(decode);
      if (map == null) return null;

      final String? codeStatut = parseStringOrNull(map['statut']);
      return EtatAccesAbonnement(
        bloque: map['bloque'] == true,
        lectureSeule: map['lecture_seule'] == true,
        enAttenteActivation: map['en_attente_activation'] == true,
        message: parseStringOrNull(map['message']),
        statut:
            codeStatut == null ? null : StatutAbonnement.fromCode(codeStatut),
        joursRestants: map['jours_restants'] == null
            ? null
            : parseInt(map['jours_restants']),
      );
    } catch (e) {
      debugPrint('AbonnementService._etatMemorise : $e');
      return null;
    }
  }

  /// 🧾 MODULE 17 — construit une « ligne d'accès » à partir du dossier
  /// d'activation (`rpc_activation_etat`, module 14).
  ///
  /// Renvoie une liste vide quand le compte n'a pas de dossier lisible :
  /// l'appelant reste alors fail-open (comportement historique).
  Future<List<Map<String, dynamic>>> _lignesDepuisDossierActivation() async {
    try {
      final Map<String, dynamic>? dossier = parseMap(
        await _client.rpc(
          'rpc_activation_etat',
          params: <String, dynamic>{'p_entreprise_id': null},
        ),
      );

      if (dossier == null) return const <Map<String, dynamic>>[];

      // Dossier réellement exploitable ? (entreprise + étape connues)
      final String etape = parseStringOrNull(dossier['etape']) ?? '';
      final String entreprise =
          parseStringOrNull(dossier['entreprise_id']) ?? '';
      if (etape.isEmpty || entreprise.isEmpty) {
        return const <Map<String, dynamic>>[];
      }

      return <Map<String, dynamic>>[
        <String, dynamic>{
          'statut': dossier['statut'],
          'date_expiration': dossier['date_expiration'],
          'montant_deja_paye': dossier['montant_deja_paye'],
          'solde_restant': dossier['solde_restant'],
          'activation_etape': etape,
        },
      ];
    } catch (e) {
      debugPrint(
        'AbonnementService._lignesDepuisDossierActivation (ignoré): $e',
      );
      return const <Map<String, dynamic>>[];
    }
  }

  /// 🧾 MODULE 17 — actualise silencieusement l'état d'accès de la session
  /// courante (retour au premier plan, rafraîchissement de l'accueil…).
  ///
  /// Les cadenas de l'interface disparaissent ainsi AUTOMATIQUEMENT dès que
  /// la finance active le compte — sans reconnexion.
  /// Best-effort : un incident laisse l'état précédent en place.
  Future<EtatAccesAbonnement> rafraichirSilencieux() async {
    final String? utilisateur = _client.auth.currentUser?.id;
    if (utilisateur == null) return acces.value;

    try {
      return await verifierAccesUtilisateur(utilisateur);
    } catch (e) {
      debugPrint('AbonnementService.rafraichirSilencieux (ignoré): $e');
      return acces.value;
    }
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
      // Cas réel (31/10) : l'écran proposait le montant du cycle PRÉCÉDENT
      // (ex. 15 000) alors que le moteur rouvre un cycle au prix mensuel
      // actuel (ex. 10 000). Le message doit dire QUOI encaisser.
      return "Le montant dépasse ce que le prochain cycle demande. Un "
          "abonnement échu est renouvelé au prix mensuel actuel : encaissez "
          'le montant indiqué dans « Nouveau cycle à encaisser ».';
    }
    if (brut.contains('SOLDE_RESTANT')) {
      return "L'abonnement n'est pas intégralement réglé : la réactivation "
          'est impossible.';
    }
    // 🚫 MIGRATION 126 — la réactivation n'offre plus de jours gratuits.
    if (brut.contains('REACTIVATION_PAYANTE')) {
      return 'Ouvrir un nouveau cycle se paie : aucun paiement Mobile Money '
          "(SerdiPay) postérieur à l'échéance n'a été trouvé. Encaisssez par "
          'Mobile Money, ou enregistrez un paiement en espèces.';
    }
    if (brut.contains('MOTIF_REQUIS')) {
      return 'Indiquez le motif du geste commercial : il est inscrit au '
          "journal d'audit.";
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
