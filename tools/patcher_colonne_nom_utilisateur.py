#!/usr/bin/env python3
# Génère la migration 71 : corrige la colonne `nom_complet`, qui N'EXISTE PAS.
#
# LE BUG, ET COMMENT IL EST ARRIVÉ EN PRODUCTION
# ----------------------------------------------
# Les migrations 67, 68 et 69 lisaient le nom d'un utilisateur avec
# `utilisateurs.nom_complet`. Cette colonne n'a JAMAIS existé : elle n'apparaît
# que dans ces trois fichiers. Le nom se lit `nom` (avec `email` en secours),
# comme le fait déjà la migration 47 en production.
#
# Le contrôle de syntaxe (libpg-query) ne pouvait PAS le voir : PL/pgSQL ne
# valide les noms de colonnes qu'à la PREMIÈRE EXÉCUTION. La migration
# s'installe donc sans broncher, et l'erreur n'apparaît que chez l'utilisateur :
#
#   PostgrestException: column demandeur.nom_complet does not exist (42703)
#
# Elle a été trouvée dans le journal de démarrage de l'application, une fois
# la v2.8.0 installée — c'est-à-dire trop tard, puisque la version est publiée.
#
# POURQUOI UNE MIGRATION SUPPLÉMENTAIRE
# -------------------------------------
# Corriger les trois fichiers ne suffit pas : les fonctions FAUTIVES sont déjà
# installées dans la base de l'utilisateur. Il faut les RÉINSTALLER. On
# réextrait donc leur texte, corrigé, depuis les fichiers sources — sans jamais
# le retaper, pour ne pas risquer d'y perdre une instruction au passage.

import re
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
MIGRATIONS = RACINE / "supabase/migrations"
CIBLE = MIGRATIONS / "20260916000071_fix_colonne_nom_utilisateur.sql"

# (fichier source, fonction à réinstaller)
A_REINSTALLER = [
    ("20260916000067_factures_abonnement.sql", "facture_abonnement_generer_interne"),
    ("20260916000068_quotas_ia_crud.sql", "rpc_agent_ia_attributions"),
    ("20260916000069_code_validation_agent.sql", "rpc_agent_codes_lister"),
    ("20260916000069_code_validation_agent.sql", "rpc_agent_dossiers_sans_code"),
]

ENTETE = """-- ============================================================================
--  biashara_yangu — CORRECTIF 71 : LA COLONNE `nom_complet` N'EXISTE PAS
--  Migration 20260916000071_fix_colonne_nom_utilisateur.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : correction de base uniquement.
--
--  LE DÉFAUT CORRIGÉ — ET IL ÉTAIT VISIBLE CHEZ L'UTILISATEUR
--  ----------------------------------------------------------
--  Les migrations 67, 68 et 69 lisaient le nom d'un utilisateur avec
--  `utilisateurs.nom_complet`. Cette colonne n'a jamais existé : elle
--  n'apparaît QUE dans ces trois fichiers. Le nom se lit `nom`, avec `email`
--  en secours — l'idiome déjà utilisé en production par la migration 47
--  (`coalesce(nullif(btrim(u.nom), ''), u.email)`).
--
--  Symptôme relevé dans le journal de l'application, v2.8.0 installée :
--
--    CodeValidationAgentService (le chargement des codes) :
--      PostgrestException(message: column demandeur.nom_complet does not
--      exist, code: 42703)
--
--  ⚠️ POURQUOI LE CONTRÔLE DE SYNTAXE NE POUVAIT PAS LE VOIR : PL/pgSQL ne
--  valide PAS les noms de colonnes à la création d'une fonction — seulement à
--  sa PREMIÈRE EXÉCUTION. La migration s'installe donc sans la moindre erreur,
--  et le défaut ne se révèle que chez l'utilisateur, au moment où il ouvre
--  l'écran. C'est la leçon de ce correctif : une migration « valide » n'est pas
--  une migration qui fonctionne.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--  Elle RÉINSTALLE les quatre fonctions qui référençaient la colonne
--  inexistante, avec le nom corrigé. Les fonctions sont reprises depuis leurs
--  fichiers d'origine (67, 68, 69) DÉJÀ CORRIGÉS : une seule expression change
--  dans chacune, rien d'autre.
--
--    1. `facture_abonnement_generer_interne`  (correctif 67) — nom de l'auteur
--       de la facture ;
--    2. `rpc_agent_ia_attributions`           (correctif 68) — nom du
--       collaborateur et de celui qui lui a attribué des quotas ;
--    3. `rpc_agent_codes_lister`              (correctif 69) — noms du
--       demandeur, de l'émetteur et du valideur du code ;
--    4. `rpc_agent_dossiers_sans_code`        (correctif 69) — nom de celui qui
--       a vérifié le dossier.
--
--  ⚠️ `create or replace` CONSERVE LES PRIVILÈGES : inutile de rejouer les
--  `revoke` / `grant` des migrations d'origine.
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS les correctifs 67, 68 et 69.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  LES QUATRE FONCTIONS, RÉINSTALLÉES AVEC LE NOM CORRIGÉ
-- ============================================================================

"""

CONTROLE = r"""

-- ============================================================================
--  2. CONTRÔLE
--
--  ⚠️ Ce contrôle vérifie DEUX choses, et la seconde est celle qui aurait
--  attrapé le défaut : que les fonctions ne mentionnent plus `nom_complet`,
--  ET que les colonnes qu'elles utilisent EXISTENT vraiment.
-- ============================================================================

do $verif_nom_utilisateur$
declare
  v_nom     text;
  v_def     text;
  v_restant text := '';
  v_manque  text := '';
begin
  --  1. Plus aucune trace de la colonne inexistante.
  foreach v_nom in array array[
    'facture_abonnement_generer_interne',
    'rpc_agent_ia_attributions',
    'rpc_agent_codes_lister',
    'rpc_agent_dossiers_sans_code'
  ] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_nom;

    if v_def is null then
      raise exception 'Correctif 71 : la fonction % est introuvable — executez d''abord les correctifs 67, 68 et 69.', v_nom;
    end if;

    if position('nom_complet' in v_def) > 0 then
      v_restant := v_restant || v_nom || ' ';
    end if;
  end loop;

  if v_restant <> '' then
    raise exception 'Correctif 71 : % reference(nt) encore nom_complet — la correction n''a pas pris.', v_restant;
  end if;

  --  2. ⚠️ LE CONTRÔLE QUI MANQUAIT : les colonnes utilisées EXISTENT-elles ?
  --  C'est cette vérification, faite sur `utilisateurs`, qui aurait empêché le
  --  défaut d'arriver chez l'utilisateur.
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'utilisateurs'
       and column_name in ('nom', 'email')
     having count(*) = 2
  ) then
    raise exception 'Correctif 71 : la table utilisateurs n''a pas les colonnes nom et email — verifiez-la a la main avant d''aller plus loin.';
  end if;

  raise notice 'Correctif 71 : les 4 fonctions lisent desormais utilisateurs.nom (secours : email), et ces colonnes existent bien.';
end $verif_nom_utilisateur$;


-- ============================================================================
--  RAPPORT FINAL
--  ⚠️ En ENTIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select 'Correctif 71 — colonne nom_complet' as chantier,
       (select count(*)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('facture_abonnement_generer_interne',
                             'rpc_agent_ia_attributions',
                             'rpc_agent_codes_lister',
                             'rpc_agent_dossiers_sans_code')
           and pg_get_functiondef(p.oid) not like '%nom_complet%')
                                as fonctions_corrigees,
       (select count(*)
          from information_schema.columns
         where table_schema = 'public' and table_name = 'utilisateurs'
           and column_name in ('nom', 'email'))
                                as colonnes_nom_et_email,
       (select public.mon_role() is not null) as session_active;
"""


def echec(message: str) -> None:
    print(f"ARRET : {message}", file=sys.stderr)
    sys.exit(1)


def extraire(chemin: Path, fonction: str) -> str:
    """Le texte complet de la fonction, depuis sa definition jusqu'a `$$;`."""
    texte = chemin.read_text(encoding="utf-8")

    signature = f"create or replace function public.{fonction}"
    if texte.count(signature) != 1:
        echec(f"{fonction} : {texte.count(signature)} definition(s) dans "
              f"{chemin.name} (extraction ambigue)")

    debut = texte.find(signature)
    fin = texte.find("$$;", debut)
    if fin < 0:
        echec(f"{fonction} : fin de fonction introuvable (`$$;`)")

    bloc = texte[debut:fin + 3]
    if len(bloc) < 300:
        echec(f"{fonction} : bloc extrait suspect ({len(bloc)} caracteres)")
    if fonction not in bloc:
        echec(f"{fonction} : le bloc extrait ne contient pas son propre nom")
    if "nom_complet" in bloc:
        echec(f"{fonction} : contient ENCORE nom_complet — corriger la source "
              "avant de generer cette migration")
    if "utilisateurs" not in bloc:
        echec(f"{fonction} : ne joint pas `utilisateurs` — mauvais bloc ?")
    return bloc


def main() -> None:
    blocs = []
    for nom_fichier, fonction in A_REINSTALLER:
        chemin = MIGRATIONS / nom_fichier
        if not chemin.exists():
            echec(f"source introuvable : {chemin}")
        blocs.append(extraire(chemin, fonction))
        print(f"OK : {fonction} extraite de {nom_fichier}")

    CIBLE.write_text(ENTETE + "\n\n".join(blocs) + "\n" + CONTROLE,
                     encoding="utf-8")
    print(f"OK : ecrit {CIBLE.name} ({sum(len(b) for b in blocs)} caracteres "
          f"de fonctions)")


if __name__ == "__main__":
    main()
