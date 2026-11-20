// lib/models/entreprise.dart
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/models/type_activite.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Entreprise cliente de la plateforme — table `public.entreprises`.
///
/// Les champs `villeNom`, `activiteNom` et `groupeTarifaireNom` sont des champs
/// de confort alimentés par une jointure locale dans `EntrepriseService` :
/// ils ne correspondent à **aucune** colonne de `public.entreprises` et ne sont
/// donc jamais envoyés à Supabase.
class Entreprise {
  final String id;
  final String nom;
  final String? villeId;
  final String? activiteId;
  final String? groupeTarifaireId;
  final StatutAbonnement statut;
  final double montantTotalDu;
  final double montantDejaPaye;
  final double soldeRestant;
  final DateTime? dateActivation;
  final DateTime? dateExpiration;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Champs de confort (jointure locale, non persistés).
  final String? villeNom;
  final String? activiteNom;
  final String? groupeTarifaireNom;

  /// Nom du responsable (patron) — jointure locale, non persisté.
  final String? responsableNom;

  /// Téléphone du responsable — jointure locale, non persisté.
  final String? telephone;

  /// Étape du workflow d'activation (correctifs 20/21) :
  /// `en_attente_verification`, `verifie`, `actif`, `restreint`, `rejete`.
  final String? activationEtape;

  /// Durée d'abonnement de la grille tarifaire, en jours.
  ///
  /// Sert à calculer la prolongation lors d'un encaissement
  /// (voir `EntrepriseService.enregistrerPaiement`).
  final int? groupeTarifaireDureeJours;

  /// 🏪 Type d'activité (migration 0083) : `boutique`, `distribution`, ou
  /// `null` = non renseigné (tous les écrans restent visibles).
  ///
  /// ⚠️ C'est l'AXE COMMERCIAL, pas le MÉTIER. Le métier (pharmacie, pressing,
  /// hôtel…) vit dans `espaces.type` et pilote les modules : voir [metier].
  final TypeActivite? typeActivite;

  /// 🧩 Le MÉTIER réel de l'entreprise, lu dans ses ESPACES
  /// (`espaces.type`) par la RPC `rpc_entreprises_metiers` (migration 174).
  ///
  /// Champ de confort (non persisté dans `entreprises`) : c'est la seule
  /// valeur à afficher comme « type de boutique ». Une entreprise peut avoir
  /// plusieurs boutiques ; on retient le métier spécialisé (jamais
  /// « boutique » quand un métier précis existe).
  final String? metier;

  /// Libellé lisible du [metier] (« Pharmacie », « Pressing »…).
  final String? metierLibelle;

  const Entreprise({
    required this.id,
    required this.nom,
    this.villeId,
    this.activiteId,
    this.groupeTarifaireId,
    this.statut = StatutAbonnement.inconnu,
    this.montantTotalDu = 0,
    this.montantDejaPaye = 0,
    this.soldeRestant = 0,
    this.dateActivation,
    this.dateExpiration,
    this.createdAt,
    this.updatedAt,
    this.villeNom,
    this.activiteNom,
    this.groupeTarifaireNom,
    this.groupeTarifaireDureeJours,
    this.responsableNom,
    this.telephone,
    this.activationEtape,
    this.typeActivite,
    this.metier,
    this.metierLibelle,
  });

  factory Entreprise.fromMap(Map<String, dynamic> map) {
    final double montantTotal = parseDouble(map['montant_total_du']);
    final double montantPaye = parseDouble(map['montant_deja_paye']);

    // 🔴 CORRECTIF 100 — le solde affiché ne doit JAMAIS contredire le dû et
    // le déjà-payé. La colonne `solde_restant` a été rendue « ordinaire » par
    // la migration 0094 : un chemin de code qui oublie de l'écrire la laisse
    // périmée (cas réel : 5 000 payés, solde toujours affiché à 15 000).
    // On calcule donc `total - payé` et on ne retient la colonne que si elle
    // est cohérente (à 1 centime près).
    final double soldeCalcule = montantTotal - montantPaye;
    final bool soldeFourni =
        map.containsKey('solde_restant') && map['solde_restant'] != null;
    final double soldeStocke =
        soldeFourni ? parseDouble(map['solde_restant']) : soldeCalcule;
    final bool soldeCoherent =
        (soldeStocke - soldeCalcule).abs() <= 0.01;

    return Entreprise(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      villeId: parseStringOrNull(map['ville_id']),
      activiteId: parseStringOrNull(map['activite_id']),
      groupeTarifaireId: parseStringOrNull(map['groupe_tarifaire_id']),
      statut: StatutAbonnement.fromCode(parseStringOrNull(map['statut'])),
      montantTotalDu: montantTotal,
      montantDejaPaye: montantPaye,
      soldeRestant: soldeCoherent
          ? (soldeStocke > 0 ? soldeStocke : 0.0)
          : (soldeCalcule > 0 ? soldeCalcule : 0.0),
      dateActivation: parseDateTimeOrNull(map['date_activation']),
      dateExpiration: parseDateTimeOrNull(map['date_expiration']),
      createdAt: parseDateTimeOrNull(map['created_at']),
      updatedAt: parseDateTimeOrNull(map['updated_at']),
      activationEtape: parseStringOrNull(map['activation_etape']),
      typeActivite:
          TypeActivite.depuis(parseStringOrNull(map['type_activite'])),
      // `metier` n'est pas une colonne de `entreprises` : il est ajouté par
      // la jointure locale de `EntrepriseService` (RPC dédiée).
      metier: parseStringOrNull(map['metier']),
      metierLibelle: parseStringOrNull(map['metier_libelle']),
    );
  }

  /// Colonnes de `public.entreprises` uniquement (hors champs de jointure).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nom': nom,
      'ville_id': villeId,
      'activite_id': activiteId,
      'groupe_tarifaire_id': groupeTarifaireId,
      'statut': statut.code,
      'montant_total_du': montantTotalDu,
      'montant_deja_paye': montantDejaPaye,
      'solde_restant': soldeRestant,
      'date_activation': dateActivation?.toIso8601String(),
      'date_expiration': dateExpiration?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Nombre de jours restants avant l'expiration, calculé **à la journée**.
  ///
  /// - Valeur positive : jours restants.
  /// - `0` : expire aujourd'hui.
  /// - Valeur négative : nombre de jours depuis l'expiration.
  /// - `null` : aucune date d'expiration enregistrée.
  int? get joursRestants {
    final DateTime? expiration = dateExpiration;
    if (expiration == null) return null;

    final DateTime maintenant = DateTime.now();
    final DateTime localeExpiration = expiration.toLocal();

    final DateTime jourExpiration = DateTime(
      localeExpiration.year,
      localeExpiration.month,
      localeExpiration.day,
    );
    final DateTime jourCourant =
        DateTime(maintenant.year, maintenant.month, maintenant.day);

    return jourExpiration.difference(jourCourant).inDays;
  }

  /// Vrai si l'abonnement se termine dans 3 jours ou moins (sans être expiré).
  bool get bientotExpire {
    final int? jours = joursRestants;
    return jours != null && jours >= 0 && jours <= 3;
  }

  bool get estSuspendue => statut == StatutAbonnement.suspendu;

  /// Statut réellement affiché à l'utilisateur.
  ///
  /// Supabase ne fait pas expirer automatiquement un abonnement : une
  /// entreprise dont la date d'expiration est dépassée peut encore porter le
  /// statut `ESSAI_7J` ou `ACTIF` en base. Ce getter corrige l'affichage côté
  /// application, sans jamais écrire en base.
  ///
  /// La correction en base est faite séparément, de façon opportuniste, par
  /// `rpc_actualiser_statuts_abonnements()` (voir `EntrepriseService`).
  StatutAbonnement get statutEffectif {
    final bool statutSoumisAExpiration =
        statut == StatutAbonnement.essai7j || statut == StatutAbonnement.actif;

    if (statutSoumisAExpiration) {
      final int? jours = joursRestants;
      if (jours != null && jours < 0) return StatutAbonnement.expire;
    }
    return statut;
  }

  /// Vrai si le statut affiché diffère de celui enregistré en base
  /// (typiquement : abonnement expiré mais statut SQL pas encore actualisé).
  bool get statutDesynchronise => statutEffectif != statut;

  /// Vrai si l'abonnement est expiré au regard de sa date d'expiration.
  bool get estExpiree => statutEffectif == StatutAbonnement.expire;

  /// Part de l'abonnement déjà réglée, bornée entre 0 et 1.
  double get tauxPaiement {
    if (montantTotalDu <= 0) return 0;

    final double taux = montantDejaPaye / montantTotalDu;
    if (taux < 0) return 0;
    if (taux > 1) return 1;
    return taux;
  }

  bool get estSolde {
    return soldeRestant <= 0;
  }

  Entreprise copyWith({
    String? id,
    String? nom,
    String? villeId,
    String? activiteId,
    String? groupeTarifaireId,
    StatutAbonnement? statut,
    double? montantTotalDu,
    double? montantDejaPaye,
    double? soldeRestant,
    DateTime? dateActivation,
    DateTime? dateExpiration,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? villeNom,
    String? activiteNom,
    String? groupeTarifaireNom,
    int? groupeTarifaireDureeJours,
    String? responsableNom,
    String? telephone,
    String? activationEtape,
    String? metier,
    String? metierLibelle,
  }) {
    return Entreprise(
      id: id ?? this.id,
      nom: nom ?? this.nom,
      villeId: villeId ?? this.villeId,
      activiteId: activiteId ?? this.activiteId,
      groupeTarifaireId: groupeTarifaireId ?? this.groupeTarifaireId,
      statut: statut ?? this.statut,
      montantTotalDu: montantTotalDu ?? this.montantTotalDu,
      montantDejaPaye: montantDejaPaye ?? this.montantDejaPaye,
      soldeRestant: soldeRestant ?? this.soldeRestant,
      dateActivation: dateActivation ?? this.dateActivation,
      dateExpiration: dateExpiration ?? this.dateExpiration,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      villeNom: villeNom ?? this.villeNom,
      activiteNom: activiteNom ?? this.activiteNom,
      groupeTarifaireNom: groupeTarifaireNom ?? this.groupeTarifaireNom,
      groupeTarifaireDureeJours:
          groupeTarifaireDureeJours ?? this.groupeTarifaireDureeJours,
      responsableNom: responsableNom ?? this.responsableNom,
      telephone: telephone ?? this.telephone,
      activationEtape: activationEtape ?? this.activationEtape,
      metier: metier ?? this.metier,
      metierLibelle: metierLibelle ?? this.metierLibelle,
    );
  }

  /// Libellé lisible de l'étape d'activation, pour l'administration.
  String get libelleActivation {
    switch (activationEtape) {
      case 'en_attente_verification':
        return 'En attente de vérification';
      case 'verifie':
        return 'Vérifié — attente finance';
      case 'restreint':
        return 'Restreint (paiement en retard)';
      case 'rejete':
        return 'Rejeté — à corriger';
      case 'actif':
      case null:
      default:
        return 'Actif';
    }
  }

  /// Vrai si le compte attend encore sa vérification/activation.
  bool get enAttenteActivation =>
      activationEtape == 'en_attente_verification' ||
      activationEtape == 'verifie' ||
      activationEtape == 'rejete';
}
