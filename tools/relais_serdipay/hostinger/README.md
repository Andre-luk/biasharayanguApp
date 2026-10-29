# Relais à IP fixe sur Hostinger (hébergement mutualisé)

SerdiPay exige une **IP serveur fixe**. Un hébergement Hostinger en possède
une : l'adresse du serveur qui héberge vos sites. Inutile de louer un VPS — il
suffit d'y déposer deux fichiers.

## 1. Le sous-domaine ne consomme pas d'emplacement

Votre offre compte **3 sites, déjà utilisés** : un **sous-domaine** d'un site
existant (par exemple `serdipay.mondomaine.cd`) ne compte **pas** comme un
nouveau site. C'est la voie à suivre.

Hostinger → **Sites web** → votre domaine → **Sous-domaines** →
créer `serdipay`. Hostinger crée un dossier, du type :

```
/home/u123456789/domains/mondomaine.cd/public_html/serdipay/
```

Activez le **SSL gratuit** sur ce sous-domaine (bouton « SSL » → Installer).

## 2. Les deux fichiers

Copiez dans ce dossier :

| Fichier | Rôle |
|---|---|
| `relais.php` | Transmet les requêtes vers Supabase (entrant) et vers l'API SerdiPay (sortant). Corps brut préservé → la signature HMAC reste valide. |
| `.htaccess` | Réécrit `/functions/v1/serdipay/…` et `/api/…` vers `relais.php`. |

⚠️ Dans `relais.php`, remplacez **une seule ligne** :

```php
const JETON_RELAIS = 'CHANGEZ-CE-JETON-PAR-UNE-VALEUR-ALEATOIRE';
```

par une longue chaîne aléatoire (par exemple le résultat de
`openssl rand -hex 32`). Cette valeur sera ensuite déclarée dans Supabase sous
le nom `SERDIPAY_RELAIS_TOKEN`. Elle empêche que votre relais serve de proxy
ouvert vers l'API SerdiPay.

## 3. Vérifier en 10 secondes

Ouvrez dans un navigateur :

```
https://serdipay.mondomaine.cd/functions/v1/serdipay/webhook
```

Réponse attendue :

```json
{"ok":true,"service":"serdipay","webhook":"actif"}
```

Si vous obtenez une page 404 Hostinger, la réécriture n'est pas active :
vérifiez que `mod_rewrite` est bien disponible (il l'est sur Hostinger) et que
le `.htaccess` est bien dans le **même dossier** que `relais.php`.

## 4. Trouver l'IP fixe à déclarer

Hostinger → **Tableau de bord** → votre hébergement → **Détails** →
**Adresse IP du serveur** (ou « IP partagée »). Elle est **fixe** tant que
votre compte reste sur ce serveur.

Vérification depuis votre ordinateur :

```bash
curl -s https://serdipay.mondomaine.cd/functions/v1/serdipay/webhook
curl -s -o /dev/null -w '%{remote_ip}\n' https://serdipay.mondomaine.cd/
```

La seconde commande affiche l'IP que SerdiPay verra : c'est celle à leur
communiquer.

## 5. Ce qu'il faut envoyer à SerdiPay

> Bonjour,
>
> Voici l'**IP serveur fixe** demandée :
>
> - **IP fixe** : `<IP_HOSTINGER>`
> - **URL de callback** : `https://serdipay.mondomaine.cd/functions/v1/serdipay/webhook`
>   (POST, JSON, signature HMAC-SHA256 du corps brut)
> - **URL de notre site** : `https://biashara-yangu-app.netlify.app`
>
> Nos appels vers votre API sortent également de cette IP : ils passent par
> `https://serdipay.mondomaine.cd/api/…`, qui relaie vers votre API officielle.
>
> L'URL de callback est déjà en production et répond
> `{"ok":true,"service":"serdipay","webhook":"actif"}`.

## 6. Côté Supabase, après réception des identifiants

**Project Settings → Edge Functions → Secrets** :

| Secret | Valeur |
|---|---|
| `SERDIPAY_WEBHOOK_SECRET` | secret fourni par SerdiPay |
| `SERDIPAY_API_KEY` *(ou)* `SERDIPAY_CLIENT_ID` + `SERDIPAY_CLIENT_SECRET` | leurs identifiants |
| `SERDIPAY_BASE_URL` | `https://serdipay.mondomaine.cd/api` |
| `SERDIPAY_RELAIS_TOKEN` | le jeton choisi à l'étape 2 |

## Ce que le relais ne fait pas

- Il ne stocke **aucune** donnée et ne journalise **aucun** corps de requête.
- Il n'expose **que** les deux chemins ci-dessus ; tout le reste répond 404.
- Il ne contient **aucune clé SerdiPay** : les identifiants restent dans les
  secrets Supabase.
