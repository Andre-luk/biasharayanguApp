// test/salle_fete_test.dart
//
// 🎉 MODULE 16 (phase C4) — Tests PURS de la salle des fêtes :
// modèles (salle, événement, prestations, tableau de bord), statuts,
// calculs (jours, solde), filtre de recherche et messages d'erreur.
// Aucun réseau : tout est construit depuis des maps JSON simulées.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/evenement.dart';
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/salle.dart';
import 'package:biashara_yangu/models/salle_fete_tableau_bord.dart';
import 'package:biashara_yangu/services/salle_fete_service.dart';

void main() {
  // =========================================================================
  // 1. LE MODÈLE SALLE
  // =========================================================================

  group('Salle', () {
    test('fromMap lit la ligne complète', () {
      final Salle salle = Salle.fromMap(<String, dynamic>{
        'id': 'salle-1',
        'nom': 'Terrasse',
        'capacite': 250,
        'prix_jour': 180000.0,
        'description': 'Vue sur jardin',
        'equipements': 'Sono, parking',
        'actif': true,
        'owner_id': 'owner-1',
      });

      expect(salle.id, 'salle-1');
      expect(salle.nom, 'Terrasse');
      expect(salle.capacite, 250);
      expect(salle.prixJour, 180000);
      expect(salle.description, 'Vue sur jardin');
      expect(salle.equipements, 'Sono, parking');
      expect(salle.actif, isTrue);
      expect(salle.designation, 'Terrasse · 250 pers.');
    });

    test('fromMap tolère les champs absents (défauts sûrs)', () {
      final Salle salle = Salle.fromMap(<String, dynamic>{'id': 'x'});

      expect(salle.nom, 'Salle');
      expect(salle.capacite, 50);
      expect(salle.prixJour, 0);
      expect(salle.actif, isTrue, reason: 'actif absent = active');
      expect(salle.description, isNull);
    });

    test('actif = false est respecté', () {
      final Salle salle = Salle.fromMap(<String, dynamic>{
        'id': 'x',
        'nom': 'Petite salle',
        'actif': false,
      });
      expect(salle.actif, isFalse);
    });
  });

  // =========================================================================
  // 2. LES STATUTS D'ÉVÉNEMENT
  // =========================================================================

  group('StatutEvenement', () {
    test('codes serveur reconnus', () {
      expect(StatutEvenement.fromCode('reserve'), StatutEvenement.reserve);
      expect(StatutEvenement.fromCode('confirme'), StatutEvenement.confirme);
      expect(StatutEvenement.fromCode('en_cours'), StatutEvenement.enCours);
      expect(StatutEvenement.fromCode('termine'), StatutEvenement.termine);
      expect(StatutEvenement.fromCode('annule'), StatutEvenement.annule);
    });

    test('code inconnu ou vide → repli « réservé »', () {
      expect(StatutEvenement.fromCode(null), StatutEvenement.reserve);
      expect(StatutEvenement.fromCode(''), StatutEvenement.reserve);
      expect(StatutEvenement.fromCode('BIDON'), StatutEvenement.reserve);
    });

    test('occupeLaSalle : vrai pour réservé / confirmé / en cours', () {
      expect(StatutEvenement.reserve.occupeLaSalle, isTrue);
      expect(StatutEvenement.confirme.occupeLaSalle, isTrue);
      expect(StatutEvenement.enCours.occupeLaSalle, isTrue);
      expect(StatutEvenement.termine.occupeLaSalle, isFalse);
      expect(StatutEvenement.annule.occupeLaSalle, isFalse);
    });

    test('estClos : vrai pour terminé / annulé', () {
      expect(StatutEvenement.termine.estClos, isTrue);
      expect(StatutEvenement.annule.estClos, isTrue);
      expect(StatutEvenement.enCours.estClos, isFalse);
    });

    test('libellés français', () {
      expect(StatutEvenement.reserve.libelle, 'Réservé');
      expect(StatutEvenement.confirme.libelle, 'Confirmé');
      expect(StatutEvenement.enCours.libelle, 'En cours');
      expect(StatutEvenement.termine.libelle, 'Terminé');
      expect(StatutEvenement.annule.libelle, 'Annulé');
    });
  });

  // =========================================================================
  // 3. LE MODÈLE ÉVÉNEMENT (jointure + calculs)
  // =========================================================================

  group('Evenement', () {
    Map<String, dynamic> ligne({Map<String, dynamic>? extra}) {
      return <String, dynamic>{
        'id': 'evt-1',
        'salle_id': 'salle-1',
        'numero': 'EVT-20261012-0001',
        'titre': 'Mariage Kabeya',
        'type_evenement': 'mariage',
        'client_id': 7,
        'client_nom': 'Famille Kabeya',
        'telephone': '+243 970 000 000',
        'date_debut': '2026-10-12',
        'date_fin': '2026-10-13',
        'heure_debut': '14:00',
        'heure_fin': '23:00',
        'nb_invites': 180,
        'prix_jour': 150000.0,
        'montant_salle': 300000.0,
        'montant_total': 450000.0,
        'montant_paye': 100000.0,
        'statut': 'confirme',
        'note': 'Menu spécial',
        'salles': <String, dynamic>{'nom': 'Salle principale'},
        'lignes_evenement': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'lig-1',
            'libelle': 'Traiteur',
            'quantite': 150,
            'prix_unitaire': 1000.0,
            'total': 150000.0,
          },
          <String, dynamic>{
            'id': 'lig-2',
            'libelle': 'Décoration',
            'quantite': 1,
            'prix_unitaire': 0.0,
            'total': 0.0,
          },
        ],
        ...?extra,
      };
    }

    test('fromMap avec jointure salle + prestations', () {
      final Evenement evenement = Evenement.fromMap(ligne());

      expect(evenement.id, 'evt-1');
      expect(evenement.salleId, 'salle-1');
      expect(evenement.salleNom, 'Salle principale');
      expect(evenement.numero, 'EVT-20261012-0001');
      expect(evenement.titre, 'Mariage Kabeya');
      expect(evenement.typeEvenement, 'mariage');
      expect(evenement.clientId, 7);
      expect(evenement.clientNom, 'Famille Kabeya');
      expect(evenement.nbInvites, 180);
      expect(evenement.statut, StatutEvenement.confirme);
      expect(evenement.lignes, hasLength(2));
      expect(evenement.lignes.first.libelle, 'Traiteur');
      expect(evenement.lignes.first.total, 150000);
    });

    test('nbJours : bornes incluses (2 jours pour le 12→13)', () {
      expect(Evenement.fromMap(ligne()).nbJours, 2);
      expect(
        Evenement.fromMap(ligne(extra: <String, dynamic>{
          'date_fin': '2026-10-12',
        })).nbJours,
        1,
      );
    });

    test('solde & estSolde', () {
      final Evenement evenement = Evenement.fromMap(ligne());
      expect(evenement.solde, 350000);
      expect(evenement.estSolde, isFalse);

      final Evenement solde = Evenement.fromMap(ligne(extra: <String, dynamic>{
        'montant_paye': 450000.0,
      }));
      expect(solde.solde, 0);
      expect(solde.estSolde, isTrue);
    });

    test('le solde ne devient jamais négatif (surpaiement historique)', () {
      final Evenement evenement = Evenement.fromMap(ligne(extra: <String, dynamic>{
        'montant_paye': 500000.0,
      }));
      expect(evenement.solde, 0);
    });

    test('periode affichée (« 12/10/2026 → 13/10/2026 »)', () {
      expect(Evenement.fromMap(ligne()).periode, '12/10/2026 → 13/10/2026');
      expect(
        Evenement.fromMap(ligne(extra: <String, dynamic>{
          'date_fin': '2026-10-12',
        })).periode,
        '12/10/2026',
      );
    });

    test('enCoursAujourdhui couvre la période complète', () {
      final Evenement evenement = Evenement.fromMap(ligne());
      expect(evenement.enCoursAujourdhui(DateTime(2026, 10, 12)), isTrue);
      expect(evenement.enCoursAujourdhui(DateTime(2026, 10, 13, 23, 59)), isTrue);
      expect(evenement.enCoursAujourdhui(DateTime(2026, 10, 11)), isFalse);
      expect(evenement.enCoursAujourdhui(DateTime(2026, 10, 14)), isFalse);
    });

    test('resumePrestations liste les libellés', () {
      expect(
        Evenement.fromMap(ligne()).resumePrestations,
        'Traiteur, Décoration',
      );
      expect(
        Evenement.fromMap(ligne(extra: <String, dynamic>{
          'lignes_evenement': <Map<String, dynamic>>[],
        })).resumePrestations,
        'Aucune prestation',
      );
    });

    test('fromMap sans jointure garde des valeurs sûres', () {
      final Evenement evenement = Evenement.fromMap(<String, dynamic>{
        'id': 'x',
        'salle_id': 's',
        'titre': 'Réunion',
        'client_nom': 'Société X',
        'date_debut': '2026-11-01',
        'date_fin': '2026-11-01',
      });

      expect(evenement.salleNom, '');
      expect(evenement.statut, StatutEvenement.reserve);
      expect(evenement.nbJours, 1);
      expect(evenement.lignes, isEmpty);
    });

    test('copyWith ne change que les champs demandés', () {
      final Evenement evenement = Evenement.fromMap(ligne());
      final Evenement modifie = evenement.copyWith(
        statut: StatutEvenement.enCours,
        montantTotal: 600000,
      );

      expect(modifie.statut, StatutEvenement.enCours);
      expect(modifie.montantTotal, 600000);
      expect(modifie.titre, evenement.titre);
      expect(modifie.clientNom, evenement.clientNom);
    });

    test('dateCourte formate ou renvoie « — »', () {
      expect(Evenement.dateCourte(DateTime(2026, 1, 5)), '05/01/2026');
      expect(Evenement.dateCourte(null), '—');
    });
  });

  // =========================================================================
  // 4. LES PRESTATIONS
  // =========================================================================

  group('LigneEvenement', () {
    test('fromMap lit la prestation', () {
      final LigneEvenement ligne = LigneEvenement.fromMap(<String, dynamic>{
        'id': 'lig-9',
        'libelle': 'Sonorisation',
        'quantite': 2,
        'prix_unitaire': 75000.0,
        'total': 150000.0,
      });

      expect(ligne.id, 'lig-9');
      expect(ligne.libelle, 'Sonorisation');
      expect(ligne.quantite, 2);
      expect(ligne.prixUnitaire, 75000);
      expect(ligne.total, 150000);
    });
  });

  // =========================================================================
  // 5. LE TABLEAU DE BORD
  // =========================================================================

  group('TableauBordSalleFete', () {
    test('fromMap lit les compteurs et les prochains événements', () {
      final TableauBordSalleFete bord =
          TableauBordSalleFete.fromMap(<String, dynamic>{
        'ok': true,
        'salles': <String, dynamic>{'total': 3, 'actives': 2},
        'evenements_en_cours': 1,
        'evenements_a_venir': 4,
        'encaisse': 250000.0,
        'solde': 400000.0,
        'prochains': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'evt-1',
            'numero': 'EVT-20261012-0001',
            'titre': 'Mariage Kabeya',
            'salle': 'Salle principale',
            'client': 'Famille Kabeya',
            'date_debut': '12/10/2026',
            'date_fin': '13/10/2026',
            'statut': 'confirme',
            'montant_total': 450000.0,
            'solde': 350000.0,
          },
        ],
      });

      expect(bord.sallesTotal, 3);
      expect(bord.sallesActives, 2);
      expect(bord.evenementsEnCours, 1);
      expect(bord.evenementsAVenir, 4);
      expect(bord.encaisse, 250000);
      expect(bord.solde, 400000);
      expect(bord.prochains, hasLength(1));
      expect(bord.prochains.first.titre, 'Mariage Kabeya');
      expect(bord.prochains.first.salle, 'Salle principale');
      expect(bord.prochains.first.solde, 350000);
    });

    test('fromMap vide : tout à zéro, aucun prochain', () {
      final TableauBordSalleFete bord =
          TableauBordSalleFete.fromMap(const <String, dynamic>{});

      expect(bord.sallesTotal, 0);
      expect(bord.evenementsEnCours, 0);
      expect(bord.evenementsAVenir, 0);
      expect(bord.encaisse, 0);
      expect(bord.prochains, isEmpty);
    });
  });

  // =========================================================================
  // 6. LE FILTRE DE RECHERCHE (PUR)
  // =========================================================================

  group('SalleFeteService.filtrer', () {
    final List<Evenement> evenements = <Evenement>[
      Evenement(
        id: '1',
        salleId: 's1',
        salleNom: 'Terrasse',
        numero: 'EVT-1',
        titre: 'Mariage Kabeya',
        clientNom: 'Famille Kabeya',
        dateDebut: DateTime(2026, 10, 12),
        dateFin: DateTime(2026, 10, 12),
      ),
      Evenement(
        id: '2',
        salleId: 's2',
        salleNom: 'Salle principale',
        numero: 'EVT-2',
        titre: 'Anniversaire Ngoie',
        clientNom: 'Ngoie',
        dateDebut: DateTime(2026, 11, 2),
        dateFin: DateTime(2026, 11, 2),
      ),
    ];

    test('recherche vide : tout passe', () {
      expect(SalleFeteService.filtrer(evenements, ''), hasLength(2));
      expect(SalleFeteService.filtrer(evenements, '   '), hasLength(2));
    });

    test('recherche par titre (insensible à la casse)', () {
      final List<Evenement> resultats =
          SalleFeteService.filtrer(evenements, 'mariage');
      expect(resultats, hasLength(1));
      expect(resultats.first.id, '1');
    });

    test('recherche par client', () {
      expect(SalleFeteService.filtrer(evenements, 'ngoie'), hasLength(1));
    });

    test('recherche par salle', () {
      expect(SalleFeteService.filtrer(evenements, 'principale'), hasLength(1));
    });

    test('recherche par numéro', () {
      expect(SalleFeteService.filtrer(evenements, 'evt-2'), hasLength(1));
    });

    test('aucune correspondance : liste vide', () {
      expect(SalleFeteService.filtrer(evenements, 'zzz'), isEmpty);
    });
  });

  // =========================================================================
  // 7. MESSAGES D'ERREUR SERVEUR (« CODE|texte »)
  // =========================================================================

  group('SalleFeteService — messages d\'erreur', () {
    test('messageErreur extrait le texte après « CODE| »', () {
      expect(
        SalleFeteService.messageErreur(
            'SALLE_OCCUPEE|La salle « Terrasse » est déjà réservée.'),
        'La salle « Terrasse » est déjà réservée.',
      );
    });

    test('messageErreur garde le texte brut sans code', () {
      expect(SalleFeteService.messageErreur('Erreur simple'), 'Erreur simple');
      expect(SalleFeteService.messageErreur('CODE|'), 'CODE|');
    });

    test('typeDepuisMessage classe droits / validation / inconnu', () {
      expect(
        SalleFeteService.typeDepuisMessage('SESSION_ABSENTE|Connectez-vous.'),
        TypeErreurSalleFete.droits,
      );
      expect(
        SalleFeteService.typeDepuisMessage('SALLE_OCCUPEE|Déjà réservée.'),
        TypeErreurSalleFete.validation,
      );
      expect(
        SalleFeteService.typeDepuisMessage('DATES_INVALIDES|Dates.'),
        TypeErreurSalleFete.validation,
      );
      expect(
        SalleFeteService.typeDepuisMessage('PAIEMENTS_SUPERIEURS|Trop payé.'),
        TypeErreurSalleFete.validation,
      );
      expect(
        SalleFeteService.typeDepuisMessage('OBSCUR|Quelque chose.'),
        TypeErreurSalleFete.inconnu,
      );
    });
  });

  // =========================================================================
  // 8. CATALOGUE DES MODULES — les phases livrées ne sont plus « bientôt »
  // =========================================================================

  group('Catalogue des modules (phases C livrées)', () {
    test('les modules des phases C1→C4 sont marqués disponibles', () {
      for (final String code in <String>[
        ModuleCode.chambres,
        ModuleCode.reservations,
        ModuleCode.checkin,
        ModuleCode.tables,
        ModuleCode.commandes,
        ModuleCode.cuisine,
        ModuleCode.lotsExpiration,
        ModuleCode.salles,
        ModuleCode.evenements,
      ]) {
        final ModuleActivite? module = ModuleActivite.parCode(code);
        expect(module, isNotNull, reason: 'Module $code absent du catalogue');
        expect(module!.disponible, isTrue,
            reason: 'Le module $code est livré : plus de badge « bientôt »');
      }
    });

    test('les modules des phases suivantes (C5+) restent « bientôt »', () {
      for (final String code in <String>[
        ModuleCode.production,
        ModuleCode.pesee,
        ModuleCode.variantes,
      ]) {
        expect(ModuleActivite.parCode(code)!.disponible, isFalse,
            reason: 'Le module $code (phase suivante) reste à venir');
      }
    });
  });
}
