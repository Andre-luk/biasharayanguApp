# Module 37 — Collaborateurs multi-entreprises (conception)

**Statut** : conception validée techniquement, **non implémentée**.
**Pré-requis** : 0170 exécutée et vérifiée (harold ne voit que HEKIMA).

---

## 1. Limite actuelle (structurelle)

Un collaborateur est décrit par **une seule ligne `utilisateurs`** :

| Colonne | Rôle actuel |
|---|---|
| `parent_id` | patron |
| `entreprise_id` | **une seule** entreprise |
| `new_role` | **un seul** rôle |
| `espace_actif_id` | une boutique de cette entreprise |
| `valide` | actif/inactif **globalement** |

Conséquences : impossible d'avoir Harold à la fois caissier dans Urembo et
pharmacien dans HEKIMA, ni de le désactiver dans une entreprise sans le
désactiver partout. C'est exactement ce que demande la mission §3.

## 2. Modèle proposé — table de rattachement

```sql
create table public.collaborateurs_entreprises (
  id             uuid primary key default gen_random_uuid(),
  utilisateur_id uuid not null references public.utilisateurs(id) on delete cascade,
  entreprise_id  uuid not null references public.entreprises(id) on delete cascade,
  role           public.role_utilisateur_enum not null,
  actif          boolean not null default true,
  cree_le        timestamptz not null default now(),
  unique (utilisateur_id, entreprise_id)
);
```

- `utilisateurs.entreprise_id` / `new_role` restent la **ligne principale**
  (compatibilité totale, aucun écran cassé).
- La table ajoute les rattachements **supplémentaires** ; la migration de
  départ recopie l'existant (aucun utilisateur perdu).
- Un même utilisateur peut donc avoir N lignes, avec un rôle différent et un
  `actif` différent par entreprise.

## 3. Fonctions à ajouter / adapter

| Objet | Rôle |
|---|---|
| `mes_entreprises()` | entreprises où `utilisateur_id = auth.uid() and actif` + rôle de chacune |
| `role_dans_entreprise(ent)` | rôle effectif (table, repli `utilisateurs.new_role`) |
| `acces_entreprise(ent)` | `true` si rattachement actif ou patron de l'entreprise |
| `mon_role()` | **rôle dans l'entreprise active** (aujourd'hui global) |
| `rpc_espaces_lister()` | itère sur `mes_entreprises()` (collaborateur) / toutes (patron) |
| `rpc_espace_basculer()` | vérifie `acces_entreprise`, met à jour `entreprise_id`, `new_role`, `espace_actif_id` |
| `abonnement_collaborateurs_actifs(ent)` | compte les lignes **actives de cette entreprise** (facturation correcte) |

## 4. RLS et permissions

- Les policies métier restent basées sur `mon_proprietaire()` (espace) : **le
  cloisonnement des données ne change pas**.
- Ce qui change : `mon_role()` doit renvoyer le rôle **dans l'entreprise de
  l'espace actif**. La matrice `peut()` (SQL) et la matrice Dart suivent.
- Le rôle affiché par l'app vient de `rpc_espaces_lister` (champ `role` par
  espace) : le middleware Flutter doit se recharger à chaque bascule
  (`EspaceService.etat` → `PermissionService.chargerRole`).

## 5. Découpage (4 migrations, sans big-bang)

1. **Phase 1 — additif** : table + index + RLS lecture + reprise de
   l'existant. Aucune fonction ne la lit encore ⇒ zéro régression.
2. **Phase 2 — lecture** : `mes_entreprises()`, `acces_entreprise()`,
   `role_dans_entreprise()` ; `rpc_espaces_lister` et `rpc_espace_basculer`
   utilisent la table (repli sur l'ancien modèle).
3. **Phase 3 — permissions** : `mon_role()` par entreprise ;
   `abonnement_collaborateurs_actifs` par lignes actives ; adaptation Dart.
4. **Phase 4 — gestion** : création/désactivation par entreprise
   (`rpc_collaborateur_*`), écran « Équipe » filtré par entreprise.

## 6. Décisions à prendre avant la phase 2

1. **Un collaborateur peut-il être PROPRIÉTAIRE d'une entreprise du patron ?**
   (recommandé : non, seul `entreprises.owner_id` l'est.)
2. **Facturation** : une même personne dans 2 entreprises compte-t-elle
   2 × 2 500 CDF ? (recommandé : oui, chaque entreprise a son abonnement.)
3. **Un collaborateur peut-il avoir plusieurs boutiques dans la même
   entreprise ?** (aujourd'hui : une seule `espace_actif_id` ; recommandé :
   oui, via la table au niveau entreprise, l'espace restant un choix d'écran.)
4. **Que devient `utilisateurs.valide` ?** (recommandé : statut du COMPTE ;
   `collaborateurs_entreprises.actif` = statut par entreprise ; un compte
   désactivé globalement reste bloqué partout.)
5. **Roles disponibles par entreprise** : les 8 rôles actuels, ou un
   sous-ensemble métier (pharmacien, caissier, magasinier) ?

## 7. Risques et garde-fous

- La phase 3 touche `mon_role()` : toutes les policies RLS en dépendent.
  ⇒ tests de non-régression obligatoires (permissions + ventes + stock).
- Ne jamais supprimer `utilisateurs.entreprise_id` : des triggers et RPC
  legacy s'y réfèrent encore.
- Toute reprise de données doit être idempotente (`on conflict do nothing`).
- Le comptage des collaborateurs facturés doit rester **par entreprise**,
  sinon un patron multi-entreprises paie deux fois le même salarié sans le
  savoir (ou l'inverse).
