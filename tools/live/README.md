# Accès Supabase pour les tests « live » — mode d'emploi

Objectif : me permettre de **vérifier réellement** (migration exécutée, RPC,
lots, vente FEFO, isolation entre entreprises) **sans que vos secrets passent
par le chat** et sans exposer votre compte de production.

---

## Option A — recommandée : vous exécutez le SQL, je vérifie par API

1. Supabase → **SQL Editor** → coller le contenu de
   `supabase/migrations/20260916000163_module36_lots_pharmacie.sql` → **Run**.
2. Me recopier **uniquement** la dernière ligne du résultat
   (`Module 36 lots — OK …`), qui ne contient aucun secret.
3. Créer un **compte de test** propriétaire (jamais votre compte réel) avec :
   - une entreprise « Boutique test »,
   - une entreprise « Pharmacie test » (type `pharmacie`),
   - 1 article dans chaque entreprise.
4. Déposer ses identifiants dans le fichier décrit ci-dessous, puis lancer :

   ```bash
   bash tools/live/verifier_module36.sh
   ```

Le script ne fait que des lectures et des appels de diagnostic. Aucun mot de
passe ni jeton n'est affiché.

---

## Où mettre les identifiants (hors dépôt, jamais committé)

```bash
mkdir -p ~/.config/biashara
cp tools/live/supabase.env.example ~/.config/biashara/supabase.env
chmod 600 ~/.config/biashara/supabase.env
nano ~/.config/biashara/supabase.env
```

Contenu :

```bash
SUPABASE_URL="https://pqzcliibocndiyqbyddr.supabase.co"
SUPABASE_ANON_KEY="<la clé anon du projet — déjà publique dans lib/main.dart>"
TEST_EMAIL="test.pharmacie@biasharayangu.cd"
TEST_PASSWORD="<mot de passe du compte de TEST>"
TEST_PRODUIT_ID="<id d'un produit de la pharmacie test, facultatif>"
```

`.gitignore` couvre `*.env` et `tools/live/supabase.env`. Le fichier réel vit
en dehors du dépôt (`~/.config/biashara/`).

### Ce que je vois et ce que je ne vois pas

- Je **n'ouvre jamais** ce fichier : les scripts le chargent eux-mêmes
  (`source`) et n'impriment que des verdicts (`OK`, `ABSENTE`, `HTTP 404`…).
- Je ne peux pas exécuter de DDL avec la clé anon : c'est voulu. Le SQL passe
  par vous (Option A) ou par l'Option B.

---

## Option B — je lance aussi le SQL (à éviter si possible)

Cela demande un **Personal Access Token Supabase** (`sbp_…`), qui donne accès
à **toute la plateforme** (projets, base, clés). Si vous l'acceptez :

1. Supabase → Account → Access Tokens → créer un jeton nommé
   `biashara-audit-temporaire`.
2. L'ajouter **uniquement** dans `~/.config/biashara/supabase.env` :

   ```bash
   SUPABASE_ACCESS_TOKEN="sbp_..."
   SUPABASE_PROJECT_REF="pqzcliibocndiyqbyddr"
   ```

3. À la fin des tests : **révoquer** ce jeton dans Supabase.

Je l'utiliserais seulement via un script dédié (Management API
`/v1/projects/{ref}/database/query`), jamais recopié dans une réponse.

---

## Option C — projet Supabase de test séparé (le plus sûr)

Créer un projet gratuit dédié aux essais, y appliquer les migrations, et me
donner l'accès (Option A ou B) **sur ce projet uniquement**. Vos données
réelles ne sont jamais touchées, et un jeton compromis ne donne accès qu'aux
données de test.

---

## Ce que je ferai avec cet accès

| Test | Nature |
|---|---|
| Migration 0163 exécutée, tables/RPC/triggers présents | lecture |
| `rpc_lots_ecarts()` | lecture |
| Réception de 3 lots du même médicament | écriture **compte de test** |
| Vente : lot le plus proche consommé (FEFO), lot périmé refusé | écriture **compte de test** |
| Retrait de lot + mouvement tracé | écriture **compte de test** |
| Isolation : article de la pharmacie invisible dans la boutique | lecture |

Jamais de test d'écriture sur un compte réel sans votre accord explicite.

---

## Scripts disponibles (13/11/2026)

| Script | Nature | Compte utilisé |
|---|---|---|
| `verifier_module36.sh` | **lecture seule** — tables/RPC du module 36, FEFO, écarts | compte pharmacie de test |
| `verifier_pressing.sh` | **lecture seule** — métier `pressing`, modules servis, catalogue, étapes, tableau de bord, atelier, caisse, compilation des RPC (18 contrôles) | `pressing.test@biashara.cd` |
| `pressing_e2e.py` | **écriture sur le compte de test** — amorçage catalogue/étapes, 1 dépôt (2 vêtements), prix figés, QR 64 hex, paiement partiel, surpaiement refusé, atelier → PRET, remise sans paiement refusée (`SOLDE_DU`), paiement du solde, remise, double remise refusée (`DEJA_REMIS`), caisse du jour | `pressing.test@biashara.cd` |

Les trois scripts lisent `~/.config/biashara/supabase.env` (chmod 600, hors
dépôt) et n'affichent **ni** le mot de passe, **ni** la clé anon, **ni** le
jeton.

### Ce que le pressing laisse en base après l'essai

`pressing_e2e.py` **ne supprime rien** (aucune politique DELETE n'existe sur
les commandes). Chaque exécution crée :

- 1 client `CLIENT TEST E2E <heure>` ;
- 1 commande `PR-AAAA-NNNNNN` portant l'observation
  « commande créée par le script de vérification » ;
- 2 lignes de vêtements, les paiements correspondants et 1 remise ;
- 2 tarifs de test (1 500 et 2 000) sur la première prestation.

Pour nettoyer : le faire par un script SQL explicite, sur décision du
propriétaire (jamais automatiquement).
