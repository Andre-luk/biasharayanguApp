// test/import_produits_test.dart
//
// Tests unitaires du MODULE 12 — Import rapide d'articles.
//
// Aucun accès réseau : ces tests vérifient le parseur CSV/TSV tolérant
// (`ImportCsv`), les conversions de nombres au format français, les alias
// d'en-têtes, la liste des erreurs par ligne et le cumul des résultats de
// `rpc_produits_importer`.
//
//     flutter test test/import_produits_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/import_produits.dart';
import 'package:biashara_yangu/utils/import_csv.dart';

void main() {
  // =========================================================================
  // 1. OUTILS PURS
  // =========================================================================

  group('ImportCsv — outils', () {
    test('détecte le séparateur le plus probable', () {
      expect(ImportCsv.detecterSeparateur('nom;prix;quantite'), ';');
      expect(ImportCsv.detecterSeparateur('nom,prix,quantite'), ',');
      expect(ImportCsv.detecterSeparateur('nom\tprix\tquantite'), '\t');
      // Un seul nom sans séparateur : le point-virgule reste le défaut.
      expect(ImportCsv.detecterSeparateur('nom'), ';');
    });

    test('découpe en respectant les guillemets', () {
      expect(
        ImportCsv.decouper('a;"b;c";d', ';'),
        <String>['a', 'b;c', 'd'],
      );
      expect(
        ImportCsv.decouper('"il a dit ""bonjour""";x', ';'),
        <String>['il a dit "bonjour"', 'x'],
      );
    });

    test('normalise les en-têtes (accents, apostrophes, casse)', () {
      expect(ImportCsv.normaliserEntete('PRIX_ACHAT'), 'prix achat');
      expect(ImportCsv.normaliserEntete('Prix d\'achat'), 'prix d achat');
      expect(ImportCsv.normaliserEntete('Désignation'), 'designation');
      expect(ImportCsv.normaliserEntete('  Unité  '), 'unite');
    });

    test('convertit les nombres aux formats français et anglo-saxons', () {
      expect(ImportCsv.nombreOuNull('1500'), 1500);
      expect(ImportCsv.nombreOuNull('1 500'), 1500);
      expect(ImportCsv.nombreOuNull('1 500,50'), 1500.5);
      expect(ImportCsv.nombreOuNull('1.500,50'), 1500.5);
      expect(ImportCsv.nombreOuNull('1,500.50'), 1500.5);
      expect(ImportCsv.nombreOuNull('1500 CDF'), 1500);
      expect(ImportCsv.nombreOuNull('2,5'), 2.5);
      expect(ImportCsv.nombreOuNull(''), isNull);
      expect(ImportCsv.nombreOuNull('abc'), isNull);
    });

    test('retire le BOM UTF-8', () {
      expect(ImportCsv.retirerBom('\uFEFFnom;prix'), 'nom;prix');
      expect(ImportCsv.retirerBom('nom;prix'), 'nom;prix');
    });
  });

  // =========================================================================
  // 2. ANALYSE DE FICHIERS
  // =========================================================================

  group('ImportCsv.analyser', () {
    test('analyse un fichier complet au format point-virgule', () {
      const String contenu = 'nom;categorie;prix_achat;prix_vente;quantite;unite_mesure\n'
          'Sucre 1kg;alimentation;1500;2000;40;kg\n'
          'Savon;hygiène;800;1200;60;pièce\n'
          'Farde Casino;papeterie;3600;4800;10;farde\n';

      final AnalyseImport analyse = ImportCsv.analyser(contenu);

      expect(analyse.enteteDetectee, isTrue);
      expect(analyse.erreurGlobale, isNull);
      expect(analyse.nbValides, 3);
      expect(analyse.nbErreurs, 0);
      expect(analyse.totalLignes, 3);
      expect(analyse.colonnesUtilisees, contains('nom'));
      expect(analyse.colonnesUtilisees, contains('prix_vente'));

      final LigneImport premiere = analyse.lignes.first;
      expect(premiere.nom, 'Sucre 1kg');
      expect(premiere.prixAchat, 1500);
      expect(premiere.prixVente, 2000);
      expect(premiere.quantite, 40);
      expect(premiere.uniteMesure, 'kg');
      expect(premiere.ligneSource, 2);
    });

    test('accepte les alias d\'en-têtes et l\'absence de colonnes optionnelles',
        () {
      const String contenu = 'Article;Prix d\'achat;Prix de vente;Qté\n'
          'Riz 25kg;28000;32000;5\n';

      final AnalyseImport analyse = ImportCsv.analyser(contenu);

      expect(analyse.nbValides, 1);
      expect(analyse.colonnesUtilisees, containsAll(<String>[
        'nom',
        'prix_achat',
        'prix_vente',
        'quantite',
      ]));
      expect(analyse.lignes.first.nom, 'Riz 25kg');
      expect(analyse.lignes.first.categorie, isNull);
    });

    test('analyse un fichier séparé par des virgules', () {
      const String contenu = 'nom,prix_vente,quantite\n'
          'Café,3800,12\n';

      final AnalyseImport analyse = ImportCsv.analyser(contenu);

      expect(analyse.nbValides, 1);
      expect(analyse.lignes.first.prixVente, 3800);
    });

    test('analyse un fichier séparé par des tabulations', () {
      const String contenu = 'nom\tprix_vente\tquantite\n'
          'Thé\t2500\t30\n';

      final AnalyseImport analyse = ImportCsv.analyser(contenu);

      expect(analyse.nbValides, 1);
      expect(analyse.lignes.first.nom, 'Thé');
    });

    test('refuse un contenu vide', () {
      final AnalyseImport analyse = ImportCsv.analyser('   ');
      expect(analyse.erreurGlobale, isNotNull);
      expect(analyse.exploitable, isFalse);
    });

    test('refuse un en-tête sans colonne « nom »', () {
      const String contenu = 'prix_achat;prix_vente\n1500;2000\n';
      final AnalyseImport analyse = ImportCsv.analyser(contenu);

      expect(analyse.enteteDetectee, isFalse);
      expect(analyse.erreurGlobale, contains('nom'));
    });

    test('signale chaque ligne refusée avec son numéro et son motif', () {
      const String contenu = 'nom;prix_achat;prix_vente;quantite\n'
          ';100;200;5\n' // ligne 2 : nom manquant
          'Sucre;abc;200;5\n' // ligne 3 : prix d'achat illisible
          'Café;1000;-5;2\n' // ligne 4 : quantité négative
          'Thé;500;800;3\n'; // ligne 5 : valide

      final AnalyseImport analyse = ImportCsv.analyser(contenu);

      expect(analyse.nbValides, 1);
      expect(analyse.nbErreurs, 3);
      expect(analyse.erreurs[0].ligne, 2);
      expect(analyse.erreurs[0].message, contains('nom'));
      expect(analyse.erreurs[1].ligne, 3);
      expect(analyse.erreurs[1].message, contains('illisible'));
      expect(analyse.erreurs[2].ligne, 4);
      expect(analyse.erreurs[2].message, contains('positifs'));
      expect(analyse.lignes.first.nom, 'Thé');
    });

    test('tolère colonnes inconnues, lignes vides et CRLF', () {
      const String contenu = 'nom;prix_vente;ref_fournisseur\r\n'
          '\r\n'
          'Sucre;2000;REF-1\r\n'
          '; ;\r\n'
          'Café;3800;REF-2\r\n';

      final AnalyseImport analyse = ImportCsv.analyser(contenu);

      expect(analyse.nbValides, 2);
      expect(analyse.colonnesInconnues, contains('ref_fournisseur'));
      expect(analyse.erreurs, isEmpty);
    });

    test('lit les valeurs entre guillemets contenant le séparateur', () {
      const String contenu = 'nom;categorie;prix_vente\n'
          '"Farde 12 ""Casino""";papeterie;4800\n';

      final AnalyseImport analyse = ImportCsv.analyser(contenu);

      expect(analyse.nbValides, 1);
      expect(analyse.lignes.first.nom, 'Farde 12 "Casino"');
      expect(analyse.lignes.first.categorie, 'papeterie');
    });
  });

  // =========================================================================
  // 3. MODÈLES D'IMPORT
  // =========================================================================

  group('LigneImport', () {
    test('toJson respecte les clés attendues par rpc_produits_importer', () {
      const LigneImport ligne = LigneImport(
        nom: 'Sucre 1kg',
        categorie: 'alimentation',
        prixAchat: 1500,
        prixVente: 2000,
        quantite: 40,
        uniteMesure: 'kg',
      );

      final Map<String, dynamic> json = ligne.toJson();
      expect(json['nom'], 'Sucre 1kg');
      expect(json['categorie'], 'alimentation');
      expect(json['prix_achat'], 1500);
      expect(json['prix_vente'], 2000);
      expect(json['quantite'], 40);
      expect(json['unite_mesure'], 'kg');
      expect(json.containsKey('description'), isFalse);
    });
  });

  group('ResultatImport', () {
    test('parse la réponse de la RPC', () {
      final ResultatImport? resultat =
          ResultatImport.depuisRpc(<String, dynamic>{
        'nb_lignes': 10,
        'crees': 7,
        'mis_a_jour': 2,
        'ignores': 1,
        'erreurs': <Map<String, dynamic>>[
          <String, dynamic>{'ligne': 4, 'nom': 'Sucre', 'message': 'Doublon ignoré.'},
        ],
      });

      expect(resultat, isNotNull);
      expect(resultat!.crees, 7);
      expect(resultat.misAJour, 2);
      expect(resultat.ignores, 1);
      expect(resultat.aDesErreurs, isTrue);
      expect(resultat.erreurs.first.ligne, 4);
    });

    test('fusionne les tranches en renumérotant les erreurs', () {
      const ResultatImport tranche1 = ResultatImport(
        nbLignes: 2,
        crees: 2,
        misAJour: 0,
        ignores: 0,
        erreurs: <ErreurImport>[],
      );
      const ResultatImport tranche2 = ResultatImport(
        nbLignes: 2,
        crees: 1,
        misAJour: 0,
        ignores: 0,
        erreurs: <ErreurImport>[
          ErreurImport(ligne: 1, message: 'Refusée.', nom: 'X'),
        ],
      );

      final ResultatImport total =
          tranche1.fusionner(tranche2, decalageLignes: 2);

      expect(total.nbLignes, 4);
      expect(total.crees, 3);
      expect(total.erreurs, hasLength(1));
      // Ligne 1 de la 2e tranche = ligne 3 du fichier complet.
      expect(total.erreurs.first.ligne, 3);
    });
  });
}
