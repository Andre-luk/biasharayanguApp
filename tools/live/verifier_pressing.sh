#!/usr/bin/env bash
# =============================================================================
#  Vérification « live » du module 35 (pressing) — SANS afficher de secret.
#
#  Pré-requis :
#    ~/.config/biashara/supabase.env  (voir tools/live/README.md, chmod 600)
#    Compte de test : pressing.test@biashara.cd (entreprise de type `pressing`)
#
#  Usage :
#    bash tools/live/verifier_pressing.sh
#
#  Le script est en LECTURE SEULE :
#    • aucune vente, aucun dépôt, aucun paiement n'est créé ;
#    • seuls des appels de lecture et un appel de diagnostic sont faits.
# =============================================================================
set -uo pipefail

FICHIER="${SUPABASE_ENV:-$HOME/.config/biashara/supabase.env}"

if [[ ! -f "$FICHIER" ]]; then
  echo "❌ Fichier de secrets absent : $FICHIER"
  echo "   → voir tools/live/README.md (section « Où mettre les identifiants »)."
  exit 2
fi

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
INFO=0

ok()   { echo "✅ $1"; OK=$((OK + 1)); }
ko()   { echo "❌ $1"; KO=$((KO + 1)); }
info() { echo "⚠️  $1"; INFO=$((INFO + 1)); }

# -----------------------------------------------------------------------------
# 0. Connexion du compte de test
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
  curl -sS --max-time 25 \
    -X POST "$BASE/auth/v1/token?grant_type=password" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" \
    --data "$CORPS_LOGIN"
)"

TOKEN="$(
  printf '%s' "$REPONSE_LOGIN" | python3 -c \
    'import sys, json; print(json.load(sys.stdin).get("access_token", ""))' 2>/dev/null
)"
UID_UTILISATEUR="$(
  printf '%s' "$REPONSE_LOGIN" | python3 -c \
    'import sys, json; print((json.load(sys.stdin).get("user") or {}).get("id", ""))' 2>/dev/null
)"

if [[ -z "$TOKEN" ]]; then
  ko "Connexion refusée pour ${TEST_EMAIL%%@*}@… (compte inexistant, mot de passe faux ou e-mail non confirmé)."
  exit 1
fi
ok "Connexion OK (${TEST_EMAIL%%@*}@…, uid ${UID_UTILISATEUR:0:8}…)"

AUTH=(-H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $TOKEN")

appel_rpc() { # $1 = nom, $2 = json (défaut {})
  local nom="$1" corps="${2:-{\}}"
  curl -sS --max-time 25 -X POST "$BASE/rest/v1/rpc/$nom" \
    "${AUTH[@]}" -H "Content-Type: application/json" --data "$corps"
}

resume_json() { # $1 = json, $2 = bloc python (multi-lignes, s'exécute)
  python3 - "$1" "$2" <<'PY'
import json, sys
brut, bloc = sys.argv[1], sys.argv[2]
try:
    d = json.loads(brut)
except Exception:
    print("ERREUR|réponse illisible")
    sys.exit(0)
if isinstance(d, dict) and d.get("message") and not any(
        k in d for k in ("ok", "espaces", "modules", "commande", "lignes")):
    print("ERREUR|" + str(d.get("message"))[:160])
    sys.exit(0)
try:
    exec(bloc, {"json": json, "d": d})
except Exception as e:  # noqa: BLE001
    print("ERREUR|" + str(e)[:160])
PY
}

# -----------------------------------------------------------------------------
# 1. Contexte : espaces de l'utilisateur et type d'activité
# -----------------------------------------------------------------------------
R_ESPACES="$(appel_rpc rpc_espaces_lister '{}')"
LIGNE_ESPACES="$(resume_json "$R_ESPACES" '
e = d if isinstance(d, list) else (d.get("espaces") or d.get("data") or [])
noms = ", ".join("%s[%s]" % (x.get("nom"), x.get("type")) for x in e)
print("%d|%s" % (len(e), noms))')"

if [[ "$LIGNE_ESPACES" == ERREUR\|* ]]; then
  ko "rpc_espaces_lister : ${LIGNE_ESPACES#ERREUR|}"
else
  IFS='|' read -r NB_ESPACES DETAIL_ESPACES <<<"$LIGNE_ESPACES"
  ok "Espaces visibles : $NB_ESPACES → ${DETAIL_ESPACES:-—}"
  if printf '%s' "$DETAIL_ESPACES" | grep -q '\[pressing\]'; then
    ok "Une entreprise de type « pressing » est bien présente."
  else
    ko "AUCUNE entreprise de type « pressing » → le compte de test n'est pas (encore) un pressing."
  fi
  if [[ "$NB_ESPACES" -gt 1 ]]; then
    info "Plusieurs espaces visibles : vérifier qu'aucune donnée de l'autre métier ne fuit."
  fi
fi

# -----------------------------------------------------------------------------
# 2. Modules activés pour ce métier (ni ventes, ni produits, ni stock)
# -----------------------------------------------------------------------------
R_MODULES="$(appel_rpc rpc_mes_modules '{}')"
LIGNE_MODULES="$(resume_json "$R_MODULES" '
g = d if isinstance(d, dict) else {}
m = g.get("modules") or []
codes = [str(x.get("code") if isinstance(x, dict) else x) for x in m]
print("%s|%s|%s|%s" % (g.get("type"), g.get("libelle"), g.get("source"),
                       ",".join(c for c in codes if c)))')"

if [[ "$LIGNE_MODULES" == ERREUR\|* ]]; then
  ko "rpc_mes_modules : ${LIGNE_MODULES#ERREUR|}"
else
  IFS='|' read -r TYPE_METIER LIBELLE_METIER SOURCE_MODULES CODES <<<"$LIGNE_MODULES"
  NB_MODULES="$(printf '%s' "$CODES" | tr ',' '\n' | grep -c . || true)"
  ok "Métier retenu : $TYPE_METIER ($LIBELLE_METIER) — source $SOURCE_MODULES"
  ok "Modules actifs ($NB_MODULES) : ${CODES:0:220}"
  # Depuis 0162 (« profil pressing complet »), le pressing garde aussi les
  # modules commerciaux (ventes, produits, stock, qr) : la garantie métier est
  # l'UNION, jamais le remplacement. Seules les 3 pages du métier sont
  # obligatoires.
  for obligatoire in press_depots press_atelier press_retraits; do
    if printf '%s' "$CODES" | tr ',' '\n' | grep -qx "$obligatoire"; then
      ok "Module $obligatoire présent."
    else
      ko "Module $obligatoire ABSENT (garantie métier 0159 non tenue)."
    fi
  done
  if [[ "$TYPE_METIER" != "pressing" ]]; then
    ko "Le métier retenu n'est pas « pressing » ($TYPE_METIER) → espaces.type à corriger."
  fi
fi

# -----------------------------------------------------------------------------
# 3. Rôle pressing et équipe
# -----------------------------------------------------------------------------
R_ROLE="$(appel_rpc pressing_role '{}')"
LIGNE_ROLE="$(resume_json "$R_ROLE" 'print(str(d if not isinstance(d, dict) else (d.get("role") or d.get("pressing_role") or "aucun")))')"
if [[ "$LIGNE_ROLE" == ERREUR\|* ]]; then
  ko "pressing_role : ${LIGNE_ROLE#ERREUR|}"
else
  ok "Rôle pressing calculé : $LIGNE_ROLE"
fi

R_EQUIPE="$(appel_rpc press_collaborateurs_lister '{}')"
LIGNE_EQUIPE="$(resume_json "$R_EQUIPE" '
e = d if isinstance(d, list) else (d.get("collaborateurs") or [])
print(len(e), "|", ", ".join(str(x.get("email") or x.get("nom") or "?") for x in e))')"
if [[ "$LIGNE_EQUIPE" == ERREUR\|* ]]; then
  info "press_collaborateurs_lister : ${LIGNE_EQUIPE#ERREUR|}"
else
  ok "Équipe pressing : $LIGNE_EQUIPE"
fi

# -----------------------------------------------------------------------------
# 4. Catalogue et étapes (peuvent être vides avant amorçage)
# -----------------------------------------------------------------------------
R_CATALOGUE="$(appel_rpc pressing_catalogue_lister '{}')"
LIGNE_CATALOGUE="$(resume_json "$R_CATALOGUE" '
g = d if isinstance(d, dict) else {}
cat = g.get("categories") or []
pre = g.get("prestations") or []
tar = g.get("tarifs") or []
print("categories=%d prestations=%d tarifs=%d" % (len(cat), len(pre), len(tar)))')"
if [[ "$LIGNE_CATALOGUE" == ERREUR\|* ]]; then
  info "pressing_catalogue_lister : ${LIGNE_CATALOGUE#ERREUR|}"
else
  ok "Catalogue : $LIGNE_CATALOGUE"
fi

R_ETAPES="$(appel_rpc pressing_etapes_lister '{}')"
LIGNE_ETAPES="$(resume_json "$R_ETAPES" '
e = d if isinstance(d, list) else (d.get("etapes") or [])
print("%d|%s" % (len(e), ", ".join(str(x.get("libelle") or x.get("code") or "?") for x in e)))')"
if [[ "$LIGNE_ETAPES" == ERREUR\|* ]]; then
  info "pressing_etapes_lister : ${LIGNE_ETAPES#ERREUR|}"
else
  ok "Étapes : $LIGNE_ETAPES"
fi

# -----------------------------------------------------------------------------
# 5. Tableau de bord, commandes, atelier, retraits, caisse
# -----------------------------------------------------------------------------
R_BORD="$(appel_rpc pressing_tableau_bord '{}')"
LIGNE_BORD="$(resume_json "$R_BORD" '
g = d if isinstance(d, dict) else {}
cles = ("commandes_ouvertes", "vetements_en_traitement", "vetements_prets",
        "a_remettre", "reste_du", "encaisse_jour")
print(" ".join("%s=%s" % (c, g.get(c)) for c in cles if c in g) or "aucun indicateur")')"
if [[ "$LIGNE_BORD" == ERREUR\|* ]]; then
  ko "pressing_tableau_bord : ${LIGNE_BORD#ERREUR|}"
else
  ok "Tableau de bord : $LIGNE_BORD"
fi

JOUR="$(date +%F)"
R_COMMANDES="$(appel_rpc pressing_commandes_lister "{\"p_recherche\":null,\"p_limite\":5}")"
LIGNE_COMMANDES="$(resume_json "$R_COMMANDES" '
e = d if isinstance(d, list) else (d.get("commandes") or [])
print("%d|%s" % (len(e), ", ".join(str(x.get("numero") or "?") for x in e[:5])))')"
if [[ "$LIGNE_COMMANDES" == ERREUR\|* ]]; then
  info "pressing_commandes_lister : ${LIGNE_COMMANDES#ERREUR|}"
else
  ok "Commandes (5 dernières) : $LIGNE_COMMANDES"
fi

R_ATELIER="$(appel_rpc pressing_atelier_lister '{"p_etape":null,"p_miennes":false,"p_limite":10}')"
LIGNE_ATELIER="$(resume_json "$R_ATELIER" '
e = d if isinstance(d, list) else (d.get("lignes") or [])
print(len(e))')"
if [[ "$LIGNE_ATELIER" == ERREUR\|* ]]; then
  info "pressing_atelier_lister : ${LIGNE_ATELIER#ERREUR|}"
else
  ok "Atelier : $LIGNE_ATELIER vêtement(s) en file."
fi

# Signature réelle : pressing_retraits_lister(p_commande_id uuid) — un UUID
# inconnu doit être refusé proprement (aucune fuite d'information).
UUID_INCONNU="$(python3 -c 'import uuid; print(uuid.uuid4())')"
R_RETRAITS="$(appel_rpc pressing_retraits_lister "{\"p_commande_id\":\"$UUID_INCONNU\"}")"
LIGNE_RETRAITS="$(resume_json "$R_RETRAITS" '
e = d if isinstance(d, list) else (d.get("retraits") or [])
print(len(e))')"
if [[ "$LIGNE_RETRAITS" == ERREUR\|* ]]; then
  info "pressing_retraits_lister : ${LIGNE_RETRAITS#ERREUR|}"
else
  ok "pressing_retraits_lister compile (commande inconnue → $LIGNE_RETRAITS remise(s))."
fi

R_CAISSE="$(appel_rpc pressing_caisse_jour "{\"p_date\":\"$JOUR\"}")"
LIGNE_CAISSE="$(resume_json "$R_CAISSE" '
g = d if isinstance(d, dict) else {}
print("encaisse=%s depots=%s remises=%s reste_du=%s modes=%s" % (
    g.get("encaisse"),
    g.get("depots") if g.get("depots") is not None else g.get("nb_depots"),
    g.get("remises") if g.get("remises") is not None else g.get("nb_remises"),
    g.get("reste_du"),
    ",".join("%s:%s" % (k, v.get("montant")) for k, v in (g.get("par_mode") or {}).items())))')"
if [[ "$LIGNE_CAISSE" == ERREUR\|* ]]; then
  info "pressing_caisse_jour : ${LIGNE_CAISSE#ERREUR|}"
else
  ok "Caisse du $JOUR : $LIGNE_CAISSE"
fi

# -----------------------------------------------------------------------------
# 6. Diagnostic : une commande inexistante doit être refusée proprement
# -----------------------------------------------------------------------------
UUID_TEST="$(python3 -c 'import uuid; print(uuid.uuid4())')"
R_FICHE="$(appel_rpc pressing_commande_fiche "{\"p_commande_id\":\"$UUID_TEST\"}")"
if printf '%s' "$R_FICHE" | grep -qiE 'INTROUVABLE|ERREUR'; then
  ok "pressing_commande_fiche compile et refuse une commande inexistante."
elif printf '%s' "$R_FICHE" | grep -qiE 'does not exist|n.existe pas'; then
  ko "pressing_commande_fiche en erreur de compilation → migration 0121 à revoir."
else
  info "pressing_commande_fiche : réponse à examiner → ${R_FICHE:0:140}"
fi

# -----------------------------------------------------------------------------
# 7. Verdict
# -----------------------------------------------------------------------------
echo
echo "═══ VERDICT PRESSING — $OK OK · $KO ÉCHEC(S) · $INFO INFO(S) ═══"
[[ "$KO" -eq 0 ]] && exit 0 || exit 1
