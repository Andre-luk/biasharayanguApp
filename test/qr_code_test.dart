// test/qr_code_test.dart
//
// Tests unitaires du MODULE 6 — QR codes (génération, étiquettes, exports).
//
// Vérifient SANS réseau :
//   • le format encodé (« PROD:123 » / « COND:<uuid> », jamais de prix) ;
//   • la lecture inverse d'un code (futur scanner) ;
//   • la construction des étiquettes d'un article et de ses conditionnements ;
//   • les dimensions d'export (300 DPI, tailles en millimètres) ;
//   • le rendu SVG (un carré par module noir) et le rendu PNG (signature).
//
//     flutter test test/qr_code_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/etiquette_qr.dart';
import 'package:biashara_yangu/services/qr_code_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Conditionnement farde = Conditionnement(
    id: '3f2a0000-0000-0000-0000-000000000001',
    produitId: 1,
    libelle: 'Farde de 12',
    quantiteUnitesBase: 12,
    prixVente: 12000,
    qrCodeId: '9b8c0000-0000-0000-0000-0000000000aa',
    codeBarreTexte: '6130000001',
  );

  const Article eau = Article(
    id: 123,
    nom: 'Eau Casino',
    categorie: 'Boissons',
    prixVente: 1000,
    quantite: 34,
    uniteMesure: 'bouteille',
    conditionnements: <Conditionnement>[farde],
  );

  // =========================================================================
  // 1. CONTENU DES QR CODES (JAMAIS DE PRIX)
  // =========================================================================

  group('EtiquetteQr — format encodé', () {
    test('un article encode « PROD:<id> »', () {
      const EtiquetteQr etiquette = EtiquetteQr(
        type: TypeQrCode.article,
        identifiant: '123',
        articleId: 123,
        titre: 'Eau Casino',
      );

      expect(etiquette.code, 'PROD:123');
      expect(etiquette.nomFichierBase, 'qr_PROD_123');
    });

    test('un conditionnement encode « COND:<qr_code_id> »', () {
      const EtiquetteQr etiquette = EtiquetteQr(
        type: TypeQrCode.conditionnement,
        identifiant: '9b8c0000-0000-0000-0000-0000000000aa',
        articleId: 123,
        titre: 'Eau Casino',
        sousTitre: 'Farde de 12 — 12 bouteilles',
      );

      expect(etiquette.code, 'COND:9b8c0000-0000-0000-0000-0000000000aa');
      expect(etiquette.libelleComplet, 'Eau Casino — Farde de 12 — 12 bouteilles');
    });

    test('le contenu ne contient JAMAIS de prix', () {
      final List<EtiquetteQr> etiquettes =
          QrCodeService.etiquettesPourArticles(<Article>[eau]);

      for (final EtiquetteQr etiquette in etiquettes) {
        // Le prix de vente (1000 / 12000) ne doit apparaître nulle part :
        // ni tel quel, ni sous forme de chiffres seuls.
        expect(etiquette.code, isNot(contains('1000')));
        expect(etiquette.code, isNot(contains('12000')));
        expect(etiquette.code, matches(RegExp(r'^(PROD|COND):[A-Za-z0-9-]+$')));
      }
    });

    test('décodage inverse (scanner) : PROD / COND / invalides', () {
      final EtiquetteQr? article = EtiquetteQr.decoder('PROD:123');
      expect(article, isNotNull);
      expect(article!.type, TypeQrCode.article);
      expect(article.identifiant, '123');
      expect(article.articleId, 123);

      final EtiquetteQr? conditionnement =
          EtiquetteQr.decoder('COND:9b8c0000-0000-0000-0000-0000000000aa');
      expect(conditionnement, isNotNull);
      expect(conditionnement!.type, TypeQrCode.conditionnement);
      expect(conditionnement.identifiant, '9b8c0000-0000-0000-0000-0000000000aa');

      expect(EtiquetteQr.decoder(null), isNull);
      expect(EtiquetteQr.decoder(''), isNull);
      expect(EtiquetteQr.decoder('PROD'), isNull);
      expect(EtiquetteQr.decoder('PROD:'), isNull);
      expect(EtiquetteQr.decoder('XYZ:123'), isNull);
      expect(EtiquetteQr.decoder(':123'), isNull);
    });

    test('TypeQrCode.depuisPrefixe', () {
      expect(TypeQrCode.depuisPrefixe('prod'), TypeQrCode.article);
      expect(TypeQrCode.depuisPrefixe(' cond '), TypeQrCode.conditionnement);
      expect(TypeQrCode.depuisPrefixe('X'), isNull);
      expect(TypeQrCode.depuisPrefixe(null), isNull);
    });
  });

  // =========================================================================
  // 2. CONSTRUCTION DES ÉTIQUETTES
  // =========================================================================

  group('QrCodeService.etiquettesPourArticles', () {
    test('article + conditionnements, dans l\'ordre', () {
      final List<EtiquetteQr> etiquettes =
          QrCodeService.etiquettesPourArticles(<Article>[eau]);

      expect(etiquettes, hasLength(2));
      expect(etiquettes[0].code, 'PROD:123');
      expect(etiquettes[0].titre, 'Eau Casino');
      expect(etiquettes[0].sousTitre, isNull);
      expect(etiquettes[1].code, 'COND:9b8c0000-0000-0000-0000-0000000000aa');
      expect(etiquettes[1].articleId, 123);
      expect(etiquettes[1].sousTitre, 'Farde de 12 — 12 bouteilles');
    });

    test('sans conditionnements quand demandé', () {
      final List<EtiquetteQr> etiquettes = QrCodeService.etiquettesPourArticles(
        <Article>[eau],
        inclureConditionnements: false,
      );

      expect(etiquettes, hasLength(1));
      expect(etiquettes.single.code, 'PROD:123');
    });

    test('un article sans conditionnement donne une seule étiquette', () {
      const Article savon = Article(id: 7, nom: 'Savon Alpha');
      final List<EtiquetteQr> etiquettes =
          QrCodeService.etiquettesPourArticles(<Article>[savon]);

      expect(etiquettes, hasLength(1));
      expect(etiquettes.single.code, 'PROD:7');
    });
  });

  // =========================================================================
  // 3. DIMENSIONS & CONSTANTES D'IMPRESSION
  // =========================================================================

  group('Dimensions d\'export', () {
    test('conversion millimètres → pixels à 300 DPI', () {
      expect(QrCodeService.dpi, 300);
      expect(QrCodeService.pixelsPourMillimetres(25.4), closeTo(300, 0.001));
      expect(QrCodeService.pixelsPourMillimetres(40), closeTo(472.44, 0.01));
    });

    test('grille PDF 3 × 4 = 12 étiquettes par page', () {
      expect(QrCodeService.colonnesParPage, 3);
      expect(QrCodeService.lignesParPage, 4);
      expect(QrCodeService.etiquettesParPage, 12);
    });

    test('tailles proposées et lots de 10', () {
      expect(QrCodeService.taillesMm, <double>[30, 40, 50]);
      expect(QrCodeService.tailleParDefautMm, 40);
      expect(QrCodeService.tailleLotDefaut, 10);
      expect(QrCodeService.quietZoneModules, 4);
    });
  });

  // =========================================================================
  // 4. RENDU SVG & PNG
  // =========================================================================

  group('Rendu des QR codes', () {
    test('le SVG contient un carré par module noir + marge normalisée', () {
      const String data = 'PROD:123';
      final String svg = QrCodeService.instance.genererSvgQrCode(data);

      final QrImage matrice = QrImage(QrCode.fromData(
        data: data,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ));
      int modulesNoirs = 0;
      for (int ligne = 0; ligne < matrice.moduleCount; ligne++) {
        for (int colonne = 0; colonne < matrice.moduleCount; colonne++) {
          if (matrice.isDark(ligne, colonne)) modulesNoirs++;
        }
      }

      expect(svg, startsWith('<svg'));
      expect(svg, contains('shape-rendering="crispEdges"'));
      expect(svg, contains('fill="#FFFFFF"')); // fond
      expect(svg, contains('fill="#000000"')); // modules
      expect('h1v1h-1z'.allMatches(svg).length, modulesNoirs);

      // 21 modules (version 1) + 2 × 4 de marge = 29.
      expect(svg, contains('viewBox="0 0 29 29"'));
      expect(svg, contains('width="40mm"'));
    });

    test('taille SVG personnalisée', () {
      final String svg =
          QrCodeService.instance.genererSvgQrCode('PROD:123', tailleMm: 30);
      expect(svg, contains('width="30mm"'));
      expect(svg, contains('height="30mm"'));
    });

    test('genererQrCode produit un PNG valide (300 DPI par défaut)', () async {
      final bytes = await QrCodeService.instance
          .genererQrCode('PROD:123', taillePixels: 300);

      // Signature PNG : 89 50 4E 47 0D 0A 1A 0A.
      expect(bytes.length, greaterThan(100));
      expect(
        bytes.sublist(0, 8),
        <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      );
    });

    test('un contenu vide est refusé', () {
      expect(
        () => QrCodeService.instance.genererSvgQrCode('   '),
        throwsA(isA<QrCodeServiceException>()),
      );
    });
  });
}
