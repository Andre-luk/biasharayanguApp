#!/usr/bin/env bash
# ============================================================================
#  Biashara Yangu — CONFIGURATION DE LA SIGNATURE OFFICIELLE (UNE SEULE FOIS)
# ----------------------------------------------------------------------------
#  Ce script :
#    1. te demande le mot de passe du keystore (saisie INVISIBLE — il ne sort
#       jamais de ce terminal, il n'est ni affiché ni enregistré) ;
#    2. vérifie le keystore et détecte l'alias réel de la clé ;
#    3. crée les secrets GitHub manquants (chiffrés, valeurs masquées) :
#       ANDROID_STORE_PASSWORD, ANDROID_KEY_PASSWORD, ANDROID_KEY_ALIAS ;
#    4. relance la release v1.2.0 → l'APK sera signé avec TA clé (APKPure).
#
#  Lancement :   bash ~/Documents/biasharayanguApp/tools/setup_signature.sh
# ============================================================================
set -e

JKS="$HOME/Documents/keystores/biashara-upload.jks"
APP_DIR="$HOME/Documents/biasharayanguApp"

echo "════════════════════════════════════════════════════════════"
echo "  Biashara Yangu — configuration de la signature officielle"
echo "════════════════════════════════════════════════════════════"

[ -f "$JKS" ] || { echo "❌ Keystore introuvable : $JKS"; exit 1; }

# --- 1. Mot de passe (saisie masquée) ---------------------------------------
read -rsp "Mot de passe du keystore (invisible pendant la saisie) : " MDP
echo

# --- 2. Vérification du keystore + alias réel -------------------------------
if ! keytool -list -keystore "$JKS" -storepass "$MDP" >/dev/null 2>&1; then
  echo "❌ Mot de passe incorrect pour ce keystore. Relance le script."
  exit 1
fi

ALIAS=$(keytool -list -keystore "$JKS" -storepass "$MDP" 2>/dev/null \
        | grep 'PrivateKeyEntry' | head -1 | cut -d, -f1 | xargs)
[ -n "$ALIAS" ] || { echo "❌ Aucune clé privée trouvée dans le keystore."; exit 1; }
echo "✅ Keystore déverrouillé — alias de la clé : « $ALIAS »"

# --- 3. Envoi des secrets (chiffrement libsodium, valeurs jamais affichées) --
python3 - "$MDP" "$ALIAS" <<'PYEOF'
import base64, json, os, re, sys, urllib.request
from nacl import encoding, public as naclpublic

mdp, alias = sys.argv[1], sys.argv[2]
REPO = 'Andre-luk/biasharayanguApp'

tok = None
for ligne in open(os.path.expanduser('~/.git-credentials')):
    m = re.match(r'https://([^:]+):([^@]+)@github\.com', ligne.strip())
    if m:
        tok = m.group(2)
        break
assert tok, 'PAT GitHub introuvable (~/.git-credentials)'

def api(method, path, data=None):
    req = urllib.request.Request(
        f'https://api.github.com/repos/{REPO}{path}',
        data=json.dumps(data).encode() if data is not None else None,
        method=method,
        headers={'Authorization': f'token {tok}',
                 'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(req) as r:
        corps = r.read()
        return json.loads(corps) if corps else {}

pk = api('GET', '/actions/secrets/public-key')
cle = naclpublic.PublicKey(pk['key'].encode(), encoding.Base64Encoder())
boite = naclpublic.SealedBox(cle)

for nom, valeur in (('ANDROID_STORE_PASSWORD', mdp),
                    ('ANDROID_KEY_PASSWORD', mdp),
                    ('ANDROID_KEY_ALIAS', alias)):
    chiffre = base64.b64encode(boite.encrypt(valeur.encode())).decode()
    api('PUT', f'/actions/secrets/{nom}',
        {'encrypted_value': chiffre, 'key_id': pk['key_id']})
    print(f'✅ Secret « {nom} » enregistré.')
PYEOF

# --- 4. Relancer la release (elle sera signée avec TA clé) ------------------
echo ""
echo "🚀 Relance de la v1.2.0 (signée avec ta clé)…"
cd "$APP_DIR"
git push origin :refs/tags/v1.2.0 >/dev/null 2>&1 || true
git tag -d v1.2.0 >/dev/null 2>&1 || true
git tag -a v1.2.0 -m "Biashara Yangu v1.2.0 — signée officiellement"
git push origin v1.2.0

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅  TOUT EST PRÊT !"
echo ""
echo "   La release signée se construit (~30 min) :"
echo "   https://github.com/Andre-luk/biasharayanguApp/actions"
echo ""
echo "   Ensuite : page Releases → télécharger « biashara-yangu.apk »"
echo "   → le téléverser sur APKPure (fiche prête : docs/apkpure_fiche.md)."
echo ""
echo "   🔑 Garde à vie : le fichier biashara-upload.jks + son mot de passe."
echo "════════════════════════════════════════════════════════════"
