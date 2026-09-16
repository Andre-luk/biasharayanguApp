-- ============================================================================
--  biashara_yangu — MODULE 2 : ACTIVITÉS & GROUPES TARIFAIRES
--  Script idempotent : peut être exécuté plusieurs fois sans effet de bord.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  PRÉREQUIS
--    Exécuter d'abord les scripts du Module 1 :
--      20260916000000_module1_entreprises.sql
--      20260916000001_module1_paiements_et_rattachement.sql
--    (la LECTURE des référentiels y est déjà autorisée aux utilisateurs
--    connectés ; ce script ajoute l'ÉCRITURE).
--
--  CE QUE FAIT CE SCRIPT
--    1. Policies d'écriture réservées aux admins (activités / groupes)
--    2. Index de performance + unicité insensible à la casse
--    3. Garde-fous en base : interdiction de supprimer un élément utilisé
--    4. Vérification finale
--
--  ⚠️ AUCUNE table ni colonne n'est créée : le schéma existant est utilisé
--     tel quel (`public.activites` et `public.groupes_tarifaires`).
-- ============================================================================


-- ============================================================================
--  1. POLICIES D'ÉCRITURE RÉSERVÉES AUX ADMINS
-- ============================================================================
--  Même convention que le Module 1 : un admin est un utilisateur dont
--  `public.utilisateurs.role = 'admin'`.
--
--  Rappel : une policy n'a d'effet que si la RLS est active sur la table.
--  Si elle ne l'est pas, rien ne change — voir la section 1 ter.

drop policy if exists "activites_ecriture_admin" on public.activites;
create policy "activites_ecriture_admin" on public.activites
  for all to authenticated
  using (
    exists (
      select 1 from public.utilisateurs u
      where u.id = auth.uid() and u.role = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.utilisateurs u
      where u.id = auth.uid() and u.role = 'admin'
    )
  );

drop policy if exists "groupes_ecriture_admin" on public.groupes_tarifaires;
create policy "groupes_ecriture_admin" on public.groupes_tarifaires
  for all to authenticated
  using (
    exists (
      select 1 from public.utilisateurs u
      where u.id = auth.uid() and u.role = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.utilisateurs u
      where u.id = auth.uid() and u.role = 'admin'
    )
  );


-- ============================================================================
--  1 ter. (OPTIONNEL) ACTIVER LA RLS — À NE FAIRE QUE SI NÉCESSAIRE
-- ============================================================================
--  Décommentez UNIQUEMENT si ces tables n'ont PAS la RLS active et que vous
--  souhaitez la protection qu'apportent les policies ci-dessus.
--  ⚠️ Activer la RLS sans policy correcte verrouille l'accès aux données.
--
-- alter table public.activites            enable row level security;
-- alter table public.groupes_tarifaires   enable row level security;


-- ============================================================================
--  2. INDEX DE PERFORMANCE ET UNICITÉ
-- ============================================================================

-- Comptage des entreprises par activité / par groupe (écrans du Module 2).
create index if not exists idx_entreprises_activite
  on public.entreprises (activite_id);
create index if not exists idx_entreprises_groupe_tarifaire
  on public.entreprises (groupe_tarifaire_id);

-- Deux activités ne doivent pas porter le même nom, même à la casse ou aux
-- espaces près (« Boulangerie » = « boulangerie  »).
--
-- Si des doublons existent déjà, l'index n'est PAS créé et un avertissement
-- est affiché : les données existantes ne sont jamais modifiées par ce script.
-- L'application vérifie de son côté et affiche l'erreur à l'utilisateur.
do $$
begin
  create unique index if not exists uq_activites_nom_normalise
    on public.activites (lower(btrim(nom)));
exception
  when others then
    raise notice 'Index uq_activites_nom_normalise non créé (doublons existants ?) : %',
      sqlerrm;
end $$;


-- ============================================================================
--  3. GARDE-FOUS : PAS DE SUPPRESSION D'UN ÉLÉMENT ENCORE UTILISÉ
-- ============================================================================
--  L'application vérifie déjà l'utilisation avant de proposer une suppression
--  (message précis avec le nombre d'entreprises concernées). Ces triggers
--  garantissent la règle quoi qu'il arrive : suppression depuis le Dashboard
--  Supabase, ou modification concurrente entre la vérification et la
--  suppression.

-- 3.1 Un groupe tarifaire utilisé par une entreprise ne peut pas être supprimé.
create or replace function public.empecher_suppression_groupe_utilise()
returns trigger
language plpgsql
as $$
begin
  if exists (
    select 1 from public.entreprises e
    where e.groupe_tarifaire_id = old.id
  ) then
    raise exception 'GROUPE_TARIFAIRE_UTILISE';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_groupes_suppression_protegee
  on public.groupes_tarifaires;

create trigger trg_groupes_suppression_protegee
  before delete on public.groupes_tarifaires
  for each row
  execute function public.empecher_suppression_groupe_utilise();

-- 3.2 Une activité utilisée (par des entreprises ou des groupes) non plus.
create or replace function public.empecher_suppression_activite_utilisee()
returns trigger
language plpgsql
as $$
begin
  if exists (
    select 1 from public.entreprises e
    where e.activite_id = old.id
  ) then
    raise exception 'ACTIVITE_UTILISEE';
  end if;

  if exists (
    select 1 from public.groupes_tarifaires g
    where g.activite_id = old.id
  ) then
    raise exception 'ACTIVITE_UTILISEE';
  end if;

  return old;
end;
$$;

drop trigger if exists trg_activites_suppression_protegee
  on public.activites;

create trigger trg_activites_suppression_protegee
  before delete on public.activites
  for each row
  execute function public.empecher_suppression_activite_utilisee();


-- ============================================================================
--  4. VÉRIFICATION
-- ============================================================================

select
  (select count(*) from public.activites)           as nb_activites,
  (select count(*) from public.groupes_tarifaires)  as nb_groupes_tarifaires,
  (select count(*) from public.entreprises)         as nb_entreprises;

-- Doit renvoyer la policy de lecture (Module 1) + celle d'écriture (Module 2).
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename in ('activites', 'groupes_tarifaires')
 order by tablename, policyname;

-- Doit renvoyer les deux triggers de protection.
select tgname
  from pg_trigger
 where not tgisinternal
   and tgname in ('trg_activites_suppression_protegee',
                  'trg_groupes_suppression_protegee')
 order by tgname;
