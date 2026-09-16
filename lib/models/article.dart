// lib/models/article.dart
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/statut_stock.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Article vendu par une boutique — table `public.produits`.
///
/// Un article est toujours décrit dans SON UNITÉ DE BASE (« bouteille »,
/// « pièce », « kg »…). Les emballages vendables (farde, carton…) vivent
/// dans la table [Conditionnement] :
///
///   • [quantite] — stock disponible exprimé en unités de base ;
///   • [prixAchat] / [prixVente] — prix de l'UNITÉ DE BASE ;
///   • [categorie] — nom de la catégorie ('' si aucune) ;
///   • [seuilAlerte] — seuil d'alerte du Module 9 (5 par défaut) ;
///   • [ownerId] — propriétaire de la boutique (le patron).
class Article {
  final int id;
  final String nom;
  final String categorie;
  final double prixAchat;
  final double prixVente;
  final double quantite;
  final String uniteMesure;
  final double seuilAlerte;
  final String? photo;
  final String? description;
  final String? ownerId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Conditionnements de l'article. Rempli par `ArticleService` lors des
  /// lectures ; vide sur un article qui vient d'être créé.
  final List<Conditionnement> conditionnements;

  const Article({
    required this.id,
    required this.nom,
    this.categorie = '',
    this.prixAchat = 0,
    this.prixVente = 0,
    this.quantite = 0,
    this.uniteMesure = 'unité',
    this.seuilAlerte = 5,
    this.photo,
    this.description,
    this.ownerId,
    this.createdAt,
    this.updatedAt,
    this.conditionnements = const <Conditionnement>[],
  });

  factory Article.fromMap(
    Map<String, dynamic> map, {
    List<Conditionnement> conditionnements = const <Conditionnement>[],
  }) {
    return Article(
      id: parseInt(map['id']),
      nom: parseString(map['nom']),
      categorie: parseString(map['categorie']),
      prixAchat: parseDouble(map['prix_achat']),
      prixVente: parseDouble(map['prix_vente']),
      quantite: parseDouble(map['quantite']),
      uniteMesure: parseString(map['unite_mesure'], fallback: 'unité'),
      seuilAlerte: parseDouble(map['seuil_alerte'], fallback: 5),
      photo: parseStringOrNull(map['photo']),
      description: parseStringOrNull(map['description']),
      ownerId: parseStringOrNull(map['owner_id']),
      createdAt: parseDateTimeOrNull(map['created_at']),
      updatedAt: parseDateTimeOrNull(map['updated_at']),
      conditionnements: conditionnements,
    );
  }

  /// Corps d'insertion / mise à jour envoyé à Supabase.
  ///
  /// L'`id` est généré par la base et l'`owner_id` est posé par le service
  /// à la création : aucun des deux ne figure ici.
  Map<String, dynamic> toMap() {
    return {
      'nom': nom,
      'categorie': categorie,
      'prix_achat': prixAchat,
      'prix_vente': prixVente,
      'quantite': quantite,
      'unite_mesure': uniteMesure,
      'photo': photo,
      'description': description,
    };
  }

  Article copyWith({
    int? id,
    String? nom,
    String? categorie,
    double? prixAchat,
    double? prixVente,
    double? quantite,
    String? uniteMesure,
    double? seuilAlerte,
    String? photo,
    String? description,
    String? ownerId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Conditionnement>? conditionnements,
  }) {
    return Article(
      id: id ?? this.id,
      nom: nom ?? this.nom,
      categorie: categorie ?? this.categorie,
      prixAchat: prixAchat ?? this.prixAchat,
      prixVente: prixVente ?? this.prixVente,
      quantite: quantite ?? this.quantite,
      uniteMesure: uniteMesure ?? this.uniteMesure,
      seuilAlerte: seuilAlerte ?? this.seuilAlerte,
      photo: photo ?? this.photo,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      conditionnements: conditionnements ?? this.conditionnements,
    );
  }

  /// Nombre de conditionnements (colonne de l'écran « Liste des articles »).
  int get nombreConditionnements => conditionnements.length;

  /// Statut d'alerte du stock (Module 9) : OK / Faible / Rupture.
  StatutStock get statutStock => StatutStock.depuisStock(
        quantite: quantite,
        seuilAlerte: seuilAlerte,
      );

  /// Stock total en unités de base, formule du cahier des charges :
  ///
  ///   stock total = stock base + (exemplaires de conditionnement × unités
  ///                              de base par conditionnement)
  ///
  /// Le stock saisi par défaut ([stockBase] = [quantite]) est déjà exprimé en
  /// unités de base : passer [nombreExemplaires] > 0 permet de calculer le
  /// stock lorsqu'on ajoute des emballages complets (ex. 10 fardes de 12 en
  /// plus des 34 bouteilles existantes → 154 bouteilles).
  static double stockTotal({
    required double stockBase,
    double nombreExemplaires = 0,
    double quantiteUnitesBase = 0,
  }) {
    return stockBase + nombreExemplaires * quantiteUnitesBase;
  }

  /// Même formule appliquée au stock actuel de cet article.
  double stockTotalAvecConditionnement(
    Conditionnement conditionnement, {
    double nombreExemplaires = 1,
  }) {
    return stockTotal(
      stockBase: quantite,
      nombreExemplaires: nombreExemplaires,
      quantiteUnitesBase: conditionnement.quantiteUnitesBase,
    );
  }
}
