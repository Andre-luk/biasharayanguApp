# Passerelle de paiement SerdiPay — intégration Biashara Yangu

> **Statut** : code livré côté dépôt (migration `79`, Edge Function `serdipay`,
> écran Flutter). **Rien n'est actif tant que le déploiement n'est pas fait**
> (voir §5) et que SerdiPay n'a pas fourni ses identifiants (§2).

---

## 1. Ce que fait l'intégration

```mermaid
sequenceDiagram
    participant App as Application Flutter
    participant EF as Edge Function serdipay
    participant DB as PostgreSQL (Supabase)
    participant SP as SerdiPay

    App->>EF: POST /initier (JWT, téléphone, opérateur)
    EF->>DB: rpc_serdipay_ouvrir → MONTANT CALCULÉ EN BASE
    EF->>SP: Création de la transaction
    SP-->>EF: URL de paiement / référence fournisseur
    EF->>DB: rpc_serdipay_definir_lien
    EF-->>App: URL (ou consigne USSD) + référence interne
    SP->>EF: POST /webhook (signé HMAC)
    EF->>DB: rpc_serdipay_confirmer (idempotent + contrôle du montant)
    DB->>DB: rpc_abonnement_enregistrer_paiement (moteur module 3)
    App->>EF: POST /statut (sondage)
    EF-->>App: statut à jour
```

**Trois garanties importantes :**

| Risque | Parade |
|---|---|
| Client qui paie moins cher | Le montant n'est **jamais** transmis par l'app : `rpc_serdipay_ouvrir` le lit dans `entreprises.solde_restant` / `factures_abonnement.solde_restant`. |
| Webhook falsifié / offert | Signature HMAC-SHA256 obligatoire. Sans `SERDIPAY_WEBHOOK_SECRET`, le webhook répond **503** ; signature fausse → **401**. |
| Double crédit (webhook rejoué) | `reference` unique + `select … for update` + transition `en_attente → paye` unique. Un rejeu répond `{ok:true, deja:true}` sans recréditer. |

---

## 2. Ce que SerdiPay doit vous fournir

À demander au commercial / à l'équipe technique SerdiPay :

1. **URL de base de l'API** (ex. `https://api.serdipay.com`) ;
2. **Identifiants** : soit une clé d'API (`SERDIPAY_API_KEY`), soit un couple
   OAuth 2.0 `client_id` / `client_secret` ;
3. **Le secret de signature des webhooks** (`SERDIPAY_WEBHOOK_SECRET`) et le nom
   de l'en-tête utilisé ;
4. **La documentation de l'endpoint de création de paiement** (chemin, corps,
   réponse) ;
5. **La liste des codes opérateurs** qu'ils attendent
   (`orange`, `airtel`, `mpesa`, `afrimoney`, `card`…).

> ⚠️ Le site public de SerdiPay annonce « API REST, OAuth 2.0, webhooks,
> environnement de test » mais **la documentation en ligne n'est pas accessible
> publiquement**. C'est pourquoi le code isole tout le vocabulaire fournisseur
> dans **une seule section** de l'Edge Function (§7).

---

## 3. Fichiers livrés

| Fichier | Rôle |
|---|---|
| `supabase/migrations/20260916000079_passerelle_serdipay.sql` | Table `paiements_serdipay` + 6 fonctions (montant serveur, confirmation, statut). |
| `supabase/functions/serdipay/index.ts` | Edge Function : `/initier`, `/webhook`, `/statut`, `/ping`. |
| `lib/models/paiement_serdipay.dart` | Modèle + statuts + opérateurs. |
| `lib/services/serdipay_service.dart` | `initier`, `statut`, `attendreConfirmation`, `ouvrirLien`. |
| `lib/pages/paiement_serdipay_page.dart` | Écran Mobile Money / carte. |
| `lib/pages/mon_activation_page.dart` | Bouton **« Payer maintenant »** sur le dossier d'activation. |
| `supabase/config.toml` | `[functions.serdipay] verify_jwt = false`. |
| `test/serdipay_test.dart` | 11 tests purs (parsing, statuts, enveloppe). |

---

## 4. Secrets à créer

Dashboard → **Project Settings → Edge Functions → Secrets** :

| Secret | Obligatoire | Exemple / remarque |
|---|---|---|
| `SERDIPAY_BASE_URL` | ✅ | `https://api.serdipay.com` (sans `/` final) |
| `SERDIPAY_API_KEY` | ⚠️ si pas d'OAuth | Clé fournie par SerdiPay |
| `SERDIPAY_CLIENT_ID` | ⚠️ si OAuth | + `SERDIPAY_CLIENT_SECRET` |
| `SERDIPAY_WEBHOOK_SECRET` | ✅ | Chaîne ≥ 32 caractères, **partagée avec SerdiPay** |
| `SERDIPAY_PATH_INITIER` | – | Défaut `/api/v1/payments` |
| `SERDIPAY_PATH_STATUT` | – | Défaut `/api/v1/payments/{reference}` |
| `SERDIPAY_TOKEN_URL` | – | Défaut `${BASE_URL}/oauth/token` |
| `SERDIPAY_SIGNATURE_HEADER` | – | Défaut `x-serdipay-signature` |
| `SERDIPAY_RETURN_URL` | – | Retour après paiement (web) |
| `SERDIPAY_DEVISE` | – | Défaut `CDF` |

> `SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` sont
> injectés automatiquement par Supabase — ne pas les recréer.

---

## 5. Déploiement (dans cet ordre)

### 5.1 Base de données

SQL Editor → coller
`supabase/migrations/20260916000079_passerelle_serdipay.sql` → **Run**.
Le script finit par un contrôle : il lève une exception si la table ou l'une des
6 fonctions manque.

### 5.2 Secrets

Créer les secrets du §4.

### 5.3 Fonction Edge

**Méthode Dashboard** : Edge Functions → *New function* → nom **`serdipay`** →
coller `supabase/functions/serdipay/index.ts` → **Deploy**.

**Méthode CLI** :

```bash
npx --yes supabase@latest functions deploy serdipay \
  --project-ref pqzcliibocndiyqbyddr --no-verify-jwt
```

### 5.4 ⚠️ Désactiver « Verify JWT »

Sur la fonction `serdipay`, désactiver **« Enforce JWT verification »**.
Sinon la passerelle Supabase répond avant notre code :

```
401 {"code":"UNAUTHORIZED_NO_AUTH_HEADER","message":"Missing authorization header"}
```

Les routes privées (`/initier`, `/statut`) vérifient **elles-mêmes** le JWT ;
le webhook s'authentifie par signature.

### 5.5 Vérification

```bash
BASE="https://pqzcliibocndiyqbyddr.supabase.co"

# 1. La fonction répond
curl -s "$BASE/functions/v1/serdipay/ping" | jq

# 2. Le webhook est protégé (401 = bon signe)
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "$BASE/functions/v1/serdipay/webhook" \
  -H "Content-Type: application/json" -d '{}'

# 3. Simulation d'un webhook signé (sur un paiement réellement ouvert)
BODY='{"reference":"SER-AAAAMMJJ-XXXXXXXX","status":"paid","amount":30000}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SERDIPAY_WEBHOOK_SECRET" -hex | sed 's/^.* //')
curl -i -X POST "$BASE/functions/v1/serdipay/webhook" \
  -H "Content-Type: application/json" \
  -H "x-serdipay-signature: $SIG" \
  --data "$BODY"
```

Réponses attendues : `401 SIGNATURE_INVALIDE` sans signature, puis
`{"ok":true,…}` avec la bonne signature.

---

## 6. 🔴 URL et IP à transmettre à SerdiPay

### 6.1 URL de base

```
https://pqzcliibocndiyqbyddr.supabase.co
```

### 6.2 URL de rappel (webhook) — **c'est celle-ci que SerdiPay doit appeler**

```
https://pqzcliibocndiyqbyddr.supabase.co/functions/v1/serdipay/webhook
```

- Méthode : **POST**, corps JSON, en-tête de signature
  `x-serdipay-signature` (HMAC-SHA256 hex ou base64 du **corps brut**).
- Un **GET** sur cette URL renvoie `200 {"ok":true,"webhook":"actif"}` — utile
  si SerdiPay valide l'URL avant activation.
- Réponses : `200` traité · `401` signature invalide · `422` montant incorrect
  · `500` erreur interne (SerdiPay doit **rejouer**).

### 6.3 Adresses IP publiques constatées

Résolution du domaine le **27/10/2026** :

| Adresse | Détail |
|---|---|
| `104.18.38.10` | Cloudflare (anycast), AS13335 |
| `172.64.149.246` | Cloudflare (anycast), AS13335 |

> ⚠️ **Ces IP ne doivent PAS être utilisées pour un filtrage.** Le domaine
> `*.supabase.co` est servi par Cloudflare en **anycast** : les adresses sont
> partagées par des milliers de clients et **changent sans préavis**. Un
> allowlist d'IP casserait l'intégration silencieusement.

**À transmettre à SerdiPay :** uniquement le **domaine** (§6.2), pas d'IP.

Si SerdiPay **exige** une IP fixe, trois options :

1. demander à activer une **IP dédiée** sur le projet Supabase (offre payante) ;
2. passer par un **reverse proxy à IP fixe** (VPS) qui relaie
   `POST /webhook` vers Supabase ;
3. demander à SerdiPay d'autoriser le **nom d'hôte** plutôt que l'IP
   (recommandé — c'est le fonctionnement normal des webhooks).

> ▶ Procédure détaillée, **message prêt à envoyer** à SerdiPay et
> configurations du relais : [`relais_ip_fixe_serdipay.md`](relais_ip_fixe_serdipay.md)
> + [`tools/relais_serdipay/`](../tools/relais_serdipay/README.md).

**Revérifier les IP à tout moment :**

```bash
getent ahostsv4 pqzcliibocndiyqbyddr.supabase.co | awk '{print $1}' | sort -u
```

Les IP peuvent aussi être vues côté SerdiPay : l'appel sortant de l'Edge
Function vers leur API provient de la plage Cloudflare/Supabase (non garantie).
Si SerdiPay whitelist nos appels **sortants**, la même conclusion s'applique :
demander une IP dédiée ou une autorisation par domaine.

---

## 7. Adapter au contrat réel de SerdiPay

Tout est concentré dans la section **4** de
`supabase/functions/serdipay/index.ts` :

| Fonction | Rôle |
|---|---|
| `construireCorpsInitier` | Corps envoyé à la création du paiement |
| `extraireUrlPaiement` | Où trouver le lien hébergé dans la réponse |
| `extraireReferenceFournisseur` | Où trouver l'id de transaction |
| `extraireWebhook` | Où trouver référence / statut / montant dans le webhook |

Les extracteurs acceptent déjà **plusieurs variantes** (`payment_url`,
`checkout_url`, `redirect_url`, `data.url`, `amount`/`montant`,
`status`/`statut`, `transaction_id`/`id`…). Si la doc SerdiPay diffère,
modifier **uniquement** ces quatre fonctions, puis redéployer.

---

## 8. Sécurité — points à ne pas affaiblir

- **Aucune policy d'écriture** sur `paiements_serdipay` : seul le `service_role`
  écrit, via des fonctions `security definer`.
- `rpc_serdipay_confirmer`, `rpc_serdipay_definir_lien` et `rpc_serdipay_echec`
  sont `execute` **uniquement pour `service_role`**.
- `auth.uid()` est absent dans un webhook : la confirmation emprunte l'identité
  du compte **FINANCE_LAPERLE** le temps de l'appel au moteur d'abonnement
  (`set_config(..., true)` = portée transaction). Ne pas transformer cet
  emprunt en droit permanent.
- Un écart de montant > **0,01** met le paiement en `echoue` et renvoie `422`.
- Le webhook ne crédite **jamais** un paiement inconnu : il répond
  `200 {ignore:true}` pour éviter une tempête de réessais.

---

## 9. Dépannage

| Symptôme | Cause probable | Correctif |
|---|---|---|
| `401 UNAUTHORIZED_NO_AUTH_HEADER` sur `/initier` | « Verify JWT » encore actif **et** pas d'en-tête `Authorization` | Normal côté app (elle envoie le JWT) ; désactiver la vérification pour le webhook |
| `/ping` → `fournisseurConfigure:false` | Secrets absents | Créer `SERDIPAY_BASE_URL` + clé/OAuth |
| `503 SERDIPAY_NON_CONFIGURE` dans l'app | Idem | Idem |
| `401 SIGNATURE_INVALIDE` dans les logs SerdiPay | Secret différent des deux côtés, ou signature calculée sur le JSON re-sérialisé | Comparer les secrets ; signer le **corps brut** |
| Webhook `200 {ignore:true}` | Référence interne absente du payload | Ajouter le champ dans `extraireWebhook` ou demander à SerdiPay de renvoyer `reference` |
| `MONTANT_INCORRECT` | SerdiPay envoie un montant en centimes, ou des frais déduits | Aligner l'unité (voir §7) ; ne jamais créditer un montant partiel sans décision métier |
| `ACTEUR_FINANCE_INTROUVABLE` | Aucun compte `FINANCE_LAPERLE`/`SUPER_ADMIN` | Vérifier `utilisateurs.new_role` |
| Paiement bloqué `en_attente` | Webhook non reçu | `POST /statut` interroge SerdiPay en secours ; vérifier l'URL de rappel |

---

## 10. Recette de bout en bout (à faire avec SerdiPay)

1. Créer un compte de test avec un abonnement **impayé** (solde > 0).
2. Ouvrir **Mon dossier d'activation → Payer maintenant**.
3. Saisir un numéro de test, choisir un opérateur → vérifier la ligne créée :

```sql
select reference, montant, devise, statut, operateur, provider_reference,
       expire_le, created_at
  from public.paiements_serdipay
 order by created_at desc
 limit 5;
```

4. Payer (ou simuler le webhook signé du §5.5).
5. Vérifier le crédit :

```sql
select reference, statut, paye_le from public.paiements_serdipay
 where reference = 'SER-…';

select statut, montant_total_du, montant_deja_paye, solde_restant,
       date_expiration
  from public.entreprises
 where id = (select entreprise_id from public.paiements_serdipay
              where reference = 'SER-…');
```

6. Rejouer **le même** webhook → doit répondre `{deja:true}` **sans** modifier
   `montant_deja_paye`.
