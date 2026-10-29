# Relais à IP fixe pour SerdiPay

Le backend Biashara Yangu est sur Supabase (Cloudflare anycast) : **aucune IP
publique stable n'est disponible**. Ces fichiers servent uniquement si SerdiPay
exige une IP fixe avant de fournir ses clés.

📄 Analyse complète et message à envoyer à SerdiPay :
[`docs/relais_ip_fixe_serdipay.md`](../../docs/relais_ip_fixe_serdipay.md)

## Contenu

| Fichier | Sens | Rôle |
|---|---|---|
| `installer_relais.sh` | **Tout-en-un** | Installe Caddy, écrit la configuration, ouvre le pare-feu, attend le certificat et affiche le bloc à envoyer à SerdiPay. **C'est le point d'entrée.** |
| `Caddyfile` | **Entrant** (SerdiPay → nous) | Termine le TLS sur le VPS, transmet le corps brut à `…/functions/v1/serdipay/webhook`. Seul `/functions/v1/serdipay/*` est exposé. Modèle de référence (le script génère le sien). |
| `tinyproxy.conf` | **Sortant** (nous → SerdiPay) | Proxy direct à IP fixe, restreint aux domaines `serdipay.com` / `serdipay.cloud`. Variante si vous ne voulez pas passer par `/api` de Caddy. |
| `serdipay.filter` | Sortant | Liste blanche des destinations du proxy (anti-proxy ouvert). |
| `verifier_webhook.sh` | Recette | Teste 401 (sans signature), 401 (mauvaise signature), 200 (bonne signature). Secret saisi en **invisible**. |

## Mise en route — une commande

```bash
# sur un VPS Ubuntu 22.04/24.04 frais, en root
sudo bash installer_relais.sh --sortant
```

Sans domaine, le script utilise `<ip>.nip.io` : nom public résolvant vers l'IP
du VPS, avec un **vrai certificat Let's Encrypt**. SerdiPay obtient donc une
URL HTTPS valide **et** une IP fixe.

Le script affiche à la fin :

```
 IP serveur (fixe) : 51.79.x.x
 URL de callback   : https://51.79.x.x.nip.io/functions/v1/serdipay/webhook
```

⚠️ Ouvrez les ports **80** et **443** dans le pare-feu du fournisseur
(security group), sinon la validation du certificat échoue.

Guide complet : [`docs/relais_ip_fixe_serdipay.md`](../../docs/relais_ip_fixe_serdipay.md)

## ⚠️ Règles à ne pas contourner

- Ne jamais exposer **toute** l'API Supabase via le relais (matcher
  `/functions/v1/serdipay/*` uniquement).
- Ne jamais désactiver la vérification de signature du webhook « pour tester ».
- Le relais ne doit contenir **aucune clé** : il ne fait que transmettre.
- Un proxy sortant ouvert sur Internet est immédiatement abusé : port fermé,
  accès par VPN ou liste blanche.
