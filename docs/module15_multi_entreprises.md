# Module 15 — PACK AVANCÉ MULTI-ENTREPRISES

> ✅ **IMPLÉMENTÉ (18/09/2026)** — migration
> `20260916000019_module15_multi_entreprises.sql` (45 instructions validées)
> + code application (modèles, `EspaceService`, sélecteur, écran
> « Mes entreprises ») + tests.
>
> **Pour l'activer** : exécuter la migration 19 dans Supabase, puis créer un
> groupe tarifaire « Pack Avancé » dans **Admin → Référentiels → Groupes
> tarifaires** avec **« Entreprises autorisées (pack) » = 3** (ou plus), et
> l'affecter aux clients concernés depuis la fiche entreprise.
>
> **Ce qui est livré** :
> - `groupes_tarifaires.max_espaces` (1 par défaut) — champ ajouté au
>   formulaire des groupes tarifaires ;
> - table `espaces` (boutique / hôtel / pharmacie / restaurant / dépôt /
>   autre), le **sélecteur d'entreprise** dans la barre supérieure, l'écran
>   **« Mes entreprises »** (liste, création, bascule, quota du pack) ;
> - `mon_proprietaire()` redéfini : l'espace actif cloisonne TOUTES les
>   données, avec repli historique (aucune donnée existante touchée) ;
> - RPC : `rpc_espaces_lister`, `rpc_espace_basculer`, `rpc_espace_creer`
>   (+ `rpc_entreprise_creer` v4 qui crée l'espace par défaut) ;
> - journal d'audit : `ESPACE_CREE`, `ESPACE_BASCULE`.
>
> **Choix V1 (à faire évoluer si besoin)** : tous les membres de l'entreprise
> voient tous les espaces ; les quotas IA restent **par espace** ; pas encore
> de renommage/désactivation d'espace.

## 1. Pourquoi ce n'est pas un simple ajout de champ

Dans l'architecture actuelle (Modules 1 à 14) :

| Élément | Rôle aujourd'hui |
|---|---|
| `public.entreprises` | Le **compte client / abonnement** (statut, montants, dates, grille tarifaire). |
| `entreprise_id` dans les tables métier (ventes, stock, clients…) | L'**espace de travail** du patron : `mon_proprietaire()` = `coalesce(parent_id, id)` de l'utilisateur — c'est-à-dire l'UUID du **patron**, pas la ligne `entreprises`. |
| `utilisateurs.entreprise_id` | Le lien vers la ligne `entreprises` (l'abonnement) — sémantique **différente** de la colonne précédente (piège documenté, corrigé au Module 13/17). |
| Collaborateurs | `parent_id` → patron ⇒ ils partagent l'espace de données du patron. |

Conclusion : aujourd'hui **1 patron = 1 espace de données = 1 commerce**.
Gérer boutique + hôtel + pharmacie avec un seul compte exige d'introduire
la notion d'**espaces** (points de vente) et de rendre l'espace actif
variable.

## 2. Approche proposée (compatible avec les données existantes)

### 2.1 Idée clé — ne PAS migrer les données métier

L'espace par défaut de chaque patron existant reçoit **exactement l'UUID du
patron**, qui est déjà la valeur stockée dans toutes les tables métier
(ventes, stock, dettes…). Résultat : **aucune table métier n'est réécrite**.
Seule la fonction de résolution d'espace est redéfinie :

```sql
-- Le cœur du système : tout le code existant appelle déjà mon_proprietaire().
create or replace function public.mon_proprietaire() returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(
    -- 1. L'espace actif choisi (nouveau — switcher d'entreprise) ;
    (select u.espace_actif_id from public.utilisateurs u where u.id = auth.uid()),
    -- 2. Repli historique : l'UUID du patron (comportement identique à avant).
    (select coalesce(u.parent_id, u.id) from public.utilisateurs u where u.id = auth.uid())
  );
$$;
```

Comme **toutes** les politiques RLS et RPC appellent déjà `mon_proprietaire()`,
redéfinir son corps suffit : le comportement actuel est strictement conservé
(fallback identique), et le multi-entreprise s'active quand `espace_actif_id`
pointe vers un second espace.

### 2.2 Nouvelles structures

```
espaces                          -- points de vente d'un compte client
  id uuid pk                     -- espace par défaut = UUID du patron (compatibilité)
  entreprise_id uuid fk → entreprises(id)   -- l'abonnement payeur
  nom text                       -- « Boutique Étoile », « Hôtel Royal »…
  type text                      -- boutique / hotel / pharmacie / autre
  ville_id uuid, actif boolean, created_at

utilisateurs.espace_actif_id uuid  -- espace courant de la session (switcher)
utilisateurs_espaces (user_id, espace_id) -- accès par collaborateur (optionnel)
```

### 2.3 Nouvelles RPC

| RPC | Rôles | Rôle |
|---|---|---|
| `rpc_espaces_lister()` | membres | Espaces accessibles (+ espace actif). |
| `rpc_espace_creer(nom, type, ville)` | PROPRIÉTAIRE **du pack avancé** | Crée un espace supplémentaire (nouvel UUID). |
| `rpc_espace_basculer(espace_id)` | membres | Change `espace_actif_id` (vérif accès). |
| `rpc_espace_supprimer(espace_id)` | PROPRIÉTAIRE | Désactive (jamais de suppression de données). |

### 2.4 Le pack avancé (offre tarifaire)

Le multi-entreprise est **réservé à un groupe tarifaire dédié** :

- nouveau groupe tarifaire « **Pack Avancé multi-entreprises** » avec :
  - `max_espaces` (nombre d'entreprises incluses — ex. 3) ;
  - prix mensuel du pack ;
  - les espaces supplémentaires au-delà du quota → options de dépassement
    (à définir : facturation par espace supplémentaire ?).
- `rpc_espace_creer` vérifie : rôle PROPRIÉTAIRE + groupe = pack avancé +
  nombre d'espaces actifs < `max_espaces`.

## 3. Interface prévue

1. **Sélecteur d'entreprise** dans la barre supérieure (visible seulement si
   le compte a ≥ 2 espaces) : bascule immédiate de tout l'espace de travail.
2. **Écran « Mes entreprises »** (Paramètres) : liste des espaces, nom de
   chaque commerce, type, bouton **Créer une entreprise** (selon pack),
   bouton **Basculer**.
3. Chaque écran (ventes, stock, accueil) affiche le **nom de l'espace actif**
   pour éviter toute confusion de caisse.

## 4. Impacts et risques

| Zone | Impact |
|---|---|
| RLS / politiques | **Aucune réécriture** : `mon_proprietaire()` redéfini couvre tout. |
| Tables métier | Aucune migration de données (astuce UUID = espace par défaut). |
| Abonnement | 1 abonnement couvre N espaces (c'est le principe du pack). |
| Quotas IA | Pool par **compte** (à trancher : partagé entre espaces ou par espace ?). |
| Journal d'audit | Inchangé (espace courant estampillé). |
| Tests | Nouveaux tests RPC + ré-exécution complète des scénarios RLS. |

## 5. Ce qui reste à décider (❓ questions au propriétaire)

1. **Combien d'entreprises** dans le pack (2, 3, 5, illimité) ?
2. **Prix du pack** (montant CDF / des extras) ?
3. **Quotas IA** : le pool de quotas est-il partagé entre les entreprises du
   compte, ou un pool par entreprise ?
4. Les **collaborateurs** : peuvent-ils être affectés à UNE entreprise
   précise (recommandé), ou voient-ils toutes les entreprises du patron ?
5. Les **rapports** : consolidés (toutes entreprises) ou par entreprise ?

## 6. Plan de livraison proposé (après validation)

1. Migration 19 : `espaces` + backfill (espace par défaut = UUID patron) +
   `utilisateurs.espace_actif_id` + `mon_proprietaire()` redéfini + RPC
   `rpc_espaces_lister` / `rpc_espace_basculer` / `rpc_espace_creer` +
   groupe tarifaire « Pack Avancé ».
2. Dart : `EspaceService` + sélecteur + écran « Mes entreprises » + tests.
3. Documentation + release.

> ⚠️ Tant que ce module n'est pas validé, **rien n'est exécuté** :
> le multi-entreprise n'existe pas et la demande reste ouverte.
