#!/usr/bin/env bash
# ============================================================================
#  BIASHARA YANGU — génération des documents PDF officiels
#  Dossier : docs/_build/build_pdf.sh
#  ---------------------------------------------------------------------------
#  Convertit chaque document HTML de `docs/` en PDF A4, à côté de sa source.
#  Outil : Google Chrome en mode « headless » (déjà présent sur la machine),
#  qui imprime les couleurs d'arrière-plan et les polices avec fidélité.
#
#  Usage :
#     ./docs/_build/build_pdf.sh              # tous les documents
#     ./docs/_build/build_pdf.sh officiel     # un sous-dossier précis
#
#  ⚠️ Le projet interdit la compilation Flutter locale (machine trop juste) :
#     ce script ne fait QUE du HTML → PDF, il ne compile rien.
# ============================================================================

set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCS="$RACINE/docs"
CHROME="${CHROME:-google-chrome}"
CIBLE="${1:-}"

if ! command -v "$CHROME" >/dev/null 2>&1; then
  echo "❌ Google Chrome introuvable. Installez-le ou définissez CHROME=/chemin/vers/chrome" >&2
  exit 1
fi

# Un PDF de 0 page ou une génération vide signale silencieusement une erreur :
# on vérifie donc chaque fichier produit avant de dire « terminé ».
generer() {
  local html="$1"
  local pdf="${html%.html}.pdf"
  local nom
  nom="$(basename "$html")"

  "$CHROME" \
    --headless=new \
    --disable-gpu \
    --no-sandbox \
    --no-pdf-header-footer \
    --virtual-time-budget=12000 \
    --print-to-pdf="$pdf" \
    "file://$html" >/dev/null 2>&1 || true

  if [[ ! -s "$pdf" ]]; then
    echo "  ❌ $nom — PDF non généré"
    return 1
  fi

  local pages
  pages="$(pdfinfo "$pdf" 2>/dev/null | awk '/^Pages:/ {print $2}')"
  local ko
  ko="$(du -h "$pdf" | cut -f1)"
  if [[ -z "$pages" || "$pages" -lt 1 ]]; then
    echo "  ⚠️  $nom — PDF illisible"
    return 1
  fi
  echo "  ✅ $(basename "$pdf") — $pages pages, $ko"
}

echo "📄 Biashara Yangu — génération des documents PDF"
echo "   dossier : $DOCS"
echo

total=0
erreurs=0

while IFS= read -r html; do
  # Les gabarits et fragments du dossier _build ne sont pas des documents.
  case "$html" in
    */_build/*) continue ;;
  esac
  if [[ -n "$CIBLE" && "$html" != *"/$CIBLE/"* ]]; then
    continue
  fi

  total=$((total + 1))
  echo "→ ${html#$DOCS/}"
  generer "$html" || erreurs=$((erreurs + 1))
done < <(find "$DOCS" -name '*.html' | sort)

echo
if [[ "$erreurs" -eq 0 ]]; then
  echo "✅ $total document(s) généré(s) sans erreur."
else
  echo "⚠️  $total document(s) traité(s), $erreurs en erreur."
  exit 1
fi
