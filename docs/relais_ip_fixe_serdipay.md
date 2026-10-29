# SerdiPay exige une URL de rappel + une IP serveur : comment débloquer

> Situation : SerdiPay refuse de fournir les clés tant que le compte marchand
> n'a pas déclaré **(1) une URL de callback** et **(2) l'IP du serveur**.
> C'est un contrôle anti-fraude courant. Voici quoi répondre et comment le
> satisfaire sans casser l'architecture Supabase.

---

## 1. L'URL de callback : on l'a déjà

```
https://pqzcliibocndiyqbyddr.supabase.co/functions/v1/serdipay/webhook
```

- **Méthode attendue : POST** (JSON), en-tête de signature
  `x-serdipay-signature` = HMAC-SHA256 du corps brut.
- **Auto-vérification** : un `GET` sur cette URL doit renvoyer
  `200 {"ok":true,"service":"serdipay","webhook":"actif"}`.
- ⚠️ **Elle doit être DÉPLOYÉE avant de la déclarer**, sinon SerdiPay reçoit
  `404 {"code":"NOT_FOUND"}` et refuse le whitelist. Le déploiement ne demande
  **aucune clé SerdiPay** : `/ping` et `GET /webhook` fonctionnent déjà.
- Si vous prévoyez plusieurs comptes marchands, dites-le tout de suite
  (voir §4) : l'URL devra porter un discriminant (`?compte=`).

**Elle ne dépend d'aucun secret SerdiPay**, donc vous pouvez la transmettre
aujourd'hui — après le déploiement (§3).

---

## 2. L'IP serveur : c'est le vrai blocage

Notre backend est `*.supabase.co`, servi par **Cloudflare en anycast** :

| Constat (28/10/2026) | Conséquence |
|---|---|
| `104.18.38.10`, `172.64.149.246` | Adresses **partagées** par des milliers de clients Cloudflare |
| Rotation possible sans préavis | Un whitelist d'IP casse l'intégration **silencieusement** |
| Aucune IP ne nous « appartient » | Impossible de réserver une adresse sur ce domaine |

Et dans l'autre sens : les appels **sortants** de l'Edge Function vers l'API
SerdiPay partent eux aussi d'une infrastructure partagée, non garantie.

### Les quatre options

| # | Option | Effort | Coût | Recommandation |
|---|---|---|---|---|
| **A** | Faire autoriser le **domaine** au lieu de l'IP | 1 message | 0 | ⭐ **À tenter d'abord** |
| **B** | Relay **VPS à IP fixe** devant Supabase (et proxy sortant) | 1 h | ~5 €/mois | ⭐ Si A refusé |
| **C** | **IP dédiée** Supabase (add-on payant) | Support Supabase | Payant | Si vous voulez rester 100 % Supabase |
| **D** | Un compte marchand + une IP **par boutique** | Non supporté aujourd'hui | – | ❌ Voir §4 |

### Message à envoyer à SerdiPay (option A)

> Bonjour,
>
> Notre plateforme (Biashara Yangu) est hébergée sur Supabase et servie par
> Cloudflare : nous ne disposons donc **pas d'adresse IP stable** à déclarer.
>
> Merci de bien vouloir :
> 1. **whitelister notre URL de rappel** :
>    `https://pqzcliibocndiyqbyddr.supabase.co/functions/v1/serdipay/webhook`
>    (POST, JSON, signature HMAC-SHA256 dans l'en-tête `x-serdipay-signature`) ;
> 2. autoriser nos appels API **par nom d'hôte** plutôt que par IP.
>
> Si l'autorisation par IP est indispensable de votre côté, pouvez-vous nous
> indiquer si vous acceptez une **IP dédiée fournie par un relais** que nous
> contrôlerons, et nous communiquer en parallèle :
> – le format exact du corps de création de paiement,
> – le nom des champs de statut/montant dans le webhook,
> – le secret de signature que nous devons configurer.
>
> Nous pouvons fournir une IP fixe sous 24 h via un relais dédié si nécessaire.

### Option A refusée par SerdiPay (29/10/2026) — on passe à l'option B

Réponse reçue : « c'est OK pour l'URL du domaine, OK pour l'URL de callback,
mais il faut donner une IP fixe, sans cela rien ne va passer. »
⇒ Le relais à IP fixe devient **obligatoire**. Voici la mise en place, prête à
exécuter.

## 2 bis. Mise en place du relais à IP fixe (15 minutes)

### Ce qu'il faut

Un point d'entrée public avec **une IP fixe**. Trois choix possibles :

| Fournisseur | Prix | Remarque |
|---|---|---|
| **Hostinger — sous-domaine d'un site existant** ⭐ | **0 €** | L'hébergement possède déjà une IP fixe ; un sous-domaine ne consomme **pas** d'emplacement de site. Deux fichiers PHP suffisent (voir `tools/relais_serdipay/hostinger/`). |
| Oracle Cloud — Always Free | 0 € (carte pour vérification) | Instance « VM.Standard.E2.1.Micro », IP publique réservée |
| Hetzner / Contabo / Vultr | 4 à 6 € / mois | IP fixe incluse, mise en route simple |

> Le relais ne stocke **aucune** donnée de paiement : il transmet les requêtes.

### Voie Hostinger (retenue le 29/10/2026)

L'offre compte 3 sites, **tous déjà utilisés** : on crée donc un
**sous-domaine** (`serdipay.mondomaine.cd`), qui ne consomme aucun emplacement.

1. Hostinger → **Sites web** → le domaine → **Sous-domaines** → créer
   `serdipay`, puis activer le **SSL gratuit**.
2. Copier `relais.php` et `.htaccess` de `tools/relais_serdipay/hostinger/`
   dans le dossier du sous-domaine.
3. Dans `relais.php`, remplacer `JETON_RELAIS` par une valeur aléatoire
   (`openssl rand -hex 32`).
4. Vérifier : `https://serdipay.mondomaine.cd/functions/v1/serdipay/webhook`
   doit répondre `{"ok":true,"service":"serdipay","webhook":"actif"}`.
5. Relever l'**IP du serveur** dans Hostinger → tableau de bord → détails.

Guide détaillé : [`tools/relais_serdipay/hostinger/README.md`](../tools/relais_serdipay/hostinger/README.md).

### Voie VPS (alternative)

Un serveur Ubuntu, **une seule fois** :

| Fournisseur | Prix | Remarque |
|---|---|---|
| Oracle Cloud — Always Free | 0 € | « VM.Standard.E2.1.Micro », IP publique réservée |
| Hetzner / Contabo / Vultr | 4 à 6 € / mois | Mise en route plus simple |

### Le nom d'hôte : pas besoin d'acheter un domaine

Le script utilise par défaut **`<ip>.nip.io`** : un nom public qui résout
automatiquement vers l'IP du serveur. Caddy obtient un **vrai certificat
Let's Encrypt** dessus, donc SerdiPay reçoit une URL **HTTPS valide** *et*
une **IP fixe** — exactement ce qu'il demande.

Si vous préférez votre propre domaine (`paiements.biasharayangu.cd`), créez
l'enregistrement `A` vers l'IP du serveur et passez-le en paramètre.

### La commande (sur le serveur, en root)

```bash
# copier le script depuis le dépôt, puis :
sudo bash installer_relais.sh                # entrant seul
sudo bash installer_relais.sh --sortant      # entrant + sortant (recommandé)
sudo bash installer_relais.sh paiements.biasharayangu.cd --sortant
```

Le script : installe Caddy, écrit un `Caddyfile` qui **n'expose que**
`/functions/v1/serdipay/*` (tout le reste renvoie 404), ouvre 22/80/443,
attend le certificat, puis **affiche le bloc à envoyer à SerdiPay**.

⚠️ Ouvrez aussi les ports 80 et 443 dans le **pare-feu du fournisseur**
(security group / réseau cloud) : sans cela Let's Encrypt échoue et SerdiPay
reçoit une erreur TLS.

### Ce qu'il faut alors envoyer à SerdiPay

> Bonjour,
>
> Merci pour votre retour. Voici l'**IP serveur fixe** demandée :
>
> - **IP fixe** : `<IP_DU_RELAIS>`
> - **URL de callback** : `https://<HOTE>/functions/v1/serdipay/webhook`
>   (POST, JSON, signature HMAC-SHA256 du corps brut)
> - **URL de notre site** : `https://biashara-yangu-app.netlify.app`
>
> Nos **appels vers votre API** partent également de cette IP fixe ; ils sont
> dirigés vers `https://<HOTE>/api`, qui relaie vers votre API officielle.
>
> Cette adresse est déjà en production et répond correctement en GET
> (`{"ok":true,"service":"serdipay","webhook":"actif"}`).
>
> Merci de nous confirmer la mise en liste blanche de cette IP, puis de nous
> communiquer vos identifiants (clé d'API ou OAuth 2.0 `client_id` /
> `client_secret`), le secret de signature des webhooks avec le nom exact de
> l'en-tête, ainsi que le format du corps de création de paiement et les codes
> opérateurs attendus.

### Après réception des clés (2 minutes, dans Supabase)

Dashboard → **Project Settings → Edge Functions → Secrets** :

| Secret | Valeur |
|---|---|
| `SERDIPAY_WEBHOOK_SECRET` | le secret fourni par SerdiPay |
| `SERDIPAY_API_KEY` *(ou)* `SERDIPAY_CLIENT_ID` + `SERDIPAY_CLIENT_SECRET` | leurs identifiants |
| `SERDIPAY_BASE_URL` | `https://<HOTE>/api` (relais) ou `https://api.serdipay.com` si SerdiPay accepte l'IP directement |

Puis vérifier :

```bash
curl -s https://pqzcliibocndiyqbyddr.supabase.co/functions/v1/serdipay/ping
# → "fournisseurConfigure": true
bash tools/relais_serdipay/verifier_webhook.sh https://<HOTE>/functions/v1/serdipay/webhook
```

### Message prêt à envoyer (version 29/10/2026 — site en ligne)

> Bonjour,
>
> Voici les trois informations demandées pour l'activation du compte marchand
> **Biashara Yangu** :
>
> **1. URL du site (domaine)**
> `https://biashara-yangu-app.netlify.app`
>
> **2. URL de callback (webhook)**
> `https://pqzcliibocndiyqbyddr.supabase.co/functions/v1/serdipay/webhook`
> – méthode **POST**, corps **JSON** ;
> – signature **HMAC-SHA256** du corps brut dans l'en-tête
>   `x-serdipay-signature` (le nom de l'en-tête peut être adapté au vôtre) ;
> – cette URL est **déjà en production** : un `GET` dessus répond
>   `200 {"ok":true,"service":"serdipay","webhook":"actif"}`.
>
> **3. IP du serveur**
> Notre plateforme est hébergée sur **Supabase** et servie par **Cloudflare**
> (réseau anycast) : elle **ne dispose pas d'une adresse IP qui nous
> appartienne**. Les adresses observées sont partagées par des milliers de
> clients Cloudflare et peuvent changer sans préavis — une autorisation par IP
> casserait l'intégration silencieusement.
>
> Merci donc de **whitelister le nom d'hôte**
> `pqzcliibocndiyqbyddr.supabase.co` (et, pour nos appels sortants vers votre
> API, d'autoriser ce même nom d'hôte).
>
> Si votre politique exige malgré tout une IP fixe, nous pouvons mettre en place
> un **relais à IP dédiée** que nous contrôlons : dites-nous si cela vous
> convient et nous vous transmettrons l'adresse sous 24 h.
>
> Merci de nous communiquer en parallèle :
> – l'URL de base de votre API (test et production) ;
> – vos identifiants (clé d'API, ou OAuth 2.0 `client_id` / `client_secret`) ;
> – le secret de signature des webhooks et le nom exact de l'en-tête ;
> – le format du corps de création de paiement et les codes opérateurs
>   attendus (`orange`, `airtel`, `mpesa`, `afrimoney`, `card`…).

---

## 3. Déployer la fonction (prérequis pour valider l'URL)

Sans déploiement, l'URL renvoie `404 NOT_FOUND` et SerdiPay refusera le
whitelist.

1. **SQL Editor** → exécuter
   `supabase/migrations/20260916000079_passerelle_serdipay.sql`.
2. Dashboard → **Edge Functions → serdipay → Deploy**
   (« Verify JWT » **désactivé**), ou en CLI :

```bash
npx supabase functions deploy serdipay \
  --project-ref pqzcliibocndiyqbyddr --no-verify-jwt
```

3. Créer au minimum `SERDIPAY_WEBHOOK_SECRET` (une longue chaîne aléatoire —
   **la même** que celle déclarée à SerdiPay) :

```bash
openssl rand -hex 32
```

4. Vérifier :

```bash
curl -s https://pqzcliibocndiyqbyddr.supabase.co/functions/v1/serdipay/ping
curl -s https://pqzcliibocndiyqbyddr.supabase.co/functions/v1/serdipay/webhook
```

`SERDIPAY_BASE_URL` et la clé d'API ne pourront être renseignés
**qu'après** réception des identifiants ; d'ici là `/initier` répond
`503 SERDIPAY_NON_CONFIGURE` (normal, l'écran de paiement reste inactif mais
l'application fonctionne).

---

## 4. ⚠️ « Par compte marchand » : point à trancher

L'intégration actuelle suppose **UN SEUL compte marchand** : celui de
l'éditeur (Biashara Tech). Toutes les boutiques passent par ce compte, et
chaque paiement est identifié par la référence interne
`SER-AAAAMMJJ-XXXXXXXX` + le champ `metadata.reference_interne`.

| Scénario | Ce que ça implique |
|---|---|
| **1 compte plateforme** (recommandé) | Rien à changer. SerdiPay envoie l'argent à Biashara Tech, qui est déjà le créancier des abonnements. |
| **1 compte par boutique** | Il faut **une paire de clés par entreprise** (table de credentials chiffrée + `?compte=<slug>` dans l'URL de rappel). Évolution de ~1 jour, à planifier. |

👉 Répondez à SerdiPay : « **un seul compte marchand** pour la plateforme ;
le rattachement à la boutique est fait par notre référence interne ». Si vous
voulez vraiment un compte par boutique, dites-le avant la signature du
contrat (le tarif et le KYC changent).

---

## 5. Option B — relay VPS à IP fixe (si A échoue)

Matériel : un petit VPS (Hetzner CX22, Contabo VPS S, DigitalOcean 4 $…),
Debian/Ubuntu, **une IPv4 fixe**. Fichiers prêts dans `tools/relais_serdipay/`.

### 5.1 DNS

```
paiements.biasharayangu.cd.   A   <IP_DU_VPS>
```

### 5.2 Entrant (webhook SerdiPay → Supabase)

Caddy fournit le TLS automatiquement (fichier `Caddyfile` fourni) :

```bash
sudo apt install -y caddy
sudo cp Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
curl -s https://paiements.biasharayangu.cd/functions/v1/serdipay/webhook
```

Nouvelle URL à déclarer à SerdiPay :

```
https://paiements.biasharayangu.cd/functions/v1/serdipay/webhook
```

Le relais ne laisse passer **que** `/functions/v1/serdipay/*` (le reste
renvoie 404) : il ne transforme pas le VPS en proxy ouvert vers votre API
Supabase entière.

### 5.3 Sortant (Edge Function → SerdiPay), si SerdiPay whitelist nos appels

Le VPS peut aussi servir de **proxy direct** : SerdiPay ne voit alors que
l'IP du VPS (`tinyproxy.conf` fourni, restreint à `*.serdipay.com`).

- Si le runtime Supabase honore `HTTPS_PROXY`, il suffit de définir
  `HTTPS_PROXY=http://<ip_vps>:8888` en secret.
- Sinon, repli : ajout d'une variable `SERDIPAY_RELAIS_URL` dans l'Edge
  Function (le relais relaie l'appel à SerdiPay). Petite évolution de code,
  à demander — elle reste **sans effet sur la sécurité** (le relais ne
  contient aucune clé, il ne fait que transmettre avec l'IP fixe).

### 5.4 Durcissement minimum

- `ufw allow 22,80,443/tcp` puis `ufw enable` ; le port `8888` **fermé**
  au public (accès par VPN/privé ou allowlist des plages Supabase).
- `unattended-upgrades`, `fail2ban`, utilisateur non-root.
- Le relais ne stocke **rien** : pas de logs de corps, pas de disque.

---

## 6. Option C — IP dédiée Supabase

À demander au support Supabase (« dedicated IPv4 for Edge Functions »).
Avantage : zéro infrastructure. Inconvénient : offre payante, et il faut
**quand même** whitelister les IP de SerdiPay de notre côté si vous voulez
filtrer les webhooks (ce que nous ne faisons pas : nous signons).

---

## 7. Récapitulatif à envoyer maintenant

| Élément | Valeur |
|---|---|
| URL de callback | `https://pqzcliibocndiyqbyddr.supabase.co/functions/v1/serdipay/webhook` |
| Méthode | `POST`, JSON, HMAC-SHA256 (`x-serdipay-signature`) |
| Secret de signature | `openssl rand -hex 32` → à configurer **des deux côtés** |
| IP serveur | **Aucune IP stable** (Cloudflare anycast) → demander autorisation par domaine, ou fournir l'IP d'un relais (option B) |
| Comptes marchands | **1 seul** (plateforme) |
| Environnement de test | demandez à SerdiPay un *sandbox* + identifiants de test |
