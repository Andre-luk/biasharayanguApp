#!/usr/bin/env python3
# Patch de la migration 68 : reprend `audit_niveau` À L'IDENTIQUE depuis la
# migration 39 (dernière version en vigueur) et y insère les actions des
# correctifs 67 et 68, JUSTE AVANT le `else 'INFO'`.
#
# Pourquoi ce script et pas une réécriture manuelle : la fonction est un gros
# CASE de ~90 lignes. La retaper de mémoire ferait perdre des correspondances
# existantes — donc des niveaux de gravité — sans que personne ne s'en
# aperçoive. On extrait, on vérifie, on insère.
#
# Toutes les hypothèses sont ASSERTÉES : si le fichier source change de forme,
# le script s'arrête au lieu de produire une migration silencieusement fausse.

import re
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
SOURCE = RACINE / "supabase/migrations/20260916000039_module18_devises.sql"
CIBLE = RACINE / "supabase/migrations/20260916000068_quotas_ia_crud.sql"
MARQUEUR = "-- @@AUDIT_NIVEAU@@"

# Actions ajoutées par les correctifs 67 (factures) et 68 (quotas IA).
# Le niveau traduit la gravité : CRITIQUE = argent ou droits, HAUT = trace
# manquante ou document annulé, MOYEN = réglage, INFO = consultation.
AJOUTS = """
    -- 🧾 CORRECTIF 67 — factures d'abonnement.
    --   ECHEC : une facture non produite est un TROU de traçabilité sur un
    --   encaissement réel — aussi grave qu'un document annulé.
    when 'FACTURE_ABONNEMENT_ECHEC'       then 'HAUT'
    when 'FACTURE_ABONNEMENT_EMISE'       then 'MOYEN'
    when 'FACTURE_ABONNEMENT_ENVOYEE'     then 'INFO'
    when 'FACTURE_ABONNEMENT_ANNULEE'     then 'HAUT'
    when 'FACTURES_ABONNEMENT_RATTRAPAGE' then 'MOYEN'
    -- 🪙 CORRECTIF 68 — quotas IA : catalogue des packs, reprise
    --   d'attribution, geste commercial. Un DON de quotas est de l'argent
    --   donné : il doit être aussi visible qu'un changement de permission.
    when 'AGENT_IA_PACK'                  then 'MOYEN'
    when 'AGENT_IA_PACK_ENREGISTRE'       then 'MOYEN'
    when 'AGENT_IA_PACK_SUPPRIME'         then 'HAUT'
    when 'AGENT_IA_ATTRIBUTION_ANNULEE'   then 'HAUT'
    when 'AGENT_IA_GESTE'                 then 'CRITIQUE'
"""


def echec(message: str) -> None:
    print(f"ARRET : {message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if not SOURCE.exists():
        echec(f"source introuvable : {SOURCE}")
    if not CIBLE.exists():
        echec(f"cible introuvable : {CIBLE}")

    source = SOURCE.read_text(encoding="utf-8")

    # ── 1. Extraction de la déclaration complète (jusqu'au `$$;` final).
    debut = source.find("create or replace function public.audit_niveau")
    if debut < 0:
        echec("audit_niveau introuvable dans la migration 39")

    if source.count("create or replace function public.audit_niveau") != 1:
        echec("plusieurs définitions de audit_niveau : extraction ambiguë")

    fin = source.find("$$;", debut)
    if fin < 0:
        echec("fin de audit_niveau introuvable (pas de $$;)")

    bloc = source[debut:fin + 3]
    if len(bloc) < 1000:
        echec(f"bloc extrait suspect (seulement {len(bloc)} caractères)")

    # ── 2. Vérifications du bloc extrait.
    if bloc.count("else 'INFO'") != 1:
        echec("attendu exactement un `else 'INFO'` dans audit_niveau")

    for controle in ("immutable", "'AGENT_IA_CONFIG'", "'DEVISE_CONFIG'", "'RAPPORT'"):
        if controle not in bloc:
            echec(f"le bloc extrait ne contient pas {controle} : mauvaise version ?")

    # ── 3. Insertion des nouvelles actions AVANT le `else 'INFO'`.
    if "AGENT_IA_GESTE" in bloc:
        echec("AGENT_IA_GESTE est déjà présent : le patch a peut-être déjà été appliqué")

    patche = bloc.replace("    else 'INFO'", AJOUTS + "    else 'INFO'", 1)

    if patche.count("AGENT_IA_GESTE") != 1:
        echec("l'insertion des nouvelles actions a échoué")
    if patche.count("else 'INFO'") != 1:
        echec("le `else 'INFO'` a été altéré")
    # Le patch ne doit RIEN avoir retiré du mapping d'origine.
    if len(patche) <= len(bloc):
        echec("le bloc patché est plus court que l'original")

    # ── 4. Remplacement du marqueur dans la migration 68.
    cible = CIBLE.read_text(encoding="utf-8")
    if cible.count(MARQUEUR) != 1:
        echec(f"attendu exactement un marqueur {MARQUEUR} dans la migration 68")

    cible = cible.replace(MARQUEUR, patche)
    CIBLE.write_text(cible, encoding="utf-8")

    print(f"OK : audit_niveau patchée ({len(bloc)} -> {len(patche)} caractères)")
    print(f"OK : {len(AJOUTS.strip().splitlines())} lignes insérées (dont commentaires)")


if __name__ == "__main__":
    main()
