// lib/utils/import_csv.dart
//
// MODULE 12 — LECTURE TOLÉRANTE D'UN CONTENU CSV / TSV POUR L'IMPORT.
//
// Objectif : importer rapidement un catalogue d'articles sans ordinateur —
// l'utilisateur colle (ou choisit) un fichier exporté d'Excel, de WhatsApp ou
// d'un fournisseur, et l'application en extrait des lignes propres.
//
// Tolérances volontaires :
//   • séparateurs `;`, `,` ou tabulation (détecté automatiquement) ;
//   • guillemets `"…"` avec doubles guillemets échappés (`""`) ;
//   • en-têtes en français avec ou sans accents, majuscules/minuscules,
//     espaces, underscores (« Prix d'achat », « PRIX_ACHAT », « qte »…) ;
//   • nombres au format français (« 1 500,50 ») ou anglo-saxon (« 1,500.50 »),
//     symboles monétaires ignorés (« 1500 CDF ») ;
//   • colonnes inconnues ignorées, lignes vides sautées, BOM Excel retiré.
//
// Ce fichier est PUR (aucun import Flutter, aucun accès réseau) : toute la
// logique est testable sans binding (voir `test/import_produits_test.dart`).

import 'package:biashara_yangu/models/import_produits.dart';

/// Analyse d'un contenu CSV/TSV d'articles.
class ImportCsv {
  const ImportCsv._();

  /// Alias d'en-têtes acceptés (clés déjà normalisées par [normaliserEntete]).
  static const Map<String, String> _alias = <String, String>{
    // — nom —
    'nom': 'nom',
    'article': 'nom',
    'articles': 'nom',
    'produit': 'nom',
    'produits': 'nom',
    'designation': 'nom',
    'libelle': 'nom',
    'intitule': 'nom',
    // — catégorie —
    'categorie': 'categorie',
    'famille': 'categorie',
    'rayon': 'categorie',
    'categorie article': 'categorie',
    // — prix d'achat —
    'prix achat': 'prix_achat',
    'prix d achat': 'prix_achat',
    'prix de l achat': 'prix_achat',
    'prixachat': 'prix_achat',
    'prixdachat': 'prix_achat',
    'achat': 'prix_achat',
    'pa': 'prix_achat',
    'cout': 'prix_achat',
    // — prix de vente —
    'prix vente': 'prix_vente',
    'prix de vente': 'prix_vente',
    'prixvente': 'prix_vente',
    'prixdvente': 'prix_vente',
    'vente': 'prix_vente',
    'pv': 'prix_vente',
    'prix': 'prix_vente',
    'prix unitaire': 'prix_vente',
    // — quantité —
    'quantite': 'quantite',
    'qte': 'quantite',
    'qty': 'quantite',
    'stock': 'quantite',
    'quantite stock': 'quantite',
    'nombre': 'quantite',
    'quantite initiale': 'quantite',
    // — unité —
    'unite': 'unite_mesure',
    'unite mesure': 'unite_mesure',
    'unite de mesure': 'unite_mesure',
    'mesure': 'unite_mesure',
    // — description —
    'description': 'description',
    'desc': 'description',
    'note': 'description',
    'notes': 'description',
    'remarque': 'description',
  };

  /// Ordre d'affichage des colonnes reconnues.
  static const List<String> champs = <String>[
    'nom',
    'categorie',
    'prix_achat',
    'prix_vente',
    'quantite',
    'unite_mesure',
    'description',
  ];

  /// Modèle prêt à coller (bouton « Insérer un modèle »).
  static const String modele =
      'nom;categorie;prix_achat;prix_vente;quantite;unite_mesure\n'
      'Sucre 1kg;alimentation;1500;2000;40;kg\n'
      'Savon Marseille;hygiène;800;1200;60;pièce\n'
      'Farde de 12 Casino;papeterie;3600;4800;10;farde';

  // ---------------------------------------------------------------------------
  // ANALYSE
  // ---------------------------------------------------------------------------

  /// Analyse un contenu complet (CSV, TSV…) et renvoie lignes + erreurs.
  static AnalyseImport analyser(String contenu) {
    final String texte = retirerBom(contenu);
    if (texte.trim().isEmpty) {
      return const AnalyseImport.vide(
        erreurGlobale: 'Le fichier est vide : collez des lignes d\'articles.',
      );
    }

    final List<String> lignesBrutes = texte.split(RegExp(r'\r\n|\r|\n'));

    // 1. Première ligne non vide = en-tête.
    int indexEntete = 0;
    while (indexEntete < lignesBrutes.length &&
        lignesBrutes[indexEntete].trim().isEmpty) {
      indexEntete++;
    }
    if (indexEntete >= lignesBrutes.length) {
      return const AnalyseImport.vide(
        erreurGlobale: 'Aucune ligne à lire : le fichier ne contient que du vide.',
      );
    }

    final String entete = lignesBrutes[indexEntete];
    final String separateur = detecterSeparateur(entete);
    final List<String> cellulesEntete = decouper(entete, separateur);

    // 2. Correspondance colonne → champ technique.
    final Map<int, String> parColonne = <int, String>{};
    final Set<String> utilises = <String>{};
    final List<String> inconnues = <String>[];
    for (int i = 0; i < cellulesEntete.length; i++) {
      final String brut = cellulesEntete[i].trim();
      if (brut.isEmpty) continue;

      final String? champ = _alias[normaliserEntete(brut)];
      if (champ == null) {
        inconnues.add(brut);
        continue;
      }
      if (utilises.contains(champ)) continue; // colonne en double : la 1re gagne
      parColonne[i] = champ;
      utilises.add(champ);
    }

    if (!utilises.contains('nom')) {
      return AnalyseImport(
        lignes: const <LigneImport>[],
        erreurs: const <ErreurImport>[],
        enteteDetectee: false,
        colonnesUtilisees: champs.where(utilises.contains).toList(growable: false),
        colonnesInconnues: inconnues,
        totalLignes: 0,
        erreurGlobale:
            'En-tête introuvable : la première ligne doit contenir au moins '
            'une colonne « nom » (ou « article », « désignation »…). '
            'Exemple : nom;categorie;prix_achat;prix_vente;quantite.',
      );
    }

    // 3. Lignes de données.
    final List<LigneImport> valides = <LigneImport>[];
    final List<ErreurImport> erreurs = <ErreurImport>[];
    int totalLignes = 0;

    for (int i = indexEntete + 1; i < lignesBrutes.length; i++) {
      final String brute = lignesBrutes[i];
      final int numeroLigne = i + 1; // 1 = première ligne du fichier

      if (brute.trim().isEmpty) continue;

      final List<String> cellules = decouper(brute, separateur);
      if (cellules.every((String cellule) => cellule.trim().isEmpty)) continue;

      totalLignes++;

      String valeur(String champ) {
        for (final MapEntry<int, String> entree in parColonne.entries) {
          if (entree.value == champ && entree.key < cellules.length) {
            return cellules[entree.key].trim();
          }
        }
        return '';
      }

      final String nom = valeur('nom');
      if (nom.isEmpty) {
        erreurs.add(ErreurImport(
          ligne: numeroLigne,
          message: 'Le nom de l\'article est obligatoire.',
        ));
        continue;
      }

      // Nombres : une cellule vide vaut 0, une cellule illisible est refusée.
      double? nombre(String champ, String libelle) {
        final String brut = valeur(champ);
        if (brut.isEmpty) return 0;
        final double? converti = nombreOuNull(brut);
        if (converti == null) {
          erreurs.add(ErreurImport(
            ligne: numeroLigne,
            nom: nom,
            message: '$libelle illisible : « $brut ».',
          ));
        }
        return converti;
      }

      final double? prixAchat = nombre('prix_achat', 'Prix d\'achat');
      if (prixAchat == null) continue;
      final double? prixVente = nombre('prix_vente', 'Prix de vente');
      if (prixVente == null) continue;
      final double? quantite = nombre('quantite', 'Quantité');
      if (quantite == null) continue;

      if (prixAchat < 0 || prixVente < 0 || quantite < 0) {
        erreurs.add(ErreurImport(
          ligne: numeroLigne,
          nom: nom,
          message: 'Les prix et la quantité doivent être positifs ou nuls.',
        ));
        continue;
      }

      String? optionnel(String champ) {
        final String brut = valeur(champ);
        return brut.isEmpty ? null : brut;
      }

      valides.add(LigneImport(
        nom: nom,
        categorie: optionnel('categorie'),
        prixAchat: prixAchat,
        prixVente: prixVente,
        quantite: quantite,
        uniteMesure: optionnel('unite_mesure'),
        description: optionnel('description'),
        ligneSource: numeroLigne,
      ));
    }

    return AnalyseImport(
      lignes: valides,
      erreurs: erreurs,
      enteteDetectee: true,
      colonnesUtilisees: champs.where(utilises.contains).toList(growable: false),
      colonnesInconnues: inconnues,
      totalLignes: totalLignes,
    );
  }

  // ---------------------------------------------------------------------------
  // OUTILS PURS
  // ---------------------------------------------------------------------------

  /// Retire le BOM UTF-8 (Excel en ajoute un quand on exporte en CSV).
  static String retirerBom(String contenu) {
    if (contenu.isNotEmpty && contenu.codeUnitAt(0) == 0xFEFF) {
      return contenu.substring(1);
    }
    return contenu;
  }

  /// Détecte le séparateur le plus probable de la ligne d'en-tête.
  static String detecterSeparateur(String entete) {
    String meilleur = ';';
    int meilleurCompte = -1;
    for (final String candidat in const <String>[';', ',', '\t']) {
      final int compte = _compterHorsGuillemets(entete, candidat);
      if (compte > meilleurCompte) {
        meilleur = candidat;
        meilleurCompte = compte;
      }
    }
    return meilleur;
  }

  /// Découpe une ligne en cellules, en respectant les guillemets.
  static List<String> decouper(String ligne, String separateur) {
    final List<String> cellules = <String>[];
    final StringBuffer courant = StringBuffer();
    bool dansGuillemets = false;

    for (int i = 0; i < ligne.length; i++) {
      final String caractere = ligne[i];
      if (dansGuillemets) {
        if (caractere == '"') {
          if (i + 1 < ligne.length && ligne[i + 1] == '"') {
            courant.write('"'); // guillemet échappé ("" → ")
            i++;
          } else {
            dansGuillemets = false;
          }
        } else {
          courant.write(caractere);
        }
      } else if (caractere == '"') {
        dansGuillemets = true;
      } else if (caractere == separateur) {
        cellules.add(courant.toString());
        courant.clear();
      } else {
        courant.write(caractere);
      }
    }
    cellules.add(courant.toString());
    return cellules;
  }

  /// Normalise un en-tête pour la correspondance d'alias :
  /// minuscules, sans accents, apostrophes/ponctuations → espaces simples.
  static String normaliserEntete(String entete) {
    final String sansAccents = _sansAccents(entete.trim().toLowerCase());
    return sansAccents
        .replaceAll(RegExp(r"[\u0027\u2019\u2018]"), ' ')
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Convertit un texte en nombre ; `null` si illisible.
  ///
  /// Gère : « 1 500,50 », « 1.500,50 », « 1,500.50 », « 1500 », « 1500 CDF »,
  /// espaces insécables, symboles monétaires.
  static double? nombreOuNull(String brut) {
    String texte = brut.trim();
    if (texte.isEmpty) return null;

    texte = texte
        .replaceAll('\u00A0', '')
        .replaceAll('\u202F', '')
        .replaceAll(' ', '')
        .replaceAll(RegExp(r'[A-Za-zÀ-ÿ$€£]'), '') // CDF, FC, USD…
        .replaceAll('%', '')
        .replaceAll('+', '');

    if (texte.isEmpty) return null;

    final bool aVirgule = texte.contains(',');
    final bool aPoint = texte.contains('.');

    if (aVirgule && aPoint) {
      // Le dernier séparateur est le séparateur décimal.
      if (texte.lastIndexOf(',') > texte.lastIndexOf('.')) {
        texte = texte.replaceAll('.', '').replaceAll(',', '.');
      } else {
        texte = texte.replaceAll(',', '');
      }
    } else if (aVirgule) {
      texte = texte.replaceAll(',', '.');
    }

    return double.tryParse(texte);
  }

  static String _sansAccents(String texte) {
    const Map<String, String> remplacements = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
      'ç': 'c',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ñ': 'n',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y',
      'œ': 'oe', 'æ': 'ae',
    };
    final StringBuffer buffer = StringBuffer();
    for (final int rune in texte.runes) {
      final String caractere = String.fromCharCode(rune);
      buffer.write(remplacements[caractere] ?? caractere);
    }
    return buffer.toString();
  }

  static int _compterHorsGuillemets(String ligne, String cible) {
    int compte = 0;
    bool dansGuillemets = false;
    for (int i = 0; i < ligne.length; i++) {
      final String caractere = ligne[i];
      if (caractere == '"') {
        dansGuillemets = !dansGuillemets;
      } else if (!dansGuillemets && caractere == cible) {
        compte++;
      }
    }
    return compte;
  }
}
