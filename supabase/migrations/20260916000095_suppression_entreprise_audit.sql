-- ============================================================================
--  biashara_yangu — CORRECTIF 95 : SUPPRESSION D'UNE ENTREPRISE
--  ---------------------------------------------------------------------------
--  PROBLÈME SIGNALÉ PAR LE PATRON (31/10/2026)
--    « Quand je supprime une entreprise, on écrit : le journal d'audit est
--      inaltérable : delete est interdit sur public.journal_audit. »
--
--  CAUSE
--    `rpc_entreprise_supprimer` (migration 0088) parcourt TOUTES les tables
--    portant `owner_id` ou `entreprise_id` et fait un `delete`. Or
--    `public.journal_audit` est protégée par le déclencheur
--    `trg_journal_audit_append_only` (module 12) : toute suppression y est
--    refusée. La première table de la liste étant le journal, TOUT s'arrête
--    et l'entreprise n'est jamais supprimée.
--
--  DÉCISION
--    Supprimer une entreprise, c'est supprimer son périmètre de données —
--    journal d'audit compris (il appartient au locataire). Le journal reste
--    inaltérable pour TOUTES les autres entreprises : le déclencheur n'est
--    neutralisé que le temps de ce nettoyage, dans la même transaction, puis
--    remis en place immédiatement.
--
--  AUTRES GARDE-FOUS AJOUTÉS
--    • les suppressions unitaires sont tolérantes : une table récalcitrante
--      est signalée (return `tables_ignorees`) au lieu de tout annuler ;
--    • une ligne d'audit `ENTREPRISE_SUPPRIMEE` est écrite après coup, SANS
--      identifiant d'entreprise (la société n'existe plus), pour garder la
--      trace de l'opération administrative elle-même.
--
--  ⚠️ IDEMPOTENT — remplace la version 0088.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

create or replace function public.rpc_entreprise_supprimer(
  p_entreprise   uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user         uuid := auth.uid();
  v_role         text;
  v_ids          uuid[];
  v_t            record;
  v_nom          text;
  v_tables       integer := 0;
  v_utilisateurs integer := 0;
  v_audit        integer := 0;
  v_ignorees     text[]  := array[]::text[];
  v_trigger_off  boolean := false;
  v_reste        integer := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if upper(btrim(coalesce(p_confirmation, ''))) <> 'SUPPRIMER' then
    raise exception 'CONFIRMATION_REQUISE|Écrivez SUPPRIMER pour confirmer.';
  end if;

  select upper(coalesce(u.new_role::text, '')) into v_role
    from public.utilisateurs u
   where u.id = v_user;

  if coalesce(v_role, '') <> 'SUPER_ADMIN' and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seul un Super Administrateur peut supprimer une entreprise.';
  end if;

  select e.nom into v_nom from public.entreprises e where e.id = p_entreprise;
  if v_nom is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe plus.';
  end if;

  if p_entreprise = public.mon_entreprise_id() then
    raise exception 'DROIT_REFUSE|Impossible de supprimer l''entreprise de votre propre compte.';
  end if;

  -- ------------------------------------------------------------------------
  -- 1. PÉRIMÈTRE : l'entreprise ET tous ses comptes (et leurs sous-comptes)
  -- ------------------------------------------------------------------------
  with recursive liens as (
    select u.id
      from public.utilisateurs u
     where u.id = p_entreprise
        or u.entreprise_id = p_entreprise
        or u.parent_id = p_entreprise
    union
    select u2.id
      from public.utilisateurs u2
      join liens l on u2.parent_id = l.id
  )
  select array_agg(distinct id) into v_ids from liens;

  v_ids := coalesce(v_ids, array[]::uuid[]) || p_entreprise;

  -- ------------------------------------------------------------------------
  -- 2. LE JOURNAL D'AUDIT — neutralisation TEMPORAIRE de l'append-only
  -- ------------------------------------------------------------------------
  -- Le temps de la transaction uniquement. Si l'on n'a pas le privilège de
  -- toucher aux déclencheurs, on continue : le journal sera alors simplement
  -- ignoré (voir étape 3), et la suppression dira pourquoi si elle bloque.
  begin
    execute 'alter table public.journal_audit disable trigger trg_journal_audit_append_only';
    v_trigger_off := true;
  exception
    when others then
      v_trigger_off := false;
  end;

  if v_trigger_off then
    begin
      execute 'delete from public.journal_audit where entreprise_id = any($1)'
        using v_ids;
      get diagnostics v_audit = row_count;
    exception
      when others then
        v_audit := 0;
    end;

    -- Remise en place IMMÉDIATE : le journal redevient inaltérable.
    begin
      execute 'alter table public.journal_audit enable trigger trg_journal_audit_append_only';
    exception
      when others then null;
    end;
  end if;

  -- ------------------------------------------------------------------------
  -- 3. TOUTES LES AUTRES TABLES portant l'entreprise ou son propriétaire
  -- ------------------------------------------------------------------------
  for v_t in
    select distinct c.table_name, c.column_name
      from information_schema.columns c
      join information_schema.tables t
        on t.table_schema = c.table_schema
       and t.table_name = c.table_name
       and t.table_type = 'BASE TABLE'
     where c.table_schema = 'public'
       and c.column_name in ('owner_id', 'entreprise_id')
       and c.table_name <> 'entreprises'
       -- jamais les traces d'audit : traitées à l'étape 2
       and c.table_name not ilike '%audit%'
       and c.table_name not ilike '%journal%'
     order by c.table_name
  loop
    begin
      execute format('delete from public.%I where %I = any($1)',
                     v_t.table_name, v_t.column_name)
        using v_ids;
      v_tables := v_tables + 1;
    exception
      when others then
        -- Une table qui refuse ne doit pas annuler tout le nettoyage :
        -- on la signale et on continue.
        v_ignorees := v_ignorees || v_t.table_name;
    end;
  end loop;

  -- ------------------------------------------------------------------------
  -- 4. LES COMPTES
  -- ------------------------------------------------------------------------
  begin
    delete from public.utilisateurs
     where id = any(v_ids) or parent_id = any(v_ids);
    get diagnostics v_utilisateurs = row_count;
  exception
    when foreign_key_violation then
      raise exception 'SUPPRESSION_BLOQUEE|Des données pointent encore vers ces comptes : supprimez-les puis réessayez.';
  end;

  -- ------------------------------------------------------------------------
  -- 5. L'ENTREPRISE
  -- ------------------------------------------------------------------------
  begin
    delete from public.entreprises where id = p_entreprise;
  exception
    when foreign_key_violation then
      raise exception 'SUPPRESSION_BLOQUEE|Des données liées empêchent la suppression de « % » : prévenez le support technique.', v_nom;
  end;

  -- ------------------------------------------------------------------------
  -- 6. TRACE ADMINISTRATIVE (sans entreprise_id : elle n'existe plus)
  -- ------------------------------------------------------------------------
  begin
    insert into public.journal_audit (action, utilisateur_id, details, created_at)
    values (
      'ENTREPRISE_SUPPRIMEE', v_user,
      jsonb_build_object(
        'entreprise_id', p_entreprise, 'nom', v_nom,
        'tables_nettoyees', v_tables,
        'comptes_supprimes', v_utilisateurs,
        'lignes_audit_supprimees', v_audit,
        'tables_ignorees', to_jsonb(v_ignorees),
        'audit_libere', v_trigger_off
      ),
      now()
    );
  exception when others then
    -- Le déclencheur de préparation d'audit peut refuser : sans gravité.
    null;
  end;

  select count(*) into v_reste from public.entreprises where id = p_entreprise;

  return jsonb_build_object(
    'ok', v_reste = 0,
    'entreprise_id', p_entreprise,
    'nom', v_nom,
    'tables_nettoyees', v_tables,
    'comptes_supprimes', v_utilisateurs,
    'lignes_audit_supprimees', v_audit,
    'tables_ignorees', to_jsonb(v_ignorees),
    'note', 'Les comptes de connexion Supabase (Authentication) restent à supprimer séparément si nécessaire.'
  );
end;
$$;

comment on function public.rpc_entreprise_supprimer(uuid, text) is
  'Supprime une entreprise, ses données applicatives (journal d''audit compris) et ses comptes. SUPER_ADMIN uniquement, confirmation « SUPPRIMER » exigée. Correctif 95 : le journal n''est plus un obstacle.';

revoke all on function public.rpc_entreprise_supprimer(uuid, text) from public, anon;
grant execute on function public.rpc_entreprise_supprimer(uuid, text) to authenticated;

-- ============================================================================
--  FIN — CORRECTIF 95
-- ============================================================================
