-- ============================================================================
--  MODULE 21 ter ter — DOSSIERS DE L'AGENT : CLOISONNEMENT STRICT
--  Migration 20260916000049_agent_dossiers_libres.sql
-- ============================================================================
--
--  À exécuter APRÈS les migrations 47 et 48. IDEMPOTENTE.
--
--  CE QUI CHANGE
--  -------------
--  La migration 47 laissait l'agent voir, dans « Vérifications » et
--  « Activations », SES dossiers ET les dossiers LIBRES (non attribués). À
--  l'usage, cela affichait une boutique qui n'appartenait PAS à l'agent.
--
--  Désormais :
--    • `rpc_activation_lister` est STRICTEMENT cloisonné : un agent ne voit
--      que les dossiers où `agent_id = lui`. Plus aucun dossier étranger ne
--      s'affiche dans ses listes de travail.
--    • Les dossiers LIBRES (agent_id IS NULL) ne disparaissent pas : ils sont
--      listés à part par `rpc_agent_dossiers_libres()`, que l'agent consulte
--      quand il veut « prendre » un dossier (l'agent est un secours qui va
--      vite). La prise en charge reste explicite et journalisée.
--
--  Aucun rôle plateforme n'est affecté : gestionnaire, finance et Super Admin
--  gardent la vue complète.
-- ============================================================================


-- ============================================================================
--  1. LISTE DES DOSSIERS — CLOISONNEMENT STRICT POUR L'AGENT
-- ============================================================================

do $m49$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_activation_lister'
   limit 1;

  if v_def is null then
    raise warning 'm49 : rpc_activation_lister introuvable — étape ignorée.';
    return;
  end if;

  if position('m49' in v_def) > 0 then
    raise notice 'm49 : rpc_activation_lister déjà cloisonné strictement.';
    return;
  end if;

  v_new := regexp_replace(
    v_def,
    $m49motif$and \(not public\.est_agent_terrain\(\)
                or e\.agent_id = auth\.uid\(\)
                or e\.agent_id is null\)$m49motif$,
    $m49repl$-- m49 : l'agent ne voit QUE ses dossiers (les libres sont listés à part).
           and (not public.est_agent_terrain()
                or e.agent_id = auth.uid())$m49repl$,
    'g');

  if v_new = v_def then
    raise warning 'm49 : motif absent de rpc_activation_lister — cloisonnement strict NON appliqué.';
  else
    execute v_new;
    raise notice 'm49 : rpc_activation_lister cloisonné STRICTEMENT sur l''agent.';
  end if;
end $m49$;


-- ============================================================================
--  2. DOSSIERS LIBRES — À PRENDRE EN CHARGE PAR L'AGENT
-- ============================================================================
--  Un dossier libre est une entreprise NON rattachée à un agent
--  (`agent_id IS NULL`) et encore en cours d'activation. L'agent les voit
--  ici, séparément, et choisit explicitement de les prendre en charge
--  (`rpc_agent_rattacher_entreprise`).

create or replace function public.rpc_agent_dossiers_libres(
  p_limite integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limite integer := least(greatest(coalesce(p_limite, 100), 1), 300);
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not public.est_agent_terrain() then
    raise exception 'DROIT_REFUSE|Réservé à un agent terrain.';
  end if;

  return coalesce((
    select jsonb_agg(s.t order by s.created_at desc)
      from (
        select jsonb_build_object(
                 'entreprise_id', e.id,
                 'nom', e.nom,
                 'statut', e.statut::text,
                 'etape', coalesce(e.activation_etape, 'actif'),
                 'ville', (select v.nom from public.villes v where v.id = e.ville_id),
                 'responsable', (
                   select coalesce(nullif(btrim(u.nom), ''), u.email)
                     from public.utilisateurs u
                    where u.entreprise_id = e.id and u.parent_id is null
                    order by u.created_at limit 1),
                 'contact', (
                   select u.email from public.utilisateurs u
                    where u.entreprise_id = e.id and u.parent_id is null
                    order by u.created_at limit 1),
                 'telephone', (
                   select to_jsonb(u) ->> 'telephone' from public.utilisateurs u
                    where u.entreprise_id = e.id and u.parent_id is null
                    order by u.created_at limit 1),
                 'created_at', e.created_at
               ) as t,
               e.created_at
          from public.entreprises e
         where e.agent_id is null
           and coalesce(e.activation_etape, 'actif')
               in ('en_attente_verification', 'verifie')
         order by e.created_at desc
         limit v_limite
      ) s
  ), '[]'::jsonb);
end;
$$;

comment on function public.rpc_agent_dossiers_libres(integer) is
  'Module 21 ter — Dossiers NON attribués (agent_id NULL) en cours d''activation, proposés à la prise en charge par un agent terrain.';

revoke all on function public.rpc_agent_dossiers_libres(integer) from public, anon;
grant execute on function public.rpc_agent_dossiers_libres(integer) to authenticated;


-- ============================================================================
--  VÉRIFICATION — RUN SÉPARÉ, SESSION AGENT
-- ============================================================================
--  -- 1. Ne doit contenir QUE les dossiers de l'agent (aucun dossier libre).
--  select jsonb_array_length(public.rpc_activation_lister(null));
--
--  -- 2. Les dossiers libres, listés à part.
--  select public.rpc_agent_dossiers_libres(50);
-- ============================================================================
--  FIN — correctif 49.
-- ============================================================================
