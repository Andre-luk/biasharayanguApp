// lib/models/groupe_tarifaire.dart
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/type_activite.dart';
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

  /// 🧩 MODULE 16 E (packs par modules) — modules autorisés par le pack.
  /// Vide = AUCUN filtre : tous les modules du profil de l'activité.
  final Set<String> modules;

  final DateTime? createdAt;

  /// 🏪 TYPE D'ACTIVITÉ du pack (migration 0083).
  ///
  /// `null` = pack COMMUN : proposé à toutes les entreprises. Un pack
  /// réservé à la distribution ne doit pas apparaître pour une boutique, et
  /// inversement — mais un type non renseigné ne masque jamais rien
  /// (règle fail-open de `ReglesTypeActivite`).
  final TypeActivite? typeActivite;

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
    this.modules = const <String>{},
    this.createdAt,
    this.typeActivite,
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
      // 🧩 MODULE 16 E — modules du pack ([] = aucun filtre).
      modules: ProfilModules.modulesDepuisJson(map['modules']),
      createdAt: parseDateTimeOrNull(map['created_at']),
      typeActivite:
          TypeActivite.depuis(parseStringOrNull(map['type_activite'])),
    );
  }

  /// Ce pack est-il proposable à une entreprise de type [connu] ?
  ///
  /// Vrai tant que le type de l'entreprise ou celui du pack n'est pas connu :
  /// on préfère proposer un pack de trop que de bloquer une souscription.
  bool proposableA(TypeActivite? connu) =>
      !ReglesTypeActivite.masque(connu, typeActivite);

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
      'modules': modules.toList(growable: false),
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

  /// 🧩 MODULE 16 E — ce pack limite-t-il les modules ?
  bool get filtreModules => modules.isNotEmpty;

  /// Résumé lisible des modules du pack (« 5 modules » / « tous »).
  String get resumeModules =>
      modules.isEmpty ? 'Tous modules' : '${modules.length} modules';

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
    Set<String>? modules,
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
      modules: modules ?? this.modules,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
