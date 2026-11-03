-- ============================================================================
--  biashara_yangu — CORRECTIF 99 : « DISTRIBUTION » DEVIENT UNE ACTIVITÉ
--  ---------------------------------------------------------------------------
--  PROBLÈME SIGNALÉ (01/11/2026)
--    « Dans la création de l'entreprise et de son propriétaire, dans
--      l'activité il y a encore 5 activités : boutique général, boulangerie,
--      hôtel, restaurant… pas de distribution. »
--
--  CAUSE — deux référentiels différents, confondus à l'écran
--    • `public.activites`          → le MÉTIER (boulangerie, hôtel…). C'est la
--      liste que le patron voit dans « Activité ». « Distribution » n'y était
--      pas : elle n'existait que comme TYPE d'espace.
--    • `public.types_espaces_modules` → le PROFIL DE MODULES (boutique,
--      distribution…), qui décide des écrans.
--
--  CE QUE FAIT CETTE MIGRATION
--    1. Ajoute « Distribution (eau, boissons, tournées) » dans `activites`.
--    2. Garantit la ligne `distribution` dans `types_espaces_modules`.
--    3. Quand une entreprise est créée avec l'activité « Distribution »,
--       son TYPE et son ESPACE deviennent distribution automatiquement
--       (déclencheur) — sans aucune manipulation supplémentaire.
--
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- ============================================================================
--  1. L'ACTIVITÉ « DISTRIBUTION » DANS LE RÉFÉRENTIEL DES MÉTIERS
-- ============================================================================
do $$
declare
  v_cols text[];
begin
  if to_regclass('public.activites') is null then
    raise warning 'public.activites absente : activité non ajoutée.';
    return;
  end if;

  select array_agg(column_name) into v_cols
    from information_schema.columns
   where table_schema = 'public' and table_name = 'activites';

  -- Déjà là ? (comparaison insensible à la casse et aux accents grossiers)
  if exists (
    select 1 from public.activites
     where lower(coalesce(nom, '')) like '%distribution%'
  ) then
    raise notice 'Correctif 99 — l''activité « Distribution » existe déjà.';
    return;
  end if;

  if 'actif' = any(v_cols) then
    execute $q$
      insert into public.activites (nom, actif)
      values ('Distribution (eau, boissons, tournées)', true)
    $q$;
  else
    execute $q$
      insert into public.activites (nom)
      values ('Distribution (eau, boissons, tournées)')
    $q$;
  end if;

  raise notice 'Correctif 99 — activité « Distribution » ajoutée.';
exception
  when others then
    raise warning 'Correctif 99 — activité non ajoutée : %', sqlerrm;
end $$;


-- ============================================================================
--  2. LE PROFIL DE MODULES « DISTRIBUTION » (rappel, tolérant)
-- ============================================================================
do $$
declare
  v_actif boolean;
begin
  if to_regclass('public.types_espaces_modules') is null then
    return;
  end if;

  select exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'types_espaces_modules'
       and column_name = 'actif'
  ) into v_actif;

  if not exists (select 1 from public.types_espaces_modules where type = 'distribution') then
    begin
      execute $q$
        insert into public.types_espaces_modules (type, libelle, modules)
        values ('distribution', 'Distribution (production & tournées)',
                '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia","distribution","production"]'::jsonb)
      $q$;
      raise notice 'Correctif 99 — profil « distribution » créé.';
    exception
      when others then
        raise warning 'Correctif 99 — profil distribution non créé : %', sqlerrm;
    end;
  elsif v_actif then
    execute 'update public.types_espaces_modules set actif = true where type = ''distribution''';
  end if;
end $$;


-- ============================================================================
--  3. ACTIVITÉ « DISTRIBUTION »  ⇒  TYPE ET ESPACE « DISTRIBUTION »
-- ============================================================================
--  Le patron choisit SON MÉTIER à la création ; le type suit. Aucune case
--  technique à cocher, et rien n'est écrasé s'il a déjà choisi un type.

create or replace function public.entreprise_aligne_type_depuis_activite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nom text;
begin
  if new.activite_id is null then
    return new;
  end if;

  select lower(coalesce(a.nom, '')) into v_nom
    from public.activites a
   where a.id = new.activite_id;

  if v_nom is null or v_nom not like '%distribution%' then
    return new;
  end if;

  -- Type d'entreprise (si encore vide).
  if new.type_activite is null or btrim(new.type_activite) = '' then
    new.type_activite := 'distribution';
  end if;

  -- Espaces génériques de cette entreprise → profil de modules distribution.
  update public.espaces
     set type = 'distribution'
   where entreprise_id = new.id
     and lower(coalesce(type, '')) in ('boutique', 'distribution');

  return new;
end;
$$;

comment on function public.entreprise_aligne_type_depuis_activite() is
  'Correctif 99 — une entreprise dont l''activité est « Distribution » devient une distribution (type + profil de modules).';

drop trigger if exists trg_entreprise_aligne_activite on public.entreprises;
create trigger trg_entreprise_aligne_activite
  before insert or update of activite_id on public.entreprises
  for each row
  execute function public.entreprise_aligne_type_depuis_activite();


-- ============================================================================
--  4. RATTRAPAGE : entreprises dont l'activité est déjà « Distribution »
-- ============================================================================
do $$
declare
  v_n integer := 0;
begin
  update public.entreprises e
     set type_activite = 'distribution',
         updated_at    = now()
    from public.activites a
   where a.id = e.activite_id
     and lower(coalesce(a.nom, '')) like '%distribution%'
     and (e.type_activite is null or btrim(e.type_activite) <> 'distribution');
  get diagnostics v_n = row_count;

  if v_n > 0 then
    update public.espaces s
       set type = 'distribution'
      from public.entreprises e
     where e.id = s.entreprise_id
       and e.type_activite = 'distribution'
       and lower(coalesce(s.type, '')) in ('boutique', 'distribution');
    raise notice 'Correctif 99 — % entreprise(s) passée(s) en distribution.', v_n;
  end if;
end $$;

-- ============================================================================
--  5. CONTRÔLE
-- ============================================================================
select (select count(*) from public.activites
         where lower(coalesce(nom, '')) like '%distribution%')       as activite_distribution,
       (select count(*) from public.types_espaces_modules
         where type = 'distribution')                                as profil_distribution,
       (select count(*) from public.entreprises
         where type_activite = 'distribution')                       as entreprises_distribution;

-- ============================================================================
--  FIN — CORRECTIF 99
-- ============================================================================
