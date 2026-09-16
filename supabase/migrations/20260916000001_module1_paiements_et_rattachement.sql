-- ============================================================================
--  biashara_yangu — MODULE 1 (suite)
--  HISTORIQUE DES PAIEMENTS + RATTACHEMENT DES UTILISATEURS AUX ENTREPRISES
--
--  Script idempotent : peut être exécuté plusieurs fois sans effet de bord.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  PRÉREQUIS
--    Exécuter d'abord 20260916000000_module1_entreprises.sql
--
--  ⚠️ Ce fichier CRÉE deux tables. C'est une décision explicite de votre part
--     (historique des encaissements + rattachement utilisateurs/entreprises).
-- ============================================================================


-- ============================================================================
--  1. HISTORIQUE DES ENCAISSEMENTS
-- ============================================================================
--  Sans cette table, seul un cumul (`entreprises.montant_deja_paye`) est
--  conservé : impossible de retrouver un paiement précis, sa date ou son auteur.

create table if not exists public.paiements_abonnement (
  id                 uuid primary key default gen_random_uuid(),
  entreprise_id      uuid not null
                     references public.entreprises (id) on delete cascade,
  montant            numeric not null,
  -- Cumul et solde APRÈS l'encaissement : permet de reconstituer l'historique
  -- sans dépendre des valeurs actuelles de l'entreprise.
  total_apres        numeric,
  solde_apres        numeric,
  -- Nombre de jours ajoutés à `date_expiration` (0 si pas de prolongation).
  prolongation_jours integer not null default 0,
  -- Auteur de l'encaissement (facultatif : un utilisateur supprimé laisse null).
  enregistre_par     uuid,
  created_at         timestamptz not null default now()
);

create index if not exists idx_paiements_abonnement_entreprise
  on public.paiements_abonnement (entreprise_id, created_at desc);

-- ============================================================================
--  2. RATTACHEMENT DES UTILISATEURS AUX ENTREPRISES
-- ============================================================================
--  Un entreprise peut avoir plusieurs utilisateurs, et un utilisateur peut
--  intervenir sur plusieurs entreprises : d'où une table de liaison.
--
--  ⚠️ La colonne `user_id` n'a volontairement PAS de clé étrangère : je ne
--     connais pas la structure exacte de `public.utilisateurs`. Pour l'ajouter
--     (recommandé si `utilisateurs.id` est bien une clé primaire), décommentez
--     la contrainte ci-dessous et relancez le script :
--
-- alter table public.entreprise_utilisateurs
--   add constraint fk_entreprise_utilisateurs_user
--   foreign key (user_id) references public.utilisateurs (id) on delete cascade;

create table if not exists public.entreprise_utilisateurs (
  entreprise_id uuid not null
                references public.entreprises (id) on delete cascade,
  user_id       uuid not null,
  created_at    timestamptz not null default now(),
  primary key (entreprise_id, user_id)
);

create index if not exists idx_entreprise_utilisateurs_user
  on public.entreprise_utilisateurs (user_id);


-- ============================================================================
--  3. ENCAISSEMENT D'UN PAIEMENT (nouvelle version)
-- ============================================================================
--  Remplace la version à 2 arguments : la nouvelle gère en plus
--    - l'historisation dans paiements_abonnement,
--    - la prolongation de l'abonnement (p_prolonger).
--
--  Met à jour UNIQUEMENT montant_deja_paye et solde_restant, et — si
--  p_prolonger vaut true — date_expiration, date_activation et statut.
--
--  Le verrou `for update` rend l'opération atomique : deux encaissements
--  simultanés ne peuvent pas se perdre l'un l'autre.

-- L'ancienne signature (2 arguments) doit être supprimée : sinon, à cause de la
-- valeur par défaut de `p_prolonger`, l'appel à 2 arguments deviendrait ambigu.
drop function if exists public.rpc_enregistrer_paiement(uuid, numeric);

create or replace function public.rpc_enregistrer_paiement(
  p_entreprise_id uuid,
  p_montant       numeric,
  p_prolonger     boolean default false
)
returns public.entreprises
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entreprise public.entreprises;
  v_paye       numeric;
  v_total      numeric;
  v_solde      numeric;
  v_duree      integer := 0;
  v_base       timestamptz;
begin
  -- Réservé aux administrateurs.
  if not exists (
    select 1 from public.utilisateurs u
    where u.id = auth.uid() and u.role = 'admin'
  ) then
    raise exception 'ACCES_REFUSE';
  end if;

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE';
  end if;

  select * into v_entreprise
  from public.entreprises
  where id = p_entreprise_id
  for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  v_paye  := coalesce(v_entreprise.montant_deja_paye, 0);
  v_total := coalesce(v_entreprise.montant_total_du, 0);
  v_solde := coalesce(v_entreprise.solde_restant, greatest(v_total - v_paye, 0));

  if p_montant > v_solde then
    raise exception 'MONTANT_SUPERIEUR';
  end if;

  -- 3.1 Montants
  update public.entreprises
     set montant_deja_paye = v_paye + p_montant,
         solde_restant      = greatest(v_solde - p_montant, 0),
         updated_at         = now()
   where id = p_entreprise_id;

  -- 3.2 Prolongation éventuelle
  if p_prolonger then
    select coalesce(g.duree_abonnement_jours, 0) into v_duree
    from public.groupes_tarifaires g
    where g.id = v_entreprise.groupe_tarifaire_id;

    v_duree := coalesce(v_duree, 0);

    -- On repart de la date d'expiration si elle est encore future, de
    -- maintenant sinon : un abonnement échu ne cumule pas de retard.
    v_base := greatest(coalesce(v_entreprise.date_expiration, now()), now());

    update public.entreprises
       set date_expiration = v_base + make_interval(days => v_duree),
           date_activation = coalesce(date_activation, now()),
           statut          = 'ACTIF',
           updated_at      = now()
     where id = p_entreprise_id;
  end if;

  select * into v_entreprise from public.entreprises where id = p_entreprise_id;

  -- 3.3 Historique
  insert into public.paiements_abonnement (
    entreprise_id,
    montant,
    total_apres,
    solde_apres,
    prolongation_jours,
    enregistre_par
  ) values (
    p_entreprise_id,
    p_montant,
    v_entreprise.montant_deja_paye,
    v_entreprise.solde_restant,
    case when p_prolonger then v_duree else 0 end,
    auth.uid()
  );

  return v_entreprise;
end;
$$;

grant execute on function public.rpc_enregistrer_paiement(uuid, numeric, boolean)
  to authenticated;


-- ============================================================================
--  4. LECTURE DES ENTREPRISES D'UN UTILISATEUR
-- ============================================================================
--  Utilisée à la connexion pour savoir si l'accès doit être bloqué.
--  En `security definer` : un utilisateur n'a pas forcément le droit de lire
--  `entreprises` directement, et il n'a pas besoin de le pouvoir.

create or replace function public.rpc_entreprises_de_utilisateur(
  p_user_id uuid default null
)
returns table (
  entreprise_id   uuid,
  nom             text,
  statut          text,
  date_expiration timestamptz,
  solde_restant   numeric
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_cible uuid;
begin
  if auth.uid() is null then
    raise exception 'ACCES_REFUSE';
  end if;

  v_cible := coalesce(p_user_id, auth.uid());

  -- Consulter les entreprises d'un autre utilisateur est réservé aux admins.
  if v_cible <> auth.uid() then
    if not exists (
      select 1 from public.utilisateurs u
      where u.id = auth.uid() and u.role = 'admin'
    ) then
      raise exception 'ACCES_REFUSE';
    end if;
  end if;

  return query
    select e.id,
           e.nom,
           e.statut::text,
           e.date_expiration,
           e.solde_restant
      from public.entreprises e
      join public.entreprise_utilisateurs eu on eu.entreprise_id = e.id
     where eu.user_id = v_cible;
end;
$$;

grant execute on function public.rpc_entreprises_de_utilisateur(uuid)
  to authenticated;


-- ============================================================================
--  5. POLICIES DES NOUVELLES TABLES
-- ============================================================================
--  Comme dans le premier script : aucune n'a d'effet tant que la RLS n'est pas
--  activée sur la table concernée.

drop policy if exists "paiements_lecture" on public.paiements_abonnement;
create policy "paiements_lecture" on public.paiements_abonnement
  for select to authenticated using (true);

drop policy if exists "paiements_insertion_admin" on public.paiements_abonnement;
create policy "paiements_insertion_admin" on public.paiements_abonnement
  for insert to authenticated
  with check (
    exists (
      select 1 from public.utilisateurs u
      where u.id = auth.uid() and u.role = 'admin'
    )
  );

drop policy if exists "entreprise_utilisateurs_lecture"
  on public.entreprise_utilisateurs;
create policy "entreprise_utilisateurs_lecture"
  on public.entreprise_utilisateurs
  for select to authenticated using (true);

drop policy if exists "entreprise_utilisateurs_admin"
  on public.entreprise_utilisateurs;
create policy "entreprise_utilisateurs_admin"
  on public.entreprise_utilisateurs
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
--  6. VÉRIFICATION
-- ============================================================================

select
  to_regclass('public.paiements_abonnement')      as table_paiements,
  to_regclass('public.entreprise_utilisateurs')   as table_rattachement;

select proname, pronargs
  from pg_proc
 where proname in ('rpc_enregistrer_paiement', 'rpc_entreprises_de_utilisateur')
 order by proname;
