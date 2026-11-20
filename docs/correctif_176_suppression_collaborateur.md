# Correctif 176 — Suppression d'un collaborateur (« Mon Équipe »)

**Date** : 20 novembre 2026
**Migration** : `supabase/migrations/20260916000176_suppression_collaborateur.sql`
**Prérequis** : migration **174** exécutée (journal d'audit sans clé étrangère)

---

## 1. Le défaut

L'écran **Mon Équipe** (*Paramètres → Mes vendeurs*, ou *Accueil →
Collaborateurs*) permet de créer, modifier et supprimer un collaborateur.

La création et la modification fonctionnaient (`rpc_collaborateur_creer`,
`rpc_collaborateur_maj` — migration 0140). La **suppression**, elle, appelait :

```dart
await SupabaseClient.rpc('delete_collaborateur',
    params: {'target_user_id': user.id});
```

Or **aucune migration ne crée `delete_collaborateur`** (vérifié sur les
176 fichiers de `supabase/migrations`). PostgREST répondait donc :

> `Could not find the function public.delete_collaborateur(target_user_id) in the schema cache` (PGRST202)

…et le message affiché à l'écran était « Suppression impossible : … » avec le
code brut. Le bouton ne pouvait **jamais** fonctionner, sur aucune version.

Conséquence concrète : un vendeur qui quitte la pharmacie devait être
« désactivé » (Modifier → actif = non), ou le patron devait passer par la
suppression de compte du Super Administrateur.

---

## 2. La correction

### 2.1 Nouvelle fonction serveur

`rpc_collaborateur_supprimer(p_id uuid, p_confirmation text)`

Garde-fous, tous côté serveur :

| Garde | Comportement |
|---|---|
| Session | `SESSION_ABSENTE` si non connecté |
| Droit | `DROIT_REFUSE` si l'appelant n'est ni le propriétaire de l'entreprise ni la plateforme |
| Confirmation | `CONFIRMATION_REQUISE` si `p_confirmation <> 'SUPPRIMER'` |
| Cible | `COLLABORATEUR_INTROUVABLE` si le compte n'existe plus |
| Soi-même | `ACTION_INTERDITE` : on ne supprime pas son propre compte par cet écran |
| Propriétaire | `DROIT_REFUSE` : le propriétaire de l'entreprise ne peut pas être supprimé ici |
| Équipe | `COLLABORATEUR_INTROUVABLE` si le collaborateur n'est pas rattaché au propriétaire |
| Historique | détache `utilisateurs.parent_id` et `agent_ia_config.updated_by`, puis `SUPPRESSION_BLOQUEE` seulement si une contrainte résiste (→ migration 174) |

Ce qui est supprimé : le **profil** (`public.utilisateurs`) puis le **compte de
connexion** (`auth.users`). Le retour indique `compte_auth_supprime`.

Ce qui n'est **pas** supprimé : ventes, encaissements, lots, mouvements de
stock, journal d'audit. Les clés étrangères `on delete set null` détachent
l'auteur ; aucune donnée métier ne disparaît.

Journal : `COLLABORATEUR_SUPPRIME` avec `collaborateur_id`, `email`, `nom`,
`role`, `compte_auth_supprime`, `boutique`.

### 2.2 Alias de compatibilité

`delete_collaborateur(target_user_id uuid)` — même logique, nom historique.
Il existe pour que **les applications déjà installées** continuent de
fonctionner sans mise à jour : elles appellent ce nom.

> ⚠️ **Erreur 42P13 rencontrée le 20/11/2026** :
> `cannot change return type of existing function — HINT: Use DROP FUNCTION
> delete_collaborateur(uuid) first.`
> Un `delete_collaborateur(uuid)` existait **déjà** dans la base avec un autre
> type de retour (créé hors dépôt) : `create or replace` refuse de changer le
> type de retour. La migration supprime donc d'abord **toutes** les versions
> de ce nom (bloc `DO` qui boucle sur `pg_proc`), puis recrée la nôtre et
> réapplique les droits. Re-exécuter 0176 est sans risque.

### 2.3 Côté Dart

* `EquipeService.supprimer({id, confirmation})` — appelle la nouvelle RPC ;
  en cas de `PGRST202` (base non migrée), retombe sur `delete_collaborateur`
  puis affiche « exécutez la migration 176 ».
* `messageErreur` traduit `CONFIRMATION_REQUISE` et `SUPPRESSION_BLOQUEE`.
* `manage_users_page.dart` `_deleteUser` — dialogue de confirmation **écrite**
  (« Écrivez SUPPRIMER pour confirmer »), puis appel du service. Le message de
  succès devient « X supprimé : son accès est fermé. »

---

## 3. Fichiers touchés

| Fichier | Nature |
|---|---|
| `supabase/migrations/20260916000176_suppression_collaborateur.sql` | **nouveau** |
| `lib/services/equipe_service.dart` | `supprimer()` + messages |
| `lib/pages/manage_users_page.dart` | Confirmation écrite + appel du service |
| `docs/guide_module_pharmacie_complet.md` | Chapitre 8 (collaborateurs) |
| `README.md` | Migration 0176 |

---

## 4. Procédure de test

1. Exécuter `20260916000176_suppression_collaborateur.sql` (après 174) dans le
   SQL Editor. Les vérifications de fin doivent renvoyer 2 fonctions et 0 clé
   étrangère sur `journal_audit`.
2. Se connecter avec le **propriétaire** de la pharmacie.
3. *Accueil → Collaborateurs* (ou *Paramètres → Mes vendeurs*).
4. Créer un collaborateur de test (e-mail neuf, mot de passe ≥ 8 caractères).
5. Le supprimer : **Supprimer** → taper `SUPPRIMER` → confirmer.
   *Attendu* : il disparaît de la liste, message « X supprimé : son accès est
   fermé. »
6. Vérifier dans Supabase :
   ```sql
   select id, email from public.utilisateurs where email = 'test@exemple.cd';
   select id, email from auth.users       where email = 'test@exemple.cd';
   ```
   *Attendu* : 0 ligne dans les deux tables.
7. Vérifier le journal :
   ```sql
   select action, details, created_at
     from public.journal_audit
    where action = 'COLLABORATEUR_SUPPRIME'
    order by created_at desc limit 3;
   ```
8. Tester les refus : taper autre chose que `SUPPRIMER` (→ message
   « Tapez SUPPRIMER… »), puis essayer de supprimer un compte *Responsable* qui
   n'appartient pas à l'équipe (→ « n'appartient pas à votre entreprise »).

---

## 5. Retour arrière

```sql
drop function if exists public.delete_collaborateur(uuid);
drop function if exists public.rpc_collaborateur_supprimer(uuid, text);
```

L'écran revient à son comportement d'avant (bouton inopérant) : aucune donnée
n'est affectée par le retrait des fonctions.
