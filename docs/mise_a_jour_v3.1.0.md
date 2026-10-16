# Mise à jour v3.1.0 — Vendre depuis la caisse, enfin

**Version :** 3.1.0 (build 35)
**Migrations SQL :** `20260916000077`
*(à exécuter ; le programme SQL fait partie de l'installation)*
**Tests :** 923/923 ✅

---

## En une phrase

**Le panier de la caisse envoyait au serveur un numéro d'article qui n'existe
que sur le téléphone — d'où « Article n° 83 introuvable » ; c'est corrigé, et
la base sait désormais remettre en place les articles que les téléphones déjà
installés réclament.**

---

## Le problème, exactement

> « Quand je vends un produit simplement dans la caisse, le produit se vend.
> Mais quand je passe par le panier et que je valide la vente, on m'écrit :
> *Article n° 83 introuvable : il a peut-être été supprimé.* — alors que les
> articles sont là. »

**Ce n'est pas un article isolé : c'est la caisse entière.** Le n° 83 venait
d'**Urembo Market** — dont *presque tous* les articles échouaient de la même
façon. Le numéro change d'une boutique à l'autre, la cause est la même.

Vérifié **en direct sur la base** (au 16/10/2026) :

| Essai | Réponse du serveur |
|---|---|
| Vente avec le n° **83** | `PRODUIT_INTROUVABLE — Article n° 83 introuvable` |
| Vente avec le n° **503** (Eau Dasani, Biashara Group) | `STOCK_INSUFFISANT — 150 disponible(s)` : l'article est **trouvé**, la vente est saine |

- **Biashara Group** : 8 articles, n° 503 à 588.
- **Urembo Market** : 78 articles, n° **508 à 587** (créés d'un seul import).

Le n° 83 n'existe dans **aucune** des deux.

**La cause :** chaque téléphone garde une copie locale de ses articles
(SQLite), avec **ses propres numéros** : 1, 2, 3… 83. La caisse envoyait ce
numéro local au serveur, qui ne peut pas le reconnaître. Le serveur n'avait
donc pas tort — il ne recevait pas le bon numéro.

**Pourquoi cela « marchait » au scanner :** le scan relit l'article **dans la
base**, donc avec son vrai numéro (508, 509…). C'est la liste de la caisse qui
était fautive, pas la caisse entière — et c'est pour cela que **des ventes sont
bel et bien enregistrées** (12 lignes, toutes avec de vrais numéros de la base).

---

## Ce qui est corrigé

### 1. La caisse parle désormais en numéros de la base

Toute la vente (clés du panier, quantités, prix, formats d'emballage) utilise
le numéro de l'article **dans la base** — celui des QR codes et des étiquettes.
L'identifiant local n'est plus jamais envoyé.

Si un article a été créé sur le téléphone **sans avoir jamais atteint le
serveur**, la caisse le dit clairement au lieu de laisser le serveur refuser :
*« Cet article n'est pas encore enregistré sur le serveur : synchronisez puis
réessayez. »*

### 2. Un message qui dit quoi faire

L'erreur « Article n° X introuvable » est complétée : elle indique d'ouvrir
**Articles** pour vérifier, recréer l'article avec **Nouvel article**, ou
demander la restauration du numéro. Plus de message sans issue.

### 3. La base sait réparer un article précis ⭐

> ⚠️ **Ce n'est PAS la solution au problème de la caisse.** Quand *presque
> tous* les articles échouent, la base ne peut rien : le téléphone n'envoie
> qu'un numéro, et aucun numéro ne permet de deviner de quel article il
> s'agit. La solution, c'est la mise à jour de l'application (§1 et §2).
>
> Cet outil sert aux **cas ponctuels** : un article réellement supprimé qu'on
> veut faire revivre **sous son ancien numéro** pour un téléphone qui le
> réclame encore.

Un téléphone non mis à jour continuera d'envoyer ses anciens numéros. La base
peut donc **recréer un article sous le numéro exact** que ce téléphone
réclame : l'article « réapparaît » et redevient vendable, **sans aucune mise à
jour** — article par article.

| Outil | Rôle |
|---|---|
| `rpc_articles_verifier(boutique, [numéros])` | **Lire** : pour chaque numéro, dit s'il existe, à quelle boutique il appartient et de quel article il s'agit |
| `rpc_article_restaurer(numéro, nom, prix…, boutique)` | **Réparer** : recrée l'article sous ce numéro précis |

Garde-fous : réservé au **propriétaire de la boutique** et à la **plateforme** ;
refuse un numéro déjà occupé (en nommant l'article qui l'occupe) ; **prévient**
si un article du même nom existe déjà (jamais de doublon silencieux) ; l'action
est **inscrite au journal d'audit** (`ARTICLE_RESTAURE`).

> ⚠️ On ne devine **jamais** à quoi correspond un numéro : c'est le commerçant
> qui donne le nom et les prix, tels qu'ils s'affichent sur son téléphone. Un
> article inventé fausserait le stock et la caisse.

### 4. En attendant la mise à jour : vendre en scannant

Le scanner, lui, fonctionne déjà : il relit l'article **dans la base**. Depuis
l'écran des **QR codes**, une planche d'étiquettes s'imprime pour tous les
articles d'une boutique : les caissiers scannent au lieu de choisir dans la
liste, et les ventes passent.

---

## Mode d'emploi de la réparation (SQL Editor)

```sql
-- 1. Que deviennent ces numéros ?
select public.rpc_articles_verifier(
  p_numeros => '[83, 91, 503]'::jsonb     -- sans p_boutique : la vôtre
);

-- 2. Recréer l'article sous le numéro réclamé
select public.rpc_article_restaurer(
  p_numero       => 83,
  p_nom          => 'Nom affiché dans l''application',
  p_prix_vente   => 2000,
  p_prix_achat   => 1500,
  p_quantite     => 10,
  p_unite_mesure => 'piece'
);
-- → « ok: true » : le téléphone peut vendre cet article immédiatement.
```

`p_boutique` n'est à préciser **que** depuis un compte plateforme (Super Admin),
pour réparer la boutique d'un client — c'est `public.produits.owner_id`,
l'identifiant du propriétaire :

```sql
select id, owner_id, nom from public.produits order by id;
```

---

## Migrations de cette version

| # | Fichier | Ce qu'elle fait |
|---|---|---|
| 77 | `20260916000077_article_restaurer.sql` | `rpc_articles_verifier` (lecture) et `rpc_article_restaurer` (réparation sous un numéro imposé) + journalisation `ARTICLE_RESTAURE` |

**Idempotente** : relançable sans effet de bord, et se termine par un rapport.

> ⚠️ Rappel : les migrations **74** (garde-fou des rôles) et **76** (péremption
> + boutiques de l'agent) doivent également être exécutées si ce n'est pas fait.

---

## Compatibilité

- Aucune donnée existante n'est supprimée, renommée ou réécrite.
- Les ventes déjà enregistrées ne sont pas touchées.
- La réparation ne s'applique qu'aux numéros que vous demandez explicitement.
- Après mise à jour de l'application, **plus aucune réparation n'est
  nécessaire** : la caisse envoie d'elle-même les bons numéros.
