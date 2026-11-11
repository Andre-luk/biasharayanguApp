-- ============================================================================
--  biashara_yangu — MIGRATION 0142 : TOUT COLLABORATEUR POINTE VERS
--  L'ENTREPRISE DE SON PATRON
--
--  LE PROBLÈME
--    Plusieurs fonctions de création de comptes écrivaient :
--        entreprise_id = <identifiant du PATRON>
--    au lieu de :
--        entreprise_id = <entreprise DU PATRON>
--
--    Or ces deux identifiants sont différents : l'entreprise porte
--    l'abonnement et cloisonne toutes les données métier (ventes, stock,
--    pressing, distribution, marketplace…). Un collaborateur dont
--    `entreprise_id` vaut l'UUID de son patron :
--      • ne retrouve plus les ESPACES de la boutique (la politique de
--        `public.espaces` compare `entreprise_id` avec celui de sa fiche) ;
--      • sort des jointures « entreprise → collaborateurs » (distribution,
--        abonnement, rapports) ;
--      • peut se voir ouvrir un environnement vide selon l'écran consulté.
--
--    Les écrans qui lisent `parent_id` continuaient de fonctionner (d'où
--    l'impression que « tout allait bien »), mais les fonctions qui filtrent
--    par `entreprise_id` ne voyaient plus ces comptes.
--
--  CE QUE FAIT CE SCRIPT
--    0. Il SÉCURISE d'abord un déclencheur hérité qui plantait sur les fiches
--       sans entreprise (`nullif(new.parent_id, '')::uuid` →
--       « invalid input syntax for type uuid: "" ») — sans lui, la correction
--       ci-dessous ne pouvait pas s'exécuter.
--    1. Il CONTRÔLE l'ampleur (comptes mal rattachés).
--    2. Il CORRIGE l'existant : chaque collaborateur reprend l'entreprise de
--       son patron.
--    3. Il installe une RÈGLE AUTOMATIQUE (trigger) pour l'avenir : dès
--       qu'un compte a un `parent_id`, son `entreprise_id` est celui de son
--       patron — quel que soit le module qui crée le compte (équipe,
--       pressing, distribution, plateforme).
--
--  ⚠️ IDEMPOTENT.
--  ⚠️ La règle ne touche JAMAIS une entreprise différente déjà en place
--     (changement volontaire, pack multi-entreprises) : elle ne réaligne que
--     les valeurs vides ou égales à l'identifiant du patron.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. DÉCLENCHEUR HÉRITÉ À SÉCURISER (obligatoire AVANT la correction)
-- ============================================================================
--  La base contient un ancien déclencheur `trg_utilisateurs_maj_collaborateurs`
--  (créé à la main, hors migrations) dont le corps fait :
--
--      v_entreprise := coalesce(
--        nullif(new.entreprise_id::text, '')::uuid,
--        nullif(new.parent_id, '')::uuid     -- ← FAUTE
--      );
--
--  `parent_id` est de type `uuid` : le comparer à la chaîne '' force
--  PostgreSQL à convertir '' en uuid, ce qui échoue :
--
--      ERROR 22P02: invalid input syntax for type uuid: ""
--
--  Résultat : TOUTE mise à jour d'une fiche dont `entreprise_id` est vide
--  (donc la réparation ci-dessous) avortait.
--
--  On fait donc, dans l'ordre :
--    a) sauvegarde de la définition des déclencheurs qui l'utilisent ;
--    b) suppression de ces déclencheurs ;
--    c) remplacement du corps par une version NULL-SAFE (même intention :
--       un collaborateur appartient à l'entreprise de son patron) ;
--    d) recréation à l'identique des déclencheurs sauvegardés.
--  Aucun autre comportement n'est modifié.

do $$
declare
  r record;
begin
  create temp table if not exists _biashara_triggers_sauves (def text);

  for r in
    select t.tgname, pg_get_triggerdef(t.oid) as def
      from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where p.proname = 'trg_utilisateurs_maj_collaborateurs'
       and not t.tgisinternal
  loop
    insert into _biashara_triggers_sauves values (r.def);
    execute format('drop trigger if exists %I on public.utilisateurs', r.tgname);
  end loop;
end $$;

-- Remplacement du corps — UNIQUEMENT si la fonction existe déjà, pour ne pas
-- créer de fonction orpheline sur une base qui ne l'a jamais eue.
do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'trg_utilisateurs_maj_collaborateurs'
  ) then
    execute $fonction$
      create or replace function public.trg_utilisateurs_maj_collaborateurs()
      returns trigger
      language plpgsql
      security definer
      set search_path = public
      as $corps$
      declare
        v_ent uuid;
      begin
        -- Aucun patron (le propriétaire lui-même) : rien à réaligner.
        if new.parent_id is null then
          return new;
        end if;

        select u.entreprise_id into v_ent
          from public.utilisateurs u
         where u.id = new.parent_id;

        -- On ne corrige que le vide ou l'identifiant du patron : une
        -- entreprise volontairement différente est respectée.
        if v_ent is not null
           and (new.entreprise_id is null or new.entreprise_id = new.parent_id) then
          new.entreprise_id := v_ent;
        end if;

        if new.espace_actif_id is null
           and exists (select 1 from public.espaces s where s.id = new.parent_id) then
          new.espace_actif_id := new.parent_id;
        end if;

        return new;
      end;
      $corps$;
    $fonction$;
  end if;
end $$;

-- Recréation des déclencheurs sauvegardés (ils pointent désormais vers le
-- corps sécurisé : même nom, mêmes événements, même timing).
do $$
declare
  d text;
begin
  if to_regclass('pg_temp._biashara_triggers_sauves') is not null then
    for d in select def from _biashara_triggers_sauves loop
      execute d;
    end loop;
    drop table if exists _biashara_triggers_sauves;
  end if;
end $$;

-- Vue d'ensemble : tous les déclencheurs qui restent sur `public.utilisateurs`.
-- Si un autre plantait de la même façon, il apparaîtrait ici.
select 'DÉCLENCHEURS UTILISATEURS' as alerte,
       t.tgname,
       p.proname as fonction,
       case when t.tgtype & 2 > 0 then 'BEFORE' else 'AFTER' end as moment,
       case
         when t.tgtype & 4 > 0  then 'INSERT '
         else ''
       end ||
       case when t.tgtype & 16 > 0 then 'UPDATE ' else '' end ||
       case when t.tgtype & 8 > 0  then 'DELETE' else '' end as evenements
  from pg_trigger t
  join pg_proc p on p.oid = t.tgfoid
 where t.tgrelid = 'public.utilisateurs'::regclass
   and not t.tgisinternal
 order by t.tgname;


-- ============================================================================
--  1. CONTRÔLE AVANT
-- ============================================================================

select 'AVANT' as moment,
       count(*) filter (
         where c.parent_id is not null
           and p.entreprise_id is not null
           and c.entreprise_id is distinct from p.entreprise_id
       ) as collaborateurs_mal_rattaches,
       count(*) filter (where c.parent_id is not null) as collaborateurs_total
  from public.utilisateurs c
  left join public.utilisateurs p on p.id = c.parent_id;


-- ============================================================================
--  2. CORRECTION DE L'EXISTANT
-- ============================================================================

update public.utilisateurs c
   set entreprise_id = p.entreprise_id
  from public.utilisateurs p
 where c.parent_id = p.id
   and p.entreprise_id is not null
   and c.entreprise_id is distinct from p.entreprise_id;


-- ============================================================================
--  3. LA RÈGLE POUR L'AVENIR
-- ============================================================================

create or replace function public.utilisateurs_rattacher_entreprise()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid;
begin
  -- Le propriétaire lui-même (pas de patron) n'est jamais modifié ici :
  -- c'est `rpc_entreprise_creer` qui fixe son entreprise.
  if new.parent_id is null then
    return new;
  end if;

  select u.entreprise_id into v_ent
    from public.utilisateurs u
   where u.id = new.parent_id;

  if v_ent is null then
    return new;
  end if;

  -- On ne réaligne que les valeurs vides ou manifestement fausses
  -- (= identifiant du patron). Une entreprise différente est respectée.
  if new.entreprise_id is null or new.entreprise_id = new.parent_id then
    new.entreprise_id := v_ent;
  end if;

  -- Espace de travail par défaut : l'espace du patron, s'il existe.
  if new.espace_actif_id is null
     and exists (select 1 from public.espaces s where s.id = new.parent_id) then
    new.espace_actif_id := new.parent_id;
  end if;

  return new;
end;
$$;

comment on function public.utilisateurs_rattacher_entreprise() is
  'Un collaborateur appartient à l''entreprise de son patron : entreprise_id réaligné automatiquement (jamais une entreprise volontairement différente).';

drop trigger if exists trg_utilisateurs_rattacher_entreprise
  on public.utilisateurs;

create trigger trg_utilisateurs_rattacher_entreprise
  before insert or update of parent_id, entreprise_id
  on public.utilisateurs
  for each row
  execute function public.utilisateurs_rattacher_entreprise();


-- ============================================================================
--  4. CONTRÔLE APRÈS
-- ============================================================================

select 'APRÈS' as moment,
       count(*) filter (
         where c.parent_id is not null
           and p.entreprise_id is not null
           and c.entreprise_id is distinct from p.entreprise_id
       ) as collaborateurs_mal_rattaches,
       count(*) filter (
         where c.parent_id is not null and c.entreprise_id is null
       ) as collaborateurs_sans_entreprise,
       count(*) filter (where c.parent_id is not null) as collaborateurs_total,
       exists (
         select 1 from pg_trigger t
          where t.tgname = 'trg_utilisateurs_rattacher_entreprise'
       ) as regle_active
  from public.utilisateurs c
  left join public.utilisateurs p on p.id = c.parent_id;

-- Détail des comptes rattachés : nom, patron, entreprise réelle.
select coalesce(p.nom, '(patron inconnu)') as patron,
       coalesce(c.nom, '') || ' ' || coalesce(c.prenom, '') as collaborateur,
       c.email,
       coalesce(c.new_role::text, c.role) as role,
       coalesce(e.nom, '(aucune)') as entreprise,
       c.entreprise_id = coalesce(p.entreprise_id, c.entreprise_id)
         as entreprise_correcte
  from public.utilisateurs c
  left join public.utilisateurs p on p.id = c.parent_id
  left join public.entreprises e on e.id = c.entreprise_id
 where c.parent_id is not null
 order by p.nom nulls last, c.nom;
