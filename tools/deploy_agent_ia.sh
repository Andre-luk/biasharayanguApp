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

# --- 3. Jeton d'accès (saisie INVISIBLE) -------------------------------
echo "Il faut un « Personal Access Token » Supabase (commence par sbp_) :"
echo "  Dashboard → votre compte → Access Tokens → Generate new token."
echo
read -rsp "Collez le jeton (la saisie reste invisible) : " SB_TOKEN
echo
if [ -z "$SB_TOKEN" ]; then
  echo "❌ Aucun jeton saisi — rien n'a été fait."
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
  echo "   Pistes : jeton invalide/expiré, projet non accessible avec ce jeton,"
  echo "   ou pas de connexion internet. Auto-test :  npx supabase projects list"
  exit 1
fi
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
