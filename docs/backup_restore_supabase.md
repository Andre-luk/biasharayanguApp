# 🔐 Sauvegarde & restauration — Supabase

> MODULE 12 — La stratégie de sauvegarde officielle de **Biashara Yangu**.
> Objectif : ne jamais perdre une seule vente. Chaque boutique travaille tous
> les jours sur ces données ; une perte serait un préjudice direct.

---

## 1. Ce que Supabase fait déjà pour nous (sauvegardes automatiques)

Selon le plan du projet (Dashboard Supabase → **Database → Backups**) :

| Plan | Sauvegarde automatique | Rétention |
|---|---|---|
| Free | Quotidienne (si activée) | courte |
| Pro | Quotidienne + option **PITR** (Point-In-Time Recovery, restauration à la seconde) | 7 à 28 jours |

**À faire une fois (5 minutes) :**

1. Ouvrir **Supabase Dashboard → le projet → Database → Backups**.
2. Vérifier que les sauvegardes automatiques sont **activées** et noter la rétention.
3. Si le plan le permet, activer **PITR** (indispensable pour restaurer « juste
   avant » une erreur humaine : vente supprimée par erreur, import raté…).

> ⚠️ Les sauvegardes automatiques couvrent la **base de données**. Les
> **fichiers Storage** (photos d'articles, etc.) ont leur propre export — voir §4.

---

## 2. Snapshot manuel (recommandé avant chaque migration ou gros import)

Un snapshot manuel se prend en 2 minutes et se garde **hors du dépôt Git**
(clé USB chiffrée, Google Drive privé…). Deux méthodes :

### Méthode A — Supabase CLI (la plus simple)

```bash
# Une seule fois : npm i -g supabase
export DB_URL="postgresql://postgres.<ref>:<MOT_DE_PASSE>@aws-0-<region>.pooler.supabase.com:5432/postgres"

# Rôles + schéma + données
supabase db dump --db-url "$DB_URL" -f backup_roles.sql    --role-only
supabase db dump --db-url "$DB_URL" -f backup_schema.sql
supabase db dump --db-url "$DB_URL" -f backup_data.sql     --data-only
```

### Méthode B — pg_dump classique

```bash
pg_dump "$DB_URL" -Fc -f biashara_$(date +%Y%m%d).dump
```

### Quand prendre un snapshot ?

- ✅ **Avant d'exécuter une migration** (Dashboard → SQL Editor → Run) ;
- ✅ **Avant un gros import d'articles** (Module 12 → écran Importer) ;
- ✅ **Avant une réinitialisation de permissions** (écran Sécurité) ;
- ✅ En routine : **une fois par semaine** (le vendredi soir par exemple).

> 💡 Les migrations du projet sont **idempotentes** (rejouables sans casser) et
> chaque module a sa vérification intégrée — mais un snapshot reste la ceinture
> de sécurité. Aucune migration ne remplace une sauvegarde.

---

## 3. Procédure de restauration

### 3.a Restauration d'urgence (sauvegarde automatique)

1. **Supabase Dashboard → Database → Backups**.
2. Choisir le point de restauration (date/heure) → **Restore**.
3. ⚠️ La restauration **remplace la base actuelle** : toute écriture faite
   depuis le point choisi est perdue. Prévenir les boutiques (prévenir = mettre
   l'application en lecture seule, cf. ci-dessous).
4. Après restauration : vérifier le journal d'audit
   (écran **Sécurité** → *Vérifier l'intégrité*) — la chaîne d'empreintes doit
   rester intègre.

### 3.b Restauration d'un snapshot manuel

```bash
# Sur une base vide (nouveau projet Supabase par exemple) :
psql "$DB_URL" -f backup_roles.sql
psql "$DB_URL" -f backup_schema.sql
psql "$DB_URL" -f backup_data.sql
```

ou avec le dump compressé :

```bash
pg_restore -d "$DB_URL" --clean --if-exists biashara_20260917.dump
```

### 3.c Mise en sécurité pendant une restauration

Pour éviter que des ventes arrivent **pendant** la restauration :

1. **Sécurité → (Super Admin)** : si tu dois couper rapidement une boutique,
   suspends son abonnement (Dashboard → table `entreprises` → `statut =
   'SUSPENDU'`) : le Module 12 bloque immédiatement toute action sensible
   (`verifier_action_sensible`) et l'application passe en accès bloqué.
2. Restaurer.
3. Remettre le statut d'origine.

---

## 4. Fichiers Storage (photos, logos)

La base ne contient que les **chemins** des fichiers. Pour sauvegarder les
fichiers eux-mêmes :

```bash
# Exporter tout un bucket
supabase storage cp -r ss:///produits ./backup_storage/produits
```

Ou, plus simple pour de petits volumes : télécharger le bucket depuis le
Dashboard (**Storage → bucket → Download**). À refaire en même temps que les
snapshots hebdomadaires.

---

## 5. Ce qu'il ne faut JAMAIS faire

- ❌ Modifier ou supprimer une ligne de `journal_audit` → **interdit par
  trigger** (`AUDIT_INALTERABLE`), c'est volontaire : le journal est la preuve.
- ❌ Restaurer une sauvegarde **sans prévenir** : prévenir d'abord (voir 3.c).
- ❌ Commiter un dump dans le dépôt Git (il contient des données clients).
- ❌ Faire un « reset » du projet Supabase sans snapshot manuel frais.

---

## 6. Routine recommandée (à afficher)

| Fréquence | Action |
|---|---|
| Quotidien (automatique) | Sauvegardes Supabase — vérifier une fois par mois qu'elles tournent |
| Hebdomadaire | Snapshot manuel (`supabase db dump`) + export Storage |
| Avant chaque migration | Snapshot manuel immédiat |
| Mensuel | Test de restauration sur un projet de test + note dans le classeur |
| À chaque incident | Consulter **Sécurité** (alertes, connexions) + **Journal d'audit** (filtre niveau CRITIQUE) |
