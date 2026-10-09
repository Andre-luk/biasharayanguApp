#!/usr/bin/env python3
# Génère la migration 70 : aligne la garde de `rpc_activation_verifier` sur ce
# que l'application déclare DÉJÀ pour l'agent de terrain.
#
# POURQUOI UN SCRIPT
# ------------------
# La fonction entière doit être redéfinie (`create or replace`), et elle fait
# plusieurs dizaines de lignes. La retaper à la main risquerait d'en perdre une
# instruction — sur une fonction du chemin d'activation, ce serait grave et
# silencieux. On extrait donc la version en vigueur et on ne remplace QUE la
# ligne de garde, en ASSERTANT que le remplacement a bien eu lieu une fois.
#
# CE QUI EST MODIFIÉ, ET CE QUI NE L'EST PAS
# ------------------------------------------
#   • MODIFIÉ : `rpc_activation_verifier` accepte désormais AGENT_TERRAIN.
#     L'application lui donne déjà l'écran (`verificationComptes` voir+valider)
#     : sans cela, son bouton « Vérifier » était refusé par le serveur.
#   • NON MODIFIÉ : `rpc_activation_valider_finance` (l'ARGENT). La séparation
#     des responsabilités du module 14 — le gestionnaire vérifie, la FINANCE
#     active — reste intacte. L'agent ne valide pas un paiement.
#   • NON MODIFIÉ : les correctifs 63/64 (l'agent ne suspend, ne réactive ni ne
#     supprime un compte). Cet alignement ne les touche pas.

import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
SOURCE = RACINE / "supabase/migrations/20260916000018_module14_activation.sql"
CIBLE = RACINE / "supabase/migrations/20260916000070_agent_verifie_dossier.sql"

SIGNATURE = "create or replace function public.rpc_activation_verifier"
ANCIENNE = "  if v_role not in ('GESTIONNAIRE_COMPTES', 'SUPER_ADMIN') then"
NOUVELLE = ("  --  ⚠️ CORRECTIF 70 — l'AGENT DE TERRAIN est ajouté.\n"
            "  --  L'application lui donne DÉJÀ cet écran (`verificationComptes`\n"
            "  --  voir+valider) : sans cette ligne, son bouton « Vérifier »\n"
            "  --  était visible puis refusé par le serveur — le pire des cas,\n"
            "  --  parce qu'il fait croire à une panne.\n"
            "  --  Il VÉRIFIE (aucun argent en jeu) ; il n'ACTIVE pas : la\n"
            "  --  validation du paiement reste à la Finance (migration 14).\n"
            "  if v_role not in ('GESTIONNAIRE_COMPTES', 'SUPER_ADMIN', 'AGENT_TERRAIN') then")

ENTETE = """-- ============================================================================
--  biashara_yangu — CORRECTIF 70 : L'AGENT PEUT VÉRIFIER UN DOSSIER
--  Migration 20260916000070_agent_verifie_dossier.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : base de données uniquement.
--
--  LE DÉFAUT CORRIGÉ
--  -----------------
--  `rpc_activation_verifier` n'autorisait que GESTIONNAIRE_COMPTES et
--  SUPER_ADMIN. Or `lib/services/permission_service.dart` donne à
--  l'AGENT_TERRAIN la page `verificationComptes` (voir + valider).
--
--  Conséquence : l'agent voyait le dossier, voyait le bouton « Vérifier », et
--  se faisait refuser par le serveur. Un écran qui propose une action pour la
--  refuser ensuite est pire qu'un écran qui ne la propose pas : l'agent croit
--  à une panne, recommence, et perd la confiance dans l'outil.
--
--  Le patron décrit précisément ce geste : « avant que l'agent confirme le
--  compte ou valide, il faut un code de validation ». L'agent CONFIRME donc le
--  compte — c'est cette étape-ci. Le correctif 69 lui fournit le contrôle.
--
--  CE QUI NE CHANGE PAS — ET C'EST DÉLIBÉRÉ
--  ----------------------------------------
--  1. `rpc_activation_valider_finance` (l'ARGENT) reste réservée à
--     FINANCE_LAPERLE et SUPER_ADMIN. La séparation des responsabilités posée
--     par le module 14 — le gestionnaire vérifie, la FINANCE active — n'est
--     PAS touchée : l'agent ne valide pas un paiement.
--  2. Les correctifs 63 et 64 restent en vigueur : l'agent ne suspend, ne
--     réactive et ne supprime AUCUN compte. Cet alignement ne les concerne pas.
--  3. Aucune autre fonction n'est modifiée. La fonction est reprise À
--     L'IDENTIQUE, seule la ligne de garde change.
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS le correctif 69.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LA FONCTION, REPRISE À L'IDENTIQUE — UNE SEULE LIGNE CHANGE
--     `create or replace` conserve les privilèges : inutile de rejouer les
--     `revoke` / `grant` de la migration 14.
-- ============================================================================

"""

CONTROLE = """

-- ============================================================================
--  2. CONTRÔLE
-- ============================================================================

do $verif_agent_verifie$
declare
  v_source text;
  v_finance text;
begin
  select pg_get_functiondef(p.oid) into v_source
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_activation_verifier';

  if v_source is null then
    raise exception 'Correctif 70 : rpc_activation_verifier introuvable.';
  end if;

  if v_source not like '%AGENT_TERRAIN%' then
    raise exception 'Correctif 70 : l''agent de terrain n''est PAS autorise a verifier — le correctif n''a pas pris.';
  end if;

  --  ⚠️ On vérifie AUSSI ce qui ne devait PAS changer : si l'agent se
  --  retrouvait un jour dans la validation du paiement, ce serait une
  --  escalation de droits silencieuse. Le contrôle l'interdit ici.
  select pg_get_functiondef(p.oid) into v_finance
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_activation_valider_finance';

  if v_finance is not null and v_finance like '%AGENT_TERRAIN%' then
    raise exception 'Correctif 70 : l''agent de terrain apparait dans la validation des paiements — ce ne doit PAS arriver, la separation des responsabilites est volee.';
  end if;

  raise notice 'Correctif 70 : l''agent de terrain peut verifier un dossier ; la validation du paiement reste a la Finance.';
end $verif_agent_verifie$;


-- ============================================================================
--  RAPPORT FINAL
--  ⚠️ En ENTIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select 'Correctif 70 — agent verifie le dossier' as chantier,
       (select pg_get_functiondef(p.oid) like '%AGENT_TERRAIN%'
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'rpc_activation_verifier')
                                                  as agent_autorise_a_verifier,
       (select pg_get_functiondef(p.oid) like '%AGENT_TERRAIN%'
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'rpc_activation_valider_finance')
                                                  as agent_dans_la_finance,
       (select public.mon_role() is not null)     as session_active;
"""


def echec(message: str) -> None:
    print(f"ARRET : {message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if not SOURCE.exists():
        echec(f"source introuvable : {SOURCE}")

    texte = SOURCE.read_text(encoding="utf-8")

    if texte.count(SIGNATURE) != 1:
        echec(f"{texte.count(SIGNATURE)} definitions de rpc_activation_verifier "
              "(extraction ambigue)")

    debut = texte.find(SIGNATURE)
    fin = texte.find("$$;", debut)
    if fin < 0:
        echec("fin de rpc_activation_verifier introuvable (pas de $$;)")

    bloc = texte[debut:fin + 3]
    if len(bloc) < 1500:
        echec(f"bloc extrait suspect ({len(bloc)} caracteres)")

    #  Garde-fous : on refuse d'extraire autre chose que la bonne fonction.
    for controle in ("rpc_activation_verifier", "ACTIVATION_VERIFIEE",
                     "v_role not in"):
        if controle not in bloc:
            echec(f"le bloc extrait ne contient pas {controle}")

    if bloc.count(ANCIENNE) != 1:
        echec("la ligne de garde attendue n'apparait pas exactement une fois")
    if "AGENT_TERRAIN" in bloc:
        echec("AGENT_TERRAIN est deja present : le patch a peut-etre deja ete applique")

    patche = bloc.replace(ANCIENNE, NOUVELLE, 1)

    if len(patche) <= len(bloc):
        echec("le bloc patche est plus court que l'original")
    if patche.count("AGENT_TERRAIN") != 1:
        echec("AGENT_TERRAIN n'a pas ete insere exactement une fois")
    #  Rien d'autre ne doit avoir bougé : on compare hors garde.
    if patche.replace(NOUVELLE, "").replace(ANCIENNE, "") != \
       bloc.replace(ANCIENNE, ""):
        echec("le patch a modifie autre chose que la ligne de garde")

    CIBLE.write_text(ENTETE + patche + CONTROLE, encoding="utf-8")

    print("OK : rpc_activation_verifier alignee "
          f"({len(bloc)} -> {len(patche)} caracteres)")
    print(f"OK : ecrit {CIBLE.name}")


if __name__ == "__main__":
    main()
