// lib/models/article.dart
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/statut_expiration.dart';
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

  /// 🏷️ CORRECTIF 59 — code-barres FABRICANT du produit (EAN-13, UPC,
  /// Code 128, ITF…), valable pour son UNITÉ DE BASE.
  ///
  /// `null` = non renseigné. Unique par patron : deux produits du même
  /// patron ne peuvent pas porter le même code (sinon un scan serait
  /// ambigu et vendrait le mauvais article).
  final String? codeBarre;

  final String? photo;
  final String? description;

  /// 🧩 MODULE 16 C1 (pharmacie) — numéro de lot (facultatif).
  final String? lotNumero;

  /// 🧩 MODULE 16 C1 — date de péremption (facultatif). Une fois dépassée,
  /// la vente est refusée par le serveur (réglage du blocage côté base).
  final DateTime? dateExpiration;

  /// 🥩 MODULE 16 C6 (boucherie) — l'article se vend AU POIDS (kg) : la
  /// caisse propose la saisie du poids (0,75 kg, pas de 0,5 kg).
  final bool vendableAuPoids;

  /// ⚡ MODULE 23 — MODE RAPIDE : le stock n'est pas suivi.
  ///
  /// L'article se vend sans contrôle de quantité ; les écrans de stock
  /// l'affichent « ∞ » et ne le comptent pas dans les alertes de rupture.
  final bool stockIllimite;

  /// 👕 MODULE 16 C8 (mode) — variantes simples : {taille, couleur,
  /// marque…} (objet JSON libre, vide si aucune).
  final Map<String, String> attributs;

  /// 💵 MODULE 29 — DEVISE DU PRIX DE CET ARTICLE (`CDF`, `USD`).
  ///
  /// `null` = la devise de l'entreprise. Dans une même boutique, un article
  /// peut être affiché en dollars et l'autre en francs : c'est le prix SAISI
  /// qui est conservé, la conversion se fait à la vente (taux du jour).
  final String? devise;

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
    this.codeBarre,
    this.photo,
    this.description,
    this.lotNumero,
    this.dateExpiration,
    this.vendableAuPoids = false,
    this.stockIllimite = false,
    this.attributs = const <String, String>{},
    this.devise,
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
      codeBarre: parseStringOrNull(map['code_barre']),
      photo: parseStringOrNull(map['photo']),
      description: parseStringOrNull(map['description']),
      lotNumero: parseStringOrNull(map['lot_numero']),
      dateExpiration: parseDateTimeOrNull(map['date_expiration']),
      vendableAuPoids: map['vendable_au_poids'] == true,
      stockIllimite: map['stock_illimite'] == true,
      attributs: _attributsDepuisJson(map['attributs']),
      devise: parseStringOrNull(map['devise']),
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
      'lot_numero': lotNumero,
      'date_expiration':
          dateExpiration == null ? null : _isoJour(dateExpiration!),
      // 🥩 MODULE 16 C6 — vente au poids (boucherie).
      'vendable_au_poids': vendableAuPoids,
      // ⚡ MODULE 23 — stock non suivi (mode rapide). La clé n'est envoyée
      //  que si elle est vraie : une base non migrée continue de fonctionner.
      if (stockIllimite) 'stock_illimite': true,
      // 👕 MODULE 16 C8 — variantes (mode).
      'attributs': attributs,
      // 💵 MODULE 29 — devise du prix, si elle diffère de celle de
      //  l'entreprise. Envoyée uniquement si renseignée : une base non
      //  migrée continue de fonctionner.
      if ((devise ?? '').trim().isNotEmpty) 'devise': devise!.trim(),
    };
  }

  /// Date au format « AAAA-MM-JJ » attendu par la colonne `date` de Supabase.
  static String _isoJour(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
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
    String? codeBarre,
    String? photo,
    String? description,
    String? lotNumero,
    DateTime? dateExpiration,
    bool? vendableAuPoids,
    bool? stockIllimite,
    Map<String, String>? attributs,
    String? devise,
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
      codeBarre: codeBarre ?? this.codeBarre,
      photo: photo ?? this.photo,
      description: description ?? this.description,
      lotNumero: lotNumero ?? this.lotNumero,
      dateExpiration: dateExpiration ?? this.dateExpiration,
      vendableAuPoids: vendableAuPoids ?? this.vendableAuPoids,
      stockIllimite: stockIllimite ?? this.stockIllimite,
      attributs: attributs ?? this.attributs,
      devise: devise ?? this.devise,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      conditionnements: conditionnements ?? this.conditionnements,
    );
  }

  /// Nombre de conditionnements (colonne de l'écran « Liste des articles »).
  int get nombreConditionnements => conditionnements.length;

  /// Statut d'alerte du stock (Module 9) : OK / Faible / Rupture.
  ///
  /// ⚡ MODE RAPIDE — un article à stock non suivi n'est JAMAIS en alerte.
  StatutStock get statutStock => stockIllimite
      ? StatutStock.ok
      : StatutStock.depuisStock(
          quantite: quantite,
          seuilAlerte: seuilAlerte,
        );

  /// Quantité affichable : « ∞ » pour un article du mode rapide.
  String get stockAffiche => stockIllimite ? '∞' : '${quantite.round()}';

  /// 🧩 MODULE 16 C1 (pharmacie) — statut d'expiration (`null` si l'article
  /// n'a pas de date de péremption).
  StatutExpiration? get statutExpiration =>
      StatutExpiration.depuis(dateExpiration);

  /// 🧮 CORRECTIF 72 — statut avec le délai RÉGLÉ PAR LA BOUTIQUE.
  ///
  /// C'est la version à utiliser dès qu'on alerte l'utilisateur : le délai de
  /// 30 jours codé en dur ne convient ni à une pharmacie (90 jours) ni à une
  /// épicerie (7 jours). Le getter [statutExpiration] reste, avec le délai par
  /// défaut, pour les appels qui n'ont pas accès au réglage.
  StatutExpiration? statutExpirationSelon(int joursProches) =>
      StatutExpiration.depuis(dateExpiration, joursProches: joursProches);

  /// L'article demande-t-il une action, selon le délai de la boutique ?
  bool estUrgentSelon(int joursProches) =>
      statutExpirationSelon(joursProches)?.estUrgent ?? false;

  /// L'article est-il expiré (date dépassée) ?
  ///
  /// ⚠️ Indépendant du délai d'alerte : « expiré » ne se négocie pas, seule
  /// l'anticipation se règle.
  bool get estExpire => statutExpiration == StatutExpiration.expire;

  /// L'article expire-t-il bientôt (≤ 30 jours) ?
  bool get expireBientot => statutExpiration == StatutExpiration.proche;

  /// L'article a-t-il une date de péremption ?
  bool get aDateExpiration => dateExpiration != null;

  /// 👕 MODULE 16 C8 (mode) — l'article a-t-il des variantes ?
  bool get aVariantes => attributs.isNotEmpty;

  /// Taille saisie (« M », « 42 »…), ou `null`.
  String? get taille => attributs['taille'];

  /// Couleur saisie, ou `null`.
  String? get couleur => attributs['couleur'];

  /// Marque saisie, ou `null`.
  String? get marque => attributs['marque'];

  /// Résumé lisible (« M · Bleu · Casino »), vide si aucun attribut.
  /// Les trois clés connues passent d'abord, puis les autres.
  String get resumeVariantes {
    if (attributs.isEmpty) return '';
    const List<String> ordre = <String>['taille', 'couleur', 'marque'];
    final List<String> parties = <String>[];
    for (final String cle in ordre) {
      final String? valeur = attributs[cle];
      if (valeur != null && valeur.isNotEmpty) parties.add(valeur);
    }
    attributs.forEach((String cle, String valeur) {
      if (!ordre.contains(cle) && valeur.isNotEmpty) parties.add(valeur);
    });
    return parties.join(' · ');
  }

  /// Convertit le jsonb `attributs` en map texte (clés/valeurs vides
  /// écartées, valeurs non textuelles converties en texte).
  static Map<String, String> _attributsDepuisJson(dynamic brut) {
    final Map<String, dynamic>? map = parseMap(brut);
    if (map == null || map.isEmpty) return const <String, String>{};

    final Map<String, String> resultat = <String, String>{};
    map.forEach((String cle, dynamic valeur) {
      final String texte = parseString(valeur).trim();
      if (cle.trim().isNotEmpty && texte.isNotEmpty) {
        resultat[cle.trim()] = texte;
      }
    });
    return resultat;
  }

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
