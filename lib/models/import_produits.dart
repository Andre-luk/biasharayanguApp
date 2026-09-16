// lib/models/import_produits.dart
//
// MODULE 12 — MODÈLES DE L'IMPORT RAPIDE D'ARTICLES.
//
// L'import passe par la RPC serveur `rpc_produits_importer(jsonb, boolean)` :
//   • jusqu'à 500 lignes par appel (le service découpe automatiquement) ;
//   • doublons par nom : ignorés (défaut) ou mis à jour — JAMAIS la quantité
//     (le stock ne bouge que par les mouvements tracés du Module 9) ;
//   • l'opération est journalisée en UNE entrée `IMPORT_PRODUITS` (niveau HAUT).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Une ligne d'import prête à envoyer au serveur.
class LigneImport {
  const LigneImport({
    required this.nom,
    this.categorie,
    this.prixAchat = 0,
    this.prixVente = 0,
    this.quantite = 0,
    this.uniteMesure,
    this.description,
    this.ligneSource,
  });

  final String nom;
  final String? categorie;
  final double prixAchat;
  final double prixVente;
  final double quantite;
  final String? uniteMesure;
  final String? description;

  /// Numéro de ligne dans le fichier d'origine (information utilisateur).
  final int? ligneSource;

  /// Charge utile JSON attendue par `rpc_produits_importer`.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'nom': nom,
      if (categorie != null && categorie!.isNotEmpty) 'categorie': categorie,
      'prix_achat': prixAchat,
      'prix_vente': prixVente,
      'quantite': quantite,
      if (uniteMesure != null && uniteMesure!.isNotEmpty)
        'unite_mesure': uniteMesure,
      if (description != null && description!.isNotEmpty)
        'description': description,
    };
  }
}

/// Une ligne refusée par l'analyse, avec son motif (en français).
class ErreurImport {
  const ErreurImport({
    required this.ligne,
    required this.message,
    this.nom,
  });

  /// Numéro de ligne dans le fichier d'origine (1 = première ligne).
  final int ligne;

  final String message;

  /// Nom lu sur la ligne (quand il a pu être extrait).
  final String? nom;

  static ErreurImport? depuisJson(dynamic valeur) {
    final Map<String, dynamic>? map = parseMap(valeur);
    if (map == null) return null;
    return ErreurImport(
      ligne: parseInt(map['ligne']),
      message: parseString(map['message'], fallback: 'Ligne refusée.'),
      nom: parseStringOrNull(map['nom']),
    );
  }
}

/// Résultat de l'analyse locale d'un contenu CSV (avant tout appel réseau).
class AnalyseImport {
  const AnalyseImport({
    required this.lignes,
    required this.erreurs,
    required this.enteteDetectee,
    required this.colonnesUtilisees,
    required this.colonnesInconnues,
    required this.totalLignes,
    this.erreurGlobale,
  });

  const AnalyseImport.vide({this.erreurGlobale})
      : lignes = const <LigneImport>[],
        erreurs = const <ErreurImport>[],
        enteteDetectee = false,
        colonnesUtilisees = const <String>[],
        colonnesInconnues = const <String>[],
        totalLignes = 0;

  final List<LigneImport> lignes;
  final List<ErreurImport> erreurs;

  /// `true` si la ligne d'en-tête contient au moins la colonne « nom ».
  final bool enteteDetectee;

  /// Colonnes reconnues (clés techniques : `nom`, `prix_vente`…).
  final List<String> colonnesUtilisees;

  /// En-têtes présents dans le fichier mais ignorés (tolérance).
  final List<String> colonnesInconnues;

  /// Nombre de lignes de données lues (hors en-tête, hors lignes vides).
  final int totalLignes;

  /// Message bloquant (fichier vide, en-tête introuvable…).
  final String? erreurGlobale;

  bool get exploitable => erreurGlobale == null && enteteDetectee && lignes.isNotEmpty;
  int get nbValides => lignes.length;
  int get nbErreurs => erreurs.length;
}

/// Résultat d'un import exécuté côté serveur (cumul des tranches de 500).
class ResultatImport {
  const ResultatImport({
    required this.nbLignes,
    required this.crees,
    required this.misAJour,
    required this.ignores,
    required this.erreurs,
  });

  const ResultatImport.vide()
      : nbLignes = 0,
        crees = 0,
        misAJour = 0,
        ignores = 0,
        erreurs = const <ErreurImport>[];

  final int nbLignes;
  final int crees;
  final int misAJour;
  final int ignores;
  final List<ErreurImport> erreurs;

  bool get aDesErreurs => erreurs.isNotEmpty;

  static ResultatImport? depuisRpc(dynamic reponse) {
    final Map<String, dynamic>? map = parseMap(reponse);
    if (map == null) return null;

    return ResultatImport(
      nbLignes: parseInt(map['nb_lignes']),
      crees: parseInt(map['crees']),
      misAJour: parseInt(map['mis_a_jour']),
      ignores: parseInt(map['ignores']),
      erreurs: parseMapList(map['erreurs'])
          .map(ErreurImport.depuisJson)
          .whereType<ErreurImport>()
          .toList(growable: false),
    );
  }

  /// Cumule deux résultats (l'import est découpé en tranches de 500 lignes).
  ///
  /// [decalageLignes] renumérote les erreurs pour qu'elles pointent la ligne
  /// d'origine du fichier complet.
  ResultatImport fusionner(ResultatImport autre, {int decalageLignes = 0}) {
    return ResultatImport(
      nbLignes: nbLignes + autre.nbLignes,
      crees: crees + autre.crees,
      misAJour: misAJour + autre.misAJour,
      ignores: ignores + autre.ignores,
      erreurs: <ErreurImport>[
        ...erreurs,
        ...autre.erreurs.map(
          (ErreurImport e) => ErreurImport(
            ligne: e.ligne + decalageLignes,
            message: e.message,
            nom: e.nom,
          ),
        ),
      ],
    );
  }
}
