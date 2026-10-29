#!/usr/bin/env bash
# ============================================================================
#  Recette du webhook SerdiPay — vérifie la SÉCURITÉ de la signature.
#
#  Trois contrôles, sans jamais créer de paiement :
#    1. POST sans signature            → doit répondre 401
#    2. POST avec une fausse signature → doit répondre 401
#    3. POST correctement signé, sur une référence INEXISTANTE
#                                      → doit répondre 200 {"ok":true,...}
#       (aucune ligne en base : rien n'est crédité)
#
#  Usage :
#     bash tools/relais_serdipay/verifier_webhook.sh [URL] [REFERENCE]
#
#  ⚠️ Le secret est saisi en INVISIBLE (read -rsp) : il ne transite ni par
#     l'historique du shell, ni par un fichier, ni par un modèle.
# ============================================================================
set -u

URL="${1:-https://pqzcliibocndiyqbyddr.supabase.co/functions/v1/serdipay/webhook}"
REF="${2:-SER-TEST-$(date +%Y%m%d)-0000}"

echo "=============================================================="
echo " Recette webhook SerdiPay"
echo " URL        : $URL"
echo " Référence  : $REF (volontairement inexistante)"
echo "=============================================================="
echo
echo "DIAGNOSTIC RAPIDE"
echo "  400 CORPS_INVALIDE        → la fonction est déployée, mais le corps est refusé"
echo "  401 SIGNATURE_INVALIDE    → fonction déployée + secret configuré (attendu ici)"
echo "  404 NOT_FOUND             → la fonction n'est PAS déployée"
echo "  503 WEBHOOK_NON_CONFIGURE → SERDIPAY_WEBHOOK_SECRET absent"
echo

read -rsp "Secret webhook SerdiPay (SERDIPAY_WEBHOOK_SECRET) : " SECRET
echo
if [ -z "$SECRET" ]; then
  echo "✗ Aucun secret saisi — arrêt."
  exit 1
fi

# Contrôle de FORME (la valeur n'est jamais affichée) : détecte un collage
# tronqué, un espace final, ou un retour à la ligne collé avec la valeur.
LONGUEUR=${#SECRET}
echo "  Valeur reçue : $LONGUEUR caractères (non affichée)."
if [ "$LONGUEUR" -lt 32 ]; then
  echo "  ⚠️  Moins de 32 caractères : collage probablement incomplet."
fi
if [ "$LONGUEUR" -gt 64 ] && [ "$((LONGUEUR % 2))" -eq 0 ]; then
  echo "  ℹ️  Plus de 64 caractères : vérifiez qu'il n'y a pas d'espace ou de"
  echo "      retour à la ligne collés avec la valeur."
fi

BODY="{\"reference\":\"$REF\",\"status\":\"paid\",\"amount\":1}"
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" -hex | sed 's/^.* //')

OK=0
KO=0

controle() {
  local libelle="$1" attendu="$2" obtenu="$3" corps="$4"
  if [ "$obtenu" = "$attendu" ]; then
    echo "  ✅ $libelle → HTTP $obtenu"
    OK=$((OK + 1))
  else
    echo "  ❌ $libelle → HTTP $obtenu (attendu $attendu)"
    echo "     $corps"
    KO=$((KO + 1))
  fi
}

echo "--------------------------------------------------------------"

# 1. Sans signature
R=$(curl -s -m 15 -o /tmp/sp1.txt -w "%{http_code}" -X POST "$URL" \
  -H "Content-Type: application/json" --data "$BODY")
controle "Sans signature" "401" "$R" "$(cat /tmp/sp1.txt)"

# 2. Mauvaise signature
R=$(curl -s -m 15 -o /tmp/sp2.txt -w "%{http_code}" -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "x-serdipay-signature: 0000000000000000000000000000000000000000000000000000000000000000" \
  --data "$BODY")
controle "Signature invalide" "401" "$R" "$(cat /tmp/sp2.txt)"

# 3. Bonne signature, référence inexistante
R=$(curl -s -m 15 -o /tmp/sp3.txt -w "%{http_code}" -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "x-serdipay-signature: $SIG" \
  --data "$BODY")
controle "Signature valide (réf. inconnue)" "200" "$R" "$(cat /tmp/sp3.txt)"

echo "--------------------------------------------------------------"
echo " Corps du dernier appel : $(cat /tmp/sp3.txt)"
echo
if [ "$KO" -eq 0 ]; then
  echo "✅ BILAN : $OK/$((OK + KO)) contrôles réussis — le webhook est protégé"
  echo "   et accepte les appels signés."
  echo
  echo "   👉 C'est CE secret-là qu'il faut transmettre à SerdiPay."
else
  echo "⚠️  BILAN : $KO échec(s) / $((OK + KO)). Voir le tableau DIAGNOSTIC."
  echo
  echo "   Si le 3e contrôle renvoie 401, la valeur saisie ne correspond PAS à"
  echo "   celle enregistrée dans Supabase. Dans ce cas :"
  echo "     • relancez le script avec l'AUTRE code généré, ou"
  echo "     • réenregistrez un secret NEUF (openssl rand -hex 32) dans"
  echo "       Dashboard → Project Settings → Edge Functions → Secrets"
  echo "       (attention : pas d'espace avant/après, pas de guillemets),"
  echo "       puis relancez ce script avec exactement cette valeur."
fi

rm -f /tmp/sp1.txt /tmp/sp2.txt /tmp/sp3.txt
unset SECRET
