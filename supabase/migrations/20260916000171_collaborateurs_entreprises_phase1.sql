-- ============================================================================
--  biashara_yangu — MIGRATION 0171 : COLLABORATEURS MULTI-ENTREPRISES (phase 1)
--
--  OBJECTIF MÉTIER (mission §3)
--    Un même utilisateur doit pouvoir travailler dans PLUSIEURS entreprises
--    du même patron, avec un rôle et une activation DIFFÉRENTS selon
--    l'entreprise. Le modèle actuel (`utilisateurs.entreprise_id` +
--    `new_role`, valeurs uniques) ne le permet pas.
--
--  CETTE PHASE EST VOLONTAIREMENT ADDITIVE
--    • Crée la table de rattachement et recopie l'existant.
--    • AUCUNE fonction existante ne la lit encore : zéro régression.
--    • Les phases suivantes (lecture, permissions, gestion) viendront après
--      validation des décisions listées dans
--      docs/module37_collaborateurs_multi_entreprises.md.
--
--  ⚠️ Aucune donnée modifiée dans `utilisateurs`. Idempotent.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- ---------------------------------------------------------------------------
-- 1. TABLE DE RATTACHEMENT
-- ---------------------------------------------------------------------------

create table if not exists public.collaborateurs_entreprises (
  id             uuid primary key default gen_random_uuid(),
  utilisateur_id uuid not null references public.utilisateurs(id) on delete cascade,
  entreprise_id  uuid not null references public.entreprises(id) on delete cascade,
  role           public.role_utilisateur_enum not null,
  actif          boolean not null default true,
  cree_le        timestamptz not null default now(),
  constraint collaborateurs_entreprises_unique
    unique (utilisateur_id, entreprise_id)
);

comment on table public.collaborateurs_entreprises is
  'Module 37 (0171) — rattachements d''un utilisateur aux entreprises : rôle et activation PROPRES à chaque entreprise. `utilisateurs.entreprise_id`/`new_role` restent la ligne principale (compatibilité).';
comment on column public.collaborateurs_entreprises.actif is
  'Activation DANS CETTE ENTREPRISE uniquement (ne touche pas aux autres rattachements).';

create index if not exists idx_collab_ent_entreprise
  on public.collaborateurs_entreprises (entreprise_id, actif);
create index if not exists idx_collab_ent_utilisateur
  on public.collaborateurs_entreprises (utilisateur_id, actif);

-- ---------------------------------------------------------------------------
-- 2. REPRISE DE L'EXISTANT (aucun utilisateur perdu)
-- ---------------------------------------------------------------------------
--  Chaque utilisateur rattaché à une entreprise reçoit SON rattachement,
--  avec son rôle actuel et l'état de validité de son compte.
--  `ON CONFLICT DO NOTHING` rend la reprise rejouable sans doublon.

insert into public.collaborateurs_entreprises (
  utilisateur_id, entreprise_id, role, actif
)
select u.id,
       u.entreprise_id,
       coalesce(u.new_role, public.role_enum('VENDEUR')),
       coalesce(u.valide, 1) = 1
  from public.utilisateurs u
 where u.entreprise_id is not null
on conflict (utilisateur_id, entreprise_id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. RLS — LECTURE SEULE CÔTÉ CLIENT
-- ---------------------------------------------------------------------------
--  • l'utilisateur voit ses propres rattachements ;
--  • le patron voit ceux de SES entreprises ;
--  • la plateforme voit tout.
--  Aucune policy d'écriture : la gestion passera par des RPC (phase 4).

alter table public.collaborateurs_entreprises enable row level security;

drop policy if exists collab_ent_lecture on public.collaborateurs_entreprises;
create policy collab_ent_lecture on public.collaborateurs_entreprises
  for select
  using (
    utilisateur_id = auth.uid()
    or public.est_plateforme()
    or exists (
      select 1
        from public.entreprises e
       where e.id = collaborateurs_entreprises.entreprise_id
         and e.owner_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 4. VERDICT
-- ---------------------------------------------------------------------------

select 'Module 37 phase 1 — rattachements : ' ||
       (select count(*) from public.collaborateurs_entreprises) ||
       ' | utilisateurs couverts : ' ||
       (select count(distinct utilisateur_id) from public.collaborateurs_entreprises) ||
       ' | entreprises couvertes : ' ||
       (select count(distinct entreprise_id) from public.collaborateurs_entreprises) ||
       ' | à reprendre : ' ||
       (select count(*)
          from public.utilisateurs u
         where u.entreprise_id is not null
           and not exists (
             select 1 from public.collaborateurs_entreprises c
              where c.utilisateur_id = u.id
                and c.entreprise_id = u.entreprise_id)) ||
       ' | table : ' ||
       case when to_regclass('public.collaborateurs_entreprises') is not null
            then 'OK' else 'ABSENTE' end as verdict;
