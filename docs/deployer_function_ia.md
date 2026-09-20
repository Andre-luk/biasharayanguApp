# Déployer l'Edge Function `agent-ia` (assistant IA)

**Constaté le 20/09/2026 :** l'application affiche « *l'assistant n'est pas
encore déployé (edge function agent-ia absente ou non publiée)* ». Ce n'est pas
un bug de l'application : le serveur répond réellement

```json
{"code":"NOT_FOUND","message":"Requested function was not found"}
```

⚠️ **Une fonction visible dans le Dashboard n'est pas forcément DÉPLOYÉE** :
créer/éditer une fonction dans l'éditeur en ligne ne la publie qu'après un clic
sur **Deploy**. Tant que ce clic n'est pas fait, l'application reçoit un 404.

---

## Méthode 1 (recommandée) — le script, en une commande

Dans un terminal, à la racine du projet :

```bash
bash tools/deploy_agent_ia.sh
```

Le script :

1. vérifie que le code source `supabase/functions/agent-ia/index.ts` existe ;
2. **demande votre « Personal Access Token » Supabase** (saisie invisible — le
   jeton ne s'affiche pas et n'est jamais transmis à personne) ;
   * où le créer : Dashboard Supabase → votre compte (en haut à droite) →
     **Access Tokens** → *Generate new token* → copier la valeur `sbp_…` ;
3. déploie la fonction sur le projet de l'application
   (`npx supabase functions deploy agent-ia --project-ref pqzcliibocndiyqbyddr`) ;
4. **vérifie** en appelant la fonction : `401/403` = déployée et protégée
   ✅ (comportement attendu), `404` = toujours pas publiée ❌.

## Méthode 2 — le Dashboard, à la souris

1. Dashboard Supabase → projet **de l'application** (`pqzcliibocndiyqbyddr`) →
   **Edge Functions** ;
2. ouvrir `agent-ia` (ou la créer avec ce nom **exact**) ;
3. coller le contenu de `supabase/functions/agent-ia/index.ts` ;
4. cliquer **Deploy** et attendre la fin du build (1–2 min) ;
5. onglet **Logs** : l'invocation doit apparaître lors d'un test dans l'app.

## Secret obligatoire

Dashboard → **Project Settings → Edge Functions → Secrets** :

| Nom | Valeur |
|---|---|
| `DEEPSEEK_API_KEY` | votre clé API DeepSeek (`sk-…`) |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` sont fournis
automatiquement par la plateforme — ne les créez pas à la main.
Sans le secret, la fonction répond `503 SECRET_MANQUANT` (message affiché tel
quel dans l'application).

## SQL préalable (déjà exécuté ✅)

| Migration | Contenu |
|---|---|
| `20260916000014_module13_agent_ia.sql` | tables (config, quotas, achats, conversations, actions) |
| `20260916000015_module13_agent_ia_rpc.sql` | débit atomique des quotas |
| `20260916000016_module13_achats_rpc.sql` | achats, attribution, configuration |

## Vérifier en ligne de commande (sans secret utilisateur)

```bash
# Extrait l'URL + la clé publique de l'app, puis appelle la fonction :
#   404 → pas déployée    401/403 → OK    500/503 → secret manquant
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  -X POST "https://pqzcliibocndiyqbyddr.supabase.co/functions/v1/agent-ia" \
  -H "apikey: <clé publique de lib/main.dart>" \
  -H "Content-Type: application/json" -d '{}'
```

## Déploiements suivants

Après toute modification de `supabase/functions/agent-ia/index.ts`, relancer la
méthode 1 (le script ne fait que republier la version du dépôt). Le fichier
`supabase/config.toml` (sans secret) déclare la fonction pour la CLI.
