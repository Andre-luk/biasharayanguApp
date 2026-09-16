// test/rapport_test.dart
//
// Tests unitaires du MODULE 11 — Rapports & exports.
//
// Aucun accès réseau : ces tests vérifient le parsing de l'enveloppe JSON des
// RPC, le formatage des valeurs (montants, quantités, pourcentages, statuts,
// dates), les références et empreintes d'exports signés, les noms de fichiers
// et la fabrication des documents Excel et PDF (polices Google désactivées).
//
//     flutter test test/rapport_test.dart

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/rapport.dart';
import 'package:biashara_yangu/services/rapport_service.dart';

/// Enveloppe serveur représentative (rapport par article avec marge).
Map<String, dynamic> _enveloppeArticle() => <String, dynamic>{
      'type': 'ventes_article',
      'titre': 'Ventes par article',
      'portee': 'entreprise',
      'debut': '2026-09-01',
      'fin': '2026-09-16',
      'colonnes': <Map<String, dynamic>>[
        <String, dynamic>{'cle': 'article', 'libelle': 'Article', 'type': 'texte'},
        <String, dynamic>{
          'cle': 'quantite',
          'libelle': 'Quantité',
          'type': 'nombre'
        },
        <String, dynamic>{'cle': 'ca', 'libelle': 'CA', 'type': 'montant'},
        <String, dynamic>{'cle': 'part', 'libelle': 'Part', 'type': 'pourcentage'},
      ],
      'lignes': <Map<String, dynamic>>[
        <String, dynamic>{
          'article': 'Sucre 1kg',
          'quantite': 25,
          'ca': 37500,
          'part': 62.5,
        },
        <String, dynamic>{
          'article': 'Café 500g',
          'quantite': 10,
          'ca': 22500,
          'part': 37.5,
        },
      ],
      'totaux': <String, dynamic>{'ca': 60000, 'quantite': 35},
      'resume': <Map<String, dynamic>>[
        <String, dynamic>{
          'libelle': 'Chiffre d\'affaires',
          'valeur': 60000,
          'type': 'montant'
        },
        <String, dynamic>{
          'libelle': 'Articles vendus',
          'valeur': 2,
          'type': 'nombre'
        },
      ],
      'parametres': <String, dynamic>{'groupe': 'jour'},
    };

ResultatRapport _resultatTest() {
  final RapportDonnees donnees =
      RapportDonnees.depuisRpc(_enveloppeArticle());
  return ResultatRapport(
    donnees: donnees,
    reference: 'RPT-20260916-TEST01',
    empreinte: RapportService.empreinteRapport(donnees),
  );
}

void main() {
  // =========================================================================
  // 1. PARSING DE L'ENVELOPPE
  // =========================================================================

  group('RapportDonnees.depuisRpc', () {
    test('lit le type, le titre, la portée et la période', () {
      final RapportDonnees donnees =
          RapportDonnees.depuisRpc(_enveloppeArticle());

      expect(donnees.type, 'ventes_article');
      expect(donnees.titre, 'Ventes par article');
      expect(donnees.portee, 'entreprise');
      expect(donnees.debut, DateTime(2026, 9, 1));
      expect(donnees.fin, DateTime(2026, 9, 16));
      expect(donnees.periodeTexte, '01/09/2026 au 16/09/2026');
      expect(donnees.typeRapport, TypeRapport.ventesArticle);
    });

    test('lit les colonnes avec leur type (défaut : texte)', () {
      final RapportDonnees donnees =
          RapportDonnees.depuisRpc(_enveloppeArticle());

      expect(donnees.colonnes, hasLength(4));
      expect(donnees.colonnes[0].type, TypeColonneRapport.texte);
      expect(donnees.colonnes[1].type, TypeColonneRapport.nombre);
      expect(donnees.colonnes[2].type, TypeColonneRapport.montant);
      expect(donnees.colonnes[3].type, TypeColonneRapport.pourcentage);

      // Type inconnu → texte.
      final RapportDonnees autre = RapportDonnees.depuisRpc(<String, dynamic>{
        'colonnes': <Map<String, dynamic>>[
          <String, dynamic>{'cle': 'x', 'libelle': 'X', 'type': 'mystere'},
        ],
      });
      expect(autre.colonnes.single.type, TypeColonneRapport.texte);
    });

    test('lit les lignes, les totaux et le résumé', () {
      final RapportDonnees donnees =
          RapportDonnees.depuisRpc(_enveloppeArticle());

      expect(donnees.lignes, hasLength(2));
      expect(donnees.estVide, isFalse);
      expect(
        donnees.valeurFormatee(donnees.lignes[0], donnees.colonnes[2]),
        '37 500 CDF',
      );
      expect(donnees.aTotal(donnees.colonnes[2]), isTrue);
      expect(donnees.totalFormate(donnees.colonnes[2]), '60 000 CDF');
      expect(donnees.aTotal(donnees.colonnes[0]), isFalse);
      expect(donnees.resume, hasLength(2));
      expect(donnees.resume[0].valeurFormatee, '60 000 CDF');
    });

    test('tolère une enveloppe vide ou partielle', () {
      final RapportDonnees vide =
          RapportDonnees.depuisRpc(const <String, dynamic>{});
      expect(vide.estVide, isTrue);
      expect(vide.colonnes, isEmpty);
      expect(vide.resume, isEmpty);
      expect(vide.titre, 'Rapport');
      expect(vide.periodeTexte, isNull);
    });
  });

  // =========================================================================
  // 2. FORMATAGE DES VALEURS
  // =========================================================================

  group('formaterValeurRapport', () {
    test('montant : séparateur de milliers + devise', () {
      expect(
        formaterValeurRapport(1234567.0, TypeColonneRapport.montant),
        '1 234 567 CDF',
      );
      expect(formaterValeurRapport(0, TypeColonneRapport.montant), '0 CDF');
    });

    test('nombre : entier sans décimale, sinon décimales significatives', () {
      expect(formaterValeurRapport(25, TypeColonneRapport.nombre), '25');
      expect(formaterValeurRapport(12.5, TypeColonneRapport.nombre), '12.5');
    });

    test('pourcentage : une décimale, virgule française', () {
      expect(formaterValeurRapport(62.5, TypeColonneRapport.pourcentage), '62,5 %');
      expect(formaterValeurRapport(37.0, TypeColonneRapport.pourcentage), '37 %');
    });

    test('texte : statuts lisibles, vide remplacé par un tiret', () {
      expect(formaterValeurRapport('non_paye', TypeColonneRapport.texte), 'Non payé');
      expect(formaterValeurRapport('rupture', TypeColonneRapport.texte), 'Rupture');
      expect(formaterValeurRapport('ok', TypeColonneRapport.texte), 'OK');
      expect(formaterValeurRapport('Sucre 1kg', TypeColonneRapport.texte), 'Sucre 1kg');
      expect(formaterValeurRapport('', TypeColonneRapport.texte), '—');
    });

    test('date : format français', () {
      expect(
        formaterValeurRapport('2026-09-16', TypeColonneRapport.date),
        '16/09/2026',
      );
    });

    test('valeur nulle ou imbuvable : tiret, jamais d\'exception', () {
      expect(formaterValeurRapport(null, TypeColonneRapport.montant), '—');
      expect(formaterValeurRapport('abc', TypeColonneRapport.nombre), 'abc');
    });
  });

  group('LigneResumeRapport', () {
    test('valeurFormatee et estNumerique', () {
      const LigneResumeRapport montant = LigneResumeRapport(
        libelle: 'CA',
        valeur: 15000,
        type: TypeColonneRapport.montant,
      );
      expect(montant.valeurFormatee, '15 000 CDF');
      expect(montant.estNumerique, isTrue);

      const LigneResumeRapport texte = LigneResumeRapport(
        libelle: 'Principale catégorie',
        valeur: 'transport',
        type: TypeColonneRapport.texte,
      );
      expect(texte.estNumerique, isFalse);
    });
  });

  // =========================================================================
  // 3. TYPES DE RAPPORTS
  // =========================================================================

  group('TypeRapport', () {
    test('les codes sont uniques', () {
      final List<String> codes =
          TypeRapport.values.map((TypeRapport t) => t.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
    });

    test('deEspace sépare boutique et plateforme', () {
      final List<TypeRapport> entreprise =
          TypeRapport.deEspace(EspaceRapport.entreprise);
      final List<TypeRapport> plateforme =
          TypeRapport.deEspace(EspaceRapport.plateforme);

      expect(entreprise, hasLength(10));
      expect(plateforme, hasLength(6));
      expect(entreprise.every((TypeRapport t) => !t.estPlateforme), isTrue);
      expect(plateforme.every((TypeRapport t) => t.estPlateforme), isTrue);
    });

    test('fromCode retrouve un type, ou null si inconnu', () {
      expect(TypeRapport.fromCode('ventes_article'), TypeRapport.ventesArticle);
      expect(TypeRapport.fromCode('ABONNEMENTS_ACTIFS'),
          TypeRapport.plateformeAbonnements);
      expect(TypeRapport.fromCode('inconnu'), isNull);
      expect(TypeRapport.fromCode(null), isNull);
    });
  });

  group('FormatExportRapport', () {
    test('fromCode avec défaut aperçu', () {
      expect(FormatExportRapport.fromCode('pdf'), FormatExportRapport.pdf);
      expect(FormatExportRapport.fromCode('excel'), FormatExportRapport.excel);
      expect(FormatExportRapport.fromCode('n_importe_quoi'),
          FormatExportRapport.apercu);
    });
  });

  // =========================================================================
  // 4. RÉFÉRENCE & EMPREINTE (EXPORTS SIGNÉS)
  // =========================================================================

  group('Références d\'export', () {
    test('génère RPT-AAAAMMJJ-XXXXXX', () {
      final String reference = RapportService.genererReferenceRapport(
        maintenant: DateTime(2026, 9, 16),
        suffixe: 'AB12CD',
      );
      expect(reference, 'RPT-20260916-AB12CD');
    });

    test('suffixe aléatoire de 6 caractères hexadécimaux', () {
      final String reference = RapportService.genererReferenceRapport(
        maintenant: DateTime(2026, 1, 5),
      );
      expect(
        RegExp(r'^RPT-20260105-[0-9A-F]{6}$').hasMatch(reference),
        isTrue,
        reason: 'référence inattendue : $reference',
      );
    });
  });

  group('Empreinte des rapports', () {
    test('même contenu → même empreinte (64 hexadécimaux)', () {
      final String a = RapportService.empreinteRapport(
          RapportDonnees.depuisRpc(_enveloppeArticle()));
      final String b = RapportService.empreinteRapport(
          RapportDonnees.depuisRpc(_enveloppeArticle()));

      expect(a, b);
      expect(a, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(a), isTrue);
    });

    test('un contenu différent change l\'empreinte', () {
      final RapportDonnees donnees =
          RapportDonnees.depuisRpc(_enveloppeArticle());
      final String originale = RapportService.empreinteRapport(donnees);

      final Map<String, dynamic> modifiee = _enveloppeArticle();
      (modifiee['lignes'] as List<dynamic>)[0] = <String, dynamic>{
        'article': 'Sucre 1kg',
        'quantite': 26, // une unité de plus suffit
        'ca': 39000,
        'part': 63.4,
      };
      final String nouvelle = RapportService.empreinteRapport(
          RapportDonnees.depuisRpc(modifiee));

      expect(nouvelle, isNot(originale));
    });

    test('empreinteCourte : 12 caractères majuscules', () {
      final String empreinte = RapportService.empreinteRapport(
          RapportDonnees.depuisRpc(_enveloppeArticle()));
      final String courte = RapportService.empreinteCourte(empreinte);
      expect(courte, hasLength(12));
      expect(courte, empreinte.substring(0, 12).toUpperCase());
    });
  });

  // =========================================================================
  // 5. NOMS DE FICHIERS
  // =========================================================================

  group('nomFichierRapport', () {
    test('avec période', () {
      expect(
        RapportService.nomFichierRapport(
          type: 'ventes',
          debut: DateTime(2026, 9, 1),
          fin: DateTime(2026, 9, 30),
          extension: 'pdf',
        ),
        'rapport_ventes_20260901_20260930.pdf',
      );
    });

    test('sans période', () {
      expect(
        RapportService.nomFichierRapport(
          type: 'stock',
          extension: 'xlsx',
        ),
        'rapport_stock.xlsx',
      );
    });
  });

  // =========================================================================
  // 6. MESSAGES D'ERREUR SERVEUR
  // =========================================================================

  group('RapportService.messageErreur', () {
    test('sépare le code du message', () {
      expect(
        RapportService.messageErreur(
            'DROIT_REFUSE|Votre rôle ne permet pas de générer ce rapport.'),
        'Votre rôle ne permet pas de générer ce rapport.',
      );
      expect(
        RapportService.messageErreur('PERIODE_INVALIDE|Période trop longue : 366 jours maximum.'),
        'Période trop longue : 366 jours maximum.',
      );
    });

    test('message sans code : renvoyé tel quel', () {
      expect(
        RapportService.messageErreur('Connexion perdue'),
        'Connexion perdue',
      );
    });
  });

  // =========================================================================
  // 7. HISTORIQUE
  // =========================================================================

  group('EntreeHistoriqueRapport', () {
    test('parse une ligne du registre', () {
      final EntreeHistoriqueRapport entree =
          EntreeHistoriqueRapport.depuisJson(<String, dynamic>{
        'id': 12,
        'type_rapport': 'ventes',
        'portee': 'entreprise',
        'format': 'pdf',
        'debut': '2026-09-01',
        'fin': '2026-09-16',
        'reference': 'RPT-20260916-ABCDEF',
        'empreinte': 'a' * 64,
        'utilisateur': 'Andre',
        'created_at': '2026-09-16T18:30:00+00:00',
      });

      expect(entree.id, 12);
      expect(entree.libelleType, 'Ventes par période');
      expect(entree.format, FormatExportRapport.pdf);
      expect(entree.periodeTexte, '01/09/2026 au 16/09/2026');
      expect(entree.createdAt, isNotNull);
      expect(entree.utilisateur, 'Andre');
    });
  });

  // =========================================================================
  // 8. GÉNÉRATION DES DOCUMENTS (SANS RÉSEAU)
  // =========================================================================

  group('Documents', () {
    test('Excel : classeur .xlsx non vide (signature ZIP)', () async {
      final ResultatRapport resultat = _resultatTest();
      final Uint8List octets = await RapportService.instance.construireExcel(
        resultat,
        nomEntreprise: 'Boutique Test',
      );

      expect(octets, isNotEmpty);
      // Un .xlsx est une archive ZIP : « PK » comme premier octet.
      expect(octets[0], 0x50);
      expect(octets[1], 0x4B);
    });

    test('PDF : document non vide (signature %PDF)', () async {
      final ResultatRapport resultat = _resultatTest();
      final Uint8List octets = await RapportService.instance.construirePDF(
        resultat,
        nomEntreprise: 'Boutique Test',
        chargerPolices: false, // aucun accès réseau dans les tests
      );

      expect(octets.length, greaterThan(400));
      // « %PDF- »
      expect(String.fromCharCodes(octets.sublist(0, 5)), '%PDF-');
    });

    test('PDF : un rapport vide se génère sans exception', () async {
      final RapportDonnees vide = RapportDonnees.depuisRpc(<String, dynamic>{
        'type': 'caisse',
        'titre': 'Caisse — entrées et sorties',
        'portee': 'entreprise',
        'debut': '2026-09-01',
        'fin': '2026-09-16',
        'colonnes': <Map<String, dynamic>>[
          <String, dynamic>{'cle': 'periode', 'libelle': 'Jour', 'type': 'texte'},
        ],
        'lignes': <dynamic>[],
        'totaux': <String, dynamic>{},
        'resume': <dynamic>[],
      });
      final Uint8List octets = await RapportService.instance.construirePDF(
        ResultatRapport(
          donnees: vide,
          reference: 'RPT-20260916-000001',
          empreinte: RapportService.empreinteRapport(vide),
        ),
        chargerPolices: false,
      );
      expect(octets, isNotEmpty);
    });
  });
}
