# Mise à jour v3.10.8 (build 65) — correctif 181

**Date** : 27 novembre 2026
**Migration Supabase requise** : `20260916000181_isolation_espace_equipe.sql`
(à exécuter après la 0180).

## Le problème

> « Les ventes de Urembo et de Hekima se percutent : quand Urembo vend
> 1 000 FC, Hekima affiche aussi 1 000 FC. »

Même propriétaire, mais **deux entreprises distinctes** : chacune affichait
les ventes de l'autre.

## La cause

Le correctif 179 a introduit `perimetre_entreprise()` — la liste des
identifiants qui « portent » les données d'une entreprise. Elle contenait
trois sources :

1. les **espaces** de l'entreprise ;
2. les **utilisateurs** de l'entreprise ;
3. ❌ **`entreprises.owner_id`** (l'UUID du patron).

Or les deux entreprises appartiennent au **même patron** : `owner_id` est donc
identique pour Urembo et Hekima. Et comme le **premier espace créé** à
l'inscription utilise l'UUID du patron comme identifiant, chaque entreprise
récupérait cet espace dans son périmètre — donc les mêmes ventes.

## La correction

1. **`perimetre_entreprise()` v2** : l'UUID du patron n'est ajouté **que si
   l'entreprise n'a aucun espace** (comptes d'avant le module 15). Dès qu'elle
   a des espaces, seuls ceux-ci (et ses utilisateurs) comptent.
2. **`entreprise_courante()` v2** : l'entreprise est celle de **l'espace de
   travail actif**, et non plus « la première par ordre alphabétique ».
3. **Réparation** des `espace_actif_id` incohérents (pointant vers un espace
   d'une autre entreprise) : ils faisaient écrire les ventes sous
   l'identifiant du patron, donc dans la mauvaise entreprise.
4. **Contrôles finaux** :
   - 4.a périmètres de deux entreprises d'un même patron → l'`intersection`
     doit être un tableau **vide** ;
   - 4.b ventes par espace sur 30 jours ;
   - 4.c ventes sans propriétaire identifiable (aucune ligne attendue) ;
   - 4.d entreprise et périmètre de la session courante.

## Ce qui est concerné

Tous les écrans qui comptent les ventes, car ils utilisent tous le même
périmètre :

| Écran | RPC |
|---|---|
| Tableau de bord (accueil) | `rpc_accueil_stats` |
| Rapport d'analyse (PDF) | `rpc_rapport_entreprise_analyse` |
| Stats par collaborateur | `rpc_rapport_vendeurs` |
| Écran Rapports | `rpc_finance_rapport` / `finance_stats_periode` |

## Vérification après la migration

```sql
-- Les périmètres ne se croisent plus : `intersection` doit être vide.
-- (requête 4.a de la migration)
```

Puis dans l'application, sur un compte à deux entreprises :

1. ouvrir **Urembo** → noter le total du jour ;
2. basculer sur **Hekima** → le total doit être **différent** (ou nul) ;
3. vendre 1 000 FC dans Urembo → seul le tableau de bord d'Urembo bouge ;
4. revenir sur Hekima → **aucun** changement.

## Note

Cette régression venait du correctif 179 (unification des périmètres). Le
principe reste le même — **un seul périmètre pour tous les écrans** — mais il
ne contient plus l'identifiant du propriétaire, qui appartient à toutes ses
entreprises à la fois.
