# Relais à IP fixe pour SerdiPay

Le backend Biashara Yangu est sur Supabase (Cloudflare anycast) : **aucune IP
publique stable n'est disponible**. Ces fichiers servent uniquement si SerdiPay
exige une IP fixe avant de fournir ses clés.

📄 Analyse complète et message à envoyer à SerdiPay :
[`docs/relais_ip_fixe_serdipay.md`](../../docs/relais_ip_fixe_serdipay.md)

## Contenu

| Fichier | Sens | Rôle |
|---|---|---|
| `Caddyfile` | **Entrant** (SerdiPay → nous) | Termine le TLS sur le VPS, transmet le corps brut à `…/functions/v1/serdipay/webhook`. Seul `/functions/v1/serdipay/*` est exposé. |
| `tinyproxy.conf` | **Sortant** (nous → SerdiPay) | Proxy direct à IP fixe, restreint aux domaines `serdipay.com` / `serdipay.cloud`. À n'activer que si SerdiPay whitelist nos appels. |
| `serdipay.filter` | Sortant | Liste blanche des destinations du proxy (anti-proxy ouvert). |
| `verifier_webhook.sh` | Recette | Teste 401 (sans signature), 401 (mauvaise signature), 200 (bonne signature). Secret saisi en **invisible**. |

## Mise en route (résumé)

```bash
# 1. DNS : paiements.biasharayangu.cd → IP du VPS
# 2. Entrant
sudo apt install -y caddy
sudo cp Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
curl -s https://paiements.biasharayangu.cd/functions/v1/serdipay/webhook

# 3. Firewall
sudo ufw allow 22,80,443/tcp && sudo ufw enable
```

L'IP à déclarer à SerdiPay est celle du VPS :

```bash
curl -4 -s ifconfig.me
```

## ⚠️ Règles à ne pas contourner

- Ne jamais exposer **toute** l'API Supabase via le relais (matcher
  `/functions/v1/serdipay/*` uniquement).
- Ne jamais désactiver la vérification de signature du webhook « pour tester ».
- Le relais ne doit contenir **aucune clé** : il ne fait que transmettre.
- Un proxy sortant ouvert sur Internet est immédiatement abusé : port fermé,
  accès par VPN ou liste blanche.
