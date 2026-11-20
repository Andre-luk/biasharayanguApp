# Correctif 174 — création unifiée, métier réel, suppressions sûres

**Version applicative :** correctif de base (aucune publication déclenchée)
**Migration :** `supabase/migrations/20260916000174_creation_unifiee_suppressions.sql`
**Statut :** écrite et validée syntaxiquement (71/71 instructions) — **à exécuter
dans Supabase → SQL Editor**, puis à tester (section 6).

---

## 1. Diagnostic (cause réelle de chaque bug)

### Problème 1 — « invalid input syntax for type uuid »

| Élément | Constat |
|---|---|
| Message | `22P02` levé **avant** l'exécution du corps de la fonction |
| Origine | Les listes déroulantes renvoient `''` (parfois `'null'`, `'undefined'`) ; `rpc_admin_entreprise_creer` déclarait `p_ville_id uuid`, `p_activite_id uuid`, `p_groupe_tarifaire_id uuid`. PostgreSQL refuse la conversion : **toute la transaction est annulée**. |
| Fichiers | `lib/pages/entreprise_creation_page.dart`, `lib/services/entreprise_service.dart` (`creerEntrepriseAvecProprietaire`), `supabase/migrations/…0073` |
| Pourquoi ça revenait | Un correctif Dart (`uuidOuNull`) existait, mais **les anciennes versions installées sur les téléphones** envoient toujours `''`. Le serveur restait intolérant. |

**Correctif à la source :** le serveur reçoit désormais ces identifiants en
`text` et les normalise (`public.uuid_ou_null(text)`). Une chaîne vide, `null`,
`undefined`, `0`, `-1` ou un code de module deviennent `NULL` — **jamais** une
erreur. Côté Dart, une règle unique : `lib/utils/uuid_utils.dart`
(`UuidValide.ouNull`), utilisée pour tous les identifiants envoyés.

### Problème 2 — Setup ≠ Super Admin

| Élément | Constat |
|---|---|
| Setup | `rpc_entreprise_creer` (insère `nom`, crée l'espace, rattache le patron) |
| Super Admin | `rpc_admin_entreprise_creer` (crée le compte Auth puis sa propre copie de l'insertion) |
| Conséquences | deux logiques à maintenir ; `owner_id` (route B, migration 145) **n'était pas écrit** par la création Super Admin → l'entreprise n'apparaissait pas dans le sélecteur de son propriétaire ; les profils de modules pouvaient manquer ; `modules_catalogue()` avait **22 codes** alors que le Dart en référence **25** (distribution + pressing absents). |

**Correctif :** un **cœur unique** `biashara_entreprise_creer_coeur(...)` appelé
par les deux points d'entrée, dans une seule transaction :
entreprise → espace → propriétaire/liaison (`entreprise_id`,
`espace_actif_id`, rôle normalisé) → dossier d'activation → profil de modules
complet → trace d'audit. `biashara_assurer_profil_activite(type)` crée le profil
**avec tout le catalogue** s'il manque (jamais écrasé s'il existe).

### Problème 3 — « les anciennes informations réapparaissent »

| Élément | Constat |
|---|---|
| Cause principale | La fiche affichait `entreprises.type_activite` (**axe commercial** : boutique / distribution) alors que le **métier** (pharmacie, pressing, hôtel…) vit dans `espaces.type`. Choisir « Pharmacie » changeait les modules… mais la carte réaffichait « Boutique ». |
| Cause secondaire | Le rafraîchissement après changement ne visait que l'espace actif (`definirMetier`), or un Super Admin n'a pas d'espace actif → modules et types n'étaient pas rechargés ; le cache de la liste (`CacheLecture`) et le cache SharedPreferences des espaces (`espace_etat_cache_v1`) n'étaient pas pérımés de façon fiable. |

**Correctif :** `rpc_entreprises_metiers()` expose le **métier réel** (source
unique : `espaces.type`, sans colonne dupliquée). L'entreprise porte désormais
`metier` / `metierLibelle` dans le modèle Dart ; la fiche affiche le métier et
l'axe ; `EntrepriseService.invaliderCachesEntreprises()` purge les caches et
recharge espaces + modules + type après **chaque** changement.

### Problème 4 — suppression d'entreprise bloquée par le journal d'audit

| Élément | Constat |
|---|---|
| Cause | `journal_audit.utilisateur_id` portait une clé étrangère (`RESTRICT`) et `rpc_entreprise_supprimer` supprimait des lignes du journal : le déclencheur `trg_journal_audit_append_only` refusait toute suppression. |
| Fichiers | `supabase/migrations/…0013` (trigger), `…0095` (contournement par `disable trigger`) |

**Correctif durable (sans affaiblir le journal) :**

1. `journal_audit` n'a **plus aucune clé étrangère** (boucle sur `pg_constraint`) ;
2. deux colonnes d'**instantané** : `entreprise_nom`, `utilisateur_email`,
   remplies à l'INSERT par `trg_audit_preparer` — le journal survit donc à la
   suppression de l'entreprise ou du compte ;
3. les suppressions n'écrivent plus dans le journal qu'en **INSERT**
   (`ENTREPRISE_SUPPRIMEE`, `UTILISATEUR_SUPPRIME`) ;
4. `trg_journal_audit_append_only` est **intact** : UPDATE et DELETE restent
   refusés à tout le monde.

### Problème 5 — suppression d'utilisateur avec cascade complète

| Élément | Constat |
|---|---|
| Existant | `rpc_admin_purger_utilisateur` supprimait les lignes rattachées **par clé étrangère**, mais **pas les entreprises possédées** (`entreprises.owner_id` n'a pas de FK vers l'utilisateur) : les boutiques et leurs paiements restaient orphelins. |
| Cycle FK bloquant | `entreprises.owner_id → utilisateurs` **et** `utilisateurs.entreprise_id → entreprises`. Quel que soit l'ordre, l'un des deux `DELETE` est refusé. |

**Correctif :** `biashara_supprimer_utilisateur_coeur(...)` :

* périmètre = la personne + ses sous-comptes + **toutes les entreprises
  possédées** (`owner_id`, `proprietaire_id`, convention `espaces.id = patron`) ;
* coupe les deux liens (`owner_id`/`proprietaire_id` → `NULL`,
  `entreprise_id` → `NULL`) avant toute suppression ;
* supprime les données métier (inventaire dynamique par
  `information_schema`, y compris `agent_ia_*` dont `entreprise_id` porte
  l'UUID du patron), les espaces, les entreprises, les comptes, puis
  `auth.users` ;
* **garde-fous** : SUPER_ADMIN uniquement, jamais son propre compte, jamais un
  compte de plateforme, jamais le dernier Super Admin ;
* **confirmation** : `SUPPRIMER`, le nom du compte ou son e-mail ;
* **sauvegarde** : toutes les lignes supprimées sont déposées en JSON dans
  `public.sauvegardes_suppressions` **avant** la suppression.

---

## 2. Ce que la migration installe

| Objet | Rôle |
|---|---|
| `public.uuid_ou_null(text)` | texte → UUID valide ou `NULL` (jamais 22P02) |
| `public.modules_catalogue()` (v2) | **25 codes** = miroir exact du Dart |
| `public.biashara_assurer_profil_activite(text)` | profil de modules garanti (créé complet si absent) |
| `public.biashara_entreprise_creer_coeur(...)` | **le** cœur de création (Setup + Super Admin) |
| `public.rpc_entreprise_creer(text, text, text)` | Setup → cœur |
| `public.rpc_admin_entreprise_creer(text, …, numeric, text)` | Super Admin → cœur (identifiants `text`) |
| `public.rpc_entreprises_metiers(uuid[])` | métier réel par entreprise (portée RLS respectée) |
| `public.sauvegardes_suppressions` | instantané JSON avant destruction |
| `public.biashara_purger_perimetre(...)` | purge technique (journal **exclu**, gardes rétablies) |
| `public.biashara_supprimer_entreprise_coeur(...)` | suppression entreprise + trace INSERT |
| `public.biashara_supprimer_utilisateur_coeur(...)` | suppression compte en cascade complète |
| `journal_audit` | colonnes `entreprise_nom` / `utilisateur_email`, **0 clé étrangère** |

## 3. Fichiers Dart modifiés

- `lib/utils/uuid_utils.dart` *(nouveau)* : règle UUID unique + traduction des
  erreurs PostgreSQL en français.
- `lib/models/entreprise.dart` : `metier` / `metierLibelle` (champs de
  confort calculés côté serveur, jamais envoyés à Supabase).
- `lib/services/entreprise_service.dart` : validation des identifiants,
  chargement du métier réel, invalidation des caches,
  `invaliderCachesEntreprises()`, messages 22P02 lisibles.
- `lib/pages/entreprise_detail_page.dart` : la carte « Type d'activité »
  affiche le **métier** (et l'axe), coche le type courant.
- `lib/pages/admin_users_page.dart` : confirmation par nom / `SUPPRIMER`,
  message de résultat avec entreprises, paiements et sauvegarde.
- `test/uuid_utils_test.dart` *(nouveau)* : 11 cas.

---

## 4. Exécution

1. Supabase → **SQL Editor** → coller `20260916000174_creation_unifiee_suppressions.sql` → **Run**.
2. Vérifier les 3 requêtes de contrôle en fin de script :
   - `13.a` → **0 ligne** (plus aucune FK sur `journal_audit`) ;
   - `13.b` → `trg_journal_audit_append_only` avec `tgenabled = 'O'` ;
   - `13.c` → **8 fonctions** listées.

## 5. Restaurer une suppression (si besoin)

```sql
-- Retrouver la sauvegarde
select id, cree_le, cible_type, cible_id, lignes,
       jsonb_object_keys(donnees) as table_sauvegardee
  from public.sauvegardes_suppressions
 order by cree_le desc;

-- Explorer une table sauvegardée
select jsonb_array_elements(donnees->'ventes')
  from public.sauvegardes_suppressions
 where id = '<id>';

-- Réinsertion (exemple : ventes) — à adapter à la table ciblée
insert into public.ventes
select * from jsonb_populate_recordset(null::public.ventes,
         (select donnees->'ventes'
            from public.sauvegardes_suppressions
           where id = '<id>'));
```

> La restauration est volontairement manuelle : elle exige de recréer d'abord
> l'entreprise et les comptes (les identifiants sont conservés dans le JSON).

---

## 6. Tests à effectuer et à rapporter

### T1 — Créer entreprise + propriétaire via le Super Admin

1. Administration → Entreprises → **Créer (complet)**.
2. Laisser **Ville / Activité / Grille vides** (c'est le cas qui provoquait 22P02).
3. Valider.

**Attendu :** succès ; l'entreprise apparaît dans la liste du Super Admin, dans
les comptes de l'Administration, et dans « Mes entreprises » du propriétaire.

```sql
select e.id, e.nom, e.owner_id, e.proprietaire_id, e.type_activite,
       e.activation_etape, s.type as metier, u.new_role
  from public.entreprises e
  left join public.espaces s on s.entreprise_id = e.id
  left join public.utilisateurs u on u.id = e.owner_id
 where e.nom = '<nom>';

select * from public.types_espaces_modules t
 where t.type = '<metier>';          -- profil complet (25 codes si créé)
```

### T2 — Créer entreprise + propriétaire via le Setup

Inscription autonome avec une catégorie (ex. Pharmacie).

**Attendu :** même structure que T1 (mêmes colonnes remplies, mêmes modules),
`activation_etape = 'en_attente_verification'` (mode complet) ou `'actif'`
(mode simple), et **un** espace.

```sql
select count(*) as espaces from public.espaces where entreprise_id = '<id>';
select e.owner_id, (select count(*) from public.utilisateurs u
                     where u.id = e.owner_id) as proprietaire_existe
  from public.entreprises e where e.id = '<id>';
```

### T3 — Changer le type, quitter, rouvrir

1. Fiche entreprise → **Changer le type** → *Pharmacie*.
2. Revenir à la liste, quitter l'écran, rouvrir la fiche.

**Attendu :** la carte affiche **Pharmacie** (métier), les modules suivent ;
aucune trace de l'ancien type.

```sql
select s.type as metier, e.type_activite
  from public.espaces s join public.entreprises e on e.id = s.entreprise_id
 where e.id = '<id>';
-- puis, connecté en propriétaire :
select public.rpc_mes_modules();
```

### T4 — Supprimer une entreprise

Fiche → **Supprimer** → taper `SUPPRIMER`.

**Attendu :** succès, **aucune** erreur de journal d'audit, une nouvelle ligne
`ENTREPRISE_SUPPRIMEE` avec `entreprise_nom` renseigné.

```sql
select action, entreprise_nom, created_at
  from public.journal_audit
 where action = 'ENTREPRISE_SUPPRIMEE'
 order by created_at desc limit 3;

select public.rpc_entreprise_supprimer('<uuid>', 'SUPPRIMER'); -- teste 2e fois → ENTREPRISE_INTROUVABLE
```

### T5 — Supprimer un propriétaire

Administration → Utilisateurs → menu → **Supprimer** → *Purge totale* →
taper le nom (ou `SUPPRIMER`).

**Attendu :** entreprises, données et paiements supprimés, compte Auth supprimé,
`entreprises_supprimees` > 0, `paiements_supprimes` renseigné,
`sauvegarde_id` non nul.

```sql
-- Ceinture et bretelles : aucune ligne orpheline
select count(*) from public.espaces where entreprise_id not in
  (select id from public.entreprises);

select count(*) from public.ventes where owner_id not in
  (select id from public.espaces);

select count(*) from public.paiements_abonnements_laperle
 where entreprise_id not in (select id from public.entreprises);

select id, cible_type, lignes from public.sauvegardes_suppressions
 order by cree_le desc limit 1;
```

### T6 — Journal toujours inaltérable

```sql
-- DOIT ÉCHOUER : UPDATE interdit
update public.journal_audit set action = 'X' where seq is not null;

-- DOIT ÉCHOUER : DELETE interdit
delete from public.journal_audit where seq is not null;
```

Attendu : `AUDIT_INALTERABLE|Le journal d'audit est inaltérable : update/delete
est interdit sur public.journal_audit.`

---

## 7. Rollback

La migration **ne supprime aucune donnée**. En cas de problème :

```sql
-- Revenir à l'ancienne signature uuid (l'application actuelle appelle la
-- version text, ne le faire qu'avec une application antérieure) :
--   drop function public.rpc_admin_entreprise_creer(text, text, text, text,
--     text, text, text, text, text, text, numeric, numeric, text);
-- puis rejouer la section 3 de la migration 0073.
```

Les colonnes `journal_audit.entreprise_nom` / `utilisateur_email` et la table
`sauvegardes_suppressions` peuvent rester : elles sont sans effet de bord.
