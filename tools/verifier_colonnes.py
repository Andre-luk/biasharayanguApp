#!/usr/bin/env python3
# ============================================================================
#  BIASHARA YANGU — vérification des colonnes et des fonctions d'une migration
#  Dossier : tools/verifier_colonnes.py
#  ---------------------------------------------------------------------------
#  POURQUOI CET OUTIL EXISTE
#  -------------------------
#  Le correctif 71 a été nécessaire parce qu'une migration référençait
#  `utilisateurs.nom_complet` — une colonne **qui n'existe pas**. Le contrôle
#  de syntaxe (libpg-query) ne pouvait pas le voir : PL/pgSQL ne valide pas les
#  noms de colonnes à la création d'une fonction, seulement à sa PREMIÈRE
#  EXÉCUTION. La migration s'installe donc sans broncher, et le défaut
#  n'apparaît que chez l'utilisateur — c'est-à-dire trop tard.
#
#  Cet outil comble ce trou, en deux vérifications :
#
#    1. COLONNES — toute colonne écrite `alias.colonne` dans la migration
#       cible qui n'apparaît NULLE PART dans les migrations antérieures (et que
#       la migration ne crée pas elle-même) est signalée. C'est exactement la
#       signature de `nom_complet`.
#
#    2. FONCTIONS — tout appel `public.fonction(...)` vers un nom qui n'est
#       défini par aucune migration est signalé.
#
#  ⚠️ LES SIGNALEMENTS SONT DES SUSPICIONS, PAS DES PREUVES. Une colonne peut
#  être légitime sans jamais avoir été écrite `alias.colonne` avant (créée par
#  `alter table … add column`, ou simple alias d'une sous-requête). Les six
#  suspects du correctif 71 étaient tous des faux positifs — mais il a fallu
#  les regarder un par un pour le savoir. C'est le but : ne rien laisser passer
#  sans le regarder.
#
#  USAGE
#  -----
#    python3 tools/verifier_colonnes.py                      # la dernière migration
#    python3 tools/verifier_colonnes.py <fichier.sql>        # une migration précise
#
#  Sortie : code 0 si aucun suspect, 1 sinon (utilisable dans un enchaînement).
# ============================================================================

import glob
import re
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
MIGRATIONS = RACINE / "supabase" / "migrations"

#  Préfixes qui ne sont jamais des alias de table (schémas, fonctions système).
PREFIXES_IGNORES = {
    "public", "auth", "pg_catalog", "extensions", "information_schema",
    "net", "storage", "vault", "cron",
}

#  ⚠️ Colonnes des CATALOGUES PostgreSQL (pg_proc, pg_attrdef, pg_constraint…).
#  Elles ne relèvent pas du schéma de l'application : les vérifier produirait
#  du bruit à chaque requête d'inspection, et un outil bruyant finit ignoré.
COLONNES_CATALOGUE = {
    "adbin", "adnum", "adrelid", "attname", "attnum", "attrelid",
    "conname", "conrelid", "contype", "nspname", "oid", "oidvectortypes",
    "pronamespace", "prokind", "proname", "prosrc", "relname", "tablename",
    "schema_name", "data_type", "column_name", "table_name", "table_schema",
    "is_nullable", "column_default", "ordinal_position", "typname",
}

#  Mots qui précèdent une TABLE et non un appel de fonction :
#  `insert into public.x (…)`, `from public.x`, `join public.x`…
MOTS_AVANT_TABLE = re.compile(
    r"(?:\b(?:into|from|join|update|delete|table|truncate|on|all\s+tables)\s+)$",
    re.I,
)

MOTIF_ALIAS_COLONNE = re.compile(r"(?<![\w.])([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)")
MOTIF_DEF_FONCTION = re.compile(r"create or replace function public\.(\w+)")
MOTIF_APPEL = re.compile(r"public\.(\w+)\s*\(")
MOTIF_CTABLE = re.compile(r"create table if not exists public\.(\w+)")
MOTIF_ACOLONNE = re.compile(r"add column if not exists\s+(\w+)", re.I)


def lire(chemin: Path) -> str:
    return chemin.read_text(encoding="utf-8")


def colonnes_referencees(fichiers: list[Path]) -> dict[str, set[str]]:
    """{colonne: {alias…}} pour un ensemble de migrations."""
    out: dict[str, set[str]] = {}
    for f in fichiers:
        for m in MOTIF_ALIAS_COLONNE.finditer(lire(f)):
            alias, colonne = m.group(1), m.group(2)
            if alias in PREFIXES_IGNORES:
                continue
            out.setdefault(colonne, set()).add(alias)
    return out


def colonnes_creees(fichiers: list[Path]) -> set[str]:
    """Colonnes que ces migrations créent (`create table`, `add column`)."""
    creees: set[str] = set()
    for f in fichiers:
        texte = lire(f)
        for bloc in re.findall(
            r"create table if not exists public\.\w+\s*\((.*?)\n\);", texte, re.S
        ):
            creees |= {m.group(1) for m in re.finditer(r"^\s*([a-z_][a-z0-9_]*)\s+", bloc, re.M)}
        creees |= {m.group(1) for m in MOTIF_ACOLONNE.finditer(texte)}
    return creees


def main() -> int:
    fichiers = sorted(MIGRATIONS.glob("*.sql"))
    if not fichiers:
        print("ARRET : aucune migration trouvee.", file=sys.stderr)
        return 2

    if len(sys.argv) > 1:
        cible = Path(sys.argv[1])
        if not cible.is_absolute():
            cible = (RACINE / sys.argv[1]).resolve()
        if not cible.exists():
            print(f"ARRET : {cible} introuvable.", file=sys.stderr)
            return 2
    else:
        cible = fichiers[-1]

    anterieures = [f for f in fichiers if f.name < cible.name]
    print(f"Migration analysee : {cible.name}")
    print(f"Migrations anterieures : {len(anterieures)}")

    avant = colonnes_referencees(anterieures)
    creees = colonnes_creees(anterieures) | colonnes_creees([cible])
    apres = colonnes_referencees([cible])

    suspects = {c: a for c, a in apres.items()
                if c not in avant and c not in creees
                and c not in COLONNES_CATALOGUE}

    # ---- Vérification 2 : les fonctions appelées existent-elles ? --------
    definies: set[str] = set()
    tables: set[str] = set()
    for f in fichiers:
        texte = lire(f)
        definies |= {m.group(1) for m in MOTIF_DEF_FONCTION.finditer(texte)}
        tables |= {m.group(1) for m in MOTIF_CTABLE.finditer(texte)}

    texte_cible = lire(cible)
    appels: set[str] = set()
    for m in MOTIF_APPEL.finditer(texte_cible):
        #  ⚠️ `insert into public.journal_audit (` ressemble à un appel de
        #  fonction : on regarde le mot qui précède.
        if MOTS_AVANT_TABLE.search(texte_cible[max(0, m.start() - 24):m.start()]):
            continue
        appels.add(m.group(1))

    appels_manquants = sorted(a for a in appels
                              if a not in definies and a not in tables)

    print(f"\n1. COLONNES SUSPECTES (jamais vues avant, non creees) : {len(suspects)}")
    for colonne, alias in sorted(suspects.items()):
        print(f"   ⚠️  {colonne:28} <- alias : {', '.join(sorted(alias))}")

    print(f"\n2. APPELS VERS UNE FONCTION INCONNUE : {len(appels_manquants)}")
    for nom in appels_manquants:
        print(f"   ⚠️  public.{nom}")

    if suspects or appels_manquants:
        print("\n👉 A VERIFIER UN PAR UN : un faux positif est frequent (colonne")
        print("   creee par `add column`, ou alias d'une sous-requete), mais un")
        print("   vrai positif casse la production sans prevenir.")
        return 1

    print("\n✅ Aucun suspect : les colonnes referencees existent et les")
    print("   fonctions appelees sont definies quelque part dans le projet.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
