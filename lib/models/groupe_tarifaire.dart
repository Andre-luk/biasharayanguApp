// lib/models/groupe_tarifaire.dart
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Grille tarifaire d'une activité — table `public.groupes_tarifaires`.
///
/// Le groupe tarifaire porte toutes les valeurs financières utilisées lors de
/// la création d'une entreprise : montant de l'abonnement, frais d'ouverture
/// et durées d'essai / d'abonnement.
class GroupeTarifaire {
  final String id;
  final String? activiteId;
  final String nom;
  final double fraisOuverture;
  final double montantAbonnement;
  final int dureeEssaiJours;
  final int dureeAbonnementJours;
  final double prixParCollaborateur;

  /// 🏢 MODULE 15 — nombre d'entreprises autorisées par le pack
  /// (1 = mono-entreprise, 3 = pack avancé multi-entreprises…).
  final int maxEspaces;

  final DateTime? createdAt;

  const GroupeTarifaire({
    required this.id,
    this.activiteId,
    required this.nom,
    this.fraisOuverture = 0,
    this.montantAbonnement = 0,
    this.dureeEssaiJours = 0,
    this.dureeAbonnementJours = 0,
    this.prixParCollaborateur = 0,
    this.maxEspaces = 1,
    this.createdAt,
  });

  factory GroupeTarifaire.fromMap(Map<String, dynamic> map) {
    final int max = parseInt(map['max_espaces'], fallback: 1);

    return GroupeTarifaire(
      id: parseString(map['id']),
      activiteId: parseStringOrNull(map['activite_id']),
      nom: parseString(map['nom']),
      fraisOuverture: parseDouble(map['frais_ouverture']),
      montantAbonnement: parseDouble(map['montant_abonnement']),
      dureeEssaiJours: parseInt(map['duree_essai_jours']),
      dureeAbonnementJours: parseInt(map['duree_abonnement_jours']),
      prixParCollaborateur: parseDouble(map['prix_par_collaborateur']),
      maxEspaces: max < 1 ? 1 : max,
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'activite_id': activiteId,
      'nom': nom,
      'frais_ouverture': fraisOuverture,
      'montant_abonnement': montantAbonnement,
      'duree_essai_jours': dureeEssaiJours,
      'duree_abonnement_jours': dureeAbonnementJours,
      'prix_par_collaborateur': prixParCollaborateur,
      'max_espaces': maxEspaces,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// Durée d'essai lisible : `7` devient `7 jours`.
  String get dureeEssaiLibelle =>
      '$dureeEssaiJours ${dureeEssaiJours > 1 ? 'jours' : 'jour'}';

  /// Durée d'abonnement lisible : `30` devient `30 jours`.
  String get dureeAbonnementLibelle =>
      '$dureeAbonnementJours ${dureeAbonnementJours > 1 ? 'jours' : 'jour'}';

  /// 🏢 MODULE 15 — ce pack autorise-t-il plusieurs entreprises ?
  bool get packMulti => maxEspaces > 1;

  GroupeTarifaire copyWith({
    String? id,
    String? activiteId,
    String? nom,
    double? fraisOuverture,
    double? montantAbonnement,
    int? dureeEssaiJours,
    int? dureeAbonnementJours,
    double? prixParCollaborateur,
    int? maxEspaces,
    DateTime? createdAt,
  }) {
    return GroupeTarifaire(
      id: id ?? this.id,
      activiteId: activiteId ?? this.activiteId,
      nom: nom ?? this.nom,
      fraisOuverture: fraisOuverture ?? this.fraisOuverture,
      montantAbonnement: montantAbonnement ?? this.montantAbonnement,
      dureeEssaiJours: dureeEssaiJours ?? this.dureeEssaiJours,
      dureeAbonnementJours: dureeAbonnementJours ?? this.dureeAbonnementJours,
      prixParCollaborateur: prixParCollaborateur ?? this.prixParCollaborateur,
      maxEspaces: maxEspaces ?? this.maxEspaces,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
