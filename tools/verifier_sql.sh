#!/usr/bin/env bash
# ============================================================================
#  tools/verifier_sql.sh — CONTRÔLE RAPIDE D'UNE MIGRATION AVANT EXÉCUTION
# ----------------------------------------------------------------------------
#  Objectif : attraper AVANT le SQL Editor les erreurs que le parseur
#  « global » ne voit pas (les corps PL/pgSQL ne sont pas analysés).
#
#  Usage :
#     tools/verifier_sql.sh supabase/migrations/2026xxxx_xxx.sql
#     tools/verifier_sql.sh            # vérifie la dernière migration
#
#  Contrôles effectués :
#   1. équilibre des blocs $$ … $$ ;
#   2. « for <var> in array … loop » (INVALIDE : il faut FOREACH) ;
#   3. `drop table` / `truncate` / `delete from` sans `where` (destructeur) ;
#   4. points de vigilance pour copier-coller (NON bloquants) :
#      alias `.xyz` utilisé alors que l'alias n'apparaît pas dans la requête.
#
#  ⚠️ Ce script ne remplace pas un vrai PostgreSQL : il complète le parseur.
# ============================================================================
set -uo pipefail

ROUGE=$'\033[31m'; VERT=$'\033[32m'; JAUNE=$'\033[33m'; RAZ=$'\033[0m'
erreurs=0
alertes=0

fichier="${1:-}"
if [[ -z "$fichier" ]]; then
  fichier="$(ls -1 supabase/migrations/*.sql | sort | tail -1)"
  echo "Aucun fichier fourni — dernière migration : $fichier"
fi

if [[ ! -f "$fichier" ]]; then
  echo "${ROUGE}✖ Fichier introuvable : $fichier${RAZ}"
  exit 2
fi

echo "── Vérification de $(basename "$fichier") ──"

# 1. Blocs $$ / $q$ / $tag$ équilibrés --------------------------------------
dollars=$(grep -o '\$\$' "$fichier" | wc -l)
if (( dollars % 2 != 0 )); then
  echo "${ROUGE}✖ Nombre impair de \$\$ ($dollars) : un bloc DO/fonction n'est pas fermé.${RAZ}"
  erreurs=$((erreurs + 1))
fi

# 2. for … in array (doit être FOREACH) -------------------------------------
while IFS= read -r ligne; do
  [[ -z "$ligne" ]] && continue
  echo "${ROUGE}✖ $ligne${RAZ}"
  echo "   → utiliser : foreach <var> in array <tableau> loop"
  erreurs=$((erreurs + 1))
done < <(grep -nE '^[[:space:]]*for[[:space:]]+[a-z_][a-z_0-9]*[[:space:]]+in[[:space:]]+array' "$fichier" || true)

# 3. Ordres destructeurs sans filtre ---------------------------------------
while IFS= read -r ligne; do
  [[ -z "$ligne" ]] && continue
  echo "${JAUNE}⚠ $ligne${RAZ}"
  echo "   → « delete from » / « truncate » sans WHERE efface TOUT : à confirmer."
  alertes=$((alertes + 1))
done < <(grep -niE '^[[:space:]]*(delete[[:space:]]+from|truncate([[:space:]]+table)?)[[:space:]]+[^;]*;' "$fichier" \
         | grep -viE 'where|truncate[[:space:]]+table[[:space:]]+[a-z_.]+[[:space:]]*;' || true)

# 4. Alias utilisés mais jamais déclarés (heuristique, non bloquant) --------
#    Pour chaque « x.colonne » on vérifie que « x » apparaît aussi comme
#    alias (« join … x », « from … x », « , x »…). Les alias d'une seule
#    lettre sont les plus risqués (g, e, s, u, a…).
for alias in g e s u a p t; do
  if grep -qE "(^|[^a-z_])${alias}\.[a-z_]" "$fichier"; then
    if ! grep -qE "([[:space:]]|,|\\()${alias}([[:space:]]|,|\\)|$)" "$fichier"; then
      echo "${JAUNE}⚠ L'alias « ${alias} » est utilisé (${alias}.colonne) sans sembler déclaré.${RAZ}"
      alertes=$((alertes + 1))
    fi
  fi
done

# Résultat ----------------------------------------------------------------
echo "──────────────────────────────────────"
if (( erreurs == 0 )); then
  echo "${VERT}✔ Aucune erreur détectée${RAZ} ($alertes alerte(s) à relire)"
else
  echo "${ROUGE}✖ $erreurs erreur(s)${RAZ}, $alertes alerte(s)"
fi
exit $(( erreurs > 0 ? 1 : 0 ))
