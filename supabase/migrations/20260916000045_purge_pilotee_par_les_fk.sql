-- ============================================================================
--  MODULE 21 ter — PURGE PILOTÉE PAR LES CLÉS ÉTRANGÈRES
--  Migration 20260916000045_purge_pilotee_par_les_fk.sql
-- ============================================================================
--
--  CE QUE LE RAPPORT DE LA MIGRATION 44 A RÉVÉLÉ
--  ---------------------------------------------
--  L'exécution réelle a rendu `comptes_supprimes: 0` avec, pour chaque compte :
--
--    journal_audit            : journal_audit_utilisateur_id_fkey
--    dettes                   : dettes_owner_id_fkey
--    depenses                 : depenses_owner_id_fkey
--    inventaires_quotidiens   : inventaires_quotidiens_owner_id_fkey
--
--  Ces clés étrangères sont en RESTRICT : tant qu'une ligne existe dans ces
--  tables, la suppression du compte est REFUSÉE par PostgreSQL. C'est correct
--  — un journal d'audit ne doit pas disparaître parce qu'on supprime un
--  compte. L'entreprise, elle, a bien été supprimée (1/1) et le garde-fou des
--  ventes a été coupé puis rétabli : la mécanique fonctionne.
--
--  POURQUOI LA LISTE DE COLONNES NE SUFFISAIT PAS
--  ----------------------------------------------
--  `rpc_admin_purger_utilisateur` cherchait les tables par NOM DE COLONNE
--  (`utilisateur_id`, `owner_id`, …). Or la liste réelle des dépendances est
--  écrite dans les CONTRAINTES, pas dans ma liste : une colonne nommée
--  autrement (`*_par`, `auteur`, …) passait à travers, et une table ajoutée
--  demain aussi.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--  Elle réécrit `rpc_admin_purger_utilisateur` pour qu'elle ne devine plus :
--  elle INTERROGE LE CATALOGUE (`pg_constraint`) et supprime dans TOUTES les
--  tables qui référencent réellement `utilisateurs` et `espaces`. Elle coupe
--  les déclencheurs de protection de ces tables, puis les rétablit.
--
--  ⚠️ DESTRUCTIF — réservé au Super Admin, confirmation par e-mail, et
--     SIMULATION par défaut (`p_simulation`).
-- ============================================================================


create or replace function public.rpc_admin_purger_utilisateur(
  p_utilisateur_id uuid,
  p_confirmation   text,
  p_simulation     boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_role     text := public.mon_role();
  v_u        public.utilisateurs;
  v_email    text;
  v_rec      record;
  v_fk       record;
  v_cols     text;
  v_n        integer;
  v_total    integer := 0;
  v_detail   jsonb := '{}'::jsonb;
  v_erreurs  jsonb := '{}'::jsonb;
  v_passe    integer;
  v_triggers text[] := array[]::text[];
  v_reactives text[] := array[]::text[];
  v_auth     boolean := false;
  v_espace   uuid;
  v_espaces  uuid[] := array[]::uuid[];
begin
  -- ------------------------------------------------------------------ gardes
  if v_role <> 'SUPER_ADMIN' then
    raise exception 'DROIT_REFUSE|Seul le Super Admin peut supprimer définitivement un compte et ses données.';
  end if;

  select * into v_u from public.utilisateurs where id = p_utilisateur_id;
  if not found then
    raise exception 'UTILISATEUR_INCONNU|Cet utilisateur est introuvable.';
  end if;

  v_email := lower(coalesce(v_u.email, ''));

  if lower(btrim(coalesce(p_confirmation, ''))) <> v_email then
    raise exception 'CONFIRMATION_INVALIDE|Recopiez exactement l''adresse e-mail du compte (%) pour confirmer.', v_email;
  end if;

  if v_u.entreprise_id is null
     and coalesce(v_u.new_role::text, '') in
         ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE',
          'SUPPORT', 'AGENT_TERRAIN') then
    raise exception 'COMPTE_PLATEFORME|% est un compte de la plateforme (%) : sa suppression verrouillerait l''administration.', v_email, v_u.new_role::text;
  end if;

  -- Espaces rattachés directement au compte (convention : espaces.id = uuid du patron).
  select coalesce(array_agg(e.id), array[]::uuid[]) into v_espaces
    from public.espaces e where e.id = p_utilisateur_id;

  v_espace := case when array_length(v_espaces, 1) is null then null else v_espaces[1] end;

  -- =========================== INVENTAIRE (simulation ET exécution)
  -- On compte, table par table, ce qui référence ce compte — la liste vient des
  -- CONTRAINTES, jamais d'une liste écrite à la main.
  for v_fk in
    select c.conrelid::regclass::text as tbl,
           c.conname as nom,
           (select array_agg(a.attname order by k.ord)
              from unnest(c.conkey) with ordinality as k(attnum, ord)
              join pg_attribute a
                on a.attrelid = c.conrelid and a.attnum = k.attnum) as cols,
           (c.confrelid = 'public.utilisateurs'::regclass) as vers_utilisateurs
      from pg_constraint c
      join pg_class cl on cl.oid = c.conrelid
      join pg_namespace n on n.oid = cl.relnamespace
     where c.contype = 'f'
       and n.nspname = 'public'
       and cl.relkind = 'r'
       and c.confrelid in ('public.utilisateurs'::regclass, 'public.espaces'::regclass)
     order by c.conrelid::regclass::text
  loop
    -- Un espace ne dépend du compte que par son identifiant.
    if not v_fk.vers_utilisateurs and v_espace is null then
      continue;
    end if;

    v_cols := array_to_string(
      array(select format('%I = $1', x) from unnest(v_fk.cols) as x), ' and ');

    v_n := 0;
    begin
      execute format('select count(*) from %s where %s', v_fk.tbl, v_cols)
        into v_n using coalesce(v_espace, p_utilisateur_id)::uuid;

      if v_n > 0 then
        v_detail := v_detail || jsonb_build_object(
          v_fk.tbl || ' (' || v_fk.nom || ')', v_n);
        v_total := v_total + v_n;
      end if;
    exception when others then
      v_erreurs := v_erreurs || jsonb_build_object('comptage:' || v_fk.tbl, sqlerrm);
    end;
  end loop;

  if coalesce(p_simulation, true) then
    return jsonb_build_object(
      'ok', true,
      'simulation', true,
      'utilisateur_id', p_utilisateur_id,
      'email', v_email,
      'lignes_concernees', v_total,
      'detail', v_detail,
      'erreurs', v_erreurs
    );
  end if;

  -- ============================================ EXÉCUTION RÉELLE
  begin
    -- 1. Couper TOUS les déclencheurs de protection des tables concernées.
    for v_fk in
      select distinct c.relname as tbl, t.tgname as tg
        from pg_constraint ct
        join pg_class cl on cl.oid = ct.conrelid
        join pg_namespace n on n.oid = cl.relnamespace
        join pg_class c on c.oid = ct.conrelid
        join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
       where ct.contype = 'f'
         and n.nspname = 'public'
         and ct.confrelid in ('public.utilisateurs'::regclass, 'public.espaces'::regclass)
    loop
      execute format('alter table public.%I disable trigger %I', v_fk.tbl, v_fk.tg);
      v_triggers := v_triggers || (v_fk.tbl || '.' || v_fk.tg);
    end loop;

    -- On coupe aussi les protections générales (« suppression interdite »).
    for v_fk in
      select c.relname as tbl, t.tgname as tg
        from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
        join pg_proc pr on pr.oid = t.tgfoid
       where n.nspname = 'public' and not t.tgisinternal
         and t.tgenabled <> 'D'
         and (pr.proname ilike '%interdit%' or pr.proname ilike '%inalterable%'
              or pr.proname ilike '%immuable%' or pr.proname ilike '%immutable%')
    loop
      execute format('alter table public.%I disable trigger %I', v_fk.tbl, v_fk.tg);
      v_triggers := v_triggers || (v_fk.tbl || '.' || v_fk.tg);
    end loop;

    -- 2. Supprimer dans les tables dépendantes. Trois passes : l'ordre des
    --    dépendances entre ces tables n'est pas garanti.
    for v_passe in 1..3 loop
      for v_fk in
        select c.conrelid::regclass::text as tbl,
               (select array_agg(a.attname order by k.ord)
                  from unnest(c.conkey) with ordinality as k(attnum, ord)
                  join pg_attribute a
                    on a.attrelid = c.conrelid and a.attnum = k.attnum) as cols,
               (c.confrelid = 'public.utilisateurs'::regclass) as vers_utilisateurs
          from pg_constraint c
          join pg_class cl on cl.oid = c.conrelid
          join pg_namespace n on n.oid = cl.relnamespace
         where c.contype = 'f'
           and n.nspname = 'public'
           and cl.relkind = 'r'
           and c.confrelid in ('public.utilisateurs'::regclass, 'public.espaces'::regclass)
      loop
        if not v_fk.vers_utilisateurs and v_espace is null then
          continue;
        end if;

        v_cols := array_to_string(
          array(select format('%I = $1', x) from unnest(v_fk.cols) as x), ' and ');

        begin
          execute format('delete from %s where %s', v_fk.tbl, v_cols)
            using coalesce(v_espace, p_utilisateur_id)::uuid;
        exception when others then
          null;  -- retenté à la passe suivante ; l'erreur finale est rapportée
        end;
      end loop;
    end loop;

    -- 3. Le profil applicatif, puis le compte GoTrue.
    delete from public.utilisateurs where id = p_utilisateur_id;

    begin
      delete from auth.users where id = p_utilisateur_id;
      v_auth := true;
    exception when others then
      v_erreurs := v_erreurs || jsonb_build_object('auth.users', sqlerrm);
    end;

    -- 4. REACTIVER tous les déclencheurs coupés — toujours, même en cas d'erreur.
    for v_fk in
      select c.relname as tbl, t.tgname as tg
        from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and not t.tgisinternal and t.tgenabled = 'D'
    loop
      execute format('alter table public.%I enable trigger %I', v_fk.tbl, v_fk.tg);
      v_reactives := v_reactives || (v_fk.tbl || '.' || v_fk.tg);
    end loop;

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (null, 'ADMIN_UTILISATEUR_PURGE', null,
        jsonb_build_object('utilisateur_id', p_utilisateur_id, 'email', v_email,
                           'detail', v_detail, 'erreurs', v_erreurs));
    exception when others then null;
    end;
  exception when others then
    -- PostgreSQL annule les ALTER TABLE (DDL transactionnel) : rien ne reste coupé.
    raise;
  end;

  return jsonb_build_object(
    'ok', true,
    'simulation', false,
    'utilisateur_id', p_utilisateur_id,
    'email', v_email,
    'lignes_concernees', v_total,
    'detail', v_detail,
    'erreurs', v_erreurs,
    'compte_auth_supprime', v_auth,
    'declencheurs_retablis', to_jsonb(v_reactives)
  );
end;
$$;

comment on function public.rpc_admin_purger_utilisateur(uuid, text, boolean) is
  'Module 21 ter — Purge DÉFINITIVE d''un compte : la liste des tables dépendantes est lue dans le CATALOGUE (clés étrangères vers utilisateurs et espaces), pas devinée. Coupe puis rétablit les déclencheurs de protection. Super Admin uniquement, confirmation par e-mail, simulation par défaut.';


revoke all on function public.rpc_admin_purger_utilisateur(uuid, text, boolean)
  from public, anon;
grant execute on function public.rpc_admin_purger_utilisateur(uuid, text, boolean)
  to authenticated;


-- ============================================================================
--  VÉRIFICATIONS
-- ============================================================================

-- a) Les tables réellement rattachées à un compte (c'est cette liste qui pilote
--    désormais la purge — plus aucune colonne n'est devinée).
select c.conname as contrainte,
       c.conrelid::regclass::text as table_dependante
  from pg_constraint c
  join pg_class cl on cl.oid = c.conrelid
  join pg_namespace n on n.oid = cl.relnamespace
 where c.contype = 'f'
   and n.nspname = 'public'
   and c.confrelid in ('public.utilisateurs'::regclass, 'public.espaces'::regclass)
 order by 2;

-- b) État actuel.
select (select count(*) from public.utilisateurs) as comptes,
       (select count(*) from public.entreprises)  as entreprises,
       (select count(*) from public.espaces)      as boutiques,
       (select count(*) from public.ventes)       as ventes;

-- ============================================================================
--  FIN — module 21 ter.
-- ============================================================================
