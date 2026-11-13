#!/usr/bin/env bash
# =============================================================================
#  Vérification « live » du module 36 (lots pharmacie) — SANS afficher de secret.
#
#  Pré-requis :
#    ~/.config/biashara/supabase.env  (voir tools/live/README.md, chmod 600)
#
#  Usage :
#    bash tools/live/verifier_module36.sh
#
#  Ce script ne fait que : connexion de test, lectures, appels de diagnostic.
#  Il n'imprime JAMAIS le mot de passe, la clé anon ni le jeton d'accès.
# =============================================================================
set -uo pipefail

FICHIER="${SUPABASE_ENV:-$HOME/.config/biashara/supabase.env}"

if [[ ! -f "$FICHIER" ]]; then
  echo "❌ Fichier de secrets absent : $FICHIER"
  echo "   → voir tools/live/README.md (section « Où mettre les identifiants »)."
  exit 2
fi

# Charge les variables sans les afficher.
set -a
# shellcheck disable=SC1090
source "$FICHIER"
set +a

for variable in SUPABASE_URL SUPABASE_ANON_KEY TEST_EMAIL TEST_PASSWORD; do
  if [[ -z "${!variable:-}" ]]; then
    echo "❌ Variable $variable vide dans $FICHIER"
    exit 2
  fi
done

BASE="${SUPABASE_URL%/}"
OK=0
KO=0

verdict_ok() { echo "✅ $1"; OK=$((OK + 1)); }
verdict_ko() { echo "❌ $1"; KO=$((KO + 1)); }
verdict_info() { echo "⚠️  $1"; }

# -----------------------------------------------------------------------------
# 1. Connexion du compte de TEST
# -----------------------------------------------------------------------------
CORPS_LOGIN="$(
  TEST_EMAIL="$TEST_EMAIL" TEST_PASSWORD="$TEST_PASSWORD" python3 - <<'PY'
import json, os
print(json.dumps({
    "email": os.environ.get("TEST_EMAIL", ""),
    "password": os.environ.get("TEST_PASSWORD", ""),
}))
PY
)"

REPONSE_LOGIN="$(
  curl -sS --max-time 20 \
    -X POST "$BASE/auth/v1/token?grant_type=password" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" \
    --data "$CORPS_LOGIN"
)"

TOKEN="$(
  printf '%s' "$REPONSE_LOGIN" | python3 -c \
    'import sys, json; print(json.load(sys.stdin).get("access_token", ""))' 2>/dev/null
)"

if [[ -z "$TOKEN" ]]; then
  verdict_ko "Connexion de test refusée (compte inexistant, mot de passe faux ou e-mail non confirmé)."
  echo "   → Aucun détail secret n'est affiché. Vérifiez le compte de test."
  exit 1
fi
verdict_ok "Connexion du compte de test OK (${TEST_EMAIL%%@*}@…)"

AUTH=(-H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $TOKEN")

# -----------------------------------------------------------------------------
# 2. La table des lots existe-t-elle et est-elle lisible ?
# -----------------------------------------------------------------------------
CODE_TABLE="$(
  curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    "$BASE/rest/v1/produits_lots?select=id&limit=1" \
    "${AUTH[@]}"
)"

case "$CODE_TABLE" in
  200) verdict_ok "Table produits_lots accessible (RLS et droits OK)." ;;
  404) verdict_ko "Table produits_lots ABSENTE → exécuter 20260916000163_module36_lots_pharmacie.sql." ;;
  401|403) verdict_info "produits_lots existe probablement, mais accès refusé (HTTP $CODE_TABLE)." ;;
  *) verdict_info "produits_lots : HTTP $CODE_TABLE (à examiner)." ;;
esac

CODE_MOUV="$(
  curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    "$BASE/rest/v1/produits_lots_mouvements?select=id&limit=1" \
    "${AUTH[@]}"
)"

case "$CODE_MOUV" in
  200) verdict_ok "Table produits_lots_mouvements accessible." ;;
  404) verdict_ko "Table produits_lots_mouvements ABSENTE → migration 0163 non exécutée." ;;
  *) verdict_info "produits_lots_mouvements : HTTP $CODE_MOUV." ;;
esac

# -----------------------------------------------------------------------------
# 3. Les RPC du module existent-elles ?
# -----------------------------------------------------------------------------
REPONSE_RPC="$(
  curl -sS -w '\n%{http_code}' --max-time 20 \
    -X POST "$BASE/rest/v1/rpc/rpc_lots_ecarts" \
    "${AUTH[@]}" -H "Content-Type: application/json" --data '{}'
)"
CODE_RPC="$(printf '%s' "$REPONSE_RPC" | tail -n1)"
CORPS_RPC="$(printf '%s' "$REPONSE_RPC" | sed '$d')"

if [[ "$CODE_RPC" == "200" ]]; then
  verdict_ok "RPC rpc_lots_ecarts opérationnelle."
elif printf '%s' "$CORPS_RPC" | grep -q 'PGRST202'; then
  verdict_ko "RPC rpc_lots_ecarts ABSENTE → migration 0163 non exécutée."
else
  verdict_info "rpc_lots_ecarts : HTTP $CODE_RPC — réponse du serveur à examiner."
fi

# -----------------------------------------------------------------------------
# 3 bis. rpc_lot_retirer COMPILE-T-ELLE ? (appel inoffensif : lot inexistant)
# -----------------------------------------------------------------------------
# Un UUID aléatoire ne correspond à aucun lot : la fonction doit répondre
# LOT_INTROUVABLE (ou DROIT_REFUSE pour un rôle sans droit). Si elle contient
# une variable non déclarée, c'est ICI qu'on le voit — le simple fait qu'elle
# existe ne prouve pas qu'elle s'exécute.
UUID_TEST="$(python3 -c 'import uuid; print(uuid.uuid4())')"
REPONSE_RETRAIT="$(
  curl -sS -w '\n%{http_code}' --max-time 20 \
    -X POST "$BASE/rest/v1/rpc/rpc_lot_retirer" \
    "${AUTH[@]}" -H "Content-Type: application/json" \
    --data "{\"p_lot_id\":\"$UUID_TEST\",\"p_motif\":\"diagnostic\"}"
)"
CODE_RETRAIT="$(printf '%s' "$REPONSE_RETRAIT" | tail -n1)"
CORPS_RETRAIT="$(printf '%s' "$REPONSE_RETRAIT" | sed '$d')"

if printf '%s' "$CORPS_RETRAIT" | grep -q 'LOT_INTROUVABLE'; then
  verdict_ok "RPC rpc_lot_retirer compile et refuse un lot inexistant."
elif printf '%s' "$CORPS_RETRAIT" | grep -q 'DROIT_REFUSE'; then
  verdict_ok "RPC rpc_lot_retirer compile (droits insuffisants pour ce compte : normal)."
elif printf '%s' "$CORPS_RETRAIT" | grep -qiE 'v_prod|does not exist|n.existe pas'; then
  verdict_ko "RPC rpc_lot_retirer CONTIENT UNE ERREUR DE COMPILATION → ré-exécuter 0163 corrigé."
else
  verdict_info "rpc_lot_retirer : HTTP $CODE_RETRAIT — réponse à examiner."
fi

# -----------------------------------------------------------------------------
# 4. Diagnostic des lots d'un article de test (facultatif)
# -----------------------------------------------------------------------------
if [[ -n "${TEST_PRODUIT_ID:-}" ]]; then
  REPONSE_LOTS="$(
    curl -sS --max-time 20 \
      -X POST "$BASE/rest/v1/rpc/rpc_lots_lister" \
      "${AUTH[@]}" -H "Content-Type: application/json" \
      --data "$(TEST_PRODUIT_ID="$TEST_PRODUIT_ID" python3 - <<'PY'
import json, os
print(json.dumps({
    "p_produit_id": int(os.environ["TEST_PRODUIT_ID"]),
    "p_jours_alarme": 30,
}))
PY
)"
  )"

  RESUME="$(
    printf '%s' "$REPONSE_LOTS" | python3 - <<'PY'
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("ERREUR|réponse illisible")
    sys.exit(0)
if "message" in d and "lots" not in d:
    print("ERREUR|" + str(d.get("message"))[:120])
    sys.exit(0)
lots = d.get("lots") or []
perimes = [l for l in lots if l.get("statut") == "perime"]
vendables = [l for l in lots if l.get("vendable")]
prochain = vendables[0] if vendables else None
print("OK|%d|%s|%s|%s|%s" % (
    len(lots),
    d.get("total_lots_restants", 0),
    d.get("total_vendable", 0),
    len(perimes),
    (prochain or {}).get("numero_lot", "—"),
))
PY
  )"

  if [[ "$RESUME" == OK\|* ]]; then
    IFS='|' read -r _ NB STOCK_LOTS STOCK_VENDABLE NB_PERIMES PROCHAIN <<<"$RESUME"
    verdict_ok "Article $TEST_PRODUIT_ID : $NB lot(s), restant $STOCK_LOTS, vendable $STOCK_VENDABLE, périmé(s) $NB_PERIMES, FEFO = $PROCHAIN."
  else
    verdict_ko "Lecture des lots impossible : ${RESUME#ERREUR|}"
  fi
else
  verdict_info "TEST_PRODUIT_ID non renseigné : lecture des lots ignorée."
fi

# -----------------------------------------------------------------------------
# 5. Bilan (aucun secret affiché)
# -----------------------------------------------------------------------------
echo
echo "— Bilan : $OK OK, $KO en échec —"
[[ "$KO" -eq 0 ]] && exit 0 || exit 1
