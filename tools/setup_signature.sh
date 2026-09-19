#!/usr/bin/env bash
# ============================================================================
#  Biashara Yangu — CONFIGURATION DE LA SIGNATURE OFFICIELLE (UNE SEULE FOIS)
# ----------------------------------------------------------------------------
#  Deux possibilités, au choix au démarrage :
#    1) Tu connais le mot de passe du keystore actuel → tout est configuré.
#    2) Mot de passe perdu/incertain → un NOUVEAU keystore est créé (aucune
#       conséquence : rien n'a encore été publié avec l'ancien), avec un
#       nouveau mot de passe que TU choisis et notes bien.
#
#  Dans tous les cas, ce script :
#    • vérifie / crée le keystore (mot de passe saisi INVISIBLEMENT — il ne
#      sort jamais de ce terminal, ni affiché, ni enregistré) ;
#    • envoie le keystore + les mots de passe vers GitHub (CHIFFRÉS ;
#      les secrets sont en écriture seule : illisibles même par un admin) ;
#    • relance la release v1.2.0 → APK signé avec TA clé, prêt pour APKPure.
#
#  Lancement :   bash ~/Documents/biasharayanguApp/tools/setup_signature.sh
# ============================================================================
set -e

JKS_DIR="$HOME/Documents/keystores"
JKS="$JKS_DIR/biashara-upload.jks"
APP_DIR="$HOME/Documents/biasharayanguApp"

echo "════════════════════════════════════════════════════════════"
echo "  Biashara Yangu — configuration de la signature officielle"
echo "════════════════════════════════════════════════════════════"
echo ""

if [ -f "$JKS" ]; then
  echo "Un keystore existe déjà : $JKS"
  echo "  1) Je connais son mot de passe"
  echo "  2) J'ai oublié le mot de passe → créer un NOUVEAU keystore"
  echo "     (sans conséquence : rien n'a encore été publié avec l'ancien)"
  read -rp "Ton choix [1/2] : " CHOIX
else
  echo "Aucun keystore trouvé → on en crée un nouveau."
  CHOIX="2"
fi

mkdir -p "$JKS_DIR"

if [ "$CHOIX" = "2" ]; then
  echo ""
  echo "⚠️  Choisis un mot de passe de 6 caractères minimum et NOTE-LE BIEN"
  echo "    (gestionnaire de mots de passe, papier en lieu sûr…)."
  echo "    🔑 C'est LUI qui protégera ta clé à vie : sans lui, plus de mises à jour."
  echo ""
  read -rsp "Nouveau mot de passe du keystore (invisible) : " MDP; echo
  read -rsp "Confirme le mot de passe (invisible)        : " MDP2; echo

  if [ "$MDP" != "$MDP2" ]; then
    echo "❌ Les deux saisies diffèrent. Relance le script."
    exit 1
  fi
  if [ ${#MDP} -lt 6 ]; then
    echo "❌ 6 caractères minimum. Relance le script."
    exit 1
  fi

  # Archive l'ancien keystore (au cas où le mot de passe te revienne un jour —
  # NE JAMAIS signer avec deux keystores différents : celui-ci devient la
  # référence unique).
  if [ -f "$JKS" ]; then
    ARCHIVE="$JKS.ancien-$(date +%Y%m%d-%H%M%S)"
    mv "$JKS" "$ARCHIVE"
    echo "ℹ️  Ancien keystore archivé : $ARCHIVE"
  fi

  keytool -genkeypair -v -keystore "$JKS" -alias biashara \
    -keyalg RSA -keysize 2048 -validity 10950 \
    -storepass "$MDP" -keypass "$MDP" \
    -dname "CN=Biashara Yangu, O=Biashara Tech, L=Lubumbashi, C=CD" >/dev/null 2>&1

  ALIAS="biashara"
  echo "✅ Nouveau keystore créé — alias : « $ALIAS »"
else
  read -rsp "Mot de passe du keystore (invisible pendant la saisie) : " MDP; echo

  if ! keytool -list -keystore "$JKS" -storepass "$MDP" >/dev/null 2>&1; then
    echo ""
    echo "❌ Mot de passe incorrect pour ce keystore."
    echo "   → Si tu n'es pas sûr : relance le script et choisis l'option 2"
    echo "     (nouveau keystore, aucune conséquence)."
    exit 1
  fi

  ALIAS=$(keytool -list -keystore "$JKS" -storepass "$MDP" 2>/dev/null \
          | grep 'PrivateKeyEntry' | head -1 | cut -d, -f1 | xargs)
  [ -n "$ALIAS" ] || { echo "❌ Aucune clé privée trouvée dans le keystore."; exit 1; }
  echo "✅ Keystore déverrouillé — alias de la clé : « $ALIAS »"
fi

# --- Envoi des secrets (chiffrés ; aucune valeur affichée) -------------------
TMPB64=$(mktemp)
chmod 600 "$TMPB64"
base64 -w0 "$JKS" > "$TMPB64"

python3 - "$MDP" "$ALIAS" "$TMPB64" <<'PYEOF'
import base64, json, os, re, sys, urllib.request
from nacl import encoding, public as naclpublic

mdp, alias, fichier_keystore = sys.argv[1], sys.argv[2], sys.argv[3]
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

with open(fichier_keystore, 'r') as f:
    keystore_b64 = f.read().strip()

for nom, valeur in (('ANDROID_KEYSTORE_BASE64', keystore_b64),
                    ('ANDROID_STORE_PASSWORD', mdp),
                    ('ANDROID_KEY_PASSWORD', mdp),
                    ('ANDROID_KEY_ALIAS', alias)):
    chiffre = base64.b64encode(boite.encrypt(valeur.encode())).decode()
    api('PUT', f'/actions/secrets/{nom}',
        {'encrypted_value': chiffre, 'key_id': pk['key_id']})
    print(f'✅ Secret « {nom} » enregistré (valeur masquée).')
PYEOF

# Suppression sécurisée du fichier temporaire (jamais laissé traîner).
shred -u "$TMPB64" 2>/dev/null || rm -f "$TMPB64"

# --- Relance de la release (signée avec ta clé) ------------------------------
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
echo "   → le téléverser sur APKPure (fiche : docs/apkpure_fiche.md)."
echo ""
echo "   🔑 À CONSERVER À VIE : le fichier biashara-upload.jks"
echo "      ET son mot de passe (note-le si ce n'est pas déjà fait !)."
echo "════════════════════════════════════════════════════════════"
