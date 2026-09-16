// lib/models/entreprise.dart
import 'package:biashara_yangu/models/statut_abonnement.dart';
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
  });

  factory Entreprise.fromMap(Map<String, dynamic> map) {
    final double montantTotal = parseDouble(map['montant_total_du']);
    final double montantPaye = parseDouble(map['montant_deja_paye']);

    // La base reste la source de vérité quand la colonne est présente ;
    // sinon on recalcule pour éviter d'afficher un solde incohérent.
    final bool soldeFourni =
        map.containsKey('solde_restant') && map['solde_restant'] != null;
    final double soldeCalcule = montantTotal - montantPaye;

    return Entreprise(
      id: parseString(map['id']),
      nom: parseString(map['nom']),
      villeId: parseStringOrNull(map['ville_id']),
      activiteId: parseStringOrNull(map['activite_id']),
      groupeTarifaireId: parseStringOrNull(map['groupe_tarifaire_id']),
      statut: StatutAbonnement.fromCode(parseStringOrNull(map['statut'])),
      montantTotalDu: montantTotal,
      montantDejaPaye: montantPaye,
      soldeRestant: soldeFourni
          ? parseDouble(map['solde_restant'])
          : (soldeCalcule > 0 ? soldeCalcule : 0.0),
      dateActivation: parseDateTimeOrNull(map['date_activation']),
      dateExpiration: parseDateTimeOrNull(map['date_expiration']),
      createdAt: parseDateTimeOrNull(map['created_at']),
      updatedAt: parseDateTimeOrNull(map['updated_at']),
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
    );
  }
}
