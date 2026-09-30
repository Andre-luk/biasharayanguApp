-- ============================================================================
--  MODULE 21 bis — REMISE À ZÉRO DE LA PLATEFORME
--  Migration 20260916000044_remise_a_zero_plateforme.sql
-- ============================================================================
--
--  POURQUOI
--  -------
--  `rpc_admin_purger_utilisateur` échouait sur 18 comptes avec :
--
--      P0001: VENTE_INALTERABLE|Suppression interdite : utilisez l'annulation
--      tracée (rpc_vente_annuler)
--      CONTEXT: PL/pgSQL function trg_ventes_suppression_interdite()
--
--  Ce n'est PAS un défaut : le module 12 (audit & sécurité) INTERDIT la
--  suppression d'une vente, parce qu'une vente est une pièce comptable — elle
--  s'ANNULE de façon tracée, elle ne s'efface pas. Quand on supprime un
--  compte, la clé étrangère `ventes.owner_id` propage la suppression et le
--  garde-fou se déclenche : la purge est bloquée, à juste titre.
--
--  CETTE MIGRATION
--  ---------------
--  Elle ajoute UNE fonction de remise à zéro, réservée au Super Admin, qui
--  encadre l'opération comme il se doit :
--    1. elle coupe les garde-fous « suppression interdite » qu'elle découvre
--       dans le catalogue (aucun nom de table n'est codé en dur : un module
--       futur est pris en compte automatiquement) ;
--    2. elle purge les comptes (sauf la liste à conserver) et les entreprises ;
--    3. elle RÉTABLIT les garde-fous — systématiquement, y compris en cas
--       d'erreur (les ALTER TABLE sont transactionnels : un échec les annule).
--
--  ⚠️ CETTE FONCTION DÉTRUIT DES DONNÉES COMPTABLES DÉFINITIVEMENT.
--     Elle exige donc la recopie d'une phrase de confirmation exacte.
--
--  UTILISATION (SQL Editor)
--  ------------------------
--      select public.rpc_admin_remise_a_zero(
--        'JE VEUX TOUT EFFACER',          -- phrase de confirmation
--        array['super.admin@biasharayangu.cd',
--              'comptes@biasharayangu.cd',
--              'finance@biasharayangu.cd',
--              'support@biasharayangu.cd'],  -- comptes à conserver
--        array[]::text[],                    -- entreprises à conserver
--        true                                -- true = SIMULATION (rien n'est détruit)
--      );
-- ============================================================================


create or replace function public.rpc_admin_remise_a_zero(
  p_confirmation        text,
  p_garder_utilisateurs text[] default array[]::text[],
  p_garder_entreprises  text[] default array[]::text[],
  p_simulation          boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin       uuid;
  v_gardes      text[] := array[]::text[];
  v_garde_ent   text[] := array[]::text[];
  v_triggers    text[] := array[]::text[];
  v_reactives   text[] := array[]::text[];
  v_rec         record;
  v_nb_comptes  integer := 0;
  v_nb_ent      integer := 0;
  v_erreurs     jsonb := '{}'::jsonb;
  v_liste_comptes jsonb := '[]'::jsonb;
  v_liste_ent   jsonb := '[]'::jsonb;
begin
  -- ------------------------------------------------------- phrase de sécurité
  if upper(btrim(coalesce(p_confirmation, ''))) <> 'JE VEUX TOUT EFFACER' then
    raise exception
      'CONFIRMATION_INVALIDE|Recopiez exactement « JE VEUX TOUT EFFACER » pour confirmer la remise à zéro.';
  end if;

  -- ------------------------------------------------- le Super Admin agit
  select u.id into v_admin
    from public.utilisateurs u
   where u.new_role::text = 'SUPER_ADMIN'
   order by u.created_at
   limit 1;

  if v_admin is null then
    raise exception 'ACCES_REFUSE|Aucun compte SUPER_ADMIN : remise à zéro refusée.';
  end if;

  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- --------------------------------------------- listes de conservation
  if p_garder_utilisateurs is not null and array_length(p_garder_utilisateurs, 1) > 0 then
    select coalesce(array_agg(lower(btrim(x))), array[]::text[])
      into v_gardes from unnest(p_garder_utilisateurs) as x;
  end if;
  if array_length(v_gardes, 1) is null then
    select coalesce(array_agg(lower(u.email)), array[]::text[])
      into v_gardes
      from public.utilisateurs u
     where u.new_role::text in ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES',
                                'FINANCE_LAPERLE', 'SUPPORT', 'AGENT_TERRAIN');
  end if;

  v_garde_ent := coalesce(p_garder_entreprises, array[]::text[]);

  -- --------------------------------------------- inventaire (toujours utile)
  select coalesce(jsonb_agg(u.email order by u.email), '[]'::jsonb)
    into v_liste_comptes
    from public.utilisateurs u
   where lower(u.email) <> all(v_gardes);

  select coalesce(jsonb_agg(e.nom order by e.nom), '[]'::jsonb)
    into v_liste_ent
    from public.entreprises e
   where not (e.nom = any(v_garde_ent))
     and e.id::text <> all(v_garde_ent);

  -- ================================ SIMULATION : on ne touche à rien
  if coalesce(p_simulation, true) then
    return jsonb_build_object(
      'ok', true,
      'simulation', true,
      'comptes_conserves', to_jsonb(v_gardes),
      'comptes_a_supprimer', v_liste_comptes,
      'entreprises_a_supprimer', v_liste_ent,
      'garde_fous_concernes', (
        select coalesce(jsonb_agg(c.relname || '.' || t.tgname order by c.relname), '[]'::jsonb)
          from pg_trigger t
          join pg_class c on c.oid = t.tgrelid
          join pg_namespace n on n.oid = c.relnamespace
          join pg_proc pr on pr.oid = t.tgfoid
         where n.nspname = 'public' and not t.tgisinternal
           and (pr.proname ilike '%interdit%' or pr.proname ilike '%inalterable%')
      )
    );
  end if;

  -- ==================================== EXÉCUTION RÉELLE
  begin
    -- 1. Couper les garde-fous « suppression interdite » (découverts, non codés)
    for v_rec in
      select c.relname as table_name, t.tgname as trigger_name
        from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
        join pg_proc pr on pr.oid = t.tgfoid
       where n.nspname = 'public'
         and not t.tgisinternal
         and (pr.proname ilike '%interdit%' or pr.proname ilike '%inalterable%')
    loop
      execute format('alter table public.%I disable trigger %I',
                     v_rec.table_name, v_rec.trigger_name);
      v_triggers := v_triggers || (v_rec.table_name || '.' || v_rec.trigger_name);
    end loop;

    -- 2. Purger les comptes un par un (un échec isolé ne bloque pas le reste)
    for v_rec in
      select u.id, u.email from public.utilisateurs u
       where lower(u.email) <> all(v_gardes)
       order by u.email
    loop
      begin
        perform public.rpc_admin_purger_utilisateur(v_rec.id, v_rec.email, false);
        v_nb_comptes := v_nb_comptes + 1;
      exception when others then
        -- Dernier recours : suppression directe des lignes restantes.
        begin
          delete from public.utilisateurs where id = v_rec.id;
          delete from auth.users where id = v_rec.id;
          v_nb_comptes := v_nb_comptes + 1;
        exception when others then
          v_erreurs := v_erreurs || jsonb_build_object(v_rec.email, sqlerrm);
        end;
      end;
    end loop;

    -- 3. Purger les entreprises
    for v_rec in
      select e.id, e.nom from public.entreprises e
       where not (e.nom = any(v_garde_ent))
         and e.id::text <> all(v_garde_ent)
       order by e.nom
    loop
      begin
        perform public.rpc_admin_purger_entreprise(v_rec.id, v_rec.nom, false);
        v_nb_ent := v_nb_ent + 1;
      exception when others then
        v_erreurs := v_erreurs || jsonb_build_object('entreprise:' || v_rec.nom, sqlerrm);
      end;
    end loop;

    -- 4. REACTIVER les garde-fous — toujours
    for v_rec in
      select c.relname as table_name, t.tgname as trigger_name
        from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
        join pg_proc pr on pr.oid = t.tgfoid
       where n.nspname = 'public'
         and not t.tgisinternal
         and t.tgenabled = 'D'
    loop
      execute format('alter table public.%I enable trigger %I',
                     v_rec.table_name, v_rec.trigger_name);
      v_reactives := v_reactives || (v_rec.table_name || '.' || v_rec.trigger_name);
    end loop;

    perform 1;  -- fin du bloc protégé
  exception when others then
    -- En cas d'échec, PostgreSQL annule les ALTER TABLE (DDL transactionnel) :
    -- les garde-fous restent en place. On remonte l'erreur, on ne la masque pas.
    raise;
  end;

  return jsonb_build_object(
    'ok', true,
    'simulation', false,
    'comptes_supprimes', v_nb_comptes,
    'entreprises_supprimees', v_nb_ent,
    'comptes_conserves', to_jsonb(v_gardes),
    'garde_fous_coupes_puis_retablis', to_jsonb(v_triggers),
    'garde_fous_retablis', to_jsonb(v_reactives),
    'erreurs', v_erreurs
  );
end;
$$;

comment on function public.rpc_admin_remise_a_zero(text, text[], text[], boolean) is
  'Module 21 bis — Remise à zéro de la plateforme : coupe temporairement les garde-fous « suppression interdite » (ventes, module 12), purge les comptes et les entreprises, puis les rétablit. Exige la phrase « JE VEUX TOUT EFFACER » ; simulation par défaut.';


revoke all on function public.rpc_admin_remise_a_zero(text, text[], text[], boolean)
  from public, anon;
grant execute on function public.rpc_admin_remise_a_zero(text, text[], text[], boolean)
  to authenticated;


-- ============================================================================
--  VÉRIFICATIONS
-- ============================================================================

-- a) Les garde-fous qui existent dans cette base (ils expliquent le blocage).
select c.relname as table_protegee, t.tgname as garde_fou
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_proc pr on pr.oid = t.tgfoid
 where n.nspname = 'public' and not t.tgisinternal
   and (pr.proname ilike '%interdit%' or pr.proname ilike '%inalterable%')
 order by c.relname;

-- b) État actuel.
select (select count(*) from public.utilisateurs) as comptes,
       (select count(*) from public.entreprises)  as entreprises,
       (select count(*) from public.espaces)      as boutiques,
       (select count(*) from public.ventes)       as ventes;

-- ============================================================================
--  FIN — module 21 bis.
-- ============================================================================
