#!/usr/bin/env python3
# Patch d'une migration : reprend `audit_niveau` À L'IDENTIQUE depuis la
# migration LA PLUS RÉCENTE qui la définit, et y insère de nouvelles actions
# JUSTE AVANT le `else 'INFO'`.
#
# ⚠️ SUPERSÈDE `patcher_audit_niveau.py` (figé sur les migrations 39 -> 68,
#    conservé comme trace de ce patch-là). Celui-ci est générique.
#
# POURQUOI CE SCRIPT
# ------------------
# `audit_niveau` est un CASE d'une centaine de lignes qui attribue un niveau de
# gravité (CRITIQUE / HAUT / MOYEN / INFO) à chaque action du journal. Les
# actions INCONNUES retombent sur `else 'INFO'` — le niveau le MOINS grave.
#
# Réécrire cette fonction de mémoire ferait perdre des correspondances
# existantes : des actions sensibles (argent, droits) se retrouveraient
# silencieusement classées « INFO », donc noyées dans le journal. C'est
# exactement le genre de régression qui ne se voit pas.
#
# On extrait donc la version en vigueur, on VÉRIFIE sa forme, et on insère.
# Toutes les hypothèses sont ASSERTÉES : si la source change de forme, le
# script s'arrête au lieu de produire une migration silencieusement fausse.
#
# USAGE
#   python3 tools/patcher_audit_niveau_generalise.py <migration_cible.sql> <ajouts.txt>
#
#   • la SOURCE est trouvée automatiquement : la migration au numéro le plus
#     élevé qui définit `create or replace function public.audit_niveau` ;
#   • `ajouts.txt` contient les lignes `when 'ACTION' then 'NIVEAU'` (avec
#     leurs commentaires) à insérer avant `else 'INFO'` ;
#   • la cible doit contenir UNE fois le marqueur `-- @@AUDIT_NIVEAU@@`.

import re
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
DOSSIER = RACINE / "supabase/migrations"
MARQUEUR = "-- @@AUDIT_NIVEAU@@"
SIGNATURE = "create or replace function public.audit_niveau"
ANCRE = "    else 'INFO'"


def echec(message: str) -> None:
    print(f"ARRET : {message}", file=sys.stderr)
    sys.exit(1)


def source_la_plus_recente() -> Path:
    """La migration au numéro le plus élevé qui définit audit_niveau."""
    candidates: list[tuple[int, Path]] = []

    for fichier in sorted(DOSSIER.glob("*.sql")):
        try:
            texte = fichier.read_text(encoding="utf-8")
        except OSError:
            continue
        if SIGNATURE not in texte:
            continue

        chiffres = re.findall(r"\d+", fichier.stem[:32])
        numero = int(chiffres[0]) if chiffres else 0
        candidates.append((numero, fichier))

    if not candidates:
        echec("aucune migration ne definit audit_niveau")

    return max(candidates, key=lambda c: c[0])[1]


def extraire(chemin: Path) -> str:
    texte = chemin.read_text(encoding="utf-8")

    if texte.count(SIGNATURE) != 1:
        echec(f"{chemin.name} : {texte.count(SIGNATURE)} definitions de "
              "audit_niveau (extraction ambigue)")

    debut = texte.find(SIGNATURE)
    fin = texte.find("$$;", debut)
    if fin < 0:
        echec(f"{chemin.name} : fin de audit_niveau introuvable (pas de $$;)")

    bloc = texte[debut:fin + 3]
    if len(bloc) < 1000:
        echec(f"{chemin.name} : bloc extrait suspect ({len(bloc)} caracteres)")
    if bloc.count(ANCRE) != 1:
        echec(f"{chemin.name} : attendu exactement un `else 'INFO'`")

    # Garde-fous : on refuse d'extraire autre chose que la bonne fonction.
    for controle in ("immutable", "'RAPPORT'", "'CREATION_ENTREPRISE'"):
        if controle not in bloc:
            echec(f"{chemin.name} : le bloc extrait ne contient pas {controle}")

    return bloc


def main() -> None:
    if len(sys.argv) != 3:
        echec("usage : patcher_audit_niveau_generalise.py <cible.sql> <ajouts.txt>")

    cible = Path(sys.argv[1])
    ajouts_fichier = Path(sys.argv[2])

    if not cible.exists():
        echec(f"cible introuvable : {cible}")
    if not ajouts_fichier.exists():
        echec(f"fichier d'ajouts introuvable : {ajouts_fichier}")

    ajouts = ajouts_fichier.read_text(encoding="utf-8").strip("\n")
    if not ajouts:
        echec("le fichier d'ajouts est vide")

    actions = re.findall(r"when\s+'([A-Z0-9_]+)'", ajouts)
    if not actions:
        echec("aucune clause `when 'ACTION'` dans le fichier d'ajouts")

    source = source_la_plus_recente()
    bloc = extraire(source)

    #  Ne jamais insérer une clause déjà présente : elle serait inutile, et
    #  surtout on ne verrait pas que le patch est un doublon.
    for action in actions:
        if f"'{action}'" in bloc:
            echec(f"l'action {action} est DÉJÀ dans audit_niveau "
                  f"({source.name}) : doublon, rien à insérer")

    patche = bloc.replace(ANCRE, ajouts + "\n" + ANCRE, 1)

    if len(patche) <= len(bloc):
        echec("le bloc patche est plus court que l'original")
    if patche.count(ANCRE) != 1:
        echec("le `else 'INFO'` a ete altere")
    for action in actions:
        if patche.count(f"'{action}'") != 1:
            echec(f"l'action {action} n'a pas ete inseree exactement une fois")

    texte_cible = cible.read_text(encoding="utf-8")
    if texte_cible.count(MARQUEUR) != 1:
        echec(f"attendu exactement un marqueur {MARQUEUR} dans {cible.name}")

    cible.write_text(texte_cible.replace(MARQUEUR, patche), encoding="utf-8")

    print(f"OK : audit_niveau extraite de {source.name} "
          f"({len(bloc)} -> {len(patche)} caracteres)")
    print(f"OK : {len(actions)} action(s) inseree(s) : {', '.join(actions)}")


if __name__ == "__main__":
    main()
