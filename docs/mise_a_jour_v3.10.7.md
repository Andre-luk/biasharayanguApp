# Mise à jour v3.10.7 (build 64) — correctif 180

**Date** : 21 novembre 2026
**Migration Supabase requise** : `20260916000180_coherence_metiers_par_espace.sql`
(à exécuter après la 0179).

## Le problème

Un compte qui possède **une boutique et un pressing** voyait sa **boutique se
comporter comme un pressing** : vente refusée (« VENTE_INTERDITE_PRESSING »),
menus Dépôts / Atelier / Retraits, collaborateurs affublés d'un métier de
pressing, et — après une bascule d'espace — les menus du pressing qui
restaient affichés.

## Ce qui a été corrigé

* **L'espace décide, plus l'entreprise.** Chaque décision (écrans, métiers,
  blocages) repose désormais sur le **type de l'espace de travail actif** :
  `espace_type`, `espace_est_pressing`, `mon_espace_actif`,
  `contexte_pressing`.
* **La garde de vente ne vise que l'espace qui vend** : une boutique du même
  groupe vend normalement, un pressing reste protégé.
* **Plus de métier pressing dans une boutique** : un trigger efface
  `role_pressing` dès que l'espace de travail n'est pas un pressing ;
  `pressing_role()` répond « aucun » hors pressing et les RPC du pressing
  refusent l'action (`PRESSING_INACTIF`).
* **Collaborateurs** : l'espace choisi (ou celui où le patron travaille)
  décide du métier ; plus d'affectation « au pressing par défaut ».
* **Écrans du pressing fermés** hors pressing, même par lien direct.
* **Bascule d'espace** : le profil de modules et le métier pressing sont
  rechargés immédiatement — plus besoin de redémarrer l'application.
* **Réparation des données** : espaces retypés par erreur au correctif 0153,
  métiers pressing invalides, personnel pressing sans espace de travail.

## Ce qui ne change pas

Les **chiffres** (tableau de bord, rapports) restent calculés sur
l'**entreprise entière** : c'est ce qui garantit qu'ils correspondent
partout (correctif 179). Ce correctif change les **écrans, les droits et les
blocages**, pas les totaux.

## Vérification

Après la migration, les contrôles finaux affichent :

* le tableau des espaces (type, ventes 30 j, est_pressing) ;
* les comptes portant un métier pressing — aucune incohérence attendue ;
* le contexte de la session courante ;
* la présence des deux triggers de cohérence.

Côté application : `dart analyze lib` sans erreur, `flutter test` vert (dont
8 nouveaux tests « une boutique n'est pas un pressing »).
