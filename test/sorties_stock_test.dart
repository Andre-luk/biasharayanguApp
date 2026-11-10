// test/sorties_stock_test.dart
//
// 📦 MODULE 9 — SORTIES DE STOCK SPÉCIALES.
//
// Ces tests couvrent la partie PURE : lecture des réponses du serveur et
// vocabulaire des motifs. Ils garantissent trois choses qui ont un coût réel :
//
//   • un montant renvoyé en `int` par PostgREST ne fait pas planter l'écran ;
//   • le détail par motif est lu même quand un motif est absent ;
//   • le rapport imprimé affiche la bonne période et la bonne devise.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/sortie_stock.dart';
import 'package:biashara_yangu/services/rapport_sorties_pdf_service.dart';

void main() {
  group('MotifSortieStock', () {
    test('chaque code est unique', () {
      final Set<String> codes =
          MotifSortieStock.values.map((MotifSortieStock m) => m.code).toSet();
      expect(codes.length, MotifSortieStock.values.length);
    });

    test('le code « consommation_proprietaire » donne le bon libellé', () {
      expect(
        MotifSortieStock.libelleDe('consommation_proprietaire'),
        'Consommation du propriétaire',
      );
      expect(MotifSortieStock.depuisCode('consommation_proprietaire'),
          MotifSortieStock.consommationProprietaire);
    });

    test('un code inconnu retombe sur « Autre motif », jamais sur une erreur',
        () {
      expect(MotifSortieStock.depuisCode('code_inexistant'),
          MotifSortieStock.autre);
      expect(MotifSortieStock.libelleDe('code_inexistant'), 'code_inexistant');
      expect(MotifSortieStock.libelleDe(null), 'Motif inconnu');
    });

    test('perte, casse et péremption sont des pertes de valeur', () {
      expect(MotifSortieStock.perte.estUnePerte, isTrue);
      expect(MotifSortieStock.casse.estUnePerte, isTrue);
      expect(MotifSortieStock.peremption.estUnePerte, isTrue);
      expect(MotifSortieStock.offert.estUnePerte, isFalse);
    });
  });

  group('ResumeSortiesStock.depuisRpc', () {
    Map<String, dynamic> reponse() => <String, dynamic>{
          'debut': '2026-09-01',
          'fin': '2026-09-30',
          'lignes': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 7,
              'produit_id': 12,
              'produit': 'Sucre 1 kg',
              'unite': 'sac',
              'quantite': 2,
              'motif': 'consommation_proprietaire',
              'note': 'Pris par le patron',
              'valeur_unitaire': 1500,
              'valeur_totale': 3000,
              'date': '2026-09-12T09:30:00Z',
            },
            <String, dynamic>{
              'id': 8,
              'produit_id': 13,
              'produit': 'Bouteille 33cl',
              'unite': 'pièce',
              'quantite': 3.5,
              'motif': 'casse',
              'valeur_unitaire': 800,
              'valeur_totale': 2800,
              'date': '2026-09-13T10:00:00Z',
            },
          ],
          'totaux': <String, dynamic>{
            'nb': 2,
            'valeur': 5800,
            'par_motif': <String, dynamic>{
              'consommation_proprietaire': <String, dynamic>{
                'nb': 1,
                'valeur': 3000,
              },
              'casse': <String, dynamic>{'nb': 1, 'valeur': 2800},
            },
          },
        };

    test('lit les lignes, les totaux et le détail par motif', () {
      final ResumeSortiesStock resume =
          ResumeSortiesStock.fromRpc(reponse());

      expect(resume.estVide, isFalse);
      expect(resume.nb, 2);
      expect(resume.valeur, 5800);
      expect(resume.lignes.length, 2);
      expect(resume.lignes.first.produit, 'Sucre 1 kg');
      expect(resume.lignes.first.quantite, 2);
      expect(resume.lignes.first.libelleMotif,
          'Consommation du propriétaire');
      expect(resume.lignes.first.note, 'Pris par le patron');
      expect(resume.parMotif.length, 2);
      expect(resume.parMotif['casse']!.valeur, 2800);
    });

    test('les motifs sont triés du plus coûteux au moins coûteux', () {
      final ResumeSortiesStock resume =
          ResumeSortiesStock.fromRpc(reponse());
      expect(resume.motifsTries.first.key, 'consommation_proprietaire');
      expect(resume.motifsTries.last.key, 'casse');
    });

    test('une réponse vide ne lève pas d\'exception', () {
      final ResumeSortiesStock resume =
          ResumeSortiesStock.fromRpc(const <String, dynamic>{});
      expect(resume.estVide, isTrue);
      expect(resume.nb, 0);
      expect(resume.valeur, 0);
      expect(resume.parMotif, isEmpty);
    });

    test('un motif inconnu est conservé tel quel, sans écraser les autres', () {
      final Map<String, dynamic> brut = reponse();
      (brut['totaux'] as Map<String, dynamic>)['par_motif'] =
          <String, dynamic>{
        'invente': <String, dynamic>{'nb': 3, 'valeur': 1000},
      };
      final ResumeSortiesStock resume = ResumeSortiesStock.fromRpc(brut);
      expect(resume.parMotif['invente']!.libelle, 'invente');
    });
  });

  group('ResultatSortieStock.fromRpc', () {
    test('lit un stock avant/après renvoyé en entiers', () {
      final ResultatSortieStock r = ResultatSortieStock.fromRpc(
        <String, dynamic>{
          'sortie_id': 41,
          'produit_id': 9,
          'nom': 'Farine',
          'unite': 'kg',
          'quantite': 5,
          'motif': 'offert',
          'valeur_unitaire': 1200,
          'valeur_totale': 6000,
          'stock_avant': 18,
          'stock_apres': 13,
          'date': '2026-09-14T08:00:00Z',
        },
      );

      expect(r.id, 41);
      expect(r.quantite, 5);
      expect(r.valeurTotale, 6000);
      expect(r.stockAvant, 18);
      expect(r.stockApres, 13);
      expect(r.motif, 'offert');
    });
  });

  group('DonneesRapportSorties', () {
    const ResumeSortiesStock vide = ResumeSortiesStock(
      lignes: <SortieStock>[],
      nb: 0,
      valeur: 0,
      parMotif: <String, TotalMotifSortie>{},
    );

    test('la période reprend les dates du serveur', () {
      final DonneesRapportSorties donnees = DonneesRapportSorties(
        etablissement: const Etablissement(nom: 'Boutique Test'),
        resume: ResumeSortiesStock(
          lignes: vide.lignes,
          nb: 0,
          valeur: 0,
          parMotif: vide.parMotif,
          debut: DateTime(2026, 9, 1),
          fin: DateTime(2026, 9, 30),
        ),
      );
      expect(donnees.periode, 'Du 01/09/2026 au 30/09/2026');
    });

    test('sans dates, la période reste lisible', () {
      final DonneesRapportSorties donnees = DonneesRapportSorties(
        etablissement: const Etablissement(nom: 'Boutique Test'),
        resume: vide,
      );
      expect(donnees.periode, 'Toutes les sorties');
    });

    test('la devise de l\'établissement est utilisée par défaut', () {
      final DonneesRapportSorties donnees = DonneesRapportSorties(
        etablissement:
            const Etablissement(nom: 'Boutique Test', devise: 'USD'),
        resume: vide,
      );
      expect(donnees.deviseAffichee, 'USD');
    });

    test('une devise passée explicitement prime', () {
      final DonneesRapportSorties donnees = DonneesRapportSorties(
        etablissement:
            const Etablissement(nom: 'Boutique Test', devise: 'USD'),
        resume: vide,
        devise: 'CDF',
      );
      expect(donnees.deviseAffichee, 'CDF');
    });

    test('le nom de fichier est daté et se termine par .pdf', () {
      final DonneesRapportSorties donnees = DonneesRapportSorties(
        etablissement: const Etablissement(nom: 'Boutique Test'),
        resume: vide,
      );
      expect(donnees.nomFichier, startsWith('sorties-stock-'));
      expect(donnees.nomFichier, endsWith('.pdf'));
    });
  });
}
