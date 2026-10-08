// test/abonnement_modules_test.dart
//
// 🧩 CORRECTIF 65 — FONCTIONNALITÉS SELON L'ABONNEMENT.
//
// Vérifient SANS réseau :
//   • la règle d'abonnement, et surtout sa règle d'or : FAIL-OPEN ;
//   • le joker `*` (niveau le plus élevé) ;
//   • le CROISEMENT activité × abonnement : un écran doit avoir du sens ET
//     être payé ;
//   • le cas qui compte le plus : une panne ou une migration absente ne doit
//     JAMAIS masquer un écran à un commerçant dont l'abonnement est en règle.
//
//     flutter test test/abonnement_modules_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/services/modules_service.dart';

/// Le croisement EXACT appliqué par `ModulesService.moduleActif`, écrit ici
/// sous forme pure pour être testable sans session ni réseau.
bool actif(
  Set<String> activite,
  bool chargeActivite,
  Set<String> abonnement,
  bool chargeAbonnement,
  String code,
) {
  return ModulesService.estActif(activite, chargeActivite, code) &&
      ModulesService.estAutoriseParAbonnement(abonnement, chargeAbonnement, code);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String ventes = ModuleCode.ventes;
  const String chambres = ModuleCode.chambres;

  // =======================================================================
  // 1. LA RÈGLE D'ABONNEMENT, SEULE
  // =======================================================================

  group('ReglesAbonnement — la règle d\'or est le fail-open', () {
    test('liste NON CHARGÉE → tout est ouvert', () {
      expect(
        ReglesAbonnement.autorise(const <String>{}, false, <String>{ventes}),
        isTrue,
      );
    });

    test('liste VIDE → tout est ouvert', () {
      expect(
        ReglesAbonnement.autorise(const <String>{}, true, <String>{ventes}),
        isTrue,
      );
    });

    test('joker « * » → tout est ouvert, y compris l\'inconnu', () {
      const Set<String> premium = <String>{ReglesAbonnement.joker};
      expect(
        ReglesAbonnement.autorise(premium, true, <String>{ventes}),
        isTrue,
      );
      expect(
        ReglesAbonnement.autorise(premium, true, <String>{'module_du_futur'}),
        isTrue,
      );
    });

    test('fonctionnalité PRÉSENTE → ouverte', () {
      expect(
        ReglesAbonnement.autorise(
            const <String>{ventes, 'produits'}, true, <String>{ventes}),
        isTrue,
      );
    });

    test('fonctionnalité ABSENTE → masquée (c\'est le but)', () {
      expect(
        ReglesAbonnement.autorise(
            const <String>{ventes, 'produits'}, true, <String>{chambres}),
        isFalse,
      );
    });

    test('au moins UNE des fonctionnalités demandées suffit', () {
      expect(
        ReglesAbonnement.autorise(
          const <String>{ventes},
          true,
          <String>{chambres, ventes},
        ),
        isTrue,
      );
    });
  });

  // =======================================================================
  // 2. LE CROISEMENT ACTIVITÉ × ABONNEMENT
  // =======================================================================

  group('Croisement — il faut du SENS (activité) ET du PAYÉ (abonnement)', () {
    test('activité OUI + abonnement OUI → l\'écran est visible', () {
      expect(actif(<String>{ventes}, true, <String>{ventes}, true, ventes),
          isTrue);
    });

    test('activité OUI + abonnement NON → masqué (fonctionnalité non payée)',
        () {
      expect(
        actif(<String>{ventes}, true, <String>{'produits'}, true, ventes),
        isFalse,
      );
    });

    test('activité NON → masqué, même si l\'abonnement l\'ouvre', () {
      //  Une pharmacie « Premium » ne doit JAMAIS voir les chambres : le
      //  croisement ne peut pas RÉVÉLER un écran hors sujet.
      //
      //  ⚠️ NUANCE IMPORTANTE : une liste VIDE n'est pas « tout exclure » —
      //  c'est « aucune restriction » (fail-open). Pour dire « cette activité
      //  n'utilise pas les chambres », il faut une liste NON VIDE
      //  (`ventes`, `produits`…) qui ne contient pas `chambres`.
      expect(
        actif(
          const <String>{ventes, ModuleCode.produits},
          true,
          const <String>{chambres},
          true,
          chambres,
        ),
        isFalse,
      );
    });

    test('abonnement NON CHARGÉ → l\'activité seule décide (fail-open)', () {
      expect(actif(<String>{ventes}, true, const <String>{}, false, ventes),
          isTrue);
      expect(
        actif(const <String>{chambres}, true, const <String>{}, false, ventes),
        isFalse,
      );
    });

    test('RIEN n\'est chargé → tout reste visible (zéro régression)', () {
      //  C'est LE cas qui protège : hors ligne, au démarrage, ou avant la
      //  migration, un commerçant qui paie ne perd aucun écran.
      expect(
        actif(const <String>{}, false, const <String>{}, false, ventes),
        isTrue,
      );
      expect(
        actif(const <String>{}, false, const <String>{}, false, chambres),
        isTrue,
      );
    });

    test('une liste d\'activité VIDE n\'exclut rien (fail-open)', () {
      //  Distinction essentielle, et source de bugs si on la confond :
      //    • liste vide      = « aucune restriction » → tout est visible ;
      //    • liste non vide  = « voici les fonctionnalités » → le reste est
      //      masqué.
      expect(actif(const <String>{}, true, const <String>{}, true, ventes),
          isTrue);
      expect(
        actif(<String>{ModuleCode.produits}, true, const <String>{}, true,
            ventes),
        isFalse,
      );
    });

    test('niveau Premium (joker) → l\'abonnement ne masque jamais rien', () {
      const Set<String> premium = <String>{ReglesAbonnement.joker};
      expect(actif(<String>{ventes}, true, premium, true, ventes), isTrue);
      expect(actif(<String>{chambres}, true, premium, true, chambres), isTrue);
    });

    test('niveau Essentiel → les fonctions non incluses sont masquées', () {
      const Set<String> essentiel = <String>{
        ModuleCode.ventes,
        ModuleCode.produits,
        ModuleCode.stock,
        ModuleCode.caisse,
        ModuleCode.clients,
        ModuleCode.rapports,
      };

      //  Payé dans l'Essentiel :
      expect(actif(essentiel, true, essentiel, true, ModuleCode.ventes),
          isTrue);
      //  Réservé au Pro :
      expect(
        actif(<String>{ModuleCode.finance}, true, essentiel, true,
            ModuleCode.finance),
        isFalse,
      );
      expect(
        actif(<String>{ModuleCode.assistantIa}, true, essentiel, true,
            ModuleCode.assistantIa),
        isFalse,
      );
    });
  });
}
