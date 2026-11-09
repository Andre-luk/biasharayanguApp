// test/pressing_test.dart
//
// 🧺 MODULE 35 — PRESSING & BLANCHISSERIE : LE MODÈLE MÉTIER.
//
// Ce que l'on vérifie (aucun réseau, aucun serveur) :
//   • les statuts sont lus et classés correctement ;
//   • le prix applicable est le plus précis (vêtement > tarif par défaut) et
//     un tarif désactivé n'est jamais appliqué ;
//   • une commande se lit complètement (vêtements, paiements, historique) et
//     ses compteurs ne mentent pas (3 prêts / 2 en traitement) ;
//   • « prêt » se déduit de l'étape finale, pas de la remise ;
//   • les champs vides ne sont pas envoyés au serveur ;
//   • facturé ≠ encaissé dans le tableau de bord.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/pressing.dart';

Map<String, dynamic> _ligne({
  required String id,
  int position = 1,
  String? designation,
  String? categorieNom,
  String? prestationNom,
  double prix = 3500,
  String etape = 'REPASSAGE',
  bool prete = false,
  bool remise = false,
  String? defauts,
  String? marque,
  String? couleur,
  String? taille,
}) {
  return <String, dynamic>{
    'id': id,
    'position': position,
    'designation': designation,
    'categorie_nom': categorieNom,
    'prestation_nom': prestationNom,
    'prix_unitaire': prix,
    'prix': prix,
    'etape_code': etape,
    'etape_libelle': etape == 'PRET' ? 'Prêt à récupérer' : 'Repassage',
    'est_prete': prete,
    'remis_le': remise ? '2026-11-09T10:00:00+00:00' : null,
    'defauts': defauts,
    'marque': marque,
    'couleur': couleur,
    'taille': taille,
    'quantite': 1,
    'photos': <String>['https://exemple/1.jpg', ''],
  };
}

void main() {
  group('StatutCommandePressing', () {
    test('lit les codes du serveur', () {
      expect(
        StatutCommandePressing.fromCode('PARTIELLEMENT_REMISE'),
        StatutCommandePressing.partiellementRemise,
      );
      expect(
        StatutCommandePressing.fromCode('remise'),
        StatutCommandePressing.remise,
      );
    });

    test('retombe sur « en traitement » si le code est inconnu', () {
      expect(
        StatutCommandePressing.fromCode('N_IMPORTE_QUOI'),
        StatutCommandePressing.enTraitement,
      );
      expect(
        StatutCommandePressing.fromCode(null),
        StatutCommandePressing.enTraitement,
      );
    });

    test('seuls « remise » et « annulée » ferment un dossier', () {
      expect(StatutCommandePressing.remise.estClose, isTrue);
      expect(StatutCommandePressing.annulee.estClose, isTrue);
      expect(StatutCommandePressing.partiellementRemise.estClose, isFalse);
      expect(StatutCommandePressing.prete.estClose, isFalse);
    });
  });

  group('PressingConfig', () {
    test('applique des valeurs sûres quand la réponse est vide', () {
      final PressingConfig c = PressingConfig.fromMap(<String, dynamic>{});
      expect(c.devise, 'CDF');
      expect(c.delaiStandardJours, 3);
      expect(c.soldeObligatoire, isTrue);
      expect(c.collecteActive, isFalse);
    });

    test('lit le serveur et se réémet à l’identique pour l’enregistrer', () {
      final PressingConfig c = PressingConfig.fromMap(<String, dynamic>{
        'devise': 'USD',
        'delai_standard_jours': 5,
        'supplement_urgence': '2000',
        'politique_remise': 'REMISE_POSSIBLE',
        'collecte_active': true,
        'frais_collecte': 1500,
      });

      expect(c.devise, 'USD');
      expect(c.delaiStandardJours, 5);
      expect(c.supplementUrgence, 2000);
      expect(c.soldeObligatoire, isFalse);

      final Map<String, dynamic> rpc = c.toRpc();
      expect(rpc['devise'], 'USD');
      expect(rpc['politique_remise'], 'REMISE_POSSIBLE');
      expect(rpc['collecte_active'], isTrue);
      expect(rpc['frais_collecte'], 1500);
    });
  });

  group('PressingCatalogue — le prix applicable', () {
    final PressingCatalogue catalogue = PressingCatalogue(
      categories: const <PressingCategorie>[
        PressingCategorie(id: 'c1', nom: 'Chemise'),
        PressingCategorie(id: 'c2', nom: 'Costume'),
      ],
      prestations: const <PressingPrestation>[
        PressingPrestation(id: 'p1', nom: 'Lavage et repassage'),
      ],
      tarifs: const <PressingTarif>[
        PressingTarif(id: 't1', prestationId: 'p1', prix: 2000),
        PressingTarif(
          id: 't2',
          prestationId: 'p1',
          categorieId: 'c1',
          prix: 3500,
        ),
        PressingTarif(
          id: 't3',
          prestationId: 'p1',
          categorieId: 'c2',
          prix: 8000,
          actif: false,
        ),
      ],
    );

    test('prend le tarif du type de vêtement quand il existe', () {
      expect(catalogue.prixPour('p1', 'c1'), 3500);
    });

    test('retombe sur le tarif par défaut', () {
      expect(catalogue.prixPour('p1', 'inconnu'), 2000);
      expect(catalogue.prixPour('p1', null), 2000);
    });

    test('ignore un tarif désactivé', () {
      // Costume : tarif spécifique désactivé ⇒ tarif par défaut.
      expect(catalogue.prixPour('p1', 'c2'), 2000);
    });

    test('renvoie null quand aucun prix n’est défini (jamais 0 inventé)', () {
      expect(catalogue.prixPour('p2', 'c1'), isNull);
    });

    test('retrouve les libellés par identifiant', () {
      expect(catalogue.categorieParId('c2')?.nom, 'Costume');
      expect(catalogue.prestationParId('p1')?.nom, 'Lavage et repassage');
      expect(catalogue.categorieParId(null), isNull);
    });

    test('un catalogue vide le dit', () {
      expect(const PressingCatalogue().estVide, isTrue);
      expect(catalogue.estVide, isFalse);
    });
  });

  group('PressingLigne', () {
    test('titre et détails lisibles par l’agent', () {
      final PressingLigne l = PressingLigne.fromMap(
        _ligne(
          id: 'l1',
          position: 3,
          designation: 'Chemise blanche',
          prestationNom: 'Repassage uniquement',
          marque: 'Zara',
          couleur: 'Blanc',
          taille: 'L',
        ),
      );

      expect(l.titre, '3 · Chemise blanche (Repassage uniquement)');
      expect(l.details, 'Zara · Blanc · taille L');
      expect(l.aDefauts, isFalse);
    });

    test('utilise le type de vêtement quand il n’y a pas de désignation', () {
      final PressingLigne l = PressingLigne.fromMap(
        _ligne(id: 'l2', categorieNom: 'Couverture'),
      );
      expect(l.titre, contains('Couverture'));
    });

    test('signale les défauts constatés au dépôt', () {
      final PressingLigne l = PressingLigne.fromMap(
        _ligne(id: 'l3', defauts: 'tache au col'),
      );
      expect(l.aDefauts, isTrue);
      expect(l.defauts, 'tache au col');
    });

    test('nettoie la liste des photos', () {
      final PressingLigne l = PressingLigne.fromMap(_ligne(id: 'l4'));
      expect(l.photos, <String>['https://exemple/1.jpg']);
    });

    test('un vêtement remis se reconnaît à sa date de remise', () {
      final PressingLigne remis = PressingLigne.fromMap(
        _ligne(id: 'l5', remise: true),
      );
      final PressingLigne pasRemis = PressingLigne.fromMap(_ligne(id: 'l6'));
      expect(remis.estRemis, isTrue);
      expect(pasRemis.estRemis, isFalse);
    });
  });

  group('PressingCommande', () {
    Map<String, dynamic> commande() => <String, dynamic>{
          'id': 'cmd-1',
          'numero': 'PR-2026-000001',
          'client_nom': 'Mama Sarah',
          'client_telephone': '+243990111222',
          'statut': 'PARTIELLEMENT_REMISE',
          'date_depot': '2026-11-08T09:00:00+00:00',
          'date_prevue': '2026-11-11T09:00:00+00:00',
          'devise': 'CDF',
          'total': '15000',
          'montant_paye': '5000',
          'solde': '10000',
          'qr_token': 'abc123',
          'lignes': <Map<String, dynamic>>[
            _ligne(id: 'l1', position: 1, prete: true, remise: true, etape: 'PRET'),
            _ligne(id: 'l2', position: 2, prete: true, remise: true, etape: 'PRET'),
            _ligne(id: 'l3', position: 3, prete: true, etape: 'PRET'),
            _ligne(id: 'l4', position: 4, prete: false),
            _ligne(id: 'l5', position: 5, prete: false),
          ],
          'paiements': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'pay-1',
              'montant': '5000',
              'mode': 'especes',
              'encaisse_le': '2026-11-08T09:05:00+00:00',
            },
          ],
          'historique': <Map<String, dynamic>>[
            <String, dynamic>{
              'ligne_id': 'l1',
              'etape_code': 'PRET',
              'etape_avant': 'REPASSAGE',
              'note': 'Contrôle qualité : conforme',
              'created_at': '2026-11-08T15:00:00+00:00',
            },
          ],
        };

    test('se lit complètement', () {
      final PressingCommande c = PressingCommande.fromMap(commande());
      expect(c.numero, 'PR-2026-000001');
      expect(c.clientNom, 'Mama Sarah');
      expect(c.statut, StatutCommandePressing.partiellementRemise);
      expect(c.total, 15000);
      expect(c.montantPaye, 5000);
      expect(c.solde, 10000);
      expect(c.lignes, hasLength(5));
      expect(c.paiements, hasLength(1));
      expect(c.historique, hasLength(1));
      expect(c.qrToken, 'abc123');
    });

    test('compte prêts, remis et en traitement sans se tromper', () {
      final PressingCommande c = PressingCommande.fromMap(commande());
      expect(c.nbLignes, 5);
      expect(c.nbRemis, 2);
      // l3 est prêt mais pas encore remis : il compte dans les prêts.
      expect(c.nbPrets, 1);
      expect(c.nbEnTraitement, 2);
      expect(c.lignesPretes, hasLength(1));
      expect(c.lignesPretes.first.id, 'l3');
    });

    test('un dossier de 5 vêtements dont 3 prêts n’est pas « terminé »', () {
      final PressingCommande c = PressingCommande.fromMap(commande());
      expect(c.statut, isNot(StatutCommandePressing.remise));
      expect(c.resume, contains('5 vêtements'));
    });

    test('reconnaît un retard seulement sur un dossier ouvert', () {
      final Map<String, dynamic> map = commande()
        ..['date_prevue'] = '2020-01-01T09:00:00+00:00';
      expect(PressingCommande.fromMap(map).estEnRetard, isTrue);

      final Map<String, dynamic> close = commande()
        ..['date_prevue'] = '2020-01-01T09:00:00+00:00'
        ..['statut'] = 'REMISE';
      expect(PressingCommande.fromMap(close).estEnRetard, isFalse);
    });

    test('un dossier annulé le dit', () {
      final Map<String, dynamic> map = commande()..['statut'] = 'ANNULEE';
      final PressingCommande c = PressingCommande.fromMap(map);
      expect(c.estAnnulee, isTrue);
      expect(c.estEnRetard, isFalse);
    });

    test('le résumé ne compte pas les remis comme prêts', () {
      final PressingCommande c = PressingCommande.fromMap(commande());
      expect(c.resume, contains('2 remis'));
    });
  });

  group('PressingPaiement', () {
    test('lit un versement et son mode en français', () {
      final PressingPaiement p = PressingPaiement.fromMap(<String, dynamic>{
        'id': 'p1',
        'montant': '3500',
        'mode': 'mobile_money',
        'reference': 'MM-99',
      });
      expect(p.montant, 3500);
      expect(p.libelleMode, 'Mobile Money');
      expect(p.estAnnule, isFalse);
    });

    test('un versement annulé garde son motif', () {
      final PressingPaiement p = PressingPaiement.fromMap(<String, dynamic>{
        'id': 'p2',
        'montant': 1000,
        'annule_le': '2026-11-09T10:00:00+00:00',
        'motif_annulation': 'erreur de caisse',
      });
      expect(p.estAnnule, isTrue);
      expect(p.motifAnnulation, 'erreur de caisse');
    });
  });

  group('PressingTableauBord', () {
    test('facturé et encaissé restent deux chiffres distincts', () {
      final PressingTableauBord d = PressingTableauBord.fromMap(
        <String, dynamic>{
          'commandes_aujourdhui': 4,
          'commandes_en_cours': 12,
          'vetements_en_traitement': 30,
          'vetements_prets': 7,
          'commandes_en_retard': 2,
          'montant_facture': '120000',
          'montant_encaisse': '75000',
          'montant_du': '45000',
        },
      );

      expect(d.commandesAujourdhui, 4);
      expect(d.vetementsPrets, 7);
      expect(d.commandesEnRetard, 2);
      expect(d.montantFacture, 120000);
      expect(d.montantEncaisse, 75000);
      expect(d.montantDu, 45000);
      expect(d.montantEncaisse, isNot(d.montantFacture));
    });

    test('une réponse vide donne des zéros, jamais des valeurs inventées', () {
      final PressingTableauBord d =
          PressingTableauBord.fromMap(<String, dynamic>{});
      expect(d.commandesAujourdhui, 0);
      expect(d.montantFacture, 0);
      expect(d.montantEncaisse, 0);
    });
  });

  group('LigneDepot — ce qui part au serveur', () {
    test('n’envoie pas de champs vides', () {
      const LigneDepot l = LigneDepot(
        categorieId: 'c1',
        prestationId: 'p1',
        designation: '  Chemise  ',
        couleur: '   ',
        quantite: 2,
      );

      final Map<String, dynamic> json = l.toJson();
      expect(json['categorie_id'], 'c1');
      expect(json['prestation_id'], 'p1');
      expect(json['designation'], 'Chemise');
      expect(json['quantite'], 2);
      expect(json.containsKey('couleur'), isFalse);
      expect(json.containsKey('marque'), isFalse);
      expect(json.containsKey('prix_unitaire'), isFalse);
    });

    test('transmet le prix saisi quand l’agent le connaît', () {
      const LigneDepot l = LigneDepot(
        categorieId: 'c1',
        prestationId: 'p1',
        prixUnitaire: 4500,
      );
      expect(l.toJson()['prix_unitaire'], 4500);
    });

    test('transmet les photos uniquement si elles existent', () {
      const LigneDepot sans = LigneDepot(categorieId: 'c1');
      const LigneDepot avec = LigneDepot(
        categorieId: 'c1',
        photos: <String>['https://exemple/a.jpg'],
      );

      expect(sans.toJson().containsKey('photos'), isFalse);
      expect(avec.toJson()['photos'], <String>['https://exemple/a.jpg']);
    });
  });

  group('PressingClient', () {
    test('sous-titre : téléphone puis adresse, sans séparateur inutile', () {
      final PressingClient c = PressingClient.fromMap(<String, dynamic>{
        'id': 'cl1',
        'nom': 'Mama Sarah',
        'telephone': '+243 990 111 222',
        'adresse': 'Av. Lumumba 12',
      });
      expect(c.sousTitre, '+243 990 111 222 · Av. Lumumba 12');

      final PressingClient seul = PressingClient.fromMap(<String, dynamic>{
        'id': 'cl2',
        'nom': 'Jean',
      });
      expect(seul.sousTitre, isEmpty);
    });
  });

  group('PressingRetrait', () {
    test('lit une opération de remise et ses vêtements', () {
      final PressingRetrait r = PressingRetrait.fromMap(<String, dynamic>{
        'id': 'r1',
        'created_at': '2026-11-09T11:00:00+00:00',
        'montant_encaisse': '7000',
        'mode_paiement': 'especes',
        'signataire': 'Mama Sarah',
        'lignes': <Map<String, dynamic>>[
          <String, dynamic>{
            'ligne_id': 'l1',
            'position': 1,
            'designation': 'Chemise',
          },
        ],
      });

      expect(r.montantEncaisse, 7000);
      expect(r.signataire, 'Mama Sarah');
      expect(r.lignes, hasLength(1));
      expect(r.lignes.first.designation, 'Chemise');
    });
  });

  group('PressingEtape', () {
    test('l’étape finale est reconnue (elle seule rend un vêtement remis­able)', () {
      final PressingEtape finale = PressingEtape.fromMap(<String, dynamic>{
        'id': 'e1',
        'code': 'PRET',
        'libelle': 'Prêt à récupérer',
        'est_finale': true,
      });
      final PressingEtape lavage = PressingEtape.fromMap(<String, dynamic>{
        'id': 'e2',
        'code': 'LAVAGE',
        'libelle': 'Lavage',
      });

      expect(finale.estFinale, isTrue);
      expect(lavage.estFinale, isFalse);
    });
  });
}
