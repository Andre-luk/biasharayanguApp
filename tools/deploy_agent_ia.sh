#!/usr/bin/env bash
# ============================================================================
#  biashara_yangu — DÉPLOIEMENT DE L'EDGE FUNCTION « agent-ia »
# ============================================================================
#  Publie (ou met à jour) la fonction Edge de l'assistant IA sur le projet
#  Supabase de l'application, puis VERIFIE qu'elle répond.
#
#  POURQUOI CE SCRIPT
#    `curl` a montré que la fonction est ABSENTE de la passerelle du projet
#    (« Requested function was not found ») alors que le code source existe
#    dans le dépôt (`supabase/functions/agent-ia/index.ts`). Une fonction
#    visible dans le Dashboard n'est PAS forcément DÉPLOYÉE : il faut cliquer
#    « Deploy » (ou lancer ce script).
#
#  COMMENT L'UTILISER
#    1. créer un « Personal Access Token » : Dashboard Supabase →
#       compte (en haut à droite) → Access Tokens → Generate new token ;
#    2. lancer :   bash tools/deploy_agent_ia.sh
#    3. coller le jeton quand il est demandé (la saisie est INVISIBLE :
#       le jeton ne s'affiche pas, n'est pas écrit dans l'historique et n'est
#       jamais envoyé ailleurs) ;
#    4. le script déploie puis teste la fonction et vous dit le résultat.
#
#  PREREQUIS
#    • Node.js installé (le script utilise `npx supabase@latest`) ;
#    • le secret DEEPSEEK_API_KEY défini dans
#      Dashboard → Project Settings → Edge Functions → Secrets
#      (sinon la fonction répondra « SECRET_MANQUANT »).
#
#  AUCUN SECRET DANS CE FICHIER : le jeton est saisi au clavier, à l'exécution.
# ============================================================================

set -u

REF="pqzcliibocndiyqbyddr"
FONCTION="agent-ia"
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$RACINE/supabase/functions/$FONCTION/index.ts"

echo "============================================================"
echo " Déploiement de l'Edge Function « $FONCTION »"
echo " Projet : $REF"
echo "============================================================"
echo

# --- 1. Le code source est-il présent ? --------------------------------
if [ ! -f "$SOURCE" ]; then
  echo "❌ Code source introuvable : $SOURCE"
  exit 1
fi
echo "✅ Code source : $SOURCE ($(wc -l < "$SOURCE") lignes)"
echo

# --- 2. Outillage ------------------------------------------------------
if ! command -v npx >/dev/null 2>&1; then
  echo "❌ Node.js/npx est requis (https://nodejs.org)."
  exit 1
fi
echo "✅ npx $(npx --version) détecté"
echo

# --- 3. Jeton d'accès (fichier privé OU saisie INVISIBLE) --------------
#  Deux façons de fournir le jeton, dans les deux cas il ne s'affiche JAMAIS
#  et n'est transmis à personne :
#    a) le déposer une fois dans un fichier privé (permissions 600) :
#         read -rsp "Jeton Supabase : " T; printf '%s' "$T" > ~/.supabase_token
#         chmod 600 ~/.supabase_token; unset T
#    b) le saisir au clavier quand ce script le demande (saisie masquée).
JETON_FICHIER="$HOME/.supabase_token"

if [ -f "$JETON_FICHIER" ]; then
  SB_TOKEN="$(tr -d '\r\n' < "$JETON_FICHIER")"
  echo "✅ Jeton lu dans $JETON_FICHIER (fichier privé, contenu non affiché)"
else
  echo "Il faut un « Personal Access Token » Supabase (commence par sbp_) :"
  echo "  Dashboard → votre compte → Access Tokens → Generate new token."
  echo
  echo "Astuce pour ne plus le ressaisir (fichier privé, jamais affiché) :"
  echo "  read -rsp \"Jeton Supabase : \" T; printf '%s' \"\$T\" > ~/.supabase_token; chmod 600 ~/.supabase_token; unset T"
  echo
  read -rsp "Collez le jeton (la saisie reste invisible) : " SB_TOKEN
  echo
fi

if [ -z "$SB_TOKEN" ]; then
  echo "❌ Aucun jeton — rien n'a été fait."
  exit 1
fi
case "$SB_TOKEN" in
  sbp_*) : ;;
  *) echo "⚠️  Le jeton ne commence pas par « sbp_ » : vérifiez-le si le déploiement échoue." ;;
esac
export SUPABASE_ACCESS_TOKEN="$SB_TOKEN"
echo "✅ Jeton reçu ($(printf '%s' "$SB_TOKEN" | wc -c) caractères, non affiché)"
echo

# --- 4. Déploiement ----------------------------------------------------
echo "--- Déploiement (peut prendre 1 à 2 minutes) ---"
cd "$RACINE" || exit 1
if npx --yes supabase@latest functions deploy "$FONCTION" --project-ref "$REF"; then
  echo
  echo "✅ Déploiement terminé."
else
  echo
  echo "❌ Le déploiement a échoué."
  echo "   • « 403 … does not have the necessary privileges » → le jeton est en"
  echo "     LECTURE SEULE : régénérez-le (Access Tokens) en laissant TOUTES les"
  echo "     portées (« scopes ») cochées, puis relancez ce script."
  echo "   • Autres pistes : jeton expiré, projet non accessible avec ce jeton,"
  echo "     pas de connexion internet. Auto-test : npx supabase projects list"
  exit 1
fi
echo

# --- 4 bis. Secret de la clé IA ---------------------------------------
echo "--- Secret DEEPSEEK_API_KEY (clé de l'IA) ---"
SECRETS=$(npx --yes supabase@latest secrets list --project-ref "$REF" 2>/dev/null || echo '')
if printf '%s' "$SECRETS" | grep -q '"name":"DEEPSEEK_API_KEY"'; then
  echo "✅ Le secret DEEPSEEK_API_KEY est défini."
else
  echo "⚠️  Le secret DEEPSEEK_API_KEY est ABSENT : la fonction répondrait"
  echo "    « SECRET_MANQUANT » (les autres noms ne sont pas lus par le code)."
  read -rsp "Collez la clé DeepSeek (sk-…), ou Entrée pour la définir plus tard : " DSK
  echo
  if [ -n "$DSK" ]; then
    if npx --yes supabase@latest secrets set "DEEPSEEK_API_KEY=$DSK" --project-ref "$REF"; then
      echo "✅ Secret enregistré."
    else
      echo "❌ Échec de l'enregistrement du secret."
    fi
    unset DSK
  else
    echo "ℹ️  Ignoré (à définir dans Dashboard → Project Settings → Edge Functions → Secrets)."
  fi
fi
echo

# --- 4 ter. Fonctions présentes (nom exact attendu) -------------------
echo "--- Fonctions publiées sur le projet ---"
npx --yes supabase@latest functions list --project-ref "$REF" 2>/dev/null \
  | python3 -c "
import sys,json
raw=sys.stdin.read()
try:
    d=json.loads(raw)
    for f in d.get('functions',[]):
        print(f\"  - {f['slug']:24} {f['status']}\")
    if not d.get('functions'):
        print('  (aucune)')
except Exception:
    print('  (liste indisponible)')
" 2>/dev/null || echo "  (liste indisponible)"
echo "⚠️  L'application appelle le slug EXACT « $FONCTION » : toute autre"
echo "    fonction (ex. nom généré automatiquement type « clever-action »)"
echo "    reste injoignable par l'app."
echo

# --- 5. Vérification par appel réel (sans secret) ----------------------
MAIN="$RACINE/lib/main.dart"
ANON=$(grep -A1 "anonKey:" "$MAIN" | grep -o "'eyJ[A-Za-z0-9._-]*'" | head -1 | tr -d "'")
if [ -z "$ANON" ]; then
  echo "⚠️  Clé publique introuvable dans lib/main.dart : vérification ignorée."
  exit 0
fi

echo "--- Vérification : appel de la fonction ---"
CODE=$(curl -s -o /tmp/ef_deploy_check.json -w "%{http_code}" \
  -X POST "https://$REF.supabase.co/functions/v1/$FONCTION" \
  -H "apikey: $ANON" -H "Content-Type: application/json" -d '{}')
echo "HTTP $CODE"
head -c 300 /tmp/ef_deploy_check.json; echo
echo

case "$CODE" in
  404)
    echo "❌ Toujours 404 : la fonction n'est pas publiée sur ce projet."
    echo "   Vérifiez que le projet « $REF » est bien celui de l'application."
    exit 1
    ;;
  401|403)
    echo "✅ La fonction RÉPOND (401/403 = elle refuse l'appel sans session,"
    echo "   c'est exactement le comportement attendu)."
    echo "   Elle est donc bien déployée : relancez l'application et testez"
    echo "   l'assistant IA (Paramètres → Assistant IA)."
    exit 0
    ;;
  500|503)
    echo "⚠️  La fonction existe mais renvoie une erreur serveur ($CODE)."
    echo "   Cause la plus fréquente : le secret DEEPSEEK_API_KEY n'est pas"
    echo "   défini (Dashboard → Project Settings → Edge Functions → Secrets)."
    echo "   Détail :"; head -c 300 /tmp/ef_deploy_check.json; echo
    exit 0
    ;;
  *)
    echo "ℹ️  Réponse inattendue (HTTP $CODE) — voici le corps pour analyse."
    exit 0
    ;;
esac
