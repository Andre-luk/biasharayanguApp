-- ============================================================================
--  biashara_yangu — CORRECTIF 98 : LA LISTE DES ACTIVITÉS NE DÉPEND PLUS
--                                D'UNE COLONNE FACULTATIVE
--  ---------------------------------------------------------------------------
--  PROBLÈME SIGNALÉ (01/11/2026)
--    « Dans la création de l'entreprise et de son propriétaire, dans
--      l'activité je ne trouve pas la sélection de l'entreprise de
--      distribution. »
--
--  CAUSE
--    L'écran de création lit `rpc_types_espaces_publics()` (migration 0038),
--    qui filtre sur `types_espaces_modules.actif`. Si cette colonne n'existe
--    pas dans la base, la fonction ÉCHOUE — et l'application retombe
--    silencieusement sur une liste figée dans le code, où « Distribution »
--    n'existait pas.
--
--  CORRECTION
--    La fonction s'adapte au schéma réel (avec ou sans `actif`), et la ligne
--    « distribution » est créée si elle manque.
--
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
declare
  v_actif boolean;
begin
  if to_regclass('public.types_espaces_modules') is null then
    raise warning 'types_espaces_modules absente : exécutez la migration 0089.';
    return;
  end if;

  select exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'types_espaces_modules'
       and column_name = 'actif'
  ) into v_actif;

  -- 1) La ligne « distribution » doit exister.
  if not exists (select 1 from public.types_espaces_modules where type = 'distribution') then
    if v_actif then
      execute $q$
        insert into public.types_espaces_modules (type, libelle, modules)
        values ('distribution', 'Distribution (production & tournées)',
                '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","distribution","production"]'::jsonb)
        on conflict (type) do nothing
      $q$;
    else
      execute $q$
        insert into public.types_espaces_modules (type, libelle, modules)
        values ('distribution', 'Distribution (production & tournées)',
                '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","distribution","production"]'::jsonb)
        on conflict (type) do nothing
      $q$;
    end if;
  end if;

  -- 2) Elle doit être active si la colonne existe.
  if v_actif then
    execute 'update public.types_espaces_modules set actif = true where type = ''distribution''';
  end if;

  raise notice 'Correctif 98 — profil « distribution » présent (colonne actif : %).', v_actif;
end $$;


-- ============================================================================
--  LA FONCTION DEVIENT TOLÉRANTE (avec ou sans colonne `actif`)
-- ============================================================================
create or replace function public.rpc_types_espaces_publics()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_res   jsonb;
  v_actif boolean;
begin
  if to_regclass('public.types_espaces_modules') is null then
    return '[]'::jsonb;
  end if;

  select exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'types_espaces_modules'
       and column_name = 'actif'
  ) into v_actif;

  if v_actif then
    execute $q$
      select coalesce(
        (select jsonb_agg(
                  jsonb_build_object('type', t.type, 'libelle', t.libelle)
                  order by (t.type = 'boutique') desc, t.libelle)
           from public.types_espaces_modules t
          where coalesce(t.actif, true)),
        '[]'::jsonb)
    $q$ into v_res;
  else
    execute $q$
      select coalesce(
        (select jsonb_agg(
                  jsonb_build_object('type', t.type, 'libelle', t.libelle)
                  order by (t.type = 'boutique') desc, t.libelle)
           from public.types_espaces_modules t),
        '[]'::jsonb)
    $q$ into v_res;
  end if;

  return coalesce(v_res, '[]'::jsonb);
exception
  when others then
    raise warning 'rpc_types_espaces_publics : %', sqlerrm;
    return '[]'::jsonb;
end;
$$;

comment on function public.rpc_types_espaces_publics() is
  'Correctif 98 — catégories d''activité (code + libellé), y compris « distribution » ; tolère l''absence de la colonne actif.';

revoke all on function public.rpc_types_espaces_publics() from public;
grant execute on function public.rpc_types_espaces_publics() to anon;
grant execute on function public.rpc_types_espaces_publics() to authenticated;


-- ============================================================================
--  CONTRÔLE
-- ============================================================================
select jsonb_pretty(public.rpc_types_espaces_publics()) as activites_proposees;

-- ============================================================================
--  FIN — CORRECTIF 98
-- ============================================================================
