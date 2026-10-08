-- ============================================================================
--  biashara_yangu — CORRECTIF 64 : L'AGENT CORRIGE, MAIS NE SUSPEND PAS
--  Migration 20260916000064_agent_corrige_sans_changer_le_statut.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : correction de base uniquement.
--
--  CE QUE LE CORRECTIF 63 AVAIT SERRÉ — ET QU'IL FAUT DESSERRER
--  ------------------------------------------------------------
--  Pour retirer à l'agent le droit de suspendre un compte, le 63 lui a
--  interdit TOUTE écriture sur `entreprises` et `utilisateurs`. C'était le
--  choix le plus sûr, mais le patron a tranché : **l'agent doit pouvoir
--  corriger les informations d'un dossier** qu'il suit (nom, ville, activité,
--  téléphone…) — il ne doit pas pouvoir changer son STATUT.
--
--  LE VRAI BESOIN, EN UNE PHRASE
--  -----------------------------
--     L'agent MODIFIE ce qui décrit le dossier,
--     il ne change JAMAIS si le compte est actif ou suspendu.
--
--  COMMENT ON DISTINGUE LES DEUX — SANS RIEN CASSER
--  ------------------------------------------------
--  Le point délicat : les RPC d'activation (`rpc_activation_verifier`,
--  `rpc_activation_valider_finance`) changent bel et bien le statut, et
--  l'agent les utilise légitimement. Un simple déclencheur « l'agent ne
--  touche pas au statut » les aurait bloquées.
--
--  La distinction repose sur `current_user`, et elle est nette :
--     • une écriture DIRECTE depuis l'application (PostgREST) s'exécute en
--       tant que rôle `authenticated` ;
--     • un passage par une RPC `security definer` s'exécute en tant que
--       PROPRIÉTAIRE de la fonction — le workflow d'activation.
--
--  Le déclencheur n'intercepte donc QUE les écritures directes du client.
--  Pour que `current_user` reste fiable, il est écrit **sans** `security
--  definer` : c'est volontaire et commenté dans le code.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--    1. REMPLACE les deux policies restrictives du 63 qui bloquaient TOUTE
--       modification (sur `entreprises` et `utilisateurs`) par un contrôle
--       PRÉCIS : le statut (et `valide`) ne change pas, le reste oui.
--    2. CONSERVE le blocage de la SUPPRESSION : l'agent ne supprime ni
--       entreprise ni compte utilisateur (demande du patron).
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS le correctif 63.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE CONTRÔLE, PRÉCIS, SUR LE STATUT D'UNE ENTREPRISE
-- ============================================================================

create or replace function public.bloquer_statut_par_agent()
returns trigger
language plpgsql
--  ⚠️ PAS de `security definer` : `current_user` doit refléter le rôle RÉEL
--  de l'instruction. C'est ce qui permet d'intercepter les écritures
--  directes de l'application sans toucher aux RPC d'activation.
set search_path = public
as $$
begin
  if current_user = 'authenticated'
     and public.est_agent_terrain()
     and new.statut is distinct from old.statut then
    raise exception
      'DROIT_REFUSE|Seul la Finance ou le Super Admin peut suspendre ou reactiver un compte.';
  end if;

  return new;
end;
$$;

comment on function public.bloquer_statut_par_agent() is
  'Correctif 64 — Refuse un changement de statut d''entreprise écrit DIRECTEMENT par un agent terrain. Les RPC d''activation (security definer) ne sont pas concernées.';

drop trigger if exists trg_entreprises_statut_par_agent on public.entreprises;
create trigger trg_entreprises_statut_par_agent
  before update on public.entreprises
  for each row
  execute function public.bloquer_statut_par_agent();


-- ============================================================================
--  2. LE MÊME CONTRÔLE SUR UN COMPTE UTILISATEUR
-- ============================================================================
--  Désactiver un compte, c'est passer `utilisateurs.valide` à false. L'agent
--  peut corriger le nom ou le téléphone d'un utilisateur de son dossier, mais
--  pas décider si son compte est actif.

create or replace function public.bloquer_activation_par_agent()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user = 'authenticated'
     and public.est_agent_terrain()
     and new.valide is distinct from old.valide then
    raise exception
      'DROIT_REFUSE|Seul la Finance ou le Super Admin peut activer ou desactiver un compte.';
  end if;

  return new;
end;
$$;

comment on function public.bloquer_activation_par_agent() is
  'Correctif 64 — Refuse un changement de `valide` écrit DIRECTEMENT par un agent terrain.';

drop trigger if exists trg_utilisateurs_valide_par_agent on public.utilisateurs;
create trigger trg_utilisateurs_valide_par_agent
  before update on public.utilisateurs
  for each row
  execute function public.bloquer_activation_par_agent();


-- ============================================================================
--  3. LE BLOCAGE GÉNÉRAL DU 63 EST RETIRÉ (la modification redevient possible)
-- ============================================================================
--  Seules les policies de MODIFICATION sont retirées : celles de SUPPRESSION
--  restent en place (l'agent ne supprime rien).

drop policy if exists entreprises_agent_sans_modification on public.entreprises;
drop policy if exists utilisateurs_agent_sans_modification on public.utilisateurs;


-- ============================================================================
--  4. CONTRÔLE
-- ============================================================================

do $verif_agent$
declare
  v_nb_update integer;
  v_nb_delete integer;
  v_nb_trg    integer;
begin
  --  4.a Les blocages de modification sont bien RETIRÉS.
  select count(*) into v_nb_update
    from pg_policies
   where schemaname = 'public'
     and policyname in ('entreprises_agent_sans_modification',
                        'utilisateurs_agent_sans_modification');

  if v_nb_update <> 0 then
    raise exception 'Correctif 64 : % blocage(s) de modification encore en place.', v_nb_update;
  end if;

  --  4.b Les blocages de SUPPRESSION sont bien CONSERVÉS.
  select count(*) into v_nb_delete
    from pg_policies
   where schemaname = 'public'
     and policyname in ('entreprises_agent_sans_suppression',
                        'utilisateurs_agent_sans_suppression');

  if v_nb_delete <> 2 then
    raise exception 'Correctif 64 : suppression — % policy(ies) sur 2 presente(s).', v_nb_delete;
  end if;

  --  4.c Les deux déclencheurs sont actifs.
  select count(*) into v_nb_trg
    from pg_trigger
   where tgname in ('trg_entreprises_statut_par_agent',
                    'trg_utilisateurs_valide_par_agent')
     and not tgisinternal;

  if v_nb_trg <> 2 then
    raise exception 'Correctif 64 : % declencheur(s) sur 2 actif(s).', v_nb_trg;
  end if;

  raise notice 'Correctif 64 : l agent corrige les informations, jamais le statut.';
end $verif_agent$;


-- ============================================================================
--  RAPPORT FINAL — ce que l'agent peut faire, désormais
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select t.table_cible,
       t.operation,
       t.regle,
       t.verdict
  from (
    select 'entreprises' as table_cible,
           'MODIFIER les informations' as operation,
           'aucune policy restrictive' as regle,
           'AUTORISE (correctif 64)' as verdict
    union all
    select 'entreprises',
           'CHANGER LE STATUT (suspendre/activer)',
           'trg_entreprises_statut_par_agent',
           'REFUSE a l''agent — direct uniquement'
    union all
    select 'entreprises',
           'SUPPRIMER',
           'entreprises_agent_sans_suppression',
           'REFUSE a l''agent'
    union all
    select 'utilisateurs',
           'MODIFIER les informations',
           'aucune policy restrictive',
           'AUTORISE (correctif 64)'
    union all
    select 'utilisateurs',
           'ACTIVER / DESACTIVER (valide)',
           'trg_utilisateurs_valide_par_agent',
           'REFUSE a l''agent — direct uniquement'
    union all
    select 'utilisateurs',
           'SUPPRIMER',
           'utilisateurs_agent_sans_suppression',
           'REFUSE a l''agent'
    union all
    select 'remise a zero',
           'EFFACER TOUTE LA PLATEFORME',
           'garde-fou est_super_admin() (63)',
           'REFUSE a tout sauf Super Admin'
  ) t
 order by t.table_cible, t.operation;


-- ============================================================================
--  NOTE — LE WORKFLOW D'ACTIVATION N'EST PAS TOUCHÉ
--  ------------------------------------------------------------------------
--  `rpc_activation_verifier` et `rpc_activation_valider_finance` changent le
--  statut : elles passent par le PROPRIÉTAIRE de la fonction et ne sont donc
--  pas interceptées. L'agent conserve son parcours complet — création du
--  dossier, vérification, validation du paiement.
--
--  Ce qu'il perd définitivement :
--    • suspendre ou réactiver un compte depuis la fiche entreprise ;
--    • activiver/désactiver un compte utilisateur ;
--    • supprimer une entreprise ou un compte.
--
--  ⚠️ SI UN AGENT REÇOIT UN REFUS alors qu'il corrige simplement une fiche :
--  c'est que l'écran passe par une écriture directe sur `statut` (le cas de
--  « Suspendre / Activer »). Transmettez le message exact : il est préfixé par
--  `DROIT_REFUSE|` et le texte qui suit est destiné à l'utilisateur.
-- ============================================================================
