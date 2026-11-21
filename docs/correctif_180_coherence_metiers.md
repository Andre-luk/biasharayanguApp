# Correctif 180 — Cohérence des métiers : chaque espace garde son type

**Version :** 3.10.7
**Migration :** `20260916000180_coherence_metiers_par_espace.sql`
**Date :** 21 novembre 2026

---

## 1. Le symptôme

> « Une boutique qui passe à la place de pressing. »

Dans un compte qui possède **une boutique ET un pressing**, la boutique se
comportait comme un pressing :

- elle **ne pouvait plus vendre** un article → « VENTE_INTERDITE_PRESSING » ;
- ses collaborateurs recevaient un **métier de pressing** (`caisse`,
  `atelier`…) et atterrissaient dans les écrans du pressing ;
- les menus **Dépôts / Atelier / Retraits** apparaissaient ;
- après une bascule pressing → boutique, les menus du pressing **restaient**
  jusqu'au redémarrage de l'application.

---

## 2. Les quatre causes

Toutes viennent d'une seule confusion :

> « **l'entreprise** fait du pressing » ≠ « **cet espace de travail** est un
> pressing ».

| N° | Cause | Effet |
|---|---|---|
| ① | **Migration 0153** : « TOUS les espaces du compte passent en `pressing` » | La boutique a été **retypée** en pressing |
| ② | **Migration 0177** : `trg_ventes_interdire_pressing` bloquait dès que **l'entreprise** possédait un pressing | La boutique du même groupe ne pouvait plus vendre |
| ③ | **Migration 0177** : `rpc_collaborateur_creer/_maj` déduisaient le métier de **l'entreprise** et affectaient par défaut **l'espace pressing** | Un vendeur de boutique devenait « caisse du pressing » |
| ④ | `pressing_role()` répondait le métier pressing même quand l'espace actif était une boutique | Menus et écrans du pressing visibles partout |

Côté application, deux défauts complétaient le tableau :

- `routeAutorisee()` laissait ouvrir `/main/pressing/...` à un propriétaire
  d'entreprise, **même hors pressing** (par lien direct) ;
- `EspaceService.basculer()` ne rechargeait **ni le profil de modules ni le
  métier pressing** : une boutique ouverte après un pressing gardait les menus
  du pressing.

---

## 3. Les correctifs

### 3.1 Un seul principe : l'ESPACE décide

| Nouvelle fonction | Réponse |
|---|---|
| `espace_type(espace)` | type normalisé (`boutique`, `pressing`, `pharmacie`…) |
| `espace_est_pressing(espace)` | **cet** espace est-il un pressing ? |
| `espace_utilise_pressing(espace)` | type pressing **ou** profil de modules contenant les dépôts |
| `mon_espace_actif()` | l'espace de travail réel de l'utilisateur (jamais l'entreprise) |
| `contexte_pressing()` | `{actif, role, espace_id, espace_type, entreprise_id}` |

`contexte_pressing()` est la **seule** source de vérité : hors d'un espace
pressing, `actif = false` et `role = "aucun"`.

### 3.2 Le pressing ne déborde plus de son espace

- `pressing_role()` → `contexte_pressing()->>'role'` : un `role_pressing`
  périmé ne donne plus accès aux écrans du pressing ;
- `pressing_exige()` → refuse par `PRESSING_INACTIF` si l'espace de travail
  n'est pas un pressing (l'espace inconnu reste toléré : on n'enferme
  personne) ;
- `pressing_entreprise()` → entreprise de l'espace de travail.

### 3.3 La garde de vente ne vise que l'espace qui vend

```sql
-- Avant : toute l'entreprise était bloquée
if entreprise_est_pressing(entreprise) then raise ... end if;

-- Après : seul un espace pressing est bloqué
if espace_est_pressing(espace_de_la_vente) then raise ... end if;
```

Une boutique du même groupe vend normalement ; un pressing continue d'être
protégé (RPC et INSERT directs compris).

### 3.4 Cohérence permanente (triggers)

| Trigger | Règle |
|---|---|
| `trg_utilisateurs_metier_pressing` | un compte dont l'espace n'est pas un pressing **ne peut pas** garder un métier pressing (`role_pressing` effacé) |
| `trg_ventes_interdire_pressing` | refuse une vente seulement dans un **espace** pressing |

### 3.5 Réparation des données

1. métiers pressing invalides **effacés** ;
2. personnel pressing sans espace de travail **replacé** dans le pressing ;
3. espaces mal typés par 0153 : quand un compte a **exactement deux** espaces
   « pressing » et qu'**un seul** enregistre réellement des ventes d'articles,
   cet espace redevient une **boutique** (règle volontairement étroite, avec
   un `NOTICE` par changement).

### 3.6 Création / modification de collaborateur

Ordre de résolution de l'espace :

1. l'espace **demandé** ;
2. sinon **l'espace où le patron travaille** en ce moment ;
3. sinon l'espace par défaut de son entreprise.

**Plus jamais « le pressing par défaut ».** Le métier pressing n'est attribué
que si l'espace retenu est un pressing.

### 3.7 Application

- `routeAutorisee()` : `/main/pressing/...` est **fermé** quand le contexte
  pressing est inactif (même par lien direct) ;
- `EspaceService.basculer()` : réinitialise puis **recharge le profil de
  modules** et le type d'activité → le métier suit l'espace ;
- `scaffold_with_nav_bar` : réécoute le changement d'espace pour **relire le
  rôle pressing** au serveur.

---

## 4. Vérification

La migration termine par quatre contrôles :

| Contrôle | Attendu |
|---|---|
| 6.a Tableau des espaces (type, ventes 30 j, `est_pressing`) | chaque espace porte son vrai type |
| 6.b Comptes avec métier pressing | **aucune** ligne avec `est_pressing = false` |
| 6.c Contexte de la session | `actif` correspond à l'espace choisi |
| 6.d Triggers | les deux triggers sont présents |

Dans l'application :

1. Espace **boutique** : vente possible, aucun menu Dépôts / Atelier /
   Retraits, `.../#/main/pressing/atelier` refusé.
2. Espace **pressing** : dépôts, atelier, retraits, équipe selon le métier ;
   la vente d'articles est refusée avec un message clair.
3. Basculer pressing → boutique : les menus changent **immédiatement**.
4. `Mon Équipe` : créer un collaborateur dans une boutique ne lui donne
   **aucun** métier pressing.

---

## 5. Ce qui ne change pas

- **Les chiffres** restent ceux de l'**entreprise** (tous ses espaces), pour
  que le tableau de bord et le rapport du patron continuent de correspondre
  exactement (correctif 179). Le rapport d'analyse distingue les sources
  (`sources.boutique`, `sources.pressing`).
- Ce correctif change les **écrans, les droits et les blocages**, pas les
  totaux.

---

## 6. Fichiers touchés

| Fichier | Nature |
|---|---|
| `supabase/migrations/20260916000180_…sql` | **nouvelle migration** |
| `lib/services/permission_service.dart` | écrans pressing fermés hors pressing |
| `lib/services/espace_service.dart` | bascule : modules + type d'activité rechargés |
| `lib/pages/scaffold_with_nav_bar.dart` | métier pressing relu à chaque bascule |
| `test/coherence_metiers_test.dart` | **nouveau** — 8 tests |
| `test/pressing_permissions_test.dart` | contexte pressing déclaré dans les tests de routes |
