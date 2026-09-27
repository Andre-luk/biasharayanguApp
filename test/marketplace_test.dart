// test/marketplace_test.dart
//
// 🛒 MODULE 19 — TESTS DU MARKETPLACE LOCAL GÉOLOCALISÉ.
//
// Ces tests couvrent la logique PURE du module (aucun accès réseau) :
//   • formatage des distances et liens externes (aucune clé d'API) ;
//   • normalisation de recherche (miroir de `public.biashara_normaliser`) ;
//   • lecture des réponses serveur (produits, boutiques, publicités,
//     visibilité, codes d'attribution) ;
//   • règles métier sensibles : séparation public/privé, avis de pertinence,
//     comparaison des prix, distinction visibilité / intérêt / intention /
//     conversion, mention « PUBLICITÉ » toujours présente.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/accueil_public.dart';
import 'package:biashara_yangu/models/boutique_publique.dart';
import 'package:biashara_yangu/models/lien_attribution.dart';
import 'package:biashara_yangu/models/localisation_boutique.dart';
import 'package:biashara_yangu/models/produit_public.dart';
import 'package:biashara_yangu/models/publication_produit.dart';
import 'package:biashara_yangu/models/publicite_biashara.dart';
import 'package:biashara_yangu/models/visibilite_biashara.dart';
import 'package:biashara_yangu/services/marketplace_service.dart';
import 'package:biashara_yangu/services/vitrine_service.dart';
import 'package:biashara_yangu/utils/geo_utils.dart';

/// Réponse serveur type d'un résultat de recherche publique.
Map<String, dynamic> _resultatBrut({
  String publicationId = 'pub-1',
  int produitId = 42,
  String nom = 'Riz parfumé 25 kg',
  double prix = 45000,
  String boutique = 'Boutique A',
  String? slug = 'boutique-a',
  double? distanceKm = 0.84,
  bool disponible = true,
}) {
  return <String, dynamic>{
    'publication_id': publicationId,
    'produit_id': produitId,
    'nom': nom,
    'description': 'Sac de 25 kg',
    'photo': null,
    'prix': prix,
    'unite': 'sac',
    'categorie': 'cereales',
    'disponible': disponible,
    'vendable_au_poids': false,
    'attributs': <String, dynamic>{},
    'distance_km': distanceKm,
    'score': 78,
    'boutique': <String, dynamic>{
      'espace_id': 'espace-$slug',
      'nom': boutique,
      'slug': slug,
      'type': 'boutique',
      'logo_url': null,
      'quartier': 'Katuba',
      'adresse': 'Avenue Kasaï 12',
      'ville': 'Lubumbashi',
      'telephone': '+243974084668',
      'whatsapp': '+243974084668',
      'latitude': -11.66,
      'longitude': 27.48,
      'localisation_verifiee': true,
    },
  };
}

void main() {
  // =========================================================================
  // OUTILS GÉOGRAPHIQUES & LIENS
  // =========================================================================
  group('formatDistance', () {
    test('aucune position connue => rien à afficher', () {
      expect(formatDistance(null), isNull);
    });

    test('moins d\'un kilomètre => mètres arrondis à la dizaine', () {
      expect(formatDistance(0.84), '840 m');
      expect(formatDistance(0.004), '0 m');
    });

    test('1 à 10 km => kilomètres avec virgule française', () {
      expect(formatDistance(1.24), '1,2 km');
      expect(formatDistance(9.96), '10,0 km');
    });

    test('au-delà de 10 km => kilomètres entiers (la précision n\'aide plus)', () {
      expect(formatDistance(24.4), '24 km');
    });
  });

  group('trancheDistance (statistiques sans position exacte)', () {
    test('les cinq tranches', () {
      expect(trancheDistance(null), 'inconnue');
      expect(trancheDistance(0.4), '<1');
      expect(trancheDistance(2.5), '1-3');
      expect(trancheDistance(7), '3-10');
      expect(trancheDistance(42), '>10');
    });
  });

  group('normaliserRecherche (miroir de biashara_normaliser)', () {
    test('minuscules, accents et espaces superflus', () {
      expect(normaliserRecherche('  RIZ  Parfumé '), 'riz parfume');
      expect(normaliserRecherche('Chaussures HOMME'), 'chaussures homme');
      expect(normaliserRecherche('ÉCRAN\tTactile'), 'ecran tactile');
    });

    test('une chaîne vide reste vide (aucun plantage)', () {
      expect(normaliserRecherche('   '), '');
    });
  });

  group('liens externes (aucune clé d\'API)', () {
    test('itinéraire : destination toujours présente, origine ajoutée', () {
      final String sansDepart = lienItineraire(latitude: -11.66, longitude: 27.48);
      expect(sansDepart, contains('destination=-11.660000,27.480000'));
      expect(sansDepart, isNot(contains('origin=')));
      expect(sansDepart, contains('maps'));

      final String avecdepart = lienItineraire(
        latitude: -11.66,
        longitude: 27.48,
        depuisLat: -11.7,
        depuisLng: 27.5,
      );
      expect(avecdepart, contains('origin=-11.700000,27.500000'));
    });

    test('WhatsApp : refusé si le numéro est inexploitable', () {
      expect(lienWhatsApp(null), isNull);
      expect(lienWhatsApp('123'), isNull);
      expect(
        lienWhatsApp('+243 974 084 668'),
        'https://wa.me/243974084668',
      );
      expect(
        lienWhatsApp('0974084668', message: 'Bonjour'),
        contains('text=Bonjour'),
      );
    });

    test('téléphone : lien tel: ou rien', () {
      expect(lienTelephone(null), isNull);
      expect(lienTelephone('12'), isNull);
      expect(lienTelephone('+243 974 084 668'), 'tel:+243974084668');
    });

    test('numéroWhatsApp normalise la saisie', () {
      expect(numeroWhatsApp('+243 974-084-668'), '243974084668');
      expect(numeroWhatsApp(''), isNull);
    });
  });

  group('adresseComplete (visiteur étranger)', () {
    test('assemble voie, quartier, repère, ville et pays', () {
      final String adresse = adresseComplete(
        numero: '12',
        avenue: 'Avenue Kasaï',
        quartier: 'Katuba',
        pointRepere: 'face à la poste',
        ville: 'Lubumbashi',
        pays: 'RDC',
      );
      expect(adresse, contains('12 Avenue Kasaï'));
      expect(adresse, contains('Katuba'));
      expect(adresse, contains('repère : face à la poste'));
      expect(adresse, contains('Lubumbashi'));
      expect(adresse, contains('RDC'));
    });

    test('sans aucune information => chaîne vide', () {
      expect(adresseComplete(), '');
    });
  });

  // =========================================================================
  // LECTURE DES RÉPONSES SERVEUR
  // =========================================================================
  group('ProduitPublic', () {
    test('lecture complète d\'un résultat de recherche', () {
      final ProduitPublic produit =
          ProduitPublic.fromMap(_resultatBrut());

      expect(produit.publicationId, 'pub-1');
      expect(produit.produitId, 42);
      expect(produit.nom, 'Riz parfumé 25 kg');
      expect(produit.prix, 45000);
      expect(produit.unite, 'sac');
      expect(produit.disponible, isTrue);
      expect(produit.boutique.nom, 'Boutique A');
      expect(produit.distanceLibelle, '840 m');
      expect(produit.cheminPublic, '/biashara/produit/pub-1');
      expect(produit.prixAvecUnite('45 000 CDF'), '45 000 CDF / sac');
    });

    test('un article sans photo reste affichable (aucune exception)', () {
      final ProduitPublic produit = ProduitPublic.fromMap(_resultatBrut());
      expect(produit.photo, isNull);
    });

    test('les variantes sont exposées quand elles existent', () {
      final Map<String, dynamic> brut = _resultatBrut();
      brut['attributs'] = <String, dynamic>{'taille': 'M', 'couleur': 'Bleu'};
      final ProduitPublic produit = ProduitPublic.fromMap(brut);
      expect(produit.resumeVariantes, contains('M'));
      expect(produit.resumeVariantes, contains('Bleu'));
    });

    test('disponibilité déclarée : jamais de stock exact exposé', () {
      final ProduitPublic produit = ProduitPublic.fromMap(
        _resultatBrut(disponible: false),
      );
      expect(produit.disponible, isFalse);
    });
  });

  group('ResumeBoutique', () {
    test('position, type lisible et lien partageable', () {
      final ResumeBoutique boutique = ResumeBoutique.fromMap(
        Map<String, dynamic>.from(
          (_resultatBrut()['boutique'] as Map).cast<String, dynamic>(),
        ),
      );

      expect(boutique.aPosition, isTrue);
      expect(boutique.typeLibelle, 'Boutique');
      expect(boutique.cheminPublic, '/biashara/boutique/boutique-a');
      expect(boutique.adresseLisible, contains('Katuba'));
      expect(boutique.localisationVerifiee, isTrue);
      expect(boutique.lienItineraireDepuis(), contains('destination='));
    });

    test('boutique sans slug ni position : pas de lien public, pas d\'itinéraire',
        () {
      final ResumeBoutique boutique = ResumeBoutique.fromMap(<String, dynamic>{
        'espace_id': 'espace-1',
        'nom': 'Boutique sans GPS',
      });

      expect(boutique.aPosition, isFalse);
      expect(boutique.cheminPublic, isNull);
      expect(boutique.lienItineraireDepuis(), isNull);
      expect(boutique.distanceLibelle, isNull);
    });
  });

  group('BoutiquePublique', () {
    Map<String, dynamic> reponse() => <String, dynamic>{
          'boutique': <String, dynamic>{
            'espace_id': 'espace-1',
            'nom': 'Alimentation Jambo',
            'slug': 'alimentation-jambo',
            'type': 'boutique',
            'description': 'Produits de première nécessité',
            'telephone': '+243900000000',
            'whatsapp': '+243900000000',
            'horaires': <String, dynamic>{
              'jours': <dynamic>[
                <String, dynamic>{'j': 'lun', 'o': '08:00', 'f': '18:00'},
                <String, dynamic>{'j': 'dim'},
              ],
              'note': 'Fermé les jours fériés',
            },
            'logo_url': null,
            'photo_url': null,
            'adresse': null,
            'quartier': 'Katuba',
            'avenue': 'Avenue Kasaï',
            'numero': '12',
            'point_repere': 'face à la poste',
            'latitude': -11.66,
            'longitude': 27.48,
            'ville': 'Lubumbashi',
            'pays': 'RDC',
            'localisation_verifiee': false,
            'distance_km': 1.2,
          },
          'produits': <dynamic>[_resultatBrut()],
          'nb_produits': 1,
          'publicites': <dynamic>[],
        };

    test('fiche complète : horaires lisibles et adresse de visiteur', () {
      final BoutiquePublique boutique = BoutiquePublique.fromMap(reponse());

      expect(boutique.nom, 'Alimentation Jambo');
      expect(boutique.typeLibelle, 'Boutique');
      expect(boutique.distanceLibelle, '1,2 km');
      expect(boutique.horairesLisibles,
          containsAll(<String>['lun : 08:00 – 18:00', 'dim : fermé']));
      expect(boutique.horairesLisibles.last, 'Fermé les jours fériés');
      expect(boutique.adresseLisible, contains('12 Avenue Kasaï'));
      expect(boutique.adresseLisible, contains('repère : face à la poste'));
      expect(boutique.nbProduits, 1);
      expect(boutique.produits, hasLength(1));
    });

    test('horaires absents : liste vide, jamais d\'exception', () {
      final Map<String, dynamic> brut = reponse();
      (brut['boutique'] as Map)['horaires'] = null;
      final BoutiquePublique boutique = BoutiquePublique.fromMap(brut);
      expect(boutique.horairesLisibles, isEmpty);
    });
  });

  group('ResultatRecherchePublic', () {
    test('résultats, total, publicités séparées et identifiant de recherche',
        () {
      final ResultatRecherchePublic resultat =
          ResultatRecherchePublic.fromMap(<String, dynamic>{
        'texte': 'riz',
        'tri': 'distance',
        'total': 7,
        'nb_boutiques': 4,
        'recherche_id': 12,
        // La publicité est dans un tableau SÉPARÉ : elle n'est jamais mêlée
        // aux résultats organiques.
        'publicites': <dynamic>[
          <String, dynamic>{
            'id': 'pub-1',
            'titre': 'Promo riz',
            'mention': 'PUBLICITÉ',
            'type_contenu': 'promotion',
          },
        ],
        'resultats': <dynamic>[_resultatBrut()],
      });

      expect(resultat.tri, TriRecherche.distance);
      expect(resultat.total, 7);
      expect(resultat.nbBoutiques, 4);
      expect(resultat.rechercheId, 12);
      expect(resultat.resultats, hasLength(1));
      expect(resultat.publicites, hasLength(1));
      expect(resultat.publicites.first.mention, 'PUBLICITÉ');
      expect(resultat.vide, isFalse);
    });

    test('tri inconnu => pertinence (repli sûr)', () {
      expect(TriRecherche.fromCode('n\'importe quoi'), TriRecherche.pertinence);
      expect(TriRecherche.fromCode(null), TriRecherche.pertinence);
    });
  });

  group('AccueilPublic', () {
    test('catégories, produits « à plat » et boutiques', () {
      final AccueilPublic accueil = AccueilPublic.fromMap(<String, dynamic>{
        'categories': <dynamic>[
          <String, dynamic>{
            'categorie': 'boissons',
            'libelle': 'boissons',
            'nb_produits': 12,
          },
        ],
        'produits': <dynamic>[
          <String, dynamic>{
            'publication_id': 'pub-9',
            'produit_id': 9,
            'nom': 'Coca-Cola 33cl',
            'photo': null,
            'prix': 1000,
            'unite': 'pièce',
            'disponible': true,
            'boutique_nom': 'Boutique A',
            'boutique_slug': 'boutique-a',
            'quartier': 'Katuba',
            'ville': 'Lubumbashi',
            'distance_km': 0.5,
          },
        ],
        'boutiques': <dynamic>[
          <String, dynamic>{
            'espace_id': 'espace-1',
            'nom': 'Boutique A',
            'slug': 'boutique-a',
            'nb_produits': 3,
          },
        ],
        'publicites': <dynamic>[],
      });

      expect(accueil.categories.first.libelleAffiche, 'Boissons');
      expect(accueil.produits.first.boutique.nom, 'Boutique A');
      expect(accueil.produits.first.boutique.slug, 'boutique-a');
      expect(accueil.boutiques.first.nbProduits, 3);
      expect(accueil.vide, isFalse);
    });

    test('accueil vide : signalé comme tel', () {
      expect(const AccueilPublic().vide, isTrue);
    });
  });

  group('FicheProduitPublic — comparaison des prix', () {
    FicheProduitPublic fiche() => FicheProduitPublic.fromMap(<String, dynamic>{
          'produit': <String, dynamic>{
            'publication_id': 'pub-a',
            'produit_id': 1,
            'nom': 'Riz 25 kg',
            'prix': 47000,
            'unite': 'sac',
            'disponible': true,
          },
          'boutique': <String, dynamic>{
            'espace_id': 'espace-a',
            'nom': 'Boutique A',
            'slug': 'boutique-a',
          },
          'autres_boutiques': <dynamic>[
            <String, dynamic>{
              'publication_id': 'pub-b',
              'produit_id': 2,
              'nom': 'Riz 25 kg',
              'prix': 42000,
              'unite': 'sac',
              'disponible': true,
              'espace_id': 'espace-b',
              'boutique_nom': 'Boutique B',
              'boutique_slug': 'boutique-b',
              'distance_km': 2.4,
            },
          ],
          'publicites': <dynamic>[],
        });

    test('les offres sont classées du moins cher au plus cher', () {
      final FicheProduitPublic f = fiche();
      expect(f.nbBoutiques, 2);
      expect(f.comparaisonTriees.first.boutique.nom, 'Boutique B');
      expect(f.prixMin, 42000);
      expect(f.prixMax, 47000);
    });

    test('un seul point de vente : la comparaison reste cohérente', () {
      final FicheProduitPublic f = FicheProduitPublic.fromMap(<String, dynamic>{
        'produit': <String, dynamic>{'publication_id': 'p', 'prix': 1000},
        'boutique': <String, dynamic>{'espace_id': 'e', 'nom': 'Seule'},
      });
      expect(f.nbBoutiques, 1);
      expect(f.prixMin, f.prixMax);
    });
  });

  group('ComparaisonPrix (regroupement local)', () {
    test('regroupe les produits identiques et calcule l\'écart', () {
      final List<ProduitPublic> produits = <ProduitPublic>[
        ProduitPublic.fromMap(_resultatBrut(prix: 45000, boutique: 'A')),
        ProduitPublic.fromMap(_resultatBrut(prix: 42000, boutique: 'C')),
        ProduitPublic.fromMap(_resultatBrut(prix: 47000, boutique: 'B')),
        ProduitPublic.fromMap(_resultatBrut(nom: 'Téléphone Tecno', prix: 120000)),
      ];

      final List<ComparaisonPrix> groupes =
          ComparaisonPrix.depuisProduits(produits);

      expect(groupes, hasLength(1));
      expect(groupes.first.offres, hasLength(3));
      expect(groupes.first.prixMin, 42000);
      expect(groupes.first.prixMax, 47000);
      expect(groupes.first.ecartPourcent, 12); // (47000-42000)/42000 ≈ 12 %
      expect(groupes.first.offres.first.prix, 42000);
    });

    test('un produit unique ne déclenche aucune comparaison', () {
      final List<ProduitPublic> produits = <ProduitPublic>[
        ProduitPublic.fromMap(_resultatBrut(boutique: 'Unique')),
      ];
      expect(ComparaisonPrix.depuisProduits(produits), isEmpty);
    });
  });

  // =========================================================================
  // ESPACE COMMERÇANT
  // =========================================================================
  group('LocalisationBoutique', () {
    Map<String, dynamic> etat({String statut = 'a_verifier'}) =>
        <String, dynamic>{
          'espace_id': 'espace-1',
          'nom': 'Ma boutique',
          'type': 'boutique',
          'visible_publiquement': true,
          'slug': 'ma-boutique',
          'description_publique': 'Épicerie de quartier',
          'telephone_public': '+243900000000',
          'whatsapp': '+243900000000',
          'horaires': <String, dynamic>{},
          'adresse': null,
          'quartier': 'Katuba',
          'avenue': null,
          'numero': null,
          'point_repere': null,
          'latitude': -11.66,
          'longitude': 27.48,
          'precision_localisation': 'gps',
          'statut_localisation': statut,
          'ville': 'Lubumbashi',
          'nb_produits_publies': 4,
          'nb_produits': 10,
          'compte_operationnel': true,
          'visible_effectivement': true,
          'activation_etape': 'actif',
        };

    test('état lu, diagnostic des informations manquantes', () {
      final LocalisationBoutique boutique =
          LocalisationBoutique.fromMap(etat());

      expect(boutique.aPosition, isTrue);
      expect(boutique.precision, PrecisionLocalisation.gps);
      expect(boutique.statut, StatutLocalisation.aVerifier);
      expect(boutique.statut.estConfirmee, isFalse);
      expect(boutique.cheminPublic, '/biashara/boutique/ma-boutique');
      expect(boutique.pretAPublier, isTrue);
      expect(boutique.pointsManquants, contains('Point de repère'));
      expect(boutique.pointsManquants, contains('Horaires'));
      expect(boutique.messageVisibilite, contains('visible'));
    });

    test('position confirmée', () {
      final LocalisationBoutique boutique =
          LocalisationBoutique.fromMap(etat(statut: 'verifiee'));
      expect(boutique.statut, StatutLocalisation.verifiee);
      expect(boutique.statut.estConfirmee, isTrue);
    });

    test('compte non validé : vitrine prête mais non publiée, message honnête',
        () {
      final Map<String, dynamic> brut = etat();
      brut['compte_operationnel'] = false;
      brut['visible_effectivement'] = false;
      brut['activation_etape'] = 'en_attente_verification';

      final LocalisationBoutique boutique = LocalisationBoutique.fromMap(brut);
      expect(boutique.enAttenteActivation, isTrue);
      expect(boutique.messageVisibilite, contains('validé'));
    });

    test('sans position : le message invite à la renseigner', () {
      final Map<String, dynamic> brut = etat();
      brut['latitude'] = null;
      brut['longitude'] = null;
      brut['statut_localisation'] = 'non_renseignee';

      final LocalisationBoutique boutique = LocalisationBoutique.fromMap(brut);
      expect(boutique.aPosition, isFalse);
      expect(boutique.pretAPublier, isFalse);
      expect(boutique.pointsManquants, contains('Position de la boutique'));
      expect(boutique.messageVisibilite, contains('position'));
    });

    test('libellé d\'une origine de position inconnue', () {
      expect(PrecisionLocalisation.libelleOuInconnu(null), 'Origine inconnue');
      expect(PrecisionLocalisation.libelleOuInconnu('gps'),
          'Ma position actuelle');
      expect(PrecisionLocalisation.fromCode('carte'),
          PrecisionLocalisation.carte);
      expect(PrecisionLocalisation.fromCode('zzz'), isNull);
    });
  });

  group('PublicationProduit & EtatPublications', () {
    test('complétude et informations manquantes', () {
      const PublicationProduit pauvre = PublicationProduit(
        produitId: 1,
        nom: 'Article sans photo',
        publie: true,
        disponible: true,
        prixVente: 1000,
      );
      expect(pauvre.completude, 40);
      expect(pauvre.informationsManquantes, contains('Photo'));
      expect(pauvre.informationsManquantes,
          contains('Courte description'));

      const PublicationProduit riche = PublicationProduit(
        produitId: 2,
        nom: 'Article complet',
        photo: 'https://exemple.cd/photo.jpg',
        descriptionCourte: 'Très bon produit',
        motsCles: 'riz, sac',
        publie: true,
        disponible: true,
        prixVente: 2000,
        prixPublic: 2500,
        unite: 'sac',
      );
      expect(riche.completude, 100);
      expect(riche.prixAffiche, 2500);
      expect(riche.prixPersonnalise, isTrue);
      expect(riche.informationsManquantes, isEmpty);
    });

    test('prix public identique au prix de vente : pas de personnalisation', () {
      const PublicationProduit article = PublicationProduit(
        produitId: 3,
        nom: 'Normal',
        publie: true,
        disponible: true,
        prixVente: 1000,
        prixPublic: 1000,
      );
      expect(article.prixPersonnalise, isFalse);
    });

    test('état global : taux de publication et compteurs', () {
      final EtatPublications etat = EtatPublications.fromMap(<String, dynamic>{
        'espace_id': 'espace-1',
        'total': 10,
        'nb_publies': 4,
        'articles': <dynamic>[
          <String, dynamic>{
            'produit_id': 1,
            'nom': 'Riz',
            'publie': true,
            'disponible': true,
            'prix_vente': 45000,
            'unite': 'sac',
          },
        ],
      });

      expect(etat.total, 10);
      expect(etat.nbPublies, 4);
      expect(etat.tauxPublication, 40);
      expect(etat.articles.first.publie, isTrue);
    });

    test('catalogue vide : aucun division par zéro', () {
      expect(const EtatPublications().tauxPublication, 0);
    });
  });

  group('VisibiliteBiashara — quatre niveaux distincts', () {
    VisibiliteBiashara donnees() =>
        VisibiliteBiashara.fromMap(<String, dynamic>{
          'debut': '2026-09-01',
          'fin': '2026-09-27',
          'resume': <String, dynamic>{
            'visibilite': 120,
            'interet': 24,
            'intention': 6,
            'conversion': 2,
            'total': 152,
          },
          'par_type': <dynamic>[
            <String, dynamic>{
              'type_evenement': 'vue_boutique',
              'categorie': 'interet',
              'nb': 20,
            },
          ],
          'par_jour': <dynamic>[
            <String, dynamic>{
              'jour': '2026-09-20',
              'visibilite': 10,
              'interet': 2,
              'intention': 1,
              'conversion': 0,
            },
          ],
          'top_produits': <dynamic>[
            <String, dynamic>{
              'entite_id': 'pub-1',
              'nom': 'Riz 25 kg',
              'vues': 12,
              'itineraire': 3,
              'telephone': 1,
              'whatsapp': 2,
              'total': 18,
            },
          ],
          'nb_recherches': 5,
          'publicites': <dynamic>[],
          'note_conversion': 'La conversion ne compte qu\'un achat attribué.',
        });

    test('les compteurs restent séparés : une vue n\'est pas un achat', () {
      final VisibiliteBiashara v = donnees();

      expect(v.resume.visibilite, 120);
      expect(v.resume.interet, 24);
      expect(v.resume.intention, 6);
      expect(v.resume.conversion, 2);
      expect(v.resume.total, 152);
      expect(v.resume.pour(CategorieEvenement.conversion), 2);
      // Taux calculés uniquement sur les affichages réels.
      expect(v.resume.tauxInteret, 20);
      expect(v.resume.tauxIntention, 5);
      expect(v.vide, isFalse);
      expect(v.nbRecherches, 5);
      expect(v.noteConversion, contains('attribué'));
    });

    test('aucun affichage : aucun taux (pas de division par zéro)', () {
      const ResumeVisibilite vide = ResumeVisibilite();
      expect(vide.tauxInteret, isNull);
      expect(vide.tauxIntention, isNull);
    });

    test('libellés des types d\'événements (français, jamais de code brut)', () {
      expect(libelleEvenement('clic_itineraire'), 'Itinéraire demandé');
      expect(libelleEvenement('clic_whatsapp'), 'WhatsApp ouvert');
      expect(libelleEvenement('vue_boutique'), 'Fiche boutique consultée');
      expect(CategorieEvenement.fromCode('intention'), CategorieEvenement.intention);
      expect(CategorieEvenement.fromCode('zzz'), CategorieEvenement.autre);
    });

    test('évolution : pourcentage comparé à la période précédente', () {
      final VisibiliteBiashara v = donnees();
      expect(v.evolutionPourcent(150, 100), 50);
      expect(v.evolutionPourcent(50, 100), -50);
      expect(v.evolutionPourcent(10, 0), 100);
      expect(v.evolutionPourcent(0, 0), isNull);
    });

    test('séries journalières et produits consultés', () {
      final VisibiliteBiashara v = donnees();
      expect(v.parJour, hasLength(1));
      expect(v.parJour.first.total, 13);
      expect(v.parType.first.libelle, 'Fiche boutique consultée');
      expect(v.topProduits.first.nom, 'Riz 25 kg');
      expect(v.topProduits.first.itineraire, 3);
    });
  });

  group('PubliciteBiashara — préparation honnête', () {
    Map<String, dynamic> brut({String statut = 'active'}) => <String, dynamic>{
          'id': 'pub-1',
          'titre': 'Riz en promotion',
          'message': '-10 % cette semaine',
          'mention': 'PUBLICITÉ',
          'type_contenu': 'promotion',
          'produit_id': 42,
          'publication_id': 'pub-9',
          'prix_promo': 40000,
          'statut': statut,
          'impressions': 200,
          'clics': 25,
          'conversions': 3,
          'boutique_nom': 'Boutique A',
          'boutique_slug': 'boutique-a',
          'cibles': <dynamic>[
            <String, dynamic>{
              'type_cible': 'rayon',
              'rayon_km': 5,
              'centre_lat': -11.66,
              'centre_lng': 27.48,
            },
          ],
        };

    test('la mention « PUBLICITÉ » est toujours portée par l\'annonce', () {
      final PubliciteBiashara pub = PubliciteBiashara.fromMap(brut());
      expect(pub.mention, 'PUBLICITÉ');
      expect(pub.typeContenu, TypeContenuPublicite.promotion);
      expect(pub.tauxClic, 13); // 25/200 → 12,5 % arrondi
      expect(pub.ciblageLisible, contains('Rayon de 5 km'));
      expect(pub.cheminPublic, '/biashara/produit/pub-9');
    });

    test('mention par défaut si le serveur n\'en fournit pas', () {
      final PubliciteBiashara pub =
          PubliciteBiashara.fromMap(<String, dynamic>{'id': 'x', 'titre': 't'});
      expect(pub.mention, 'PUBLICITÉ');
      expect(pub.publicationId, isNull);
    });

    test('cycle de vie : seul un statut modifiable est éditable ; seule une '
        'campagne active est diffusée', () {
      expect(StatutPublicite.brouillon.modifiable, isTrue);
      expect(StatutPublicite.pause.modifiable, isTrue);
      expect(StatutPublicite.refusee.modifiable, isTrue);
      expect(StatutPublicite.active.modifiable, isFalse);
      expect(StatutPublicite.soumise.modifiable, isFalse);

      expect(StatutPublicite.active.diffusee, isTrue);
      expect(StatutPublicite.brouillon.diffusee, isFalse);
      expect(StatutPublicite.pause.diffusee, isFalse);
    });

    test('cible publicitaire : aller-retour JSON sans perte', () {
      const CiblePublicite cible = CiblePublicite(
        type: TypeCiblePublicite.rayon,
        rayonKm: 3,
        centreLat: -11.66,
        centreLng: 27.48,
      );
      final Map<String, dynamic> map = cible.toMap();
      expect(map['type_cible'], 'rayon');
      expect(map['rayon_km'], 3);

      final CiblePublicite relue = CiblePublicite.fromMap(map);
      expect(relue.type, TypeCiblePublicite.rayon);
      expect(relue.rayonKm, 3);
      expect(relue.libelle, contains('Rayon de 3 km'));
    });

    test('ciblage vide = toute la plateforme (explicite pour le commerçant)', () {
      expect(const PubliciteBiashara(id: 'x', titre: 't').ciblageLisible,
          'Toute la plateforme');
    });

    test('sans cible : un ciblage « ville » s\'affiche lisiblement', () {
      const CiblePublicite cible = CiblePublicite(
        type: TypeCiblePublicite.ville,
        villeId: 'ville-1',
      );
      expect(cible.libelle, contains('Ville'));
    });
  });

  group('LienAttribution', () {
    test('code promotionnel : le code technique « code » reste reconnu', () {
      expect(TypeLienAttribution.fromCode('code'),
          TypeLienAttribution.promotionnel);
      expect(TypeLienAttribution.promotionnel.code, 'code');
      expect(TypeLienAttribution.fromCode('qr'), TypeLienAttribution.qr);
      expect(TypeLienAttribution.fromCode(null), TypeLienAttribution.qr);
    });

    test('lecture et message client', () {
      final LienAttribution lien =
          LienAttribution.fromMap(<String, dynamic>{
        'id': 'l-1',
        'code': 'BIA-4F2A9C',
        'type_lien': 'qr',
        'libelle': 'QR vitrine',
        'actif': true,
        'utilisations': 0,
      });

      expect(lien.code, 'BIA-4F2A9C');
      expect(lien.type, TypeLienAttribution.qr);
      expect(lien.messageClient, contains('BIA-4F2A9C'));
      // Une conversion n'est comptée QUE si le code est utilisé.
      expect(lien.utilisations, 0);
    });
  });

  // =========================================================================
  // MESSAGES D'ERREUR (contrat serveur « CODE|message »)
  // =========================================================================
  group('messages d\'erreur serveur', () {
    test('le code technique est retiré, le texte français est conservé', () {
      expect(
        MarketplaceService.messageErreur(
            'BOUTIQUE_INCONNUE|Cette boutique n\'est plus présente.'),
        'Cette boutique n\'est plus présente.',
      );
      expect(VitrineService.messageErreur('ACCES_REFUSE|Interdit.'),
          'Interdit.');
    });

    test('un message sans code reste inchangé', () {
      expect(MarketplaceService.messageErreur('Erreur simple'),
          'Erreur simple');
      expect(VitrineService.messageErreur(''), '');
    });
  });

  group('VillePublique', () {
    test('libellé avec le nombre de boutiques', () {
      final VillePublique ville = VillePublique.fromMap(<String, dynamic>{
        'id': 'v-1',
        'nom': 'Lubumbashi',
        'pays': 'RDC',
        'nb_boutiques': 12,
      });
      expect(ville.libelleAffiche, 'Lubumbashi (12)');
      expect(
        const VillePublique(id: 'v-2', nom: 'Kolwezi').libelleAffiche,
        'Kolwezi',
      );
    });
  });
}
