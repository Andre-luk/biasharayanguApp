# Mise à jour v3.10.4 (build 61)

**Date** : 20 novembre 2026

## Collaborateurs du pressing

* Les écrans accessibles suivent le métier attribué : accueil, atelier, caisse ou responsable.
* Vente boutique, scanner, panier, pesée, stock et caisse boutique ne sont pas proposés dans un pressing, même si un ancien profil de modules les expose encore.
* Les routes directes sont protégées ; une garde Supabase refuse aussi les insertions de ventes boutique dans un pressing.
* Les anciens collaborateurs pressing sans métier reçoivent un rôle restreint depuis leur rôle d'entreprise.

## Rapports, QR codes et gestion

* Le rapport hebdomadaire/mensuel lit aussi les prestations des pressings, ne crée plus de table temporaire et classe tous les produits/prestations par chiffre d'affaires.
* Les champs historiques `REAL` sont convertis en `NUMERIC` dans le calcul du rapport.
* Le tableau QR distingue les codes existants (un par article et emballage) des émissions facturées, avec répartition par boutique.
* Suppression de collaborateur corrigée avec confirmation écrite et conservation des historiques métier.
* Le guide complet de pharmacie est disponible en PDF dans les fichiers de la release.

## Migration Supabase requise

Exécuter les migrations dans l'ordre : **0174 → 0175 → 0176 → 0177**. La 0177 contient la correction de rapport `REAL → NUMERIC`, l'isolation des droits pressing et la garde serveur contre les ventes boutique dans un pressing.

## Vérification

* `flutter analyze lib` : aucune erreur.
* `flutter test` : 1 514 tests réussis.
* Migration 0177 : vérification syntaxique SQL 57/57.
