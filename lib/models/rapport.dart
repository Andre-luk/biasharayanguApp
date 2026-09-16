// lib/models/rapport.dart
//
// MODULE 11 — RAPPORTS & EXPORTS (modèles).
//
// Ce fichier ne contient que des objets de valeur PURS (aucun accès réseau,
// aucun import Flutter) : il est testable sans binding.
//
// Les RPC du Module 11 (`rpc_rapport_entreprise`, `rpc_rapport_plateforme`)
// renvoient tous la même ENVELOPPE :
//
//   {
//     "type":       "ventes_article",
//     "titre":      "Ventes par article",
//     "portee":     "entreprise" | "plateforme",
//     "debut":      "AAAA-MM-JJ",  "fin": "AAAA-MM-JJ",
//     "colonnes":   [ {"cle","libelle","type"} … ],
//     "lignes":     [ { "cle": valeur … } … ],
//     "totaux":     { "cle": valeur … },
//     "resume":     [ {"libelle","valeur","type"} … ],
//     "parametres": { … }
//   }
//
// Les mêmes modèles servent à l'écran d'aperçu, au PDF et à l'Excel : un seul
// formateur ([formaterValeurRapport]) garantit un rendu identique partout.

import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Espace auquel appartient un rapport.
enum EspaceRapport {
  entreprise('entreprise', 'Entreprise'),
  plateforme('plateforme', 'Plateforme La Perle');

  const EspaceRapport(this.code, this.libelle);

  final String code;
  final String libelle;
}

/// Type d'une valeur de colonne — détermine son formatage d'affichage.
enum TypeColonneRapport {
  texte('texte'),
  nombre('nombre'),
  montant('montant'),
  date('date'),
  pourcentage('pourcentage');

  const TypeColonneRapport(this.code);

  /// Valeur envoyée par le serveur.
  final String code;

  /// Convertit un code serveur en type de colonne (défaut : [texte]).
  static TypeColonneRapport fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final TypeColonneRapport type in values) {
      if (type.code == normalise) return type;
    }
    return TypeColonneRapport.texte;
  }
}

/// Groupement temporel proposé par certains rapports (ventes, comptes).
enum GroupePeriodeRapport {
  jour('jour', 'Par jour'),
  semaine('semaine', 'Par semaine'),
  mois('mois', 'Par mois');

  const GroupePeriodeRapport(this.code, this.libelle);

  final String code;
  final String libelle;
}

/// Format d'une opération tracée (registre des rapports).
enum FormatExportRapport {
  apercu('apercu', 'Aperçu'),
  pdf('pdf', 'PDF'),
  excel('excel', 'Excel'),
  partage('partage', 'Partage'),
  impression('impression', 'Impression');

  const FormatExportRapport(this.code, this.libelle);

  final String code;
  final String libelle;

  /// Convertit un code serveur en format (défaut : [apercu]).
  static FormatExportRapport fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final FormatExportRapport format in values) {
      if (format.code == normalise) return format;
    }
    return FormatExportRapport.apercu;
  }
}

/// Les types de rapports proposés par l'écran « Rapports ».
///
/// [code] est la valeur envoyée à la RPC ; [espace] indique si le rapport est
/// généré par `rpc_rapport_entreprise` ou `rpc_rapport_plateforme`.
enum TypeRapport {
  // ------------------------------------------------------------- entreprise
  ventes(
    'ventes',
    'Ventes par période',
    'Chiffre d\'affaires jour par jour, par semaine ou par mois',
    EspaceRapport.entreprise,
  ),
  ventesArticle(
    'ventes_article',
    'Ventes par article',
    'Quantités et chiffre d\'affaires de chaque article',
    EspaceRapport.entreprise,
  ),
  ventesCategorie(
    'ventes_categorie',
    'Ventes par catégorie',
    'Répartition du chiffre d\'affaires par catégorie d\'articles',
    EspaceRapport.entreprise,
  ),
  ventesVendeur(
    'ventes_vendeur',
    'Ventes par vendeur',
    'Activité et chiffre d\'affaires de chaque vendeur',
    EspaceRapport.entreprise,
  ),
  topProduits(
    'top_produits',
    'Produits les plus vendus',
    'Classement des articles par quantité vendue',
    EspaceRapport.entreprise,
  ),
  finance(
    'finance',
    'CA, dépenses & bénéfice',
    'Chiffre d\'affaires, coût des marchandises, dépenses et bénéfice net',
    EspaceRapport.entreprise,
  ),
  stock(
    'stock',
    'État du stock',
    'Stock actuel, seuils d\'alerte, ruptures et valeur du stock',
    EspaceRapport.entreprise,
  ),
  caisse(
    'caisse',
    'Caisse (entrées / sorties)',
    'Flux de caisse : encaissements, sorties et net par jour',
    EspaceRapport.entreprise,
  ),
  depenses(
    'depenses',
    'Dépenses',
    'Dépenses par catégorie ou détail ligne à ligne',
    EspaceRapport.entreprise,
  ),
  dettes(
    'dettes',
    'Dettes clients',
    'Restes à recouvrer, ancienneté et échéances des clients',
    EspaceRapport.entreprise,
  ),

  // ------------------------------------------------------------- plateforme
  plateformeRevenus(
    'revenus',
    'Revenus globaux',
    'Encaissements de la plateforme par mois et par type de paiement',
    EspaceRapport.plateforme,
  ),
  plateformeAbonnements(
    'abonnements_actifs',
    'Abonnements par statut',
    'Répartition des entreprises par statut d\'abonnement',
    EspaceRapport.plateforme,
  ),
  plateformeImpayes(
    'impayes',
    'Impayés',
    'Entreprises avec un solde restant dû',
    EspaceRapport.plateforme,
  ),
  plateformeVilles(
    'villes',
    'Revenus par ville',
    'Montants dus, encaissés et restants par ville',
    EspaceRapport.plateforme,
  ),
  plateformeActivites(
    'activites',
    'Revenus par activité',
    'Montants dus, encaissés et restants par activité',
    EspaceRapport.plateforme,
  ),
  plateformeNouveauxComptes(
    'nouveaux_comptes',
    'Nouveaux comptes',
    'Nouvelles entreprises et nouveaux utilisateurs par période',
    EspaceRapport.plateforme,
  );

  const TypeRapport(this.code, this.libelle, this.description, this.espace);

  /// Code envoyé à la RPC.
  final String code;

  /// Libellé affiché.
  final String libelle;

  /// Phrase d'explication affichée sous le sélecteur.
  final String description;

  /// Espace du rapport.
  final EspaceRapport espace;

  /// `true` pour un rapport de la plateforme La Perle.
  bool get estPlateforme => espace == EspaceRapport.plateforme;

  /// Types d'un espace donné, dans l'ordre de déclaration.
  static List<TypeRapport> deEspace(EspaceRapport espace) => values
      .where((TypeRapport type) => type.espace == espace)
      .toList(growable: false);

  /// Convertit un code serveur en type de rapport (`null` si inconnu).
  static TypeRapport? fromCode(String? code) {
    final String normalise = (code ?? '').trim().toLowerCase();
    for (final TypeRapport type in values) {
      if (type.code == normalise) return type;
    }
    return null;
  }
}

/// Statuts lisibles (stock, dettes, abonnements) pour les exports.
const Map<String, String> _libellesStatutsRapport = <String, String>{
  'non_paye': 'Non payé',
  'partiel': 'Partiel',
  'paye': 'Payé',
  'ok': 'OK',
  'faible': 'Faible',
  'rupture': 'Rupture',
  'actif': 'Actif',
  'essai_7j': 'Essai 7 jours',
  'expire': 'Expiré',
  'suspendu': 'Suspendu',
  'en_attente_complement': 'Attente de complément',
  'inconnu': 'Inconnu',
};

/// Rend un statut technique lisible (« non_paye » → « Non payé »).
String libelleStatutRapport(String brut) {
  final String normalise = brut.trim().toLowerCase();
  return _libellesStatutsRapport[normalise] ?? brut;
}

/// Formate une valeur de rapport selon le type de sa colonne.
///
/// Utilisé par l'écran d'aperçu, le PDF et (indirectement) l'Excel : c'est le
/// formatage franchement commun du module.
String formaterValeurRapport(Object? valeur, TypeColonneRapport type) {
  if (valeur == null) return '—';

  switch (type) {
    case TypeColonneRapport.texte:
      final String texte = valeur.toString().trim();
      if (texte.isEmpty) return '—';
      return libelleStatutRapport(texte);

    case TypeColonneRapport.nombre:
      final double? quantite = _enDouble(valeur);
      if (quantite == null) return valeur.toString();
      return formatQuantite(quantite);

    case TypeColonneRapport.montant:
      final double? montant = _enDouble(valeur);
      if (montant == null) return valeur.toString();
      return formatMontant(montant);

    case TypeColonneRapport.date:
      if (valeur is DateTime) return formatDate(valeur);
      final DateTime? date = DateTime.tryParse(valeur.toString());
      return date == null ? valeur.toString() : formatDate(date);

    case TypeColonneRapport.pourcentage:
      final double? part = _enDouble(valeur);
      if (part == null) return valeur.toString();
      // Séparateur décimal français (la valeurs est arrondie au 0,1).
      final String texte = part
          .toStringAsFixed(1)
          .replaceAll(RegExp(r'\.0$'), '')
          .replaceAll('.', ',');
      return '$texte %';
  }
}

double? _enDouble(Object? valeur) {
  if (valeur is num) return valeur.toDouble();
  if (valeur is String) return double.tryParse(valeur.replaceAll(',', '.'));
  return null;
}

/// Une colonne d'un rapport.
class ColonneRapport {
  const ColonneRapport({
    required this.cle,
    required this.libelle,
    required this.type,
  });

  /// Clé technique dans les lignes/totaux.
  final String cle;

  /// En-tête affiché.
  final String libelle;

  /// Type de formatage.
  final TypeColonneRapport type;

  factory ColonneRapport.depuisJson(Map<String, dynamic> map) {
    return ColonneRapport(
      cle: parseString(map['cle']),
      libelle: parseString(map['libelle'], fallback: parseString(map['cle'])),
      type: TypeColonneRapport.fromCode(parseStringOrNull(map['type'])),
    );
  }

  @override
  String toString() => '$libelle ($cle, ${type.code})';
}

/// Un indicateur du bandeau « résumé » (CA, marge, nombre d'alertes…).
class LigneResumeRapport {
  const LigneResumeRapport({
    required this.libelle,
    required this.valeur,
    required this.type,
  });

  final String libelle;
  final Object? valeur;
  final TypeColonneRapport type;

  /// Valeur déjà formatée pour l'affichage.
  String get valeurFormatee => formaterValeurRapport(valeur, type);

  /// La valeur est-elle numérique (pour un éventuel alignement) ?
  bool get estNumerique =>
      type == TypeColonneRapport.montant ||
      type == TypeColonneRapport.nombre ||
      type == TypeColonneRapport.pourcentage;

  factory LigneResumeRapport.depuisJson(Map<String, dynamic> map) {
    return LigneResumeRapport(
      libelle: parseString(map['libelle']),
      valeur: map['valeur'],
      type: TypeColonneRapport.fromCode(parseStringOrNull(map['type'])),
    );
  }
}

/// Données complètes d'un rapport prêt à afficher / exporter.
class RapportDonnees {
  const RapportDonnees({
    required this.type,
    required this.titre,
    required this.portee,
    required this.debut,
    required this.fin,
    required this.colonnes,
    required this.lignes,
    required this.totaux,
    required this.resume,
    required this.parametres,
  });

  /// Code du type de rapport (ex. `ventes_article`).
  final String type;

  /// Titre affiché / imprimé.
  final String titre;

  /// `entreprise` ou `plateforme`.
  final String portee;

  /// Première date couverte (incluse), si le rapport a une période.
  final DateTime? debut;

  /// Dernière date couverte (incluse).
  final DateTime? fin;

  /// Colonnes à afficher, dans l'ordre.
  final List<ColonneRapport> colonnes;

  /// Lignes de données (chaque ligne = map clé → valeur).
  final List<Map<String, dynamic>> lignes;

  /// Ligne de totaux (sous-ensemble des clés des colonnes).
  final Map<String, dynamic> totaux;

  /// Bandeau d'indicateurs.
  final List<LigneResumeRapport> resume;

  /// Filtres normalisés renvoyés par le serveur (écho).
  final Map<String, dynamic> parametres;

  /// Le rapport ne contient aucune ligne.
  bool get estVide => lignes.isEmpty;

  /// Type applicatif (si connu de cette version de l'application).
  TypeRapport? get typeRapport => TypeRapport.fromCode(type);

  /// Période affichable (« 01/09/2026 au 30/09/2026 »), ou `null`.
  String? get periodeTexte {
    if (debut == null && fin == null) return null;
    return '${formatDate(debut, valeurAbsente: '…')} au ${formatDate(fin, valeurAbsente: '…')}';
  }

  /// Valeur brute d'une cellule (utilisée par l'export Excel).
  Object? valeur(Map<String, dynamic> ligne, ColonneRapport colonne) =>
      ligne[colonne.cle];

  /// Valeur d'une cellule formatée pour l'affichage / le PDF.
  String valeurFormatee(Map<String, dynamic> ligne, ColonneRapport colonne) =>
      formaterValeurRapport(ligne[colonne.cle], colonne.type);

  /// `true` si la colonne possède un total renseigné.
  bool aTotal(ColonneRapport colonne) =>
      totaux.containsKey(colonne.cle) && totaux[colonne.cle] != null;

  /// Total formaté d'une colonne (`null` si absent).
  String? totalFormate(ColonneRapport colonne) {
    if (!aTotal(colonne)) return null;
    return formaterValeurRapport(totaux[colonne.cle], colonne.type);
  }

  factory RapportDonnees.depuisRpc(Map<String, dynamic> map) {
    return RapportDonnees(
      type: parseString(map['type']),
      titre: parseString(map['titre'], fallback: 'Rapport'),
      portee: parseString(map['portee'], fallback: 'entreprise'),
      debut: parseDateTimeOrNull(map['debut']),
      fin: parseDateTimeOrNull(map['fin']),
      colonnes: parseMapList(map['colonnes'])
          .map(ColonneRapport.depuisJson)
          .toList(growable: false),
      lignes: parseMapList(map['lignes']),
      totaux: parseMap(map['totaux']) ?? const <String, dynamic>{},
      resume: parseMapList(map['resume'])
          .map(LigneResumeRapport.depuisJson)
          .toList(growable: false),
      parametres: parseMap(map['parametres']) ?? const <String, dynamic>{},
    );
  }
}

/// Résultat d'une génération : données + référence + empreinte.
///
/// La [reference] (« RPT-AAAAMMJJ-XXXXXX ») identifie l'opération dans le
/// registre `rapports_generes` ; l'[empreinte] est le SHA-256 du contenu (les
/// exports la portent pour être « signés » et vérifiables).
class ResultatRapport {
  const ResultatRapport({
    required this.donnees,
    required this.reference,
    required this.empreinte,
  });

  final RapportDonnees donnees;
  final String reference;
  final String empreinte;
}

/// Une ligne de l'historique des rapports générés (`rpc_rapports_historique`).
class EntreeHistoriqueRapport {
  const EntreeHistoriqueRapport({
    required this.id,
    required this.typeRapport,
    required this.portee,
    required this.format,
    required this.debut,
    required this.fin,
    required this.reference,
    required this.empreinte,
    required this.utilisateur,
    required this.createdAt,
  });

  final int id;

  /// Code du type de rapport.
  final String typeRapport;
  final String portee;
  final FormatExportRapport format;
  final DateTime? debut;
  final DateTime? fin;
  final String reference;
  final String? empreinte;
  final String utilisateur;
  final DateTime? createdAt;

  /// Libellé du type si connu.
  String get libelleType =>
      TypeRapport.fromCode(typeRapport)?.libelle ?? typeRapport;

  /// Période affichable.
  String? get periodeTexte {
    if (debut == null && fin == null) return null;
    return '${formatDate(debut, valeurAbsente: '…')} au ${formatDate(fin, valeurAbsente: '…')}';
  }

  factory EntreeHistoriqueRapport.depuisJson(Map<String, dynamic> map) {
    return EntreeHistoriqueRapport(
      id: parseInt(map['id']),
      typeRapport: parseString(map['type_rapport']),
      portee: parseString(map['portee'], fallback: 'entreprise'),
      format: FormatExportRapport.fromCode(parseStringOrNull(map['format'])),
      debut: parseDateTimeOrNull(map['debut']),
      fin: parseDateTimeOrNull(map['fin']),
      reference: parseString(map['reference']),
      empreinte: parseStringOrNull(map['empreinte']),
      utilisateur: parseString(map['utilisateur']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }
}
