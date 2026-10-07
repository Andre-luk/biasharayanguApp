#!/usr/bin/env bash
# ============================================================================
#  BIASHARA YANGU — rapatriement des paquets d'une release GitHub
#  Fichier : tools/recuperer_release.sh
# ============================================================================
#
#  POURQUOI CE SCRIPT
#  ------------------
#  Le dépôt est PRIVÉ : les fichiers d'une release ne se téléchargent pas par
#  un simple lien. Ce script interroge l'API GitHub avec le jeton déjà présent
#  sur la machine (`~/.git-credentials`), puis range chaque paquet dans le
#  dossier de diffusion.
#
#  USAGE
#  -----
#     bash tools/recuperer_release.sh              # dernier tag (v2.4.1)
#     bash tools/recuperer_release.sh v2.5.0       # un tag précis
#     DEST=/autre/dossier bash tools/recuperer_release.sh
#
#  ⛔ AUCUN secret n'est affiché : le jeton est lu dans le fichier, utilisé
#     dans l'en-tête HTTP, et jamais écrit à l'écran ni sur le disque.
# ============================================================================

set -uo pipefail

DEPOT="Andre-luk/biasharayanguApp"
TAG="${1:-v2.4.1}"
DEST="${DEST:-$HOME/Téléchargements/Biashara-Yangu-$TAG}"
API="https://api.github.com/repos/$DEPOT"

# --- Jeton : lu dans le magasin d'identifiants de git -----------------------
TOKEN="$(sed -n 's|https://[^:]*:\([^@]*\)@github.com.*|\1|p' \
          "$HOME/.git-credentials" 2>/dev/null | head -1)"

if [ -z "$TOKEN" ]; then
  echo "❌ Aucun jeton trouvé dans ~/.git-credentials."
  echo "   Le dépôt est privé : un jeton est nécessaire pour télécharger."
  exit 1
fi

echo "============================================================"
echo " Récupération de la release $TAG"
echo " Dépôt : $DEPOT"
echo " Vers  : $DEST"
echo "============================================================"
echo

# --- La release existe-t-elle ? --------------------------------------------
CODE="$(curl -s -o /tmp/_rel.json -w '%{http_code}' \
        -H "Authorization: token $TOKEN" "$API/releases/tags/$TAG")"

if [ "$CODE" != "200" ]; then
  echo "❌ Release « $TAG » introuvable (HTTP $CODE)."
  echo "   Vérifiez que le tag a bien été poussé et que le CI a terminé :"
  echo "   https://github.com/$DEPOT/actions"
  exit 1
fi

# --- Liste des fichiers ----------------------------------------------------
mapfile -t LIGNES < <(python3 - "$TAG" <<'PY'
import json, sys
d = json.load(open('/tmp/_rel.json'))
nom_release = d.get('name') or sys.argv[1]
print(f"INFO\t{nom_release}")
for a in d.get('assets', []):
    print(f"ASSET\t{a['id']}\t{a['name']}\t{a['size']}")
PY
)

if [ "${#LIGNES[@]}" -le 1 ]; then
  echo "⏳ La release existe mais AUCUN fichier n'y est encore attaché."
  echo "   Le CI est probablement en train de compiler. Relancez ce script"
  echo "   dans quelques minutes."
  exit 2
fi

for ligne in "${LIGNES[@]}"; do
  if [ "${ligne%%$'\t'*}" = "INFO" ]; then
    echo "📦 ${ligne#*$'\t'}"
    echo
  fi
done

# --- Dossier de destination, par famille -----------------------------------
mkdir -p "$DEST/1-Applications/Android" \
         "$DEST/1-Applications/Linux" \
         "$DEST/1-Applications/Windows"

ranger() {  # $1 = nom du fichier téléchargé → renvoie le chemin de destination
  case "$1" in
    *.apk)   echo "$DEST/1-Applications/Android/$1" ;;
    *linux*) echo "$DEST/1-Applications/Linux/$1" ;;
    *windows*|*setup.exe) echo "$DEST/1-Applications/Windows/$1" ;;
    *)       echo "$DEST/$1" ;;
  esac
}

erreurs=0
for ligne in "${LIGNES[@]}"; do
  [ "${ligne%%$'\t'*}" = "ASSET" ] || continue

  IFS=$'\t' read -r _ ID NOM TAILLE <<< "$ligne"
  MO=$(( TAILLE / 1048576 ))
  CIBLE="$(ranger "$NOM")"

  printf '↓ %-38s (%s Mo) ' "$NOM" "$MO"

  # `-L` est OBLIGATOIRE : l'API renvoie un 302 vers un stockage signé, et curl
  # retire l'en-tête Authorization sur ce renvoi (comportement voulu).
  curl -sL --retry 3 --retry-delay 2 --max-time 900 \
       -H "Authorization: token $TOKEN" \
       -H "Accept: application/octet-stream" \
       -o "$CIBLE" "$API/releases/assets/$ID" || true

  # Un téléchargement tronqué est fréquent sur les gros fichiers : on contrôle
  # donc l'archive avant de dire « terminé ».
  OK=1
  case "$CIBLE" in
    *.gz)  gzip -t "$CIBLE" 2>/dev/null || OK=0 ;;
    *.zip) unzip -t "$CIBLE" >/dev/null 2>&1 || OK=0 ;;
  esac
  # Un APK est un ZIP : il doit s'ouvrir et contenir AndroidManifest.xml.
  case "$CIBLE" in
    *.apk) unzip -l "$CIBLE" 2>/dev/null | grep -q AndroidManifest.xml || OK=0 ;;
    *.exe) [ -s "$CIBLE" ] || OK=0 ;;
  esac

  if [ "$OK" = "1" ] && [ -s "$CIBLE" ]; then
    echo "✅"
  else
    echo "❌ (fichier incomplet — supprimé)"
    rm -f "$CIBLE"
    erreurs=$((erreurs + 1))
  fi
done

echo
if [ "$erreurs" -eq 0 ]; then
  echo "✅ Tous les paquets ont été récupérés dans :"
  echo "   $DEST/1-Applications/"
else
  echo "⚠️  $erreurs fichier(s) incomplet(s). Relancez ce script (il reprend)."
  exit 1
fi
