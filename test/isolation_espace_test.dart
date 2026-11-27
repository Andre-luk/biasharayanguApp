// test/isolation_espace_test.dart
//
// 🧩 CORRECTIF 0181 — priorité de la portée de travail.
//
// La RLS du serveur compare `owner_id` à `mon_proprietaire()` (l'ESPACE actif
// VÉRIFIÉ). Le client doit donc utiliser cette valeur en premier, et seulement
// à défaut l'espace simplement choisi (hors ligne / démarrage à froid).
// Ces tests verrouillent ce contrat, utilisé par `DBHelper`, la caisse hors
// ligne, la synchronisation et les écrans de statistiques.

import 'package:flutter_test/flutter_test.dart';

import 'package:biashara_yangu/services/scope_donnees.dart';

void main() {
  tearDown(ScopeDonnees.reinitialiser);

  group('ScopeDonnees — portée de travail', () {
    test('proprioPourEcriture : la valeur vérifiée par le serveur prime', () {
      ScopeDonnees.definirEspaceActif('espace-A');
      ScopeDonnees.definirProprietaireEffectif('espace-A');

      expect(ScopeDonnees.espaceActif, 'espace-A');
      expect(ScopeDonnees.proprietaireEffectif, 'espace-A');
      expect(ScopeDonnees.proprioPourEcriture, 'espace-A');
    });

    test('changer d\'entreprise invalide la valeur vérifiée', () {
      ScopeDonnees.definirEspaceActif('espace-A');
      ScopeDonnees.definirProprietaireEffectif('espace-A');

      ScopeDonnees.definirEspaceActif('espace-B');

      expect(ScopeDonnees.proprietaireEffectif, isNull,
          reason: 'la valeur de A ne doit jamais servir dans B');
      expect(ScopeDonnees.proprioPourEcriture, 'espace-B');
    });

    test('hors ligne : repli sur l\'espace choisi', () {
      ScopeDonnees.definirEspaceActif('espace-A');

      expect(ScopeDonnees.proprietaireEffectif, isNull);
      expect(ScopeDonnees.proprioPourEcriture, 'espace-A');
    });

    test('redefinir le MÊME espace conserve la valeur vérifiée', () {
      ScopeDonnees.definirEspaceActif('espace-A');
      ScopeDonnees.definirProprietaireEffectif('espace-A');

      ScopeDonnees.definirEspaceActif('espace-A');

      expect(ScopeDonnees.proprietaireEffectif, 'espace-A');
    });

    test('reinitialiser (déconnexion) efface tout', () {
      ScopeDonnees.definirEspaceActif('espace-A');
      ScopeDonnees.definirProprietaireEffectif('espace-A');

      ScopeDonnees.reinitialiser();

      expect(ScopeDonnees.estDefini, isFalse);
      expect(ScopeDonnees.espaceActif, isNull);
      expect(ScopeDonnees.proprietaireEffectif, isNull);
      expect(ScopeDonnees.proprioPourEcriture, isNull);
    });

    test('les valeurs vides ou blanches sont ignorées', () {
      ScopeDonnees.definirEspaceActif('  espace-A  ');
      ScopeDonnees.definirProprietaireEffectif('   ');

      expect(ScopeDonnees.espaceActif, 'espace-A');
      expect(ScopeDonnees.proprietaireEffectif, isNull);
      expect(ScopeDonnees.proprioPourEcriture, 'espace-A');
    });
  });
}
