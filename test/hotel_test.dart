// test/hotel_test.dart
//
// 🏨 MODULE 16 (phase C2) — Tests PURS du module hôtel : modèles chambre /
// réservation, facture de séjour, tableau de bord et messages d'erreur.
// Aucun réseau, aucun widget.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/chambre.dart';
import 'package:biashara_yangu/models/hotel_tableau_bord.dart';
import 'package:biashara_yangu/models/reservation.dart';
import 'package:biashara_yangu/services/hotel_service.dart';

void main() {
  // =========================================================================
  // 1. CHAMBRES
  // =========================================================================

  group('ChambreStatut', () {
    test('fromCode accepte les codes serveur et retombe sur libre', () {
      expect(ChambreStatut.fromCode('libre'), ChambreStatut.libre);
      expect(ChambreStatut.fromCode('reservee'), ChambreStatut.reservee);
      expect(ChambreStatut.fromCode('occupee'), ChambreStatut.occupee);
      expect(ChambreStatut.fromCode('a_nettoyer'), ChambreStatut.aNettoyer);
      expect(ChambreStatut.fromCode('  OCCUPEE '), ChambreStatut.occupee);
      expect(ChambreStatut.fromCode(null), ChambreStatut.libre);
      expect(ChambreStatut.fromCode('inconnu'), ChambreStatut.libre);
    });
  });

  group('Chambre', () {
    test('fromMap lit tous les champs', () {
      final Chambre chambre = Chambre.fromMap(<String, dynamic>{
        'id': 'chambre-1',
        'numero': '101',
        'type_chambre': 'Double',
        'capacite': 2,
        'prix_nuit': 25000,
        'statut': 'reservee',
        'equipements': 'Climatisation, balcon',
        'actif': true,
        'owner_id': 'patron-1',
      });

      expect(chambre.id, 'chambre-1');
      expect(chambre.numero, '101');
      expect(chambre.typeChambre, 'Double');
      expect(chambre.capacite, 2);
      expect(chambre.prixNuit, 25000);
      expect(chambre.statut, ChambreStatut.reservee);
      expect(chambre.equipements, 'Climatisation, balcon');
      expect(chambre.actif, isTrue);
      expect(chambre.designation, 'Chambre 101 — Double');
      expect(chambre.disponible, isFalse);
    });

    test('designation simple sans type, disponible seulement si libre+active',
        () {
      const Chambre nue = Chambre(id: 'c', numero: '7');
      expect(nue.designation, 'Chambre 7');
      expect(nue.disponible, isTrue);

      final Chambre occupee = nue.copyWith(statut: ChambreStatut.occupee);
      expect(occupee.disponible, isFalse);

      final Chambre inactive = nue.copyWith(actif: false);
      expect(inactive.disponible, isFalse);
    });
  });

  // =========================================================================
  // 2. RÉSERVATIONS
  // =========================================================================

  group('StatutReservation', () {
    test('fromCode, estActive', () {
      expect(StatutReservation.fromCode('reservee'),
          StatutReservation.reservee);
      expect(StatutReservation.fromCode('en_cours'),
          StatutReservation.enCours);
      expect(StatutReservation.fromCode('terminee'),
          StatutReservation.terminee);
      expect(StatutReservation.fromCode('annulee'),
          StatutReservation.annulee);
      expect(StatutReservation.fromCode(null), StatutReservation.reservee);

      expect(StatutReservation.reservee.estActive, isTrue);
      expect(StatutReservation.enCours.estActive, isTrue);
      expect(StatutReservation.terminee.estActive, isFalse);
      expect(StatutReservation.annulee.estActive, isFalse);
    });
  });

  group('Reservation', () {
    Map<String, dynamic> ligne([String statut = 'reservee']) {
      return <String, dynamic>{
        'id': 'resa-1',
        'chambre_id': 'chambre-1',
        'chambres': <String, dynamic>{'numero': '101', 'type_chambre': 'Double'},
        'client_id': 12,
        'client_nom': 'M. Kabila',
        'clients': <String, dynamic>{'nom': 'M. Kabila', 'telephone': '+243 800'},
        'date_arrivee': '2026-10-01',
        'date_depart': '2026-10-05',
        'nb_personnes': 2,
        'prix_nuit': 25000,
        'montant_total': 100000,
        'montant_paye': 40000,
        'statut': statut,
      };
    }

    test('fromMap avec jointures chambre et client', () {
      final Reservation reservation = Reservation.fromMap(ligne());

      expect(reservation.id, 'resa-1');
      expect(reservation.chambreNumero, '101');
      expect(reservation.clientId, 12);
      expect(reservation.clientNom, 'M. Kabila');
      expect(reservation.clientTelephone, '+243 800');
      expect(reservation.nuits, 4);
      expect(reservation.montantTotal, 100000);
      expect(reservation.montantPaye, 40000);
      expect(reservation.solde, 60000);
      expect(reservation.estActive, isTrue);
    });

    test('solde jamais négatif (surpaiement toléré côté affichage)', () {
      final Map<String, dynamic> map = ligne('en_cours')
        ..['montant_paye'] = 120000;
      expect(Reservation.fromMap(map).solde, 0);
    });

    test('enRetard : arrivée passée et encore en attente', () {
      final DateTime hier = DateTime.now().subtract(const Duration(days: 1));
      final DateTime demain = DateTime.now().add(const Duration(days: 1));

      final Reservation retard = Reservation(
        id: 'r',
        chambreId: 'c',
        clientNom: 'Client',
        dateArrivee: hier,
        dateDepart: demain,
      );
      expect(retard.enRetard, isTrue);

      // Une fois le client arrivé, plus de badge « en retard ».
      final Reservation arrive = retard.copyWith(
        statut: StatutReservation.enCours,
      );
      expect(arrive.enRetard, isFalse);
    });
  });

  group('FactureSejour', () {
    test('référence, ligne nuits × prix et soldes', () {
      final Reservation reservation = Reservation(
        id: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        chambreId: 'chambre-1',
        chambreNumero: '101',
        clientNom: 'M. Kabila',
        dateArrivee: DateTime(2026, 10, 1),
        dateDepart: DateTime(2026, 10, 5),
        prixNuit: 25000,
        montantTotal: 100000,
        montantPaye: 40000,
      );

      final FactureSejour facture = FactureSejour.depuisReservation(reservation);

      expect(facture.reference, 'SÉJ-3FA85F64');
      expect(facture.lignes, hasLength(1));
      expect(facture.lignes.first.libelle, '4 nuits × 25000');
      expect(facture.lignes.first.montant, 100000);
      expect(facture.total, 100000);
      expect(facture.paye, 40000);
      expect(facture.solde, 60000);
    });

    test('singulier « 1 nuit »', () {
      final Reservation reservation = Reservation(
        id: 'abcdef12',
        chambreId: 'c',
        clientNom: 'Client',
        dateArrivee: DateTime(2026, 10, 1),
        dateDepart: DateTime(2026, 10, 2),
        prixNuit: 30000,
        montantTotal: 30000,
      );

      expect(FactureSejour.depuisReservation(reservation).lignes.first.libelle,
          '1 nuit × 30000');
      expect(
          FactureSejour.depuisReservation(reservation).reference, 'SÉJ-ABCDEF12');
    });
  });

  // =========================================================================
  // 3. TABLEAU DE BORD
  // =========================================================================

  group('TableauBordHotel', () {
    test('fromMap lit l\'occupation et les listes du jour', () {
      final TableauBordHotel bord = TableauBordHotel.fromMap(<String, dynamic>{
        'ok': true,
        'chambres': <String, dynamic>{
          'total': 12,
          'libres': 5,
          'reservees': 2,
          'occupees': 4,
          'a_nettoyer': 1,
        },
        'occupation': 33.3,
        'reservations_actives': 6,
        'arrivees_count': 2,
        'departs_count': 1,
        'arrivees': <dynamic>[
          <String, dynamic>{
            'id': 'resa-1',
            'chambre': '101',
            'client': 'M. Kabila',
            'date_arrivee': '01/10/2026',
            'date_depart': '05/10/2026',
            'nb_personnes': 2,
            'montant_total': 100000,
            'montant_paye': 40000,
            'solde': 60000,
            'retard': true,
          },
        ],
        'departs': <dynamic>[],
      });

      expect(bord.total, 12);
      expect(bord.libres, 5);
      expect(bord.reservees, 2);
      expect(bord.occupees, 4);
      expect(bord.aNettoyer, 1);
      expect(bord.occupation, 33.3);
      expect(bord.reservationsActives, 6);
      expect(bord.arriveesCount, 2);
      expect(bord.departsCount, 1);
      expect(bord.arrivees, hasLength(1));
      expect(bord.arrivees.first.chambre, '101');
      expect(bord.arrivees.first.solde, 60000);
      expect(bord.arrivees.first.retard, isTrue);
      expect(bord.departs, isEmpty);
    });

    test('fromMap tolère une réponse vide', () {
      final TableauBordHotel bord =
          TableauBordHotel.fromMap(const <String, dynamic>{});

      expect(bord.total, 0);
      expect(bord.arrivees, isEmpty);
      expect(bord.departs, isEmpty);
    });
  });

  // =========================================================================
  // 4. ERREURS SERVEUR & OPTIONS CLIENT
  // =========================================================================

  group('HotelService — messages d\'erreur', () {
    test('messageErreur extrait le texte après « CODE| »', () {
      expect(
        HotelService.messageErreur(
            'CHAMBRE_OCCUPEE|La chambre 101 est déjà réservée sur cette période.'),
        'La chambre 101 est déjà réservée sur cette période.',
      );
      expect(HotelService.messageErreur('STOCK_INSUFFISANT'),
          'STOCK_INSUFFISANT');
    });

    test('typeDepuisMessage classe droits / validation / inconnu', () {
      expect(HotelService.typeDepuisMessage('DROIT_REFUSE|…'),
          TypeErreurHotel.droits);
      expect(HotelService.typeDepuisMessage('HORS_BOUTIQUE|…'),
          TypeErreurHotel.droits);
      expect(HotelService.typeDepuisMessage('SEJOUR_EN_COURS|…'),
          TypeErreurHotel.validation);
      expect(HotelService.typeDepuisMessage('DATES_INVALIDES|…'),
          TypeErreurHotel.validation);
      expect(HotelService.typeDepuisMessage('BANG|…'),
          TypeErreurHotel.inconnu);
    });
  });

  group('ClientHotelOption', () {
    test('depuisRpc', () {
      final ClientHotelOption client =
          ClientHotelOption.depuisRpc(<String, dynamic>{
        'id': 7,
        'nom': 'Mme Tshala',
        'telephone': '+243 810',
      });

      expect(client.id, 7);
      expect(client.nom, 'Mme Tshala');
      expect(client.telephone, '+243 810');
    });
  });
}
