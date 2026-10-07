#!/usr/bin/env bash
# ============================================================================
#  biashara_yangu — TEST DE L'EDGE FUNCTION « admin-agents » (module 21 quinquies)
# ============================================================================
#  Vérifie que l'API de service destinée à BIASHARA GROUP répond correctement :
#  recrutement / suivi des agents terrain (fiche, journal, liste, création,
#  désactivation).
#
#  COMMENT L'UTILISER
#    1. lancer :   bash tools/test_admin_agents.sh
#    2. coller le jeton de service `BG_ADMIN_TOKEN` quand il est demandé
#       (la saisie est INVISIBLE : le jeton n'est ni affiché, ni écrit dans
#       l'historique, ni enregistré sur le disque) ;
#    3. le script enchaîne les 4 appels et affiche les réponses.
#
#  AUCUN SECRET DANS CE FICHIER.
#
#  DIAGNOSTIC RAPIDE (si un appel échoue)
#  --------------------------------------
#    405 METHODE_INVALIDE / « Utilisez POST. »
#        → la fonction contient le code d'« agent-ia » : coller le contenu de
#          supabase/functions/admin-agents/index.ts et redéployer.
#    401 UNAUTHORIZED_NO_AUTH_HEADER / « Missing authorization header »
#        → la passerelle exige encore un JWT : désactiver « Verify JWT » sur la
#          fonction (Edge Functions → admin-agents → Settings).
#    401 JETON_INVALIDE
#        → bon code, mais le jeton saisi ne correspond pas au secret
#          BG_ADMIN_TOKEN (vérifier la casse, les espaces, les guillemets).
#    503 SECRET_MANQUANT … BG_ADMIN_TOKEN
#        → le secret n'est pas défini sur la fonction.
#    503 NON_DEPLOYE
#        → exécuter la migration 20260916000051_api_biashara_group_agents.sql.
# ============================================================================

set -u

REF="pqzcliibocndiyqbyddr"
B="https://$REF.functions.supabase.co"
BASE="$B/admin-agents"

# Clé anon PUBLIQUE (extraite de lib/main.dart) : elle n'est pas secrète.
ANON='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBxemNsaWlib2NuZGl5cWJ5ZGRyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA1NjAxMjksImV4cCI6MjA3NjEzNjEyOX0.t5XXsrOk_AFRwm-13LYz23-Q6jyFDXEDGNo6kjRDSlM'

# Agent témoin créé pendant les tests du cloisonnement (agent@espoir.com).
AGENT_ID="${AGENT_ID:-83162486-0478-4314-bb8e-9bdee71cc516}"

echo "============================================================"
echo " Test de l'API « $BASE »"
echo " Projet : $REF"
echo "============================================================"
echo

if ! command -v curl >/dev/null 2>&1; then
  echo "❌ curl est requis."
  exit 1
fi

# --- Saisie INVISIBLE du jeton de service ------------------------------
read -rsp "Jeton de service (BG_ADMIN_TOKEN) : " TOKEN
echo
echo

if [ -z "${TOKEN:-}" ]; then
  echo "❌ Aucun jeton saisi."
  exit 1
fi

# En-têtes communs. `Authorization` reste utile si « Verify JWT » est encore
# activé ; il est inoffensif sinon.
HDR=(-H "Authorization: Bearer $ANON" -H "x-bg-token: $TOKEN")

succes=0
echecs=0

# $1 = libellé · $2 = URL · $3 = méthode (défaut GET) · $4 = corps JSON
appeler() {
  local libelle="$1" url="$2" methode="${3:-GET}" corps="${4:-}"
  local fichier="/tmp/aa_$$.json" code

  if [ -n "$corps" ]; then
    code=$(curl -s -o "$fichier" -w "%{http_code}" -X "$methode" \
      "${HDR[@]}" -H "Content-Type: application/json" -d "$corps" "$url")
  else
    code=$(curl -s -o "$fichier" -w "%{http_code}" -X "$methode" \
      "${HDR[@]}" "$url")
  fi

  echo "── [$code] $libelle"
  echo "   $url"
  if [ "$code" = "200" ]; then
    head -c 900 "$fichier"; echo
    succes=$((succes + 1))
  else
    cat "$fichier"; echo
    echecs=$((echecs + 1))
  fi
  echo
  rm -f "$fichier"
}

# --- 1. ping -----------------------------------------------------------
appeler "Ping du service" "$BASE/ping"

# --- 2. liste des agents ----------------------------------------------
appeler "Liste des agents" "$BASE/agents"

# --- 3. fiche d'un agent ----------------------------------------------
appeler "Fiche de l'agent témoin" "$BASE/agents/$AGENT_ID"

# --- 4. journal unifié -------------------------------------------------
appeler "Journal unifié (5 dernières actions)" \
  "$BASE/agents/$AGENT_ID/journal?limite=5"

# --- Bilan -------------------------------------------------------------
echo "============================================================"
echo " Résultat : $succes appel(s) OK · $echecs échec(s)"
echo "============================================================"

if [ "$echecs" -eq 0 ]; then
  echo "✅ L'API est pleinement opérationnelle : Biashara Group peut"
  echo "   consommer $BASE avec l'en-tête « x-bg-token »."
else
  echo "⚠️  Corrigez les points ci-dessus puis relancez ce script."
  echo "   (voir la section DIAGNOSTIC en tête du script)"
fi
