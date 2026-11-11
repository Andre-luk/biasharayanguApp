// test/pressing_equipe_test.dart
//
// MODULE 35 — LES MÉTIERS DU PRESSING.
//
// Ces tests verrouillent la règle qui compte : chaque métier ouvre des droits
// DIFFÉRENTS. Si un jour quelqu'un « simplifie » ces getters, un agent d'atelier
// pourrait changer les tarifs ou un caissier faire avancer un vêtement — et
// c'est exactement ce que le module doit empêcher.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/pressing_equipe.dart';

void main() {
  group('RolePressing — les codes envoyés au serveur', () {
    test('les quatre métiers et leurs codes sont stables', () {
      expect(
        RolePressing.tous.map((RolePressing r) => r.code).toList(),
        <String>['responsable', 'accueil', 'atelier', 'caisse'],
      );
    });

    test('chaque métier a un libellé et une explication', () {
      for (final RolePressing role in RolePressing.tous) {
        expect(role.libelle.trim(), isNotEmpty, reason: role.code);
        expect(role.explication.trim(), isNotEmpty, reason: role.code);
      }
    });

    test('depuisCode tolère la casse, les espaces et l\'inconnu', () {
      expect(RolePressing.depuisCode('atelier'), RolePressing.atelier);
      expect(RolePressing.depuisCode('  CAISSE  '), RolePressing.caisse);
      expect(RolePressing.depuisCode('proprietaire'), isNull);
      expect(RolePressing.depuisCode(''), isNull);
      expect(RolePressing.depuisCode(null), isNull);
    });
  });

  group('RolePressing — ce que chaque métier peut faire', () {
    test('le responsable peut tout', () {
      const RolePressing r = RolePressing.responsable;
      expect(r.peutRegler, isTrue);
      expect(r.peutAccueillir, isTrue);
      expect(r.peutAtelier, isTrue);
      expect(r.peutEncaisser, isTrue);
    });

    test('l\'accueil reçoit et encaisse, mais ne régle ni ne traite', () {
      const RolePressing r = RolePressing.accueil;
      expect(r.peutAccueillir, isTrue);
      expect(r.peutEncaisser, isTrue);
      expect(r.peutRegler, isFalse);
      expect(r.peutAtelier, isFalse);
    });

    test('l\'atelier traite les vêtements, sans toucher au prix ni à l\'argent',
        () {
      const RolePressing r = RolePressing.atelier;
      expect(r.peutAtelier, isTrue);
      expect(r.peutRegler, isFalse);
      expect(r.peutAccueillir, isFalse);
      expect(r.peutEncaisser, isFalse);
    });

    test('la caisse encaisse et remet, sans régler ni traiter', () {
      const RolePressing r = RolePressing.caisse;
      expect(r.peutEncaisser, isTrue);
      expect(r.peutRegler, isFalse);
      expect(r.peutAtelier, isFalse);
      expect(r.peutAccueillir, isFalse);
    });
  });

  group('CollaborateurPressing', () {
    test('lit la réponse du serveur', () {
      final CollaborateurPressing c =
          CollaborateurPressing.fromMap(<String, dynamic>{
        'id': 'u1',
        'nom': 'Kabila',
        'prenom': 'Marie',
        'email': 'marie@press.cd',
        'telephone': '0990000000',
        'role': 'atelier',
        'actif': true,
      });

      expect(c.id, 'u1');
      expect(c.nomComplet, 'Marie Kabila');
      expect(c.initiales, 'KM');
      expect(c.role, RolePressing.atelier);
      expect(c.actif, isTrue);
    });

    test('un compte sans métier reste lisible', () {
      final CollaborateurPressing c =
          CollaborateurPressing.fromMap(<String, dynamic>{'id': 'u2'});
      expect(c.role, isNull);
      expect(c.actif, isTrue);
      expect(c.nomComplet, '');
      expect(c.initiales, '?');
    });

    test('nomComplet ne laisse pas d\'espace parasite', () {
      const CollaborateurPressing c = CollaborateurPressing(
        id: 'u3',
        nom: 'Mukendi',
      );
      expect(c.nomComplet, 'Mukendi');
    });
  });

  group('EquipePressing', () {
    test('lit le métier courant et la liste', () {
      final EquipePressing e =
          EquipePressing.fromRpc(<String, dynamic>{
        'role': 'caisse',
        'lignes': <dynamic>[
          <String, dynamic>{
            'id': 'u1',
            'nom': 'Ilunga',
            'prenom': 'Paul',
            'role': 'accueil',
            'actif': true,
          },
        ],
      });

      expect(e.roleCourant, RolePressing.caisse);
      expect(e.collaborateurs, hasLength(1));
      expect(e.estVide, isFalse);
      expect(e.collaborateurs.first.nomComplet, 'Paul Ilunga');
    });

    test('le patron n\'a pas de métier : roleCourant reste null', () {
      final EquipePressing e =
          EquipePressing.fromRpc(<String, dynamic>{'role': 'proprietaire'});
      expect(e.roleCourant, isNull);
      expect(e.estVide, isTrue);
    });
  });
}
