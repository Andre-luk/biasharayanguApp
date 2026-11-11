-- ============================================================================
--  biashara_yangu — MIGRATION 0139 : « JE NE VOIS AUCUN UTILISATEUR »
--
--  SYMPTÔME (signalé)
--    Le compte est bien créé (« utilisateur créé »), mais la page
--    SUPER ADMIN → UTILISATEURS n'affiche PLUS PERSONNE — pas même le compte
--    qui vient d'être créé, ni les anciens.
--
--  POURQUOI C'EST TROMPEUR
--    L'écran lit `public.utilisateurs` avec `select *`. Deux situations
--    produisent la MÊME chose à l'écran (une liste vide) :
--      1. la lecture échoue (RLS, colonne illisible) → 0 ligne renvoyée ;
--      2. les fiches existent mais `new_role` est NULL pour tout le monde →
--         plus aucun rôle de plateforme reconnu → plus rien n'est autorisé.
--    Une liste vide n'est donc PAS la preuve qu'il n'y a plus d'utilisateurs.
--
--  CE QUE FAIT CETTE MIGRATION
--    A. DIAGNOSTIC (lignes affichées) : nombre de fiches, nombre de comptes
--       Auth, fiches SANS `new_role`, policies présentes sur `utilisateurs`,
--       et la liste des comptes de la plateforme.
--    B. RÉPARATION :
--       1. recrée les fiches manquantes des comptes Auth (comme 0138) ;
--       2. remplit `new_role` là où il est NULL, à partir de l'ancien `role`
--          (vendor → PROPRIETAIRE, collaborator → VENDEUR, admin →
--          SUPER_ADMIN) — SANS jamais modifier un rôle déjà défini ;
--       3. (re)pose des policies de LECTURE / ÉCRITURE explicites :
--            • la plateforme voit et modifie tout ;
--            • chacun voit sa propre fiche, celles de ses collaborateurs et
--              celles de son entreprise ;
--            • un patron modifie ses collaborateurs.
--    C. CONTRÔLE : plus aucune fiche sans rôle, et au moins une policy de
--       lecture permissive.
--
--  ⚠️ IDEMPOTENT — ne supprime AUCUNE donnée, ne change aucun rôle existant.
--  OÙ L'EXÉCUTER : Supabase Dashboard → SQL Editor → coller → Run.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  A. DIAGNOSTIC AVANT (lecture seule)
-- ============================================================================

-- A.1 Combien de fiches, combien de comptes Auth ?
select 'ÉTAT DES COMPTES' as controle,
       (select count(*) from public.utilisateurs)                as fiches_utilisateurs,
       (select count(*) from auth.users)                         as comptes_auth,
       (select count(*) from public.utilisateurs where new_role is null)
                                                                 as fiches_sans_role,
       (select count(*) from public.utilisateurs where valide = 1)
                                                                 as fiches_actives;

-- A.2 Les comptes de la plateforme (ceux qui DOIVENT voir la liste).
select 'COMPTES DE LA PLATEFORME' as controle,
       email, role, new_role::text as new_role, valide
  from public.utilisateurs
 where new_role::text in ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES',
                          'FINANCE_LAPERLE', 'SUPPORT')
    or role in ('admin', 'expert')
 order by email;

-- A.3 Policies (RLS) existantes sur `utilisateurs` : c'est elles qui décident
--     des lignes visibles. Une policy est « permissive » ou « restrictive ».
select 'POLICIES SUR public.utilisateurs' as controle,
       policyname, cmd, permissive, roles::text as roles
  from pg_policies
 where schemaname = 'public' and tablename = 'utilisateurs'
 order by permissive desc, cmd, policyname;


-- ============================================================================
--  B. RÉPARATION
-- ============================================================================

-- B.1 Fiches manquantes des comptes Auth (aucune suppression, aucune fusion).
do $$
declare
  v_res jsonb;
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where p.proname = 'reparer_profils_auth' and n.nspname = 'public') then
    v_res := public.reparer_profils_auth();
    raise notice 'Rattrapage : % fiche(s) recréée(s), % compte(s) encore sans fiche.',
      v_res->>'fiches_creees', v_res->>'comptes_sans_fiche_restants';
  end if;
end $$;

-- B.2 `new_role` vide alors que l'ancien rôle est connu ----------------------
--     ⚠️ On ne touche JAMAIS à un rôle déjà défini : c'est ce qui garantit
--        qu'aucun droit n'est modifié par cette migration.
update public.utilisateurs u
   set new_role = public.role_enum(public.role_herite(u.role))
 where u.new_role is null
   and u.role is not null
   and public.role_enum(public.role_herite(u.role)) is not null;

-- B.3 Policies de lecture et d'écriture --------------------------------------
--     Les policies « restrictives » du module 47/63 restent en place : elles
--     ne font que BORNER les agents terrain. Ici on (re)pose les policies
--     PERMISSIVES qui doivent exister pour que la plateforme lise sa liste.
alter table public.utilisateurs enable row level security;

drop policy if exists zz_lecture_utilisateurs on public.utilisateurs;
create policy zz_lecture_utilisateurs on public.utilisateurs
  for select to authenticated
  using (
    -- 1) La plateforme voit tout (c'est son écran d'administration).
    public.est_plateforme()
    -- 2) Chacun voit sa propre fiche.
    or id::text = auth.uid()::text
    -- 3) Un patron voit ses collaborateurs.
    or parent_id::text = auth.uid()::text
    -- 4) Les membres d'une même entreprise (comparaison tolérante aux types
    --    hérités : certaines bases ont encore `entreprise_id` en texte).
    or entreprise_id::text = auth.uid()::text
  );

drop policy if exists zz_maj_utilisateurs on public.utilisateurs;
create policy zz_maj_utilisateurs on public.utilisateurs
  for update to authenticated
  using (
    public.est_plateforme()
    or parent_id::text = auth.uid()::text
    or id::text = auth.uid()::text
  )
  with check (
    public.est_plateforme()
    or parent_id::text = auth.uid()::text
    or id::text = auth.uid()::text
  );

drop policy if exists zz_insertion_utilisateurs on public.utilisateurs;
create policy zz_insertion_utilisateurs on public.utilisateurs
  for insert to authenticated
  with check (
    id::text = auth.uid()::text
    or public.est_plateforme()
    or parent_id::text = auth.uid()::text
  );


-- ============================================================================
--  C. CONTRÔLE APRÈS
-- ============================================================================

select 'APRÈS RÉPARATION' as controle,
       (select count(*) from public.utilisateurs) as fiches_utilisateurs,
       (select count(*) from public.utilisateurs where new_role is null)
         as fiches_sans_role,
       (select count(*) from public.utilisateurs
         where new_role::text in ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES',
                                  'FINANCE_LAPERLE', 'SUPPORT'))
         as comptes_plateforme,
       (select count(*) from auth.users a
          left join public.utilisateurs x on x.id = a.id
         where x.id is null) as comptes_sans_fiche;

select 'POLICIES PERMISSIVES DE LECTURE' as controle,
       count(*) as nb
  from pg_policies
 where schemaname = 'public'
   and tablename = 'utilisateurs'
   and permissive = 'PERMISSIVE'
   and cmd in ('SELECT', 'ALL');
