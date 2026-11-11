-- ============================================================================
--  biashara_yangu — MIGRATION 0138 : « DATABASE ERROR SAVING NEW USER »
--
--  SYMPTÔME (signalé par le propriétaire)
--    Créer un utilisateur « vendeur de la boutique » depuis l'application
--    renvoie :
--        exception: code « unexpected_failure »,
--        message « Database error saving new user »
--
--  D'OÙ VIENT CE MESSAGE
--    Il n'est pas produit par l'application : c'est GoTrue (le service
--    d'authentification de Supabase) qui l'émet quand l'INSERT dans
--    `auth.users` échoue — le plus souvent parce qu'un TRIGGER
--    `AFTER INSERT ON auth.users` (celui qui crée la fiche dans
--    `public.utilisateurs`) lève une exception.
--    Une seule ligne en erreur annule TOUTE la création du compte : le client
--    voit « Database error saving new user » et n'a aucun compte.
--
--  CE QUE FAIT CETTE MIGRATION (uniquement côté base, rien à réinstaller)
--    1. DIAGNOSTIC : liste les colonnes NOT NULL sans valeur par défaut de
--       `public.utilisateurs` (la cause la plus fréquente), les triggers
--       présents sur `auth.users` et sur `public.utilisateurs`, et les comptes
--       Auth SANS fiche (comptes créés pendant la panne).
--    2. RÉPARATION DE FOND : le trigger de création de fiche est remplacé par
--       une version TOLÉRANTE qui ne peut PLUS faire échouer une inscription :
--         • lit les métadonnées sans jamais supposer leur forme ;
--         • convertit l'ancien rôle (vendor/collaborator/…) via `role_herite`
--           au lieu de caster un texte brut dans l'énumération ;
--         • ne duplique pas une fiche existante (`on conflict do nothing`) ;
--         • enveloppe tout dans `exception when others` : au pire la fiche est
--           incomplète (et réparable), mais le compte existe et la connexion
--           fonctionne.
--    3. RATTRAPAGE : `reparer_profils_auth()` recrée les fiches manquantes des
--       comptes Auth déjà créés (ceux qui ont échoué avant cette migration),
--       puis la fonction est exécutée.
--
--  ⚠️ IDEMPOTENT : relançable sans dupliquer une fiche ni casser un compte.
--  OÙ L'EXÉCUTER : Supabase Dashboard → SQL Editor → coller → Run.
--  (Le tableau de contrôle est la DERNIÈRE instruction : c'est le seul
--   résultat que l'éditeur affiche.)
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. DIAGNOSTIC AVANT (lecture seule)
-- ============================================================================

-- 1.a Colonnes NOT NULL SANS valeur par défaut : ce sont elles qui font
--     échouer un INSERT qui ne les renseigne pas.
select 'COLONNES NOT NULL SANS DÉFAUT (public.utilisateurs)' as controle,
       column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'utilisateurs'
   and is_nullable  = 'NO'
   and column_default is null
 order by ordinal_position;

-- 1.b Triggers présents sur auth.users (ceux qui peuvent bloquer GoTrue).
select 'TRIGGERS SUR auth.users (avant)' as controle,
       t.tgname,
       p.proname as fonction,
       pg_get_triggerdef(t.oid) as definition
  from pg_trigger t
  join pg_class c       on c.oid = t.tgrelid
  join pg_namespace n   on n.oid = c.relnamespace
  join pg_proc p        on p.oid = t.tgfoid
 where n.nspname = 'auth' and c.relname = 'users' and not t.tgisinternal;

-- 1.c Comptes Auth SANS fiche applicative (créés pendant la panne).
select 'COMPTES AUTH SANS FICHE' as controle,
       count(*) as nb
  from auth.users u
  left join public.utilisateurs x on x.id = u.id
 where x.id is null;


-- ============================================================================
--  2. LE TRIGGER DE CRÉATION DE FICHE — VERSION QUI NE BLOQUE JAMAIS
-- ============================================================================

-- 2.0 Filet de sécurité : une colonne NOT NULL SANS défaut est la cause n°1
--     d'un « Database error saving new user » (l'INSERT de la fiche ne la
--     renseigne pas). On pose un défaut RAISONNABLE sur les colonnes
--     facultatives connues — jamais sur une colonne métier obligatoire.
do $$
declare
  v_col   text;
  v_type  text;
  v_notnull boolean;
  v_defaut  text;
begin
  for v_col, v_notnull, v_type in
    select column_name, (is_nullable = 'NO'), data_type
      from information_schema.columns
     where table_schema = 'public' and table_name = 'utilisateurs'
  loop
    continue when not v_notnull;
    continue when exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'utilisateurs'
         and column_name = v_col and column_default is not null
    );

    v_defaut := case
      when v_col in ('press_actif', 'dist_actif') then 'true'
      when v_col in ('valide', 'actif')            then '1'
      when v_type = 'boolean'                      then 'false'
      when v_type in ('integer', 'bigint', 'smallint', 'numeric', 'real',
                      'double precision')          then '0'
      when v_type = 'jsonb'                        then '''{}''::jsonb'
      when v_type = 'text' or v_type like 'character%' then ''''''
      else null
    end;

    if v_defaut is not null then
      execute format('alter table public.utilisateurs alter column %I set default %s',
                     v_col, v_defaut);
      raise notice 'Défaut posé sur public.utilisateurs.% = %', v_col, v_defaut;
    end if;
  end loop;
end $$;

create or replace function public.auth_creer_fiche_utilisateur()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meta    jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_email   text  := lower(btrim(coalesce(new.email, '')));
  v_nom     text;
  v_prenom  text;
  v_role    text;
  v_parent  uuid;
  v_avatar  text;
begin
  -- 2.1 Métadonnées lues SANS rien supposer -------------------------------
  v_nom    := nullif(btrim(coalesce(v_meta->>'nom', '')), '');
  v_prenom := nullif(btrim(coalesce(v_meta->>'prenom', '')), '');
  v_role   := nullif(btrim(coalesce(v_meta->>'role', '')), '');
  v_avatar := nullif(btrim(coalesce(v_meta->>'avatar', '')), '');

  if v_nom is null then
    v_nom := coalesce(nullif(split_part(v_email, '@', 1), ''), 'Utilisateur');
  end if;

  -- 2.2 `parent_id` : un texte invalide ne doit PAS faire échouer le compte.
  begin
    v_parent := nullif(btrim(coalesce(v_meta->>'parent_id', '')), '')::uuid;
  exception
    when others then v_parent := null;
  end;

  -- 2.3 La fiche applicative ----------------------------------------------
  --  ⚠️ `new_role` passe par `role_herite` : 'vendor', 'collaborator',
  --     'caissier'… sont convertis au lieu d'être castés à l'aveugle dans
  --     l'énumération (c'était la cause du rejet de l'inscription).
  insert into public.utilisateurs (
    id, nom, prenom, email, role, new_role, valide,
    parent_id, espace_actif_id, avatar, created_at
  ) values (
    new.id,
    v_nom,
    v_prenom,
    v_email,
    coalesce(v_role, 'vendor'),
    coalesce(
      public.role_enum(public.role_herite(coalesce(v_role, 'vendor'))),
      public.role_enum('PROPRIETAIRE')
    ),
    1,
    v_parent,
    v_parent,
    v_avatar,
    now()
  )
  on conflict (id) do nothing;

  return new;

exception
  when others then
    -- 2.4 LE COMPTE NE DOIT JAMAIS ÊTRE PERDU À CAUSE D'UNE FICHE.
    --     On signale le problème (visible dans les logs) et on laisse
    --     l'inscription aboutir : la fiche sera recréée par
    --     `reparer_profils_auth()`.
    raise warning
      'Fiche utilisateur non créée pour % (le compte Auth existe) : % (%)',
      v_email, sqlerrm, sqlstate;
    return new;
end;
$$;

comment on function public.auth_creer_fiche_utilisateur() is
  'Crée la fiche public.utilisateurs d''un compte Auth. Ne fait JAMAIS échouer l''inscription : toute erreur est journalisée et la fiche pourra être recréée.';

-- 2.5 Un SEUL trigger sur auth.users : on remplace celui qui bloquait ------
do $$
declare
  v_nom text;
begin
  for v_nom in
    select t.tgname
      from pg_trigger t
      join pg_class c     on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'auth' and c.relname = 'users' and not t.tgisinternal
  loop
    execute format('drop trigger if exists %I on auth.users', v_nom);
    raise notice 'Ancien trigger supprimé sur auth.users : %', v_nom;
  end loop;

  create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.auth_creer_fiche_utilisateur();
end $$;


-- ============================================================================
--  3. RATTRAPAGE DES COMPTES DÉJÀ CRÉÉS SANS FICHE
-- ============================================================================

create or replace function public.reparer_profils_auth(p_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email   text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_creees  integer := 0;
  v_restant integer := 0;
  u         record;
  v_nom     text;
begin
  for u in
    select a.id, a.email, coalesce(a.raw_user_meta_data, '{}'::jsonb) as meta
      from auth.users a
      left join public.utilisateurs x on x.id = a.id
     where x.id is null
       and (v_email is null or lower(a.email) = v_email)
  loop
    v_nom := nullif(btrim(coalesce(u.meta->>'nom', '')), '');
    if v_nom is null then
      v_nom := coalesce(nullif(split_part(lower(coalesce(u.email, '')), '@', 1), ''),
                        'Utilisateur');
    end if;

    begin
      insert into public.utilisateurs (
        id, nom, prenom, email, role, new_role, valide, avatar, created_at
      ) values (
        u.id,
        v_nom,
        nullif(btrim(coalesce(u.meta->>'prenom', '')), ''),
        lower(coalesce(u.email, '')),
        coalesce(nullif(btrim(coalesce(u.meta->>'role', '')), ''), 'vendor'),
        coalesce(
          public.role_enum(public.role_herite(u.meta->>'role')),
          public.role_enum('PROPRIETAIRE')
        ),
        1,
        nullif(btrim(coalesce(u.meta->>'avatar', '')), ''),
        now()
      )
      on conflict (id) do nothing;

      v_creees := v_creees + 1;
    exception
      when unique_violation then
        -- Même adresse e-mail déjà présente sur une AUTRE fiche : on ne
        -- fusionne pas d'office (cela toucherait des droits). On le signale.
        raise warning
          'Compte % : une fiche avec cet e-mail existe déjà (autre identifiant) — à traiter à la main.',
          u.email;
      when others then
        raise warning 'Compte % : fiche non recréée (%)', u.email, sqlerrm;
    end;
  end loop;

  select count(*) into v_restant
    from auth.users a
    left join public.utilisateurs x on x.id = a.id
   where x.id is null;

  return jsonb_build_object(
    'fiches_creees',  v_creees,
    'comptes_sans_fiche_restants', v_restant
  );
end;
$$;

comment on function public.reparer_profils_auth(text) is
  'Recrée les fiches public.utilisateurs manquantes des comptes Auth (sans supprimer ni fusionner aucun compte).';

revoke all on function public.reparer_profils_auth(text) from public, anon;
grant execute on function public.reparer_profils_auth(text) to authenticated, service_role;

-- Exécution immédiate du rattrapage (aucun argument = tous les comptes).
do $$
declare
  v_res jsonb;
begin
  v_res := public.reparer_profils_auth();
  raise notice 'Rattrapage : % fiche(s) recréée(s), % compte(s) sans fiche restant(s).',
    v_res->>'fiches_creees', v_res->>'comptes_sans_fiche_restants';
end $$;


-- ============================================================================
--  4. CONTRÔLE APRÈS
-- ============================================================================

select 'TRIGGER DE CRÉATION DE FICHE' as controle,
       (select count(*)
          from pg_trigger t
          join pg_class c     on c.oid = t.tgrelid
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'auth' and c.relname = 'users' and not t.tgisinternal)
         as nb_triggers_sur_auth_users,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where p.proname = 'auth_creer_fiche_utilisateur'
                  and n.nspname = 'public') as fonction_ok;

select 'COMPTES AUTH SANS FICHE (après)' as controle,
       count(*) as nb
  from auth.users u
  left join public.utilisateurs x on x.id = u.id
 where x.id is null;
